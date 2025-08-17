// SSH Isolate Worker - Runs all SSH operations in separate isolate
// This completely isolates SSH operations from the main UI thread

import 'dart:async';
import 'dart:isolate';
import 'package:server_box/ffi/ssh_client.dart' as rust_ssh;

/// Commands that can be sent to SSH isolate
class SshIsolateCommand {
  final String type;
  final Map<String, dynamic> data;
  final SendPort responsePort;

  SshIsolateCommand({
    required this.type,
    required this.data,
    required this.responsePort,
  });
}

/// SSH Isolate Worker Manager
class SshIsolateManager {
  static SshIsolateManager? _instance;
  static SshIsolateManager get instance => _instance ??= SshIsolateManager._();
  
  SshIsolateManager._();

  Isolate? _isolate;
  SendPort? _sendPort;
  final Completer<void> _readyCompleter = Completer<void>();
  
  /// Initialize the SSH isolate worker
  Future<void> initialize() async {
    if (_isolate != null) return;
    
    final receivePort = ReceivePort();
    
    _isolate = await Isolate.spawn(
      _sshIsolateEntryPoint,
      receivePort.sendPort,
    );
    
    // Wait for the isolate to send back its SendPort
    final sendPort = await receivePort.first as SendPort;
    _sendPort = sendPort;
    _readyCompleter.complete();
    
    print('SSH Isolate Worker initialized');
  }
  
  /// Execute SSH command in isolate
  Future<Map<String, dynamic>> executeCommand(
    String type,
    Map<String, dynamic> data,
  ) async {
    await _readyCompleter.future;
    
    final responsePort = ReceivePort();
    final command = SshIsolateCommand(
      type: type,
      data: data,
      responsePort: responsePort.sendPort,
    );
    
    _sendPort!.send(command);
    
    final result = await responsePort.first as Map<String, dynamic>;
    responsePort.close();
    
    return result;
  }
  
  /// Dispose the isolate
  void dispose() {
    _isolate?.kill();
    _isolate = null;
    _sendPort = null;
  }
}

/// Entry point for SSH isolate
void _sshIsolateEntryPoint(SendPort mainSendPort) async {
  final receivePort = ReceivePort();
  
  // Send back our SendPort to main isolate
  mainSendPort.send(receivePort.sendPort);
  
  // Map to store SSH clients by ID
  final Map<String, rust_ssh.SshClient> clients = {};
  
  await for (final message in receivePort) {
    if (message is SshIsolateCommand) {
      try {
        final result = await _handleCommand(message, clients);
        message.responsePort.send({
          'success': true,
          'data': result,
        });
      } catch (e) {
        message.responsePort.send({
          'success': false,
          'error': e.toString(),
        });
      }
    }
  }
}

/// Handle SSH commands in isolate
Future<Map<String, dynamic>> _handleCommand(
  SshIsolateCommand command,
  Map<String, rust_ssh.SshClient> clients,
) async {
  switch (command.type) {
    case 'connect':
      return await _handleConnect(command.data, clients);
    case 'execute':
      return await _handleExecute(command.data, clients);
    case 'createShell':
      return await _handleCreateShell(command.data, clients);
    case 'disconnect':
      return await _handleDisconnect(command.data, clients);
    default:
      throw Exception('Unknown command type: ${command.type}');
  }
}

Future<Map<String, dynamic>> _handleConnect(
  Map<String, dynamic> data,
  Map<String, rust_ssh.SshClient> clients,
) async {
  final config = rust_ssh.SshConfig(
    host: data['host'],
    port: data['port'],
    username: data['username'],
    password: data['password'],
    privateKey: data['privateKey'],
    passphrase: data['passphrase'],
    timeout: Duration(seconds: data['timeoutSecs'] ?? 30),
  );
  
  final client = rust_ssh.SshClient();
  await client.connect(config);
  
  final clientId = data['clientId'] as String;
  clients[clientId] = client;
  
  return {
    'clientId': clientId,
    'connected': true,
  };
}

Future<Map<String, dynamic>> _handleExecute(
  Map<String, dynamic> data,
  Map<String, rust_ssh.SshClient> clients,
) async {
  final clientId = data['clientId'] as String;
  final command = data['command'] as String;
  
  final client = clients[clientId];
  if (client == null) {
    throw Exception('Client not found: $clientId');
  }
  
  final result = await client.execute(command);
  
  return {
    'stdout': result.stdout,
    'stderr': result.stderr,
    'exitCode': result.exitCode,
  };
}

Future<Map<String, dynamic>> _handleCreateShell(
  Map<String, dynamic> data,
  Map<String, rust_ssh.SshClient> clients,
) async {
  final clientId = data['clientId'] as String;
  
  final client = clients[clientId];
  if (client == null) {
    throw Exception('Client not found: $clientId');
  }
  
  await client.createShell();
  
  return {
    'shellCreated': true,
  };
}

Future<Map<String, dynamic>> _handleDisconnect(
  Map<String, dynamic> data,
  Map<String, rust_ssh.SshClient> clients,
) async {
  final clientId = data['clientId'] as String;
  
  final client = clients.remove(clientId);
  if (client != null) {
    client.close();
  }
  
  return {
    'disconnected': true,
  };
}