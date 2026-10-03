import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_service.dart';
import 'package:self_improvement/core/backup/import_preview.dart';
import 'package:self_improvement/core/backup/reset_service.dart';
import 'package:self_improvement/core/backup/testing/in_memory_backup_adapters.dart';
import 'package:self_improvement/core/notifications/domain/notification_routes.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/features/reminders/application/reminder_data_ports.dart';

import '../../core/backup/support/backup_fixtures.dart';
import '../../core/notifications/support/reminder_harness.dart';

/// The reminder engine behind import and reset: the real canceller and
/// listener the app plugs into the backup engine (C08, C09, AT28).
void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  PlatformScheduleRequest request(int id) => PlatformScheduleRequest(
    id: id,
    fireAtUtc: DateTime.utc(2026, 10, 4, 10),
    timeZoneId: 'Europe/Berlin',
    title: 'Zeit für ein Glas Wasser',
    payload: NotificationRoutes.water,
  );

  group('ReminderNotificationCanceller', () {
    test('cancels everything the system holds', () async {
      final h = await ReminderHarness.create();
      addTearDown(h.dispose);
      await h.platform.schedule(request(1));
      await h.platform.schedule(request(2));
      expect(h.platform.alarms, hasLength(2));

      await ReminderNotificationCanceller(h.platform).cancelAllNotifications();

      expect(h.platform.alarms, isEmpty);
      expect(await h.platform.pendingIds(), isEmpty);
      expect(h.platform.cancelAllPendingCalls, 1);
    });

    test('is idempotent', () async {
      final h = await ReminderHarness.create();
      addTearDown(h.dispose);
      final canceller = ReminderNotificationCanceller(h.platform);

      await canceller.cancelAllNotifications();
      await canceller.cancelAllNotifications();

      expect(h.platform.alarms, isEmpty);
    });

    test('a failing system is reported so the engine can say so', () async {
      final h = await ReminderHarness.create();
      addTearDown(h.dispose);
      h.platform.cancelFailure = StateError('no alarm service');

      expect(
        ReminderNotificationCanceller(h.platform).cancelAllNotifications(),
        throwsStateError,
      );
    });
  });

  group('ReminderReplanListener', () {
    test('plans from the stored wish and rules', () async {
      final h = await ReminderHarness.create();
      addTearDown(h.dispose);
      await h.setWanted(true);
      await h.setWaterHours({12, 14});
      expect(h.platform.alarms, isEmpty, reason: 'nothing planned yet');

      await ReminderReplanListener(h.service).onDataReplaced();

      expect(h.platform.alarms, isNotEmpty);
    });

    test('plans nothing when reminders are not wanted', () async {
      final h = await ReminderHarness.create();
      addTearDown(h.dispose);
      await h.setWaterHours({12});

      await ReminderReplanListener(h.service).onDataReplaced();

      expect(h.platform.alarms, isEmpty);
    });
  });

  group('CompositeBackupListener', () {
    test('runs every listener in order', () async {
      final order = <int>[];
      final composite = CompositeBackupListener([
        RecordingBackupListener(onReplaced: () async => order.add(1)),
        RecordingBackupListener(onReplaced: () async => order.add(2)),
        RecordingBackupListener(onReplaced: () async => order.add(3)),
      ]);

      await composite.onDataReplaced();

      expect(order, [1, 2, 3]);
    });

    test(
      'a failing listener does not stop the others and is reported',
      () async {
        final calls = <String>[];
        final failing = RecordingBackupListener(
          onReplaced: () async => calls.add('failing'),
        )..failure = StateError('first');
        final composite = CompositeBackupListener([
          RecordingBackupListener(onReplaced: () async => calls.add('a')),
          failing,
          RecordingBackupListener(onReplaced: () async => calls.add('b')),
        ]);

        await expectLater(composite.onDataReplaced(), throwsStateError);

        expect(calls, ['a', 'failing', 'b']);
      },
    );

    test('the first error is the one thrown', () async {
      final first = RecordingBackupListener()..failure = StateError('first');
      final second = RecordingBackupListener()
        ..failure = ArgumentError('second');
      final composite = CompositeBackupListener([first, second]);

      await expectLater(composite.onDataReplaced(), throwsStateError);
      expect(second.calls, 1);
    });

    test('an empty composite does nothing', () async {
      await const CompositeBackupListener([]).onDataReplaced();
    });
  });

  group('with the backup engine', () {
    Future<(ReminderHarness, BackupService, ResetService)> wire({
      NotificationPermission permission = NotificationPermission.granted,
    }) async {
      final h = await ReminderHarness.create(permission: permission);
      addTearDown(h.dispose);
      final canceller = ReminderNotificationCanceller(h.platform);
      final listener = CompositeBackupListener([
        ReminderReplanListener(h.service),
      ]);
      final service = BackupService(
        database: h.database,
        clock: h.data.clock,
        files: InMemoryBackupFileGateway(),
        projections: h.data.projections,
        notifications: canceller,
        listener: listener,
      );
      final reset = ResetService(
        database: h.database,
        clock: h.data.clock,
        notifications: canceller,
        listener: listener,
      );
      return (h, service, reset);
    }

    Future<PreparedImport> prepared(BackupService service) async {
      final json = await richBackupJson();
      final result = await service.prepareImport(
        Uint8List.fromList(utf8.encode(jsonEncode(json))),
      );
      return (result as ImportReady).prepared;
    }

    List<int> localHours(ReminderHarness h, String route) => [
      for (final alarm in h.platform.alarms.values)
        if (alarm.payload == route)
          h.data.clock.toLocal(alarm.fireAtUtc).time.hour,
    ];

    test('an import cancels the old alarms and plans from the new rules (C08, C09)', () async {
      final (h, service, _) = await wire();
      await h.setWanted(true);
      await h.setWaterHours({18});
      await h.service.reconcile();
      expect(localHours(h, NotificationRoutes.water), everyElement(18));
      expect(h.platform.alarms, isNotEmpty);

      final outcome = await service.confirmImport(await prepared(service));

      expect(outcome.followUpSucceeded, isTrue);
      // The file asks for reminders and holds a 10:00 water rule: the 18:00
      // alarms of the old data are gone, the new ones are planned.
      final water = localHours(h, NotificationRoutes.water);
      expect(water, isNotEmpty);
      expect(water, everyElement(10));
    });

    test('the wish of the file never grants the permission (AT28)', () async {
      final (h, service, _) = await wire(
        permission: NotificationPermission.denied,
      );

      final outcome = await service.confirmImport(await prepared(service));

      expect(outcome.followUpSucceeded, isTrue);
      expect(await h.preferences.notificationsWanted(), isTrue);
      expect(h.platform.alarms, isEmpty);
      final status = await h.service.readStatus();
      expect(status.state, ReminderState.blocked);
    });

    test('a reset removes every alarm and plans nothing (C09, Q01)', () async {
      final (h, _, reset) = await wire();
      await h.setWanted(true);
      await h.setWaterHours({12, 14});
      await h.service.reconcile();
      expect(h.platform.alarms, isNotEmpty);

      final outcome = await reset.resetAllData(confirmation: 'LÖSCHEN');

      expect(outcome.followUpSucceeded, isTrue);
      expect(h.platform.alarms, isEmpty);
      expect(await h.preferences.notificationsWanted(), isFalse);
      expect((await h.service.readStatus()).state, ReminderState.off);
    });
  });
}
