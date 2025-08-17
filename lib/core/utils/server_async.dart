import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/ffi/ssh_isolate_adapter.dart';

/// Async wrapper for SSH client generation that runs in an isolate
/// This prevents blocking the main UI thread during SSH connections

/// Async SSH client generator that uses IsolateSSHClient for non-blocking connections
class AsyncSshClientGenerator {
  /// Generate an SSH client asynchronously using IsolateSSHClient
  /// This prevents blocking the main UI thread during connection
  static Future<dynamic> genClientAsync(
    Spi spi, {
    Duration timeout = const Duration(seconds: 5),
  }) async {

    try {
      // Connect directly using IsolateSSHClient for proper session management
      // This ensures all SSH operations go through the same isolate system
      final isolateClient = await IsolateSSHClient.connect(
        host: spi.ip,
        port: spi.port,
        username: spi.user,
        password: spi.pwd ?? '',
        timeout: timeout,
      );
      
      debugPrint('AsyncSshClientGenerator: Successfully connected to ${spi.ip}:${spi.port} via IsolateSSHClient');
      return isolateClient;
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