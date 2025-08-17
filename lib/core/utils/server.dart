import 'dart:async';

import 'package:server_box/ffi/ssh_adapter_async.dart';
import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/foundation.dart';
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

Future<SSHClient> genClient(
  Spi spi, {
  void Function(GenSSHClientStatus)? onStatus,
  String? privateKey,
  String? jumpPrivateKey,
  Duration timeout = const Duration(seconds: 5),
  Spi? jumpSpi,
  SSHUserInfoRequestHandler? onKeyboardInteractive,
}) async {
  onStatus?.call(GenSSHClientStatus.socket);

  // Handle jump server
  if (jumpSpi != null || spi.jumpId != null) {
    final jumpSpi_ = jumpSpi ?? Stores.server.box.get(spi.jumpId!);
    if (jumpSpi_ != null) {
      // For now, simplified jump server support
      // In full implementation, would setup proper forwarding
      debugPrint('Jump server not fully implemented in Rust SSH adapter');
    }
  }

  final keyId = spi.keyId;
  
  // Use direct connection with our new adapter
  if (keyId == null) {
    // Password authentication
    onStatus?.call(GenSSHClientStatus.pwd);
    return await SSHClient.connect(
      host: spi.ip,
      port: spi.port,
      username: spi.user,
      password: spi.pwd ?? '',
      timeout: timeout,
    );
  } else {
    // Key authentication
    onStatus?.call(GenSSHClientStatus.key);
    privateKey ??= getPrivateKey(keyId);
    return await SSHClient.connectWithKey(
      host: spi.ip,
      port: spi.port,
      username: spi.user,
      privateKey: privateKey,
      timeout: timeout,
    );
  }
}
