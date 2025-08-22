import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_lib/fl_lib.dart';
import 'package:server_box/core/libssh2/libssh2_client.dart';
import 'package:server_box/core/libssh2/ssh_logger.dart';

/// Adapter to make LibSSH2Client compatible with dartssh2 interface
/// This allows gradual migration from dartssh2 to libssh2
class SSHClient {
  final LibSSH2Client _client;
  final SSHLogger logger;
  
  SSHClient._({
    required LibSSH2Client client,
    required this.logger,
  }) : _client = client;
  
  /// Create SSH client from Socket (compatibility method)
  factory SSHClient(
    dynamic socket, {
    required String username,
    String Function()? onPasswordRequest,
    List<dynamic>? identities,
    dynamic onUserInfoRequest,
  }) {
    // This factory is for compatibility with dartssh2
    // In reality, we'll use the connect method below
    throw UnimplementedError('Use SSHClient.connect instead');
  }
  
  /// Connect to SSH server using libssh2
  static Future<SSHClient> connect(
    String host,
    int port, {
    required String username,
    String? password,
    String? privateKeyPath,
    String? passphrase,
    Duration timeout = const Duration(seconds: 30),
    SSHLogger? logger,
  }) async {
    logger ??= SSHLogger();
    logger.info('[ADAPTER] Creating SSH client for $username@$host:$port');
    
    final client = LibSSH2Client(
      host: host,
      port: port,
      username: username,
      password: password,
      privateKeyPath: privateKeyPath,
      passphrase: passphrase,
      timeout: timeout,
      logger: logger,
    );
    
    await client.connect();
    
    return SSHClient._(
      client: client,
      logger: logger,
    );
  }
  
  /// Execute a command (compatibility method)
  Future<SSHSession> execute(
    String command, {
    dynamic pty,
    Map<String, String>? environment,
  }) async {
    logger.info('[ADAPTER] Executing command: $command');
    
    // For simple command execution, we don't need a full shell
    final result = await _client.execute(command);
    
    return SSHSession._(
      client: _client,
      command: command,
      output: result,
      logger: logger,
    );
  }
  
  /// Open a shell session (compatibility method)
  Future<SSHSession> shell({
    dynamic pty,
    Map<String, String>? environment,
  }) async {
    logger.info('[ADAPTER] Opening shell session');
    
    // Parse PTY config if provided
    int cols = 80;
    int rows = 24;
    String termType = 'xterm-256color';
    
    if (pty != null) {
      // Assuming pty is SSHPtyConfig from dartssh2
      try {
        cols = pty.width ?? 80;
        rows = pty.height ?? 24;
        termType = pty.type ?? 'xterm-256color';
      } catch (e) {
        logger.warning('[ADAPTER] Failed to parse PTY config', e);
      }
    }
    
    final session = await _client.shell(
      termType: termType,
      cols: cols,
      rows: rows,
      environment: environment,
    );
    
    return SSHSession._(
      client: _client,
      session: session,
      logger: logger,
    );
  }
  
  /// Ping for keep-alive (compatibility method)
  Future<void> ping() async {
    await _client.ping();
  }
  
  /// Check if connection is closed (compatibility property)
  bool get isClosed => false; // Always return false since we manage connection internally
  
  /// Close the connection
  Future<void> close() async {
    logger.info('[ADAPTER] Closing SSH connection');
    await _client.disconnect();
  }
  
  /// Run SFTP (not implemented yet)
  Future<dynamic> sftp() async {
    throw UnimplementedError('SFTP not yet implemented in libssh2 adapter');
  }
  
  /// Forward local port (not implemented yet)
  Future<dynamic> forwardLocal(String host, int port) async {
    throw UnimplementedError('Port forwarding not yet implemented in libssh2 adapter');
  }
  
  /// Run a command and return the output (compatibility method)
  Future<String> run(String command) async {
    logger.info('[ADAPTER] Running command: $command');
    return await _client.execute(command);
  }
}

/// SSH Session wrapper for compatibility
class SSHSession {
  final LibSSH2Client _client;
  final SSHLogger logger;
  final String? command;
  final String? output;
  final LibSSH2Session? _session;
  
  StreamController<Uint8List>? _stdoutController;
  StreamController<Uint8List>? _stderrController;
  StreamController<Uint8List>? _stdinController;
  
