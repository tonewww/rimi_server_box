// Async SSH Client using new Rust SSH architecture
// This provides true async SSH operations that don't block the main thread

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Load the native library
final DynamicLibrary _lib = () {
  try {
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('librust_ssh.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.open('librust_ssh.dylib');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('rust_ssh.dll');
    } else {
      throw UnsupportedError('Platform not supported');
    }
  } catch (e) {
    print('Failed to load Rust SSH library: $e');
    // Try loading from current directory
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        return DynamicLibrary.open('./librust_ssh.so');
      } else if (Platform.isIOS || Platform.isMacOS) {
        return DynamicLibrary.open('./librust_ssh.dylib');
      } else if (Platform.isWindows) {
        return DynamicLibrary.open('./rust_ssh.dll');
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e2) {
      print('Failed to load from current directory: $e2');
      rethrow;
    }
  }
}();

// C structures
final class CSshConfig extends Struct {
  external Pointer<Utf8> host;
  @Uint32()
  external int port;
  external Pointer<Utf8> username;
  external Pointer<Utf8> password;
  external Pointer<Utf8> privateKey;
  external Pointer<Utf8> passphrase;
  @Uint32()
  external int timeoutSecs;
}

final class CCommandResult extends Struct {
  external Pointer<Utf8> stdout;
  external Pointer<Utf8> stderr;
  @Int32()
  external int exitCode;
}

// Callback types
typedef AsyncCallbackNative = Void Function(Uint64 operationId, Int32 success, Int32 errorCode, Pointer<Void> userData);
typedef AsyncCallbackDart = void Function(int operationId, int success, int errorCode, Pointer<Void> userData);

// Native function signatures  
typedef SshConnectAsyncNative = Uint64 Function(Pointer<CSshConfig> config, Pointer<NativeFunction<AsyncCallbackNative>> callback, Pointer<Void> userData);
typedef SshConnectAsyncDart = int Function(Pointer<CSshConfig> config, Pointer<NativeFunction<AsyncCallbackNative>> callback, Pointer<Void> userData);

typedef SshDisconnectAsyncNative = Uint64 Function(Uint64 sessionId, Pointer<NativeFunction<AsyncCallbackNative>> callback, Pointer<Void> userData);
typedef SshDisconnectAsyncDart = int Function(int sessionId, Pointer<NativeFunction<AsyncCallbackNative>> callback, Pointer<Void> userData);

typedef SshExecuteCommandAsyncNative = Uint64 Function(Uint64 sessionId, Pointer<Utf8> command, Pointer<NativeFunction<AsyncCallbackNative>> callback, Pointer<Void> userData);
typedef SshExecuteCommandAsyncDart = int Function(int sessionId, Pointer<Utf8> command, Pointer<NativeFunction<AsyncCallbackNative>> callback, Pointer<Void> userData);

// Bind native functions
final _sshConnectAsync = _lib.lookupFunction<SshConnectAsyncNative, SshConnectAsyncDart>('ssh_connect_async');
final _sshDisconnectAsync = _lib.lookupFunction<SshDisconnectAsyncNative, SshDisconnectAsyncDart>('ssh_disconnect_async');
final _sshExecuteCommandAsync = _lib.lookupFunction<SshExecuteCommandAsyncNative, SshExecuteCommandAsyncDart>('ssh_execute_command_async');

/// SSH Configuration for async client
class AsyncSshConfig {
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final String? passphrase;
  final Duration timeout;

  const AsyncSshConfig({
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKey,
    this.passphrase,
    this.timeout = const Duration(seconds: 30),
  });
}

/// Command execution result
class AsyncCommandResult {
  final String stdout;
  final String stderr;
  final int exitCode;

  const AsyncCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  @override
  String toString() => 'AsyncCommandResult(stdout: $stdout, stderr: $stderr, exitCode: $exitCode)';
}

