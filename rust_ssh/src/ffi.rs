//! FFI (Foreign Function Interface) bindings for Dart

use crate::{
    SshConfig, AuthMethod, SshClient, SftpClient, get_ssh_worker, SshCommand,
    SESSION_MANAGER, SshError, ErrorCode, FileInfo, SystemType
};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_uint, c_void};
use tokio::sync::oneshot;

/// C-compatible SSH configuration
#[repr(C)]
pub struct CSshConfig {
    pub host: *const c_char,
    pub port: c_uint,
    pub username: *const c_char,
    pub password: *const c_char,
    pub private_key: *const c_char,
    pub passphrase: *const c_char,
    pub timeout_secs: c_uint,
}

/// C-compatible command result
#[repr(C)]
pub struct CCommandResult {
    pub stdout: *mut c_char,
    pub stderr: *mut c_char,
    pub exit_code: c_int,
}

/// C-compatible file info
#[repr(C)]
pub struct CFileInfo {
    pub name: *mut c_char,
    pub size: u64,
    pub is_dir: c_int,
    pub permissions: c_uint,
    pub modified: u64,
}

/// C-compatible progress callback type
/// Parameters: transferred (u64), total (u64), user_data (*mut c_void)
pub type CProgressCallback = extern "C" fn(u64, u64, *mut c_void);

/// Global variable to store last error message
static mut LAST_ERROR: Option<String> = None;

/// Store error message for retrieval
fn set_last_error(error: String) {
    unsafe {
        LAST_ERROR = Some(error);
    }
}

/// Get last error message
#[no_mangle]
pub extern "C" fn ssh_get_last_error() -> *mut c_char {
    unsafe {
        if let Some(ref error) = LAST_ERROR {
            match CString::new(error.clone()) {
                Ok(c_string) => c_string.into_raw(),
                Err(_) => std::ptr::null_mut(),
            }
        } else {
            std::ptr::null_mut()
        }
    }
}

/// Create SSH connection
#[no_mangle]
pub extern "C" fn ssh_connect(config: *const CSshConfig) -> u64 {
    if config.is_null() {
        set_last_error("Config pointer is null".to_string());
        return 0;
    }
    
    let config = unsafe { &*config };
    
    let rust_config = match convert_c_config_to_rust(config) {
        Ok(config) => config,
        Err(e) => {
            set_last_error(format!("Config conversion failed: {}", e));
            return 0;
        }
    };
    
    match SshClient::connect(rust_config) {
        Ok(connection) => {
            let mut manager = SESSION_MANAGER.lock();
            manager.add_session(connection)
        }
        Err(e) => {
            set_last_error(format!("SSH connection failed: {}", e));
            0
        }
    }
}

/// Disconnect SSH session
#[no_mangle]
pub extern "C" fn ssh_disconnect(session_id: u64) -> c_int {
    let mut manager = SESSION_MANAGER.lock();
    match manager.remove_session(session_id) {
        Some(mut connection) => {
            match SshClient::disconnect(&mut connection) {
                Ok(_) => ErrorCode::Success as c_int,
                Err(e) => ErrorCode::from(&e) as c_int,
            }
        }
        None => ErrorCode::SessionNotFound as c_int,
    }
}

/// Execute command
#[no_mangle]
pub extern "C" fn ssh_execute_command(
    session_id: u64,
    command: *const c_char,
    result: *mut CCommandResult,
) -> c_int {
    if command.is_null() || result.is_null() {
        return ErrorCode::InvalidConfig as c_int;
    }
    
    let command_str = match unsafe { CStr::from_ptr(command) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };
    
    let mut manager = SESSION_MANAGER.lock();
    let connection = match manager.get_session_mut(session_id) {
        Some(conn) => conn,
        None => return ErrorCode::SessionNotFound as c_int,
    };
    
    match SshClient::execute_command(connection, command_str) {
        Ok(cmd_result) => {
            unsafe {
                (*result).stdout = CString::new(cmd_result.stdout)
                    .unwrap_or_default()
                    .into_raw();
                (*result).stderr = CString::new(cmd_result.stderr)
                    .unwrap_or_default()
                    .into_raw();
                (*result).exit_code = cmd_result.exit_code.unwrap_or(-1);
            }
            ErrorCode::Success as c_int
        }
        Err(e) => ErrorCode::from(&e) as c_int,
    }
}

