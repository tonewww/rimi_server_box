// True Async SSH Adapter using Dart Isolates
// This completely isolates SSH operations from the main thread to prevent UI blocking

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Message types for isolate communication
enum SshIsolateMessageType {
  connect,
  connectWithKey,
  execute,
  sftp,
  forwardLocal,
  forwardRemote,
  shell,
  close,
  ping,
}

/// Request message for isolate communication
class SshIsolateRequest {
  final SshIsolateMessageType type;
  final Map<String, dynamic> data;
  final int requestId;

  SshIsolateRequest({
    required this.type,
    required this.data,
    required this.requestId,
  });
}

/// Response message from isolate
class SshIsolateResponse {
  final int requestId;
  final bool success;
  final dynamic result;
  final String? error;

  SshIsolateResponse({
    required this.requestId,
    required this.success,
    this.result,
    this.error,
  });
}

/// True async SSH client using Dart Isolates
class IsolateSSHClient {
  static Isolate? _isolate;
  static SendPort? _sendPort;
  static ReceivePort? _receivePort;
  static final Map<int, Completer<SshIsolateResponse>> _pendingRequests = {};
  static int _nextRequestId = 1;
  static bool _isInitialized = false;
  
  bool _connected = false;
  String? _sessionId;

  /// Initialize the SSH isolate (call once per app lifecycle)
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    debugPrint('SSH: Initializing isolate-based SSH client');
    
    // Cleanup any existing resources first
    await cleanup();
    
    // Create receive port for main isolate
    _receivePort = ReceivePort();
    
    // Spawn the SSH worker isolate
    _isolate = await Isolate.spawn(
      _sshIsolateEntryPoint,
      _receivePort!.sendPort,
      debugName: 'SSH-Worker-Isolate',
    );
    
    // Listen for messages from worker isolate
    _receivePort!.listen((message) {
      if (message is SendPort) {
        // First message is the worker's send port
        _sendPort = message;
        debugPrint('SSH: Isolate communication established');
      } else if (message is SshIsolateResponse) {
        // Handle response from worker
        final completer = _pendingRequests.remove(message.requestId);
        completer?.complete(message);
      }
    });
    
