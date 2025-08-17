//! SSH connection and session management

use crate::{SshConfig, SshConnection, SshError, SshResult, AuthMethod, CommandResult, SystemType};
use ssh2::{Session, Channel};
use std::io::prelude::*;
use std::net::{TcpStream, ToSocketAddrs};
use std::path::Path;
use std::time::Duration;

/// SSH client implementation
pub struct SshClient;

impl SshClient {
    /// Create a new SSH connection
    pub fn connect(config: SshConfig) -> SshResult<SshConnection> {
        let addr = format!("{}:{}", config.host, config.port);
        let tcp = TcpStream::connect_timeout(
            &addr.to_socket_addrs()?.next().ok_or_else(|| {
                SshError::ConnectionFailed("Invalid address".to_string())
            })?,
            Duration::from_secs(config.timeout_secs),
        )?;
        
        let mut session = Session::new()?;
        session.set_tcp_stream(tcp);
        session.handshake()?;
        
        // Authenticate
        Self::authenticate(&mut session, &config)?;
        
        let mut connection = SshConnection::new(session, config);
        connection.connected = true;
        
        Ok(connection)
    }
    
    /// Authenticate with the SSH server
    fn authenticate(session: &mut Session, config: &SshConfig) -> SshResult<()> {
        match &config.auth {
            AuthMethod::Password(password) => {
                session.userauth_password(&config.username, password)?;
            }
            AuthMethod::PrivateKey { key, passphrase } => {
                let key_path = Path::new(key);
                if key_path.exists() {
                    // Key file path
                    session.userauth_pubkey_file(
                        &config.username,
                        None,
                        key_path,
                        passphrase.as_deref(),
                    )?;
                } else {
                    // Key content - write to temp file
                    let temp_key = Self::write_temp_key(key)?;
                    session.userauth_pubkey_file(
                        &config.username,
                        None,
                        &temp_key,
                        passphrase.as_deref(),
                    )?;
                    std::fs::remove_file(temp_key).ok();
                }
            }
            AuthMethod::KeyboardInteractive => {
                // Basic keyboard-interactive authentication implementation
                // This attempts to use available authentication methods
                let methods = session.auth_methods(&config.username)?;
                if methods.contains("password") {
                    // If password auth is available, prompt for password
                    // For now, we return an error indicating UI interaction is needed
                    return Err(SshError::AuthenticationFailed(
                        "Keyboard-interactive authentication requires UI interaction".to_string(),
                    ));
                } else if methods.contains("publickey") {
                    // Try public key authentication if available
                    return Err(SshError::AuthenticationFailed(
                        "Keyboard-interactive fallback to publickey not implemented".to_string(),
                    ));
                } else {
                    return Err(SshError::AuthenticationFailed(
                        "No compatible authentication methods available".to_string(),
                    ));
                }
            }
        }
        
        if !session.authenticated() {
            return Err(SshError::AuthenticationFailed(
                "Authentication failed".to_string(),
            ));
        }
        
        Ok(())
    }
    
    /// Write private key to temporary file
    fn write_temp_key(key_content: &str) -> SshResult<std::path::PathBuf> {
        use std::io::Write;
        
        let temp_dir = std::env::temp_dir();
        let temp_file = temp_dir.join(format!("ssh_key_{}", uuid::Uuid::new_v4()));
        
        let mut file = std::fs::File::create(&temp_file)?;
        file.write_all(key_content.as_bytes())?;
        file.sync_all()?;
        
        // Set secure permissions (Unix only)
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = file.metadata()?.permissions();
            perms.set_mode(0o600);
            std::fs::set_permissions(&temp_file, perms)?;
        }
        
        Ok(temp_file)
    }
    
    /// Execute a command
    pub fn execute_command(
        connection: &mut SshConnection,
        command: &str,
    ) -> SshResult<CommandResult> {
        let mut channel = connection.session.channel_session()?;
        channel.exec(command)?;
        
        let mut stdout = String::new();
        let mut stderr = String::new();
        
        channel.read_to_string(&mut stdout)?;
        channel.stderr().read_to_string(&mut stderr)?;
        channel.wait_close()?;
        
        let exit_code = channel.exit_status().ok();
        
        Ok(CommandResult {
            stdout,
            stderr,
            exit_code,
        })
    }
    
    /// Execute a command with streaming output
    pub fn execute_command_streaming<F>(
        connection: &mut SshConnection,
        command: &str,
        mut callback: F,
    ) -> SshResult<CommandResult>
    where
        F: FnMut(&str) -> bool, // Return false to stop
    {
        let mut channel = connection.session.channel_session()?;
        channel.exec(command)?;
        
        let mut stdout = String::new();
        let mut stderr = String::new();
        let mut buffer = [0; 1024];
        
        loop {
            match channel.read(&mut buffer) {
                Ok(0) => break, // EOF
                Ok(n) => {
                    let data = String::from_utf8_lossy(&buffer[..n]);
                    stdout.push_str(&data);
                    if !callback(&data) {
                        break;
                    }
                }
                Err(e) => return Err(SshError::IoError(e.to_string())),
            }
        }
        
        channel.stderr().read_to_string(&mut stderr)?;
        channel.wait_close()?;
        
        let exit_code = channel.exit_status().ok();
        
        Ok(CommandResult {
            stdout,
            stderr,
            exit_code,
        })
    }
    
    /// Detect system type
    pub fn detect_system_type(connection: &mut SshConnection) -> SshResult<SystemType> {
        let result = Self::execute_command(connection, "uname -s")?;
        
        if result.exit_code != Some(0) {
            // Try Windows detection
            let windows_result = Self::execute_command(connection, "echo %OS%")?;
            if windows_result.stdout.to_lowercase().contains("windows") {
                return Ok(SystemType::Windows);
            }
            return Ok(SystemType::Unknown);
        }
        
        let os_name = result.stdout.trim().to_lowercase();
        match os_name.as_str() {
            "linux" => Ok(SystemType::Linux),
            "darwin" => Ok(SystemType::MacOS),
            "freebsd" | "openbsd" | "netbsd" => Ok(SystemType::BSD),
            _ => Ok(SystemType::Unknown),
        }
    }
    
    /// Create a shell session
    pub fn create_shell(connection: &mut SshConnection) -> SshResult<Channel> {
        let mut channel = connection.session.channel_session()?;
        channel.request_pty("xterm", None, None)?;
        channel.shell()?;
        Ok(channel)
    }
    
    /// Create port forwarding channel
    pub fn forward_local(
        connection: &mut SshConnection, 
        remote_host: &str, 
        remote_port: u16
    ) -> SshResult<Channel> {
        let channel = connection.session.channel_direct_tcpip(
            remote_host,
            remote_port,
            None,
        )?;
        Ok(channel)
    }

    /// Create reverse port forwarding
    pub fn forward_remote(
        connection: &mut SshConnection,
        remote_port: u16,
        local_host: &str,
        local_port: u16,
    ) -> SshResult<()> {
        connection.session.channel_forward_listen(
            remote_port,
            Some(local_host),
            Some(local_port as u32),
        )?;
        Ok(())
    }

    /// Close connection
    pub fn disconnect(connection: &mut SshConnection) -> SshResult<()> {
        if connection.connected {
            connection.session.disconnect(None, "", None)?;
            connection.connected = false;
        }
        Ok(())
    }
}

// Add uuid dependency - we'll need to add this to Cargo.toml
mod uuid {
    pub struct Uuid;
    impl Uuid {
        pub fn new_v4() -> String {
            use std::time::{SystemTime, UNIX_EPOCH};
            let timestamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            format!("{:x}", timestamp)
        }
    }
}