/// Detect system type
#[no_mangle]
pub extern "C" fn ssh_detect_system_type(session_id: u64) -> c_int {
    let mut manager = SESSION_MANAGER.lock();
    let connection = match manager.get_session_mut(session_id) {
        Some(conn) => conn,
        None => return -1,
    };
    
    match SshClient::detect_system_type(connection) {
        Ok(system_type) => system_type as c_int,
        Err(_) => SystemType::Unknown as c_int,
    }
}

/// Get active session count
#[no_mangle]
pub extern "C" fn ssh_get_session_count() -> c_int {
    let manager = SESSION_MANAGER.lock();
    manager.session_count() as c_int
}

/// Create SFTP session
#[no_mangle]
pub extern "C" fn sftp_create(session_id: u64) -> c_int {
    let manager = SESSION_MANAGER.lock();
    let connection = match manager.get_session(session_id) {
        Some(conn) => conn,
        None => return ErrorCode::SessionNotFound as c_int,
    };
    
    match SftpClient::new(connection) {
        Ok(_) => ErrorCode::Success as c_int,
        Err(e) => ErrorCode::from(&e) as c_int,
    }
}

/// List directory
#[no_mangle]
pub extern "C" fn sftp_list_dir(
    session_id: u64,
    path: *const c_char,
    files: *mut *mut CFileInfo,
    count: *mut c_uint,
) -> c_int {
    if path.is_null() || files.is_null() || count.is_null() {
        return ErrorCode::InvalidConfig as c_int;
    }
    
    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };
    
    let manager = SESSION_MANAGER.lock();
    let connection = match manager.get_session(session_id) {
        Some(conn) => conn,
        None => return ErrorCode::SessionNotFound as c_int,
    };
    
    let sftp = match SftpClient::new(connection) {
        Ok(sftp) => sftp,
        Err(e) => return ErrorCode::from(&e) as c_int,
    };
    
    match SftpClient::list_dir(&sftp, path_str) {
        Ok(file_list) => {
            let c_files = convert_files_to_c(file_list);
            unsafe {
                *count = c_files.len() as c_uint;
                *files = c_files.as_ptr() as *mut CFileInfo;
                std::mem::forget(c_files); // Prevent deallocation
            }
            ErrorCode::Success as c_int
        }
        Err(e) => ErrorCode::from(&e) as c_int,
    }
}

/// Free memory allocated for strings
#[no_mangle]
pub extern "C" fn free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

/// Free memory allocated for command result
#[no_mangle]
pub extern "C" fn free_command_result(result: *mut CCommandResult) {
    if !result.is_null() {
        unsafe {
            free_string((*result).stdout);
            free_string((*result).stderr);
        }
    }
}

/// Convert C config to Rust config
fn convert_c_config_to_rust(config: &CSshConfig) -> Result<SshConfig, SshError> {
    let host = unsafe { CStr::from_ptr(config.host) }
        .to_str()
        .map_err(|_| SshError::InvalidConfig("Invalid host".to_string()))?
        .to_string();
    
    let username = unsafe { CStr::from_ptr(config.username) }
        .to_str()
        .map_err(|_| SshError::InvalidConfig("Invalid username".to_string()))?
        .to_string();
    
    let auth = if !config.password.is_null() {
        let password = unsafe { CStr::from_ptr(config.password) }
            .to_str()
            .map_err(|_| SshError::InvalidConfig("Invalid password".to_string()))?
            .to_string();
        AuthMethod::Password(password)
    } else if !config.private_key.is_null() {
        let key = unsafe { CStr::from_ptr(config.private_key) }
            .to_str()
            .map_err(|_| SshError::InvalidConfig("Invalid private key".to_string()))?
            .to_string();
        
        let passphrase = if !config.passphrase.is_null() {
            Some(unsafe { CStr::from_ptr(config.passphrase) }
                .to_str()
                .map_err(|_| SshError::InvalidConfig("Invalid passphrase".to_string()))?
                .to_string())
        } else {
            None
        };
        
        AuthMethod::PrivateKey { key, passphrase }
    } else {
        AuthMethod::KeyboardInteractive
    };
    
    Ok(SshConfig {
        host,
        port: config.port as u16,
        username,
        auth,
        timeout_secs: config.timeout_secs as u64,
        jump_host: None, // TODO: Implement jump host support
    })
}

