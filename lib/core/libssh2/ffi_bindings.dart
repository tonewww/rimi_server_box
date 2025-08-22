import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// Helper function to get the executable directory
String _getExecutableDir() {
  final executable = Platform.resolvedExecutable;
  final executableDir = File(executable).parent.path;
  return executableDir;
}

// Load system libraries for socket operations
final DynamicLibrary _libc = Platform.isWindows
    ? DynamicLibrary.open('ws2_32.dll')
    : DynamicLibrary.process();

// Load libssh2 library
final DynamicLibrary _libssh2 = () {
  if (Platform.isWindows) {
    return DynamicLibrary.open('libssh2.dll');
  } else if (Platform.isMacOS) {
    // Try multiple paths for macOS, prioritizing bundled library
    final execDir = _getExecutableDir();
    final projectRoot = '/Users/tgy/workspace/duotai/rimi_server_box';
    final paths = [
      // Try @rpath first (for properly configured bundles)
      '@rpath/libssh2.dylib',
      // For development - use absolute path to the lib directory
      '$projectRoot/lib/libssh2.dylib',
      // For bundled app - explicit path to Frameworks
      '$execDir/../Frameworks/libssh2.dylib',
      // Alternative bundled paths
      '${execDir.replaceAll('/MacOS', '')}/Frameworks/libssh2.dylib',
      '$execDir/libssh2.dylib',
      // Current directory attempts
      '${Directory.current.path}/lib/libssh2.dylib',
      // Fallback to system paths (but may be blocked by sandbox)
      '/opt/homebrew/lib/libssh2.dylib',  // Homebrew ARM64
      '/usr/local/lib/libssh2.dylib',      // Homebrew Intel
    ];
    
    for (final path in paths) {
      try {
        // Try to load directly without existence check
        // File.existsSync might fail due to sandbox restrictions
        return DynamicLibrary.open(path);
      } catch (e) {
        // Log error and try next path
        if (kDebugMode) {
          print('Failed to load libssh2 from $path: $e');
        }
      }
    }
    throw Exception('libssh2.dylib not found. Searched paths: ${paths.join(", ")}');
  } else if (Platform.isLinux) {
    // Try bundled library first
    final paths = [
      'lib/libssh2.so',
      './libssh2.so',
      'libssh2.so',
      '/usr/lib/libssh2.so',
      '/usr/local/lib/libssh2.so',
    ];
    
    for (final path in paths) {
      try {
        return DynamicLibrary.open(path);
      } catch (_) {
        // Try next path
      }
    }
    throw Exception('libssh2.so not found');
  } else if (Platform.isAndroid) {
    return DynamicLibrary.open('libssh2.so');
  } else if (Platform.isIOS) {
    return DynamicLibrary.process();
  }
  throw UnsupportedError('Unsupported platform');
}();

// Native socket types and functions
class SocketAF {
  static const int AF_INET = 2;   // IPv4
  static const int AF_INET6 = 10; // IPv6 on Linux, 30 on macOS
}

class SocketType {
  static const int SOCK_STREAM = 1; // TCP
}

class SocketProto {
  static const int IPPROTO_TCP = 6;
}

// Socket address structures
final class SockaddrIn extends Struct {
  @Uint16()
  external int sin_family;
  
  @Uint16()
  external int sin_port;
  
  @Uint32()
  external int sin_addr;
  
  @Array(8)
  external Array<Uint8> sin_zero;
}

// Native socket function signatures
typedef SocketNative = Int32 Function(Int32 domain, Int32 type, Int32 protocol);
typedef Socket = int Function(int domain, int type, int protocol);

typedef ConnectNative = Int32 Function(Int32 socket, Pointer<SockaddrIn> address, Uint32 addressLen);
typedef Connect = int Function(int socket, Pointer<SockaddrIn> address, int addressLen);

typedef CloseNative = Int32 Function(Int32 fd);
typedef Close = int Function(int fd);

