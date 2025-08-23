import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/foundation.dart';

import 'package:server_box/core/libssh2/ffi_bindings.dart';
import 'package:server_box/core/libssh2/ssh_logger.dart';
import 'package:server_box/core/libssh2/ssh_message.dart';

/// Async SSH Client wrapper for libssh2
/// Handles all SSH operations in an isolate with message passing
class AsyncSSHClient {
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final String? publicKey;
  final String? passphrase;
  final Duration timeout;
  final SSHLogger logger;

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  final _responseHandlers = <int, Completer<SSHMessage>>{};
  int _messageId = 0;

  StreamController<String>? _stdoutController;
  StreamController<String>? _stderrController;
  StreamController<SSHConnectionStatus>? _statusController;

  AsyncSSHClient({
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.privateKey,
    this.publicKey,
    this.passphrase,
    this.timeout = const Duration(seconds: 30),
    SSHLogger? logger,
  }) : logger = logger ?? SSHLogger();

  Stream<String> get stdout =>
      _stdoutController?.stream ?? const Stream.empty();
  Stream<String> get stderr =>
      _stderrController?.stream ?? const Stream.empty();
  Stream<SSHConnectionStatus> get status =>
      _statusController?.stream ?? const Stream.empty();

  /// Initialize the SSH client and start the isolate
  Future<void> connect() async {
    logger.info('Starting SSH connection to $username@$host:$port');

    _stdoutController = StreamController<String>.broadcast();
    _stderrController = StreamController<String>.broadcast();
    _statusController = StreamController<SSHConnectionStatus>.broadcast();

    _receivePort = ReceivePort();
    _receivePort!.listen(_handleIsolateMessage);

    try {
      logger.debug('Spawning SSH isolate...');
      _isolate = await Isolate.spawn(
        _sshIsolateEntryPoint,
        SSHIsolateParams(
          sendPort: _receivePort!.sendPort,
          host: host,
          port: port,
          username: username,
          password: password,
          privateKey: privateKey,
          publicKey: publicKey,
          passphrase: passphrase,
          timeout: timeout,
        ),
      );

      // Wait for isolate to be ready
      final completer = Completer<SSHMessage>();
      _responseHandlers[-1] = completer;

      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('SSH isolate initialization timeout');
        },
      );

      logger.info('SSH isolate ready, initiating connection...');

      // Start connection
      final response = await _sendMessage(
        SSHMessage(id: _nextMessageId(), type: SSHMessageType.connect),
      );

      if (response.error != null) {
        throw Exception('Connection failed: ${response.error}');
      }

