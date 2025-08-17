// Test IsolateSSHClient connection and command execution
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/ffi/ssh_isolate_adapter.dart';

void main() {
  group('IsolateSSHClient Connection Tests', () {
    setUpAll(() async {
      print('=== IsolateSSHClient Connection Test Setup ===');
      await IsolateSSHClient.initialize();
      print('IsolateSSHClient initialized successfully');
    });

    tearDownAll(() async {
      print('=== IsolateSSHClient Connection Test Cleanup ===');
      await IsolateSSHClient.cleanup();
      print('IsolateSSHClient cleaned up');
    });

    test('Connect to SSH server and execute uname command', () async {
      print('\n🔌 Testing SSH connection via IsolateSSHClient...');
      
      IsolateSSHClient? client;
      
      try {
        // Read the private key file
        final keyFile = File('${Platform.environment['HOME']}/.ssh/id_ed25519');
        if (!keyFile.existsSync()) {
          print('❌ Private key file not found, skipping test');
          return;
        }
        
        final privateKey = await keyFile.readAsString();
        
        // Test connection with key authentication (based on our previous successful test)
        client = await IsolateSSHClient.connectWithKey(
          host: '192.168.50.7',
          port: 22,
          username: 'ptw',
          privateKey: privateKey,
          timeout: const Duration(seconds: 10),
        );
        
        print('✅ SSH connection established successfully');
        print('   Session ID: ${client.sessionId}');
        print('   Connected: ${client.isConnected}');
        
        expect(client.isConnected, isTrue);
        expect(client.sessionId, isNotNull);
        
        // Test command execution
        print('\n🧪 Testing command execution: uname -a');
        final result = await client.run('uname -a');
        
        print('✅ Command executed successfully:');
        print('   stdout: "${result.stdout.trim()}"');
        print('   stderr: "${result.stderr.trim()}"');
        print('   exit code: ${result.exitCode}');
        
        expect(result.exitCode, equals(0));
        expect(result.stdout.trim(), isNotEmpty);
        expect(result.stdout.toLowerCase(), contains('linux'));
        
        // Test another command
        print('\n🧪 Testing command execution: whoami');
        final whoamiResult = await client.run('whoami');
        
        print('✅ Whoami command executed:');
        print('   stdout: "${whoamiResult.stdout.trim()}"');
        print('   exit code: ${whoamiResult.exitCode}');
        
        expect(whoamiResult.exitCode, equals(0));
        expect(whoamiResult.stdout.trim(), equals('ptw'));
        
        // Test echo command
        print('\n🧪 Testing command execution: echo test');
        final echoResult = await client.run('echo test');
        
        print('✅ Echo command executed:');
        print('   stdout: "${echoResult.stdout.trim()}"');
        print('   exit code: ${echoResult.exitCode}');
        
        expect(echoResult.exitCode, equals(0));
        expect(echoResult.stdout.trim(), equals('test'));
        
        print('\n🎉 All SSH connection and command tests passed!');
        
      } catch (e, stackTrace) {
        print('❌ SSH connection test failed: $e');
        print('Stack trace: $stackTrace');
        fail('SSH connection test failed: $e');
      } finally {
        if (client != null) {
          print('\n🔌 Closing SSH connection...');
          await client.close();
          print('✅ SSH connection closed');
        }
      }
    });

    test('Test SSH connection with password (should fail)', () async {
      print('\n🔌 Testing SSH connection with password (expected to fail)...');
      
      try {
        final client = await IsolateSSHClient.connect(
          host: '192.168.50.7',
          port: 22,
          username: 'ptw',
          password: 'wrong_password',
          timeout: const Duration(seconds: 5),
        );
        
        await client.close();
        fail('Password authentication should have failed');
        
      } catch (e) {
        print('✅ Password authentication failed as expected: $e');
        expect(e.toString(), contains('Authentication failed'));
      }
    });

    test('Test connection to non-existent host (should fail quickly)', () async {
      print('\n🔌 Testing SSH connection to non-existent host...');
      
      try {
        final client = await IsolateSSHClient.connect(
          host: '192.0.2.1', // RFC5737 test address - should be unreachable
          port: 22,
          username: 'test',
          password: 'test',
          timeout: const Duration(seconds: 5),
        );
        
        await client.close();
        fail('Connection to non-existent host should have failed');
        
      } catch (e) {
        print('✅ Connection to non-existent host failed as expected: $e');
        expect(e.toString().toLowerCase(), anyOf([
          contains('timeout'),
          contains('connection'),
          contains('failed'),
        ]));
      }
    });
  });
}