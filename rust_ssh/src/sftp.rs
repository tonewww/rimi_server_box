//! SFTP functionality

use crate::{SshConnection, SshError, SshResult, FileInfo, ProgressCallback};
use ssh2::Sftp;
use std::io::prelude::*;
use std::path::Path;

/// SFTP client implementation
pub struct SftpClient;

impl SftpClient {
    /// Create SFTP session
    pub fn new(connection: &SshConnection) -> SshResult<Sftp> {
        let sftp = connection.session.sftp()?;
        Ok(sftp)
    }
    
    /// List directory contents
    pub fn list_dir(sftp: &Sftp, path: &str) -> SshResult<Vec<FileInfo>> {
        let mut files = Vec::new();
        
        for (path_buf, stat) in sftp.readdir(Path::new(path))? {
            let name = path_buf.file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("?")
                .to_string();
            
            files.push(FileInfo {
                name,
                size: stat.size.unwrap_or(0),
                is_dir: stat.is_dir(),
                permissions: stat.perm.unwrap_or(0),
                modified: stat.mtime.unwrap_or(0),
            });
        }
        
        Ok(files)
    }
    
    /// Download file
    pub fn download_file(
        sftp: &Sftp,
        remote_path: &str,
        local_path: &str,
        progress_callback: Option<ProgressCallback>,
    ) -> SshResult<()> {
        let mut remote_file = sftp.open(Path::new(remote_path))?;
        let stat = remote_file.stat()?;
        let total_size = stat.size.unwrap_or(0);
        
        let mut local_file = std::fs::File::create(local_path)?;
        let mut buffer = [0; 8192];
        let mut downloaded = 0u64;
        
        loop {
            match remote_file.read(&mut buffer) {
                Ok(0) => break, // EOF
                Ok(n) => {
                    local_file.write_all(&buffer[..n])?;
                    downloaded += n as u64;
                    
                    if let Some(ref callback) = progress_callback {
                        callback(downloaded, total_size);
                    }
                }
                Err(e) => return Err(SshError::IoError(e.to_string())),
            }
        }
        
        local_file.sync_all()?;
        Ok(())
    }
    
    /// Upload file
    pub fn upload_file(
        sftp: &Sftp,
        local_path: &str,
        remote_path: &str,
        progress_callback: Option<ProgressCallback>,
    ) -> SshResult<()> {
        let local_file = std::fs::File::open(local_path)?;
        let total_size = local_file.metadata()?.len();
        
        let mut remote_file = sftp.create(Path::new(remote_path))?;
        let mut local_reader = std::io::BufReader::new(local_file);
        let mut buffer = [0; 8192];
        let mut uploaded = 0u64;
        
        loop {
            match local_reader.read(&mut buffer) {
                Ok(0) => break, // EOF
                Ok(n) => {
                    remote_file.write_all(&buffer[..n])?;
                    uploaded += n as u64;
                    
                    if let Some(ref callback) = progress_callback {
                        callback(uploaded, total_size);
                    }
                }
                Err(e) => return Err(SshError::IoError(e.to_string())),
            }
        }
        
        // remote_file.sync_all()?; // ssh2::File doesn't have sync_all
        // File will be synced automatically when dropped
        Ok(())
    }
    
    /// Remove file
    pub fn remove_file(sftp: &Sftp, path: &str) -> SshResult<()> {
        sftp.unlink(Path::new(path))?;
        Ok(())
    }
    
    /// Remove directory
    pub fn remove_dir(sftp: &Sftp, path: &str) -> SshResult<()> {
        sftp.rmdir(Path::new(path))?;
        Ok(())
    }
    
    /// Create directory
    pub fn create_dir(sftp: &Sftp, path: &str) -> SshResult<()> {
        sftp.mkdir(Path::new(path), 0o755)?;
        Ok(())
    }
    
    /// Rename file/directory
    pub fn rename(sftp: &Sftp, old_path: &str, new_path: &str) -> SshResult<()> {
        sftp.rename(Path::new(old_path), Path::new(new_path), None)?;
        Ok(())
    }
    
    /// Get file/directory information
    pub fn stat(sftp: &Sftp, path: &str) -> SshResult<FileInfo> {
        let stat = sftp.stat(Path::new(path))?;
        
        let name = Path::new(path)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("?")
            .to_string();
        
        Ok(FileInfo {
            name,
            size: stat.size.unwrap_or(0),
            is_dir: stat.is_dir(),
            permissions: stat.perm.unwrap_or(0),
            modified: stat.mtime.unwrap_or(0),
        })
    }
}