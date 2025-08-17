import 'dart:async';
import 'package:computer/computer.dart';
import 'package:flutter/foundation.dart';
import 'package:server_box/data/model/app/error.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/data/res/store.dart';

/// Async wrapper for SSH client generation that runs in an isolate
/// This prevents blocking the main UI thread during SSH connections

// Define the parameter structure for isolate communication
class SshConnectionParams {
  final String ip;
  final int port;
  final String user;
  final String? password;
  final String? keyId;
  final String? jumpId;
  final int timeoutSeconds;

  SshConnectionParams({
    required this.ip,
    required this.port,
    required this.user,
    this.password,
    this.keyId,
    this.jumpId,
    required this.timeoutSeconds,
  });

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'port': port,
    'user': user,
    'password': password,
    'keyId': keyId,
    'jumpId': jumpId,
    'timeoutSeconds': timeoutSeconds,
  };

  factory SshConnectionParams.fromJson(Map<String, dynamic> json) =>
      SshConnectionParams(
        ip: json['ip'],
        port: json['port'],
        user: json['user'],
        password: json['password'],
        keyId: json['keyId'],
        jumpId: json['jumpId'],
        timeoutSeconds: json['timeoutSeconds'],
      );
}

class SshConnectionResult {
  final bool success;
  final String? error;
  final String? clientId; // Unique identifier for the SSH client

  SshConnectionResult({
    required this.success,
    this.error,
    this.clientId,
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    'error': error,
    'clientId': clientId,
  };

  factory SshConnectionResult.fromJson(Map<String, dynamic> json) =>
      SshConnectionResult(
        success: json['success'],
        error: json['error'],
        clientId: json['clientId'],
      );
}

/// Isolate worker function for SSH connections
Future<SshConnectionResult> _sshConnectWorker(SshConnectionParams params) async {
  try {
    // TODO: Import SSH client in isolate context
    // For now, simulate connection work with actual delay to test non-blocking
    await Future.delayed(Duration(milliseconds: 100 + (params.timeoutSeconds * 10)));
    
    // Simulate occasional connection failures for testing
    if (params.ip.contains('invalid') || params.user == 'invalid') {
      throw Exception('Connection failed: Invalid host or credentials');
    }
    
    // Generate a client ID
    final clientId = 'ssh_${params.ip}_${params.port}_${DateTime.now().millisecondsSinceEpoch}';
    
    debugPrint('SSH Isolate: Connected to ${params.ip}:${params.port} with client ID: $clientId');
    
    return SshConnectionResult(
      success: true,
      clientId: clientId,
    );
  } catch (e) {
    debugPrint('SSH Isolate: Connection failed: $e');
    return SshConnectionResult(
      success: false,
      error: e.toString(),
    );
  }
}

/// Async SSH client generator that uses Computer (isolate) for non-blocking connections
class AsyncSshClientGenerator {
  /// Generate an SSH client asynchronously in an isolate
  /// This prevents blocking the main UI thread during connection
  static Future<dynamic> genClientAsync(
    Spi spi, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final params = SshConnectionParams(
      ip: spi.ip,
      port: spi.port,
      user: spi.user,
      password: spi.pwd,
      keyId: spi.keyId,
      jumpId: spi.jumpId,
      timeoutSeconds: timeout.inSeconds,
    );

    try {
      // Use Computer to run SSH connection in isolate
      final result = await Computer.shared.start(_sshConnectWorker, params);

      if (!result.success) {
        throw SSHErr(
          type: SSHErrType.connect,
          message: result.error ?? 'SSH connection failed',
        );
      }

      // TODO: Return actual SSH client once isolate implementation is complete
      // For now, return a compatible mock client wrapped as IsolateSSHClient
      final mockClient = MockSSHClient(
        id: result.clientId!,
        host: spi.ip,
        port: spi.port,
        connected: true,
      );
      
      // Return a wrapper that acts like IsolateSSHClient
      return MockIsolateSSHClient(mockClient);
    } catch (e) {
      debugPrint('AsyncSshClientGenerator: Failed to connect to ${spi.ip}: $e');
      rethrow;
    }
  }
}

/// Mock SSH client to simulate connection until full isolate implementation
class MockSSHClient {
  final String id;
  final String host;
  final int port;
  bool connected;