      _statusController?.add(SSHConnectionStatus.connected);
      logger.info('SSH connection established successfully');
    } catch (e, stack) {
      logger.error('Failed to connect', e, stack);
      await disconnect();
      rethrow;
    }
  }

  /// Open a shell session
  Future<void> shell({
    String termType = 'xterm-256color',
    int cols = 80,
    int rows = 24,
    Map<String, String>? environment,
  }) async {
    logger.info(
      'Opening shell session (term=$termType, cols=$cols, rows=$rows)',
    );

    final response = await _sendMessage(
      SSHMessage(
        id: _nextMessageId(),
        type: SSHMessageType.shell,
        data: {
          'termType': termType,
          'cols': cols,
          'rows': rows,
          'environment': environment,
        },
      ),
    );

    if (response.error != null) {
      logger.error('Failed to open shell', response.error);
      throw Exception('Failed to open shell: ${response.error}');
    }

    logger.info('Shell session opened successfully');
  }

  /// Execute a command
  Future<String> execute(String command) async {
    logger.info('Executing command: $command');

    final response = await _sendMessage(
      SSHMessage(
        id: _nextMessageId(),
        type: SSHMessageType.execute,
        data: {'command': command},
      ),
    );

    if (response.error != null) {
      logger.error('Command execution failed', response.error);
      throw Exception('Command execution failed: ${response.error}');
    }

    final result = response.data?['output'] as String? ?? '';
    logger.debug('Command output: ${result.length} bytes');
    return result;
  }

  /// Write data to stdin
  Future<void> write(String data) async {
    logger.debug('Writing ${data.length} bytes to stdin');

    final response = await _sendMessage(
      SSHMessage(
        id: _nextMessageId(),
        type: SSHMessageType.write,
        data: {'data': data},
      ),
    );

    if (response.error != null) {
      logger.error('Write failed', response.error);
      throw Exception('Write failed: ${response.error}');
    }
  }

  /// Resize terminal
  Future<void> resizeTerminal(int cols, int rows) async {
    logger.info('Resizing terminal to ${cols}x${rows}');

    final response = await _sendMessage(
      SSHMessage(
        id: _nextMessageId(),
        type: SSHMessageType.resize,
        data: {'cols': cols, 'rows': rows},
      ),
    );

    if (response.error != null) {
      logger.error('Terminal resize failed', response.error);
      throw Exception('Terminal resize failed: ${response.error}');
    }

    logger.debug('Terminal resized successfully');
  }

  /// Send keep-alive ping
  Future<void> ping() async {
    logger.debug('Sending keep-alive ping');

    try {
      final response = await _sendMessage(
        SSHMessage(id: _nextMessageId(), type: SSHMessageType.ping),
      ).timeout(const Duration(seconds: 5));

      if (response.error != null) {
        throw Exception(response.error);
      }

      logger.debug('Keep-alive ping successful');
    } catch (e) {
      logger.warning('Keep-alive ping failed', e);
      _statusController?.add(SSHConnectionStatus.disconnected);
      rethrow;
    }
  }

  /// Disconnect and clean up
  Future<void> disconnect() async {
    logger.info('Disconnecting SSH client');

    try {
      if (_sendPort != null) {
        await _sendMessage(
          SSHMessage(id: _nextMessageId(), type: SSHMessageType.disconnect),
        ).timeout(const Duration(seconds: 2));
      }
    } catch (e) {
      logger.warning('Error during disconnect', e);
    }

    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _receivePort?.close();
    _receivePort = null;

    await _stdoutController?.close();
    await _stderrController?.close();
    await _statusController?.close();

    _stdoutController = null;
    _stderrController = null;
    _statusController = null;

    _responseHandlers.clear();

    logger.info('SSH client disconnected');
  }

  int _nextMessageId() => ++_messageId;

  Future<SSHMessage> _sendMessage(SSHMessage message) {
    if (_sendPort == null) {
      throw StateError('SSH client not connected');
    }

    final completer = Completer<SSHMessage>();
    _responseHandlers[message.id] = completer;

    _sendPort!.send(message.toMap());

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _responseHandlers.remove(message.id);
        throw TimeoutException('Request timeout for message ${message.id}');
      },
    );
  }

  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      _responseHandlers[-1]?.complete(
        SSHMessage(id: -1, type: SSHMessageType.ready),
      );
      _responseHandlers.remove(-1);
      return;
    }

    if (message is Map) {
      final sshMessage = SSHMessage.fromMap(Map<String, dynamic>.from(message));

      switch (sshMessage.type) {
        case SSHMessageType.stdout:
          final data = sshMessage.data?['data'] as String?;
          if (data != null) {
            logger.debug('Received stdout: ${data.length} bytes');
            _stdoutController?.add(data);
          }
          break;

        case SSHMessageType.stderr:
          final data = sshMessage.data?['data'] as String?;
          if (data != null) {
            logger.debug('Received stderr: ${data.length} bytes');
            _stderrController?.add(data);
          }
          break;

        case SSHMessageType.status:
          final status = SSHConnectionStatus
              .values[sshMessage.data?['status'] as int? ?? 0];
          logger.info('Connection status changed: $status');
          _statusController?.add(status);
          break;

        case SSHMessageType.log:
          final level = sshMessage.data?['level'] as String?;
          final msg = sshMessage.data?['message'] as String?;
          if (level != null && msg != null) {
            logger.log(level, msg);
          }
          break;

        default:
          final completer = _responseHandlers.remove(sshMessage.id);
          completer?.complete(sshMessage);
          break;
      }
    }
  }
}

