import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/ffi/ssh_bindings.dart';
import 'package:server_box/ffi/ssh_client.dart';

void main() {
  group('SSH FFI Integration Tests', () {
    setUpAll(() {
      // Initialize the SSH library once for all tests
      SshClient.initialize();
    });

    tearDownAll(() {
      // Cleanup the SSH library after all tests
      SshClient.cleanup();
    });

    test('Library initialization should succeed', () {
      // Library should already be initialized in setUpAll
      // Test that we can call initialize multiple times safely
      expect(() => SshClient.initialize(), returnsNormally);
    });

    test('SSH configuration validation', () {
      // Test valid configuration
      const validConfig = SshConfig(
        host: 'localhost',
        port: 22,
        username: 'testuser',
        password: 'testpass',
      );
      
      expect(validConfig.host, equals('localhost'));
      expect(validConfig.port, equals(22));
      expect(validConfig.username, equals('testuser'));
      expect(validConfig.password, equals('testpass'));
      expect(validConfig.timeout, equals(Duration(seconds: 30)));
    });

    test('SSH configuration with private key', () {
      const keyConfig = SshConfig(
        host: 'example.com',
        username: 'keyuser',
        privateKey: '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----',
        passphrase: 'keypass',
      );
      
      expect(keyConfig.privateKey, isNotNull);
      expect(keyConfig.passphrase, equals('keypass'));
      expect(keyConfig.password, isNull);
    });

    test('SSH client connection failure handling', () async {
      final client = SshClient();
      
      // Test connection to non-existent host
      const invalidConfig = SshConfig(
        host: 'nonexistent.invalid.host.12345',
        username: 'testuser',
        password: 'testpass',
        timeout: Duration(seconds: 5),
      );
      
      expect(
        () async => await client.connect(invalidConfig),
        throwsA(isA<SshException>()),
      );
      
      expect(client.isConnected, isFalse);
      expect(client.sessionId, isNull);
    });

    test('Command execution without connection should fail', () async {
      final client = SshClient();
      
      expect(
        () async => await client.execute('echo test'),
        throwsA(isA<SshException>().having(
          (e) => e.errorCode,
          'error code',
          ErrorCode.sessionNotFound,
        )),
      );
    });

    test('System type detection without connection should fail', () async {
      final client = SshClient();
      
      expect(
        () async => await client.detectSystemType(),
        throwsA(isA<SshException>().having(
          (e) => e.errorCode,
          'error code',
          ErrorCode.sessionNotFound,
        )),
      );
    });

    test('Double connection should fail', () async {
      // This test would require a mock server or we skip it
      // We'll test the logic when we have a real connection
      expect(true, isTrue); // Placeholder test
    });

    test('Disconnect without connection should succeed', () async {
      final client = SshClient();
      
      // Should not throw
      expect(() async => await client.disconnect(), returnsNormally);
    });

    test('Command result structure', () {
      const result = CommandResult(
        stdout: 'test output',
        stderr: 'test error',
        exitCode: 0,
      );
      
      expect(result.stdout, equals('test output'));
      expect(result.stderr, equals('test error'));
      expect(result.exitCode, equals(0));
      expect(result.toString(), contains('CommandResult'));
      expect(result.toString(), contains('test output'));
    });

    test('File info structure', () {
      final now = DateTime.now();
      final fileInfo = FileInfo(
        name: 'test.txt',
        size: 1024,
        isDir: false,
        permissions: 644,
        modified: now,
      );
      
      expect(fileInfo.name, equals('test.txt'));
      expect(fileInfo.size, equals(1024));
      expect(fileInfo.isDir, isFalse);
      expect(fileInfo.permissions, equals(644));
      expect(fileInfo.modified, equals(now));
      expect(fileInfo.toString(), contains('FileInfo'));
    });

    test('SSH exception structure', () {
      const exception = SshException('Test error', ErrorCode.connectionFailed);
      
      expect(exception.message, equals('Test error'));
      expect(exception.errorCode, equals(ErrorCode.connectionFailed));
      expect(exception.toString(), contains('SshException'));
      expect(exception.toString(), contains('Test error'));
      expect(exception.toString(), contains('1')); // Error code
    });

    test('Error codes are properly defined', () {
      expect(ErrorCode.success, equals(0));
      expect(ErrorCode.connectionFailed, equals(1));
      expect(ErrorCode.authenticationFailed, equals(2));
      expect(ErrorCode.commandFailed, equals(3));
      expect(ErrorCode.sftpError, equals(4));
      expect(ErrorCode.ioError, equals(5));
      expect(ErrorCode.invalidConfig, equals(6));
      expect(ErrorCode.sessionNotFound, equals(7));
      expect(ErrorCode.other, equals(99));
    });

    test('System types are properly defined', () {
      expect(SystemType.linux, equals(0));
      expect(SystemType.windows, equals(1));
      expect(SystemType.macOS, equals(2));
      expect(SystemType.bsd, equals(3));
      expect(SystemType.unknown, equals(4));
    });
  });

  group('SFTP FFI Integration Tests', () {
    test('SFTP client creation without SSH connection should fail', () async {
      final sshClient = SshClient();
      final sftpClient = SftpClient(sshClient);
      
      expect(
        () async => await sftpClient.initialize(),
        throwsA(isA<SshException>().having(
          (e) => e.errorCode,
          'error code',
          ErrorCode.sessionNotFound,
        )),
      );
    });

    test('SFTP operations without connection should fail', () async {
      final sshClient = SshClient();
      final sftpClient = SftpClient(sshClient);
      
      expect(
        () async => await sftpClient.listDirectory('/'),
        throwsA(isA<SshException>().having(
          (e) => e.errorCode,
          'error code',
          ErrorCode.sessionNotFound,
        )),
      );
    });

    test('SFTP client creation succeeds with SSH client', () {
      final sshClient = SshClient();
      final sftpClient = SftpClient(sshClient);
      
      expect(sftpClient, isNotNull);
      expect(sftpClient, isA<SftpClient>());
    });
  });

  group('Memory Management Tests', () {
    test('Multiple client instances should work independently', () {
      final client1 = SshClient();
      final client2 = SshClient();
      
      expect(client1.isConnected, isFalse);
      expect(client2.isConnected, isFalse);
      expect(client1.sessionId, isNull);
      expect(client2.sessionId, isNull);
      
      // Clients should be independent
      expect(identical(client1, client2), isFalse);
    });

    test('Library cleanup should be safe to call multiple times', () {
      expect(() => SshClient.cleanup(), returnsNormally);
      expect(() => SshClient.cleanup(), returnsNormally);
      
      // Re-initialize for other tests
      SshClient.initialize();
    });
  });
}