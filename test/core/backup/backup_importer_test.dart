import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_document.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_importer.dart';
import 'package:self_improvement/core/backup/backup_validator.dart';
import 'package:self_improvement/core/backup/database_wipe.dart';
import 'package:self_improvement/core/backup/dto/body_nutrition_dtos.dart';
import 'package:self_improvement/core/backup/dto/task_dtos.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/core/testing/test_database.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/local_date.dart';

import 'support/backup_fixtures.dart';
import 'support/fact_projection.dart';

void main() {
  setUpAll(() {
    TimeZones.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  /// The validated document of a rich source database.
  Future<BackupDocument> richDocument() async {
    final source = await DataHarness.create();
    addTearDown(source.dispose);
    await populateRichDatabase(source.database);
    final backup = await BackupExporter(
      database: source.database,
      clock: source.clock,
    ).export();
    return const BackupValidator().validateBytes(backup.bytes).document!;
  }

  /// A target database with unrelated data of its own.
  Future<AppDatabase> targetWithOtherData() async {
    final target = await DataHarness.create();
    addTearDown(target.dispose);
    await populateOtherData(target.database);
    return target.database;
  }

  group('replace, never merge', () {
    test('afterwards the database holds exactly the imported rows', () async {
      final document = await richDocument();
      final source = await DataHarness.create();
      addTearDown(source.dispose);
      await populateRichDatabase(source.database);
      final expected = await expectedExportRows(source.database);

      final target = await targetWithOtherData();
      final result = await BackupImporter(
        database: target,
        projections: const NoopProjectionSynchronizer(),
      ).replaceAll(document);

      expect(await backupTablesDump(target), expected);
      expect(result.recordCount, document.data.recordCount);
    });

    test('nothing of the previous data survives', () async {
      final document = await richDocument();
      final target = await targetWithOtherData();
      await BackupImporter(
        database: target,
        projections: const NoopProjectionSynchronizer(),
      ).replaceAll(document);

      expect(
        await (target.select(
          target.weightEntries,
        )..where((w) => w.id.equals(uuid(0xA01)))).get(),
        isEmpty,
      );
      expect(
        await (target.select(
          target.habits,
        )..where((h) => h.id.equals(uuid(0xA02)))).get(),
        isEmpty,
      );
      expect(await target.select(target.habitChecks).get(), hasLength(3));
      final profile = await target.select(target.profile).getSingle();
      expect(profile.displayName, 'Mia Muster');
      expect(profile.rowVersion, 7);
      final rules = await target.select(target.reminderRules).get();
      expect(rules.map((r) => r.route), isNot(contains('/old')));
    });

    test('the technical tables are wiped, not exported or restored', () async {
      final document = await richDocument();
      final target = await targetWithOtherData();
      expect(await target.select(target.xpAwards).get(), isNotEmpty);
      await BackupImporter(
        database: target,
        projections: const NoopProjectionSynchronizer(),
      ).replaceAll(document);

      expect(await target.select(target.xpAwards).get(), isEmpty);
      expect(await target.select(target.commandReceipts).get(), isEmpty);
      expect(await target.select(target.scheduledNotifications).get(), isEmpty);
    });

    test(
      'ids, timestamps and versions are restored exactly, nothing is deleted',
      () async {
        final document = await richDocument();
        final target = await DataHarness.create();
        addTearDown(target.dispose);
        await BackupImporter(
          database: target.database,
          projections: const NoopProjectionSynchronizer(),
        ).replaceAll(document);
        final db = target.database;

        final weight = await (db.select(
          db.weightEntries,
        )..where((w) => w.id.equals(Ids.weightFirst))).getSingle();
        expect(weight.createdAtUtc, at(2, 6, 30, 16));
        expect(weight.updatedAtUtc, at(2, 6, 45, 1, 5));
        expect(weight.occurredAtUtc, at(2, 6, 30, 15, 250));
        expect(weight.rowVersion, 2);
        expect(weight.deletedAtUtc, isNull);

        // No imported row is soft-deleted.
        final dump = await dumpDatabase(db);
        for (final table in [
          'weight_entries',
          'step_days',
          'water_entries',
          'meal_entries',
          'focus_sessions',
          'workout_entries',
          'tasks',
          'habits',
          'habit_checks',
        ]) {
          expect(dump[table], isNotEmpty, reason: table);
          for (final row in dump[table]!) {
            expect(row, contains('deletedAtUtc: null'), reason: table);
          }
        }
      },
    );

    test('works on a database without singleton rows', () async {
      final document = await richDocument();
      final empty = createTestDatabase();
      addTearDown(empty.close);
      await BackupImporter(
        database: empty,
        projections: const NoopProjectionSynchronizer(),
      ).replaceAll(document);
      expect(await empty.select(empty.profile).getSingle(), isNotNull);
      expect(await empty.select(empty.weightEntries).get(), hasLength(3));
    });

    test('importing the same file twice gives the same state', () async {
      final document = await richDocument();
      final target = await targetWithOtherData();
      final importer = BackupImporter(
        database: target,
        projections: const NoopProjectionSynchronizer(),
      );
      await importer.replaceAll(document);
      final first = await dumpDatabase(target);
      await importer.replaceAll(document);
      expect(await dumpDatabase(target), first);
    });

    test(
      'importing an almost empty backup replaces everything with it',
      () async {
        final empty = await DataHarness.create();
        addTearDown(empty.dispose);
        final backup = await BackupExporter(
          database: empty.database,
          clock: empty.clock,
        ).export();
        final document = const BackupValidator()
            .validateBytes(backup.bytes)
            .document!;

        final target = await targetWithOtherData();
        await BackupImporter(
          database: target,
          projections: const NoopProjectionSynchronizer(),
        ).replaceAll(document);
        expect(await target.select(target.weightEntries).get(), isEmpty);
        expect(await target.select(target.habits).get(), isEmpty);
        expect(await target.select(target.profile).getSingle(), isNotNull);
      },
    );

    test('database streams see the replacement', () async {
      final document = await richDocument();
      final target = await targetWithOtherData();
      final emissions = <List<String>>[];
      final subscription = target
          .select(target.weightEntries)
          .watch()
          .listen((rows) => emissions.add([for (final r in rows) r.id]));
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(emissions.last, [uuid(0xA01)]);

      await BackupImporter(
        database: target,
        projections: const NoopProjectionSynchronizer(),
      ).replaceAll(document);
      await pumpEventQueue();

      expect(
        emissions.last,
        unorderedEquals([Ids.weightFirst, uuid(0x102), uuid(0x103)]),
      );
    });

    test(
      'every table of the schema is covered by the wipe and the backup',
      () async {
        final harness = await DataHarness.create();
        addTearDown(harness.dispose);
        final db = harness.database;
        expect(
          {for (final t in db.allTables) t.actualTableName},
          {
            for (final t in BackupTable.values) t.key,
            ...BackupFormat.technicalTables,
          },
          reason:
              'a new table must be added to the backup format or declared '
              'technical on purpose',
        );
        await populateRichDatabase(db);
        await db.transaction(() => DatabaseWipe.deleteAllRows(db));
        for (final table in db.allTables) {
          expect(
            await db.select(table).get(),
            isEmpty,
            reason: table.actualTableName,
          );
        }
      },
    );
  });

  group('XP recomputation inside the same transaction', () {
    test(
      'the projection is called once with every day that has facts',
      () async {
        final document = await richDocument();
        final projection = RecordingProjectionSynchronizer();
        final target = await DataHarness.create(projections: projection);
        addTearDown(target.dispose);
        final result = await BackupImporter(
          database: target.database,
          projections: projection,
        ).replaceAll(document);

        expect(projection.syncs, hasLength(1));
        expect(projection.syncs.single.toList(), [
          march(2),
          march(3),
          march(4),
        ]);
        expect(result.recomputedDays, 3);
      },
    );

    test('runs after the replace, before the commit', () async {
      final document = await richDocument();
      final target = await targetWithOtherData();
      final probe = ProbingProjection(target)..staleWeightId = uuid(0xA01);
      await BackupImporter(
        database: target,
        projections: probe,
      ).replaceAll(document);
      expect(probe.weightsSeen, 3, reason: 'imported rows are visible');
      expect(probe.staleWeightsSeen, 0, reason: 'old rows are already gone');
      expect(probe.profilesSeen, 1);
    });

    test('is not called when no day has facts', () async {
      final empty = await DataHarness.create();
      addTearDown(empty.dispose);
      final backup = await BackupExporter(
        database: empty.database,
        clock: empty.clock,
      ).export();
      final document = const BackupValidator()
          .validateBytes(backup.bytes)
          .document!;
      final projection = RecordingProjectionSynchronizer();
      final result = await BackupImporter(
        database: empty.database,
        projections: projection,
      ).replaceAll(document);
      expect(projection.syncs, isEmpty);
      expect(result.recomputedDays, 0);
    });

    test('awards come from the projection, not from the file', () async {
      final document = await richDocument();
      final target = await DataHarness.create();
      addTearDown(target.dispose);
      final projection = FactBasedProjection(target.database);
      await BackupImporter(
        database: target.database,
        projections: projection,
      ).replaceAll(document);

      final awards = await target.database
          .select(target.database.xpAwards)
          .get();
      expect(
        awards.map((a) => a.awardKey),
        containsAll([
          'weight:2026-03-02',
          'weight:2026-03-03',
          'weight:2026-03-04',
          'water:${uuid(0x122)}',
        ]),
      );
      // The stale award rows of the fixture (the exported database had other
      // awards) are not in the file, so nothing is carried over.
      expect(awards.where((a) => a.awardKey == 'weight:2025-06-02'), isEmpty);
    });
  });

  group('fact days', () {
    BackupDocument withChanges(
      Map<String, Object?> root,
      void Function(Map<String, Object?> data) change,
    ) {
      change(root['data']! as Map<String, Object?>);
      return BackupDocument.fromJson(root);
    }

    late Map<String, Object?> baseJson;
    setUp(() async => baseJson = await richBackupJson());

    Map<String, Object?> copy() => jsonCopy(baseJson);

    test('weight, step, water, workout and habit check dates count', () {
      final root = copy();
      final document = withChanges(root, (data) {
        void shift(String table, String key, String date) {
          final list = data[table]! as List<Object?>;
          (list.first! as Map<String, Object?>)[key] = date;
        }

        shift('weight_entries', 'local_date', '2026-05-01');
        shift('step_days', 'local_date', '2026-05-02');
        shift('water_entries', 'local_date', '2026-05-03');
        shift('workout_entries', 'local_date', '2026-05-04');
        shift('habit_checks', 'local_date', '2026-05-05');
      });
      final days = BackupImporter.factDays(document.data);
      expect(
        days,
        containsAll([
          LocalDate(2026, 5, 1),
          LocalDate(2026, 5, 2),
          LocalDate(2026, 5, 3),
          LocalDate(2026, 5, 4),
          LocalDate(2026, 5, 5),
        ]),
      );
    });

    test(
      'completion dates of tasks and focus sessions count, others do not',
      () {
        final root = copy();
        final document = withChanges(root, (data) {
          // Completed task (index 1) and completed session (index 0).
          ((data['tasks']! as List<Object?>)[1]!
                  as Map<String, Object?>)['completed_local_date'] =
              '2026-06-10';
          ((data['focus_sessions']! as List<Object?>)[0]!
                  as Map<String, Object?>)['completed_local_date'] =
              '2026-06-11';
          // Due date of an open task and the start of a discarded session are
          // not facts of a day.
          ((data['tasks']! as List<Object?>)[0]!
                  as Map<String, Object?>)['due_local_date'] =
              '2026-06-12';
        });
        final days = BackupImporter.factDays(document.data);
        expect(days, contains(LocalDate(2026, 6, 10)));
        expect(days, contains(LocalDate(2026, 6, 11)));
        expect(days, isNot(contains(LocalDate(2026, 6, 12))));
      },
    );

    test('meals and snapshot-only days do not count', () {
      final root = copy();
      final document = withChanges(root, (data) {
        ((data['meal_entries']! as List<Object?>).first!
                as Map<String, Object?>)['local_date'] =
            '2026-07-01';
        ((data['daily_goal_snapshots']! as List<Object?>).first!
                as Map<String, Object?>)['local_date'] =
            '2026-07-02';
      });
      final days = BackupImporter.factDays(document.data);
      expect(days, isNot(contains(LocalDate(2026, 7, 1))));
      expect(days, isNot(contains(LocalDate(2026, 7, 2))));
    });

    test('days are unique and in ascending order', () {
      final document = BackupDocument.fromJson(copy());
      final days = BackupImporter.factDays(document.data).toList();
      expect(days, [march(2), march(3), march(4)]);
      expect(days, equals([...days]..sort()));
    });

    test('a backup without facts has no fact days', () {
      final root = copy();
      final document = withChanges(root, (data) {
        for (final table in [
          'weight_entries',
          'step_days',
          'water_entries',
          'workout_entries',
          'habit_checks',
          'tasks',
          'focus_sessions',
        ]) {
          (data[table]! as List<Object?>).clear();
        }
      });
      expect(BackupImporter.factDays(document.data), isEmpty);
    });
  });

  group('any failure rolls everything back (AT27 style)', () {
    late BackupDocument document;
    late DataHarness target;
    late Map<String, List<String>> before;

    setUp(() async {
      document = await richDocument();
      target = await DataHarness.create();
      addTearDown(target.dispose);
      await populateOtherData(target.database);
      before = await dumpDatabase(target.database);
    });

    test('a failing projection leaves the previous data intact', () async {
      final projection = RecordingProjectionSynchronizer()
        ..failure = StateError('simulated projection failure');
      await expectLater(
        BackupImporter(
          database: target.database,
          projections: projection,
        ).replaceAll(document),
        throwsA(isA<StateError>()),
      );
      expect(projection.syncs, hasLength(1), reason: 'the projection did run');
      expect(await dumpDatabase(target.database), before);
    });

    test(
      'a failure in the projection after it already wrote also rolls back',
      () async {
        final projection = WriteThenFailProjection(target.database);
        await expectLater(
          BackupImporter(
            database: target.database,
            projections: projection,
          ).replaceAll(document),
          throwsA(isA<StateError>()),
        );
        expect(await dumpDatabase(target.database), before);
      },
    );

    /// A document whose LAST inserted rows violate a database constraint
    /// although every record passes the DTO checks of a file (the DTOs are
    /// built directly here, bypassing the validator).
    BackupDocument withBrokenRow(BackupData Function(BackupData data) change) =>
        BackupDocument(
          exportedAtUtc: document.exportedAtUtc,
          appVersion: document.appVersion,
          data: change(document.data),
        );

    BackupData replaceWeights(BackupData d, List<WeightEntryDto> weights) =>
        BackupData(
          profile: d.profile,
          appSettings: d.appSettings,
          moduleStatusHistory: d.moduleStatusHistory,
          dashboardCards: d.dashboardCards,
          goalVersions: d.goalVersions,
          dailyGoalSnapshots: d.dailyGoalSnapshots,
          weightEntries: weights,
          stepDays: d.stepDays,
          waterEntries: d.waterEntries,
          mealEntries: d.mealEntries,
          focusSessions: d.focusSessions,
          workoutEntries: d.workoutEntries,
          tasks: d.tasks,
          habits: d.habits,
          habitChecks: d.habitChecks,
          reminderRules: d.reminderRules,
        );

    BackupData addHabitCheck(BackupData d, HabitCheckDto check) => BackupData(
      profile: d.profile,
      appSettings: d.appSettings,
      moduleStatusHistory: d.moduleStatusHistory,
      dashboardCards: d.dashboardCards,
      goalVersions: d.goalVersions,
      dailyGoalSnapshots: d.dailyGoalSnapshots,
      weightEntries: d.weightEntries,
      stepDays: d.stepDays,
      waterEntries: d.waterEntries,
      mealEntries: d.mealEntries,
      focusSessions: d.focusSessions,
      workoutEntries: d.workoutEntries,
      tasks: d.tasks,
      habits: d.habits,
      habitChecks: [...d.habitChecks, check],
      reminderRules: d.reminderRules,
    );

    WeightEntryDto weight(String id, {int grams = 71500, DateTime? time}) =>
        WeightEntryDto(
          id: id,
          weightGrams: grams,
          occurredAtUtc: time ?? at(20, 6),
          localDate: march(20),
          timezoneId: berlin,
          beforeToilet: false,
          afterDrinking: false,
          afterEating: false,
          gamificationEligible: true,
          createdAtUtc: at(20, 6),
          updatedAtUtc: at(20, 6),
          rowVersion: 1,
        );

    test(
      'a row that violates a CHECK only during the insert rolls back',
      () async {
        final broken = withBrokenRow(
          (d) => replaceWeights(d, [
            ...d.weightEntries,
            weight(uuid(0xB01), grams: 71550), // not a multiple of 100 g
          ]),
        );
        await expectLater(
          BackupImporter(
            database: target.database,
            projections: const NoopProjectionSynchronizer(),
          ).replaceAll(broken),
          throwsA(anything),
        );
        expect(await dumpDatabase(target.database), before);
      },
    );

    test(
      'a foreign key violation in the last table rolls back everything',
      () async {
        final broken = withBrokenRow(
          (d) => addHabitCheck(
            d,
            HabitCheckDto(
              id: uuid(0xB02),
              habitId: uuid(0xDEAD), // no such habit
              localDate: march(21),
              checkedAtUtc: at(21, 7),
              timezoneId: berlin,
              eligibility: true,
              createdAtUtc: at(21, 7),
              updatedAtUtc: at(21, 7),
              rowVersion: 1,
            ),
          ),
        );
        await expectLater(
          BackupImporter(
            database: target.database,
            projections: const NoopProjectionSynchronizer(),
          ).replaceAll(broken),
          throwsA(anything),
        );
        expect(await dumpDatabase(target.database), before);
      },
    );

    test('a unique key violation (same measurement time) rolls back', () async {
      final broken = withBrokenRow(
        (d) => replaceWeights(d, [
          weight(uuid(0xB03)),
          weight(uuid(0xB04)), // same instant as the first
        ]),
      );
      await expectLater(
        BackupImporter(
          database: target.database,
          projections: const NoopProjectionSynchronizer(),
        ).replaceAll(broken),
        throwsA(anything),
      );
      expect(await dumpDatabase(target.database), before);
    });

    test('a duplicate primary key rolls back', () async {
      final broken = withBrokenRow(
        (d) => replaceWeights(d, [
          weight(uuid(0xB05)),
          weight(uuid(0xB05), time: at(21, 6)),
        ]),
      );
      await expectLater(
        BackupImporter(
          database: target.database,
          projections: const NoopProjectionSynchronizer(),
        ).replaceAll(broken),
        throwsA(anything),
      );
      expect(await dumpDatabase(target.database), before);
    });

    test('after a failure the same import works', () async {
      final projection = RecordingProjectionSynchronizer()
        ..failure = StateError('boom');
      await expectLater(
        BackupImporter(
          database: target.database,
          projections: projection,
        ).replaceAll(document),
        throwsA(isA<StateError>()),
      );
      projection.failure = null;
      await BackupImporter(
        database: target.database,
        projections: projection,
      ).replaceAll(document);
      expect(
        await target.database.select(target.database.habits).get(),
        hasLength(2),
      );
      expect(
        await target.database.select(target.database.weightEntries).get(),
        hasLength(3),
      );
    });

    test(
      'streams do not announce a replacement that was rolled back',
      () async {
        final emissions = <List<String>>[];
        final subscription = target.database
            .select(target.database.weightEntries)
            .watch()
            .listen((rows) => emissions.add([for (final r in rows) r.id]));
        addTearDown(subscription.cancel);
        await pumpEventQueue();
        final projection = RecordingProjectionSynchronizer()
          ..failure = StateError('boom');
        await expectLater(
          BackupImporter(
            database: target.database,
            projections: projection,
          ).replaceAll(document),
          throwsA(isA<StateError>()),
        );
        await pumpEventQueue();
        for (final emission in emissions) {
          expect(emission, [uuid(0xA01)]);
        }
      },
    );
  });

  group('tasks and focus data survive field by field', () {
    test('tags, descriptions and completion triple', () async {
      final document = await richDocument();
      final target = await DataHarness.create();
      addTearDown(target.dispose);
      await BackupImporter(
        database: target.database,
        projections: const NoopProjectionSynchronizer(),
      ).replaceAll(document);
      final tasks = await target.database.select(target.database.tasks).get();
      final byTitle = {for (final t in tasks) t.title: t};
      final open = byTitle['Steuererklärung vorbereiten']!;
      expect(open.tagsJson, ['Finanzen', 'Dringend']);
      expect(open.description, 'Belege sortieren');
      expect(open.dueLocalDate, march(10));
      expect(open.completedAtUtc, isNull);
      expect(open.completionEligibility, isNull);
      final done = byTitle['Altpapier rausbringen']!;
      expect(done.completedAtUtc, at(3, 17, 45, 10, 500));
      expect(done.completedLocalDate, march(3));
      expect(done.completionEligibility, isFalse);
      expect(done.timezoneId, 'Europe/Berlin');
      expect(TaskDto.fromRow(done).isCompleted, isTrue);
    });
  });
}
