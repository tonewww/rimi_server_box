// Test IsolateSSHClient ping functionality specifically
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/ffi/ssh_isolate_adapter.dart';

void main() {
  group('IsolateSSHClient Ping Tests', () {
    setUpAll(() async {
      print('=== IsolateSSHClient Ping Test Setup ===');
      await IsolateSSHClient.initialize();
    });

    tearDownAll(() async {
      print('=== IsolateSSHClient Ping Test Cleanup ===');
      await IsolateSSHClient.cleanup();
    });

    test('Test ping functionality', () async {
      print('\n🔌 Testing ping functionality...');
      
      IsolateSSHClient? client;
      
      try {
        // Read the private key file
        final keyFile = File('${Platform.environment['HOME']}/.ssh/id_ed25519');
        if (!keyFile.existsSync()) {
          print('❌ Private key file not found, skipping test');
          return;
        }
        
        final privateKey = await keyFile.readAsString();
        
        // Connect using key authentication
        client = await IsolateSSHClient.connectWithKey(
          host: '192.168.50.7',
          port: 22,
          username: 'ptw',
          privateKey: privateKey,
          timeout: const Duration(seconds: 10),
        );
        
        print('✅ SSH connection established');
        
        // Test ping operation
        print('\n🏓 Testing ping operation...');
        await client.ping();
        print('✅ Ping operation completed successfully');
        
        // Test shell operation
        print('\n🐚 Testing shell operation...');
        final shell = await client.shell();
        print('✅ Shell operation completed successfully');
        
        print('\n🎉 All ping and shell tests passed!');
        
      } catch (e, stackTrace) {
        print('❌ Test failed: $e');
        print('Stack trace: $stackTrace');
        fail('Test failed: $e');
      } finally {
        if (client != null) {
          print('\n🔌 Closing SSH connection...');
          await client.close();
          print('✅ SSH connection closed');
        }
      }
    });
  });
}