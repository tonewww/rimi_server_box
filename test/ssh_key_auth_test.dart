// Test SSH connection using key-based authentication
import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/ffi/ssh_bindings.dart';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

void main() {
  group('SSH Key Authentication Tests', () {
    setUpAll(() {
      print('=== SSH Key Authentication Test Setup ===');
      final initResult = NativeSshBindings.init();
      print('SSH library initialization result: $initResult');
      expect(initResult, equals(ErrorCode.success));
    });

    tearDownAll(() {
      print('=== SSH Key Authentication Test Cleanup ===');
      final cleanupResult = NativeSshBindings.cleanup();
      print('SSH library cleanup result: $cleanupResult');
    });

    test('Test SSH connection with ED25519 key authentication', () async {
      print('\n=== Testing SSH Key Authentication ===');
      
      // Check if the key file exists
      final keyPath = '${Platform.environment['HOME']}/.ssh/id_ed25519';
      final keyFile = File(keyPath);
      
      if (!keyFile.existsSync()) {
        print('❌ Private key not found at: $keyPath');
        print('Skipping key authentication test');
        return;
      }
      
      print('🔑 Using private key: $keyPath');
      
      final config = malloc<CSshConfig>();
      try {
        final host = '192.168.50.7'.toNativeUtf8();
        final username = 'ptw'.toNativeUtf8();
        final privateKey = keyPath.toNativeUtf8();
        
        config.ref
          ..host = host.cast()
          ..port = 22
          ..username = username.cast()
          ..password = nullptr  // No password, using key
          ..private_key = privateKey.cast()
          ..passphrase = nullptr  // No passphrase for this key
          ..timeout_secs = 10;
        
        print('Configuration:');
        print('  Host: 192.168.50.7');
        print('  Port: 22');
        print('  Username: ptw');
        print('  Private Key: $keyPath');
        print('  Timeout: 10 seconds');
        
        // Attempt connection
        print('\nAttempting SSH connection with key authentication...');
        final sessionId = NativeSshBindings.connect(config);
        print('Connection result: sessionId = $sessionId');
        
        if (sessionId == 0) {
          print('❌ Key authentication failed');
          
          final lastError = NativeSshBindings.getLastError();
          if (lastError != null) {
            print('💡 Specific error: $lastError');
          }
          
          fail('SSH key authentication failed');
        } else {
          print('✅ Key authentication successful! Session ID: $sessionId');
          
          // Test command execution
          print('\n🧪 Testing command execution...');
          final command = 'whoami'.toNativeUtf8();
          final result = malloc<CCommandResult>();
          
          try {
            final execResult = NativeSshBindings.executeCommand(
              sessionId, 
              command.cast(), 
              result
            );
            
            if (execResult == ErrorCode.success) {
              final stdout = result.ref.stdout.cast<Utf8>().toDartString();
              final stderr = result.ref.stderr.cast<Utf8>().toDartString();
              final exitCode = result.ref.exitCode;
              
              print('✅ Command executed successfully:');
              print('  stdout: "${stdout.trim()}"');
              print('  stderr: "${stderr.trim()}"');
              print('  exit code: $exitCode');
              
              expect(stdout.trim(), equals('ptw'));
              expect(exitCode, equals(0));
            } else {
              print('❌ Command execution failed with error code: $execResult');
              fail('Command execution failed');
            }
            
            NativeSshBindings.freeCommandResult(result);
          } finally {
            malloc.free(command);
            malloc.free(result);
          }
          
          // Test another command
          print('\n🧪 Testing system info command...');
          final unameCommand = 'uname -a'.toNativeUtf8();
          final unameResult = malloc<CCommandResult>();
          
          try {
            final execResult = NativeSshBindings.executeCommand(
              sessionId, 
              unameCommand.cast(), 
              unameResult
            );
            
            if (execResult == ErrorCode.success) {
              final stdout = unameResult.ref.stdout.cast<Utf8>().toDartString();
              print('✅ System info: ${stdout.trim()}');
            }
            
            NativeSshBindings.freeCommandResult(unameResult);
          } finally {
            malloc.free(unameCommand);
            malloc.free(unameResult);
          }
          
          // Disconnect
          print('\n🔌 Disconnecting...');
          final disconnectResult = NativeSshBindings.disconnect(sessionId);
          print('✅ Disconnect result: $disconnectResult');
          expect(disconnectResult, equals(ErrorCode.success));
        }
        
      } finally {
        // Clean up allocated memory
        if (config.ref.host != nullptr) malloc.free(config.ref.host);
        if (config.ref.username != nullptr) malloc.free(config.ref.username);
        if (config.ref.private_key != nullptr) malloc.free(config.ref.private_key);
        malloc.free(config);
      }
    });

    test('Test SSH connection with password (expected to fail)', () {
      print('\n=== Testing Password Authentication (Expected to Fail) ===');
      
      final config = malloc<CSshConfig>();
      try {
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
          ..timeout_secs = 5;
        
        print('Attempting password authentication (should fail)...');
        final sessionId = NativeSshBindings.connect(config);
        
        expect(sessionId, equals(0), reason: 'Password auth should fail for this user');
        
        final lastError = NativeSshBindings.getLastError();
        if (lastError != null) {
          print('✅ Expected authentication failure: $lastError');
          expect(lastError, contains('Authentication failed'));
        }
        
      } finally {
        if (config.ref.host != nullptr) malloc.free(config.ref.host);
        if (config.ref.username != nullptr) malloc.free(config.ref.username);
        if (config.ref.password != nullptr) malloc.free(config.ref.password);
        malloc.free(config);
      }
    });
  });
}