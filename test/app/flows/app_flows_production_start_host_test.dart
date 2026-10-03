import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../../integration_test/app_flows_test.dart' as emulator_entry;

/// Runs the EMULATOR entry point (`integration_test/app_flows_test.dart`) in
/// the host VM: the same `SelfImprovementApp()` with the production starter,
/// the real SQLite file (in a temporary directory), the real clock, the real
/// Dart code of `flutter_timezone`, `path_provider` and
/// `flutter_local_notifications`, and the live test binding the emulator uses.
///
/// Only the native side of three plugins does not exist on the host. Their
/// platform channels are answered here, the way a fresh Android emulator
/// answers: the support and cache directories, the time zone `Europe/Berlin`,
/// and notifications that are not allowed yet. What this does NOT prove: the
/// native parts (the Android plugins, the sqlite library of the APK, the
/// keyboard, real screen sizes, real permissions). It runs the code that opens
/// the database file, starts and restarts the app and wipes the data against a
/// real file and real frames, without an emulator.
///
/// It takes about a minute because it waits in real time like on a device. For
/// a quick loop run `app_flows_host_test.dart` alone.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final root = Directory.systemTemp.createTempSync('flows_production_start_');
  final support = Directory('${root.path}/support')..createSync();
  final cache = Directory('${root.path}/cache')..createSync();
  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // A leftover temporary directory is not a test failure.
    }
  });

  final messenger = binding.defaultBinaryMessenger;
  messenger
    ..setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => switch (call.method) {
        'getApplicationSupportDirectory' => support.path,
        _ => cache.path,
      },
    )
    ..setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (call) async => 'Europe/Berlin',
    )
    ..setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => switch (call.method) {
        'initialize' => true,
        'areNotificationsEnabled' => false,
        'pendingNotificationRequests' => <Map<Object?, Object?>>[],
        _ => null,
      },
    )
    // The integration test binding reports its result to the host app of an
    // emulator run; there is none here.
    ..setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/integration_test'),
      (call) async => null,
    );
  // On Android the plugin registers its implementation at start.
  AndroidFlutterLocalNotificationsPlugin.registerWith();

  emulator_entry.main();
}