  SSHSession._({
    required LibSSH2Client client,
    required this.logger,
    this.command,
    this.output,
    LibSSH2Session? session,
  }) : _client = client,
       _session = session {
    if (session != null) {
      _setupStreams();
    } else if (output != null) {
      _setupStaticOutput();
    }
  }
  
  void _setupStreams() {
    _stdoutController = StreamController<Uint8List>.broadcast();
    _stderrController = StreamController<Uint8List>.broadcast();
    _stdinController = StreamController<Uint8List>.broadcast();
    
    // Forward streams from session
    _session?.stdout.listen((data) {
      logger.debug('[SESSION] Stdout: ${data.length} bytes');
      _stdoutController?.add(data);
    });
    
    _session?.stderr.listen((data) {
      logger.debug('[SESSION] Stderr: ${data.length} bytes');
      _stderrController?.add(data);
    });
    
    _stdinController?.stream.listen((data) {
      logger.debug('[SESSION] Stdin: ${data.length} bytes');
      _session?.stdin.add(data);
    });
  }
  
  void _setupStaticOutput() {
    _stdoutController = StreamController<Uint8List>.broadcast();
    _stderrController = StreamController<Uint8List>.broadcast();
    _stdinController = StreamController<Uint8List>.broadcast();
    
    // Add static output if available
    if (output != null) {
      _stdoutController!.add(utf8.encode(output!));
      _stdoutController!.close();
    }
    _stderrController!.close();
    _stdinController!.close();
  }
  
  Stream<Uint8List> get stdout => _stdoutController?.stream ?? const Stream.empty();
  Stream<Uint8List> get stderr => _stderrController?.stream ?? const Stream.empty();
  Sink<Uint8List> get stdin => _stdinController?.sink ?? _NullSink();
  
  /// Resize terminal (for shell sessions)
  Future<void> resizeTerminal(int width, int height, [int? pixelWidth, int? pixelHeight]) async {
    if (_session != null) {
      logger.info('[SESSION] Resizing terminal to ${width}x$height');
      await _session.resizeTerminal(width, height);
    }
  }
  
  /// Close the session
  Future<void> close() async {
    logger.info('[SESSION] Closing session');
    await _session?.close();
    await _stdoutController?.close();
    await _stderrController?.close();
    await _stdinController?.close();
  }
  
  /// Get exit code (compatibility)
  int? get exitCode => _session?.exitCode;
  
  /// Wait for done (compatibility)
  Future<void> get done async {
    await stdout.drain();
    await stderr.drain();
  }
}

/// Null sink for stdin when not available
class _NullSink implements Sink<Uint8List> {
  @override
  void add(Uint8List data) {}
  
  @override
  void close() {}
}

/// SSH Socket wrapper for compatibility
class SSHSocket {
  final String host;
  final int port;
  final Socket? _socket;
  
  SSHSocket._(this.host, this.port, this._socket);
  
  /// Connect to host (compatibility method)
  static Future<SSHSocket> connect(
    String host,
    int port, {
    Duration? timeout,
  }) async {
    // This is for compatibility only
    // Real connection happens in SSHClient.connect
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
    } catch (e) {
      // Ignore, we'll handle connection in SSHClient
    }
    return SSHSocket._(host, port, socket);
  }
  
  void close() {
    _socket?.close();
  }
}

/// SSH PTY Config for compatibility
class SSHPtyConfig {
  final int? width;
  final int? height;
  final String? type;
  
  const SSHPtyConfig({
    this.width = 80,
    this.height = 24,
    this.type = 'xterm-256color',
  });
}

/// SSH Key Pair for compatibility
class SSHKeyPair {
  final String privateKey;
  final String? publicKey;
  
  SSHKeyPair(this.privateKey, [this.publicKey]);
  
  /// Load from PEM (compatibility method)
  static List<SSHKeyPair> fromPem(String pem, [String? passphrase]) {
    // This is simplified - in reality would parse the PEM
    return [SSHKeyPair(pem)];
  }
  
  /// Check if PEM is encrypted
  static bool isEncryptedPem(String pem) {
    return pem.contains('ENCRYPTED');
  }
  
  /// Convert to PEM
  String toPem() => privateKey;
}

// Extensions are provided by fl_lib, no need to redefine them

/// SSH User Info Request Handler (compatibility)
typedef SSHUserInfoRequestHandler = void Function(dynamic);

/// Extend Uint8List with bytes property for compatibility
extension Uint8ListBytes on Uint8List {
  Uint8List takeBytes() => this;
}