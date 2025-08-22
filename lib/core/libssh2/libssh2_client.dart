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
  String? _pendingPassword;
  bool _passwordSentGlobal = false;
  
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
  
  /// Check if a command is available in the system
  Future<bool> _isCommandAvailable(String command) async {
    try {
      // For absolute paths, check if file exists
      if (command.startsWith('/')) {
        final file = File(command);
        return await file.exists();
      }
      // For command names, use which
      final result = await Process.run('which', [command]);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

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
        // When using key auth, disable password authentication to avoid prompts
        args.addAll(['-o', 'PasswordAuthentication=no']);
        args.addAll(['-o', 'PreferredAuthentications=publickey']);
        args.addAll(['-o', 'PubkeyAuthentication=yes']);
      } else if (password != null) {
        logger.debug('[AUTH] Password authentication will be used');
        // When using password auth, disable public key authentication
        args.addAll(['-o', 'PasswordAuthentication=yes']);
        args.addAll(['-o', 'PreferredAuthentications=password']);
        args.addAll(['-o', 'PubkeyAuthentication=no']);
      } else {
        logger.warning('[AUTH] No authentication method specified, using default');
        // Let SSH use its default authentication order
      }
      
      args.add('$username@$host');
      
      logger.info('[CONNECT] Starting SSH process with args: ${args.join(' ')}');
      
      // Start SSH process
      if (password != null) {
        // Check for sshpass in common locations (especially for macOS)
        logger.info('[AUTH] Checking for sshpass for password authentication');
        
        final sshpassPaths = [
          '/opt/homebrew/bin/sshpass',  // Apple Silicon homebrew path
          '/usr/local/bin/sshpass',      // Intel homebrew path
          'sshpass',                      // System PATH
        ];
        
        String? sshpassPath;
        for (final path in sshpassPaths) {
          if (await _isCommandAvailable(path)) {
            sshpassPath = path;
            logger.info('[AUTH] Found sshpass at: $path');
            break;
          }
        }
        
        if (sshpassPath != null) {
          logger.info('[AUTH] Using sshpass for password authentication');
          _process = await Process.start(
            sshpassPath,
            ['-p', password!, 'ssh', ...args],
            mode: ProcessStartMode.normal,
            environment: {
              'TERM': 'xterm-256color',
              'LC_ALL': 'en_US.UTF-8',
            },
          );
        } else if (Platform.isMacOS) {
          logger.warning('[AUTH] sshpass not found in common locations');
          logger.error('[AUTH] Please install sshpass: brew install hudochenkov/sshpass/sshpass');
          throw Exception('sshpass is required for password authentication on macOS. Please install it with: brew install hudochenkov/sshpass/sshpass');
        } else {
          // On Linux, try to use SSH directly with password (won't work but try anyway)
          logger.warning('[AUTH] sshpass not found, attempting direct SSH (may fail for password auth)');
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
    
    // Buffer for accumulating stderr to detect password prompts
    final stderrBuffer = StringBuffer();
    
    // Forward stdout
    _processStdout!.listen(
      (data) {
        final output = utf8.decode(data, allowMalformed: true);
        logger.debug('[STDOUT] Received ${data.length} bytes: ${output.replaceAll('\n', '\\n').replaceAll('\r', '\\r')}');
        _stdoutController?.add(Uint8List.fromList(data));
        
        // Also check stdout for password prompt (sometimes appears here)
        if (!_passwordSentGlobal && _pendingPassword != null && 
            (output.contains("'s password:") || output.endsWith("password: "))) {
          logger.info('[AUTH] Password prompt detected in stdout, sending password');
          logger.debug('[AUTH] Stdout when prompt detected: "$output"');
          _passwordSentGlobal = true;
          _process!.stdin.write(_pendingPassword!);
          _process!.stdin.write('\n');
          _process!.stdin.flush();
          logger.debug('[AUTH] Password sent from stdout handler');
          _pendingPassword = null;
        }
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
        
        // Accumulate stderr for password prompt detection
        stderrBuffer.write(message);
        final buffered = stderrBuffer.toString();
        
        // Check for password prompt in accumulated buffer
        // The prompt appears as "user@host's password: " without newline
        if (!_passwordSentGlobal && _pendingPassword != null) {
          if (buffered.endsWith("'s password: ") || 
              buffered.contains("'s password:")) {
            logger.info('[AUTH] Password prompt detected in stderr stream handler');
            logger.debug('[AUTH] Buffer content: \'$buffered\'');
            _passwordSentGlobal = true;
            stderrBuffer.clear();
            
            logger.debug('[AUTH] Writing password to stdin from stderr handler');
            _process!.stdin.write(_pendingPassword!);
            _process!.stdin.write('\n');
            _process!.stdin.flush();
            logger.debug('[AUTH] Password sent and flushed from stderr handler');
            _pendingPassword = null;
          }
        }
        
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
    StreamSubscription? stderrSubscription;
    StreamSubscription? stdoutSubscription;
    Timer? timeoutTimer;
    bool passwordSent = false;
    bool authSuccess = false;
    
    // For macOS with expect, we need different connection detection
    final isUsingExpect = password != null && Platform.isMacOS;
    
    // Set up timeout - shorter for expect since it handles its own timeout
    final connectionTimeout = isUsingExpect ? const Duration(seconds: 10) : timeout;
    timeoutTimer = Timer(connectionTimeout, () {
      logger.error('[CONNECT] Connection timeout after ${connectionTimeout.inSeconds} seconds');
      if (!completer.isCompleted) {
        stderrSubscription?.cancel();
        stdoutSubscription?.cancel();
        completer.completeError(TimeoutException('SSH connection timeout'));
      }
    });
    
    // Buffer to accumulate stderr messages for password prompt detection
    final stderrBuffer = StringBuffer();
    
    // Listen for password prompt in stderr
    stderrSubscription = _processStderr!.listen((data) async {
      final error = utf8.decode(data, allowMalformed: true);
      
      // Add to buffer for password prompt detection
      stderrBuffer.write(error);
      final bufferedError = stderrBuffer.toString();
      
      // Log all stderr for debugging password prompt detection
      logger.debug('[AUTH] Stderr buffer content: ${bufferedError.replaceAll('\n', '\\n').replaceAll('\r', '\\r')}');
      
      // Check for password prompt (for macOS direct password handling)
      // The password prompt appears as "ptw@192.168.50.7's password: " in stderr
      if (!passwordSent && !_passwordSentGlobal && _pendingPassword != null) {
        // Check if buffer ends with password prompt (no newline after prompt)
        if (bufferedError.endsWith("'s password: ") || 
            bufferedError.contains("'s password:")) {
          logger.info('[AUTH] Password prompt detected in waitForConnection');
          logger.debug('[AUTH] Buffer when prompt detected: "$bufferedError"');
          logger.debug('[AUTH] Sending password: ${_pendingPassword!.replaceAll(RegExp(r'.'), '*')}');
          
          passwordSent = true;
          _passwordSentGlobal = true;
          // Clear buffer after detecting password prompt
          stderrBuffer.clear();
          
          // Send password to stdin
          _process!.stdin.write(_pendingPassword!);
          _process!.stdin.write('\n');
          await _process!.stdin.flush();
          logger.debug('[AUTH] Password written to stdin and flushed');
          _pendingPassword = null; // Clear password after use
          
          // After sending password, wait for authentication result
          // Give SSH some time to process the password
          Future.delayed(const Duration(milliseconds: 1000), () {
            // Send a simple command to trigger prompt output
            if (!authSuccess && !completer.isCompleted) {
              logger.debug('[AUTH] Sending echo command to verify connection');
              _process!.stdin.write('echo "SSH_CONNECTED"\n');
              _process!.stdin.flush();
              logger.debug('[AUTH] Echo command sent');
            }
          });
        }
      }
      
      // Check for authentication success in debug messages
      if (error.contains('debug1: Authentication succeeded')) {
        logger.info('[AUTH] Authentication succeeded');
        authSuccess = true;
        // Authentication succeeded, but shell might not be ready yet
        // Send a command to trigger prompt
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!completer.isCompleted) {
            _process!.stdin.write('echo "SSH_CONNECTED"\n');
            _process!.stdin.flush();
          }
        });
      }
      
      // Check for connection errors
      if (error.contains('Connection refused') ||
          error.contains('No route to host') ||
          (error.contains('Permission denied') && passwordSent)) {
        logger.error('[CONNECT] Connection error: $error');
        if (!completer.isCompleted) {
          timeoutTimer?.cancel();
          stderrSubscription?.cancel();
          stdoutSubscription?.cancel();
          completer.completeError(Exception(error));
        }
      }
    });
    
    // Listen for connection success in stdout
    stdoutSubscription = _processStdout!.listen((data) {
      final output = utf8.decode(data, allowMalformed: true);
      logger.debug('[CONNECT] Stdout received (${data.length} bytes): ${output.replaceAll('\n', '\\n').replaceAll('\r', '\\r')}');
      
      // For expect, look for spawn command or debug output
      if (isUsingExpect && output.contains('spawn ssh')) {
        logger.debug('[CONNECT] Expect spawn command detected, waiting for actual connection');
        return;
      }
      
      // Check for our connection verification echo or common shell prompts
      final hasConnectedMarker = output.contains('SSH_CONNECTED');
      final hasDollarPrompt = output.contains('\$');
      final hasHashPrompt = output.contains('#');
      final hasArrowPrompt = output.contains('>');
      final hasTildePrompt = output.contains('~]') || output.contains(':~');
      final hasAtSymbol = output.contains('@');
      final hasLastLogin = output.contains('Last login');
      final hasWelcome = output.contains('Welcome');
      
      logger.debug('[CONNECT] Prompt detection: connected=$hasConnectedMarker, \$=$hasDollarPrompt, #=$hasHashPrompt, >=$hasArrowPrompt, ~=$hasTildePrompt, @=$hasAtSymbol, lastlogin=$hasLastLogin, welcome=$hasWelcome');
      
      if (hasConnectedMarker ||
          hasDollarPrompt || 
          hasHashPrompt || 
          hasArrowPrompt ||
          hasTildePrompt ||
          (hasAtSymbol && (output.contains(':~') || output.contains(':/'))) ||
          hasLastLogin ||
          hasWelcome) {
        logger.info('[CONNECT] Connection established - prompt detected in output: "${output.substring(0, output.length.clamp(0, 50))}"');
        if (!completer.isCompleted) {
          timeoutTimer?.cancel();
          stderrSubscription?.cancel();
          stdoutSubscription?.cancel();
          completer.complete();
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
    _passwordSentGlobal = false;
    _pendingPassword = null;
    
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