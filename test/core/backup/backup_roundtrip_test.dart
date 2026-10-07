import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_importer.dart';
import 'package:self_improvement/core/backup/backup_validator.dart';
import 'package:self_improvement/core/backup/database_wipe.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/test_database.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/shared/local_date.dart';

import 'support/backup_fixtures.dart';
import 'support/fact_projection.dart';

void main() {
  setUpAll(() {
    TimeZones.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late DataHarness source;

  setUp(() async {
    source = await DataHarness.create();
    addTearDown(source.dispose);
    await populateRichDatabase(source.database);
  });

  Future<ExportedBackup> exportFrom(AppDatabase db, FakeClock clock) =>
      BackupExporter(database: db, clock: clock).export();

  /// Validates [backup] like an import does and returns the typed document.
  BackupValidationResult validated(ExportedBackup backup) =>
      const BackupValidator().validateBytes(backup.bytes);

  group('every table and field survives export -> import', () {
    test('into an empty database, row by row', () async {
      final expected = await expectedExportRows(source.database);
      // The fixture really exercises all seventeen tables.
      for (final entry in expected.entries) {
        expect(entry.value, isNotEmpty, reason: entry.key);
      }
      final backup = await exportFrom(source.database, source.clock);
      final result = validated(backup);
      expect(result.report.problems, isEmpty);

      final target = createTestDatabase();
      addTearDown(target.close);
      await BackupImporter(
        database: target,
        projections: const NoopProjectionSynchronizer(),
      ).replaceAll(result.document!);

      expect(await backupTablesDump(target), expected);
    });

    test('into the same database after wiping it', () async {
      final expected = await expectedExportRows(source.database);
      final backup = await exportFrom(source.database, source.clock);
      await source.database.transaction(
        () => DatabaseWipe.deleteAllRows(source.database),
      );
      expect(
        await source.database.select(source.database.weightEntries).get(),
        isEmpty,
      );

      await BackupImporter(
        database: source.database,
        projections: const NoopProjectionSynchronizer(),
      ).replaceAll(validated(backup).document!);

      expect(await backupTablesDump(source.database), expected);
    });

    test('export -> import -> export gives the identical file', () async {
      final first = await exportFrom(source.database, source.clock);
      final target = await DataHarness.create();
      addTearDown(target.dispose);
      await BackupImporter(
        database: target.database,
        projections: const NoopProjectionSynchronizer(),
      ).replaceAll(validated(first).document!);
      final second = await exportFrom(target.database, target.clock);
      expect(second.bytes, first.bytes);
      expect(second.fileName, first.fileName);
    });

    test(
      'text with quotes, backslashes, newlines, umlauts and emoji',
      () async {
        final backup = await exportFrom(source.database, source.clock);
        final target = createTestDatabase();
        addTearDown(target.close);
        await BackupImporter(
          database: target,
          projections: const NoopProjectionSynchronizer(),
        ).replaceAll(validated(backup).document!);
        final entry = await (target.select(
          target.waterEntries,
        )..where((w) => w.id.equals(uuid(0x121)))).getSingle();
        expect(entry.note, specialNote);
      },
    );

    test('millisecond instants, UTC and zone ids are kept exactly', () async {
      final backup = await exportFrom(source.database, source.clock);
      final target = createTestDatabase();
      addTearDown(target.close);
      await BackupImporter(
        database: target,
        projections: const NoopProjectionSynchronizer(),
      ).replaceAll(validated(backup).document!);
      final weights = await (target.select(
        target.weightEntries,
      )..orderBy([(w) => OrderingTerm.asc(w.occurredAtUtc)])).get();
      expect(weights.first.occurredAtUtc, at(2, 6, 30, 15, 250));
      expect(weights.first.occurredAtUtc.isUtc, isTrue);
      expect(weights.map((w) => w.timezoneId), [berlin, 'Asia/Tokyo', berlin]);
      expect(weights.map((w) => w.localDate), [march(2), march(3), march(4)]);
      final profile = await target.select(target.profile).getSingle();
      expect(profile.createdAtUtc, at(1, 7, 15, 30, 123));
      expect(profile.updatedAtUtc, at(2, 18, 0, 0, 7));
    });

    test(
      'a running session is restored as a paused one with its time',
      () async {
        final db = source.database;
        await (db.delete(db.focusSessions)).go();
        final now = source.clock.nowUtc();
        await db
            .into(db.focusSessions)
            .insert(
              FocusSessionsCompanion.insert(
                id: uuid(0xF01),
                category: 'learning',
                plannedSeconds: 3600,
                accumulatedSeconds: const Value(600),
                segmentStartedAtUtc: Value(
                  now.subtract(const Duration(minutes: 10)),
                ),
                startedAtUtc: now.subtract(const Duration(minutes: 40)),
                timezoneId: berlin,
                status: 'running',
                createdAtUtc: now.subtract(const Duration(minutes: 40)),
                updatedAtUtc: now.subtract(const Duration(minutes: 10)),
              ),
            );
        final backup = await exportFrom(db, source.clock);

        final target = await DataHarness.create();
        addTearDown(target.dispose);
        await BackupImporter(
          database: target.database,
          projections: const NoopProjectionSynchronizer(),
        ).replaceAll(validated(backup).document!);

        final restored = await target.database
            .select(target.database.focusSessions)
            .getSingle();
        expect(
          restored.status,
          'paused',
          reason: 'it must be resumed explicitly',
        );
        expect(restored.accumulatedSeconds, 1200);
        expect(restored.segmentStartedAtUtc, isNull);
        expect(restored.plannedSeconds, 3600);

        // The source session is untouched and still running.
        final live = await db.select(db.focusSessions).getSingle();
        expect(live.status, 'running');
        expect(live.accumulatedSeconds, 600);
      },
    );
  });

  group('the fixture covers every field', () {
    test(
      'null and non-null of every nullable field, both values of every boolean',
      () async {
        final root = await richBackupJson();
        final data = root['data']! as Map<String, Object?>;
        for (final table in BackupTable.values) {
          final section = data[table.key];
          final records = table.isSingleton
              ? [section! as Map<String, Object?>]
              : (section! as List<Object?>).cast<Map<String, Object?>>();
          final columns = await source.database
              .customSelect("PRAGMA table_info('${table.key}')")
              .get();
          for (final column in columns) {
            final name = column.read<String>('name');
            if (name == 'deleted_at_utc') {
              continue;
            }
            final values = [for (final r in records) r[name]];
            final nullable = column.read<int>('notnull') == 0;
            // A paused backup never has a running segment; a singleton has one
            // record only (its null variants are covered by the empty-database
            // export test).
            final canBeBoth =
                !table.isSingleton && name != 'segment_started_at_utc';
            if (nullable && canBeBoth) {
              expect(
                values,
                contains(isNull),
                reason: '${table.key}.$name null',
              );
              expect(
                values.any((v) => v != null),
                isTrue,
                reason: '${table.key}.$name non-null',
              );
            }
            if (values.every((v) => v is bool || v == null) &&
                values.any((v) => v is bool) &&
                canBeBoth) {
              expect(values, contains(true), reason: '${table.key}.$name true');
              expect(
                values,
                contains(false),
                reason: '${table.key}.$name false',
              );
            }
            if (values.any((v) => v is List) && canBeBoth) {
              expect(
                values.where((v) => v is List && v.isEmpty),
                isNotEmpty,
                reason: '${table.key}.$name empty list',
              );
              expect(
                values.where((v) => v is List && v.isNotEmpty),
                isNotEmpty,
                reason: '${table.key}.$name filled list',
              );
            }
          }
        }
      },
    );
  });

  group('AT30: export, change, import: data and computed values are back', () {
    test('original rows and recomputed XP awards are restored', () async {
      final db = source.database;
      final projection = FactBasedProjection(db);
      // The values the app computed from the original facts.
      await projection.syncDays({march(2), march(3), march(4), march(5)});
      final originalRows = await expectedExportRows(db);
      final originalAwards = (await dumpDatabase(db))['xp_awards']!;
      final originalXp = await projection.totalXp();
      expect(originalXp, greaterThan(0));
      expect(originalAwards, isNotEmpty);

      final backup = await exportFrom(db, source.clock);

      // --- the user changes things after the backup was made -------------
      await db.delete(db.weightEntries).go();
      await db
          .into(db.weightEntries)
          .insert(
            WeightEntriesCompanion.insert(
              id: uuid(0xC01),
              weightGrams: 65000,
              occurredAtUtc: at(12, 6),
              localDate: march(12),
              timezoneId: berlin,
              gamificationEligible: true,
              createdAtUtc: at(12, 6),
              updatedAtUtc: at(12, 6),
            ),
          );
      await db
          .update(db.profile)
          .write(const ProfileCompanion(displayName: Value('Geändert')));
      await (db.update(db.habits)
            ..where((h) => h.id.equals(Ids.habitMeditation)))
          .write(const HabitsCompanion(title: Value('Umbenannt')));
      await projection.syncDays({march(2), march(3), march(4), march(12)});
      expect(await projection.totalXp(), isNot(originalXp));
      expect((await expectedExportRows(db))['weight_entries'], hasLength(1));

      // --- preview, then replace ----------------------------------------
      final result = validated(backup);
      expect(result.isValid, isTrue);
      await BackupImporter(
        database: db,
        projections: projection,
      ).replaceAll(result.document!);

      expect(await expectedExportRows(db), originalRows);
      expect((await dumpDatabase(db))['xp_awards'], originalAwards);
      expect(await projection.totalXp(), originalXp);
      expect(projection.syncs.last.toList(), [
        march(2),
        march(3),
        march(4),
      ], reason: 'XP recomputed for exactly the days with facts');
    });

    test(
      'the awards of days that only had deleted facts do not come back',
      () async {
        final db = source.database;
        final projection = FactBasedProjection(db);
        // 2026-03-05 only has soft-deleted rows.
        await projection.syncDays({march(2), march(5)});
        final backup = await exportFrom(db, source.clock);

        final target = await DataHarness.create();
        addTearDown(target.dispose);
        await BackupImporter(
          database: target.database,
          projections: FactBasedProjection(target.database),
        ).replaceAll(validated(backup).document!);

        final awards = await target.database
            .select(target.database.xpAwards)
            .get();
        expect(
          awards.map((a) => a.localDate),
          isNot(contains(LocalDate(2026, 3, 5))),
        );
      },
    );
  });
}