typedef SendNative = IntPtr Function(Int32 socket, Pointer<Uint8> buffer, IntPtr length, Int32 flags);
typedef Send = int Function(int socket, Pointer<Uint8> buffer, int length, int flags);

typedef RecvNative = IntPtr Function(Int32 socket, Pointer<Uint8> buffer, IntPtr length, Int32 flags);
typedef Recv = int Function(int socket, Pointer<Uint8> buffer, int length, int flags);

typedef InetPtonNative = Int32 Function(Int32 af, Pointer<Utf8> src, Pointer<Uint32> dst);
typedef InetPton = int Function(int af, Pointer<Utf8> src, Pointer<Uint32> dst);

typedef HtonsNative = Uint16 Function(Uint16 hostshort);
typedef Htons = int Function(int hostshort);

// Type definitions
typedef LibSSH2SessionPtr = Pointer<Void>;
typedef LibSSH2ChannelPtr = Pointer<Void>;
typedef LibSSH2ListenerPtr = Pointer<Void>;
typedef LibSSH2SFTPPtr = Pointer<Void>;
typedef LibSSH2SFTPHandlePtr = Pointer<Void>;
typedef LibSSH2KnownHostsPtr = Pointer<Void>;
typedef LibSSH2AgentPtr = Pointer<Void>;

// Auth types
class AuthType {
  static const int password = 1;
  static const int publicKey = 2;
  static const int hostBased = 4;
  static const int keyboard = 8;
  static const int publicKeyFromAgent = 16;
}

// Error codes
class LibSSH2Error {
  static const int none = 0;
  static const int socket = -1;
  static const int bannerRecv = -2;
  static const int bannerSend = -3;
  static const int invalidMac = -4;
  static const int kexFailure = -5;
  static const int alloc = -6;
  static const int socketSend = -7;
  static const int keyExchangeFailure = -8;
  static const int timeout = -9;
  static const int hostKeyInit = -10;
  static const int hostKeySign = -11;
  static const int decrypt = -12;
  static const int socketDisconnect = -13;
  static const int proto = -14;
  static const int passwordExpired = -15;
  static const int file = -16;
  static const int methodNone = -17;
  static const int authenticationFailed = -18;
  static const int publicKeyUnverified = -19;
  static const int channelOutOfOrder = -20;
  static const int channelFailure = -21;
  static const int channelRequestDenied = -22;
  static const int channelUnknown = -23;
  static const int channelWindowExceeded = -24;
  static const int channelPacketExceeded = -25;
  static const int channelClosed = -26;
  static const int channelEofSent = -27;
  static const int scpProtocol = -28;
  static const int zlib = -29;
  static const int socketTimeout = -30;
  static const int sftpProtocol = -31;
  static const int requestDenied = -32;
  static const int methodNotSupported = -33;
  static const int inval = -34;
  static const int invalidPollType = -35;
  static const int publicKeyProtocol = -36;
  static const int eagain = -37;
  static const int bufferTooSmall = -38;
  static const int badUse = -39;
  static const int compress = -40;
  static const int outOfBoundary = -41;
  static const int agentProtocol = -42;
  static const int socketRecv = -43;
  static const int encrypt = -44;
  static const int badSocket = -45;
  static const int knownHosts = -46;
  static const int channelWindowFull = -47;
  static const int keyfileAuthFailed = -48;
  static const int randgen = -49;
}

// Native function signatures
typedef LibSSH2InitNative = Int32 Function(Int32 flags);
typedef LibSSH2Init = int Function(int flags);

typedef LibSSH2ExitNative = Void Function();
typedef LibSSH2Exit = void Function();

// libssh2_session_init_ex takes 4 optional parameters (all can be NULL/0)
typedef LibSSH2SessionInitNative = LibSSH2SessionPtr Function(
    Pointer<Void> myalloc,  // custom allocator (can be NULL)
    Pointer<Void> myfree,   // custom free (can be NULL)  
    Pointer<Void> myrealloc, // custom realloc (can be NULL)
    Pointer<Void> abstract); // abstract pointer (can be NULL)
