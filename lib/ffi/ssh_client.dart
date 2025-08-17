// High-level Dart wrapper for Rust SSH library

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:server_box/ffi/ssh_bindings.dart';

/// SSH configuration for Dart
class SshConfig {
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final String? passphrase;
  final Duration timeout;

  const SshConfig({
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKey,
    this.passphrase,
    this.timeout = const Duration(seconds: 30),
  });
}

/// Command execution result
class CommandResult {
  final String stdout;
  final String stderr;
  final int? exitCode;

  const CommandResult({
    required this.stdout,
    required this.stderr,
    this.exitCode,
  });

  @override
  String toString() => 'CommandResult(stdout: $stdout, stderr: $stderr, exitCode: $exitCode)';
}

/// File information
class FileInfo {
  final String name;
  final int size;
  final bool isDir;
  final int permissions;
  final DateTime modified;

  const FileInfo({
    required this.name,
    required this.size,
    required this.isDir,
    required this.permissions,
    required this.modified,
  });

  @override
  String toString() => 'FileInfo(name: $name, size: $size, isDir: $isDir)';
}

/// SSH library exceptions
class SshException implements Exception {
  final String message;
  final int errorCode;

  const SshException(this.message, this.errorCode);

  @override
  String toString() => 'SshException: $message (code: $errorCode)';
}

/// High-level SSH client
class SshClient {
  static bool _initialized = false;
  int? _sessionId;

  /// Initialize the SSH library (call once)
  static void initialize() {
    if (!_initialized) {
      final result = NativeSshBindings.init();
      if (result != ErrorCode.success) {
        throw SshException('Failed to initialize SSH library', result);
      }
      _initialized = true;
    }
  }

  /// Cleanup the SSH library (call when done)
  static void cleanup() {
    if (_initialized) {
      NativeSshBindings.cleanup();
      _initialized = false;
    }
  }

  /// Connect to SSH server
  Future<void> connect(SshConfig config) async {
    if (_sessionId != null) {
      throw SshException('Already connected', ErrorCode.other);
    }

    final cConfig = malloc<CSshConfig>();
    try {
      cConfig.ref
        ..host = config.host.toNativeUtf8().cast()
        ..port = config.port
        ..username = config.username.toNativeUtf8().cast()
        ..password = config.password?.toNativeUtf8().cast() ?? nullptr
        ..private_key = config.privateKey?.toNativeUtf8().cast() ?? nullptr
        ..passphrase = config.passphrase?.toNativeUtf8().cast() ?? nullptr
        ..timeout_secs = config.timeout.inSeconds;

      final sessionId = NativeSshBindings.connect(cConfig);
      if (sessionId == 0) {
        throw SshException('Connection failed', ErrorCode.connectionFailed);
      }

      _sessionId = sessionId;
    } finally {
      // Free allocated strings
      if (cConfig.ref.host != nullptr) malloc.free(cConfig.ref.host);
      if (cConfig.ref.username != nullptr) malloc.free(cConfig.ref.username);
      if (cConfig.ref.password != nullptr) malloc.free(cConfig.ref.password);
      if (cConfig.ref.private_key != nullptr) malloc.free(cConfig.ref.private_key);
      if (cConfig.ref.passphrase != nullptr) malloc.free(cConfig.ref.passphrase);
      malloc.free(cConfig);
    }
  }

  /// Disconnect from SSH server
  Future<void> disconnect() async {
    if (_sessionId == null) return;

    final result = NativeSshBindings.disconnect(_sessionId!);
    if (result != ErrorCode.success) {
      throw SshException('Disconnect failed', result);
    }

    _sessionId = null;
  }

  /// Execute a command
  Future<CommandResult> execute(String command) async {
    if (_sessionId == null) {
      throw SshException('Not connected', ErrorCode.sessionNotFound);
    }

    final commandPtr = command.toNativeUtf8().cast<Utf8>();
    final resultPtr = malloc<CCommandResult>();

    try {
      final errorCode = NativeSshBindings.executeCommand(_sessionId!, commandPtr, resultPtr);
      if (errorCode != ErrorCode.success) {
        throw SshException('Command execution failed', errorCode);
      }

      final result = CommandResult(
        stdout: resultPtr.ref.stdout.cast<Utf8>().toDartString(),
        stderr: resultPtr.ref.stderr.cast<Utf8>().toDartString(),
        exitCode: resultPtr.ref.exitCode,
      );

      // Free the result memory
      NativeSshBindings.freeCommandResult(resultPtr);

      return result;
    } finally {
      malloc.free(commandPtr);
      malloc.free(resultPtr);
    }
  }

