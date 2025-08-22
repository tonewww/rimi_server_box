import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:server_box/core/libssh2/libssh2_ffi_client.dart';
import 'package:server_box/core/libssh2/ssh_logger.dart';

// Re-export SFTP types from sftp_adapter
export 'package:server_box/core/libssh2/sftp_adapter.dart' show SftpClient;

/// Adapter to provide SSH functionality using libssh2 FFI
class SSHClient {
  final LibSSH2FFIClient _client;
  final SSHLogger logger;
  
  SSHClient._({
    required LibSSH2FFIClient client,
    required this.logger,
  }) : _client = client;
  
  /// Factory constructor for compatibility (not used with libssh2)
  factory SSHClient(
    dynamic socket, {
    required String username,
    String Function()? onPasswordRequest,
    List<dynamic>? identities,
    dynamic onUserInfoRequest,
  }) {
    throw UnimplementedError('Use SSHClient.connect for libssh2 implementation');
  }
  
  /// Connect to SSH server using libssh2 FFI
  static Future<SSHClient> connect(
    String host,
    int port, {
    required String username,
    String? password,
    String? privateKeyPath,
    String? publicKeyPath,
    String? passphrase,
    Duration timeout = const Duration(seconds: 30),
    SSHLogger? logger,
  }) async {
    logger ??= SSHLogger();
    logger.info('[ADAPTER] Connecting to $username@$host:$port using libssh2 FFI');
    
    final client = LibSSH2FFIClient(
      host: host,
      port: port,
      username: username,
      password: password,
      privateKeyPath: privateKeyPath,
      publicKeyPath: publicKeyPath,
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
  
  /// Execute a command
  Future<SSHSession> execute(
    String command, {
    dynamic pty,
    Map<String, String>? environment,
  }) async {
    logger.info('[ADAPTER] Executing command: $command');
    
    final result = await _client.execute(command);
    
    return SSHSession._(
      client: _client,
      command: command,
      output: result,
      logger: logger,
    );
  }
  
  /// Open a shell session
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
      try {
        // Handle both SSHPtyConfig and similar structures
        cols = pty.width ?? pty.cols ?? 80;
        rows = pty.height ?? pty.rows ?? 24;
        termType = pty.type ?? pty.termType ?? 'xterm-256color';
      } catch (e) {
        logger.warning('[ADAPTER] Failed to parse PTY config, using defaults', e);
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
  
  /// Run a command and return the output
  Future<String> run(String command) async {
    logger.info('[ADAPTER] Running command: $command');
    return await _client.execute(command);
  }
  
  /// Ping for keep-alive
  Future<void> ping() async {
    await _client.ping();
  }
  
  /// Check if connection is closed
  bool get isClosed => false; // Managed internally by libssh2
  
  /// Close the connection
  Future<void> close() async {
    logger.info('[ADAPTER] Closing SSH connection');
    await _client.disconnect();
  }
  
  /// Run SFTP (not implemented yet)
  Future<dynamic> sftp() async {
    throw UnimplementedError('SFTP not yet implemented in libssh2 FFI adapter');
  }
  
  /// Forward local port (not implemented yet)
  Future<dynamic> forwardLocal(String host, int port) async {
    throw UnimplementedError('Port forwarding not yet implemented in libssh2 FFI adapter');
  }
}

/// SSH Session wrapper
class SSHSession {
  final LibSSH2FFIClient? _client;
  final LibSSH2FFISession? _session;
  final String? _command;
  final String? _output;
  final SSHLogger logger;
  
  SSHSession._({
    LibSSH2FFIClient? client,
    LibSSH2FFISession? session,
    String? command,
    String? output,
    required this.logger,
  }) : _client = client,
       _session = session,
       _command = command,
       _output = output;
  
  Stream<Uint8List> get stdout {
    if (_session != null) {
      return _session.stdout;
    }
    // For command execution, return output as stream
    if (_output != null) {
      return Stream.value(Uint8List.fromList(_output.codeUnits));
    }
    return const Stream.empty();
  }
  
  Stream<Uint8List> get stderr {
    if (_session != null) {
      return _session.stderr;
    }
    return const Stream.empty();
  }
  
  Sink<Uint8List> get stdin {
    if (_session != null) {
      return _session.stdin;
    }
    // For command execution, create a dummy sink
    return _DummySink();
  }
  
  /// Resize terminal
  Future<void> resizeTerminal(int cols, int rows) async {
    if (_session != null) {
      logger.info('[SESSION] Resizing terminal to ${cols}x${rows}');
      await _session.resizeTerminal(cols, rows);
    } else {
      logger.warning('[SESSION] Cannot resize: not a shell session');
    }
  }
  
  /// Close session
  void close() {
    logger.info('[SESSION] Closing session');
    _session?.close();
  }
  
  /// Get exit code
  int? get exitCode => _session?.exitCode;
  
  /// Wait for session to complete
  Future<void> get done async {
    // For command execution, complete immediately
    if (_command != null) {
      return;
    }
    // For shell session, wait for it to close
    // This is a simplified implementation
    while (_session != null) {
      await Future.delayed(const Duration(seconds: 1));
    }
  }
}

/// Dummy sink for command execution
class _DummySink implements Sink<Uint8List> {
  @override
  void add(Uint8List data) {
    // Ignore input for command execution
  }
  
  @override
  void close() {
    // Nothing to close
  }
}

// Type aliases for compatibility
class SSHSocket {
  static Future<SSHSocket> connect(String host, int port, {Duration? timeout}) async {
    // This is not used with libssh2, but provided for compatibility
    throw UnimplementedError('Use SSHClient.connect for libssh2 implementation');
  }
}

class SSHKeyPair {
  static List<SSHKeyPair> fromPem(String pem, [String? passphrase]) {
    // This is not used with libssh2, but provided for compatibility
    throw UnimplementedError('Key pairs are handled internally by libssh2');
  }
  
  static bool isEncryptedPem(String pem) {
    // Simple check for encrypted PEM
    return pem.contains('ENCRYPTED');
  }
  
  String toPem() {
    throw UnimplementedError('Key pairs are handled internally by libssh2');
  }
}

class SSHPtyConfig {
  final int? width;
  final int? height;
  final String? type;
  
  SSHPtyConfig({this.width, this.height, this.type});
}

typedef SSHUserInfoRequestHandler = void Function(dynamic);