typedef LibSSH2SessionInit = LibSSH2SessionPtr Function(
    Pointer<Void> myalloc,
    Pointer<Void> myfree,
    Pointer<Void> myrealloc,
    Pointer<Void> abstract);

typedef LibSSH2SessionFreeNative = Int32 Function(LibSSH2SessionPtr session);
typedef LibSSH2SessionFree = int Function(LibSSH2SessionPtr session);

typedef LibSSH2SessionHandshakeNative = Int32 Function(
    LibSSH2SessionPtr session, Int32 socket);
typedef LibSSH2SessionHandshake = int Function(
    LibSSH2SessionPtr session, int socket);

typedef LibSSH2SessionDisconnectNative = Int32 Function(
    LibSSH2SessionPtr session, Int32 reason, Pointer<Utf8> description, Pointer<Utf8> lang);
typedef LibSSH2SessionDisconnect = int Function(
    LibSSH2SessionPtr session, int reason, Pointer<Utf8> description, Pointer<Utf8> lang);

typedef LibSSH2SessionLastErrorNative = Int32 Function(
    LibSSH2SessionPtr session, Pointer<Pointer<Utf8>> errmsg, Pointer<Int32> errmsgLen, Int32 wantBuf);
typedef LibSSH2SessionLastError = int Function(
    LibSSH2SessionPtr session, Pointer<Pointer<Utf8>> errmsg, Pointer<Int32> errmsgLen, int wantBuf);

typedef LibSSH2SessionSetBlockingNative = Void Function(
    LibSSH2SessionPtr session, Int32 blocking);
typedef LibSSH2SessionSetBlocking = void Function(
    LibSSH2SessionPtr session, int blocking);

typedef LibSSH2SessionGetBlockingNative = Int32 Function(LibSSH2SessionPtr session);
typedef LibSSH2SessionGetBlocking = int Function(LibSSH2SessionPtr session);

typedef LibSSH2UserauthPasswordNative = Int32 Function(
    LibSSH2SessionPtr session, 
    Pointer<Utf8> username, 
    Uint32 usernameLen,
    Pointer<Utf8> password,
    Uint32 passwordLen);
typedef LibSSH2UserauthPassword = int Function(
    LibSSH2SessionPtr session, 
    Pointer<Utf8> username, 
    int usernameLen,
    Pointer<Utf8> password,
    int passwordLen);

typedef LibSSH2UserauthPublicKeyFromFileNative = Int32 Function(
    LibSSH2SessionPtr session,
    Pointer<Utf8> username,
    Uint32 usernameLen,
    Pointer<Utf8> publicKey,
    Pointer<Utf8> privateKey,
    Pointer<Utf8> passphrase);
typedef LibSSH2UserauthPublicKeyFromFile = int Function(
    LibSSH2SessionPtr session,
    Pointer<Utf8> username,
    int usernameLen,
    Pointer<Utf8> publicKey,
    Pointer<Utf8> privateKey,
    Pointer<Utf8> passphrase);

typedef LibSSH2UserauthPublicKeyFromMemoryNative = Int32 Function(
    LibSSH2SessionPtr session,
    Pointer<Utf8> username,
    Pointer<Uint8> publicKeyData,
    IntPtr publicKeyLen,
    Pointer<Uint8> privateKeyData,
    IntPtr privateKeyLen,
    Pointer<Utf8> passphrase);
typedef LibSSH2UserauthPublicKeyFromMemory = int Function(
    LibSSH2SessionPtr session,
    Pointer<Utf8> username,
    Pointer<Uint8> publicKeyData,
    int publicKeyLen,
    Pointer<Uint8> privateKeyData,
    int privateKeyLen,
    Pointer<Utf8> passphrase);

