// Dart FFI bindings for Rust SSH library

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Load the native library
DynamicLibrary _loadLibrary() {
  if (Platform.isMacOS) {
    // First try debug build, then release build
    try {
      return DynamicLibrary.open('rust_ssh/target/debug/librust_ssh.dylib');
    } catch (e) {
      return DynamicLibrary.open('rust_ssh/target/release/librust_ssh.dylib');
    }
  } else if (Platform.isLinux) {
    try {
      return DynamicLibrary.open('rust_ssh/target/debug/librust_ssh.so');
    } catch (e) {
      return DynamicLibrary.open('rust_ssh/target/release/librust_ssh.so');
    }
  } else if (Platform.isWindows) {
    try {
      return DynamicLibrary.open('rust_ssh/target/debug/rust_ssh.dll');
    } catch (e) {
      return DynamicLibrary.open('rust_ssh/target/release/rust_ssh.dll');
    }
  } else if (Platform.isAndroid) {
    return DynamicLibrary.open('librust_ssh.so');
  } else if (Platform.isIOS) {
    return DynamicLibrary.process();
  }
  throw UnsupportedError('Unsupported platform');
}

final DynamicLibrary _lib = _loadLibrary();

/// C SSH Configuration struct - must match Rust CSshConfig exactly
final class CSshConfig extends Struct {
  external Pointer<Utf8> host;
  @Uint32()
  external int port;
  external Pointer<Utf8> username;
  external Pointer<Utf8> password;
  // ignore: non_constant_identifier_names
  external Pointer<Utf8> private_key;  // Must match Rust field name
  external Pointer<Utf8> passphrase;
  @Uint32()
  // ignore: non_constant_identifier_names
  external int timeout_secs;  // Must match Rust field name
}

/// C Command Result struct
final class CCommandResult extends Struct {
  external Pointer<Utf8> stdout;
  external Pointer<Utf8> stderr;
  @Int32()
  external int exitCode;
}

/// C File Info struct
final class CFileInfo extends Struct {
  external Pointer<Utf8> name;
  @Uint64()
  external int size;
  @Int32()
  external int isDir;
  @Uint32()
  external int permissions;
  @Uint64()
  external int modified;
}

/// Error codes
class ErrorCode {
  static const int success = 0;
  static const int connectionFailed = 1;
  static const int authenticationFailed = 2;
  static const int commandFailed = 3;
  static const int sftpError = 4;
  static const int ioError = 5;
  static const int invalidConfig = 6;
  static const int sessionNotFound = 7;
  static const int other = 99;
}

/// System types
class SystemType {
  static const int linux = 0;
  static const int windows = 1;
  static const int macOS = 2;
  static const int bsd = 3;
  static const int unknown = 4;
}

/// Native function bindings
class NativeSshBindings {
  /// Initialize the library
  static final int Function() _rustSshInit = _lib
      .lookup<NativeFunction<Int32 Function()>>('rust_ssh_init')
      .asFunction();

  /// Cleanup the library
  static final int Function() _rustSshCleanup = _lib
      .lookup<NativeFunction<Int32 Function()>>('rust_ssh_cleanup')
      .asFunction();

  /// Connect to SSH server
  static final int Function(Pointer<CSshConfig>) _sshConnect = _lib
      .lookup<NativeFunction<Uint64 Function(Pointer<CSshConfig>)>>('ssh_connect')
      .asFunction();

  /// Disconnect SSH session
  static final int Function(int) _sshDisconnect = _lib
      .lookup<NativeFunction<Int32 Function(Uint64)>>('ssh_disconnect')
      .asFunction();

  /// Execute command
  static final int Function(int, Pointer<Utf8>, Pointer<CCommandResult>) _sshExecuteCommand = _lib
      .lookup<NativeFunction<Int32 Function(Uint64, Pointer<Utf8>, Pointer<CCommandResult>)>>('ssh_execute_command')
      .asFunction();

  /// Detect system type
  static final int Function(int) _sshDetectSystemType = _lib
      .lookup<NativeFunction<Int32 Function(Uint64)>>('ssh_detect_system_type')
      .asFunction();

  /// Create local port forwarding
  static final int Function(int, Pointer<Utf8>, int) _sshForwardLocal = _lib
      .lookup<NativeFunction<Int32 Function(Uint64, Pointer<Utf8>, Uint16)>>('ssh_forward_local')
      .asFunction();

  /// Create shell session
  static final int Function(int) _sshCreateShell = _lib
      .lookup<NativeFunction<Int32 Function(Uint64)>>('ssh_create_shell')
      .asFunction();

