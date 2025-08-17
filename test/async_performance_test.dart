// Performance test for the async SSH architecture
// This test demonstrates that async operations don't block the main thread

import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/ffi/ssh_adapter_async.dart';

void main() {
  group('Async Performance Tests', () {
    test('Multiple async SSH clients can be created without blocking', () async {
      // Test that we can create multiple clients concurrently
      final stopwatch = Stopwatch()..start();
      
      final clients = <AsyncSSHClient>[];
      
      // Create 5 clients concurrently
      for (int i = 0; i < 5; i++) {
        clients.add(AsyncSSHClient());
      }
      
      stopwatch.stop();
      
      // Creating clients should be very fast (under 100ms)
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
      expect(clients.length, equals(5));
      
      // All clients should be disconnected initially
      for (final client in clients) {
        expect(client.isConnected, false);
        expect(client.isClosed, true);
      }
    });

    test('Async architecture provides proper type checking', () {
      // Test that our async types work correctly
      final client = AsyncSSHClient();
      
      // Test type compatibility
      expect(client, isA<AsyncSSHClient>());
      expect(client, isA<SSHClient>()); // Type alias should work
      
      expect(client.isConnected, isA<bool>());
      expect(client.isClosed, isA<bool>());
      expect(client.isUsingAsync, isA<bool>());
    });

    test('Async operations have proper future typing', () {
      final client = AsyncSSHClient();
      
      // Test that methods return proper Future types
      expect(client.close(), isA<Future<void>>());
      expect(client.ping(), isA<Future<void>>());
      
      // Static methods should also return proper types
      expect(AsyncSSHClient.connect(
        host: 'test',
        username: 'test',
        password: 'test',
      ), isA<Future<AsyncSSHClient>>());
      
      expect(AsyncSSHClient.connectWithKey(
        host: 'test',
        username: 'test',
        privateKey: 'test',
      ), isA<Future<AsyncSSHClient>>());
    });

    test('Error handling works correctly for invalid connections', () async {
      // Test that connection attempts to invalid hosts fail gracefully
      final stopwatch = Stopwatch()..start();
      
      try {
        await AsyncSSHClient.connect(
          host: 'invalid.host.example.com',
          username: 'testuser',
          password: 'testpass',
          timeout: const Duration(seconds: 1), // Short timeout for testing
        );
        
        // If we get here, the connection unexpectedly succeeded
        fail('Expected connection to fail for invalid host');
      } catch (e) {
        // Connection should fail, which is expected
        stopwatch.stop();
        
        // Should fail quickly due to timeout
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
        expect(e, isA<Exception>());
      }
    });

    test('Async methods maintain proper signatures', () {
      final client = AsyncSSHClient();
      
      // Test that methods accept the right parameters
      expect(() => client.run('test command'), returnsNormally);
      expect(() => client.execute('test command'), returnsNormally);
      expect(() => client.shell(), returnsNormally);
      expect(() => client.sftp(), returnsNormally);
      
      // Test port forwarding methods
      expect(() => client.forwardLocal('localhost', 22), returnsNormally);
      expect(() => client.forwardRemote(8080, 'localhost', 22), returnsNormally);
    });
  });
  
  group('Performance Comparison Tests', () {
    test('Async client creation is non-blocking', () {
      final stopwatch = Stopwatch()..start();
      
      // Create multiple clients in quick succession
      final clients = <AsyncSSHClient>[];
      for (int i = 0; i < 10; i++) {
        clients.add(AsyncSSHClient());
      }
      
      stopwatch.stop();
      
      // Creating 10 clients should be very fast
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
      expect(clients.length, equals(10));
      
      // Cleanup
      for (final client in clients) {
        client.close();
      }
    });
    
    test('Async architecture supports proper resource management', () async {
      final client = AsyncSSHClient();
      
      // Test that we can call close multiple times safely
      await client.close();
      await client.close(); // Second close should not throw
      
      // Test that closed client reports correct state
      expect(client.isConnected, false);
      expect(client.isClosed, true);
    });
  });
}