typedef LibSSH2UserauthKeyboardInteractiveNative = Int32 Function(
    LibSSH2SessionPtr session,
    Pointer<Utf8> username,
    Pointer<NativeFunction<KeyboardResponseCallback>>);
typedef LibSSH2UserauthKeyboardInteractive = int Function(
    LibSSH2SessionPtr session,
    Pointer<Utf8> username,
    Pointer<NativeFunction<KeyboardResponseCallback>>);

typedef KeyboardResponseCallback = Void Function(
    Pointer<Utf8> name,
    Int32 nameLen,
    Pointer<Utf8> instruction,
    Int32 instructionLen,
    Int32 numPrompts,
    Pointer<Void> prompts,
    Pointer<Void> responses,
    Pointer<Void> abstract);

typedef LibSSH2ChannelOpenSessionNative = LibSSH2ChannelPtr Function(
    LibSSH2SessionPtr session,
    Pointer<Utf8> channelType,
    Uint32 channelTypeLen,
    Uint32 windowSize,
    Uint32 packetSize,
    Pointer<Utf8> message,
    Uint32 messageLen);
typedef LibSSH2ChannelOpenSession = LibSSH2ChannelPtr Function(
    LibSSH2SessionPtr session,
    Pointer<Utf8> channelType,
    int channelTypeLen,
    int windowSize,
    int packetSize,
    Pointer<Utf8> message,
    int messageLen);

typedef LibSSH2ChannelFreeNative = Int32 Function(LibSSH2ChannelPtr channel);
typedef LibSSH2ChannelFree = int Function(LibSSH2ChannelPtr channel);

typedef LibSSH2ChannelCloseNative = Int32 Function(LibSSH2ChannelPtr channel);
typedef LibSSH2ChannelClose = int Function(LibSSH2ChannelPtr channel);

typedef LibSSH2ChannelWaitClosedNative = Int32 Function(LibSSH2ChannelPtr channel);
typedef LibSSH2ChannelWaitClosed = int Function(LibSSH2ChannelPtr channel);

typedef LibSSH2ChannelRequestPtyNative = Int32 Function(
    LibSSH2ChannelPtr channel, Pointer<Utf8> termType);
typedef LibSSH2ChannelRequestPty = int Function(
    LibSSH2ChannelPtr channel, Pointer<Utf8> termType);

typedef LibSSH2ChannelRequestPtyExNative = Int32 Function(
    LibSSH2ChannelPtr channel,
    Pointer<Utf8> termType,
    Int32 termTypeLen,
    Pointer<Utf8> modes,
    Int32 modesLen,
    Int32 width,
    Int32 height,
    Int32 widthPx,
    Int32 heightPx);
typedef LibSSH2ChannelRequestPtyEx = int Function(
    LibSSH2ChannelPtr channel,
    Pointer<Utf8> termType,
    int termTypeLen,
    Pointer<Utf8> modes,
    int modesLen,
    int width,
    int height,
    int widthPx,
    int heightPx);

typedef LibSSH2ChannelShellNative = Int32 Function(LibSSH2ChannelPtr channel);
typedef LibSSH2ChannelShell = int Function(LibSSH2ChannelPtr channel);

typedef LibSSH2ChannelExecNative = Int32 Function(
    LibSSH2ChannelPtr channel, Pointer<Utf8> command);
typedef LibSSH2ChannelExec = int Function(
    LibSSH2ChannelPtr channel, Pointer<Utf8> command);

typedef LibSSH2ChannelSubsystemNative = Int32 Function(
    LibSSH2ChannelPtr channel, Pointer<Utf8> subsystem);
typedef LibSSH2ChannelSubsystem = int Function(
    LibSSH2ChannelPtr channel, Pointer<Utf8> subsystem);

typedef LibSSH2ChannelReadNative = IntPtr Function(
    LibSSH2ChannelPtr channel, Pointer<Uint8> buffer, IntPtr bufferLen);
