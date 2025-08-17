//! Async worker system for handling blocking SSH operations in separate threads

use crate::{SshConfig, SshError, SshResult, CommandResult, FileInfo};
use std::sync::Arc;
use parking_lot::Mutex;
use tokio::sync::{mpsc, oneshot};
use std::thread;
use std::time::Duration;
use std::collections::HashMap;

/// Unique ID for async operations
pub type OperationId = u64;

/// Commands that can be sent to the SSH worker
#[derive(Debug)]
pub enum SshCommand {
    Connect {
        config: SshConfig,
        response: oneshot::Sender<SshResult<u64>>,
    },
    Disconnect {
        session_id: u64,
        response: oneshot::Sender<SshResult<()>>,
    },
    ExecuteCommand {
        session_id: u64,
        command: String,
        response: oneshot::Sender<SshResult<CommandResult>>,
    },
    CreateShell {
        session_id: u64,
        response: oneshot::Sender<SshResult<()>>,
    },
    ForwardLocal {
        session_id: u64,
        remote_host: String,
        remote_port: u16,
        response: oneshot::Sender<SshResult<()>>,
    },
    ForwardRemote {
        session_id: u64,
        remote_port: u16,
        local_host: String,
        local_port: u16,
        response: oneshot::Sender<SshResult<()>>,
    },
    SftpListDir {
        session_id: u64,
        path: String,
        response: oneshot::Sender<SshResult<Vec<FileInfo>>>,
    },
    SftpDownload {
        session_id: u64,
        remote_path: String,
        local_path: String,
        response: oneshot::Sender<SshResult<()>>,
    },
    SftpUpload {
        session_id: u64,
        local_path: String,
        remote_path: String,
        response: oneshot::Sender<SshResult<()>>,
    },
    SftpRemoveFile {
        session_id: u64,
        path: String,
        response: oneshot::Sender<SshResult<()>>,
    },
    SftpCreateDir {
        session_id: u64,
        path: String,
        response: oneshot::Sender<SshResult<()>>,
    },
    SftpRemoveDir {
        session_id: u64,
        path: String,
        response: oneshot::Sender<SshResult<()>>,
    },
    SftpRename {
        session_id: u64,
        old_path: String,
        new_path: String,
        response: oneshot::Sender<SshResult<()>>,
    },
    SftpStat {
        session_id: u64,
        path: String,
        response: oneshot::Sender<SshResult<FileInfo>>,
    },
    CancelOperation {
        operation_id: OperationId,
        response: oneshot::Sender<SshResult<()>>,
    },
}

/// SSH Worker that runs in a separate thread and handles blocking operations
pub struct SshWorker {
    command_sender: mpsc::UnboundedSender<SshCommand>,
    next_operation_id: Arc<Mutex<u64>>,
    active_operations: Arc<Mutex<HashMap<OperationId, tokio::task::AbortHandle>>>,
}

impl SshWorker {
    /// Create a new SSH worker with its own thread
    pub fn new() -> Self {
        let (command_sender, mut command_receiver) = mpsc::unbounded_channel::<SshCommand>();
        let next_operation_id = Arc::new(Mutex::new(1));
        let active_operations = Arc::new(Mutex::new(HashMap::new()));
        let active_ops_clone = active_operations.clone();

        // Spawn a dedicated thread for SSH operations
        thread::spawn(move || {
            // Create a new single-threaded tokio runtime for this thread
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("Failed to create Tokio runtime");

            rt.block_on(async move {
                let mut session_manager = crate::SessionManager::new();

                while let Some(command) = command_receiver.recv().await {
                    Self::handle_command(command, &mut session_manager, active_ops_clone.clone()).await;
                }
            });
        });

        SshWorker {
            command_sender,
            next_operation_id,
            active_operations,
        }
    }

