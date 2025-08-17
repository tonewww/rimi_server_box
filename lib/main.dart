// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:computer/computer.dart';
import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:server_box/app.dart';
import 'package:server_box/core/sync.dart';
import 'package:server_box/data/model/app/menu/server_func.dart';
import 'package:server_box/data/model/app/server_detail_card.dart';
import 'package:server_box/data/provider/private_key.dart';
import 'package:server_box/data/provider/server.dart';
import 'package:server_box/data/provider/sftp.dart';
import 'package:server_box/data/provider/snippet.dart';
import 'package:server_box/data/res/build_data.dart';
import 'package:server_box/data/res/store.dart';
import 'package:server_box/data/ssh/session_manager.dart';
import 'package:server_box/data/store/server.dart';
import 'package:server_box/ffi/ssh_isolate_adapter.dart';
import 'package:server_box/hive/hive_registrar.g.dart';

Future<void> main() async {
  _runInZone(() async {
    await _initApp();
    runApp(const MyApp());
  });
}

void _runInZone(void Function() body) {
  final zoneSpec = ZoneSpecification(
    print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
      parent.print(zone, line);
    },
  );

  runZonedGuarded(
    body,
    (e, s) => print('[ZONE] $e\n$s'),
    zoneSpecification: zoneSpec,
  );
}

Future<void> _initApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initData();
  _setupDebug();
  await _initWindow();

  _doPlatformRelated();

  // Initialize Android session notification channel/handler
  TermSessionManager.init();

  // Initialize SSH isolate for non-blocking SSH operations
  await IsolateSSHClient.initialize();
}

Future<void> _initData() async {
  await Paths.init(BuildData.name, bakName: 'srvbox_bak.json');

  await Hive.initFlutter();
  Hive.registerAdapters();

  await PrefStore.shared.init(); // Call this before accessing any store

  try {
    await Stores.init();
  } catch (e) {
    print('Store initialization failed: $e');

    // Check if it's a keychain/secure storage error
    if (e.toString().contains('-34018') ||
        e.toString().contains('authorization') ||
        e.toString().contains('entitlement') ||
        e.toString().contains('keychain')) {
      print('Keychain/secure storage error detected.');
      print(
        'This is likely due to macOS entitlement issues or missing code signing.',
      );
      print('To fix this issue:');
      print(
        '1. Add proper keychain entitlements to macos/Runner/DebugProfile.entitlements',
      );
      print('2. Configure code signing in Xcode project settings');
      print('3. Or run on a device with proper provisioning profile');
      print('');
      print('For SSH functionality testing, you can try:');
      print('- Running tests instead: flutter test');
      print('- Using a different platform (iOS/Android) if available');
      print('- Configuring proper macOS development team and signing');

      // For now, we'll terminate gracefully rather than crash
      exit(1);
    } else {
      rethrow;
    }
  }

  // It may effect the following logic, so await it.
  // DO DB migration before load any provider.
  await _doDbMigrate();

  // DO NOT change the order of these providers.
  PrivateKeyProvider.instance.load();
  SnippetProvider.instance.load();
  ServerProvider.instance.load();
  SftpProvider.instance.load();

  if (Stores.setting.betaTest.fetch()) AppUpdate.chan = AppUpdateChan.beta;

  FontUtils.loadFrom(Stores.setting.fontPath.fetch());
}

void _setupDebug() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    DebugProvider.addLog(record);
    lprint(record);
    if (record.error != null) print(record.error);
    if (record.stackTrace != null) print(record.stackTrace);
  });
}

void _doPlatformRelated() async {
  if (isAndroid) {
    // try switch to highest refresh rate
    FlutterDisplayMode.setHighRefreshRate();
  }

  final serversCount = Stores.server.keys().length;
  Computer.shared.turnOn(
    workersCount: (serversCount / 3).round() + 1,
  ); // Plus 1 to avoid 0.

  bakSync.sync();
}

// It may contains some async heavy funcs.
Future<void> _doDbMigrate() async {
  final lastVer = Stores.setting.lastVer.fetch();
  const newVer = BuildData.build;
  // It's only the version upgrade trigger logic.
  // How to upgrade the data is inside each own func.
  if (lastVer < newVer) {
    ServerDetailCards.autoAddNewCards(newVer);
    ServerFuncBtn.autoAddNewFuncs(newVer);
    Stores.setting.lastVer.put(newVer);
  }

  // Migrate the old id to new id.
  ServerStore.instance.migrateIds();
}

Future<void> _initWindow() async {
  if (!isDesktop) return;
  final windowStateProp = Stores.setting.windowState;
  final windowState = windowStateProp.fetch();
  final hideTitleBar = Stores.setting.hideTitleBar.fetch();
  await SystemUIs.initDesktopWindow(
    hideTitleBar: hideTitleBar,
    size: windowState?.size ?? Size(947, 487),
    position: windowState?.position,
    listener: WindowStateListener(windowStateProp),
  );
}