/// Convert Rust files to C files
/// Create local port forwarding
#[no_mangle]
pub extern "C" fn ssh_forward_local(
    session_id: u64,
    remote_host: *const c_char,
    remote_port: u16,
) -> i32 {
    if remote_host.is_null() {
        return ErrorCode::InvalidConfig as i32;
    }

    let remote_host = unsafe {
        match CStr::from_ptr(remote_host).to_str() {
            Ok(s) => s,
            Err(_) => return ErrorCode::InvalidConfig as i32,
        }
    };

    let mut session_manager = SESSION_MANAGER.lock();
    if let Some(connection) = session_manager.get_session_mut(session_id) {
        match SshClient::forward_local(connection, remote_host, remote_port) {
            Ok(_) => ErrorCode::Success as i32,
            Err(_) => ErrorCode::Other as i32,
        }
    } else {
        ErrorCode::SessionNotFound as i32
    }
}

/// Create shell session
#[no_mangle]
pub extern "C" fn ssh_create_shell(session_id: u64) -> i32 {
    let mut session_manager = SESSION_MANAGER.lock();
    if let Some(connection) = session_manager.get_session_mut(session_id) {
        match SshClient::create_shell(connection) {
            Ok(_) => ErrorCode::Success as i32,
            Err(_) => ErrorCode::Other as i32,
        }
    } else {
        ErrorCode::SessionNotFound as i32
    }
}

/// Create reverse port forwarding
#[no_mangle]
pub extern "C" fn ssh_forward_remote(
    session_id: u64,
    remote_port: u16,
    local_host: *const c_char,
    local_port: u16,
) -> i32 {
    if local_host.is_null() {
        return ErrorCode::InvalidConfig as i32;
    }

    let local_host = unsafe {
        match CStr::from_ptr(local_host).to_str() {
            Ok(s) => s,
            Err(_) => return ErrorCode::InvalidConfig as i32,
        }
    };

    let mut session_manager = SESSION_MANAGER.lock();
    if let Some(connection) = session_manager.get_session_mut(session_id) {
        match SshClient::forward_remote(connection, remote_port, local_host, local_port) {
            Ok(_) => ErrorCode::Success as i32,
            Err(_) => ErrorCode::Other as i32,
        }
    } else {
        ErrorCode::SessionNotFound as i32
    }
}

