// Debug test to analyze SSH connection failures in detail
import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/ffi/ssh_bindings.dart';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

void main() {
  group('Rust SSH Debug Tests', () {
    setUpAll(() {
      print('=== Rust SSH Debug Test Setup ===');
      final initResult = NativeSshBindings.init();
      print('SSH library initialization result: $initResult');
      expect(initResult, equals(ErrorCode.success));
    });

    tearDownAll(() {
      print('=== Rust SSH Debug Test Cleanup ===');
      final cleanupResult = NativeSshBindings.cleanup();
      print('SSH library cleanup result: $cleanupResult');
    });

    test('Test SSH connection with detailed error reporting', () async {
      print('\n=== Starting SSH Connection Debug Test ===');
      
      // Create configuration
      final config = malloc<CSshConfig>();
      try {
        // Set up connection parameters
        final host = '192.168.50.7'.toNativeUtf8();
        final username = 'ptw'.toNativeUtf8();
        final password = 'test123'.toNativeUtf8();
        
        config.ref
          ..host = host.cast()
          ..port = 22
          ..username = username.cast()
          ..password = password.cast()
          ..private_key = nullptr
          ..passphrase = nullptr
          ..timeout_secs = 10;
        
        print('Configuration created:');
        print('  Host: 192.168.50.7');
        print('  Port: 22');
        print('  Username: ptw');
        print('  Password: [set]');
        print('  Timeout: 10 seconds');
        
        // Attempt connection
        print('\nAttempting SSH connection...');
        final sessionId = NativeSshBindings.connect(config);
        print('Connection result: sessionId = $sessionId');
        
        if (sessionId == 0) {
          print('❌ Connection failed with session ID 0');
          
          // Get the specific error message
          final lastError = NativeSshBindings.getLastError();
          if (lastError != null) {
            print('💡 Specific error: $lastError');
          } else {
            print('⚠️  No specific error message available');
          }
          
          fail('SSH connection failed - see detailed output above');
        } else {
          print('✅ Connection successful with session ID: $sessionId');
          
          // Test command execution
          print('\nTesting command execution...');
          final command = 'echo "test"'.toNativeUtf8();
          final result = malloc<CCommandResult>();
          
          try {
            final execResult = NativeSshBindings.executeCommand(
              sessionId, 
              command.cast(), 
              result
            );
            
            print('Command execution result code: $execResult');
            
            if (execResult == ErrorCode.success) {
              final stdout = result.ref.stdout.cast<Utf8>().toDartString();
              final stderr = result.ref.stderr.cast<Utf8>().toDartString();
              final exitCode = result.ref.exitCode;
              
              print('Command output:');
              print('  stdout: "$stdout"');
              print('  stderr: "$stderr"');
              print('  exit code: $exitCode');
            } else {
              print('❌ Command execution failed with error code: $execResult');
            }
            
            // Free command result
            NativeSshBindings.freeCommandResult(result);
          } finally {
            malloc.free(command);
            malloc.free(result);
          }
          
          // Disconnect
          print('\nDisconnecting...');
          final disconnectResult = NativeSshBindings.disconnect(sessionId);
          print('Disconnect result: $disconnectResult');
        }
        
      } finally {
        // Clean up allocated memory
        if (config.ref.host != nullptr) malloc.free(config.ref.host);
        if (config.ref.username != nullptr) malloc.free(config.ref.username);
        if (config.ref.password != nullptr) malloc.free(config.ref.password);
        malloc.free(config);
      }
    });

    test('Test with invalid host to verify error handling', () {
      print('\n=== Testing with Invalid Host ===');
      
      final config = malloc<CSshConfig>();
      try {
        final host = 'invalid.host.that.does.not.exist'.toNativeUtf8();
        final username = 'test'.toNativeUtf8();
        final password = 'test'.toNativeUtf8();
        
        config.ref
          ..host = host.cast()
          ..port = 22
          ..username = username.cast()
          ..password = password.cast()
          ..private_key = nullptr
          ..passphrase = nullptr
          ..timeout_secs = 5;
        
        print('Attempting connection to invalid host...');
        final sessionId = NativeSshBindings.connect(config);
        print('Result with invalid host: sessionId = $sessionId');
        
        expect(sessionId, equals(0), reason: 'Should fail with invalid host');
        
      } finally {
        if (config.ref.host != nullptr) malloc.free(config.ref.host);
        if (config.ref.username != nullptr) malloc.free(config.ref.username);
        if (config.ref.password != nullptr) malloc.free(config.ref.password);
        malloc.free(config);
      }
    });

    test('Test with unreachable host (timeout)', () {
      print('\n=== Testing with Unreachable Host ===');
      
      final config = malloc<CSshConfig>();
      try {
        // Use a valid IP that should be unreachable (reserved range)
        final host = '192.0.2.1'.toNativeUtf8();  // RFC5737 test address
        final username = 'test'.toNativeUtf8();
        final password = 'test'.toNativeUtf8();
        
        config.ref
          ..host = host.cast()
          ..port = 22
          ..username = username.cast()
          ..password = password.cast()
          ..private_key = nullptr
          ..passphrase = nullptr
          ..timeout_secs = 5;
        
        print('Attempting connection to unreachable host (timeout test)...');
        final sessionId = NativeSshBindings.connect(config);
        print('Result with unreachable host: sessionId = $sessionId');
        
        expect(sessionId, equals(0), reason: 'Should fail with unreachable host');
        
      } finally {
        if (config.ref.host != nullptr) malloc.free(config.ref.host);
        if (config.ref.username != nullptr) malloc.free(config.ref.username);
        if (config.ref.password != nullptr) malloc.free(config.ref.password);
        malloc.free(config);
      }
    });
  });
}