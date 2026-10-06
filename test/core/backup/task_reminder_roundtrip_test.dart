import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/backup_service.dart';
import 'package:self_improvement/core/backup/import_preview.dart';
import 'package:self_improvement/core/backup/testing/in_memory_backup_adapters.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/features/reminders/application/reminder_data_ports.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';

import '../notifications/support/reminder_harness.dart';
import 'support/backup_fixtures.dart';

/// The reminder of a task through the backup (BS-111, AT30, C09): tasks made
/// with the real commands, exported, imported into an empty app with the real
/// reminder engine behind the follow-up, and exported again. Everything that
/// belongs to the reminder comes back exactly, and the notifications are
/// planned again from what the file contains.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  final originalDebugPrint = debugPrint;
  setUp(() => debugPrint = (String? message, {int? wrapWidth}) {});
  tearDown(() => debugPrint = originalDebugPrint);

  // The source starts at 08:30 Berlin on 2026-10-03.
  late ReminderHarness source;
  late String open;
  late String none;
  late String completed;
  late String newYork;
  late String moved;
  late String deleted;
  late String expired;

  DateTime inHours(int hours) =>
      DateTime.utc(2026, 10, 3, 6, 30).add(Duration(hours: hours));

  setUp(() async {
    source = await ReminderHarness.create();
    addTearDown(source.dispose);
    await source.setWanted(true);
    open = await source.createTask(title: 'Offen', reminderAt: inHours(3));
    none = await source.createTask(title: 'Ohne Erinnerung');
    completed = await source.createTask(
      title: 'Erledigt',
      reminderAt: inHours(5),
    );
    await source.completeTask(completed);
    // A reminder set on a trip: its date and zone are those of the trip.
    source.data.clock.setTimeZone('America/New_York');
    newYork = await source.createTask(
      title: 'In New York gesetzt',
      reminderAt: inHours(8),
    );
    source.data.clock.setTimeZone('Asia/Tokyo');
    moved = await source.createTask(
      title: 'Verschoben',
      reminderAt: inHours(2),
    );
    await source.setReminder(moved, inHours(50));
    source.data.clock.setTimeZone('Europe/Berlin');
    deleted = await source.createTask(
      title: 'Gelöscht',
      reminderAt: inHours(9),
    );
    await source.deleteTask(deleted);
    expired = await source.createTask(
      title: 'Abgelaufen',
      reminderAt: inHours(1),
    );
    // Two hours later the last one has gone off (10:30 Berlin).
    source.data.clock.advance(const Duration(hours: 2));
  });

  Future<ExportedBackup> exportFrom(ReminderHarness h) =>
      BackupExporter(database: h.database, clock: h.data.clock).export();

  /// An empty app of the same minute with the real engine behind the
  /// follow-ups of an import, like the app wires them.
  Future<(ReminderHarness, BackupService)> emptyApp() async {
    final target = await ReminderHarness.create(nowIso: '2026-10-03T08:30:00Z');
    addTearDown(target.dispose);
    final service = BackupService(
      database: target.database,
      clock: target.data.clock,
      files: InMemoryBackupFileGateway(),
      projections: target.data.projections,
      notifications: ReminderNotificationCanceller(target.platform),
      listener: ReminderReplanListener(target.service),
    );
    return (target, service);
  }

  Future<ImportOutcome> importInto(
    BackupService service,
    ExportedBackup backup,
  ) async {
    final result = await service.prepareImport(
      Uint8List.fromList(backup.bytes),
    );
    return service.confirmImport((result as ImportReady).prepared);
  }

  test('every field of every task survives export and import, row by row '
      '(BS-111, AT30)', () async {
    final backup = await exportFrom(source);
    final (target, service) = await emptyApp();
    await importInto(service, backup);

    final expected = await expectedExportRows(source.database);
    final dump = await backupTablesDump(target.database);
    expect(
      expected['tasks'],
      hasLength(6),
      reason: 'the deleted one is not exported',
    );
    expect(dump['tasks'], expected['tasks']);
  });

  test('the reminder keeps its instant, its frozen date and its zone, also '
      'where it was set in another zone (BS-111, AT30, AT25)', () async {
    final backup = await exportFrom(source);
    final (target, service) = await emptyApp();
    await importInto(service, backup);

    Future<TaskReminder?> reminder(ReminderHarness h, String id) async =>
        (await h.tasks.findById(id))?.reminder;

    for (final id in [open, completed, newYork, moved, expired]) {
      final before = await reminder(source, id);
      expect(before, isNotNull, reason: id);
      expect(await reminder(target, id), before, reason: id);
    }
    expect(await reminder(target, none), isNull);
    expect(await target.tasks.findById(deleted), isNull);

    // The zone a reminder was set in stays that zone.
    expect((await reminder(target, newYork))!.timezoneId, 'America/New_York');
    expect((await reminder(target, moved))!.timezoneId, 'Asia/Tokyo');
    expect((await reminder(target, open))!.timezoneId, 'Europe/Berlin');
  });

  test('after the import the notifications are planned again from the file: '
      'open tasks with a reminder that lies ahead, nothing else '
      '(BS-111, AT28, C09)', () async {
    final backup = await exportFrom(source);
    final (target, service) = await emptyApp();
    expect(await target.preferences.notificationsWanted(), isFalse);

    final outcome = await importInto(service, backup);

    expect(outcome.followUpSucceeded, isTrue);
    // The wish of the file is restored; the permission comes from the system.
    expect(await target.preferences.notificationsWanted(), isTrue);
    final status = await target.service.readStatus();
    expect(status.state, ReminderState.active);

    final rows = await target.rows();
    expect(
      {for (final row in rows) row.semanticKey},
      {'task:$open', 'task:$newYork', 'task:$moved'},
      reason: 'not the completed, the expired, the deleted, the one without',
    );
    expect(rows.every((row) => row.kind == ReminderKind.task), isTrue);
    final alarms = {
      for (final alarm in target.platform.alarms.values)
        alarm.payload: alarm.fireAtUtc,
    };
    expect(alarms, {
      '/tasks/$open': inHours(3),
      '/tasks/$newYork': inHours(8),
      '/tasks/$moved': inHours(50),
    });
  });

  test('the reminders of the old data are gone, those of the file are the '
      'only ones (BS-111, C09)', () async {
    final backup = await exportFrom(source);
    final (target, service) = await emptyApp();
    await target.setWanted(true);
    // Ids of the old data that cannot meet those of the file.
    for (var i = 0; i < 100; i++) {
      target.data.ids.newId();
    }
    final other = await target.createTask(
      title: 'Nur im Ziel',
      reminderAt: DateTime.utc(2026, 10, 3, 20),
    );
    await target.service.reconcile();
    expect(target.platform.alarms.values.single.payload, '/tasks/$other');

    await importInto(service, backup);

    expect(
      target.platform.alarms.values.map((alarm) => alarm.payload),
      isNot(contains('/tasks/$other')),
    );
    expect(await target.tasks.findById(other), isNull);
    expect(target.platform.alarms, hasLength(3));
  });

  test('without the permission an import keeps the reminders stored and '
      'plans nothing, the status says so (BS-111, AT28)', () async {
    final backup = await exportFrom(source);
    final (target, service) = await emptyApp();
    target.platform.permission = NotificationPermission.denied;

    await importInto(service, backup);

    expect((await target.tasks.findById(open))!.reminder, isNotNull);
    expect(target.platform.alarms, isEmpty);
    expect((await target.service.readStatus()).state, ReminderState.blocked);
  });

  test(
    'export -> import -> export gives the identical file (BS-111, AT30)',
    () async {
      final first = await exportFrom(source);
      final (target, service) = await emptyApp();
      await importInto(service, first);
      final second = await exportFrom(target);
      expect(second.bytes, first.bytes);
    },
  );
}
