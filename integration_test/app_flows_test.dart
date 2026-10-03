import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:self_improvement/app/app.dart';
import 'package:self_improvement/core/database/database_connection.dart';

import 'flows/first_start_flow.dart';
import 'flows/flow_context.dart';
import 'flows/focus_flow.dart';
import 'flows/platform_flow.dart';
import 'flows/reset_flow.dart';
import 'flows/tasks_flow.dart';
import 'flows/water_flow.dart';
import 'flows/weight_flow.dart';

/// The emulator side of the flows: the app starts exactly like in production
/// (`SelfImprovementApp()` with its default starter and no override), so the
/// real SQLite file in the app support directory, the real device zone from
/// `flutter_timezone`, the real notification plugin and the real clock are in
/// play. The same flow functions run in `test/app/flows/app_flows_host_test.dart`
/// on the host.
///
/// WARNING: before every test the database file of the app is deleted, so every
/// test starts like a fresh install. Run this only on an emulator or a device
/// whose app data may be thrown away.
final class _DeviceEnvironment implements FlowEnvironment {
  /// The longest real time the emulator waits when a flow wants time to pass.
  /// Long enough to be measured on the one-second countdown, short enough to
  /// keep the run fast.
  static const Duration _maxRealWait = Duration(seconds: 4);

  @override
  Future<void> closeApp(WidgetTester tester) async {
    // Unmounting the app disposes the provider container and closes the
    // database connection; closing is asynchronous, so give it a moment before
    // anything touches the file again.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFor(tester, const Duration(seconds: 1));
  }

  @override
  Future<void> openApp(WidgetTester tester) async {
    await tester.pumpWidget(const SelfImprovementApp());
    await waitForAppStart(tester);
  }

  @override
  Future<Duration> letTimePass(WidgetTester tester, Duration wanted) async {
    final real = wanted < _maxRealWait ? wanted : _maxRealWait;
    return _pumpFor(tester, real);
  }

  @override
  Future<void> expectDatabaseOnDisk() async {
    final file = await _databaseFile();
    expect(
      file.existsSync(),
      isTrue,
      reason: 'the production start must create ${file.path}',
    );
  }

  @override
  Future<String> platformZoneId() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;
}

/// Pumps frames for [duration] of real time and returns how long it took.
Future<Duration> _pumpFor(WidgetTester tester, Duration duration) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < duration) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return watch.elapsed;
}

/// The SQLite file of the app, see `openAppConnection`.
Future<File> _databaseFile() async {
  final directory = await getApplicationSupportDirectory();
  return File(p.join(directory.path, '$appDatabaseName.sqlite'));
}

/// Deletes the database file and its companions (`-wal`, `-shm`, `-journal`),
/// so the next start of the app creates and migrates a new database like on a
/// fresh install.
Future<void> _deleteDatabaseFiles() async {
  final directory = await getApplicationSupportDirectory();
  if (!directory.existsSync()) {
    return;
  }
  for (final entity in directory.listSync()) {
    if (entity is File && p.basename(entity.path).startsWith(appDatabaseName)) {
      entity.deleteSync();
    }
  }
}

/// Runs [flow] on a fresh install: empty app data, the production start, and
/// the app closed again afterwards (also when the flow fails), so its database
/// connection is gone before the next test deletes the file.
Future<void> _runFlow(
  WidgetTester tester,
  Future<void> Function(FlowContext ctx) flow,
) async {
  await _deleteDatabaseFiles();
  final environment = _DeviceEnvironment();
  final ctx = FlowContext(tester: tester, environment: environment);
  try {
    await environment.openApp(tester);
    await flow(ctx);
  } finally {
    await environment.closeApp(tester);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Render every frame the app asks for, like the real app does. The default
  // policy only draws the frames the test pumps, which stretches the time
  // between two frames to the pump interval and shifts how asynchronous work
  // and frames interleave compared to a user holding the phone.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  // Like `main()`: draw behind the system bars.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  // A wedged flow must not hold the CI job until its own limit.
  const limit = Timeout(Duration(minutes: 5));

  testWidgets('AT01 first start: onboarding leads to the home screen', (
    tester,
  ) async {
    await _runFlow(tester, firstStartFlow);
  }, timeout: limit);

  testWidgets(
    'AT02 and AT06 weight: saved, shown and still there after a restart',
    (tester) async {
      await _runFlow(tester, weightPersistsFlow);
    },
    timeout: limit,
  );

  testWidgets('AT10 water: +250 ml from the home screen, undo once', (
    tester,
  ) async {
    await _runFlow(tester, waterQuickAddFlow);
  }, timeout: limit);

  testWidgets('AT13 task: create, complete, reopen, complete again', (
    tester,
  ) async {
    await _runFlow(tester, taskFlow);
  }, timeout: limit);

  testWidgets(
    'AT16 focus: pause, resume, restart mid-session, time caught up',
    (tester) async {
      await _runFlow(tester, focusSessionFlow);
    },
    timeout: limit,
  );

  testWidgets(
    'AT32 reset: cancel changes nothing, confirm returns to the onboarding',
    (tester) async {
      await _runFlow(tester, resetFlow);
    },
    timeout: limit,
  );

  testWidgets(
    'F7 platform: database file, zone and reminder platform after the start (permission only read, not asserted)',
    (tester) async {
      await _runFlow(tester, realPlatformFlow);
    },
    timeout: limit,
  );
}
