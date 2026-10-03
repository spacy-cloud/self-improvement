import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/notifications/application/reminder_service.dart';
import 'package:self_improvement/core/notifications/data/reminder_input_reader.dart';
import 'package:self_improvement/core/notifications/data/reminder_preferences_repository.dart';
import 'package:self_improvement/core/notifications/data/scheduled_notification_repository.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/platform/flutter_local_notifications_reminder_platform.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// The whole engine (planner, service, projection in SQLite) on the real
/// `flutter_local_notifications` Dart code, with only the native Android side
/// replaced by a small stateful stand-in behind the method channel.
///
/// The harness time is far in the future because the plugin checks "not in the
/// past" against the real clock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    fln.AndroidFlutterLocalNotificationsPlugin.registerWith();
  });
  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // The service logs failure categories; keep the test output clean.
  final originalDebugPrint = debugPrint;
  setUp(() => debugPrint = (String? message, {int? wrapWidth}) {});
  tearDown(() => debugPrint = originalDebugPrint);

  late DataHarness data;
  late _NativeAndroid android;
  late FlutterLocalNotificationsReminderPlatform platform;
  late ReminderPreferencesRepository preferences;
  late ReminderService service;

  setUp(() async {
    data = await DataHarness.create(nowIso: '2036-10-03T06:30:00Z');
    android = _NativeAndroid();
    messenger.setMockMethodCallHandler(channel, android.handle);
    platform = FlutterLocalNotificationsReminderPlatform();
    preferences = ReminderPreferencesRepository(
      database: data.database,
      runner: data.runner,
    );
    service = ReminderService(
      inputs: ReminderInputReader(
        database: data.database,
        modules: data.moduleStatus,
        waterGoalReachedToday: () async => false,
      ),
      scheduled: ScheduledNotificationRepository(data.database),
      preferences: preferences,
      platform: platform,
      clock: data.clock,
    );
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await service.dispose();
    await platform.dispose();
    await data.dispose();
  });

  Future<void> switchOn({Set<int> hours = const {10}}) async {
    await preferences.setNotificationsEnabled(
      commandId: data.ids.newId(),
      enabled: true,
    );
    await preferences.setWaterSlots(commandId: data.ids.newId(), hours: hours);
  }

  test(
    'switching on hands seven inexact one-shot alarms to the system',
    () async {
      await switchOn();
      final status = await service.reconcile();

      expect(status.state, ReminderState.active);
      expect(status.scheduledCount, 7);
      expect(android.scheduled, hasLength(7));
      expect(android.scheduled.keys.every((id) => id > 0), isTrue);
      for (final call in android.scheduled.values) {
        final specifics = call['platformSpecifics']! as Map<Object?, Object?>;
        expect(specifics['scheduleMode'], 'inexactAllowWhileIdle');
        expect(call['payload'], '/water');
        expect(call['title'], 'Zeit für ein Glas Wasser');
        expect(call['timeZoneName'], 'Europe/Berlin');
      }
      // 10:00 local on the first day of the horizon.
      final first = android.scheduled.values.first;
      expect(first['scheduledDateTime'], '2036-10-03T10:00:00');
      expect(android.channelCreated, isTrue);
    },
  );

  test('a second run does nothing and only reads', () async {
    await switchOn();
    await service.reconcile();
    android.calls.clear();

    await service.reconcile();

    expect(
      android.calls.map((c) => c.method).toSet(),
      everyElement(
        isIn({
          'areNotificationsEnabled',
          'pendingNotificationRequests',
          'initialize',
          'createNotificationChannel',
        }),
      ),
    );
    expect(android.calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
    expect(android.calls.where((c) => c.method == 'cancel'), isEmpty);
  });

  test('a slot switched off cancels exactly its alarms', () async {
    await switchOn(hours: {10, 12});
    await service.reconcile();
    expect(android.scheduled, hasLength(14));
    android.calls.clear();

    await preferences.setWaterSlots(commandId: data.ids.newId(), hours: {10});
    await service.reconcile();

    final cancels = android.calls.where((c) => c.method == 'cancel').toList();
    expect(cancels, hasLength(7));
    expect(android.scheduled, hasLength(7));
    for (final call in android.scheduled.values) {
      expect(
        (call['scheduledDateTime']! as String).endsWith('T10:00:00'),
        isTrue,
      );
    }
  });

  test(
    'switching reminders off cancels everything pending, not what is shown',
    () async {
      await switchOn();
      await service.reconcile();
      android.calls.clear();

      await preferences.setNotificationsEnabled(
        commandId: data.ids.newId(),
        enabled: false,
      );
      final status = await service.reconcile();

      expect(status.state, ReminderState.off);
      expect(android.scheduled, isEmpty);
      expect(
        android.calls.map((c) => c.method),
        contains('cancelAllPendingNotifications'),
      );
      expect(android.calls.map((c) => c.method), isNot(contains('cancelAll')));
    },
  );

  test('a refused permission schedules nothing and says so', () async {
    android.notificationsEnabled = false;
    await switchOn();
    final status = await service.reconcile();
    expect(status.state, ReminderState.blocked);
    expect(android.scheduled, isEmpty);
    expect(android.calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
  });

  test('allowing notifications later makes the next run schedule', () async {
    android.notificationsEnabled = false;
    await switchOn();
    await service.reconcile();
    android.notificationsEnabled = true;
    final status = await service.reconcile();
    expect(status.state, ReminderState.active);
    expect(android.scheduled, hasLength(7));
  });

  test('enabling through the service asks for the permission once', () async {
    android.notificationsEnabled = false;
    android.grantsOnRequest = true;
    await preferences.setWaterSlots(commandId: data.ids.newId(), hours: {10});
    final status = await service.enableReminders(commandId: data.ids.newId());
    expect(android.permissionRequests, 1);
    expect(status.state, ReminderState.active);
    expect(android.scheduled, hasLength(7));
  });

  test(
    'a refusing dialog leaves the app usable and the state blocked',
    () async {
      android.notificationsEnabled = false;
      android.grantsOnRequest = false;
      await preferences.setWaterSlots(commandId: data.ids.newId(), hours: {10});
      final status = await service.enableReminders(commandId: data.ids.newId());
      expect(status.state, ReminderState.blocked);
      expect(android.permissionRequests, 1);
      expect(android.scheduled, isEmpty);
    },
  );

  test('alarms the system lost are registered again', () async {
    await switchOn();
    await service.reconcile();
    final before = Set.of(android.scheduled.keys);
    android.scheduled.clear(); // e.g. the plugin's storage was cleared
    android.calls.clear();

    await service.reconcile();

    expect(android.scheduled.keys.toSet(), before, reason: 'same ids');
    expect(
      android.calls.where((c) => c.method == 'zonedSchedule'),
      hasLength(7),
    );
  });

  test('a failing native side is a typed status, not an exception', () async {
    android.failSchedule = true;
    await switchOn();
    final status = await service.reconcile();
    expect(status.state, ReminderState.schedulingError);
    expect(status.lastError, ReminderErrorCategory.platform);
    expect(status.scheduledCount, 0);

    android.failSchedule = false;
    final retry = await service.reconcile();
    expect(retry.state, ReminderState.active);
    expect(retry.scheduledCount, 7);
  });

  test(
    'a habit reminder travels with the neutral text and its detail route',
    () async {
      await preferences.setNotificationsEnabled(
        commandId: data.ids.newId(),
        enabled: true,
      );
      final now = data.clock.nowUtc();
      await data.database
          .into(data.database.habits)
          .insert(
            HabitsCompanion.insert(
              id: '00000000-0000-4000-8000-0000000000a1',
              title: 'Meine private Gewohnheit',
              startedLocalDate: LocalDate(2036, 1, 1),
              reminderLocalTime: const Value(LocalTime(18, 0)),
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
      await service.reconcile();
      expect(android.scheduled, hasLength(7));
      for (final call in android.scheduled.values) {
        expect(call['title'], 'Zeit für deine Gewohnheit');
        expect(call['payload'], '/habits/00000000-0000-4000-8000-0000000000a1');
        expect(call.toString(), isNot(contains('private')));
      }
    },
  );
}

/// A stateful stand-in for the native side of the plugin on Android.
final class _NativeAndroid {
  final List<MethodCall> calls = [];
  final Map<int, Map<Object?, Object?>> scheduled = {};

  bool notificationsEnabled = true;
  bool grantsOnRequest = true;
  bool failSchedule = false;
  bool channelCreated = false;
  int permissionRequests = 0;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'initialize':
        return true;
      case 'createNotificationChannel':
        channelCreated = true;
        return null;
      case 'areNotificationsEnabled':
        return notificationsEnabled;
      case 'requestNotificationsPermission':
        permissionRequests++;
        notificationsEnabled = grantsOnRequest;
        return grantsOnRequest;
      case 'zonedSchedule':
        if (failSchedule) {
          throw PlatformException(code: 'boom', message: 'native failure');
        }
        final arguments = call.arguments as Map<Object?, Object?>;
        scheduled[arguments['id']! as int] = arguments;
        return null;
      case 'cancel':
        final arguments = call.arguments as Map<Object?, Object?>;
        scheduled.remove(arguments['id']);
        return null;
      case 'cancelAllPendingNotifications':
        scheduled.clear();
        return null;
      case 'pendingNotificationRequests':
        return <Object?>[
          for (final entry in scheduled.entries)
            <String, Object?>{
              'id': entry.key,
              'title': entry.value['title'],
              'body': entry.value['body'],
              'payload': entry.value['payload'],
            },
        ];
      case 'getNotificationAppLaunchDetails':
        return <String, Object?>{'notificationLaunchedApp': false};
      default:
        throw MissingPluginException('no answer for ${call.method}');
    }
  }
}
