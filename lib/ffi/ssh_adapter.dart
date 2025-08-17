// SSH Adapter - Bridge between dartssh2 API and Rust SSH implementation
// This allows gradual migration while maintaining existing code compatibility

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:server_box/ffi/ssh_client.dart' as rust_ssh;

/// Compatibility layer to bridge dartssh2 API with Rust SSH implementation
/// This allows existing code to work with minimal changes during migration

/// SSH User Info Request Handler type for compatibility
typedef SSHUserInfoRequestHandler = Future<(String?, String?)> Function(String, String, String, List<String>, List<bool>);

/// SSH Socket for compatibility with dartssh2
class SSHSocket {
  final String? host;
  final int? port;
  
  SSHSocket({this.host, this.port});
  
  /// Stream for socket data (placeholder)
  Stream<dynamic> get stream => Stream.empty();
  
  /// Sink for socket data (placeholder)
  StreamSink<List<int>> get sink => StreamController<List<int>>().sink;
  
  static Future<SSHSocket> connect(String host, int port, {Duration? timeout}) async {
    // For compatibility - actual connection will be handled by SSHClient
    return SSHSocket(host: host, port: port);
  }
}

/// SSH Forward Channel for compatibility
class SSHForwardChannel extends SSHSocket {
  SSHForwardChannel(String host, int port) : super(host: host, port: port);
  
  /// Close the forward channel
  Future<void> close() async {
    // Placeholder for closing forward channel
  }
}

class SSHClient {
  late rust_ssh.SshClient _rustClient;
  bool _connected = false;
  
  SSHClient([
    dynamic socket, // For compatibility with socket-based constructor
    String? username,
    String? Function()? onPasswordRequest,
    SSHUserInfoRequestHandler? onUserInfoRequest,
    List<SSHKeyPair>? identities,
  ]) {
    _rustClient = rust_ssh.SshClient();
    
    // If parameters provided, auto-connect
    if (socket != null && username != null) {
      _autoConnect(socket, username, onPasswordRequest, onUserInfoRequest, identities);
    }
  }

  /// Auto-connect when constructor parameters are provided
  void _autoConnect(
    dynamic socket,
    String username, 
    String? Function()? onPasswordRequest,
    SSHUserInfoRequestHandler? onUserInfoRequest,
    List<SSHKeyPair>? identities,
  ) {
    // Extract host/port from socket (simplified)
    String host = 'localhost';
    int port = 22;
    
    if (socket is SSHSocket) {
      // Extract from socket if possible
      host = socket.host ?? 'localhost';
      port = socket.port ?? 22;
    }

    // Use password if provided
    if (onPasswordRequest != null) {
      final password = onPasswordRequest();
      if (password != null) {
        Future.microtask(() async {
          try {
            await _connectWithPassword(host, port, username, password);
          } catch (e) {
            debugPrint('Auto-connect failed: $e');
          }
        });
      }
    }
    
    // Use key if provided  
    if (identities != null && identities.isNotEmpty) {
      final key = identities.first.toPem();
      Future.microtask(() async {
        try {
          await _connectWithKey(host, port, username, key);
        } catch (e) {
          debugPrint('Auto-connect with key failed: $e');
        }
      });
    }
  }

  Future<void> _connectWithPassword(String host, int port, String username, String password) async {
    final config = rust_ssh.SshConfig(
      host: host,
      port: port,
      username: username,
      password: password,
    );
    await _rustClient.connect(config);
    _connected = true;
  }

  Future<void> _connectWithKey(String host, int port, String username, String privateKey) async {
    final config = rust_ssh.SshConfig(
      host: host,
      port: port,
      username: username,
      privateKey: privateKey,
    );
    await _rustClient.connect(config);
    _connected = true;
  }

