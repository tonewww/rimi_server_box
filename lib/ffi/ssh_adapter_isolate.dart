// SSH Adapter using Isolate - Completely non-blocking SSH operations
// This provides the same API as ssh_adapter.dart but uses isolate for all operations

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:server_box/ffi/ssh_isolate_worker.dart';
import 'dart:math';

/// Non-blocking SSH client using isolate worker
class IsolateSSHClient {
  String? _clientId;
  bool _connected = false;
  
  /// Connect using password
  static Future<IsolateSSHClient> connect({
    required String host,
    int port = 22,
    required String username,
    required String password,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = IsolateSSHClient();
    
    // Initialize isolate worker if needed
    await SshIsolateManager.instance.initialize();
    
    // Generate unique client ID
    client._clientId = 'ssh_${host}_${port}_${Random().nextInt(100000)}';
    
    debugPrint('SSH Isolate: Connecting to $host:$port');
    
    final result = await SshIsolateManager.instance.executeCommand('connect', {
      'clientId': client._clientId,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'timeoutSecs': timeout.inSeconds,
    });
    
    if (result['success']) {
      client._connected = true;
      debugPrint('SSH Isolate: Connected successfully to $host:$port');
      return client;
    } else {
      throw Exception('SSH connection failed: ${result['error']}');
    }
  }
  
  /// Connect using private key
  static Future<IsolateSSHClient> connectWithKey({
    required String host,
    int port = 22,
    required String username,
    required String privateKey,
    String? passphrase,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = IsolateSSHClient();
    
    // Initialize isolate worker if needed
    await SshIsolateManager.instance.initialize();
    
    // Generate unique client ID
    client._clientId = 'ssh_${host}_${port}_${Random().nextInt(100000)}';
    
    debugPrint('SSH Isolate: Connecting with key to $host:$port');
    
    final result = await SshIsolateManager.instance.executeCommand('connect', {
      'clientId': client._clientId,
      'host': host,
      'port': port,
      'username': username,
      'privateKey': privateKey,
      'passphrase': passphrase,
      'timeoutSecs': timeout.inSeconds,
    });
    
    if (result['success']) {
      client._connected = true;
      debugPrint('SSH Isolate: Connected with key successfully to $host:$port');
      return client;
    } else {
      throw Exception('SSH key connection failed: ${result['error']}');
    }
  }
  
  /// Execute command
  Future<IsolateCommandResult> execute(String command) async {
    if (!_connected || _clientId == null) {
      throw StateError('SSH client not connected');
    }
    
    final result = await SshIsolateManager.instance.executeCommand('execute', {
      'clientId': _clientId,
      'command': command,
    });
    
    if (result['success']) {
      return IsolateCommandResult(
        stdout: result['data']['stdout'],
        stderr: result['data']['stderr'],
        exitCode: result['data']['exitCode'],
      );
    } else {
      throw Exception('Command execution failed: ${result['error']}');
    }
  }
  
  /// Create shell session
  Future<void> createShell() async {
    if (!_connected || _clientId == null) {
      throw StateError('SSH client not connected');
    }
    
    final result = await SshIsolateManager.instance.executeCommand('createShell', {
      'clientId': _clientId,
    });
    
    if (!result['success']) {
      throw Exception('Shell creation failed: ${result['error']}');
    }
  }
  
  /// Execute command (alias for compatibility)
  Future<IsolateCommandResult> run(String command) async {
    return execute(command);
  }
  
  /// Close connection
  void close() {
    if (_clientId != null) {
      // Fire and forget - don't wait for disconnect
      SshIsolateManager.instance.executeCommand('disconnect', {
        'clientId': _clientId,
      }).catchError((e) {
        debugPrint('SSH Isolate: Disconnect error: $e');
      });
      
      _clientId = null;
      _connected = false;
    }
  }
  
  /// Check if connected
  bool get isConnected => _connected;
  
  /// Check if closed
  bool get isClosed => !_connected;
}

/// Command result from isolate
class IsolateCommandResult {
  final String stdout;
  final String stderr;
  final int? exitCode;
  
  IsolateCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });
  
  String get string => stdout;
}

/// SSH Session for compatibility
class IsolateSSHSession {
  final IsolateCommandResult _result;
  
  IsolateSSHSession._(this._result);
  
  int? get exitCode => _result.exitCode;
  
  Stream<List<int>> get stdout async* {
    yield _result.stdout.codeUnits;
  }
  
  Stream<List<int>> get stderr async* {
    yield _result.stderr.codeUnits;
  }
}

// Compatibility classes and types
typedef SSHClient = IsolateSSHClient;
typedef SSHSession = IsolateSSHSession;

// SFTP and other features - simplified for now
class SftpClient {}
class SSHForwardChannel {}
class SSHSocket {}
class SftpFile {}
class SftpName {}

// Error classes
class SSHAuthAbortError implements Exception {
  final String message;
  SSHAuthAbortError(this.message);
  @override
  String toString() => 'SSHAuthAbortError: $message';
}

class SSHAuthFailError implements Exception {
  final String message;
  SSHAuthFailError(this.message);
  @override
  String toString() => 'SSHAuthFailError: $message';
}

class SSHKeyPair {
  static List<SSHKeyPair> fromPem(String pem, [String? passphrase]) => [];
  static bool isEncryptedPem(String pem) => false;
  String toPem() => '';
}

// Additional compatibility exports
class SSHPtyConfig {}
class SftpFileOpenMode {
  static const int create = 1;
  static const int write = 2;
  static const int truncate = 4;
}