/// Download file via SFTP
#[no_mangle]
pub extern "C" fn sftp_download_file(
    session_id: u64,
    remote_path: *const c_char,
    local_path: *const c_char,
) -> c_int {
    if remote_path.is_null() || local_path.is_null() {
        return ErrorCode::InvalidConfig as c_int;
    }

    let remote_path_str = match unsafe { CStr::from_ptr(remote_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };

    let local_path_str = match unsafe { CStr::from_ptr(local_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };

    let manager = SESSION_MANAGER.lock();
    let connection = match manager.get_session(session_id) {
        Some(conn) => conn,
        None => return ErrorCode::SessionNotFound as c_int,
    };

    let sftp = match SftpClient::new(connection) {
        Ok(sftp) => sftp,
        Err(e) => return ErrorCode::from(&e) as c_int,
    };

    match SftpClient::download_file(&sftp, remote_path_str, local_path_str, None) {
        Ok(_) => ErrorCode::Success as c_int,
        Err(e) => ErrorCode::from(&e) as c_int,
    }
}

/// Download file via SFTP with progress callback
#[no_mangle]
pub extern "C" fn sftp_download_file_with_progress(
    session_id: u64,
    remote_path: *const c_char,
    local_path: *const c_char,
    progress_callback: Option<CProgressCallback>,
    user_data: *mut c_void,
) -> c_int {
    if remote_path.is_null() || local_path.is_null() {
        return ErrorCode::InvalidConfig as c_int;
    }

    let remote_path_str = match unsafe { CStr::from_ptr(remote_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };

    let local_path_str = match unsafe { CStr::from_ptr(local_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };

    let manager = SESSION_MANAGER.lock();
    let connection = match manager.get_session(session_id) {
        Some(conn) => conn,
        None => return ErrorCode::SessionNotFound as c_int,
    };

    let sftp = match SftpClient::new(connection) {
        Ok(sftp) => sftp,
        Err(e) => return ErrorCode::from(&e) as c_int,
    };

    let callback = progress_callback.map(|cb| {
        let user_data_addr = user_data as usize;
        Box::new(move |transferred: u64, total: u64| {
            cb(transferred, total, user_data_addr as *mut c_void);
        }) as Box<dyn Fn(u64, u64) + Send + Sync>
    });

    match SftpClient::download_file(&sftp, remote_path_str, local_path_str, callback) {
        Ok(_) => ErrorCode::Success as c_int,
        Err(e) => ErrorCode::from(&e) as c_int,
    }
}

/// Upload file via SFTP
#[no_mangle]
pub extern "C" fn sftp_upload_file(
    session_id: u64,
    local_path: *const c_char,
    remote_path: *const c_char,
) -> c_int {
    if local_path.is_null() || remote_path.is_null() {
        return ErrorCode::InvalidConfig as c_int;
    }

    let local_path_str = match unsafe { CStr::from_ptr(local_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };

    let remote_path_str = match unsafe { CStr::from_ptr(remote_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };

    let manager = SESSION_MANAGER.lock();
    let connection = match manager.get_session(session_id) {
        Some(conn) => conn,
        None => return ErrorCode::SessionNotFound as c_int,
    };

    let sftp = match SftpClient::new(connection) {
        Ok(sftp) => sftp,
        Err(e) => return ErrorCode::from(&e) as c_int,
    };

    match SftpClient::upload_file(&sftp, local_path_str, remote_path_str, None) {
        Ok(_) => ErrorCode::Success as c_int,
        Err(e) => ErrorCode::from(&e) as c_int,
    }
}

/// Upload file via SFTP with progress callback
#[no_mangle]
pub extern "C" fn sftp_upload_file_with_progress(
    session_id: u64,
    local_path: *const c_char,
    remote_path: *const c_char,
    progress_callback: Option<CProgressCallback>,
    user_data: *mut c_void,
) -> c_int {
    if local_path.is_null() || remote_path.is_null() {
        return ErrorCode::InvalidConfig as c_int;
    }

    let local_path_str = match unsafe { CStr::from_ptr(local_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };

    let remote_path_str = match unsafe { CStr::from_ptr(remote_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };

    let manager = SESSION_MANAGER.lock();
    let connection = match manager.get_session(session_id) {
        Some(conn) => conn,
        None => return ErrorCode::SessionNotFound as c_int,
    };

    let sftp = match SftpClient::new(connection) {
        Ok(sftp) => sftp,
        Err(e) => return ErrorCode::from(&e) as c_int,
    };

    let callback = progress_callback.map(|cb| {
        let user_data_addr = user_data as usize;
        Box::new(move |transferred: u64, total: u64| {
            cb(transferred, total, user_data_addr as *mut c_void);
        }) as Box<dyn Fn(u64, u64) + Send + Sync>
    });

    match SftpClient::upload_file(&sftp, local_path_str, remote_path_str, callback) {
        Ok(_) => ErrorCode::Success as c_int,
        Err(e) => ErrorCode::from(&e) as c_int,
    }
}

/// Remove file via SFTP
#[no_mangle]
pub extern "C" fn sftp_remove_file(
    session_id: u64,
    path: *const c_char,
) -> c_int {
    if path.is_null() {
        return ErrorCode::InvalidConfig as c_int;
    }

    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };

    let manager = SESSION_MANAGER.lock();
    let connection = match manager.get_session(session_id) {
        Some(conn) => conn,
        None => return ErrorCode::SessionNotFound as c_int,
    };

    let sftp = match SftpClient::new(connection) {
        Ok(sftp) => sftp,
        Err(e) => return ErrorCode::from(&e) as c_int,
    };

    match SftpClient::remove_file(&sftp, path_str) {
        Ok(_) => ErrorCode::Success as c_int,
        Err(e) => ErrorCode::from(&e) as c_int,
    }
}

/// Remove directory via SFTP
#[no_mangle]
pub extern "C" fn sftp_remove_dir(
    session_id: u64,
    path: *const c_char,
) -> c_int {
    if path.is_null() {
        return ErrorCode::InvalidConfig as c_int;
    }

    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };

    let manager = SESSION_MANAGER.lock();
    let connection = match manager.get_session(session_id) {
        Some(conn) => conn,
        None => return ErrorCode::SessionNotFound as c_int,
    };

    let sftp = match SftpClient::new(connection) {
        Ok(sftp) => sftp,
        Err(e) => return ErrorCode::from(&e) as c_int,
    };

    match SftpClient::remove_dir(&sftp, path_str) {
        Ok(_) => ErrorCode::Success as c_int,
        Err(e) => ErrorCode::from(&e) as c_int,
    }
}

/// Create directory via SFTP
#[no_mangle]
pub extern "C" fn sftp_create_dir(
    session_id: u64,
    path: *const c_char,
) -> c_int {
    if path.is_null() {
        return ErrorCode::InvalidConfig as c_int;
    }

    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };

    let manager = SESSION_MANAGER.lock();
    let connection = match manager.get_session(session_id) {
        Some(conn) => conn,
        None => return ErrorCode::SessionNotFound as c_int,
    };

    let sftp = match SftpClient::new(connection) {
        Ok(sftp) => sftp,
        Err(e) => return ErrorCode::from(&e) as c_int,
    };

    match SftpClient::create_dir(&sftp, path_str) {
        Ok(_) => ErrorCode::Success as c_int,
        Err(e) => ErrorCode::from(&e) as c_int,
    }
}

/// Rename file/directory via SFTP
#[no_mangle]
pub extern "C" fn sftp_rename(
    session_id: u64,
    old_path: *const c_char,
    new_path: *const c_char,
) -> c_int {
    if old_path.is_null() || new_path.is_null() {
        return ErrorCode::InvalidConfig as c_int;
    }

    let old_path_str = match unsafe { CStr::from_ptr(old_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };

    let new_path_str = match unsafe { CStr::from_ptr(new_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };

    let manager = SESSION_MANAGER.lock();
    let connection = match manager.get_session(session_id) {
        Some(conn) => conn,
        None => return ErrorCode::SessionNotFound as c_int,
    };

    let sftp = match SftpClient::new(connection) {
        Ok(sftp) => sftp,
        Err(e) => return ErrorCode::from(&e) as c_int,
    };

    match SftpClient::rename(&sftp, old_path_str, new_path_str) {
        Ok(_) => ErrorCode::Success as c_int,
        Err(e) => ErrorCode::from(&e) as c_int,
    }
}

/// Get file/directory stat via SFTP
#[no_mangle]
pub extern "C" fn sftp_stat(
    session_id: u64,
    path: *const c_char,
    file_info: *mut CFileInfo,
) -> c_int {
    if path.is_null() || file_info.is_null() {
        return ErrorCode::InvalidConfig as c_int;
    }

    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return ErrorCode::InvalidConfig as c_int,
    };

    let manager = SESSION_MANAGER.lock();
    let connection = match manager.get_session(session_id) {
        Some(conn) => conn,
        None => return ErrorCode::SessionNotFound as c_int,
    };

    let sftp = match SftpClient::new(connection) {
        Ok(sftp) => sftp,
        Err(e) => return ErrorCode::from(&e) as c_int,
    };

    match SftpClient::stat(&sftp, path_str) {
        Ok(info) => {
            unsafe {
                (*file_info).name = CString::new(info.name).unwrap_or_default().into_raw();
                (*file_info).size = info.size;
                (*file_info).is_dir = if info.is_dir { 1 } else { 0 };
                (*file_info).permissions = info.permissions;
                (*file_info).modified = info.modified;
            }
            ErrorCode::Success as c_int
        }
        Err(e) => ErrorCode::from(&e) as c_int,
    }
}

fn convert_files_to_c(files: Vec<FileInfo>) -> Vec<CFileInfo> {
    files.into_iter().map(|file| {
        CFileInfo {
            name: CString::new(file.name).unwrap_or_default().into_raw(),
            size: file.size,
            is_dir: if file.is_dir { 1 } else { 0 },
            permissions: file.permissions,
            modified: file.modified,
        }
    }).collect()
}

// =============================================================================
// ASYNC FFI FUNCTIONS - NEW ARCHITECTURE
// =============================================================================

/// Callback type for async operation results
/// Parameters: operation_id (u64), success (c_int), error_code (c_int), user_data (*mut c_void)
pub type AsyncCallback = extern "C" fn(u64, c_int, c_int, *mut c_void);

/// Thread-safe wrapper for user data
struct UserDataWrapper {
    ptr: usize,
}

unsafe impl Send for UserDataWrapper {}

impl UserDataWrapper {
    fn new(ptr: *mut c_void) -> Self {
        Self { ptr: ptr as usize }
    }
    
    fn as_ptr(&self) -> *mut c_void {
        self.ptr as *mut c_void
    }
}

/// Simple SSH connection - avoid async callbacks issues
/// Just use the regular ssh_connect function
#[no_mangle]
pub extern "C" fn ssh_connect_async(
    config: *const CSshConfig,
    _callback: AsyncCallback,
    _user_data: *mut c_void,
) -> u64 {
    // For now, just use the regular sync connection
    // This avoids the isolate callback issues
    ssh_connect(config)
}

/// Simple SSH disconnection - avoid async callbacks issues
#[no_mangle]
pub extern "C" fn ssh_disconnect_async(
    session_id: u64,
    _callback: AsyncCallback,
    _user_data: *mut c_void,
) -> u64 {
    // For now, just use the regular sync disconnection
    ssh_disconnect(session_id);
    session_id  // Return the session_id as operation_id
}

/// Simple command execution - avoid async callbacks issues
#[no_mangle]
pub extern "C" fn ssh_execute_command_async(
    session_id: u64,
    command: *const c_char,
    _callback: AsyncCallback,
    user_data: *mut c_void,
) -> u64 {
    if command.is_null() {
        return 0;
    }
    
    let command_str = match unsafe { CStr::from_ptr(command) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };
    
    // Execute command synchronously if user_data is provided
    if !user_data.is_null() {
        let c_result = user_data as *mut CCommandResult;
        let _error_code = ssh_execute_command(session_id, command, c_result);
    }
    
    session_id  // Return session_id as operation_id
}
/// C-compatible file list result for async operations
#[repr(C)]
pub struct CFileListResult {
    pub count: c_int,
    pub files: *mut CFileInfo,
}

/// Async SFTP list directory
#[no_mangle]
pub extern "C" fn sftp_listdir_async(
    session_id: u64,
    path: *const c_char,
    callback: AsyncCallback,
    user_data: *mut c_void,
) -> u64 {
    if path.is_null() {
        return 0;
    }
    
    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };
    
    let worker = get_ssh_worker();
    let operation_id = worker.next_operation_id();
    let user_data_wrapper = UserDataWrapper::new(user_data);
    
    let (sender, receiver) = oneshot::channel();
    let command = SshCommand::SftpListDir {
        session_id,
        path: path_str,
        response: sender,
    };
    
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().expect("Failed to create runtime");
        rt.block_on(async {
            if let Err(_) = worker.send_command(command).await {
                callback(operation_id, 0, ErrorCode::Other as c_int, user_data_wrapper.as_ptr());
                return;
            }
            
            match receiver.await {
                Ok(Ok(files)) => {
                    let user_data_ptr = user_data_wrapper.as_ptr();
                    if !user_data_ptr.is_null() {
                        let c_files = convert_files_to_c(files);
                        unsafe {
                            let result = user_data_ptr as *mut CFileListResult;
                            (*result).count = c_files.len() as c_int;
                            (*result).files = Box::into_raw(c_files.into_boxed_slice()) as *mut CFileInfo;
                        }
                    }
                    callback(operation_id, 1, ErrorCode::Success as c_int, user_data_ptr);
                },
                Ok(Err(e)) => {
                    callback(operation_id, 0, ErrorCode::from(&e) as c_int, user_data_wrapper.as_ptr());
                },
                Err(_) => {
                    callback(operation_id, 0, ErrorCode::Other as c_int, user_data_wrapper.as_ptr());
                }
            }
        });
    });
    
    operation_id
}
