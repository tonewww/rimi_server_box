//! Rust SSH Library for ServerBox
//! 
//! This library provides SSH and SFTP functionality using ssh2-rs
//! with FFI bindings for Dart/Flutter integration.

use std::sync::Arc;
use parking_lot::Mutex;
use once_cell::sync::Lazy;

pub mod ssh;
pub mod sftp;
pub mod ffi;
pub mod error;
pub mod types;
pub mod async_worker;

pub use ssh::*;
pub use sftp::*;
pub use error::*;
pub use types::*;
pub use async_worker::*;

/// Global session manager for handling SSH connections
static SESSION_MANAGER: Lazy<Arc<Mutex<SessionManager>>> = 
    Lazy::new(|| Arc::new(Mutex::new(SessionManager::new())));

/// Session manager to track active SSH connections
pub struct SessionManager {
    sessions: std::collections::HashMap<u64, SshConnection>,
    next_id: u64,
}

impl SessionManager {
    pub fn new() -> Self {
        Self {
            sessions: std::collections::HashMap::new(),
            next_id: 1,
        }
    }

    pub fn add_session(&mut self, session: SshConnection) -> u64 {
        let id = self.next_id;
        self.next_id += 1;
        self.sessions.insert(id, session);
        id
    }

    pub fn get_session(&self, id: u64) -> Option<&SshConnection> {
        self.sessions.get(&id)
    }

    pub fn get_session_mut(&mut self, id: u64) -> Option<&mut SshConnection> {
        self.sessions.get_mut(&id)
    }

    pub fn remove_session(&mut self, id: u64) -> Option<SshConnection> {
        self.sessions.remove(&id)
    }

    pub fn list_sessions(&self) -> Vec<u64> {
        self.sessions.keys().copied().collect()
    }

    pub fn session_count(&self) -> usize {
        self.sessions.len()
    }
}

/// Initialize the library
#[no_mangle]
pub extern "C" fn rust_ssh_init() -> i32 {
    // Initialize logging or other global state if needed
    0
}

/// Cleanup the library
#[no_mangle]
pub extern "C" fn rust_ssh_cleanup() -> i32 {
    // Cleanup global state
    SESSION_MANAGER.lock().sessions.clear();
    0
}