/// Parameters for SSH isolate
class SSHIsolateParams {
  final SendPort sendPort;
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final String? publicKey;
  final String? passphrase;
  final Duration timeout;

  SSHIsolateParams({
    required this.sendPort,
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.privateKey,
    this.publicKey,
    this.passphrase,
    required this.timeout,
  });
}

/// SSH isolate entry point
void _sshIsolateEntryPoint(SSHIsolateParams params) {
  final isolate = SSHIsolate(params);
  isolate.run();
}

/// SSH isolate implementation
class SSHIsolate {
  final SSHIsolateParams params;
  final ReceivePort receivePort = ReceivePort();
  late final SendPort mainSendPort;

  LibSSH2SessionPtr? session;
  LibSSH2ChannelPtr? channel;
  Socket? socket;
  Timer? readTimer;

  SSHIsolate(this.params) : mainSendPort = params.sendPort;

  void run() {
    // Send our send port to main isolate
    mainSendPort.send(receivePort.sendPort);

    // Listen for messages
    receivePort.listen(_handleMessage);

    // Initialize libssh2
    _log('info', 'Initializing libssh2 in isolate');
    final rc = LibSSH2.init(0);
    if (rc != 0) {
      _log('error', 'Failed to initialize libssh2: $rc');
      return;
    }
  }

  void _handleMessage(dynamic message) async {
    if (message is Map) {
      final sshMessage = SSHMessage.fromMap(Map<String, dynamic>.from(message));

      try {
        switch (sshMessage.type) {
          case SSHMessageType.connect:
            await _connect();
            _reply(
              sshMessage,
              SSHMessage(id: sshMessage.id, type: SSHMessageType.response),
            );
            break;

          case SSHMessageType.shell:
            await _openShell(sshMessage.data ?? {});
            _reply(
              sshMessage,
              SSHMessage(id: sshMessage.id, type: SSHMessageType.response),
            );
            break;

          case SSHMessageType.execute:
            final output = await _execute(
              sshMessage.data?['command'] as String,
            );
            _reply(
              sshMessage,
              SSHMessage(
                id: sshMessage.id,
                type: SSHMessageType.response,
                data: {'output': output},
              ),
            );
            break;

          case SSHMessageType.write:
            await _write(sshMessage.data?['data'] as String);
            _reply(
              sshMessage,
              SSHMessage(id: sshMessage.id, type: SSHMessageType.response),
            );
            break;

          case SSHMessageType.resize:
            await _resize(
              sshMessage.data?['cols'] as int,
              sshMessage.data?['rows'] as int,
            );
            _reply(
              sshMessage,
              SSHMessage(id: sshMessage.id, type: SSHMessageType.response),
            );
            break;

          case SSHMessageType.ping:
            // Just reply to confirm we're alive
            _reply(
              sshMessage,
              SSHMessage(id: sshMessage.id, type: SSHMessageType.response),
            );
            break;

          case SSHMessageType.disconnect:
            await _disconnect();
            _reply(
              sshMessage,
              SSHMessage(id: sshMessage.id, type: SSHMessageType.response),
            );
            receivePort.close();
            break;

          default:
            _reply(
              sshMessage,
              SSHMessage(
                id: sshMessage.id,
                type: SSHMessageType.response,
                error: 'Unknown message type',
              ),
            );
        }
      } catch (e, stack) {
        _log('error', 'Error handling message: $e\n$stack');
        _reply(
          sshMessage,
          SSHMessage(
            id: sshMessage.id,
            type: SSHMessageType.response,
            error: e.toString(),
          ),
        );
      }
    }
  }

