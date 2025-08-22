/// SSH message types for isolate communication
enum SSHMessageType {
  connect,
  disconnect,
  shell,
  execute,
  write,
  resize,
  ping,
  ready,
  response,
  stdout,
  stderr,
  status,
  log,
  error,
}

/// SSH connection status
enum SSHConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// SSH message for isolate communication
class SSHMessage {
  final int id;
  final SSHMessageType type;
  final Map<String, dynamic>? data;
  final String? error;

  SSHMessage({
    required this.id,
    required this.type,
    this.data,
    this.error,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.index,
      'data': data,
      'error': error,
    };
  }

  factory SSHMessage.fromMap(Map<String, dynamic> map) {
    return SSHMessage(
      id: map['id'] as int,
      type: SSHMessageType.values[map['type'] as int],
      data: map['data'] as Map<String, dynamic>?,
      error: map['error'] as String?,
    );
  }

  @override
  String toString() {
    return 'SSHMessage(id: $id, type: $type, data: $data, error: $error)';
  }
}