typedef LibSSH2ChannelRead = int Function(
    LibSSH2ChannelPtr channel, Pointer<Uint8> buffer, int bufferLen);

typedef LibSSH2ChannelReadStderrNative = IntPtr Function(
    LibSSH2ChannelPtr channel, Pointer<Uint8> buffer, IntPtr bufferLen);
typedef LibSSH2ChannelReadStderr = int Function(
    LibSSH2ChannelPtr channel, Pointer<Uint8> buffer, int bufferLen);

typedef LibSSH2ChannelWriteNative = IntPtr Function(
    LibSSH2ChannelPtr channel, Pointer<Uint8> buffer, IntPtr bufferLen);
typedef LibSSH2ChannelWrite = int Function(
    LibSSH2ChannelPtr channel, Pointer<Uint8> buffer, int bufferLen);

typedef LibSSH2ChannelWriteStderrNative = IntPtr Function(
    LibSSH2ChannelPtr channel, Pointer<Uint8> buffer, IntPtr bufferLen);
typedef LibSSH2ChannelWriteStderr = int Function(
    LibSSH2ChannelPtr channel, Pointer<Uint8> buffer, int bufferLen);

typedef LibSSH2ChannelFlushNative = Int32 Function(LibSSH2ChannelPtr channel);
typedef LibSSH2ChannelFlush = int Function(LibSSH2ChannelPtr channel);

typedef LibSSH2ChannelFlushStderrNative = Int32 Function(LibSSH2ChannelPtr channel);
typedef LibSSH2ChannelFlushStderr = int Function(LibSSH2ChannelPtr channel);

typedef LibSSH2ChannelEofNative = Int32 Function(LibSSH2ChannelPtr channel);
typedef LibSSH2ChannelEof = int Function(LibSSH2ChannelPtr channel);

typedef LibSSH2ChannelSendEofNative = Int32 Function(LibSSH2ChannelPtr channel);
typedef LibSSH2ChannelSendEof = int Function(LibSSH2ChannelPtr channel);

typedef LibSSH2ChannelWaitEofNative = Int32 Function(LibSSH2ChannelPtr channel);
typedef LibSSH2ChannelWaitEof = int Function(LibSSH2ChannelPtr channel);

typedef LibSSH2ChannelGetExitStatusNative = Int32 Function(LibSSH2ChannelPtr channel);
typedef LibSSH2ChannelGetExitStatus = int Function(LibSSH2ChannelPtr channel);

typedef LibSSH2ChannelSetEnvNative = Int32 Function(
    LibSSH2ChannelPtr channel, Pointer<Utf8> varname, Pointer<Utf8> value);
typedef LibSSH2ChannelSetEnv = int Function(
    LibSSH2ChannelPtr channel, Pointer<Utf8> varname, Pointer<Utf8> value);

typedef LibSSH2ChannelRequestPtySizeNative = Int32 Function(
    LibSSH2ChannelPtr channel, Int32 width, Int32 height, Int32 widthPx, Int32 heightPx);
typedef LibSSH2ChannelRequestPtySize = int Function(
    LibSSH2ChannelPtr channel, int width, int height, int widthPx, int heightPx);

// FFI function bindings
class LibSSH2 {
  static final LibSSH2Init init = _libssh2
      .lookup<NativeFunction<LibSSH2InitNative>>('libssh2_init')
      .asFunction();

  static final LibSSH2Exit exit = _libssh2
      .lookup<NativeFunction<LibSSH2ExitNative>>('libssh2_exit')
      .asFunction();

  static final LibSSH2SessionInit sessionInit = _libssh2
      .lookup<NativeFunction<LibSSH2SessionInitNative>>('libssh2_session_init_ex')
      .asFunction();

  static final LibSSH2SessionFree sessionFree = _libssh2
      .lookup<NativeFunction<LibSSH2SessionFreeNative>>('libssh2_session_free')
      .asFunction();