  Future<void> _connect() async {
    _log('info', 'Connecting to ${params.host}:${params.port}');

    // Create TCP socket
    socket = await Socket.connect(
      params.host,
      params.port,
      timeout: params.timeout,
    );

    _log('debug', 'TCP connection established');

    // Create SSH session
    session = LibSSH2.sessionInit();
    if (session == null || session!.address == 0) {
      throw Exception('Failed to create SSH session');
    }

    _log('debug', 'SSH session created');

    // Set non-blocking mode
    LibSSH2.sessionSetBlocking(session!, 0);

    // Perform SSH handshake
    _log('info', 'Performing SSH handshake');
    var rc = LibSSH2Error.eagain;
    while (rc == LibSSH2Error.eagain) {
      rc = LibSSH2.sessionHandshake(session!, socket!.hashCode);
      if (rc == LibSSH2Error.eagain) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    if (rc != 0) {
      final error = _getLastError();
      throw Exception('SSH handshake failed: $error');
    }

    _log('info', 'SSH handshake completed');

    // Authenticate
    await _authenticate();

    _log('info', 'Authentication successful');
  }

  Future<void> _authenticate() async {
    _log('info', 'Authenticating user: ${params.username}');

    if (params.privateKey != null) {
      await _authenticateWithKey();
    } else if (params.password != null) {
      await _authenticateWithPassword();
    } else {
      throw Exception('No authentication method provided');
    }
  }

  Future<void> _authenticateWithPassword() async {
    _log('debug', 'Using password authentication');

    final usernamePtr = params.username.toNativeUtf8();
    final passwordPtr = params.password!.toNativeUtf8();

    try {
      var rc = LibSSH2Error.eagain;
      while (rc == LibSSH2Error.eagain) {
        rc = LibSSH2.userauthPassword(session!, usernamePtr, passwordPtr);
        if (rc == LibSSH2Error.eagain) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }

      if (rc != 0) {
        final error = _getLastError();
        throw Exception('Password authentication failed: $error');
      }
    } finally {
      malloc.free(usernamePtr);
      malloc.free(passwordPtr);
    }
  }

  Future<void> _authenticateWithKey() async {
    _log('debug', 'Using public key authentication');

    final usernamePtr = params.username.toNativeUtf8();
    final privateKeyBytes = utf8.encode(params.privateKey!);
    final privateKeyPtr = malloc<Uint8List>(privateKeyBytes.length);
    privateKeyPtr
        .asTypedList(privateKeyBytes.length)
        .setAll(0, privateKeyBytes);

    final publicKeyBytes = params.publicKey != null
        ? utf8.encode(params.publicKey!)
        : Uint8List(0);
    final publicKeyPtr = publicKeyBytes.isNotEmpty
        ? malloc<Uint8List>(publicKeyBytes.length)
        : null;
    if (publicKeyPtr != null && publicKeyPtr.address != 0) {
      publicKeyPtr.asTypedList(publicKeyBytes.length).setAll(0, publicKeyBytes);
    }

    final passphrasePtr = params.passphrase?.toNativeUtf8();

    try {
      var rc = LibSSH2Error.eagain;
      while (rc == LibSSH2Error.eagain) {
        rc = LibSSH2.userauthPublicKeyFromMemory(
          session!,
          usernamePtr,
          publicKeyPtr.cast(),
          publicKeyBytes.length,
          privateKeyPtr.cast(),
          privateKeyBytes.length,
          passphrasePtr.cast(),
        );
        if (rc == LibSSH2Error.eagain) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }

      if (rc != 0) {
        final error = _getLastError();
        throw Exception('Public key authentication failed: $error');
      }
    } finally {
      malloc.free(usernamePtr);
      malloc.free(privateKeyPtr);
      if (publicKeyPtr != null && publicKeyPtr.address != 0) {
        malloc.free(publicKeyPtr);
      }
      if (passphrasePtr != null) {
        malloc.free(passphrasePtr);
      }
    }
  }

  Future<void> _openShell(Map<String, dynamic> params) async {
    _log('info', 'Opening shell channel');

    // Open channel
    channel = LibSSH2.channelOpenSession(session!);
    if (channel == null || channel!.address == 0) {
      throw Exception('Failed to open channel');
    }

    _log('debug', 'Channel opened');

    // Request PTY
    final termType = params['termType'] as String? ?? 'xterm-256color';
    final cols = params['cols'] as int? ?? 80;
    final rows = params['rows'] as int? ?? 24;

    _log('debug', 'Requesting PTY: $termType ${cols}x${rows}');

    final termTypePtr = termType.toNativeUtf8();
    final modesPtr = Pointer<Utf8>.fromAddress(0);

    try {
      var rc = LibSSH2Error.eagain;
      while (rc == LibSSH2Error.eagain) {
        rc = LibSSH2.channelRequestPtyEx(
          channel!,
          termTypePtr,
          termType.length,
          modesPtr,
          0,
          cols,
          rows,
          0,
          0,
        );
        if (rc == LibSSH2Error.eagain) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }

      if (rc != 0) {
        final error = _getLastError();
        throw Exception('Failed to request PTY: $error');
      }
    } finally {
      malloc.free(termTypePtr);
    }

    _log('debug', 'PTY allocated');

    // Set environment variables
    final environment = params['environment'] as Map<String, String>?;
    if (environment != null) {
      for (final entry in environment.entries) {
        await _setEnv(entry.key, entry.value);
      }
    }

    // Start shell
    _log('info', 'Starting shell');
    var rc = LibSSH2Error.eagain;
    while (rc == LibSSH2Error.eagain) {
      rc = LibSSH2.channelShell(channel!);
      if (rc == LibSSH2Error.eagain) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    if (rc != 0) {
      final error = _getLastError();
      throw Exception('Failed to start shell: $error');
    }

    _log('info', 'Shell started successfully');

    // Start reading data
    _startReadLoop();
  }

  Future<void> _setEnv(String name, String value) async {
    final namePtr = name.toNativeUtf8();
    final valuePtr = value.toNativeUtf8();

    try {
      var rc = LibSSH2Error.eagain;
      while (rc == LibSSH2Error.eagain) {
        rc = LibSSH2.channelSetEnv(channel!, namePtr, valuePtr);
        if (rc == LibSSH2Error.eagain) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }

      if (rc != 0) {
        _log('warning', 'Failed to set environment variable $name');
      }
    } finally {
      malloc.free(namePtr);
      malloc.free(valuePtr);
    }
  }

  void _startReadLoop() {
    readTimer?.cancel();
    readTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      _readData();
    });
  }

