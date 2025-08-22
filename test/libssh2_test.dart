import 'dart:io';
import 'dart:typed_data';

import 'package:fl_lib/fl_lib.dart';
import 'package:server_box/core/libssh2/libssh2_client.dart';
import 'package:server_box/core/libssh2/ssh_adapter.dart';
import 'package:server_box/core/libssh2/ssh_logger.dart';
import 'package:server_box/core/libssh2/ssh_message.dart';
import 'package:test/test.dart';

void main() {
  group('LibSSH2 Client Tests', () {
    test('Test SSH connection adapter compatibility', () async {
      // Test that our adapter provides the expected interface
      
      // Test SSHPtyConfig
      final ptyConfig = SSHPtyConfig(
        width: 80,
        height: 24,
        type: 'xterm-256color',
      );
      expect(ptyConfig.width, 80);
      expect(ptyConfig.height, 24);
      expect(ptyConfig.type, 'xterm-256color');
      
      // Test SSHKeyPair
      const testKey = '''-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA...
-----END RSA PRIVATE KEY-----''';
      
      final keyPairs = SSHKeyPair.fromPem(testKey);
      expect(keyPairs, isNotEmpty);
      expect(keyPairs.first.toPem(), testKey);
      
      // Test extensions
      final testString = 'Hello SSH';
      final bytes = testString.uint8List;
      expect(bytes, isA<Uint8List>());
      expect(bytes.string, testString);
      
      print('✅ SSH adapter compatibility tests passed');
    });
    
    test('Test logger functionality', () {
      final logger = SSHLogger(prefix: 'TEST');
      
      // These should not throw
      logger.debug('Debug message');
      logger.info('Info message');
      logger.warning('Warning message');
      logger.error('Error message');
      logger.log('info', 'Log message');
      
      print('✅ Logger tests passed');
    });
    
    test('Test LibSSH2Client initialization', () async {
      // Test client creation (without actual connection)
      final client = LibSSH2Client(
        host: 'test.example.com',
        port: 22,
        username: 'testuser',
        password: 'testpass',
      );
      
      expect(client.host, 'test.example.com');
      expect(client.port, 22);
      expect(client.username, 'testuser');
      expect(client.status, SSHConnectionStatus.disconnected);
      
      print('✅ LibSSH2Client initialization tests passed');
    });
    
    test('Test private key file operations', () async {
      // Test saving and cleaning up temp key
      const testKey = '''-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA...test...
-----END RSA PRIVATE KEY-----''';
      
      // Save key to temp
      final tempDir = await Directory.systemTemp.createTemp('ssh_test_');
      final keyFile = File('${tempDir.path}/test_key');
      await keyFile.writeAsString(testKey);
      
      expect(await keyFile.exists(), true);
      expect(await keyFile.readAsString(), testKey);
      
      // Clean up
      await keyFile.delete();
      await tempDir.delete();
      
      expect(await keyFile.exists(), false);
      expect(await tempDir.exists(), false);
      
      print('✅ Private key file operations tests passed');
    });
  });
}