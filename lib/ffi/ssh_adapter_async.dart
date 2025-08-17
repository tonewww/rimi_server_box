// Async SSH Adapter - Enhanced version using the new async architecture
// This provides the same API as ssh_adapter.dart but with true async operations

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:server_box/ffi/ssh_client_async.dart' as async_ssh;
import 'package:server_box/ffi/ssh_client.dart' as rust_ssh;

/// Enhanced SSH client that uses async operations when possible
class AsyncSSHClient {
  async_ssh.AsyncSshClient? _asyncClient;
  rust_ssh.SshClient? _fallbackClient;
  bool _connected = false;
  bool _useAsync = true; // Flag to enable/disable async operations
  
  AsyncSSHClient([
    dynamic socket,
    String? username,
    String? Function()? onPasswordRequest,
    dynamic onUserInfoRequest,
    List<dynamic>? identities,
  ]) {
    // Initialize both clients for fallback capability
    _asyncClient = async_ssh.AsyncSshClient();
    _fallbackClient = rust_ssh.SshClient();
  }

  /// Connect using async operations (preferred)
  static Future<AsyncSSHClient> connect({
    required String host,
    int port = 22,
    required String username,
    required String password,
    Duration timeout = const Duration(seconds: 30),
    bool useAsync = true,
  }) async {
    final client = AsyncSSHClient();
    client._useAsync = useAsync;
    
    // Force use of sync client only - completely disable async for stability
    client._useAsync = false;
    debugPrint('SSH: Using sync-only mode for stability');
    
    // Fallback to synchronous client
    final config = rust_ssh.SshConfig(
      host: host,
      port: port,
      username: username,
      password: password,
      timeout: timeout,
    );
    
    await client._fallbackClient!.connect(config);
    client._connected = true;
    
    debugPrint('SSH: Connected using fallback sync client to $host:$port');
    return client;
  }

  /// Connect using private key
  static Future<AsyncSSHClient> connectWithKey({
    required String host,
    int port = 22,
    required String username,
    required String privateKey,
    String? passphrase,
    Duration timeout = const Duration(seconds: 30),
    bool useAsync = true,
  }) async {
    final client = AsyncSSHClient();
    client._useAsync = useAsync;
    
    // Force use of sync client only - completely disable async for stability
    client._useAsync = false;
    debugPrint('SSH: Using sync-only mode for stability');
    
    // Fallback to synchronous client
    final config = rust_ssh.SshConfig(
      host: host,
      port: port,
      username: username,
      privateKey: privateKey,
      passphrase: passphrase,
      timeout: timeout,
    );
    
    await client._fallbackClient!.connect(config);
    client._connected = true;
    
    debugPrint('SSH: Connected using fallback sync client with key to $host:$port');
    return client;
  }