  void _readData() {
    if (channel == null) return;
    if (channel!.address == 0) return;

    final buffer = malloc<Uint8List>(4096);

    try {
      // Read stdout
      var bytesRead = LibSSH2.channelRead(channel!, buffer, 4096);
      if (bytesRead > 0) {
        final data = buffer.asTypedList(bytesRead);
        final str = utf8.decode(data, allowMalformed: true);
        mainSendPort.send(
          SSHMessage(
            id: 0,
            type: SSHMessageType.stdout,
            data: {'data': str},
          ).toMap(),
        );
      }

      // Read stderr
      bytesRead = LibSSH2.channelReadStderr(channel!, buffer, 4096);
      if (bytesRead > 0) {
        final data = buffer.asTypedList(bytesRead);
        final str = utf8.decode(data, allowMalformed: true);
        mainSendPort.send(
          SSHMessage(
            id: 0,
            type: SSHMessageType.stderr,
            data: {'data': str},
          ).toMap(),
        );
      }

      // Check if channel is EOF
      if (LibSSH2.channelEof(channel!) != 0) {
        _log('info', 'Channel reached EOF');
        readTimer?.cancel();
        mainSendPort.send(
          SSHMessage(
            id: 0,
            type: SSHMessageType.status,
            data: {'status': SSHConnectionStatus.disconnected.index},
          ).toMap(),
        );
      }
    } finally {
      malloc.free(buffer);
    }
  }