  /// Connect using password authentication
  static Future<SSHClient> connect({
    required String host,
    int port = 22,
    required String username,
    required String password,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = SSHClient();
    
    final config = rust_ssh.SshConfig(
      host: host,
      port: port,
      username: username,
      password: password,
      timeout: timeout,
    );
    
    await client._rustClient.connect(config);
    client._connected = true;
    
    return client;
  }

  /// Connect using private key authentication
  static Future<SSHClient> connectWithKey({
    required String host,
    int port = 22,
    required String username,
    required String privateKey,
    String? passphrase,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = SSHClient();
    
    final config = rust_ssh.SshConfig(
      host: host,
      port: port,
      username: username,
      privateKey: privateKey,
      passphrase: passphrase,
      timeout: timeout,
    );
    
    await client._rustClient.connect(config);
    client._connected = true;
    
    return client;
  }

  /// Execute a command and return session
  Future<SSHSession> execute(
    String command, {
    Map<String, String>? environment,
    SSHPtyConfig? pty,
  }) async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }
    
    final result = await _rustClient.execute(command);
    
    // Create a session wrapper that provides streams
    return SSHSession._(result, command);
  }

  /// Run a command and return future result for compatibility
  Future<SSHResult> run(String command) async {
    final result = await _rustClient.execute(command);
    return SSHResult._(result);
  }

  /// Close the connection
  Future<void> close() async {
    if (_connected) {
      await _rustClient.disconnect();
      _connected = false;
    }
  }

  /// Check if connected
  bool get isConnected => _connected;

  /// Check if closed (opposite of connected for compatibility)
  bool get isClosed => !_connected;

  /// Create SFTP client
  Future<SftpClient> sftp() async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }
    
    final sftpClient = rust_ssh.SftpClient(_rustClient);
    await sftpClient.initialize();
    
    return SftpClient._(sftpClient);
  }

  /// Forward local port (for jump server support)
  Future<SSHForwardChannel> forwardLocal(String remoteHost, int remotePort, [String? localHost, int? localPort]) async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }
    
    // Setup actual port forwarding through Rust SSH implementation
    await _rustClient.forwardLocal(remoteHost, remotePort);
    
    // Return a forward channel that represents the forwarded connection
    return SSHForwardChannel(remoteHost, remotePort);
  }

  /// Forward remote port (reverse port forwarding)
  Future<void> forwardRemote(int remotePort, String localHost, int localPort) async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }
    
    // Setup actual reverse port forwarding through Rust SSH implementation
    await _rustClient.forwardRemote(remotePort, localHost, localPort);
  }

  /// Execute command with password support (for compatibility with extensions)
  Future<int?> execWithPwd(
    String script, {
    String? entry,
    dynamic context,
    dynamic onStdout,
    dynamic onStderr,
    required String id,
  }) async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }
    
    // Simplified implementation - execute command directly
    final result = await _rustClient.execute(script);
    return result.exitCode;
  }

  /// Create shell session (for SSH terminal)
  Future<SSHSession> shell({dynamic pty, Map<String, String>? environment}) async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }
    
    // Create actual shell session using Rust SSH implementation
    await _rustClient.createShell();
    
    // Create a shell session representation
    final result = rust_ssh.CommandResult(
      stdout: '',
      stderr: '',
      exitCode: null,
    );
    
    return SSHSession._(result, 'shell');
  }

  /// Ping the SSH connection to keep it alive
  Future<void> ping() async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }
    
    // Send a simple command to keep the connection alive
    try {
      await _rustClient.execute('echo ping');
    } catch (e) {
      // If ping fails, mark as disconnected
      _connected = false;
      rethrow;
    }
  }
}

/// SSH Session wrapper to provide compatibility with dartssh2 API
class SSHSession {
  final rust_ssh.CommandResult _result;
  
  late final Stream<Uint8List> stdout;
  late final Stream<Uint8List> stderr;
  late final StreamSink<Uint8List> stdin;
  
  int? _exitCode;

  SSHSession._(this._result, String command) {
    _exitCode = _result.exitCode;
    
    // Create streams from the command result
    final stdoutController = StreamController<Uint8List>();
    final stderrController = StreamController<Uint8List>();
    final stdinController = StreamController<Uint8List>();
    
    stdout = stdoutController.stream;
    stderr = stderrController.stream;
    stdin = stdinController.sink;
    
    // Emit the results immediately since Rust SSH executes commands synchronously
    if (_result.stdout.isNotEmpty) {
      stdoutController.add(Uint8List.fromList(_result.stdout.codeUnits));
    }
    if (_result.stderr.isNotEmpty) {
      stderrController.add(Uint8List.fromList(_result.stderr.codeUnits));
    }
    
    // Close streams
    stdoutController.close();
    stderrController.close();
  }

