import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_service.dart';
import 'package:self_improvement/core/backup/import_preview.dart';
import 'package:self_improvement/core/backup/testing/in_memory_backup_adapters.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';

import '../database/support/migration_support.dart';
import 'support/backup_fixtures.dart';
import 'support/v1_backup_support.dart';

/// Importing the backups of v0.1.0 (schema 1, backup version 1) into the
/// current app (BS-98, D-016): nothing is lost, the new fields have their
/// defaults, XP is recomputed the way v0.1.0 had it, and the two ways of
/// upgrading (a migrated database, an imported backup) lead to the same
/// version 2 file.
///
/// The files are fixtures that the unchanged code of v0.1.0 wrote
/// (`test/fixtures/v1`).
void main() {
  setUpAll(() {
    TimeZones.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  /// The moment the scenario of `v1-database.sql` ended: the clock of the
  /// backup `v1-database-backup.json` and of the migrated database.
  const scenarioEnd = '2026-04-08T07:20:00Z';

  /// An empty app. With [realProjection] the import recomputes snapshots and
  /// XP like in the app; without it only the records of the file are written.
  Future<({DataHarness harness, BackupService service})> emptyApp({
    String nowIso = '2026-03-31T10:00:00Z',
    bool realProjection = false,
  }) async {
    final harness = await DataHarness.create(
      nowIso: nowIso,
      realProjection: realProjection,
    );
    addTearDown(harness.dispose);
    final service = BackupService(
      database: harness.database,
      clock: harness.clock,
      files: InMemoryBackupFileGateway(),
      projections: harness.projections,
    );
    return (harness: harness, service: service);
  }

  Future<ImportOutcome> importFile(BackupService service, String name) async {
    final preparation = await service.prepareImport(v1Bytes(name));
    expect(
      preparation,
      isA<ImportReady>(),
      reason: preparation is ImportRejected
          ? preparation.report.problems.take(3).join('; ')
          : null,
    );
    return service.confirmImport((preparation as ImportReady).prepared);
  }

  /// The decoded `data` object of what the app exports now.
  Future<Map<String, Object?>> exportedData(
    DataHarness harness, {
    ClockService? clock,
  }) async {
    final backup = await BackupExporter(
      database: harness.database,
      clock: clock ?? harness.clock,
    ).export();
    final root = jsonDecode(utf8.decode(backup.bytes)) as Map<String, Object?>;
    expect(root['schemaVersion'], 2);
    return root['data']! as Map<String, Object?>;
  }

  group(
    'the version 1 backups of v0.1.0 import into schema 2 (AT30, BS-98)',
    () {
      for (final name in v1BackupFiles) {
        test(
          '$name: every record is there, the new fields have defaults',
          () async {
            final app = await emptyApp();
            final v1 = v1Json(name);

            final preparation = await app.service.prepareImport(v1Bytes(name));
            expect(preparation, isA<ImportReady>());
            final preview = (preparation as ImportReady).preview;
            expect(preview.schemaVersion, 1, reason: 'the version of the FILE');
            expect(preview.counts[BackupTable.workoutDayMarks], 0);
            await app.service.confirmImport(preparation.prepared);

            // The export of what was imported is the file plus the defaults of
            // version 2 (compared as decoded JSON: only the meaning counts).
            expect(
              await exportedData(app.harness),
              expectedVersion2Data(v1['data']! as Map<String, Object?>),
            );
          },
        );
      }

      test(
        'the 90 day demo backup: every table of the database is filled',
        () async {
          final app = await emptyApp(realProjection: true);
          final outcome = await importFile(app.service, demoBackupFile);
          expect(outcome.recordCount, greaterThan(1000));
          expect(outcome.followUpSucceeded, isTrue);
          final counts = await rowCounts(app.harness.database);
          expect(counts['weight_entries'], greaterThan(50));
          expect(counts['step_days'], greaterThan(50));
          expect(counts['xp_awards'], greaterThan(100), reason: 'recomputed');
          expect(counts['workout_day_marks'], 0);
          final steps = await app.harness.database
              .select(app.harness.database.stepDays)
              .get();
          expect(steps.map((s) => s.source).toSet(), {'manual'});
          final settings = await app.harness.database
              .select(app.harness.database.appSettings)
              .getSingle();
          expect(settings.healthStepsSyncEnabled, isFalse);
          expect(settings.healthStepsLastSyncAtUtc, isNull);
          final tasks = await app.harness.database
              .select(app.harness.database.tasks)
              .get();
          expect(tasks, isNotEmpty);
          expect(tasks.every((t) => t.reminderAtUtc == null), isTrue);
          expect(tasks.every((t) => t.reminderLocalDate == null), isTrue);
          expect(tasks.every((t) => t.reminderTimezoneId == null), isTrue);
        },
      );

      test(
        'the rich file keeps quotes, line breaks, milliseconds and zones',
        () async {
          final app = await emptyApp();
          await importFile(app.service, richBackupFile);
          final db = app.harness.database;
          final water = await (db.select(
            db.waterEntries,
          )..where((w) => w.id.equals(uuid(0x121)))).getSingle();
          expect(water.note, specialNote);
          final weights = await (db.select(
            db.weightEntries,
          )..orderBy([(w) => OrderingTerm.asc(w.occurredAtUtc)])).get();
          expect(weights.first.occurredAtUtc, at(2, 6, 30, 15, 250));
          expect(weights.map((w) => w.timezoneId), [
            berlin,
            'Asia/Tokyo',
            berlin,
          ]);
        },
      );

      test(
        'the fresh installation file gives an empty app with the defaults',
        () async {
          final app = await emptyApp(nowIso: '2026-10-03T08:00:00Z');
          await importFile(app.service, freshInstallBackupFile);
          final db = app.harness.database;
          final counts = await rowCounts(db);
          expect(counts['profile'], 1);
          expect(counts['app_settings'], 1);
          expect(
            {
              for (final e in counts.entries)
                if (e.value > 0) e.key,
            },
            {'profile', 'app_settings'},
          );
          final settings = await db.select(db.appSettings).getSingle();
          expect(settings.healthStepsSyncEnabled, isFalse);
          expect(settings.healthStepsLastSyncAtUtc, isNull);
        },
      );
    },
  );

  group('XP is recomputed the way v0.1.0 had it (AT30, BS-98)', () {
    test(
      'the backup of the fixture database gives the awards of the database',
      () async {
        // The awards the v0.1.0 commands wrote while the scenario ran.
        final v1 = V1FixtureDatabase(v1FixtureExecutor());
        addTearDown(v1.close);
        final v1Awards = await _awards(v1);
        expect(v1Awards, isNotEmpty);

        // The same facts, imported from the backup of that database: the
        // import recomputes every award from the facts.
        final app = await emptyApp(nowIso: scenarioEnd, realProjection: true);
        await importFile(app.service, databaseBackupFile);
        expect(await _awards(app.harness.database), v1Awards);
      },
    );

    test('the total XP of the demo backup is the sum of its awards', () async {
      final app = await emptyApp(realProjection: true);
      await importFile(app.service, demoBackupFile);
      final total = await app.harness.totalXp();
      expect(total, greaterThan(0));
      final sum = await app.harness.database
          .customSelect('SELECT SUM(points) AS s FROM xp_awards')
          .getSingle();
      expect(sum.read<int>('s'), total);
    });
  });

  group('both ways to upgrade end in the same version 2 file (BS-98)', () {
    test('a migrated v0.1.0 database and an imported v0.1.0 backup export the same bytes', () async {
      // Way 1: the database file of v0.1.0 is opened by the new code.
      final migrated = AppDatabase(v1FixtureExecutor());
      addTearDown(migrated.close);
      final clock = FakeClock.at(scenarioEnd);
      final viaDatabase = await BackupExporter(
        database: migrated,
        clock: clock,
      ).export();

      // Way 2: the backup v0.1.0 made of that database is imported.
      final app = await emptyApp(nowIso: scenarioEnd);
      await importFile(app.service, databaseBackupFile);
      final viaBackup = await BackupExporter(
        database: app.harness.database,
        clock: app.harness.clock,
      ).export();

      expect(viaBackup.bytes, viaDatabase.bytes);
      expect(viaBackup.isRestorable, isTrue);
      expect(viaDatabase.isRestorable, isTrue);
    });
  });

  group('a file that is rejected changes nothing (AT31, BS-98)', () {
    test('a version 1 file with a field of version 2 is refused', () async {
      final app = await emptyApp();
      await importFile(app.service, demoBackupFile);
      final before = await dumpDatabase(app.harness.database);

      final root = v1Json(richBackupFile);
      (root['data']! as Map<String, Object?>)['workout_day_marks'] =
          <Object?>[];
      final preparation = await app.service.prepareImport(
        Uint8List.fromList(utf8.encode(jsonEncode(root))),
      );
      expect(preparation, isA<ImportRejected>());
      expect(
        (preparation as ImportRejected).report.problems.single.displayText,
        'data: Unbekannter Abschnitt',
      );
      expect(await dumpDatabase(app.harness.database), before);
    });

    test('a file of version 3 is refused', () async {
      final app = await emptyApp();
      await importFile(app.service, demoBackupFile);
      final before = await dumpDatabase(app.harness.database);

      final root = v1Json(demoBackupFile)..['schemaVersion'] = 3;
      final preparation = await app.service.prepareImport(
        Uint8List.fromList(utf8.encode(jsonEncode(root))),
      );
      expect(preparation, isA<ImportRejected>());
      expect(
        (preparation as ImportRejected).failure.userMessage,
        contains('Schema-Version dieser Datei wird nicht unterstützt'),
      );
      expect(await dumpDatabase(app.harness.database), before);
    });
  });
}

/// All XP awards as sorted text lines.
Future<List<String>> _awards(AppDatabase db) async {
  final rows = await db.select(db.xpAwards).get();
  return rows.map((row) => row.toString()).toList()..sort();
}