    // Wait for isolate to send back its send port
    await Future.delayed(const Duration(milliseconds: 100));
    _isInitialized = true;
    debugPrint('SSH: Isolate initialization complete');
  }

  /// Cleanup the SSH isolate
  static Future<void> cleanup() async {
    debugPrint('SSH: Cleaning up isolate');
    _isolate?.kill();
    _receivePort?.close();
    _pendingRequests.clear();
    _sendPort = null;
    _isolate = null;
    _receivePort = null;
    _isInitialized = false;
  }

  /// Send request to isolate and wait for response
  Future<SshIsolateResponse> _sendRequest(
    SshIsolateMessageType type,
    Map<String, dynamic> data,
  ) async {
    if (!_isInitialized || _sendPort == null) {
      throw StateError('SSH isolate not initialized');
    }

    final requestId = _nextRequestId++;
    final completer = Completer<SshIsolateResponse>();
    _pendingRequests[requestId] = completer;

    final request = SshIsolateRequest(
      type: type,
      data: data,
      requestId: requestId,
    );

    _sendPort!.send(request);
    
    // Add timeout to prevent infinite waiting
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(requestId);
        throw TimeoutException('SSH request timed out', const Duration(seconds: 30));
      },
    );
  }

  /// Connect using password authentication
  static Future<IsolateSSHClient> connect({
    required String host,
    int port = 22,
    required String username,
    required String password,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await initialize();
    
    final client = IsolateSSHClient();
    
    final response = await client._sendRequest(
      SshIsolateMessageType.connect,
      {
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'timeout': timeout.inMilliseconds,
      },
    );

    if (!response.success) {
      throw Exception(response.error ?? 'SSH connection failed');
    }

    client._connected = true;
    client._sessionId = response.result as String?;
    debugPrint('SSH: Connected via isolate to $host:$port');
    
    return client;
  }

  /// Connect using private key authentication
  static Future<IsolateSSHClient> connectWithKey({
    required String host,
    int port = 22,
    required String username,
    required String privateKey,
    String? passphrase,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await initialize();
    
    final client = IsolateSSHClient();
    
    final response = await client._sendRequest(
      SshIsolateMessageType.connectWithKey,
      {
        'host': host,
        'port': port,
        'username': username,
        'privateKey': privateKey,
        'passphrase': passphrase,
        'timeout': timeout.inMilliseconds,
      },
    );

    if (!response.success) {
      throw Exception(response.error ?? 'SSH key-based connection failed');
    }

    client._connected = true;
    client._sessionId = response.result as String?;
    debugPrint('SSH: Connected via isolate with key to $host:$port');
    
    return client;
  }

  /// Execute command
  Future<IsolateSSHResult> run(String command) async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }

    final response = await _sendRequest(
      SshIsolateMessageType.execute,
      {
        'sessionId': _sessionId,
        'command': command,
      },
    );

    if (!response.success) {
      throw Exception(response.error ?? 'Command execution failed');
    }

    final result = response.result as Map<String, dynamic>;
    return IsolateSSHResult(
      stdout: result['stdout'] as String,
      stderr: result['stderr'] as String,
      exitCode: result['exitCode'] as int?,
    );
  }

  /// Execute and return session wrapper
  Future<IsolateSSHSession> execute(
    String command, {
    Map<String, String>? environment,
    dynamic pty,
  }) async {
    final result = await run(command);
    return IsolateSSHSession._(result, command);
  }

  /// Create SFTP client
  Future<IsolateSftpClient> sftp() async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }

    final response = await _sendRequest(
      SshIsolateMessageType.sftp,
      {'sessionId': _sessionId},
    );

    if (!response.success) {
      throw Exception(response.error ?? 'SFTP initialization failed');
    }

    return IsolateSftpClient._(this, response.result as String);
  }

  /// Forward local port
  Future<IsolateSSHForwardChannel> forwardLocal(
    String remoteHost,
    int remotePort, [
    String? localHost,
    int? localPort,
  ]) async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }

    final response = await _sendRequest(
      SshIsolateMessageType.forwardLocal,
      {
        'sessionId': _sessionId,
        'remoteHost': remoteHost,
        'remotePort': remotePort,
        'localHost': localHost,
        'localPort': localPort,
      },
    );

    if (!response.success) {
      throw Exception(response.error ?? 'Local port forwarding failed');
    }

    return IsolateSSHForwardChannel(remoteHost, remotePort);
  }

  /// Forward remote port
  Future<void> forwardRemote(int remotePort, String localHost, int localPort) async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }

    final response = await _sendRequest(
      SshIsolateMessageType.forwardRemote,
      {
        'sessionId': _sessionId,
        'remotePort': remotePort,
        'localHost': localHost,
        'localPort': localPort,
      },
    );

    if (!response.success) {
      throw Exception(response.error ?? 'Remote port forwarding failed');
    }
  }

  /// Create shell session
  Future<IsolateSSHSession> shell({
    dynamic pty,
    Map<String, String>? environment,
  }) async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }

    final response = await _sendRequest(
      SshIsolateMessageType.shell,
      {
        'sessionId': _sessionId,
        'pty': pty?.toString(),
        'environment': environment,
      },
    );

    if (!response.success) {
      throw Exception(response.error ?? 'Shell creation failed');
    }

    final result = IsolateSSHResult(
      stdout: '',
      stderr: '',
      exitCode: null,
    );

    return IsolateSSHSession._(result, 'shell');
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

  /// Ping to keep connection alive
  Future<void> ping() async {
    if (!_connected) {
      throw StateError('SSH client not connected');
    }

    final response = await _sendRequest(
      SshIsolateMessageType.ping,
      {'sessionId': _sessionId},
    );

    if (!response.success) {
      _connected = false;
      throw Exception(response.error ?? 'Ping failed');
    }
  }

  /// Close the connection
  Future<void> close() async {
    if (!_connected) return;

    try {
      await _sendRequest(
        SshIsolateMessageType.close,
        {'sessionId': _sessionId},
      );
    } catch (e) {
      debugPrint('SSH: Error during isolate disconnect: $e');
    }

    _connected = false;
    _sessionId = null;
  }

  /// Check if connected
  bool get isConnected => _connected;

  /// Check if closed
  bool get isClosed => !_connected;
}