  /// Detect system type
  Future<int> detectSystemType() async {
    if (_sessionId == null) {
      throw SshException('Not connected', ErrorCode.sessionNotFound);
    }

    return NativeSshBindings.detectSystemType(_sessionId!);
  }

  /// Create local port forwarding (jump server functionality)
  Future<void> forwardLocal(String remoteHost, int remotePort) async {
    if (_sessionId == null) {
      throw SshException('Not connected', ErrorCode.sessionNotFound);
    }

    final remoteHostPtr = remoteHost.toNativeUtf8().cast<Utf8>();
    
    try {
      final errorCode = NativeSshBindings.forwardLocal(_sessionId!, remoteHostPtr, remotePort);
      if (errorCode != ErrorCode.success) {
        throw SshException('Local port forwarding failed', errorCode);
      }
    } finally {
      malloc.free(remoteHostPtr);
    }
  }

  /// Create reverse port forwarding
  Future<void> forwardRemote(int remotePort, String localHost, int localPort) async {
    if (_sessionId == null) {
      throw SshException('Not connected', ErrorCode.sessionNotFound);
    }

    final localHostPtr = localHost.toNativeUtf8().cast<Utf8>();
    
    try {
      final errorCode = NativeSshBindings.forwardRemote(_sessionId!, remotePort, localHostPtr, localPort);
      if (errorCode != ErrorCode.success) {
        throw SshException('Reverse port forwarding failed', errorCode);
      }
    } finally {
      malloc.free(localHostPtr);
    }
  }

  /// Create shell session
  Future<void> createShell() async {
    if (_sessionId == null) {
      throw SshException('Not connected', ErrorCode.sessionNotFound);
    }

    final errorCode = NativeSshBindings.createShell(_sessionId!);
    if (errorCode != ErrorCode.success) {
      throw SshException('Shell creation failed', errorCode);
    }
  }

  /// Check if connected
  bool get isConnected => _sessionId != null;

  /// Get session ID
  int? get sessionId => _sessionId;
}

/// SFTP client for file operations
class SftpClient {
  final SshClient _sshClient;

  SftpClient(this._sshClient);

  /// Create SFTP session
  Future<void> initialize() async {
    if (_sshClient.sessionId == null) {
      throw SshException('SSH not connected', ErrorCode.sessionNotFound);
    }

    final result = NativeSshBindings.sftpCreate(_sshClient.sessionId!);
    if (result != ErrorCode.success) {
      throw SshException('SFTP initialization failed', result);
    }
  }

  /// List directory contents
  Future<List<FileInfo>> listDirectory(String path) async {
    if (_sshClient.sessionId == null) {
      throw SshException('SSH not connected', ErrorCode.sessionNotFound);
    }

    final pathPtr = path.toNativeUtf8().cast<Utf8>();
    final filesPtr = malloc<Pointer<CFileInfo>>();
    final countPtr = malloc<Uint32>();

    try {
      final errorCode = NativeSshBindings.sftpListDir(
        _sshClient.sessionId!,
        pathPtr,
        filesPtr,
        countPtr,
      );

      if (errorCode != ErrorCode.success) {
        throw SshException('Directory listing failed', errorCode);
      }

      final count = countPtr.value;
      final files = <FileInfo>[];

      for (int i = 0; i < count; i++) {
        final filePtr = filesPtr.value + i;
        final file = FileInfo(
          name: filePtr.ref.name.cast<Utf8>().toDartString(),
          size: filePtr.ref.size,
          isDir: filePtr.ref.isDir != 0,
          permissions: filePtr.ref.permissions,
          modified: DateTime.fromMillisecondsSinceEpoch(filePtr.ref.modified * 1000),
        );
        files.add(file);
      }

      return files;
    } finally {
      malloc.free(pathPtr);
      malloc.free(filesPtr);
      malloc.free(countPtr);
    }
  }

  /// Download file from remote to local
  Future<void> downloadFile(String remotePath, String localPath, {
    void Function(int transferred, int total)? onProgress,
  }) async {
    if (_sshClient.sessionId == null) {
      throw SshException('SSH not connected', ErrorCode.sessionNotFound);
    }

    final remotePathPtr = remotePath.toNativeUtf8().cast<Utf8>();
    final localPathPtr = localPath.toNativeUtf8().cast<Utf8>();

    try {
      final errorCode = NativeSshBindings.sftpDownloadFile(
        _sshClient.sessionId!,
        remotePathPtr,
        localPathPtr,
      );

      if (errorCode != ErrorCode.success) {
        throw SshException('File download failed', errorCode);
      }

      // For now, call progress callback with completion (100%)
      // TODO: Implement real-time progress using FFI callbacks
      if (onProgress != null) {
        onProgress(100, 100);
      }
    } finally {
      malloc.free(remotePathPtr);
      malloc.free(localPathPtr);
    }
  }

