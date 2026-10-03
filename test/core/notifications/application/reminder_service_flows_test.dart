import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/reminder_harness.dart';

/// The flows the settings screen drives: switching reminders on after an
/// explanation, the permission dialog, a refusal, the way out through the
/// system settings, and the status the screen shows.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  final originalDebugPrint = debugPrint;
  setUp(() => debugPrint = (String? message, {int? wrapWidth}) {});
  tearDown(() => debugPrint = originalDebugPrint);

  late ReminderHarness h;

  /// The permission is not granted yet; the dialog will grant it.
  Future<void> create({
    NotificationPermission permission = NotificationPermission.denied,
    NotificationPermission answer = NotificationPermission.granted,
  }) async {
    h = await ReminderHarness.create(permission: permission);
    h.platform.permissionAfterRequest = answer;
    await h.setWaterHours({10, 12});
  }

  tearDown(() => h.dispose());

  Future<AppSettingsRow> settings() =>
      h.database.select(h.database.appSettings).getSingle();

  String commandId() => h.data.ids.newId();

  group('switching reminders on', () {
    test('asks for the permission, stores the wish and schedules', () async {
      await create();
      final status = await h.service.enableReminders(commandId: commandId());

      expect(h.platform.requestPermissionCalls, 1);
      expect(status.state, ReminderState.active);
      expect(status.wanted, isTrue);
      expect(status.permission, NotificationPermission.granted);
      expect(status.scheduledCount, 14);
      expect((await settings()).notificationsEnabled, isTrue);
      expect(h.platform.alarms, hasLength(14));
    });

    test(
      'a refusal keeps the wish, shows blocked and schedules nothing',
      () async {
        await create(answer: NotificationPermission.denied);
        final status = await h.service.enableReminders(commandId: commandId());

        expect(status.state, ReminderState.blocked);
        expect(status.isBlocked, isTrue);
        expect(status.wanted, isTrue);
        expect(status.permission, NotificationPermission.denied);
        expect(status.scheduledCount, 0);
        expect(h.platform.scheduleCalls, isEmpty);
        expect((await settings()).notificationsEnabled, isTrue);
      },
    );

    test(
      'the app stays usable: the core data commands are unaffected',
      () async {
        await create(answer: NotificationPermission.denied);
        await h.service.enableReminders(commandId: commandId());
        // A business command still works while reminders are blocked.
        final outcome = await h.preferences.setWaterSlots(
          commandId: commandId(),
          hours: {14},
        );
        expect(outcome.replayed, isFalse);
      },
    );

    test('does not ask again when the permission is already granted', () async {
      await create(permission: NotificationPermission.granted);
      final status = await h.service.enableReminders(commandId: commandId());
      expect(h.platform.requestPermissionCalls, 0);
      expect(status.state, ReminderState.active);
    });

    test('a retry with the same command id stores the wish once', () async {
      await create();
      final id = commandId();
      final versionBefore = (await settings()).rowVersion;
      final receipts = await h.receiptCount();

      await h.service.enableReminders(commandId: id);
      await h.service.enableReminders(commandId: id);

      expect((await settings()).rowVersion, versionBefore + 1);
      // One receipt for the wish (the second call was a replay).
      expect(await h.receiptCount(), receipts + 1);
    });

    test(
      'a failure of the wish itself reaches the caller and asks nothing',
      () async {
        await create();
        await h.database.delete(h.database.appSettings).go();
        await expectLater(
          h.service.enableReminders(commandId: commandId()),
          throwsA(isA<AppFailure>()),
        );
        expect(h.platform.requestPermissionCalls, 0);
        expect(h.platform.scheduleCalls, isEmpty);
      },
    );

    test('reconcile alone never shows the permission dialog', () async {
      await create();
      await h.setWanted(true);
      await h.service.reconcile();
      await h.service.reconcile();
      expect(h.platform.requestPermissionCalls, 0);
    });
  });

  group('permission changes in the system settings', () {
    test('granting it later makes the next run schedule everything', () async {
      await create(answer: NotificationPermission.denied);
      await h.service.enableReminders(commandId: commandId());
      expect(await h.rows(), isEmpty);

      // The user opened the system settings and allowed notifications.
      h.platform.permission = NotificationPermission.granted;
      final status = await h.service.reconcile();

      expect(status.state, ReminderState.active);
      expect(status.scheduledCount, 14);
      expect(h.platform.requestPermissionCalls, 1, reason: 'no second dialog');
    });

    test('revoking it later cancels everything', () async {
      await create(permission: NotificationPermission.granted);
      await h.service.enableReminders(commandId: commandId());
      expect(h.platform.alarms, hasLength(14));

      h.platform.permission = NotificationPermission.denied;
      final status = await h.service.reconcile();

      expect(status.state, ReminderState.blocked);
      expect(h.platform.alarms, isEmpty);
      expect(await h.rows(), isEmpty);
      expect(
        (await settings()).notificationsEnabled,
        isTrue,
        reason: 'the wish stays',
      );
    });

    test('requestPermission shows the dialog and plans right away', () async {
      await create();
      await h.setWanted(true);
      final result = await h.service.requestPermission();
      expect(result, NotificationPermission.granted);
      expect(await h.rows(), hasLength(14));
    });

    test('requestPermission with a refusal reports it', () async {
      await create(answer: NotificationPermission.denied);
      await h.setWanted(true);
      final result = await h.service.requestPermission();
      expect(result, NotificationPermission.denied);
      expect(await h.rows(), isEmpty);
    });

    test('a failing dialog is unavailable, not an exception', () async {
      await create();
      h.platform.requestFailure = StateError('no activity');
      expect(
        await h.service.requestPermission(),
        NotificationPermission.unavailable,
      );
    });

    test('permissionStatus never throws', () async {
      await create(permission: NotificationPermission.granted);
      expect(
        await h.service.permissionStatus(),
        NotificationPermission.granted,
      );
      h.platform.permissionFailure = StateError('x');
      expect(
        await h.service.permissionStatus(),
        NotificationPermission.unavailable,
      );
    });

    test(
      'the system settings can be opened, a failure is just false',
      () async {
        await create();
        expect(await h.service.openSystemSettings(), isTrue);
        h.platform.settingsCanOpen = false;
        expect(await h.service.openSystemSettings(), isFalse);
        expect(h.platform.openSettingsCalls, 2);
      },
    );
  });

  group('switching reminders off', () {
    test('stores the wish and cancels everything', () async {
      await create(permission: NotificationPermission.granted);
      await h.service.enableReminders(commandId: commandId());
      final status = await h.service.disableReminders(commandId: commandId());

      expect(status.state, ReminderState.off);
      expect(status.scheduledCount, 0);
      expect(h.platform.alarms, isEmpty);
      expect(await h.rows(), isEmpty);
      expect((await settings()).notificationsEnabled, isFalse);
    });

    test('a retry with the same command id changes nothing twice', () async {
      await create(permission: NotificationPermission.granted);
      await h.service.enableReminders(commandId: commandId());
      final id = commandId();
      await h.service.disableReminders(commandId: id);
      final version = (await settings()).rowVersion;
      await h.service.disableReminders(commandId: id);
      expect((await settings()).rowVersion, version);
    });

    test('switching on again after off schedules afresh', () async {
      await create(permission: NotificationPermission.granted);
      await h.service.enableReminders(commandId: commandId());
      await h.service.disableReminders(commandId: commandId());
      final status = await h.service.enableReminders(commandId: commandId());
      expect(status.scheduledCount, 14);
    });
  });

  group('status', () {
    test(
      'before any run: the wish, the permission and the projection',
      () async {
        await create(permission: NotificationPermission.granted);
        final status = await h.service.readStatus();
        expect(status.wanted, isFalse);
        expect(status.state, ReminderState.off);
        expect(status.permission, NotificationPermission.granted);
        expect(status.scheduledCount, 0);
        expect(status.lastError, isNull);
        expect(
          h.platform.scheduleCalls,
          isEmpty,
          reason: 'reading schedules nothing',
        );
      },
    );

    test('reads the permission as the device reports it now', () async {
      await create(permission: NotificationPermission.granted);
      await h.service.enableReminders(commandId: commandId());
      h.platform.permission = NotificationPermission.denied;
      // No reconcile yet: the screen still sees the truth of the device.
      final status = await h.service.readStatus();
      expect(status.permission, NotificationPermission.denied);
      expect(status.state, ReminderState.blocked);
      expect(status.scheduledCount, 14, reason: 'until the next run cancels');
    });

    test('keeps the outcome of the last run', () async {
      await create(permission: NotificationPermission.granted);
      await h.setWanted(true);
      h.platform.scheduleFailure = const ReminderPlatformException(
        PlatformFailureKind.failed,
      );
      await h.service.reconcile();
      final status = await h.service.readStatus();
      expect(status.lastError, ReminderErrorCategory.platform);
      expect(status.failedCount, 14);
    });

    test('knows the next planned time', () async {
      await create(permission: NotificationPermission.granted);
      final status = await h.service.enableReminders(commandId: commandId());
      expect(status.nextFireAtUtc, DateTime.utc(2026, 10, 3, 8));
      expect(
        (await h.service.readStatus()).nextFireAtUtc,
        status.nextFireAtUtc,
      );
    });

    test('watchStatus emits the current status, then every change', () async {
      await create(permission: NotificationPermission.granted);
      final emissions = <ReminderStatus>[];
      final subscription = h.service.watchStatus().listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(emissions, hasLength(1));
      expect(emissions.single.state, ReminderState.off);

      await h.service.enableReminders(commandId: commandId());
      await pumpEventQueue();
      expect(emissions.last.state, ReminderState.active);
      expect(emissions.last.scheduledCount, 14);

      await h.service.disableReminders(commandId: commandId());
      await pumpEventQueue();
      expect(emissions.last.state, ReminderState.off);
    });

    test('watchStatus does not repeat an unchanged status', () async {
      await create(permission: NotificationPermission.granted);
      await h.service.enableReminders(commandId: commandId());
      final emissions = <ReminderStatus>[];
      final subscription = h.service.watchStatus().listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      final count = emissions.length;

      await h.service.reconcile();
      await h.service.reconcile();
      await pumpEventQueue();
      expect(emissions, hasLength(count));
    });

    test('a second listener gets the current status too', () async {
      await create(permission: NotificationPermission.granted);
      await h.service.enableReminders(commandId: commandId());
      final first = <ReminderStatus>[];
      final second = <ReminderStatus>[];
      final a = h.service.watchStatus().listen(first.add);
      final b = h.service.watchStatus().listen(second.add);
      addTearDown(a.cancel);
      addTearDown(b.cancel);
      await pumpEventQueue();
      expect(first.last.state, ReminderState.active);
      expect(second.last.state, ReminderState.active);
    });

    test('reminders in the limit show the cut in the status', () async {
      await create(permission: NotificationPermission.granted);
      for (var n = 0; n < 12; n++) {
        await h.addHabit(time: const LocalTime(9, 0));
      }
      final status = await h.service.enableReminders(commandId: commandId());
      expect(status.planLimitReached, isTrue);
      expect(status.scheduledCount, 40);
    });
  });
}