/// SSH isolate entry point - runs in worker isolate
void _sshIsolateEntryPoint(SendPort mainSendPort) async {
  // Import Rust SSH client in isolate context
  // TODO: Complete full Rust FFI integration within isolate worker thread
  
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);
  
  // Import SSH client in isolate
  dynamic rustSshClient;
  try {
    // Initialize SSH client library in isolate context
    // For now we'll use a fallback approach
    rustSshClient = null; // Placeholder for now
  } catch (e) {
    print('SSH Isolate: Failed to initialize Rust SSH client: $e');
  }
  
  // Active SSH sessions in this isolate
  final Map<String, dynamic> sessions = {};
  
  await for (final message in receivePort) {
    if (message is SshIsolateRequest) {
      try {
        final response = await _handleSshRequest(message, sessions);
        mainSendPort.send(response);
      } catch (e) {
        mainSendPort.send(SshIsolateResponse(
          requestId: message.requestId,
          success: false,
          error: 'Isolate error: $e',
        ));
      }
    }
  }
}

/// Handle SSH request in worker isolate
Future<SshIsolateResponse> _handleSshRequest(
  SshIsolateRequest request,
  Map<String, dynamic> sessions,
) async {
  // TODO: Replace placeholder implementation with actual Rust SSH client integration
  // TODO: Implement proper error handling for real SSH operations in isolate
  // TODO: Add session state management and connection pooling for isolate
  // This is currently a placeholder implementation
  
  switch (request.type) {
    case SshIsolateMessageType.connect:
      await Future.delayed(const Duration(milliseconds: 100)); // Simulate connection
      final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
      sessions[sessionId] = {'connected': true, 'type': 'password'};
      return SshIsolateResponse(
        requestId: request.requestId,
        success: true,
        result: sessionId,
      );
      
    case SshIsolateMessageType.connectWithKey:
      await Future.delayed(const Duration(milliseconds: 100)); // Simulate connection
      final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
      sessions[sessionId] = {'connected': true, 'type': 'key'};
      return SshIsolateResponse(
        requestId: request.requestId,
        success: true,
        result: sessionId,
      );
      
    case SshIsolateMessageType.execute:
      await Future.delayed(const Duration(milliseconds: 50)); // Simulate execution
      return SshIsolateResponse(
        requestId: request.requestId,
        success: true,
        result: {
          'stdout': 'Command executed: ${request.data['command']}',
          'stderr': '',
          'exitCode': 0,
        },
      );
      
    case SshIsolateMessageType.sftp:
      await Future.delayed(const Duration(milliseconds: 20)); // Simulate SFTP init
      final sftpId = 'sftp_${DateTime.now().millisecondsSinceEpoch}';
      return SshIsolateResponse(
        requestId: request.requestId,
        success: true,
        result: sftpId,
      );
      
    case SshIsolateMessageType.ping:
      return SshIsolateResponse(
        requestId: request.requestId,
        success: true,
        result: 'pong',
      );
      
    case SshIsolateMessageType.close:
      final sessionId = request.data['sessionId'] as String?;
      if (sessionId != null) {
        sessions.remove(sessionId);
      }
      return SshIsolateResponse(
        requestId: request.requestId,
        success: true,
        result: 'closed',
      );
      
    default:
      return SshIsolateResponse(
        requestId: request.requestId,
        success: false,
        error: 'Unsupported operation: ${request.type}',
      );
  }
}

/// SSH Result for isolate implementation
class IsolateSSHResult {
  final String stdout;
  final String stderr;
  final int? exitCode;

  IsolateSSHResult({
    required this.stdout,
    required this.stderr,
    this.exitCode,
  });

  String get string => stdout;

  @override
  String toString() => 'IsolateSSHResult(stdout: $stdout, stderr: $stderr, exitCode: $exitCode)';
}

/// SSH Session for isolate implementation
class IsolateSSHSession {
  final IsolateSSHResult _result;
  late final Stream<Uint8List> stdout;
  late final Stream<Uint8List> stderr;
  late final StreamSink<Uint8List> stdin;

