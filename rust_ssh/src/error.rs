//! Error types for SSH library

use std::fmt;

/// SSH library errors
#[derive(Debug, Clone)]
pub enum SshError {
    /// Connection errors
    ConnectionFailed(String),
    /// Authentication errors
    AuthenticationFailed(String),
    /// Command execution errors
    CommandFailed(String),
    /// SFTP errors
    SftpError(String),
    /// IO errors
    IoError(String),
    /// Invalid configuration
    InvalidConfig(String),
    /// Session not found
    SessionNotFound(u64),
    /// Generic error
    Other(String),
}

impl fmt::Display for SshError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SshError::ConnectionFailed(msg) => write!(f, "Connection failed: {}", msg),
            SshError::AuthenticationFailed(msg) => write!(f, "Authentication failed: {}", msg),
            SshError::CommandFailed(msg) => write!(f, "Command failed: {}", msg),
            SshError::SftpError(msg) => write!(f, "SFTP error: {}", msg),
            SshError::IoError(msg) => write!(f, "IO error: {}", msg),
            SshError::InvalidConfig(msg) => write!(f, "Invalid configuration: {}", msg),
            SshError::SessionNotFound(id) => write!(f, "Session not found: {}", id),
            SshError::Other(msg) => write!(f, "Error: {}", msg),
        }
    }
}

impl std::error::Error for SshError {}

impl From<ssh2::Error> for SshError {
    fn from(err: ssh2::Error) -> Self {
        SshError::Other(err.to_string())
    }
}

impl From<std::io::Error> for SshError {
    fn from(err: std::io::Error) -> Self {
        SshError::IoError(err.to_string())
    }
}

impl From<anyhow::Error> for SshError {
    fn from(err: anyhow::Error) -> Self {
        SshError::Other(err.to_string())
    }
}

/// Result type for SSH operations
pub type SshResult<T> = Result<T, SshError>;

/// Error codes for FFI
#[repr(C)]
pub enum ErrorCode {
    Success = 0,
    ConnectionFailed = 1,
    AuthenticationFailed = 2,
    CommandFailed = 3,
    SftpError = 4,
    IoError = 5,
    InvalidConfig = 6,
    SessionNotFound = 7,
    Other = 99,
}

impl From<&SshError> for ErrorCode {
    fn from(error: &SshError) -> Self {
        match error {
            SshError::ConnectionFailed(_) => ErrorCode::ConnectionFailed,
            SshError::AuthenticationFailed(_) => ErrorCode::AuthenticationFailed,
            SshError::CommandFailed(_) => ErrorCode::CommandFailed,
            SshError::SftpError(_) => ErrorCode::SftpError,
            SshError::IoError(_) => ErrorCode::IoError,
            SshError::InvalidConfig(_) => ErrorCode::InvalidConfig,
            SshError::SessionNotFound(_) => ErrorCode::SessionNotFound,
            SshError::Other(_) => ErrorCode::Other,
        }
    }
}