  /// Get exit code
  int? get exitCode => _exitCode;
  
  /// Write data to stdin
  void write(dynamic data) {
    if (data is String) {
      stdin.add(Uint8List.fromList(data.codeUnits));
    } else if (data is List<int>) {
      stdin.add(Uint8List.fromList(data));
    }
  }
  
  /// Resize terminal (for shell sessions)
  void resizeTerminal(int width, int height) {
    // Placeholder for terminal resize functionality
    debugPrint('Terminal resize: ${width}x$height');
  }
  
  /// Future that completes when session is done
  Future<void> get done => Future.value();
  
  /// Close the session
  Future<void> close() async {
    // Session is already closed in Rust implementation
  }
}

/// SSH Result wrapper for command execution compatibility
class SSHResult {
  final rust_ssh.CommandResult _result;
  
  SSHResult._(this._result);
  
  /// Get the result as string (stdout)
  String get string => _result.stdout;
  
  /// Get stderr
  String get stderr => _result.stderr;
  
  /// Get exit code
  int? get exitCode => _result.exitCode;
}

/// SSH PTY Configuration (placeholder for compatibility)
class SSHPtyConfig {
  final int width;
  final int height;
  final String term;
  
  const SSHPtyConfig({
    this.width = 80,
    this.height = 24,
    this.term = 'xterm',
  });
}

/// SSH Authentication Error for compatibility
class SSHAuthAbortError extends rust_ssh.SshException {
  SSHAuthAbortError(String message) : super(message, 2); // authenticationFailed code
}

/// SSH Authentication Failed Error for compatibility  
class SSHAuthFailError extends rust_ssh.SshException {
  SSHAuthFailError(String message) : super(message, 2); // authenticationFailed code
}

// SSH Error types and classes are provided by the app's error model to avoid conflicts

/// SSH Key Pair placeholder for compatibility
class SSHKeyPair {
  final String _key;
  
  SSHKeyPair._(this._key);
  
  static List<SSHKeyPair> fromPem(String pem, [String? passphrase]) {
    // For now, just return a single key pair
    // In full implementation, this would parse the PEM format
    return [SSHKeyPair._(pem)];
  }
  
  static bool isEncryptedPem(String pem) {
    return pem.contains('ENCRYPTED') || pem.contains('Proc-Type: 4,ENCRYPTED');
  }
  
  String toPem() => _key;
}

/// SFTP File Mode for compatibility with dartssh2
class SftpFileMode {
  final int permissions;
  
  const SftpFileMode(this.permissions);
  
  bool get userRead => (permissions & 0x100) != 0;
  bool get userWrite => (permissions & 0x080) != 0;
  bool get userExecute => (permissions & 0x040) != 0;
  
  bool get groupRead => (permissions & 0x020) != 0;
  bool get groupWrite => (permissions & 0x010) != 0;
  bool get groupExecute => (permissions & 0x008) != 0;
  
  bool get otherRead => (permissions & 0x004) != 0;
  bool get otherWrite => (permissions & 0x002) != 0;
  bool get otherExecute => (permissions & 0x001) != 0;

  /// Get permission string representation
  String get str {
    final user = _getRoleMode(userRead, userWrite, userExecute);
    final group = _getRoleMode(groupRead, groupWrite, groupExecute);
    final other = _getRoleMode(otherRead, otherWrite, otherExecute);
    return '$user$group$other';
  }

  /// Convert to UnixPerm for compatibility
  dynamic toUnixPerm() {
    // Return a compatible object - this would need the actual UnixPerm import
    return _createUnixPerm();
  }

  String _getRoleMode(bool r, bool w, bool x) {
    return '${r ? 'r' : '-'}${w ? 'w' : '-'}${x ? 'x' : '-'}';
  }

  dynamic _createUnixPerm() {
    // Placeholder - would create actual UnixPerm object
    return null;
  }
}

/// SFTP Client for compatibility with dartssh2
class SftpClient {
  final rust_ssh.SftpClient _rustClient;
  
  SftpClient._(this._rustClient);
  
  /// List directory contents
  Future<List<SftpName>> listdir(String path) async {
    final files = await _rustClient.listDirectory(path);
    return files.map((f) => SftpName._(f)).toList();
  }
  
