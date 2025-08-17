#ifndef RUST_SSH_H
#define RUST_SSH_H

#pragma once

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct Option_CProgressCallback Option_CProgressCallback;

/**
 * C-compatible SSH configuration
 */
typedef struct CSshConfig {
  const char *host;
  unsigned int port;
  const char *username;
  const char *password;
  const char *private_key;
  const char *passphrase;
  unsigned int timeout_secs;
} CSshConfig;

/**
 * C-compatible command result
 */
typedef struct CCommandResult {
  char *stdout;
  char *stderr;
  int exit_code;
} CCommandResult;

/**
 * C-compatible file info
 */
typedef struct CFileInfo {
  char *name;
  uint64_t size;
  int is_dir;
  unsigned int permissions;
  uint64_t modified;
} CFileInfo;

/**
 * Callback type for async operation results
 * Parameters: operation_id (u64), success (c_int), error_code (c_int), user_data (*mut c_void)
 */
typedef void (*AsyncCallback)(uint64_t, int, int, void*);

/**
 * Initialize the library
 */
int32_t rust_ssh_init(void);

/**
 * Cleanup the library
 */
int32_t rust_ssh_cleanup(void);

/**
 * Create SSH connection
 */
uint64_t ssh_connect(const struct CSshConfig *config);

/**
 * Disconnect SSH session
 */
int ssh_disconnect(uint64_t session_id);

/**
 * Execute command
 */
int ssh_execute_command(uint64_t session_id, const char *command, struct CCommandResult *result);

/**
 * Detect system type
 */
int ssh_detect_system_type(uint64_t session_id);

/**
 * Get active session count
 */
int ssh_get_session_count(void);

/**
 * Create SFTP session
 */
int sftp_create(uint64_t session_id);

/**
 * List directory
 */
int sftp_list_dir(uint64_t session_id,
                  const char *path,
                  struct CFileInfo **files,
                  unsigned int *count);

/**
 * Free memory allocated for strings
 */
void free_string(char *ptr);

/**
 * Free memory allocated for command result
 */
void free_command_result(struct CCommandResult *result);

/**
 * Convert Rust files to C files
 * Create local port forwarding
 */
int32_t ssh_forward_local(uint64_t session_id, const char *remote_host, uint16_t remote_port);

/**
 * Create shell session
 */
int32_t ssh_create_shell(uint64_t session_id);

/**
 * Create reverse port forwarding
 */
int32_t ssh_forward_remote(uint64_t session_id,
                           uint16_t remote_port,
                           const char *local_host,
                           uint16_t local_port);

/**
 * Download file via SFTP
 */
int sftp_download_file(uint64_t session_id, const char *remote_path, const char *local_path);

/**
 * Download file via SFTP with progress callback
 */
int sftp_download_file_with_progress(uint64_t session_id,
                                     const char *remote_path,
                                     const char *local_path,
                                     struct Option_CProgressCallback progress_callback,
                                     void *user_data);

/**
 * Upload file via SFTP
 */
int sftp_upload_file(uint64_t session_id, const char *local_path, const char *remote_path);

/**
 * Upload file via SFTP with progress callback
 */
int sftp_upload_file_with_progress(uint64_t session_id,
                                   const char *local_path,
                                   const char *remote_path,
                                   struct Option_CProgressCallback progress_callback,
                                   void *user_data);

/**
 * Remove file via SFTP
 */
int sftp_remove_file(uint64_t session_id, const char *path);

/**
 * Remove directory via SFTP
 */
int sftp_remove_dir(uint64_t session_id, const char *path);

/**
 * Create directory via SFTP
 */
int sftp_create_dir(uint64_t session_id, const char *path);

/**
 * Rename file/directory via SFTP
 */
int sftp_rename(uint64_t session_id, const char *old_path, const char *new_path);

/**
 * Get file/directory stat via SFTP
 */
int sftp_stat(uint64_t session_id, const char *path, struct CFileInfo *file_info);

/**
 * Simple SSH connection - avoid async callbacks issues
 * Just use the regular ssh_connect function
 */
uint64_t ssh_connect_async(const struct CSshConfig *config,
                           AsyncCallback _callback,
                           void *_user_data);

/**
 * Simple SSH disconnection - avoid async callbacks issues
 */
uint64_t ssh_disconnect_async(uint64_t session_id, AsyncCallback _callback, void *_user_data);

/**
 * Simple command execution - avoid async callbacks issues
 */
uint64_t ssh_execute_command_async(uint64_t session_id,
                                   const char *command,
                                   AsyncCallback _callback,
                                   void *user_data);

/**
 * Async SFTP list directory
 */
uint64_t sftp_listdir_async(uint64_t session_id,
                            const char *path,
                            AsyncCallback callback,
                            void *user_data);

#endif /* RUST_SSH_H */