    /// Handle a command in the worker thread
    async fn handle_command(
        command: SshCommand, 
        session_manager: &mut crate::SessionManager,
        active_operations: Arc<Mutex<HashMap<OperationId, tokio::task::AbortHandle>>>,
    ) {
        match command {
            SshCommand::Connect { config, response } => {
                let result = crate::SshClient::connect(config);
                match result {
                    Ok(connection) => {
                        let session_id = session_manager.add_session(connection);
                        let _ = response.send(Ok(session_id));
                    },
                    Err(e) => {
                        let _ = response.send(Err(e));
                    },
                }
            },
            SshCommand::Disconnect { session_id, response } => {
                let result = if let Some(mut connection) = session_manager.remove_session(session_id) {
                    crate::SshClient::disconnect(&mut connection)
                } else {
                    Err(SshError::Other("Session not found".to_string()))
                };

                let _ = response.send(result);
            },
            SshCommand::ExecuteCommand { session_id, command, response } => {
                let result = if let Some(connection) = session_manager.get_session_mut(session_id) {
                    // Execute the command directly without spawn_blocking since we're already in a worker thread
                    crate::SshClient::execute_command(connection, &command)
                } else {
                    Err(SshError::Other("Session not found".to_string()))
                };

                let _ = response.send(result);
            },
            SshCommand::CreateShell { session_id, response } => {
                let result = if let Some(connection) = session_manager.get_session_mut(session_id) {
                    crate::SshClient::create_shell(connection).map(|_| ())
                } else {
                    Err(SshError::Other("Session not found".to_string()))
                };

                let _ = response.send(result);
            },
            SshCommand::ForwardLocal { session_id, remote_host, remote_port, response } => {
                let result = if let Some(connection) = session_manager.get_session_mut(session_id) {
                    crate::SshClient::forward_local(connection, &remote_host, remote_port).map(|_| ())
                } else {
                    Err(SshError::Other("Session not found".to_string()))
                };

                let _ = response.send(result);
            },
            SshCommand::ForwardRemote { session_id, remote_port, local_host, local_port, response } => {
                let result = if let Some(connection) = session_manager.get_session_mut(session_id) {
                    crate::SshClient::forward_remote(connection, remote_port, &local_host, local_port)
                } else {
                    Err(SshError::Other("Session not found".to_string()))
                };

                let _ = response.send(result);
            },
            SshCommand::SftpListDir { session_id, path, response } => {
                let result = if let Some(connection) = session_manager.get_session(session_id) {
                    match crate::SftpClient::new(connection) {
                        Ok(sftp) => crate::SftpClient::list_dir(&sftp, &path),
                        Err(e) => Err(e),
                    }
                } else {
                    Err(SshError::Other("Session not found".to_string()))
                };

                let _ = response.send(result);
            },
            SshCommand::SftpDownload { session_id, remote_path, local_path, response } => {
                let result = if let Some(connection) = session_manager.get_session(session_id) {
                    match crate::SftpClient::new(connection) {
                        Ok(sftp) => crate::SftpClient::download_file(&sftp, &remote_path, &local_path, None),
                        Err(e) => Err(e),
                    }
                } else {
                    Err(SshError::Other("Session not found".to_string()))
                };

                let _ = response.send(result);
            },
            SshCommand::SftpUpload { session_id, local_path, remote_path, response } => {
                let result = if let Some(connection) = session_manager.get_session(session_id) {
                    match crate::SftpClient::new(connection) {
                        Ok(sftp) => crate::SftpClient::upload_file(&sftp, &local_path, &remote_path, None),
                        Err(e) => Err(e),
                    }
                } else {
                    Err(SshError::Other("Session not found".to_string()))
                };

                let _ = response.send(result);
            },
            SshCommand::SftpRemoveFile { session_id, path, response } => {
                let result = if let Some(connection) = session_manager.get_session(session_id) {
                    match crate::SftpClient::new(connection) {
                        Ok(sftp) => crate::SftpClient::remove_file(&sftp, &path),
                        Err(e) => Err(e),
                    }
                } else {
                    Err(SshError::Other("Session not found".to_string()))
                };

                let _ = response.send(result);
            },
            SshCommand::SftpCreateDir { session_id, path, response } => {
                let result = if let Some(connection) = session_manager.get_session(session_id) {
                    match crate::SftpClient::new(connection) {
                        Ok(sftp) => crate::SftpClient::create_dir(&sftp, &path),
                        Err(e) => Err(e),
                    }
                } else {
                    Err(SshError::Other("Session not found".to_string()))
                };

                let _ = response.send(result);
            },
            SshCommand::SftpRemoveDir { session_id, path, response } => {
                let result = if let Some(connection) = session_manager.get_session(session_id) {
                    match crate::SftpClient::new(connection) {
                        Ok(sftp) => crate::SftpClient::remove_dir(&sftp, &path),
                        Err(e) => Err(e),
                    }
                } else {
                    Err(SshError::Other("Session not found".to_string()))
                };

                let _ = response.send(result);
            },
            SshCommand::SftpRename { session_id, old_path, new_path, response } => {
                let result = if let Some(connection) = session_manager.get_session(session_id) {
                    match crate::SftpClient::new(connection) {
                        Ok(sftp) => crate::SftpClient::rename(&sftp, &old_path, &new_path),
                        Err(e) => Err(e),
                    }
                } else {
                    Err(SshError::Other("Session not found".to_string()))
                };

                let _ = response.send(result);
            },
            SshCommand::SftpStat { session_id, path, response } => {
                let result = if let Some(connection) = session_manager.get_session(session_id) {
                    match crate::SftpClient::new(connection) {
                        Ok(sftp) => crate::SftpClient::stat(&sftp, &path),
                        Err(e) => Err(e),
                    }
                } else {
                    Err(SshError::Other("Session not found".to_string()))
                };

                let _ = response.send(result);
            },
            SshCommand::CancelOperation { operation_id, response } => {
                // Try to cancel the operation by removing it from active operations
                let mut ops = active_operations.lock();
                if let Some(abort_handle) = ops.remove(&operation_id) {
                    abort_handle.abort();
                    let _ = response.send(Ok(()));
                } else {
                    let _ = response.send(Err(SshError::Other("Operation not found or already completed".to_string())));
                }
            },
        }
    }