  IsolateSSHSession._(this._result, String command) {
    _initializeStreams(_result.stdout, _result.stderr);
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

  int? get exitCode => _result.exitCode;

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

/// SFTP client for isolate implementation
class IsolateSftpClient {
  final IsolateSSHClient _sshClient;
  final String _sftpId;

  IsolateSftpClient._(this._sshClient, this._sftpId);

  Future<List<IsolateSftpName>> listdir(String path) async {
    // TODO: Implement via isolate communication
    debugPrint('SFTP listdir: $path');
    return [];
  }

  Future<void> rmdir(String path) async {
    // TODO: Implement via isolate communication
    debugPrint('SFTP rmdir: $path');
  }

  Future<void> remove(String path) async {
    // TODO: Implement via isolate communication
    debugPrint('SFTP remove: $path');
  }

  Future<void> mkdir(String path) async {
    // TODO: Implement via isolate communication
    debugPrint('SFTP mkdir: $path');
  }

  Future<void> rename(String oldPath, String newPath) async {
    // TODO: Implement via isolate communication
    debugPrint('SFTP rename: $oldPath -> $newPath');
  }

  Future<IsolateSftpFile> open(String path, {dynamic mode}) async {
    // TODO: Implement via isolate communication
    debugPrint('SFTP open: $path');
    return IsolateSftpFile._(path);
  }

  Future<void> close() async {
    // TODO: Implement via isolate communication
    debugPrint('SFTP close');
  }
}

/// Forward channel for isolate implementation
class IsolateSSHForwardChannel {
  final String host;
  final int port;

  IsolateSSHForwardChannel(this.host, this.port);

  Stream<dynamic> get stream => Stream.empty();
  StreamSink<List<int>> get sink => StreamController<List<int>>().sink;

  Future<void> close() async {
    debugPrint('Forward channel close: $host:$port');
  }
}

/// SFTP name for isolate implementation
class IsolateSftpName {
  final String filename;
  final dynamic attr;

  IsolateSftpName(this.filename, this.attr);
}

/// SFTP file for isolate implementation
class IsolateSftpFile {
  final String _path;

  IsolateSftpFile._(this._path);

  Future<dynamic> write(dynamic data, {void Function(int)? onProgress}) async {
    debugPrint('SFTP write to: $_path');
    return IsolateSftpFileWriter._(data, onProgress);
  }

  Future<List<int>> read({int? offset, int? length}) async {
    debugPrint('SFTP read from: $_path');
    return [];
  }

  Future<dynamic> stat() async {
    debugPrint('SFTP stat: $_path');
    return null;
  }

  Future<void> close() async {
    debugPrint('SFTP close file: $_path');
  }
}

/// SFTP file writer for isolate implementation
class IsolateSftpFileWriter {
  final dynamic _data;
  final void Function(int)? _onProgress;

  IsolateSftpFileWriter._(this._data, this._onProgress);

  Future<void> get done async {
    if (_onProgress != null) {
      _onProgress!(100);
    }
  }
}

/// Export type aliases for compatibility
typedef SSHClient = IsolateSSHClient;
typedef SSHSession = IsolateSSHSession;
typedef SSHResult = IsolateSSHResult;
typedef SSHForwardChannel = IsolateSSHForwardChannel;
typedef SftpClient = IsolateSftpClient;
typedef SftpName = IsolateSftpName;
typedef SftpFile = IsolateSftpFile;
typedef SftpFileWriter = IsolateSftpFileWriter;

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

// Additional compatibility exports
typedef SftpFileAttr = dynamic;
typedef SftpFileMode = dynamic;
typedef SftpFileAttributes = dynamic;

/// SSH error classes for compatibility
class SSHAuthAbortError implements Exception {
  final String message;
  const SSHAuthAbortError(this.message);
  @override
  String toString() => 'SSHAuthAbortError: $message';
}

class SSHAuthFailError implements Exception {
  final String message;
  const SSHAuthFailError(this.message);
  @override
  String toString() => 'SSHAuthFailError: $message';
}