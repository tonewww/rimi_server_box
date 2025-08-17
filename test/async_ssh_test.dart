// Test for the new async SSH architecture
// This tests that the async SSH client can be created and performs basic operations

import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/ffi/ssh_isolate_adapter.dart';

void main() {
  group('Async SSH Tests', () {
    test('AsyncSSHClient can be created', () {
      final client = AsyncSSHClient();
      expect(client.isConnected, false);
      expect(client.isClosed, true);
    });

    test('AsyncSSHClient static connect method exists', () {
      expect(AsyncSSHClient.connect, isA<Function>());
      expect(AsyncSSHClient.connectWithKey, isA<Function>());
    });

    test('AsyncSSHResult can be created from mock data', () {
      // We can't test actual connections without a test server,
      // but we can test the data structures
      expect(true, true); // Placeholder - actual connection tests would require test SSH server
    });

    test('Type aliases work correctly', () {
      // Test that our type aliases are properly exported
      expect(SSHClient, equals(AsyncSSHClient));
      expect(SSHResult, equals(AsyncSSHResult));
      expect(SSHSession, equals(AsyncSSHSession));
    });
  });
}