  /// Create reverse port forwarding
  static final int Function(int, int, Pointer<Utf8>, int) _sshForwardRemote = _lib
      .lookup<NativeFunction<Int32 Function(Uint64, Uint16, Pointer<Utf8>, Uint16)>>('ssh_forward_remote')
      .asFunction();

  /// Create SFTP session
  static final int Function(int) _sftpCreate = _lib
      .lookup<NativeFunction<Int32 Function(Uint64)>>('sftp_create')
      .asFunction();

  /// List directory
  static final int Function(int, Pointer<Utf8>, Pointer<Pointer<CFileInfo>>, Pointer<Uint32>) _sftpListDir = _lib
      .lookup<NativeFunction<Int32 Function(Uint64, Pointer<Utf8>, Pointer<Pointer<CFileInfo>>, Pointer<Uint32>)>>('sftp_list_dir')
      .asFunction();

  /// Download file via SFTP
  static final int Function(int, Pointer<Utf8>, Pointer<Utf8>) _sftpDownloadFile = _lib
      .lookup<NativeFunction<Int32 Function(Uint64, Pointer<Utf8>, Pointer<Utf8>)>>('sftp_download_file')
      .asFunction();

  /// Upload file via SFTP
  static final int Function(int, Pointer<Utf8>, Pointer<Utf8>) _sftpUploadFile = _lib
      .lookup<NativeFunction<Int32 Function(Uint64, Pointer<Utf8>, Pointer<Utf8>)>>('sftp_upload_file')
      .asFunction();

  /// Remove file via SFTP
  static final int Function(int, Pointer<Utf8>) _sftpRemoveFile = _lib
      .lookup<NativeFunction<Int32 Function(Uint64, Pointer<Utf8>)>>('sftp_remove_file')
      .asFunction();

  /// Remove directory via SFTP
  static final int Function(int, Pointer<Utf8>) _sftpRemoveDir = _lib
      .lookup<NativeFunction<Int32 Function(Uint64, Pointer<Utf8>)>>('sftp_remove_dir')
      .asFunction();

  /// Create directory via SFTP
  static final int Function(int, Pointer<Utf8>) _sftpCreateDir = _lib
      .lookup<NativeFunction<Int32 Function(Uint64, Pointer<Utf8>)>>('sftp_create_dir')
      .asFunction();

  /// Rename file/directory via SFTP
  static final int Function(int, Pointer<Utf8>, Pointer<Utf8>) _sftpRename = _lib
      .lookup<NativeFunction<Int32 Function(Uint64, Pointer<Utf8>, Pointer<Utf8>)>>('sftp_rename')
      .asFunction();

  /// Get file/directory stat via SFTP
  static final int Function(int, Pointer<Utf8>, Pointer<CFileInfo>) _sftpStat = _lib
      .lookup<NativeFunction<Int32 Function(Uint64, Pointer<Utf8>, Pointer<CFileInfo>)>>('sftp_stat')
      .asFunction();

  /// Download file via SFTP with progress callback
  static final int Function(int, Pointer<Utf8>, Pointer<Utf8>, Pointer<NativeFunction<Void Function(Uint64, Uint64, Pointer<Void>)>>, Pointer<Void>) _sftpDownloadFileWithProgress = _lib
      .lookup<NativeFunction<Int32 Function(Uint64, Pointer<Utf8>, Pointer<Utf8>, Pointer<NativeFunction<Void Function(Uint64, Uint64, Pointer<Void>)>>, Pointer<Void>)>>('sftp_download_file_with_progress')
      .asFunction();

  /// Upload file via SFTP with progress callback
  static final int Function(int, Pointer<Utf8>, Pointer<Utf8>, Pointer<NativeFunction<Void Function(Uint64, Uint64, Pointer<Void>)>>, Pointer<Void>) _sftpUploadFileWithProgress = _lib
      .lookup<NativeFunction<Int32 Function(Uint64, Pointer<Utf8>, Pointer<Utf8>, Pointer<NativeFunction<Void Function(Uint64, Uint64, Pointer<Void>)>>, Pointer<Void>)>>('sftp_upload_file_with_progress')
      .asFunction();

  /// Free string memory
  static final void Function(Pointer<Utf8>) _freeString = _lib
      .lookup<NativeFunction<Void Function(Pointer<Utf8>)>>('free_string')
      .asFunction();

  /// Free command result memory
  static final void Function(Pointer<CCommandResult>) _freeCommandResult = _lib
      .lookup<NativeFunction<Void Function(Pointer<CCommandResult>)>>('free_command_result')
      .asFunction();

