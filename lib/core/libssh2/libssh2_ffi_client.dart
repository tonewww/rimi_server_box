import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:server_box/core/libssh2/ffi_bindings.dart';
import 'package:server_box/core/libssh2/ssh_logger.dart';

/// Real libssh2 client using FFI bindings
class LibSSH2FFIClient {
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKeyPath;
  final String? publicKeyPath;
  final String? passphrase;
  final Duration timeout;
  final SSHLogger logger;
  
  int _socketFd = -1;  // Native socket file descriptor
  LibSSH2SessionPtr? _session;
  LibSSH2ChannelPtr? _channel;
  
  StreamController<Uint8List>? _stdoutController;
  StreamController<Uint8List>? _stderrController;
  Timer? _readTimer;
  
  LibSSH2FFIClient({
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.privateKeyPath,
    this.publicKeyPath,
    this.passphrase,
    this.timeout = const Duration(seconds: 30),
    SSHLogger? logger,
  }) : logger = logger ?? SSHLogger();

  Stream<Uint8List> get stdout => _stdoutController?.stream ?? const Stream.empty();
  Stream<Uint8List> get stderr => _stderrController?.stream ?? const Stream.empty();
  
  /// Connect to SSH server using libssh2
  Future<void> connect() async {
    logger.info('[FFI] Connecting to $username@$host:$port');
    
    _stdoutController = StreamController<Uint8List>.broadcast();
    _stderrController = StreamController<Uint8List>.broadcast();
    
    try {
      // Initialize libssh2
      logger.debug('[FFI] Initializing libssh2');
      final initResult = LibSSH2.init(0);
      if (initResult != 0) {
        throw Exception('Failed to initialize libssh2: $initResult');
      }
      
      // Create native socket connection
      logger.debug('[FFI] Creating native socket connection');
      try {
        _socketFd = NativeSocket.createAndConnect(host, port);
        logger.info('[FFI] Native socket connected successfully, fd=$_socketFd');
      } catch (e) {
        throw Exception('Failed to create socket connection: $e');
      }
      
      // Create SSH session
      logger.debug('[FFI] Creating SSH session');
      try {
        // Pass NULL for all parameters to use defaults
        _session = LibSSH2.sessionInit(nullptr, nullptr, nullptr, nullptr);
        logger.debug('[FFI] Session pointer: $_session');
        if (_session == nullptr) {
          throw Exception('Failed to create SSH session - session is null');
        }
        logger.debug('[FFI] SSH session created successfully');
      } catch (e, stack) {
        logger.error('[FFI] Failed to create SSH session', e, stack);
        throw Exception('Failed to create SSH session: $e');
      }
      
      // Set non-blocking mode
      try {
        logger.debug('[FFI] Setting non-blocking mode');
        LibSSH2.sessionSetBlocking(_session!, 0);
        logger.debug('[FFI] Non-blocking mode set successfully');
      } catch (e, stack) {
        logger.error('[FFI] Failed to set non-blocking mode', e, stack);
        throw Exception('Failed to set non-blocking mode: $e');
      }
      
      // Perform SSH handshake
      logger.debug('[FFI] Performing SSH handshake with native socket fd=$_socketFd');
      
      int handshakeResult;
      final startTime = DateTime.now();
      do {
        try {
          logger.debug('[FFI] Calling LibSSH2.sessionHandshake...');
          handshakeResult = LibSSH2.sessionHandshake(_session!, _socketFd);
          logger.debug('[FFI] sessionHandshake returned: $handshakeResult');
        } catch (e, stack) {
          logger.error('[FFI] sessionHandshake crashed', e, stack);
          throw Exception('SSH handshake crashed: $e');
        }
        
        if (handshakeResult == LibSSH2Error.eagain) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
        if (DateTime.now().difference(startTime) > timeout) {
          throw TimeoutException('SSH handshake timeout');
        }
      } while (handshakeResult == LibSSH2Error.eagain);
      
      if (handshakeResult != 0) {
        final error = _getLastError();
        throw Exception('SSH handshake failed: $error');
      }
      
      logger.info('[FFI] SSH handshake successful');
      
      // Authenticate
      await _authenticate();
      
      logger.info('[FFI] SSH connection established successfully');
      
      // Start reading from channel
      _startReading();
      
    } catch (e, stack) {
      logger.error('[FFI] Connection failed', e, stack);
      await disconnect();
      rethrow;
    }
  }
  