  static final LibSSH2SessionHandshake sessionHandshake = _libssh2
      .lookup<NativeFunction<LibSSH2SessionHandshakeNative>>('libssh2_session_handshake')
      .asFunction();

  static final LibSSH2SessionDisconnect sessionDisconnect = _libssh2
      .lookup<NativeFunction<LibSSH2SessionDisconnectNative>>('libssh2_session_disconnect_ex')
      .asFunction();

  static final LibSSH2SessionLastError sessionLastError = _libssh2
      .lookup<NativeFunction<LibSSH2SessionLastErrorNative>>('libssh2_session_last_error')
      .asFunction();

  static final LibSSH2SessionSetBlocking sessionSetBlocking = _libssh2
      .lookup<NativeFunction<LibSSH2SessionSetBlockingNative>>('libssh2_session_set_blocking')
      .asFunction();

  static final LibSSH2SessionGetBlocking sessionGetBlocking = _libssh2
      .lookup<NativeFunction<LibSSH2SessionGetBlockingNative>>('libssh2_session_get_blocking')
      .asFunction();

  static final LibSSH2UserauthPassword userauthPassword = _libssh2
      .lookup<NativeFunction<LibSSH2UserauthPasswordNative>>('libssh2_userauth_password_ex')
      .asFunction();

  static final LibSSH2UserauthPublicKeyFromFile userauthPublicKeyFromFile = _libssh2
      .lookup<NativeFunction<LibSSH2UserauthPublicKeyFromFileNative>>(
          'libssh2_userauth_publickey_fromfile_ex')
      .asFunction();

  static final LibSSH2UserauthPublicKeyFromMemory userauthPublicKeyFromMemory = _libssh2
      .lookup<NativeFunction<LibSSH2UserauthPublicKeyFromMemoryNative>>(
          'libssh2_userauth_publickey_frommemory')
      .asFunction();

  static final LibSSH2UserauthKeyboardInteractive userauthKeyboardInteractive = _libssh2
      .lookup<NativeFunction<LibSSH2UserauthKeyboardInteractiveNative>>(
          'libssh2_userauth_keyboard_interactive_ex')
      .asFunction();

  static final LibSSH2ChannelOpenSession channelOpenSession = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelOpenSessionNative>>('libssh2_channel_open_ex')
      .asFunction();

  static final LibSSH2ChannelFree channelFree = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelFreeNative>>('libssh2_channel_free')
      .asFunction();

  static final LibSSH2ChannelClose channelClose = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelCloseNative>>('libssh2_channel_close')
      .asFunction();

  static final LibSSH2ChannelWaitClosed channelWaitClosed = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelWaitClosedNative>>('libssh2_channel_wait_closed')
      .asFunction();

  static final LibSSH2ChannelRequestPty channelRequestPty = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelRequestPtyNative>>('libssh2_channel_request_pty_ex')
      .asFunction();

  static final LibSSH2ChannelRequestPtyEx channelRequestPtyEx = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelRequestPtyExNative>>('libssh2_channel_request_pty_ex')
      .asFunction();

  static final LibSSH2ChannelShell channelShell = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelShellNative>>('libssh2_channel_shell')
      .asFunction();

  static final LibSSH2ChannelExec channelExec = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelExecNative>>('libssh2_channel_exec')
      .asFunction();

  static final LibSSH2ChannelSubsystem channelSubsystem = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelSubsystemNative>>('libssh2_channel_subsystem')
      .asFunction();

  static final LibSSH2ChannelRead channelRead = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelReadNative>>('libssh2_channel_read_ex')
      .asFunction();

  static final LibSSH2ChannelReadStderr channelReadStderr = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelReadStderrNative>>('libssh2_channel_read_stderr')
      .asFunction();

  static final LibSSH2ChannelWrite channelWrite = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelWriteNative>>('libssh2_channel_write_ex')
      .asFunction();