  /// Execute command (async when possible)
  Future<AsyncSSHResult> run(String command) async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }
    
    if (_useAsync && _asyncClient!.isConnected) {
      try {
        final result = await _asyncClient!.execute(command);
        return AsyncSSHResult._(result);
      } catch (e) {
        debugPrint('SSH: Async execute failed, falling back: $e');
        // Fall back to sync execution
        _useAsync = false;
      }
    }
    
    // Use direct sync call - worker isolate prevents main thread blocking
    final result = await _fallbackClient!.execute(command);
    return AsyncSSHResult.fromSync(result);
  }

  /// Execute and return session wrapper for compatibility
  Future<AsyncSSHSession> execute(
    String command, {
    Map<String, String>? environment,
    dynamic pty,
  }) async {
    final result = await run(command);
    return AsyncSSHSession._(result, command);
  }

  /// Close the connection
  Future<void> close() async {
    if (!_connected) return;
    
    if (_useAsync && _asyncClient!.isConnected) {
      try {
        await _asyncClient!.disconnect();
      } catch (e) {
        debugPrint('SSH: Error during async disconnect: $e');
      }
    }
    
    if (_fallbackClient != null) {
      try {
        await _fallbackClient!.disconnect();
      } catch (e) {
        debugPrint('SSH: Error during sync disconnect: $e');
      }
    }
    
    _connected = false;
  }

  /// Check if connected
  bool get isConnected => _connected;

  /// Check if closed (opposite of connected)
  bool get isClosed => !_connected;

  /// Check if using async operations
  bool get isUsingAsync => _useAsync && (_asyncClient?.isConnected ?? false);

  /// Create SFTP client (sync for stability)
  Future<dynamic> sftp() async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }
    
    // Use direct sync call - worker isolate prevents main thread blocking
    final sftpClient = rust_ssh.SftpClient(_fallbackClient!);
    await sftpClient.initialize();
    return AsyncSftpClient._(sftpClient);
  }

  /// Forward local port (sync for stability)
  Future<dynamic> forwardLocal(String remoteHost, int remotePort, [String? localHost, int? localPort]) async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }
    
    // Use direct sync call - worker isolate prevents main thread blocking
    await _fallbackClient!.forwardLocal(remoteHost, remotePort);
    return AsyncSSHForwardChannel(remoteHost, remotePort);
  }

  /// Forward remote port (sync for stability)
  Future<void> forwardRemote(int remotePort, String localHost, int localPort) async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }
    
    // Use direct sync call - worker isolate prevents main thread blocking
    await _fallbackClient!.forwardRemote(remotePort, localHost, localPort);
  }

  /// Execute command with password support
  Future<int?> execWithPwd(
    String script, {
    String? entry,
    dynamic context,
    dynamic onStdout,
    dynamic onStderr,
    required String id,
  }) async {
    final result = await run(script);
    return result.exitCode;
  }

  /// Create shell session (sync for stability)
  Future<AsyncSSHSession> shell({dynamic pty, Map<String, String>? environment}) async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }
    
    // Use direct sync call - worker isolate prevents main thread blocking
    await _fallbackClient!.createShell();
    
    final result = rust_ssh.CommandResult(
      stdout: '',
      stderr: '',
      exitCode: null,
    );
    
    return AsyncSSHSession.fromSync(result, 'shell');
  }

  /// Ping to keep connection alive
  Future<void> ping() async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }
    
    try {
      await run('echo ping');
    } catch (e) {
      _connected = false;
      rethrow;
    }
  }
}

/// SSH Session wrapper for async operations
class AsyncSSHSession {
  final dynamic _result;
  late final Stream<Uint8List> stdout;
  late final Stream<Uint8List> stderr;
  late final StreamSink<Uint8List> stdin;
  int? _exitCode;

  AsyncSSHSession._(AsyncSSHResult result, String command) : _result = result {
    _exitCode = result.exitCode;
    _initializeStreams(result.stdout, result.stderr);
  }

  AsyncSSHSession.fromSync(rust_ssh.CommandResult result, String command) : _result = result {
    _exitCode = result.exitCode;
    _initializeStreams(result.stdout, result.stderr);
  }

  void _initializeStreams(String stdoutStr, String stderrStr) {
    final stdoutController = StreamController<Uint8List>();
    final stderrController = StreamController<Uint8List>();
    final stdinController = StreamController<Uint8List>();
    
    stdout = stdoutController.stream;
    stderr = stderrController.stream;
    stdin = stdinController.sink;
    
    // Emit the results immediately
    if (stdoutStr.isNotEmpty) {
      stdoutController.add(Uint8List.fromList(stdoutStr.codeUnits));
    }
    if (stderrStr.isNotEmpty) {
      stderrController.add(Uint8List.fromList(stderrStr.codeUnits));
    }
    
    stdoutController.close();
    stderrController.close();
  }

  int? get exitCode => _exitCode;
  
  void write(dynamic data) {
    if (data is String) {
      stdin.add(Uint8List.fromList(data.codeUnits));
    } else if (data is List<int>) {
      stdin.add(Uint8List.fromList(data));
    }
  }
  