  /// Authenticate with the server
  Future<void> _authenticate() async {
    logger.info('[FFI] Starting authentication');
    
    final usernamePtr = username.toNativeUtf8();
    
    try {
      if (password != null) {
        // Password authentication
        logger.info('[FFI] Using password authentication');
        final passwordPtr = password!.toNativeUtf8();
        
        try {
          int authResult;
          do {
            authResult = LibSSH2.userauthPassword(
              _session!,
              usernamePtr,
              username.length,
              passwordPtr,
              password!.length,
            );
            if (authResult == LibSSH2Error.eagain) {
              await Future.delayed(const Duration(milliseconds: 10));
            }
          } while (authResult == LibSSH2Error.eagain);
          
          if (authResult != 0) {
            final error = _getLastError();
            throw Exception('Password authentication failed: $error');
          }
          
          logger.info('[FFI] Password authentication successful');
        } finally {
          calloc.free(passwordPtr);
        }
        
      } else if (privateKeyPath != null) {
        // Public key authentication
        logger.info('[FFI] Using public key authentication');
        final privateKeyPtr = privateKeyPath!.toNativeUtf8();
        final publicKeyPtr = (publicKeyPath ?? '').toNativeUtf8();
        final passphrasePtr = (passphrase ?? '').toNativeUtf8();
        
        try {
          int authResult;
          do {
            authResult = LibSSH2.userauthPublicKeyFromFile(
              _session!,
              usernamePtr,
              username.length,
              publicKeyPtr,
              privateKeyPtr,
              passphrasePtr,
            );
            if (authResult == LibSSH2Error.eagain) {
              await Future.delayed(const Duration(milliseconds: 10));
            }
          } while (authResult == LibSSH2Error.eagain);
          
          if (authResult != 0) {
            final error = _getLastError();
            throw Exception('Public key authentication failed: $error');
          }
          
          logger.info('[FFI] Public key authentication successful');
        } finally {
          calloc.free(privateKeyPtr);
          calloc.free(publicKeyPtr);
          calloc.free(passphrasePtr);
        }
        
      } else {
        throw Exception('No authentication method provided');
      }
    } finally {
      calloc.free(usernamePtr);
    }
  }
  
  /// Get last error message from libssh2
  String _getLastError() {
    if (_session == null || _session == nullptr) {
      return 'No session';
    }
    
    final errmsgPtr = calloc<Pointer<Utf8>>();
    final errmsgLenPtr = calloc<Int32>();
    
    try {
      final errorCode = LibSSH2.sessionLastError(
        _session!,
        errmsgPtr,
        errmsgLenPtr,
        0,
      );
      
      if (errmsgPtr.value != nullptr) {
        return errmsgPtr.value.toDartString();
      }
      
      return 'Error code: $errorCode';
    } finally {
      calloc.free(errmsgPtr);
      calloc.free(errmsgLenPtr);
    }
  }
  