  Future<String> _execute(String command) async {
    _log('info', 'Executing command: $command');

    // Open channel
    final execChannel = LibSSH2.channelOpenSession(session!);
    if (execChannel == null || execChannel!.address == 0) {
      throw Exception('Failed to open channel for command execution');
    }

    final commandPtr = command.toNativeUtf8();
    final output = StringBuffer();

    try {
      // Execute command
      var rc = LibSSH2Error.eagain;
      while (rc == LibSSH2Error.eagain) {
        rc = LibSSH2.channelExec(execChannel, commandPtr);
        if (rc == LibSSH2Error.eagain) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }

      if (rc != 0) {
        final error = _getLastError();
        throw Exception('Failed to execute command: $error');
      }

      // Read output
      final buffer = malloc<Uint8List>(4096);
      try {
        while (true) {
          final bytesRead = LibSSH2.channelRead(execChannel, buffer, 4096);
          if (bytesRead > 0) {
            final data = buffer.asTypedList(bytesRead);
            output.write(utf8.decode(data, allowMalformed: true));
          } else if (bytesRead == 0) {
            if (LibSSH2.channelEof(execChannel) != 0) {
              break;
            }
            await Future.delayed(const Duration(milliseconds: 10));
          } else if (bytesRead == LibSSH2Error.eagain) {
            await Future.delayed(const Duration(milliseconds: 10));
          } else {
            break;
          }
        }
      } finally {
        malloc.free(buffer);
      }

      // Close channel
      LibSSH2.channelClose(execChannel);
      LibSSH2.channelFree(execChannel);
    } finally {
      malloc.free(commandPtr);
    }

    return output.toString();
  }

  Future<void> _write(String data) async {
    if (channel == null || channel!.address == 0) {
      throw StateError('No active channel');
    }

    final bytes = utf8.encode(data);
    final buffer = malloc<Uint8List>(bytes.length);
    buffer.asTypedList(bytes.length).setAll(0, bytes);

    try {
      var written = 0;
      while (written < bytes.length) {
        final rc = LibSSH2.channelWrite(
          channel!,
          buffer.elementAt(written),
          bytes.length - written,
        );

        if (rc > 0) {
          written += rc;
        } else if (rc == LibSSH2Error.eagain) {
          await Future.delayed(const Duration(milliseconds: 10));
        } else {
          final error = _getLastError();
          throw Exception('Write failed: $error');
        }
      }
    } finally {
      malloc.free(buffer);
    }
  }

  Future<void> _resize(int cols, int rows) async {
    if (channel == null || channel!.address == 0) {
      throw StateError('No active channel');
    }

    _log('debug', 'Resizing PTY to ${cols}x${rows}');

    var rc = LibSSH2Error.eagain;
    while (rc == LibSSH2Error.eagain) {
      rc = LibSSH2.channelRequestPtySize(channel!, cols, rows, 0, 0);
      if (rc == LibSSH2Error.eagain) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    if (rc != 0) {
      final error = _getLastError();
      throw Exception('Failed to resize PTY: $error');
    }
  }

  Future<void> _disconnect() async {
    _log('info', 'Disconnecting SSH session');

    readTimer?.cancel();

    if (channel != null && channel!.address != 0) {
      LibSSH2.channelClose(channel!);
      LibSSH2.channelFree(channel!);
      channel = null;
    }

    if (session != null && session!.address != 0) {
      final reasonPtr = 'Client disconnecting'.toNativeUtf8();
      final langPtr = 'en'.toNativeUtf8();

      LibSSH2.sessionDisconnect(
        session!,
        11, // SSH_DISCONNECT_BY_APPLICATION
        reasonPtr,
        langPtr,
      );

      LibSSH2.sessionFree(session!);
      session = null;

      malloc.free(reasonPtr);
      malloc.free(langPtr);
    }

    await socket?.close();
    socket = null;

    LibSSH2.exit();

    _log('info', 'SSH session disconnected');
  }

  String _getLastError() {
    if (session == null || session!.address == 0) return 'No session';

    final errmsgPtr = calloc<Pointer<Utf8>>();
    final errmsgLenPtr = calloc<Int32>();

    try {
      final rc = LibSSH2.sessionLastError(session!, errmsgPtr, errmsgLenPtr, 0);
      if (rc != 0 && errmsgPtr.value.address != 0) {
        return errmsgPtr.value.toDartString();
      }
      return 'Unknown error (code: $rc)';
    } finally {
      calloc.free(errmsgPtr);
      calloc.free(errmsgLenPtr);
    }
  }

  void _reply(SSHMessage request, SSHMessage response) {
    mainSendPort.send(response.toMap());
  }

  void _log(String level, String message) {
    mainSendPort.send(
      SSHMessage(
        id: 0,
        type: SSHMessageType.log,
        data: {'level': level, 'message': message},
      ).toMap(),
    );
  }
}
