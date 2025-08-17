import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/data/ssh/session_manager.dart';

void main() {
  group('SSH Connection Status Tests', () {
    setUpAll(() {
      debugPrint('Setting up SSH Connection Status Tests');
    });

    tearDownAll(() {
      debugPrint('Tearing down SSH Connection Status Tests');
    });

    test('TermSessionManager should handle status updates correctly', () {
      final spi = Spi(
        id: 'test-server-1',
        name: 'Test Server',
        ip: '127.0.0.1',
        port: 22,
        user: 'testuser',
        pwd: 'testpass',
      );

      // Add session
      TermSessionManager.add(
        id: 'ssh_test-server-1',
        spi: spi,
        startTimeMs: DateTime.now().millisecondsSinceEpoch,
        disconnect: () => debugPrint('Disconnect called'),
        status: TermSessionStatus.connecting,
      );

      // Verify initial status
      expect(
        TermSessionManager.entries.containsKey('ssh_test-server-1'),
        isTrue,
      );
      expect(
        TermSessionManager.entries['ssh_test-server-1']?.status,
        equals(TermSessionStatus.connecting),
      );

      // Update to connected
      TermSessionManager.updateStatus(
        'ssh_test-server-1',
        TermSessionStatus.connected,
      );
      expect(
        TermSessionManager.entries['ssh_test-server-1']?.status,
        equals(TermSessionStatus.connected),
      );

      // Update to disconnected
      TermSessionManager.updateStatus(
        'ssh_test-server-1',
        TermSessionStatus.disconnected,
      );
      expect(
        TermSessionManager.entries['ssh_test-server-1']?.status,
        equals(TermSessionStatus.disconnected),
      );

      // Remove session
      TermSessionManager.remove('ssh_test-server-1');
      expect(
        TermSessionManager.entries.containsKey('ssh_test-server-1'),
        isFalse,
      );
    });

    test('TermSessionManager should handle multiple sessions', () {
      final spi1 = Spi(
        id: 'test-server-1',
        name: 'Test Server 1',
        ip: '127.0.0.1',
        port: 22,
        user: 'testuser',
        pwd: 'testpass',
      );

      final spi2 = Spi(
        id: 'test-server-2',
        name: 'Test Server 2',
        ip: '192.168.1.100',
        port: 22,
        user: 'testuser',
        pwd: 'testpass',
      );

      // Add multiple sessions
      TermSessionManager.add(
        id: 'ssh_test-server-1',
        spi: spi1,
        startTimeMs: DateTime.now().millisecondsSinceEpoch,
        disconnect: () => debugPrint('Disconnect server 1'),
        status: TermSessionStatus.connecting,
      );

      TermSessionManager.add(
        id: 'ssh_test-server-2',
        spi: spi2,
        startTimeMs: DateTime.now().millisecondsSinceEpoch,
        disconnect: () => debugPrint('Disconnect server 2'),
        status: TermSessionStatus.connecting,
      );

      expect(TermSessionManager.entries.length, equals(2));

      // Update different statuses
      TermSessionManager.updateStatus(
        'ssh_test-server-1',
        TermSessionStatus.connected,
      );
      TermSessionManager.updateStatus(
        'ssh_test-server-2',
        TermSessionStatus.disconnected,
      );

      expect(
        TermSessionManager.entries['ssh_test-server-1']?.status,
        equals(TermSessionStatus.connected),
      );
      expect(
        TermSessionManager.entries['ssh_test-server-2']?.status,
        equals(TermSessionStatus.disconnected),
      );

      // Clean up
      TermSessionManager.remove('ssh_test-server-1');
      TermSessionManager.remove('ssh_test-server-2');
      expect(TermSessionManager.entries.isEmpty, isTrue);
    });

    test(
      'TermSessionStatus enum should have correct string representation',
      () {
        expect(TermSessionStatus.connecting.toString(), equals('Connecting'));
        expect(TermSessionStatus.connected.toString(), equals('Connected'));
        expect(
          TermSessionStatus.disconnected.toString(),
          equals('Disconnected'),
        );
      },
    );

    test('TermSessionInfo should serialize to JSON correctly', () {
      final info = TermSessionInfo(
        id: 'test-session',
        title: 'Test Server',
        subtitle: 'user@127.0.0.1:22',
        startTimeMs: 1234567890,
        status: TermSessionStatus.connected,
      );

      final json = info.toJson();
      expect(json['id'], equals('test-session'));
      expect(json['title'], equals('Test Server'));
      expect(json['subtitle'], equals('user@127.0.0.1:22'));
      expect(json['startTimeMs'], equals(1234567890));
      expect(json['status'], equals('Connected'));
    });
  });
}