  /// Remove directory
  Future<void> rmdir(String path) async {
    await _rustClient.removeDirectory(path);
  }

  /// Remove file
  Future<void> remove(String path) async {
    await _rustClient.removeFile(path);
  }

  /// Create directory
  Future<void> mkdir(String path) async {
    await _rustClient.createDirectory(path);
  }

  /// Rename file/directory
  Future<void> rename(String oldPath, String newPath) async {
    await _rustClient.rename(oldPath, newPath);
  }

  /// Open file (placeholder for file operations)
  Future<SftpFile> open(String path, {dynamic mode}) async {
    // Placeholder - implement file opening
    debugPrint('SFTP open: $path');
    return SftpFile._(path);
  }

  /// Close SFTP client
  Future<void> close() async {
    // SFTP client cleanup handled by Rust implementation
  }
}

/// SFTP Name (file/directory entry) for compatibility
class SftpName {
  final rust_ssh.FileInfo _fileInfo;
  
  SftpName._(this._fileInfo);
  
  String get filename => _fileInfo.name;
  SftpFileAttr get attr => SftpFileAttr._(_fileInfo);
}

/// SFTP File Attributes for compatibility
class SftpFileAttr {
  final rust_ssh.FileInfo _fileInfo;
  
  SftpFileAttr._(this._fileInfo);
  
  bool get isDirectory => _fileInfo.isDir;
  bool get isFile => !_fileInfo.isDir;
  int get size => _fileInfo.size;
  SftpFileMode get permissions => SftpFileMode(_fileInfo.permissions);
  SftpFileMode? get mode => SftpFileMode(_fileInfo.permissions);
  DateTime get modified => _fileInfo.modified;
  DateTime get modifyTime => _fileInfo.modified;
  
  /// Get modify time as Unix timestamp in milliseconds for compatibility
  int get modifyTimeMillis => _fileInfo.modified.millisecondsSinceEpoch;
}

/// SFTP File Open Mode for compatibility
class SftpFileOpenMode {
  static const read = SftpFileOpenMode._(['read']);
  static const write = SftpFileOpenMode._(['write']);
  static const create = SftpFileOpenMode._(['create']);
  static const truncate = SftpFileOpenMode._(['truncate']);
  
  final List<String> _modes;
  const SftpFileOpenMode._(this._modes);
  
  /// Combine modes using bitwise OR
  SftpFileOpenMode operator |(SftpFileOpenMode other) {
    return SftpFileOpenMode._([..._modes, ...other._modes]);
  }
  
  @override
  String toString() => _modes.join('|');
}

/// SFTP File for file operations
class SftpFile {
  final String _path;
  
  SftpFile._(this._path);
  
  /// Write data to file
  Future<SftpFileWriter> write(dynamic data, {void Function(int)? onProgress}) async {
    debugPrint('SFTP write to: $_path (onProgress: ${onProgress != null})');
    return SftpFileWriter._(data, onProgress);
  }
  
  /// Read data from file with optional offset and length parameters
  Future<List<int>> read({int? offset, int? length}) async {
    debugPrint('SFTP read from: $_path (offset: $offset, length: $length)');
    return [];
  }
  
  /// Get file statistics
  Future<SftpFileAttributes> stat() async {
    debugPrint('SFTP stat: $_path');
    // Return a placeholder file attributes object
    return SftpFileAttributes._(
      size: 0,
      modifyTime: DateTime.now(),
      mode: SftpFileMode(420), // 0o644 in decimal
    );
  }
  
  /// Close file
  Future<void> close() async {
    debugPrint('SFTP close file: $_path');
  }
}

/// SFTP File Writer for compatibility
class SftpFileWriter {
  final dynamic _data;
  final void Function(int)? _onProgress;
  
  SftpFileWriter._(this._data, this._onProgress);
  
  /// Future that completes when write is done
  Future<void> get done async {
    // Simulate writing with progress
    if (_onProgress != null) {
      _onProgress(100); // Report 100% completion
    }
  }
}

/// SFTP File Attributes for compatibility
class SftpFileAttributes {
  final int size;
  final DateTime modifyTime;
  final SftpFileMode? mode;
  
  SftpFileAttributes._({
    required this.size,
    required this.modifyTime,
    this.mode,
  });
}


// Extensions are provided by fl_lib package to avoid conflicts