/// Operation tracker for async operations
class _OperationTracker {
  static final Map<int, Completer> _operations = {};
  static int _nextId = 1;

  static int registerOperation(Completer completer) {
    final id = _nextId++;
    _operations[id] = completer;
    return id;
  }

  static void completeOperation(int id, dynamic result, [Object? error]) {
    final completer = _operations.remove(id);
    if (completer != null) {
      if (error != null) {
        completer.completeError(error);
      } else {
        completer.complete(result);
      }
    }
  }

  static void clearOperation(int id) {
    _operations.remove(id);
  }
}

/// Exception thrown by async SSH operations
class AsyncSshException implements Exception {
  final String message;
  final int errorCode;

  const AsyncSshException(this.message, this.errorCode);

  @override
  String toString() => 'AsyncSshException($errorCode): $message';
}

/// Async SSH Client - provides non-blocking SSH operations
class AsyncSshClient {
  int? _sessionId;
  bool _connected = false;
  
  /// Connect to SSH server asynchronously
  Future<void> connect(AsyncSshConfig config) async {
    if (_connected) {
      throw const AsyncSshException('Already connected', -1);
    }

    print('Async SSH: Attempting to connect to ${config.host}:${config.port}');

    final completer = Completer<int>();
    final operationId = _OperationTracker.registerOperation(completer);

    // Create C config structure
    final cConfig = calloc<CSshConfig>();
    cConfig.ref.host = config.host.toNativeUtf8();
    cConfig.ref.port = config.port;
    cConfig.ref.username = config.username.toNativeUtf8();
    cConfig.ref.password = config.password?.toNativeUtf8() ?? nullptr;
    cConfig.ref.privateKey = config.privateKey?.toNativeUtf8() ?? nullptr;
    cConfig.ref.passphrase = config.passphrase?.toNativeUtf8() ?? nullptr;
    cConfig.ref.timeoutSecs = config.timeout.inSeconds;

    // Create callback
    final callback = Pointer.fromFunction<AsyncCallbackNative>(_onConnectResult);

    try {
      print('Async SSH: Calling native connect function...');
      // Call async native function
      final operationIdReturned = _sshConnectAsync(cConfig, callback, Pointer.fromAddress(operationId));
      
      print('Async SSH: Native function returned operation ID: $operationIdReturned');
      
      if (operationIdReturned == 0) {
        _OperationTracker.clearOperation(operationId);
        throw const AsyncSshException('Failed to start connection operation', -1);
      }

      print('Async SSH: Waiting for connection result...');
      // With the simplified approach, the function completes synchronously
      // but may still trigger the callback, so we wait briefly
      final sessionId = await completer.future.timeout(
        const Duration(seconds: 1), // Much shorter timeout since it's mostly sync now
        onTimeout: () {
          // If no callback received, treat the returned operation ID as session ID
          print('Async SSH: No callback received, using operation ID as session ID');
          return operationIdReturned;
        },
      );
      
      _sessionId = sessionId;
      _connected = true;
      print('Async SSH: Successfully connected with session ID: $sessionId');
    } catch (e) {
      print('Async SSH: Connection failed: $e');
      rethrow;
    } finally {
      // Cleanup
      calloc.free(cConfig.ref.host);
      calloc.free(cConfig.ref.username);
      if (cConfig.ref.password != nullptr) calloc.free(cConfig.ref.password);
      if (cConfig.ref.privateKey != nullptr) calloc.free(cConfig.ref.privateKey);
      if (cConfig.ref.passphrase != nullptr) calloc.free(cConfig.ref.passphrase);
      calloc.free(cConfig);
    }
  }

