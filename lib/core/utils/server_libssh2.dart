import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:server_box/core/libssh2/ssh_adapter.dart';
import 'package:server_box/core/libssh2/ssh_logger.dart';
import 'package:server_box/data/model/app/error.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/data/res/store.dart';

/// Must put this func out of any Class.
///
/// Because of this function is called by [compute].
///
/// https://stackoverflow.com/questions/51998995/invalid-arguments-illegal-argument-in-isolate-message-object-is-a-closure
List<SSHKeyPair> loadIndentity(String key) {
  return SSHKeyPair.fromPem(key);
}

/// [args] : [key, pwd]
String decyptPem(List<String> args) {
  /// skip when the key is not encrypted, or will throw exception
  if (!SSHKeyPair.isEncryptedPem(args[0])) return args[0];
  final sshKey = SSHKeyPair.fromPem(args[0], args[1]);
  return sshKey.first.toPem();
}

enum GenSSHClientStatus { socket, key, pwd }

String getPrivateKey(String id) {
  final pki = Stores.key.fetchOne(id);
  if (pki == null) {
    throw SSHErr(type: SSHErrType.noPrivateKey, message: 'key [$id] not found');
  }
  return pki.key;
}

/// Save private key to temporary file for SSH client
Future<String> savePrivateKeyToTemp(String key) async {
  final tempDir = await Directory.systemTemp.createTemp('ssh_key_');
  final keyFile = File('${tempDir.path}/id_rsa');
  await keyFile.writeAsString(key);
  
  // Set proper permissions (600) for the key file
  if (Platform.isLinux || Platform.isMacOS) {
    await Process.run('chmod', ['600', keyFile.path]);
  }
  
  return keyFile.path;
}

/// Clean up temporary key file
Future<void> cleanupTempKey(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    // Also try to delete the parent temp directory
    final parent = file.parent;
    if (await parent.exists() && parent.path.contains('ssh_key_')) {
      await parent.delete(recursive: true);
    }
  } catch (e) {
    // Ignore cleanup errors
  }
}

Future<SSHClient> genClient(
  Spi spi, {
  void Function(GenSSHClientStatus)? onStatus,

  /// Only pass this param if using multi-threading and key login
  String? privateKey,

  /// Only pass this param if using multi-threading and key login
  String? jumpPrivateKey,
  Duration timeout = const Duration(seconds: 5),

  /// [Spi] of the jump server
  ///
  /// Must pass this param if using multi-threading and key login
  Spi? jumpSpi,

  /// Handle keyboard-interactive authentication
  dynamic onKeyboardInteractive,
}) async {
  final logger = SSHLogger(prefix: 'SSH-${spi.name}');
  logger.info('[genClient] Starting SSH client generation for ${spi.user}@${spi.ip}:${spi.port}');
  
  onStatus?.call(GenSSHClientStatus.socket);

  String? alterUser;
  String? tempKeyPath;

  try {
    // Handle jump server proxy
    final jumpSpi_ = () {
      if (jumpSpi != null) return jumpSpi;
      if (spi.jumpId != null) return Stores.server.box.get(spi.jumpId);
    }();
    
    if (jumpSpi_ != null) {
      logger.info('[genClient] Using jump server: ${jumpSpi_.user}@${jumpSpi_.ip}:${jumpSpi_.port}');
      // For jump servers, we need to use the dartssh2 approach for now
      // as port forwarding is not yet implemented in libssh2 adapter
      throw UnimplementedError('Jump servers not yet supported with libssh2');
    }

    // Try primary connection
    String host = spi.ip;
    int port = spi.port;
    String user = spi.user;
    
    try {
      logger.debug('[genClient] Attempting primary connection to $host:$port');
    } catch (e) {
      logger.warning('[genClient] Primary connection failed, trying alternate URL', e);
      if (spi.alterUrl == null) rethrow;
      
      try {
        final res = spi.fromStringUrl();
        alterUser = res.$2;
        host = res.$1;
        port = res.$3;
        user = alterUser ?? spi.user;
        logger.info('[genClient] Using alternate URL: $user@$host:$port');
      } catch (e) {
        logger.error('[genClient] Alternate URL parsing failed', e);
        rethrow;
      }
    }

    // Prepare authentication
    final keyId = spi.keyId;
    String? password = spi.pwd;
    
    if (keyId != null) {
      onStatus?.call(GenSSHClientStatus.key);
      logger.info('[genClient] Using key authentication with key ID: $keyId');
      
      privateKey ??= getPrivateKey(keyId);
      tempKeyPath = await savePrivateKeyToTemp(privateKey);
      logger.debug('[genClient] Private key saved to temp file: $tempKeyPath');
      password = null; // Don't use password if key is provided
    } else if (password != null) {
      onStatus?.call(GenSSHClientStatus.pwd);
      logger.info('[genClient] Using password authentication');
    } else {
      logger.error('[genClient] No authentication method available');
      throw SSHErr(type: SSHErrType.auth, message: 'No authentication method provided');
    }

    // Create SSH client with libssh2
    logger.info('[genClient] Creating SSH client with libssh2 adapter');
    final client = await SSHClient.connect(
      host,
      port,
      username: user,
      password: password,
      privateKeyPath: tempKeyPath,
      timeout: timeout,
      logger: logger,
    );

    logger.info('[genClient] SSH client created successfully');
    
    // Clean up temp key file after connection
    if (tempKeyPath != null) {
      // Schedule cleanup after a delay to ensure the connection is established
      Future.delayed(const Duration(seconds: 2), () {
        cleanupTempKey(tempKeyPath!).then((_) {
          logger.debug('[genClient] Temporary key file cleaned up');
        });
      });
    }
    
    return client;
    
  } catch (e, stack) {
    logger.error('[genClient] Failed to generate SSH client', e, stack);
    
    // Clean up temp key file on error
    if (tempKeyPath != null) {
      await cleanupTempKey(tempKeyPath);
    }
    
    rethrow;
  }
}