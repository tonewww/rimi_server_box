import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:server_box/core/libssh2/ssh_logger.dart';
import 'package:server_box/core/libssh2/ssh_message.dart';

/// High-level SSH client wrapper that mimics dartssh2 interface
/// but uses libssh2 under the hood via process spawning
class LibSSH2Client {
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKeyPath;
  final String? passphrase;
  final Duration timeout;
  final SSHLogger logger;
  
  Process? _process;
  StreamController<Uint8List>? _stdoutController;
  StreamController<Uint8List>? _stderrController;
  StreamController<String>? _stdinController;
  SSHConnectionStatus _status = SSHConnectionStatus.disconnected;
  Stream<List<int>>? _processStdout;
  Stream<List<int>>? _processStderr;
  
  LibSSH2Client({
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.privateKeyPath,
    this.passphrase,
    this.timeout = const Duration(seconds: 30),
    SSHLogger? logger,
  }) : logger = logger ?? SSHLogger();

  Stream<Uint8List> get stdout => _stdoutController?.stream ?? const Stream.empty();
  Stream<Uint8List> get stderr => _stderrController?.stream ?? const Stream.empty();
  SSHConnectionStatus get status => _status;

  /// Connect to SSH server
  Future<void> connect() async {
    logger.info('[CONNECT] Initiating SSH connection to $username@$host:$port');
    
    _stdoutController = StreamController<Uint8List>.broadcast();
    _stderrController = StreamController<Uint8List>.broadcast();
    _stdinController = StreamController<String>.broadcast();
    
    try {
      _status = SSHConnectionStatus.connecting;
      logger.debug('[CONNECT] Building SSH command arguments');
      
      // Build SSH command
      final args = <String>[
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=/dev/null',
        '-o', 'ConnectTimeout=${timeout.inSeconds}',
        '-o', 'ServerAliveInterval=5',
        '-o', 'ServerAliveCountMax=3',
        '-o', 'TCPKeepAlive=yes',
        '-o', 'LogLevel=DEBUG',
        '-p', port.toString(),
      ];
      
      if (privateKeyPath != null) {
        logger.debug('[AUTH] Using private key authentication: $privateKeyPath');
        args.addAll(['-i', privateKeyPath!]);
      }
      
      if (password != null) {
        logger.debug('[AUTH] Password authentication will be used');
        // Note: We'll handle password via sshpass or expect
      }
      
      args.add('$username@$host');
      
      logger.info('[CONNECT] Starting SSH process with args: ${args.join(' ')}');
      
      // Start SSH process
      if (password != null && Platform.isLinux) {
        // Use sshpass for password authentication on Linux
        _process = await Process.start(
          'sshpass',
          ['-p', password!, 'ssh', ...args],
          mode: ProcessStartMode.normal,
        );
      } else {
        _process = await Process.start(
          'ssh',
          args,
          mode: ProcessStartMode.normal,
          environment: {
            'TERM': 'xterm-256color',
            'LC_ALL': 'en_US.UTF-8',
          },
        );
      }
      
      logger.debug('[CONNECT] SSH process started with PID: ${_process!.pid}');
      
      // Setup stream forwarding
      _setupStreamForwarding();
      
      // Wait for connection
      await _waitForConnection();
      
      _status = SSHConnectionStatus.connected;
      logger.info('[CONNECT] SSH connection established successfully');
      
    } catch (e, stack) {
      logger.error('[CONNECT] Failed to connect', e, stack);
      _status = SSHConnectionStatus.error;
      await disconnect();
      rethrow;
    }
  }

  void _setupStreamForwarding() {
    logger.debug('[STREAM] Setting up stream forwarding');
    
    // Convert process streams to broadcast streams (only listen once)
    _processStdout = _process!.stdout.asBroadcastStream();
    _processStderr = _process!.stderr.asBroadcastStream();
    
    // Forward stdout
    _processStdout!.listen(
      (data) {
        logger.debug('[STDOUT] Received ${data.length} bytes');
        _stdoutController?.add(Uint8List.fromList(data));
      },
      onError: (e) {
        logger.error('[STDOUT] Stream error', e);
        _stdoutController?.addError(e);
      },
      onDone: () {
        logger.info('[STDOUT] Stream closed');
        _stdoutController?.close();
      },
    );
    
    // Forward stderr
    _processStderr!.listen(
      (data) {
        final message = utf8.decode(data, allowMalformed: true);
        logger.debug('[STDERR] Received: $message');
        _stderrController?.add(Uint8List.fromList(data));
        
        // Check for authentication errors
        if (message.contains('Permission denied') ||
            message.contains('Authentication failed')) {
          logger.error('[AUTH] Authentication failed');
          _status = SSHConnectionStatus.error;
        }
      },
      onError: (e) {
        logger.error('[STDERR] Stream error', e);
        _stderrController?.addError(e);
      },
      onDone: () {
        logger.info('[STDERR] Stream closed');
        _stderrController?.close();
      },
    );
    
    // Forward stdin
    _stdinController!.stream.listen(
      (data) {
        logger.debug('[STDIN] Writing ${data.length} characters');
        _process!.stdin.write(data);
      },
      onError: (e) {
        logger.error('[STDIN] Stream error', e);
      },
    );
    
    // Monitor process exit
    _process!.exitCode.then((code) {
      logger.info('[PROCESS] SSH process exited with code: $code');
      _status = SSHConnectionStatus.disconnected;
      disconnect();
    });
  }

