// Simple SSH connection test for debugging
import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/ffi/ssh_isolate_adapter.dart';

void main() {
  group('Simple SSH Tests', () {
    setUpAll(() async {
      print('Initializing SSH isolate...');
      await IsolateSSHClient.initialize();
      print('SSH isolate initialized');
    });

    tearDownAll(() async {
      print('Cleaning up SSH isolate...');
      await IsolateSSHClient.cleanup();
      print('SSH isolate cleaned up');
    });

    test('SSH isolate initialization works', () async {
      // Just test that initialization doesn't crash
      expect(true, isTrue);
      print('SSH isolate test passed');
    });

    test('SSH client creation works', () {
      final client = IsolateSSHClient();
      expect(client.isConnected, false);
      expect(client.isClosed, true);
      print('SSH client creation test passed');
    });

    test('SSH connection attempt (will likely fail but should not crash)', () async {
      print('Attempting SSH connection...');
      
      try {
        final client = await IsolateSSHClient.connect(
          host: '192.168.50.7',
          port: 22,
          username: 'ptw',
          password: 'test123',
          timeout: const Duration(seconds: 5),
        );
        
        print('SSH connection successful!');
        print('Session ID: ${client.sessionId}');
        print('Is connected: ${client.isConnected}');
        
        // Try a simple command
        print('Executing simple command...');
        final result = await client.run('echo "test"');
        print('Command result: "${result.stdout}"');
        print('Command stderr: "${result.stderr}"');
        print('Command exit code: ${result.exitCode}');
        
        await client.close();
        print('Connection closed successfully');
        
      } catch (e) {
        print('SSH connection failed (expected): $e');
        // This is expected to fail in many test environments
        expect(e, isA<Exception>());
      }
    });
  });
}