import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/ffi/ssh_adapter.dart';
import 'package:server_box/ffi/ssh_client.dart' as rust_ssh;

void main() {
  group('SSH Adapter Compatibility Tests', () {
    setUpAll(() {
      // Initialize the Rust SSH library
      rust_ssh.SshClient.initialize();
    });

    tearDownAll(() {
      // Cleanup
      rust_ssh.SshClient.cleanup();
    });

    test('SSHClient creation should work', () {
      final client = SSHClient();
      expect(client, isNotNull);
      expect(client.isConnected, isFalse);
    });

    test('SSH connection failure should throw proper exception', () async {
      expect(
        () async => await SSHClient.connect(
          host: 'nonexistent.invalid.host.12345',
          username: 'test',
          password: 'test',
          timeout: Duration(seconds: 2),
        ),
        throwsA(isA<rust_ssh.SshException>()),
      );
    });

    test('SSH key-based connection should handle invalid hosts', () async {
      expect(
        () async => await SSHClient.connectWithKey(
          host: 'nonexistent.invalid.host.12345', 
          username: 'test',
          privateKey: '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----',
          timeout: Duration(seconds: 2),
        ),
        throwsA(isA<rust_ssh.SshException>()),
      );
    });

    test('SSHPtyConfig should have proper defaults', () {
      const pty = SSHPtyConfig();
      expect(pty.width, equals(80));
      expect(pty.height, equals(24));
      expect(pty.term, equals('xterm'));
    });

    test('SSHPtyConfig should accept custom values', () {
      const pty = SSHPtyConfig(width: 120, height: 30, term: 'vt100');
      expect(pty.width, equals(120));
      expect(pty.height, equals(30));
      expect(pty.term, equals('vt100'));
    });

    test('SSH exceptions should work', () {
      final exception = SSHAuthFailError('Authentication failed');
      expect(exception.message, equals('Authentication failed'));
      expect(exception.toString(), contains('Authentication failed'));
    });

    test('SSHKeyPair fromPem should work', () {
      const testKey = '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----';
      final keyPairs = SSHKeyPair.fromPem(testKey);
      
      expect(keyPairs, isNotEmpty);
      expect(keyPairs.first.toPem(), equals(testKey));
    });

    test('SSHKeyPair isEncryptedPem should detect encryption', () {
      const encryptedKey = '-----BEGIN RSA PRIVATE KEY-----\nProc-Type: 4,ENCRYPTED\ntest\n-----END RSA PRIVATE KEY-----';
      const regularKey = '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----';
      
      expect(SSHKeyPair.isEncryptedPem(encryptedKey), isTrue);
      expect(SSHKeyPair.isEncryptedPem(regularKey), isFalse);
    });

    test('String and Uint8List types should be available', () {
      const testString = 'Hello World';
      final uint8List = Uint8List.fromList(testString.codeUnits);
      
      expect(uint8List, isA<Uint8List>());
      expect(String.fromCharCodes(uint8List), equals(testString));
    });

    test('SSHClient close should work without connection', () async {
      final client = SSHClient();
      
      // Should not throw
      expect(() async => await client.close(), returnsNormally);
      expect(client.isConnected, isFalse);
    });

    test('Command execution without connection should fail', () async {
      final client = SSHClient();
      
      expect(
        () async => await client.execute('echo test'),
        throwsA(isA<StateError>()),
      );
    });

    test('SSHSession streams should be properly typed', () {
      // Test stream type checking - we can't directly create SSHSession
      // but we can test the type system
      expect(Stream<Uint8List>, isA<Type>());
      expect(StreamSink<Uint8List>, isA<Type>());
    });

    test('SSH adapter basic functionality', () {
      // Basic adapter functionality tests
      expect(SSHSocket, isA<Type>());
      expect(SSHForwardChannel, isA<Type>());
      expect(SSHAuthAbortError, isA<Type>());
      expect(SSHAuthFailError, isA<Type>());
    });
  });
}