  /// Get last error message
  static final Pointer<Utf8> Function() _getLastError = _lib
      .lookup<NativeFunction<Pointer<Utf8> Function()>>('ssh_get_last_error')
      .asFunction();

  /// Initialize library
  static int init() => _rustSshInit();

  /// Cleanup library
  static int cleanup() => _rustSshCleanup();

  /// Connect to SSH server
  static int connect(Pointer<CSshConfig> config) => _sshConnect(config);

  /// Disconnect SSH session
  static int disconnect(int sessionId) => _sshDisconnect(sessionId);

  /// Execute command
  static int executeCommand(int sessionId, Pointer<Utf8> command, Pointer<CCommandResult> result) =>
      _sshExecuteCommand(sessionId, command, result);

  /// Detect system type
  static int detectSystemType(int sessionId) => _sshDetectSystemType(sessionId);

  /// Create local port forwarding
  static int forwardLocal(int sessionId, Pointer<Utf8> remoteHost, int remotePort) =>
      _sshForwardLocal(sessionId, remoteHost, remotePort);

  /// Create shell session
  static int createShell(int sessionId) => _sshCreateShell(sessionId);

  /// Create reverse port forwarding
  static int forwardRemote(int sessionId, int remotePort, Pointer<Utf8> localHost, int localPort) =>
      _sshForwardRemote(sessionId, remotePort, localHost, localPort);

  /// Create SFTP session
  static int sftpCreate(int sessionId) => _sftpCreate(sessionId);

  /// List directory
  static int sftpListDir(int sessionId, Pointer<Utf8> path, Pointer<Pointer<CFileInfo>> files, Pointer<Uint32> count) =>
      _sftpListDir(sessionId, path, files, count);

  /// Download file via SFTP
  static int sftpDownloadFile(int sessionId, Pointer<Utf8> remotePath, Pointer<Utf8> localPath) =>
      _sftpDownloadFile(sessionId, remotePath, localPath);

  /// Upload file via SFTP
  static int sftpUploadFile(int sessionId, Pointer<Utf8> localPath, Pointer<Utf8> remotePath) =>
      _sftpUploadFile(sessionId, localPath, remotePath);

  /// Remove file via SFTP
  static int sftpRemoveFile(int sessionId, Pointer<Utf8> path) =>
      _sftpRemoveFile(sessionId, path);

  /// Remove directory via SFTP
  static int sftpRemoveDir(int sessionId, Pointer<Utf8> path) =>
      _sftpRemoveDir(sessionId, path);

  /// Create directory via SFTP
  static int sftpCreateDir(int sessionId, Pointer<Utf8> path) =>
      _sftpCreateDir(sessionId, path);

  /// Rename file/directory via SFTP
  static int sftpRename(int sessionId, Pointer<Utf8> oldPath, Pointer<Utf8> newPath) =>
      _sftpRename(sessionId, oldPath, newPath);

  /// Get file/directory stat via SFTP
  static int sftpStat(int sessionId, Pointer<Utf8> path, Pointer<CFileInfo> fileInfo) =>
      _sftpStat(sessionId, path, fileInfo);

  /// Download file via SFTP with progress callback
  static int sftpDownloadFileWithProgress(int sessionId, Pointer<Utf8> remotePath, Pointer<Utf8> localPath, Pointer<NativeFunction<Void Function(Uint64, Uint64, Pointer<Void>)>> progressCallback, Pointer<Void> userData) =>
      _sftpDownloadFileWithProgress(sessionId, remotePath, localPath, progressCallback, userData);

  /// Upload file via SFTP with progress callback
  static int sftpUploadFileWithProgress(int sessionId, Pointer<Utf8> localPath, Pointer<Utf8> remotePath, Pointer<NativeFunction<Void Function(Uint64, Uint64, Pointer<Void>)>> progressCallback, Pointer<Void> userData) =>
      _sftpUploadFileWithProgress(sessionId, localPath, remotePath, progressCallback, userData);

  /// Free string memory
  static void freeString(Pointer<Utf8> ptr) => _freeString(ptr);

  /// Free command result memory
  static void freeCommandResult(Pointer<CCommandResult> result) => _freeCommandResult(result);

  /// Get last error message
  static String? getLastError() {
    final errorPtr = _getLastError();
    if (errorPtr == nullptr) {
      return null;
    }
    
    final error = errorPtr.toDartString();
    freeString(errorPtr);  // Free the error string
    return error;
  }
}