// SSH connection diagnostic test
import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/ffi/ssh_isolate_adapter.dart';

void main() {
  group('SSH Connection Diagnostic Tests', () {
    setUpAll(() async {
      print('=== SSH Diagnostic Test Suite ===');
      await IsolateSSHClient.initialize();
    });

    tearDownAll(() async {
      await IsolateSSHClient.cleanup();
    });

    test('Test connection to localhost SSH (if available)', () async {
      print('\n--- Testing localhost SSH connection ---');
      
      try {
        final client = await IsolateSSHClient.connect(
          host: 'localhost',
          port: 22,
          username: 'testuser',
          password: 'testpass',
          timeout: const Duration(seconds: 5),
        );
        
        print('✅ Localhost SSH connection successful');
        await client.close();
        
      } catch (e) {
        print('❌ Localhost SSH connection failed: $e');
        print('   This is normal if SSH server is not running on localhost');
        expect(e, isA<Exception>());
      }
    });

    test('Test connection with invalid host', () async {
      print('\n--- Testing invalid host connection ---');
      
      try {
        await IsolateSSHClient.connect(
          host: 'invalid.nonexistent.host.example',
          port: 22,
          username: 'test',
          password: 'test',
          timeout: const Duration(seconds: 2),
        );
        
        fail('Should have failed for invalid host');
        
      } catch (e) {
        print('✅ Invalid host correctly failed: $e');
        expect(e, isA<Exception>());
      }
    });

    test('Test connection to unreachable IP', () async {
      print('\n--- Testing unreachable IP connection ---');
      
      try {
        await IsolateSSHClient.connect(
          host: '192.0.2.1', // RFC5737 test address
          port: 22,
          username: 'test',
          password: 'test',
          timeout: const Duration(seconds: 2),
        );
        
        fail('Should have failed for unreachable IP');
        
      } catch (e) {
        print('✅ Unreachable IP correctly failed: $e');
        expect(e, isA<Exception>());
      }
    });

    test('Test connection to wrong port', () async {
      print('\n--- Testing wrong port connection ---');
      
      try {
        await IsolateSSHClient.connect(
          host: 'google.com', // Known host but wrong SSH port
          port: 80, // HTTP port instead of SSH port
          username: 'test',
          password: 'test',
          timeout: const Duration(seconds: 3),
        );
        
        fail('Should have failed for wrong port');
        
      } catch (e) {
        print('✅ Wrong port correctly failed: $e');
        expect(e, isA<Exception>());
      }
    });

    test('Test SSH-specific error handling', () async {
      print('\n--- Testing SSH-specific error patterns ---');
      
      // Test various error conditions to understand what the Rust library returns
      final testCases = [
        {'host': '192.168.50.7', 'port': 22, 'user': 'invaliduser', 'pass': 'invalidpass', 'desc': 'Invalid credentials'},
        {'host': '127.0.0.1', 'port': 2222, 'user': 'test', 'pass': 'test', 'desc': 'Non-standard SSH port'},
        {'host': '192.168.1.999', 'port': 22, 'user': 'test', 'pass': 'test', 'desc': 'Invalid IP address'},
      ];
      
      for (final testCase in testCases) {
        print('\n  Testing: ${testCase['desc']}');
        try {
          await IsolateSSHClient.connect(
            host: testCase['host']! as String,
            port: testCase['port']! as int,
            username: testCase['user']! as String,
            password: testCase['pass']! as String,
            timeout: const Duration(seconds: 3),
          );
          
          print('  ⚠️  Unexpected success for ${testCase['desc']}');
          
        } catch (e) {
          print('  ✅ Expected failure for ${testCase['desc']}: $e');
          
          // Analyze error types
          if (e.toString().contains('Connection failed')) {
            print('     → Connection-level error detected');
          } else if (e.toString().contains('Authentication')) {
            print('     → Authentication error detected');
          } else if (e.toString().contains('timeout')) {
            print('     → Timeout error detected');
          } else {
            print('     → Other error type detected');
          }
        }
      }
    });

    test('Test with real server credentials (if available)', () async {
      print('\n--- Testing with potentially real server ---');
      print('📝 Note: This test uses credentials from the app configuration');
      print('   It will likely fail but helps diagnose the exact issue');
      
      try {
        final client = await IsolateSSHClient.connect(
          host: '192.168.50.7',
          port: 22,
          username: 'ptw',
          password: 'test123', // This is likely wrong
          timeout: const Duration(seconds: 10),
        );
        
        print('🎉 Real server connection successful!');
        
        // Test a simple command
        final result = await client.run('whoami');
        print('Command result: ${result.stdout}');
        
        await client.close();
        
      } catch (e) {
        print('❌ Real server connection failed: $e');
        
        // Provide specific diagnosis based on error
        if (e.toString().contains('Connection failed (code: 1)')) {
          print('   🔍 Diagnosis: Code 1 typically means:');
          print('      - Network unreachable');
          print('      - SSH service not running on target');
          print('      - Firewall blocking connection');
          print('      - Invalid host/port combination');
        } else if (e.toString().contains('Authentication')) {
          print('   🔍 Diagnosis: Authentication failed');
          print('      - Wrong username/password');
          print('      - Account locked or disabled');
          print('      - Key-based auth required');
        } else if (e.toString().contains('timeout')) {
          print('   🔍 Diagnosis: Connection timeout');
          print('      - Host is unreachable');
          print('      - Network latency too high');
          print('      - Firewall dropping packets');
        }
        
        expect(e, isA<Exception>());
      }
    });
  });
}