  Future<void> _waitForConnection() async {
    logger.debug('[CONNECT] Waiting for connection establishment');
    
    final completer = Completer<void>();
    StreamSubscription? subscription;
    Timer? timeoutTimer;
    
    // Set up timeout
    timeoutTimer = Timer(timeout, () {
      logger.error('[CONNECT] Connection timeout after ${timeout.inSeconds} seconds');
      if (!completer.isCompleted) {
        subscription?.cancel();
        completer.completeError(TimeoutException('SSH connection timeout'));
      }
    });
    
    // Listen for connection indicators
    subscription = _processStdout!.listen((data) {
      final output = utf8.decode(data, allowMalformed: true);
      logger.debug('[CONNECT] Checking output for connection: ${output.substring(0, output.length.clamp(0, 100))}');
      
      // Check for common shell prompts or welcome messages
      if (output.contains('\$') || 
          output.contains('#') || 
          output.contains('>') ||
          output.contains('Last login') ||
          output.contains('Welcome')) {
        logger.info('[CONNECT] Connection established - prompt detected');
        if (!completer.isCompleted) {
          timeoutTimer?.cancel();
          subscription?.cancel();
          completer.complete();
        }
      }
    });
    
    // Also check stderr for errors
    _processStderr!.listen((data) {
      final error = utf8.decode(data, allowMalformed: true);
      if (error.contains('Connection refused') ||
          error.contains('No route to host') ||
          error.contains('Permission denied')) {
        logger.error('[CONNECT] Connection error: $error');
        if (!completer.isCompleted) {
          timeoutTimer?.cancel();
          subscription?.cancel();
          completer.completeError(Exception(error));
        }
      }
    });
    
    await completer.future;
    logger.debug('[CONNECT] Connection wait completed');
  }

  /// Execute a command
  Future<String> execute(String command) async {
    logger.info('[EXEC] Executing command: $command');
    
    if (_status != SSHConnectionStatus.connected) {
      throw StateError('Not connected');
    }
    
    final output = StringBuffer();
    final completer = Completer<String>();
    
    // Create unique markers
    final startMarker = '<<<START_${DateTime.now().millisecondsSinceEpoch}>>>';
    final endMarker = '<<<END_${DateTime.now().millisecondsSinceEpoch}>>>';
    
    logger.debug('[EXEC] Using markers: $startMarker, $endMarker');
    
    StreamSubscription? subscription;
    Timer? timeoutTimer;
    
    // Set up timeout
    timeoutTimer = Timer(timeout, () {
      logger.error('[EXEC] Command execution timeout');
      if (!completer.isCompleted) {
        subscription?.cancel();
        completer.completeError(TimeoutException('Command execution timeout'));
      }
    });
    
    // Listen for output
    var capturing = false;
    subscription = _stdoutController!.stream.listen((data) {
      final text = utf8.decode(data, allowMalformed: true);
      
      if (text.contains(startMarker)) {
        logger.debug('[EXEC] Start marker detected, beginning capture');
        capturing = true;
        final parts = text.split(startMarker);
        if (parts.length > 1) {
          final afterMarker = parts[1];
          if (afterMarker.contains(endMarker)) {
            final content = afterMarker.split(endMarker)[0];
            output.write(content);
            capturing = false;
            logger.debug('[EXEC] End marker detected, capture complete');
            if (!completer.isCompleted) {
              timeoutTimer?.cancel();
              subscription?.cancel();
              completer.complete(output.toString());
            }
          } else {
            output.write(afterMarker);
          }
        }
      } else if (capturing) {
        if (text.contains(endMarker)) {
          final content = text.split(endMarker)[0];
          output.write(content);
          capturing = false;
          logger.debug('[EXEC] End marker detected, capture complete');
          if (!completer.isCompleted) {
            timeoutTimer?.cancel();
            subscription?.cancel();
            completer.complete(output.toString());
          }
        } else {
          output.write(text);
        }
      }
    });
    
    // Send command with markers
    logger.debug('[EXEC] Sending command with markers');
    write('echo "$startMarker" && $command && echo "$endMarker"\n');
    
    final result = await completer.future;
    logger.debug('[EXEC] Command completed, output length: ${result.length}');
    return result;
  }