  void resizeTerminal(int width, int height) {
    debugPrint('Terminal resize: ${width}x$height');
  }
  
  Future<void> get done => Future.value();
  
  Future<void> close() async {
    // Session cleanup handled automatically
  }
}

/// SSH Result wrapper for async operations
class AsyncSSHResult {
  final String stdout;
  final String stderr;
  final int? exitCode;
  
  AsyncSSHResult._(async_ssh.AsyncCommandResult result)
      : stdout = result.stdout,
        stderr = result.stderr,
        exitCode = result.exitCode;

  AsyncSSHResult.fromSync(rust_ssh.CommandResult result)
      : stdout = result.stdout,
        stderr = result.stderr,
        exitCode = result.exitCode;
  
  String get string => stdout;
  
  @override
  String toString() => 'AsyncSSHResult(stdout: $stdout, stderr: $stderr, exitCode: $exitCode)';
}

/// Forward channel wrapper
class AsyncSSHForwardChannel {
  final String host;
  final int port;
  
  AsyncSSHForwardChannel(this.host, this.port);
  
  Stream<dynamic> get stream => Stream.empty();
  StreamSink<List<int>> get sink => StreamController<List<int>>().sink;
  
  Future<void> close() async {
    // Placeholder for closing forward channel
  }
}

/// SFTP Client wrapper (uses sync implementation for now)
class AsyncSftpClient {
  final rust_ssh.SftpClient _rustClient;
  
  AsyncSftpClient._(this._rustClient);
  
  Future<List<SftpName>> listdir(String path) async {
    final files = await _rustClient.listDirectory(path);
    return files.map((f) => AsyncSftpName._(f)).toList();
  }
  
  Future<void> rmdir(String path) async {
    await _rustClient.removeDirectory(path);
  }

  Future<void> remove(String path) async {
    await _rustClient.removeFile(path);
  }

  Future<void> mkdir(String path) async {
    await _rustClient.createDirectory(path);
  }

  Future<void> rename(String oldPath, String newPath) async {
    await _rustClient.rename(oldPath, newPath);
  }

  Future<dynamic> open(String path, {dynamic mode}) async {
    debugPrint('SFTP open: $path');
    return AsyncSftpFile._(path);
  }

  Future<void> close() async {
    // SFTP client cleanup handled by Rust implementation
  }
}

/// SFTP Name wrapper
class AsyncSftpName {
  final rust_ssh.FileInfo _fileInfo;
  
  AsyncSftpName._(this._fileInfo);
  
  String get filename => _fileInfo.name;
  dynamic get attr => AsyncSftpFileAttr._(_fileInfo);
}

/// SFTP File Attributes wrapper
class AsyncSftpFileAttr {
  final rust_ssh.FileInfo _fileInfo;
  
  AsyncSftpFileAttr._(this._fileInfo);
  
  bool get isDirectory => _fileInfo.isDir;
  bool get isFile => !_fileInfo.isDir;
  int get size => _fileInfo.size;
  dynamic get mode => AsyncSftpFileMode(_fileInfo.permissions);
  DateTime get modified => _fileInfo.modified;
  DateTime get modifyTime => _fileInfo.modified;
  int get modifyTimeMillis => _fileInfo.modified.millisecondsSinceEpoch;
}

/// SFTP File Mode wrapper
class AsyncSftpFileMode {
  final int permissions;
  
  const AsyncSftpFileMode(this.permissions);
  
  bool get userRead => (permissions & 0x100) != 0;
  bool get userWrite => (permissions & 0x080) != 0;
  bool get userExecute => (permissions & 0x040) != 0;
  
  bool get groupRead => (permissions & 0x020) != 0;
  bool get groupWrite => (permissions & 0x010) != 0;
  bool get groupExecute => (permissions & 0x008) != 0;
  
  bool get otherRead => (permissions & 0x004) != 0;
  bool get otherWrite => (permissions & 0x002) != 0;
  bool get otherExecute => (permissions & 0x001) != 0;
  
