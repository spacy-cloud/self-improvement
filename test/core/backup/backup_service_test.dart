import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_document.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_service.dart';
import 'package:self_improvement/core/backup/import_preview.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/core/backup/platform/backup_file_gateway.dart';
import 'package:self_improvement/core/backup/snapshot_consistency_checker.dart';
import 'package:self_improvement/core/backup/testing/in_memory_backup_adapters.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/core/time/clock_service.dart';

import 'support/backup_fixtures.dart';
import 'support/fact_projection.dart';

void main() {
  setUpAll(() {
    TimeZones.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late DataHarness harness;
  late InMemoryBackupFileGateway files;
  late RecordingNotificationCanceller canceller;
  late RecordingBackupListener listener;
  late RecordingProjectionSynchronizer projection;
  late BackupService service;
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;

  setUp(() async {
    projection = RecordingProjectionSynchronizer();
    harness = await DataHarness.create(projections: projection);
    addTearDown(harness.dispose);
    await populateRichDatabase(harness.database);
    files = InMemoryBackupFileGateway();
    canceller = RecordingNotificationCanceller();
    listener = RecordingBackupListener();
    service = BackupService(
      database: harness.database,
      clock: harness.clock,
      files: files,
      projections: projection,
      notifications: canceller,
      listener: listener,
    );
    logs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = originalDebugPrint);
  });

  /// The bytes of a valid backup made from the live database.
  Future<Uint8List> validBackupBytes() async =>
      (await service.exportBackup()).bytes;

  Map<String, Object?> decoded(Uint8List bytes) =>
      jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;

  group('export and share', () {
    test(
      'exportBackup writes a temporary file with the documented name',
      () async {
        final backup = await service.exportBackup();
        expect(backup.fileName, 'self-improvement-backup-2026-10-03-1000.json');
        expect(backup.path, '/cache/backup_exports/${backup.fileName}');
        expect(files.files[backup.path], backup.bytes);
        expect(backup.isRestorable, isTrue);
        expect(backup.exportedAtUtc, DateTime.utc(2026, 10, 3, 8));
        expect(backup.recordCount, greaterThan(40));
        expect(decoded(backup.bytes)['format'], 'levelup_life_backup');
      },
    );

    test('exporting changes no data and shares nothing yet', () async {
      final before = await dumpDatabase(harness.database);
      await service.exportBackup();
      expect(await dumpDatabase(harness.database), before);
      expect(files.sharedPaths, isEmpty);
      expect(canceller.calls, 0);
      expect(listener.calls, 0);
    });

    test(
      'sharing opens the share sheet for the temporary file, then deletes it',
      () async {
        final backup = await service.exportBackup();
        final status = await service.shareBackup(backup);

        expect(status, BackupShareStatus.shared);
        expect(files.sharedPaths, [backup.path]);
        expect(files.fileExistedWhileSharing, [true]);
        expect(files.files, isEmpty, reason: 'cleaned up after sharing');
        // Not the platform copies: the receiving app may still read them.
        expect(files.deleteCalls, [false]);
      },
    );

    test(
      'a dismissed share sheet is reported and changes no business data',
      () async {
        final before = await dumpDatabase(harness.database);
        files.shareStatus = BackupShareStatus.dismissed;
        final backup = await service.exportBackup();
        expect(await service.shareBackup(backup), BackupShareStatus.dismissed);
        expect(files.files, isEmpty);
        expect(await dumpDatabase(harness.database), before);
      },
    );

    test('an unknown share result is passed on', () async {
      files.shareStatus = BackupShareStatus.unknown;
      final backup = await service.exportBackup();
      expect(await service.shareBackup(backup), BackupShareStatus.unknown);
    });

    test(
      'a failing share is a StorageFailure and the file is still deleted',
      () async {
        files.shareFailure = StateError('no activity');
        final backup = await service.exportBackup();
        await expectLater(
          service.shareBackup(backup),
          throwsA(isA<StorageFailure>()),
        );
        expect(files.files, isEmpty);
      },
    );

    test('a failing cleanup after sharing does not hide the result', () async {
      final backup = await service.exportBackup();
      files.deleteFailure = StateError('disk');
      expect(await service.shareBackup(backup), BackupShareStatus.shared);
    });

    test('sharing a backup without a file is a StorageFailure', () async {
      final backup = (await service.exportBackup());
      final detached = ExportedBackup(
        fileName: backup.fileName,
        bytes: backup.bytes,
        exportedAtUtc: backup.exportedAtUtc,
        counts: backup.counts,
        importCheck: backup.importCheck,
      );
      await expectLater(
        service.shareBackup(detached),
        throwsA(isA<StorageFailure>()),
      );
      expect(files.sharedPaths, isEmpty);
    });

    test(
      'a failing file write is a StorageFailure and leaves the data alone',
      () async {
        files.writeFailure = StateError('disk full');
        final before = await dumpDatabase(harness.database);
        await expectLater(
          service.exportBackup(),
          throwsA(
            isA<StorageFailure>().having(
              (f) => f.causeType,
              'cause',
              'StateError',
            ),
          ),
        );
        expect(files.files, isEmpty);
        expect(await dumpDatabase(harness.database), before);
      },
    );

    test('an unreadable database is a StorageFailure', () async {
      await harness.database.delete(harness.database.appSettings).go();
      await expectLater(service.exportBackup(), throwsA(isA<StorageFailure>()));
      expect(files.files, isEmpty);
    });

    test(
      'cleaning up at start removes leftovers including platform copies',
      () async {
        files.files['/cache/backup_exports/old.json'] = Uint8List(3);
        expect(await service.cleanUpTemporaryExports(), isTrue);
        expect(files.files, isEmpty);
        expect(files.deleteCalls, [true]);
      },
    );

    test('a failing start-up cleanup never throws', () async {
      files.deleteFailure = StateError('disk');
      expect(await service.cleanUpTemporaryExports(), isFalse);
    });
  });

  group('prepareImport: preview or problems, never a change', () {
    test(
      'a valid file yields a preview with name, counts and origin',
      () async {
        final bytes = await validBackupBytes();
        final preparation = await service.prepareImport(bytes);

        expect(preparation, isA<ImportReady>());
        final preview = (preparation as ImportReady).preview;
        expect(preview.profileName, 'Mia Muster');
        expect(preview.hasProfileName, isTrue);
        expect(preview.exportedAtUtc, DateTime.utc(2026, 10, 3, 8));
        expect(preview.appVersion, AppConfig.appVersion);
        expect(preview.counts[BackupTable.weightEntries], 3);
        expect(preview.counts[BackupTable.habits], 2);
        expect(preview.counts[BackupTable.profile], 1);
        expect(preview.counts.keys, BackupTable.values);
        expect(
          preview.totalRecords,
          preparation.prepared.document.data.recordCount,
        );
        expect(preview.entryCount, preview.totalRecords - 2);
        expect(
          () => preview.counts[BackupTable.tasks] = 99,
          throwsUnsupportedError,
        );
      },
    );

    test(
      'without a name in the file the default profile name is shown',
      () async {
        final root = decoded(await validBackupBytes());
        ((root['data']! as Map<String, Object?>)['profile']!
                as Map<String, Object?>)['display_name'] =
            null;
        final preparation = await service.prepareImport(
          Uint8List.fromList(utf8.encode(jsonEncode(root))),
        );
        final preview = (preparation as ImportReady).preview;
        expect(preview.profileName, 'Mein Profil');
        expect(preview.hasProfileName, isFalse);
      },
    );

    test('preparing runs no projection, no cancel, no listener', () async {
      await service.prepareImport(await validBackupBytes());
      expect(projection.syncs, isEmpty);
      expect(canceller.calls, 0);
      expect(listener.calls, 0);
    });

    test(
      'a rejected file carries the report and an unsupported_backup failure',
      () async {
        final root = decoded(await validBackupBytes())..['schemaVersion'] = 3;
        final preparation = await service.prepareImport(
          Uint8List.fromList(utf8.encode(jsonEncode(root))),
        );
        expect(preparation, isA<ImportRejected>());
        final rejected = preparation as ImportRejected;
        expect(rejected.report.problems.single.field, 'schemaVersion');
        expect(rejected.failure, isA<UnsupportedBackupFailure>());
        expect(rejected.failure.code, 'unsupported_backup');
        expect(rejected.failure.userMessage, rejected.report.summary);
        expect(
          rejected.failure.userMessage,
          contains('Deine vorhandenen Daten wurden nicht verändert'),
        );
      },
    );

    group('AT31: nothing changes for', () {
      late Map<String, List<String>> before;
      setUp(() async => before = await dumpDatabase(harness.database));

      Future<void> expectRejected(Uint8List bytes, {String? location}) async {
        final preparation = await service.prepareImport(bytes);
        expect(preparation, isA<ImportRejected>());
        if (location != null) {
          expect(
            (preparation as ImportRejected).report.problems.first.location,
            location,
          );
        }
        expect(await dumpDatabase(harness.database), before);
        expect(projection.syncs, isEmpty);
        expect(canceller.calls, 0);
        expect(listener.calls, 0);
      }

      Future<Map<String, Object?>> rootJson() async =>
          decoded(await validBackupBytes());

      Uint8List encode(Map<String, Object?> root) =>
          Uint8List.fromList(utf8.encode(jsonEncode(root)));

      test('a wrong schema version', () async {
        final root = await rootJson()
          ..['schemaVersion'] = 99;
        await expectRejected(encode(root), location: 'root');
      });

      test('duplicate ids', () async {
        final root = await rootJson();
        final weights =
            (root['data']! as Map<String, Object?>)['weight_entries']!
                as List<Object?>;
        (weights[1]! as Map<String, Object?>)['id'] =
            (weights[0]! as Map<String, Object?>)['id'];
        await expectRejected(encode(root), location: 'weight_entries[1]');
      });

      test('a missing foreign key target', () async {
        final root = await rootJson();
        ((root['data']! as Map<String, Object?>)['habit_checks']!
                as List<Object?>)
            .map((c) => c! as Map<String, Object?>)
            .first['habit_id'] = uuid(
          0xFFFF,
        );
        await expectRejected(encode(root), location: 'habit_checks[0]');
      });

      test('a file larger than 10 MiB', () async {
        final json = await validBackupBytes();
        final bytes = Uint8List(BackupFormat.maxFileBytes + 1)
          ..fillRange(0, BackupFormat.maxFileBytes + 1, 0x20)
          ..setRange(0, json.length, json);
        await expectRejected(bytes, location: 'file');
      });

      test('more than 50,000 records', () async {
        final root = await rootJson();
        final data = root['data']! as Map<String, Object?>;
        final rules = data['reminder_rules']! as List<Object?>;
        final template = Map<String, Object?>.of(
          rules.first! as Map<String, Object?>,
        );
        final total =
            2 +
            data.values.whereType<List<Object?>>().fold<int>(
              0,
              (sum, list) => sum + list.length,
            );
        final missing = BackupFormat.maxRecords + 1 - total;
        for (var i = 0; i < missing; i++) {
          rules.add(
            Map<String, Object?>.of(template)..['id'] = uuid(0x500000 + i),
          );
        }
        final bytes = encode(root);
        expect(
          bytes.length,
          lessThan(BackupFormat.maxFileBytes),
          reason: 'the record limit must be what rejects it, not the size',
        );
        await expectRejected(bytes, location: 'data');
      });

      test('an empty file, garbage and JSON that is not a backup', () async {
        await expectRejected(Uint8List(0), location: 'file');
        await expectRejected(
          Uint8List.fromList([0, 1, 2, 3]),
          location: 'file',
        );
        await expectRejected(
          Uint8List.fromList(utf8.encode('{"hello":"world"}')),
          location: 'root',
        );
      });

      test(
        'a wrong format marker, extra fields, wrong types, bad dates',
        () async {
          var root = await rootJson()
            ..['format'] = 'x';
          await expectRejected(encode(root), location: 'root');
          root = await rootJson();
          ((root['data']! as Map<String, Object?>)['habits']! as List<Object?>)
                  .map((h) => h! as Map<String, Object?>)
                  .first['color'] =
              'red';
          await expectRejected(encode(root), location: 'habits[0]');
          root = await rootJson();
          ((root['data']! as Map<String, Object?>)['water_entries']!
                      as List<Object?>)
                  .map((h) => h! as Map<String, Object?>)
                  .first['amount_ml'] =
              '250';
          await expectRejected(encode(root), location: 'water_entries[0]');
          root = await rootJson();
          ((root['data']! as Map<String, Object?>)['step_days']!
                      as List<Object?>)
                  .map((h) => h! as Map<String, Object?>)
                  .first['local_date'] =
              '2026-02-30';
          await expectRejected(encode(root), location: 'step_days[0]');
        },
      );
    });
  });

  group('confirmImport: replace everything', () {
    test(
      'replaces all data, recomputes XP days, then cancels and notifies',
      () async {
        final expected = await expectedExportRows(harness.database);
        final bytes = await validBackupBytes();
        // The user changes things after the backup: other data replaces it.
        await populateOtherData(harness.database);
        expect(await expectedExportRows(harness.database), isNot(expected));

        final events = <String>[];
        var weightsAtCancel = -1;
        final observed = BackupService(
          database: harness.database,
          clock: harness.clock,
          files: files,
          projections: projection,
          notifications: RecordingNotificationCanceller(
            onCancel: () async {
              events.add('cancel');
              weightsAtCancel =
                  (await harness.database
                          .select(harness.database.weightEntries)
                          .get())
                      .length;
            },
          ),
          listener: RecordingBackupListener(
            onReplaced: () async => events.add('listener'),
          ),
        );

        final preparation = await observed.prepareImport(bytes) as ImportReady;
        final outcome = await observed.confirmImport(preparation.prepared);

        expect(await backupTablesDump(harness.database), expected);
        expect(outcome.recordCount, preparation.preview.totalRecords);
        expect(outcome.recomputedDays, 3);
        expect(projection.syncs.single.toList(), [
          march(2),
          march(3),
          march(4),
        ]);
        expect(events, [
          'cancel',
          'listener',
        ], reason: 'cancel first, then re-plan');
        expect(
          weightsAtCancel,
          3,
          reason: 'the commit happened before cancelling',
        );
        expect(outcome.notificationsCancelled, isTrue);
        expect(outcome.listenerNotified, isTrue);
        expect(outcome.followUpSucceeded, isTrue);
        expect(
          await harness.database
              .select(harness.database.scheduledNotifications)
              .get(),
          isEmpty,
        );
      },
    );

    test(
      'a failing projection leaves everything as it was and tells nobody',
      () async {
        final bytes = await validBackupBytes();
        await populateOtherData(harness.database);
        final before = await dumpDatabase(harness.database);
        final preparation = await service.prepareImport(bytes) as ImportReady;
        projection.failure = StateError('simulated projection failure');

        await expectLater(
          service.confirmImport(preparation.prepared),
          throwsA(
            isA<StorageFailure>().having(
              (f) => f.causeType,
              'cause',
              'StateError',
            ),
          ),
        );
        expect(await dumpDatabase(harness.database), before);
        expect(
          canceller.calls,
          0,
          reason: 'nothing changed, nothing to cancel',
        );
        expect(listener.calls, 0);
      },
    );

    test('an AppFailure of the projection is passed on unchanged', () async {
      final preparation =
          await service.prepareImport(await validBackupBytes()) as ImportReady;
      projection.failure = const ConflictFailure(ConflictKind.invalidState);
      await expectLater(
        service.confirmImport(preparation.prepared),
        throwsA(isA<ConflictFailure>()),
      );
    });

    test('a failing cancel or listener does not undo the import', () async {
      final bytes = await validBackupBytes();
      await populateOtherData(harness.database);
      canceller.failure = StateError('plugin');
      listener.failure = StateError('ui');
      final preparation = await service.prepareImport(bytes) as ImportReady;
      final outcome = await service.confirmImport(preparation.prepared);

      expect(outcome.notificationsCancelled, isFalse);
      expect(outcome.listenerNotified, isFalse);
      expect(outcome.followUpSucceeded, isFalse);
      expect(
        await harness.database.select(harness.database.weightEntries).get(),
        hasLength(3),
      );
      expect(
        listener.calls,
        1,
        reason: 'the listener still ran after a failed cancel',
      );
    });

    test('confirming the same preparation twice is harmless', () async {
      final preparation =
          await service.prepareImport(await validBackupBytes()) as ImportReady;
      await service.confirmImport(preparation.prepared);
      final first = await dumpDatabase(harness.database);
      await service.confirmImport(preparation.prepared);
      expect(await dumpDatabase(harness.database), first);
    });

    test('a rejected or failed import never resets the data', () async {
      await service.prepareImport(Uint8List.fromList(utf8.encode('garbage')));
      projection.failure = StateError('x');
      final preparation =
          await service.prepareImport(await validBackupBytes()) as ImportReady;
      await expectLater(
        service.confirmImport(preparation.prepared),
        throwsA(isA<StorageFailure>()),
      );
      final profile = await harness.database
          .select(harness.database.profile)
          .getSingle();
      expect(profile.displayName, 'Mia Muster');
      expect(profile.onboardingCompleted, isTrue);
    });
  });

  group('AT30 at service level', () {
    test(
      'export, change, prepare, confirm: data and computed values are back',
      () async {
        final db = harness.database;
        final computing = FactBasedProjection(db);
        final svc = BackupService(
          database: db,
          clock: harness.clock,
          files: files,
          projections: computing,
          notifications: canceller,
          listener: listener,
        );
        await computing.syncDays({march(2), march(3), march(4)});
        final originalRows = await expectedExportRows(db);
        final originalAwards = (await dumpDatabase(db))['xp_awards']!;

        final backup = await svc.exportBackup();

        await db.delete(db.waterEntries).go();
        await db.delete(db.weightEntries).go();
        await db
            .update(db.profile)
            .write(const ProfileCompanion(displayName: Value('Geändert')));
        await computing.syncDays({march(2), march(3), march(4)});
        expect((await dumpDatabase(db))['xp_awards'], isNot(originalAwards));

        final preparation =
            await svc.prepareImport(backup.bytes) as ImportReady;
        expect(preparation.preview.profileName, 'Mia Muster');
        await svc.confirmImport(preparation.prepared);

        expect(await expectedExportRows(db), originalRows);
        expect((await dumpDatabase(db))['xp_awards'], originalAwards);
      },
    );
  });

  group('privacy', () {
    test('logs contain error types only, never values from the data', () async {
      // An error whose message carries personal data.
      projection.failure = StateError('Mia Muster 71,5 kg Haferbrei');
      files.deleteFailure = StateError('Mia Muster');
      canceller.failure = StateError('Mia Muster');
      listener.failure = StateError('Mia Muster');
      final preparation =
          await service.prepareImport(await validBackupBytes()) as ImportReady;
      await expectLater(
        service.confirmImport(preparation.prepared),
        throwsA(isA<StorageFailure>()),
      );
      projection.failure = null;
      await service.confirmImport(preparation.prepared);
      await service.cleanUpTemporaryExports();
      final export = await service.exportBackup();
      await service.shareBackup(export);

      expect(logs, isNotEmpty);
      final all = logs.join('\n');
      expect(all, contains('StateError'));
      for (final secret in ['Mia', 'Muster', '71,5', 'Haferbrei', 'Steuer']) {
        expect(all, isNot(contains(secret)));
      }
    });

    test('failures carry no personal data', () async {
      projection.failure = StateError('Mia Muster');
      final preparation =
          await service.prepareImport(await validBackupBytes()) as ImportReady;
      try {
        await service.confirmImport(preparation.prepared);
        fail('expected a StorageFailure');
      } on StorageFailure catch (failure) {
        expect(failure.toString(), 'StorageFailure(storage)');
        expect(failure.userMessage, isNot(contains('Mia')));
        expect(failure.causeType, 'StateError');
      }
    });

    test('a rejection summary never contains values of the file', () async {
      final root = decoded(await validBackupBytes());
      final data = root['data']! as Map<String, Object?>;
      (data['profile']! as Map<String, Object?>)['display_name'] =
          'Mia Muster ${'x' * 60}';
      final preparation = await service.prepareImport(
        Uint8List.fromList(utf8.encode(jsonEncode(root))),
      );
      final summary = (preparation as ImportRejected).report.summary;
      expect(summary, isNot(contains('Mia')));
      expect(summary, isNot(contains('Muster')));
    });
  });

  test(
    'a snapshot checker plugged into the service rejects the file',
    () async {
      final checked = BackupService(
        database: harness.database,
        clock: harness.clock,
        files: files,
        projections: projection,
        snapshotChecker: _AlwaysObjects(),
      );
      final preparation = await checked.prepareImport(await validBackupBytes());
      expect(preparation, isA<ImportRejected>());
      expect(
        (preparation as ImportRejected).report.problems.single.displayText,
        'daily_goal_snapshots[0]: Snapshot widerspricht der Historie',
      );
      // The export of the same service is checked with the same rules.
      final backup = await checked.exportBackup();
      expect(backup.isRestorable, isFalse);
    },
  );
}

final class _AlwaysObjects implements SnapshotConsistencyChecker {
  @override
  List<ImportProblem> check(BackupData data) => [
    ImportProblem.record(
      BackupTable.dailyGoalSnapshots,
      0,
      'Snapshot widerspricht der Historie',
    ),
  ];
}