  /// Open a shell session
  Future<LibSSH2Session> shell({
    String termType = 'xterm-256color',
    int cols = 80,
    int rows = 24,
    Map<String, String>? environment,
  }) async {
    logger.info('[SHELL] Opening shell session (term=$termType, cols=$cols, rows=$rows)');
    
    if (_status != SSHConnectionStatus.connected) {
      throw StateError('Not connected');
    }
    
    // Set terminal size
    logger.debug('[SHELL] Setting terminal size');
    write('stty cols $cols rows $rows\n');
    
    // Set environment variables
    if (environment != null) {
      logger.debug('[SHELL] Setting ${environment.length} environment variables');
      for (final entry in environment.entries) {
        write('export ${entry.key}="${entry.value}"\n');
      }
    }
    
    // Clear screen
    write('clear\n');
    
    logger.info('[SHELL] Shell session ready');
    
    return LibSSH2Session(
      client: this,
      stdout: stdout,
      stderr: stderr,
      termType: termType,
      cols: cols,
      rows: rows,
    );
  }

  /// Write data to stdin
  void write(String data) {
    logger.debug('[WRITE] Writing ${data.length} characters to stdin');
    _stdinController?.add(data);
  }

  /// Send keep-alive ping
  Future<void> ping() async {
    logger.debug('[PING] Sending keep-alive ping');
    
    try {
      final result = await execute('echo "ping"').timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          logger.warning('[PING] Keep-alive ping timeout');
          throw TimeoutException('Ping timeout');
        },
      );
      
      if (result.trim() == 'ping') {
        logger.debug('[PING] Keep-alive ping successful');
      } else {
        logger.warning('[PING] Unexpected ping response: $result');
      }
    } catch (e) {
      logger.error('[PING] Keep-alive ping failed', e);
      _status = SSHConnectionStatus.disconnected;
      rethrow;
    }
  }

  /// Disconnect and clean up
  Future<void> disconnect() async {
    logger.info('[DISCONNECT] Disconnecting SSH client');
    
    try {
      // Send exit command
      if (_process != null && _status == SSHConnectionStatus.connected) {
        logger.debug('[DISCONNECT] Sending exit command');
        write('exit\n');
        
        // Wait a bit for graceful exit
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Kill process if still running
      if (_process != null) {
        logger.debug('[DISCONNECT] Killing SSH process');
        _process!.kill(ProcessSignal.sigterm);
        
        // Force kill if needed
        await Future.delayed(const Duration(milliseconds: 500));
        if (_process != null) {
          _process!.kill(ProcessSignal.sigkill);
        }
      }
    } catch (e) {
      logger.warning('[DISCONNECT] Error during disconnect', e);
    }
    
    _process = null;
    _status = SSHConnectionStatus.disconnected;
    
    await _stdoutController?.close();
    await _stderrController?.close();
    await _stdinController?.close();
    
    _stdoutController = null;
    _stderrController = null;
    _stdinController = null;
    
    logger.info('[DISCONNECT] SSH client disconnected');
  }
}

/// SSH Session wrapper
class LibSSH2Session {
  final LibSSH2Client client;
  final Stream<Uint8List> stdout;
  final Stream<Uint8List> stderr;
  final String termType;
  int cols;
  int rows;
  
  StreamController<Uint8List>? _stdinController;
  
  LibSSH2Session({
    required this.client,
    required this.stdout,
    required this.stderr,
    required this.termType,
    required this.cols,
    required this.rows,
  }) {
    _stdinController = StreamController<Uint8List>();
    _stdinController!.stream.listen((data) {
      client.write(utf8.decode(data));
    });
  }
  
  Sink<Uint8List> get stdin => _stdinController!.sink;
  
  /// Resize terminal
  Future<void> resizeTerminal(int newCols, int newRows) async {
    client.logger.info('[RESIZE] Resizing terminal to ${newCols}x$newRows');
    cols = newCols;
    rows = newRows;
    client.write('stty cols $newCols rows $newRows\n');
  }
  
  /// Close session
  Future<void> close() async {
    client.logger.info('[SESSION] Closing session');
    await _stdinController?.close();
    _stdinController = null;
  }
  
  /// Get exit code (not supported in this implementation)
  int? get exitCode => null;
}