  /// Start reading from channel
  void _startReading() {
    if (_channel == null || _channel == nullptr) return;
    
    _readTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _readChannelData();
    });
  }
  
  /// Read data from channel
  void _readChannelData() {
    if (_channel == null || _channel == nullptr) return;
    
    final buffer = calloc<Uint8>(4096);
    
    try {
      // Read stdout (stream_id = 0)
      final bytesRead = LibSSH2.channelReadEx(_channel!, 0, buffer, 4096);
      if (bytesRead > 0) {
        final data = Uint8List.fromList(buffer.asTypedList(bytesRead));
        _stdoutController?.add(data);
      }
      
      // Read stderr (stream_id = 1 for SSH_EXTENDED_DATA_STDERR)
      final stderrBytesRead = LibSSH2.channelReadEx(_channel!, 1, buffer, 4096);
      if (stderrBytesRead > 0) {
        final data = Uint8List.fromList(buffer.asTypedList(stderrBytesRead));
        _stderrController?.add(data);
      }
    } finally {
      calloc.free(buffer);
    }
  }
  
  /// Open a shell session
  Future<LibSSH2FFISession> shell({
    String termType = 'xterm-256color',
    int cols = 80,
    int rows = 24,
    Map<String, String>? environment,
  }) async {
    logger.info('[FFI] Opening shell session');
    
    if (_session == null || _session == nullptr) {
      throw StateError('Not connected');
    }
    
    // Open channel
    logger.debug('[FFI] Opening channel');
    final sessionTypePtr = 'session'.toNativeUtf8();
    final emptyMessagePtr = ''.toNativeUtf8();
    
    try {
      // Keep trying to open channel (non-blocking mode)
      final startTime = DateTime.now();
      while (true) {
        _channel = LibSSH2.channelOpenSession(
          _session!,
          sessionTypePtr,
          7, // 'session' length
          2097152, // Default window size (2MB)
          32768,   // Default packet size (32KB)
          emptyMessagePtr,
          0,
        );
        
        if (_channel != nullptr) {
          break; // Success
        }
        
        // Check if it's EAGAIN (would block)
        final errorCode = LibSSH2.sessionLastError(
          _session!,
          calloc<Pointer<Utf8>>(),
          calloc<Int32>(),
          0,
        );
        
        if (errorCode == LibSSH2Error.eagain) {
          // Non-blocking mode, try again
          await Future.delayed(const Duration(milliseconds: 10));
          
          if (DateTime.now().difference(startTime) > timeout) {
            throw TimeoutException('Channel open timeout');
          }
        } else {
          // Real error
          final error = _getLastError();
          throw Exception('Failed to open channel: $error');
        }
      }
    } finally {
      calloc.free(sessionTypePtr);
      calloc.free(emptyMessagePtr);
    }
    
    // Request PTY
    logger.debug('[FFI] Requesting PTY');
    final termTypePtr = termType.toNativeUtf8();
    final modesPtr = ''.toNativeUtf8();
    
    try {
      int ptyResult;
      do {
        ptyResult = LibSSH2.channelRequestPtyEx(
          _channel!,
          termTypePtr,
          termType.length,
          modesPtr,
          0,
          cols,
          rows,
          0,
          0,
        );
        if (ptyResult == LibSSH2Error.eagain) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      } while (ptyResult == LibSSH2Error.eagain);
      
      if (ptyResult != 0) {
        final error = _getLastError();
        throw Exception('Failed to request PTY: $error');
      }
    } finally {
      calloc.free(termTypePtr);
      calloc.free(modesPtr);
    }
    
    // Set environment variables
    if (environment != null) {
      for (final entry in environment.entries) {
        final keyPtr = entry.key.toNativeUtf8();
        final valuePtr = entry.value.toNativeUtf8();
        
        try {
          LibSSH2.channelSetEnv(_channel!, keyPtr, valuePtr);
        } finally {
          calloc.free(keyPtr);
          calloc.free(valuePtr);
        }
      }
    }
    
    // Start shell
    logger.debug('[FFI] Starting shell');
    final shellRequest = 'shell'.toNativeUtf8();
    final nullPtr = nullptr;
    int shellResult;
    do {
      shellResult = LibSSH2.channelProcessStartup(
        _channel!, 
        shellRequest, 
        'shell'.length,
        nullPtr,
        0
      );
      if (shellResult == LibSSH2Error.eagain) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    } while (shellResult == LibSSH2Error.eagain);
    malloc.free(shellRequest);
    
    if (shellResult != 0) {
      final error = _getLastError();
      throw Exception('Failed to start shell: $error');
    }
    
    logger.info('[FFI] Shell session opened successfully');
    
    // Start reading
    _startReading();
    
    return LibSSH2FFISession(
      client: this,
      stdout: stdout,
      stderr: stderr,
      termType: termType,
      cols: cols,
      rows: rows,
    );
  }
  
  /// Execute a command
  Future<String> execute(String command) async {
    logger.info('[FFI] Executing command: $command');
    
    if (_session == null || _session == nullptr) {
      throw StateError('Not connected');
    }
    
    // Open channel for command
    final sessionTypePtr = 'session'.toNativeUtf8();
    final emptyMessagePtr = ''.toNativeUtf8();
    
    LibSSH2ChannelPtr? channel;
    try {
      // Keep trying to open channel (non-blocking mode)
      final startTime = DateTime.now();
      while (true) {
        channel = LibSSH2.channelOpenSession(
          _session!,
          sessionTypePtr,
          7, // 'session' length
          2097152, // Default window size (2MB)
          32768,   // Default packet size (32KB)
          emptyMessagePtr,
          0,
        );
        
        if (channel != nullptr) {
          break; // Success
        }
        
        // Check if it's EAGAIN (would block)
        final errorCode = LibSSH2.sessionLastError(
          _session!,
          calloc<Pointer<Utf8>>(),
          calloc<Int32>(),
          0,
        );
        
        if (errorCode == LibSSH2Error.eagain) {
          // Non-blocking mode, try again
          await Future.delayed(const Duration(milliseconds: 10));
          
          if (DateTime.now().difference(startTime) > timeout) {
            throw TimeoutException('Channel open timeout');
          }
        } else {
          // Real error
          final error = _getLastError();
          throw Exception('Failed to open channel: $error');
        }
      }
    } finally {
      calloc.free(sessionTypePtr);
      calloc.free(emptyMessagePtr);
    }
    
    
    final commandPtr = command.toNativeUtf8();
    
    try {
      // Execute command
      final execRequest = 'exec'.toNativeUtf8();
      int execResult;
      do {
        execResult = LibSSH2.channelProcessStartup(
          channel,
          execRequest,
          'exec'.length,
          commandPtr,
          command.length
        );
        if (execResult == LibSSH2Error.eagain) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      } while (execResult == LibSSH2Error.eagain);
      malloc.free(execRequest);
      
      if (execResult != 0) {
        final error = _getLastError();
        LibSSH2.channelFree(channel);
        throw Exception('Failed to execute command: $error');
      }
      
      // Read output
      final output = StringBuffer();
      final buffer = calloc<Uint8>(4096);
      
      try {
        while (true) {
          final bytesRead = LibSSH2.channelReadEx(channel, 0, buffer, 4096);
          if (bytesRead == 0) {
            if (LibSSH2.channelEof(channel) != 0) {
              break;
            }
            await Future.delayed(const Duration(milliseconds: 10));
          } else if (bytesRead > 0) {
            output.write(utf8.decode(buffer.asTypedList(bytesRead)));
          } else if (bytesRead == LibSSH2Error.eagain) {
            await Future.delayed(const Duration(milliseconds: 10));
          } else {
            break;
          }
        }
      } finally {
        calloc.free(buffer);
      }
      
      // Close channel
      LibSSH2.channelClose(channel);
      LibSSH2.channelWaitClosed(channel);
      LibSSH2.channelFree(channel);
      
      logger.debug('[FFI] Command completed');
      return output.toString();
      
    } finally {
      calloc.free(commandPtr);
    }
  }
  
  /// Write data to stdin
  void write(String data) {
    if (_channel == null || _channel == nullptr) {
      logger.warning('[FFI] Cannot write: no channel');
      return;
    }
    
    logger.debug('[FFI] Writing ${data.length} bytes');
    
    final bytes = utf8.encode(data);
    final buffer = calloc<Uint8>(bytes.length);
    
    try {
      for (int i = 0; i < bytes.length; i++) {
        buffer[i] = bytes[i];
      }
      
      int written = 0;
      while (written < bytes.length) {
        final result = LibSSH2.channelWriteEx(
          _channel!,
          0, // stream_id = 0 for stdout
          buffer + written,
          bytes.length - written,
        );
        
        if (result > 0) {
          written += result;
        } else if (result == LibSSH2Error.eagain) {
          // Non-blocking mode, try again
          Future.delayed(const Duration(milliseconds: 1));
        } else {
          logger.error('[FFI] Write error: $result');
          break;
        }
      }
    } finally {
      calloc.free(buffer);
    }
  }
  
  /// Send keep-alive ping
  Future<void> ping() async {
    logger.debug('[FFI] Sending keep-alive');
    // libssh2 handles keep-alive internally with proper configuration
    // This is a no-op for now
  }
  
  /// Resize terminal
  Future<void> resizeTerminal(int cols, int rows) async {
    if (_channel == null || _channel == nullptr) {
      logger.warning('[FFI] Cannot resize: no channel');
      return;
    }
    
    logger.info('[FFI] Resizing terminal to ${cols}x${rows}');
    
    int result;
    do {
      result = LibSSH2.channelRequestPtySize(_channel!, cols, rows, 0, 0);
      if (result == LibSSH2Error.eagain) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    } while (result == LibSSH2Error.eagain);
    
    if (result != 0) {
      logger.warning('[FFI] Failed to resize terminal: $result');
    }
  }
  
  /// Disconnect and clean up
  Future<void> disconnect() async {
    logger.info('[FFI] Disconnecting');
    
    _readTimer?.cancel();
    _readTimer = null;
    
    if (_channel != null && _channel != nullptr) {
      LibSSH2.channelClose(_channel!);
      LibSSH2.channelFree(_channel!);
      _channel = null;
    }
    
    if (_session != null && _session != nullptr) {
      final reasonPtr = 'Client disconnecting'.toNativeUtf8();
      final langPtr = 'en'.toNativeUtf8();
      
      try {
        LibSSH2.sessionDisconnect(
          _session!,
          11, // SSH_DISCONNECT_BY_APPLICATION
          reasonPtr,
          langPtr,
        );
      } finally {
        calloc.free(reasonPtr);
        calloc.free(langPtr);
      }
      
      LibSSH2.sessionFree(_session!);
      _session = null;
    }
    
    if (_socketFd >= 0) {
      NativeSocket.closeSocket(_socketFd);
      _socketFd = -1;
    }
    
    await _stdoutController?.close();
    await _stderrController?.close();
    _stdoutController = null;
    _stderrController = null;
    
    logger.info('[FFI] Disconnected');
  }
}

/// SSH session for FFI client
class LibSSH2FFISession {
  final LibSSH2FFIClient client;
  final Stream<Uint8List> stdout;
  final Stream<Uint8List> stderr;
  final String termType;
  int cols;
  int rows;
  
  StreamController<Uint8List>? _stdinController;
  
  LibSSH2FFISession({
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
    cols = newCols;
    rows = newRows;
    await client.resizeTerminal(newCols, newRows);
  }
  
  /// Close session
  Future<void> close() async {
    client.logger.info('[SESSION] Closing session');
    await _stdinController?.close();
    _stdinController = null;
  }
  
  /// Get exit code
  int? get exitCode => null; // Will be implemented when channel tracking is added
}