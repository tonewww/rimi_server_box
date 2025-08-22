// SFTP compatibility adapter for libssh2
// This provides dartssh2 SFTP classes until we fully implement SFTP in libssh2

import 'package:server_box/view/widget/unix_perm.dart';

/// SFTP Name entry (compatibility class)
class SftpName {
  final String filename;
  final SftpFileAttrs attr;
  final String? longname;
  
  SftpName({
    required this.filename,
    required this.attr,
    this.longname,
  });
}

/// SFTP File Attributes (compatibility class)
class SftpFileAttrs {
  final int? size;
  final int? mode;
  final int? accessTime;
  final int? modifyTime;
  final int? uid;
  final int? gid;
  
  SftpFileAttrs({
    this.size,
    this.mode,
    this.accessTime,
    this.modifyTime,
    this.uid,
    this.gid,
  });
  
  bool get isDirectory => mode != null && (mode! & 0x4000) != 0;
  bool get isFile => mode != null && (mode! & 0x8000) != 0;
  bool get isSymbolicLink => mode != null && (mode! & 0xA000) == 0xA000;
}

/// SFTP File Mode (compatibility)
class SftpFileMode {
  final int mode;
  
  SftpFileMode(this.mode);
  
  // Permission check properties
  bool get userRead => (mode & 0400) != 0;
  bool get userWrite => (mode & 0200) != 0;
  bool get userExecute => (mode & 0100) != 0;
  bool get groupRead => (mode & 0040) != 0;
  bool get groupWrite => (mode & 0020) != 0;
  bool get groupExecute => (mode & 0010) != 0;
  bool get otherRead => (mode & 0004) != 0;
  bool get otherWrite => (mode & 0002) != 0;
  bool get otherExecute => (mode & 0001) != 0;
  
  // Convert mode to octal string (e.g., "0755")
  String get str => mode.toRadixString(8).padLeft(4, '0');
  
  // Convert to UnixPerm (for compatibility with existing code)
  UnixPerm toUnixPerm() {
    return UnixPerm(
      user: UnixPermOp(
        r: userRead,
        w: userWrite,
        x: userExecute,
      ),
      group: UnixPermOp(
        r: groupRead,
        w: groupWrite,
        x: groupExecute,
      ),
      other: UnixPermOp(
        r: otherRead,
        w: otherWrite,
        x: otherExecute,
      ),
    );
  }
  
  // Static constants for compatibility
  static const int S_IRUSR = 0400;
  static const int S_IWUSR = 0200;
  static const int S_IXUSR = 0100;
  static const int S_IRGRP = 0040;
  static const int S_IWGRP = 0020;
  static const int S_IXGRP = 0010;
  static const int S_IROTH = 0004;
  static const int S_IWOTH = 0002;
  static const int S_IXOTH = 0001;
}

/// SFTP File Open Mode flags
class SftpFileOpenMode {
  static const int create = 0x08;
  static const int truncate = 0x10;
  static const int write = 0x02;
  static const int read = 0x01;
  static const int append = 0x04;
}

/// SFTP File handle (compatibility stub)
class SftpFile {
  Future<SftpFileAttrs> stat() async {
    // Return dummy stats for now
    return SftpFileAttrs(size: 0);
  }
  
  Stream<List<int>> read({int? offset, int? length}) {
    // Return empty stream for now
    return Stream.empty();
  }
  
  SftpFileWriter write(Stream<List<int>> data, {void Function(int)? onProgress}) {
    return SftpFileWriter._();
  }
  
  Future<void> close() async {
    // No-op for compatibility
  }
}

/// SFTP File Writer (compatibility stub)
class SftpFileWriter {
  SftpFileWriter._();
  
  Future<void> get done async {
    // No-op for compatibility
  }
}

/// SFTP Client (compatibility stub)
class SftpClient {
  Future<List<SftpName>> listdir(String path) async {
    // Stub implementation
    throw UnimplementedError('SFTP not yet implemented in libssh2 adapter');
  }
  
  Future<void> mkdir(String path) async {
    throw UnimplementedError('SFTP not yet implemented in libssh2 adapter');
  }
  
  Future<void> rmdir(String path) async {
    throw UnimplementedError('SFTP not yet implemented in libssh2 adapter');
  }
  
  Future<void> remove(String path) async {
    throw UnimplementedError('SFTP not yet implemented in libssh2 adapter');
  }
  
  Future<void> rename(String oldPath, String newPath) async {
    throw UnimplementedError('SFTP not yet implemented in libssh2 adapter');
  }
  
  Future<SftpFileAttrs> stat(String path) async {
    throw UnimplementedError('SFTP not yet implemented in libssh2 adapter');
  }
  
  Future<SftpFile> open(String path, {int mode = SftpFileOpenMode.read}) async {
    // Return stub file for now
    return SftpFile();
  }
  
  Future<void> close() async {
    // No-op for compatibility
  }
}

/// SSH Auth errors (compatibility)
class SSHAuthAbortError extends Error {
  final String message;
  SSHAuthAbortError(this.message);
  
  @override
  String toString() => 'SSH Auth Abort: $message';
}

class SSHAuthFailError extends Error {
  final String message;
  SSHAuthFailError(this.message);
  
  @override
  String toString() => 'SSH Auth Failed: $message';
}

/// SSH Forward Channel (compatibility stub)
class SSHForwardChannel {
  final String host;
  final int port;
  
  SSHForwardChannel(this.host, this.port);
  
  Future<void> close() async {
    // No-op for compatibility
  }
}