  /// Upload file from local to remote
  Future<void> uploadFile(String localPath, String remotePath, {
    void Function(int transferred, int total)? onProgress,
  }) async {
    if (_sshClient.sessionId == null) {
      throw SshException('SSH not connected', ErrorCode.sessionNotFound);
    }

    final localPathPtr = localPath.toNativeUtf8().cast<Utf8>();
    final remotePathPtr = remotePath.toNativeUtf8().cast<Utf8>();

    try {
      final errorCode = NativeSshBindings.sftpUploadFile(
        _sshClient.sessionId!,
        localPathPtr,
        remotePathPtr,
      );

      if (errorCode != ErrorCode.success) {
        throw SshException('File upload failed', errorCode);
      }

      // For now, call progress callback with completion (100%)
      // TODO: Implement real-time progress using FFI callbacks
      if (onProgress != null) {
        onProgress(100, 100);
      }
    } finally {
      malloc.free(localPathPtr);
      malloc.free(remotePathPtr);
    }
  }

  /// Remove file
  Future<void> removeFile(String path) async {
    if (_sshClient.sessionId == null) {
      throw SshException('SSH not connected', ErrorCode.sessionNotFound);
    }

    final pathPtr = path.toNativeUtf8().cast<Utf8>();

    try {
      final errorCode = NativeSshBindings.sftpRemoveFile(
        _sshClient.sessionId!,
        pathPtr,
      );

      if (errorCode != ErrorCode.success) {
        throw SshException('File removal failed', errorCode);
      }
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Remove directory
  Future<void> removeDirectory(String path) async {
    if (_sshClient.sessionId == null) {
      throw SshException('SSH not connected', ErrorCode.sessionNotFound);
    }

    final pathPtr = path.toNativeUtf8().cast<Utf8>();

    try {
      final errorCode = NativeSshBindings.sftpRemoveDir(
        _sshClient.sessionId!,
        pathPtr,
      );

      if (errorCode != ErrorCode.success) {
        throw SshException('Directory removal failed', errorCode);
      }
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Create directory
  Future<void> createDirectory(String path) async {
    if (_sshClient.sessionId == null) {
      throw SshException('SSH not connected', ErrorCode.sessionNotFound);
    }

    final pathPtr = path.toNativeUtf8().cast<Utf8>();

    try {
      final errorCode = NativeSshBindings.sftpCreateDir(
        _sshClient.sessionId!,
        pathPtr,
      );

      if (errorCode != ErrorCode.success) {
        throw SshException('Directory creation failed', errorCode);
      }
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Rename file or directory
  Future<void> rename(String oldPath, String newPath) async {
    if (_sshClient.sessionId == null) {
      throw SshException('SSH not connected', ErrorCode.sessionNotFound);
    }

    final oldPathPtr = oldPath.toNativeUtf8().cast<Utf8>();
    final newPathPtr = newPath.toNativeUtf8().cast<Utf8>();

    try {
      final errorCode = NativeSshBindings.sftpRename(
        _sshClient.sessionId!,
        oldPathPtr,
        newPathPtr,
      );

      if (errorCode != ErrorCode.success) {
        throw SshException('Rename failed', errorCode);
      }
    } finally {
      malloc.free(oldPathPtr);
      malloc.free(newPathPtr);
    }
  }

  /// Get file or directory information
  Future<FileInfo> stat(String path) async {
    if (_sshClient.sessionId == null) {
      throw SshException('SSH not connected', ErrorCode.sessionNotFound);
    }

    final pathPtr = path.toNativeUtf8().cast<Utf8>();
    final fileInfoPtr = malloc<CFileInfo>();

    try {
      final errorCode = NativeSshBindings.sftpStat(
        _sshClient.sessionId!,
        pathPtr,
        fileInfoPtr,
      );

      if (errorCode != ErrorCode.success) {
        throw SshException('Stat failed', errorCode);
      }

      final fileInfo = FileInfo(
        name: fileInfoPtr.ref.name.cast<Utf8>().toDartString(),
        size: fileInfoPtr.ref.size,
        isDir: fileInfoPtr.ref.isDir != 0,
        permissions: fileInfoPtr.ref.permissions,
        modified: DateTime.fromMillisecondsSinceEpoch(fileInfoPtr.ref.modified * 1000),
      );

      // Free the name string allocated by Rust
      NativeSshBindings.freeString(fileInfoPtr.ref.name.cast<Utf8>());

      return fileInfo;
    } finally {
      malloc.free(pathPtr);
      malloc.free(fileInfoPtr);
    }
  }
}

// Note: Using extensions from package:ffi for string conversion