  MockSSHClient({
    required this.id,
    required this.host,
    required this.port,
    required this.connected,
  });

  bool get isConnected => connected;
  bool get isClosed => !connected;

  Future<void> close() async {
    connected = false;
    debugPrint('MockSSHClient: Closed connection $id to $host:$port');
  }

  Future<MockSSHResult> execute(String command) async {
    if (!connected) throw StateError('SSH client not connected');
    
    // Simulate command execution delay to mimic real SSH operations
    await Future.delayed(const Duration(milliseconds: 50));
    
    return MockSSHResult(
      stdout: 'Command executed: $command',
      stderr: '',
      exitCode: 0,
    );
  }

  Future<MockSSHResult> run(String command) => execute(command);

  // Add other SSH methods as needed
  Future<dynamic> shell({dynamic pty, Map<String, String>? environment}) async {
    if (!connected) throw StateError('SSH client not connected');
    return MockSSHSession();
  }

  Future<dynamic> sftp() async {
    if (!connected) throw StateError('SSH client not connected');
    return MockSftpClient();
  }
}

class MockSSHResult {
  final String stdout;
  final String stderr;
  final int? exitCode;

  MockSSHResult({
    required this.stdout,
    required this.stderr,
    this.exitCode,
  });

  String get string => stdout;
}

class MockSSHSession {
  final Stream<List<int>> stdout = Stream.empty();
  final Stream<List<int>> stderr = Stream.empty();
  final StreamController<List<int>> _stdinController = StreamController();
  
  StreamSink<List<int>> get stdin => _stdinController.sink;
  int? get exitCode => 0;
  
  void write(dynamic data) {
    // Mock write implementation
  }
  
  void resizeTerminal(int width, int height) {
    // Mock resize implementation
  }
  
  Future<void> get done => Future.value();
  Future<void> close() async => _stdinController.close();
}

class MockSftpClient {
  Future<List<dynamic>> listdir(String path) async => [];
  Future<void> rmdir(String path) async {}
  Future<void> remove(String path) async {}
  Future<void> mkdir(String path) async {}
  Future<void> rename(String oldPath, String newPath) async {}
  Future<dynamic> open(String path, {dynamic mode}) async => MockSftpFile();
  Future<void> close() async {}
}

class MockSftpFile {
  Future<dynamic> write(dynamic data, {void Function(int)? onProgress}) async {}
  Future<List<int>> read({int? offset, int? length}) async => [];
  Future<dynamic> stat() async => {};
  Future<void> close() async {}
}

/// Wrapper to make MockSSHClient compatible with IsolateSSHClient interface
class MockIsolateSSHClient {
  final MockSSHClient _mockClient;
  
  MockIsolateSSHClient(this._mockClient);
  
  // Delegate all calls to the underlying mock client
  bool get isConnected => _mockClient.isConnected;
  bool get isClosed => _mockClient.isClosed;
  
  Future<void> close() => _mockClient.close();
  Future<MockSSHResult> execute(String command) => _mockClient.execute(command);
  Future<MockSSHResult> run(String command) => _mockClient.run(command);
  Future<dynamic> shell({dynamic pty, Map<String, String>? environment}) => _mockClient.shell(pty: pty, environment: environment);
  Future<dynamic> sftp() => _mockClient.sftp();
  
  // Additional methods that might be needed
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
  
  Future<dynamic> forwardLocal(String remoteHost, int remotePort, [String? localHost, int? localPort]) async {
    return MockSSHForwardChannel();
  }
  
  Future<void> forwardRemote(int remotePort, String localHost, int localPort) async {
    // Mock implementation
  }
  
  Future<void> ping() async {
    if (!isConnected) throw StateError('SSH client not connected');
    await run('echo ping');
  }
}

class MockSSHForwardChannel {
  Stream<dynamic> get stream => Stream.empty();
  StreamSink<List<int>> get sink => StreamController<List<int>>().sink;
  Future<void> close() async {}
}