  static final LibSSH2ChannelWriteStderr channelWriteStderr = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelWriteStderrNative>>('libssh2_channel_write_stderr')
      .asFunction();

  static final LibSSH2ChannelFlush channelFlush = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelFlushNative>>('libssh2_channel_flush_ex')
      .asFunction();

  static final LibSSH2ChannelFlushStderr channelFlushStderr = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelFlushStderrNative>>('libssh2_channel_flush_stderr')
      .asFunction();

  static final LibSSH2ChannelEof channelEof = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelEofNative>>('libssh2_channel_eof')
      .asFunction();

  static final LibSSH2ChannelSendEof channelSendEof = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelSendEofNative>>('libssh2_channel_send_eof')
      .asFunction();

  static final LibSSH2ChannelWaitEof channelWaitEof = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelWaitEofNative>>('libssh2_channel_wait_eof')
      .asFunction();

  static final LibSSH2ChannelGetExitStatus channelGetExitStatus = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelGetExitStatusNative>>('libssh2_channel_get_exit_status')
      .asFunction();

  static final LibSSH2ChannelSetEnv channelSetEnv = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelSetEnvNative>>('libssh2_channel_setenv_ex')
      .asFunction();

  static final LibSSH2ChannelRequestPtySize channelRequestPtySize = _libssh2
      .lookup<NativeFunction<LibSSH2ChannelRequestPtySizeNative>>('libssh2_channel_request_pty_size_ex')
      .asFunction();
}

// Native socket operations
class NativeSocket {
  // Function pointers
  static final Socket socket = _libc
      .lookup<NativeFunction<SocketNative>>('socket')
      .asFunction();
      
  static final Connect connect = _libc
      .lookup<NativeFunction<ConnectNative>>('connect')
      .asFunction();
      
  static final Close close = _libc
      .lookup<NativeFunction<CloseNative>>('close')
      .asFunction();
      
  static final Send send = _libc
      .lookup<NativeFunction<SendNative>>('send')
      .asFunction();
      
  static final Recv recv = _libc
      .lookup<NativeFunction<RecvNative>>('recv')
      .asFunction();
      
  static final InetPton inetPton = _libc
      .lookup<NativeFunction<InetPtonNative>>('inet_pton')
      .asFunction();
      
  static final Htons htons = _libc
      .lookup<NativeFunction<HtonsNative>>('htons')
      .asFunction();
      
  /// Create a TCP socket and connect to the specified host and port
  static int createAndConnect(String host, int port) {
    // Create socket
    final socketFd = socket(SocketAF.AF_INET, SocketType.SOCK_STREAM, SocketProto.IPPROTO_TCP);
    if (socketFd < 0) {
      throw Exception('Failed to create socket: $socketFd');
    }
    
    // Prepare address structure
    final addr = calloc<SockaddrIn>();
    try {
      addr.ref.sin_family = SocketAF.AF_INET;
      addr.ref.sin_port = htons(port);
      
      // Convert IP address string to binary
      final hostPtr = host.toNativeUtf8();
      final addrPtr = calloc<Uint32>();
      try {
        final result = inetPton(SocketAF.AF_INET, hostPtr, addrPtr);
        if (result != 1) {
          close(socketFd);
          throw Exception('Invalid IP address: $host');
        }
        addr.ref.sin_addr = addrPtr.value;
      } finally {
        calloc.free(hostPtr);
        calloc.free(addrPtr);
      }
      
      // Connect
      final connectResult = connect(socketFd, addr, sizeOf<SockaddrIn>());
      if (connectResult < 0) {
        close(socketFd);
        throw Exception('Failed to connect to $host:$port: $connectResult');
      }
      
      return socketFd;
    } finally {
      calloc.free(addr);
    }
  }
  
  /// Close a socket
  static void closeSocket(int socketFd) {
    if (socketFd >= 0) {
      close(socketFd);
    }
  }
}