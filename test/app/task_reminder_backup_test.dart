import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/backup_providers.dart';
import 'package:self_improvement/core/backup/import_preview.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';

import '../core/notifications/support/reminder_harness.dart';
import '../support/pump_app.dart';
import 'support/app_harness.dart';

/// An import into the running app plans the notifications again, from the
/// reminders in the file (BS-111, AT28, AT30, C09): the integration the app
/// itself wires (`AppBackupListener`), with the real services, the real
/// reminder engine and the real router; only the operating system is a fake.
void main() {
  testWidgets('after an import the reminders of the file are planned, those '
      'of the replaced data are gone (BS-111, AT30)', (tester) async {
    // The file: made by another app (the same minute), with the real commands.
    final source =
        await tester.runAsync(ReminderHarness.create) as ReminderHarness;
    late String inFile;
    late String completedInFile;
    final bytes = (await tester.runAsync(() async {
      await source.setWanted(true);
      inFile = await source.createTask(
        title: 'Aus der Datei',
        reminderAt: DateTime.utc(2026, 10, 3, 12),
      );
      completedInFile = await source.createTask(
        title: 'Erledigt in der Datei',
        reminderAt: DateTime.utc(2026, 10, 3, 13),
      );
      await source.completeTask(completedInFile);
      final backup = await BackupExporter(
        database: source.database,
        clock: source.data.clock,
      ).export();
      return backup.bytes;
    }))!;
    addTearDown(() => tester.runAsync(source.dispose));

    // The running app has a task with a reminder of its own.
    late String ownId;
    final app = await pumpFullApp(
      tester,
      seed: (harness) async {
        // Ids that cannot meet those of the file.
        for (var i = 0; i < 100; i++) {
          harness.ids.newId();
        }
      },
    );
    await app.runLive(
      () => app.container
          .read(reminderPreferencesRepositoryProvider)
          .setNotificationsEnabled(
            commandId: app.harness.ids.newId(),
            enabled: true,
          ),
    );
    final repository = app.container.read(taskRepositoryProvider);
    ownId = (await app.runLive(
      () => repository.create(
        commandId: app.harness.ids.newId(),
        draft: TaskDraft(
          title: 'Eigene Aufgabe',
          reminderAtUtc: app.harness.clock.nowUtc().add(
            const Duration(hours: 9),
          ),
        ),
      ),
    )).entityId!;
    await tester.pumpUntil(() => app.platform.alarms.isNotEmpty);
    expect(app.platform.alarms.values.single.payload, '/tasks/$ownId');

    // The import, as the data screen runs it.
    final service = app.container.read(backupServiceProvider);
    final prepared = await app.runLive(() => service.prepareImport(bytes));
    final outcome = await app.runLive(
      () => service.confirmImport((prepared as ImportReady).prepared),
    );
    await app.settle();

    expect(outcome.followUpSucceeded, isTrue);
    await tester.pumpUntil(
      () => app.platform.alarms.values.any(
        (alarm) => alarm.payload == '/tasks/$inFile',
      ),
      reason: 'the reminder of the file was not planned',
    );
    expect(
      {for (final alarm in app.platform.alarms.values) alarm.payload},
      {'/tasks/$inFile'},
      reason: 'neither the replaced task nor the completed one in the file',
    );
    expect(
      app.platform.alarms.values.single.fireAtUtc,
      DateTime.utc(2026, 10, 3, 12),
    );
  });
}
