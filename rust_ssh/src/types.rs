//! Type definitions for SSH library

use serde::{Deserialize, Serialize};

/// Authentication methods
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AuthMethod {
    Password(String),
    PrivateKey { key: String, passphrase: Option<String> },
    KeyboardInteractive,
}

/// SSH connection configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SshConfig {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub auth: AuthMethod,
    pub timeout_secs: u64,
    pub jump_host: Option<Box<SshConfig>>,
}

/// SSH connection wrapper
pub struct SshConnection {
    pub session: ssh2::Session,
    pub config: SshConfig,
    pub connected: bool,
}

impl SshConnection {
    pub fn new(session: ssh2::Session, config: SshConfig) -> Self {
        Self {
            session,
            config,
            connected: false,
        }
    }
}

/// Command execution result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommandResult {
    pub stdout: String,
    pub stderr: String,
    pub exit_code: Option<i32>,
}

/// SFTP file information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileInfo {
    pub name: String,
    pub size: u64,
    pub is_dir: bool,
    pub permissions: u32,
    pub modified: u64,
}

/// File transfer progress callback
pub type ProgressCallback = Box<dyn Fn(u64, u64) + Send + Sync>;

/// SSH session status
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum SessionStatus {
    Disconnected,
    Connecting,
    Connected,
    Error,
}

/// System type detection
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum SystemType {
    Linux,
    Windows,
    MacOS,
    BSD,
    Unknown,
}