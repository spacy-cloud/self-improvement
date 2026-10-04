import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_document.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_ports.dart';
import 'package:self_improvement/core/backup/backup_providers.dart';
import 'package:self_improvement/core/backup/import_preview.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/core/backup/platform/file_selector_backup_file_picker.dart';
import 'package:self_improvement/core/backup/platform/share_plus_backup_file_gateway.dart';
import 'package:self_improvement/core/backup/snapshot_consistency_checker.dart';
import 'package:self_improvement/core/backup/testing/in_memory_backup_adapters.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';

import 'support/backup_fixtures.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late RecordingProjectionSynchronizer projection;
  late DataHarness harness;

  setUp(() async {
    projection = RecordingProjectionSynchronizer();
    harness = await DataHarness.create(projections: projection);
    addTearDown(harness.dispose);
    await populateRichDatabase(harness.database);
  });

  test(
    'the service is built from the core providers and overridable adapters',
    () async {
      final files = InMemoryBackupFileGateway();
      final canceller = RecordingNotificationCanceller();
      final listener = RecordingBackupListener();
      final container = harness.createContainer(
        overrides: [
          backupFileGatewayProvider.overrideWithValue(files),
          notificationCancellerProvider.overrideWithValue(canceller),
          backupListenerProvider.overrideWithValue(listener),
        ],
      );

      final service = container.read(backupServiceProvider);
      final backup = await service.exportBackup();
      expect(files.files, contains(backup.path));
      expect(backup.fileName, 'self-improvement-backup-2026-10-03-1000.json');

      final preparation =
          await service.prepareImport(backup.bytes) as ImportReady;
      final outcome = await service.confirmImport(preparation.prepared);
      expect(
        projection.syncs,
        hasLength(1),
        reason: 'the projection of the container',
      );
      expect(canceller.calls, 1);
      expect(listener.calls, 1);
      expect(outcome.followUpSucceeded, isTrue);
    },
  );

  test('the reset service uses the same adapters', () async {
    final files = InMemoryBackupFileGateway();
    final canceller = RecordingNotificationCanceller();
    final listener = RecordingBackupListener();
    final container = harness.createContainer(
      overrides: [
        backupFileGatewayProvider.overrideWithValue(files),
        notificationCancellerProvider.overrideWithValue(canceller),
        backupListenerProvider.overrideWithValue(listener),
      ],
    );
    final outcome = await container
        .read(resetServiceProvider)
        .resetAllData(confirmation: 'löschen');
    expect(outcome.followUpSucceeded, isTrue);
    expect(canceller.calls, 1);
    expect(listener.calls, 1);
    expect(files.deleteCalls, [true]);
    expect(
      await harness.database.select(harness.database.weightEntries).get(),
      isEmpty,
    );
  });

  test('a snapshot checker provider reaches the validation', () async {
    final container = harness.createContainer(
      overrides: [
        backupFileGatewayProvider.overrideWithValue(
          InMemoryBackupFileGateway(),
        ),
        snapshotConsistencyCheckerProvider.overrideWithValue(_RejectAll()),
      ],
    );
    final service = container.read(backupServiceProvider);
    final backup = await service.exportBackup();
    expect(backup.isRestorable, isFalse);
    expect(await service.prepareImport(backup.bytes), isA<ImportRejected>());
  });

  test('defaults: production adapters, no-op hooks, no checker', () {
    final container = harness.createContainer();
    expect(
      container.read(backupFileGatewayProvider),
      isA<SharePlusBackupFileGateway>(),
    );
    expect(
      container.read(backupFilePickerProvider),
      isA<FileSelectorBackupFilePicker>(),
    );
    expect(
      container.read(notificationCancellerProvider),
      isA<NoopNotificationCanceller>(),
    );
    expect(container.read(backupListenerProvider), isA<NoopBackupListener>());
    expect(container.read(snapshotConsistencyCheckerProvider), isNull);
  });

  test('the picker provider can be replaced by a fake', () async {
    final picker = FakeBackupFilePicker();
    final container = harness.createContainer(
      overrides: [backupFilePickerProvider.overrideWithValue(picker)],
    );
    expect(identical(container.read(backupFilePickerProvider), picker), isTrue);
    expect(
      await container.read(backupFilePickerProvider).pickBackupFile(),
      isNull,
    );
  });

  test('services are created once per container', () {
    final container = harness.createContainer(
      overrides: [
        backupFileGatewayProvider.overrideWithValue(
          InMemoryBackupFileGateway(),
        ),
      ],
    );
    expect(
      identical(
        container.read(backupServiceProvider),
        container.read(backupServiceProvider),
      ),
      isTrue,
    );
  });
}

final class _RejectAll implements SnapshotConsistencyChecker {
  @override
  List<ImportProblem> check(BackupData data) => [
    ImportProblem.record(BackupTable.dailyGoalSnapshots, 0, 'abgelehnt'),
  ];
}