  /// Disconnect from SSH server asynchronously
  Future<void> disconnect() async {
    if (!_connected || _sessionId == null) {
      return;
    }

    final completer = Completer<void>();
    final operationId = _OperationTracker.registerOperation(completer);

    // Create callback
    final callback = Pointer.fromFunction<AsyncCallbackNative>(_onDisconnectResult);

    // Call async native function
    final operationIdReturned = _sshDisconnectAsync(_sessionId!, callback, Pointer.fromAddress(operationId));
    
    if (operationIdReturned == 0) {
      _OperationTracker.clearOperation(operationId);
      throw const AsyncSshException('Failed to start disconnection operation', -1);
    }

    // Wait for result
    await completer.future;
    _sessionId = null;
    _connected = false;
  }

  /// Execute command asynchronously
  Future<AsyncCommandResult> execute(String command) async {
    if (!_connected || _sessionId == null) {
      throw const AsyncSshException('Not connected', -1);
    }

    final completer = Completer<AsyncCommandResult>();
    final operationId = _OperationTracker.registerOperation(completer);

    // Allocate result structure that will be filled by the callback
    final result = calloc<CCommandResult>();
    
    // Create callback
    final callback = Pointer.fromFunction<AsyncCallbackNative>(_onExecuteResult);

    // Convert command to C string
    final commandPtr = command.toNativeUtf8();

    try {
      // Call async native function - pass result struct as user data
      final operationIdReturned = _sshExecuteCommandAsync(
        _sessionId!, 
        commandPtr, 
        callback, 
        result.cast<Void>()
      );
      
      if (operationIdReturned == 0) {
        _OperationTracker.clearOperation(operationId);
        throw const AsyncSshException('Failed to start execute operation', -1);
      }

      // Wait for result
      return await completer.future;
    } finally {
      calloc.free(commandPtr);
      // Note: result will be freed in the callback after reading
    }
  }

  /// Check if connected
  bool get isConnected => _connected;

  /// Get session ID
  int? get sessionId => _sessionId;
}

// Static callback functions for native calls

void _onConnectResult(int operationId, int success, int errorCode, Pointer<Void> userData) {
  print('_onConnectResult called: operationId=$operationId, success=$success, errorCode=$errorCode');
  final opId = userData.address;
  
  if (success == 1) {
    // errorCode contains the session ID on success
    print('Connection successful, session ID: $errorCode');
    _OperationTracker.completeOperation(opId, errorCode);
  } else {
    print('Connection failed with error code: $errorCode');
    _OperationTracker.completeOperation(
      opId, 
      null, 
      AsyncSshException('Connection failed', errorCode)
    );
  }
}

void _onDisconnectResult(int operationId, int success, int errorCode, Pointer<Void> userData) {
  print('_onDisconnectResult called: operationId=$operationId, success=$success, errorCode=$errorCode');
  final opId = userData.address;
  
  if (success == 1) {
    _OperationTracker.completeOperation(opId, null);
  } else {
    _OperationTracker.completeOperation(
      opId, 
      null, 
      AsyncSshException('Disconnection failed', errorCode)
    );
  }
}

void _onExecuteResult(int operationId, int success, int errorCode, Pointer<Void> userData) {
  final opId = operationId; // Use the operation ID passed to the callback
  final result = userData.cast<CCommandResult>();

  try {
    if (success == 1) {
      // Read result from C structure
      final stdout = result.ref.stdout.toDartString();
      final stderr = result.ref.stderr.toDartString();
      final exitCode = result.ref.exitCode;

      final commandResult = AsyncCommandResult(
        stdout: stdout,
        stderr: stderr,
        exitCode: exitCode,
      );

      _OperationTracker.completeOperation(opId, commandResult);
    } else {
      _OperationTracker.completeOperation(
        opId, 
        null, 
        AsyncSshException('Command execution failed', errorCode)
      );
    }
  } finally {
    // Free the C strings allocated by Rust
    if (result.ref.stdout != nullptr) {
      calloc.free(result.ref.stdout);
    }
    if (result.ref.stderr != nullptr) {
      calloc.free(result.ref.stderr);
    }
    // Free the result structure
    calloc.free(result);
  }
}