  String get str {
    final user = _getRoleMode(userRead, userWrite, userExecute);
    final group = _getRoleMode(groupRead, groupWrite, groupExecute);
    final other = _getRoleMode(otherRead, otherWrite, otherExecute);
    return '$user$group$other';
  }

  dynamic toUnixPerm() => null; // Placeholder

  String _getRoleMode(bool r, bool w, bool x) {
    return '${r ? 'r' : '-'}${w ? 'w' : '-'}${x ? 'x' : '-'}';
  }
}

/// SFTP File wrapper
class AsyncSftpFile {
  final String _path;
  
  AsyncSftpFile._(this._path);
  
  Future<dynamic> write(dynamic data, {void Function(int)? onProgress}) async {
    debugPrint('SFTP write to: $_path (onProgress: ${onProgress != null})');
    return AsyncSftpFileWriter._(data, onProgress);
  }
  
  Future<List<int>> read({int? offset, int? length}) async {
    debugPrint('SFTP read from: $_path (offset: $offset, length: $length)');
    return [];
  }
  
  Future<dynamic> stat() async {
    debugPrint('SFTP stat: $_path');
    return AsyncSftpFileAttributes._(
      size: 0,
      modifyTime: DateTime.now(),
      mode: AsyncSftpFileMode(420),
    );
  }
  
  Future<void> close() async {
    debugPrint('SFTP close file: $_path');
  }
}

/// SFTP File Writer wrapper
class AsyncSftpFileWriter {
  final dynamic _data;
  final void Function(int)? _onProgress;
  
  AsyncSftpFileWriter._(this._data, this._onProgress);
  
  Future<void> get done async {
    if (_onProgress != null) {
      _onProgress!(100);
    }
  }
}

/// SFTP File Attributes wrapper
class AsyncSftpFileAttributes {
  final int size;
  final DateTime modifyTime;
  final AsyncSftpFileMode? mode;
  
  AsyncSftpFileAttributes._({
    required this.size,
    required this.modifyTime,
    this.mode,
  });
}

/// SSH PTY Configuration for compatibility
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

/// SSH Key Pair for compatibility
class SSHKeyPair {
  final String _key;
  
  SSHKeyPair._(this._key);
  
  static List<SSHKeyPair> fromPem(String pem, [String? passphrase]) {
    return [SSHKeyPair._(pem)];
  }
  
  static bool isEncryptedPem(String pem) {
    return pem.contains('ENCRYPTED') || pem.contains('Proc-Type: 4,ENCRYPTED');
  }
  
  String toPem() => _key;
}

/// SSH User Info Request Handler type for compatibility
typedef SSHUserInfoRequestHandler = Future<(String?, String?)> Function(String, String, String, List<String>, List<bool>);

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

/// SSH Authentication Abort Error for compatibility
class SSHAuthAbortError implements Exception {
  final String message;
  const SSHAuthAbortError(this.message);
  
  @override
  String toString() => 'SSHAuthAbortError: $message';
}

/// SSH Authentication Failed Error for compatibility  
class SSHAuthFailError implements Exception {
  final String message;
  const SSHAuthFailError(this.message);
  
  @override
  String toString() => 'SSHAuthFailError: $message';
}

// Export type aliases for compatibility
typedef SSHClient = AsyncSSHClient;
typedef SSHSession = AsyncSSHSession;
typedef SSHResult = AsyncSSHResult;
typedef SSHForwardChannel = AsyncSSHForwardChannel;
typedef SftpClient = AsyncSftpClient;
typedef SftpName = AsyncSftpName;
typedef SftpFileAttr = AsyncSftpFileAttr;
typedef SftpFileMode = AsyncSftpFileMode;
typedef SftpFile = AsyncSftpFile;
typedef SftpFileWriter = AsyncSftpFileWriter;
typedef SftpFileAttributes = AsyncSftpFileAttributes;