    /// Send a command to the worker and get a unique operation ID
    pub async fn send_command(&self, command: SshCommand) -> Result<(), SshError> {
        self.command_sender.send(command)
            .map_err(|_| SshError::Other("Worker thread is not running".to_string()))
    }

    /// Get the next operation ID
    pub fn next_operation_id(&self) -> u64 {
        let mut id = self.next_operation_id.lock();
        let current = *id;
        *id += 1;
        current
    }

    /// Cancel an operation by its ID
    pub async fn cancel_operation(&self, operation_id: OperationId) -> Result<(), SshError> {
        let (sender, receiver) = oneshot::channel();
        let command = SshCommand::CancelOperation {
            operation_id,
            response: sender,
        };
        
        self.send_command(command).await?;
        receiver.await.map_err(|_| SshError::Other("Cancel operation failed".to_string()))?
    }

    /// Send command with timeout
    pub async fn send_command_with_timeout(
        &self, 
        command: SshCommand, 
        timeout: Duration
    ) -> Result<(), SshError> {
        let send_future = self.send_command(command);
        tokio::time::timeout(timeout, send_future)
            .await
            .map_err(|_| SshError::Other("Operation timed out".to_string()))?
    }
}

/// Global SSH worker instance
static SSH_WORKER: once_cell::sync::Lazy<SshWorker> = once_cell::sync::Lazy::new(|| {
    SshWorker::new()
});

/// Get the global SSH worker instance
pub fn get_ssh_worker() -> &'static SshWorker {
    &SSH_WORKER
}