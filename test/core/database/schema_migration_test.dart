import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/schema_migrations.dart';
import 'package:self_improvement/core/testing/test_database.dart';

import '../../support/db_fixtures.dart';
import 'support/migration_support.dart';

/// Matcher for a SQLite constraint violation (CHECK, UNIQUE, ...).
Matcher get violatesConstraint => throwsA(
  predicate<Object>(
    (e) => e.toString().toLowerCase().contains('constraint failed'),
    'a SQLite constraint violation',
  ),
);

/// The migration from schema 1 to schema 2 (BS-98, data contract v2): every
/// step on its own, the whole run, and the result against a fresh database.
///
/// The starting point is always the fixture `test/fixtures/v1/v1-database.sql`:
/// a schema 1 database that the unchanged v0.1.0 code wrote (see
/// `generate_v1_fixtures.dart.txt`). The tests open it WITHOUT the upgrade
/// (`V1FixtureDatabase`), run one step and compare it with the state before.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late V1FixtureDatabase db;
  late Map<String, List<String>> v1Columns;
  late Map<String, List<String>> before;

  setUp(() async {
    db = V1FixtureDatabase(v1FixtureExecutor());
    v1Columns = await columnsOfAllTables(db);
    before = await rowsOfAllTables(db, v1Columns);
  });
  tearDown(() => db.close());

  /// All rows over all schema 1 columns as before the step.
  Future<void> expectNoV1ValueChanged() async {
    expect(await rowsOfAllTables(db, v1Columns), before);
  }

  Future<List<String>> columnsOf(String table) async =>
      (await columnsOfAllTables(db))[table]!;

  Future<Set<String>> tableNames() async =>
      (await columnsOfAllTables(db)).keys.toSet();

  group('the starting point is a real schema 1 database (BS-98)', () {
    test('19 tables, user_version 1, every table holds rows', () async {
      expect(await userVersion(db), 1);
      expect(v1Columns.keys, hasLength(19));
      final counts = await rowCounts(db);
      for (final entry in counts.entries) {
        expect(entry.value, greaterThan(0), reason: entry.key);
      }
      expect(await integrityCheck(db), ['ok']);
      expect(await foreignKeyViolations(db), isEmpty);
    });

    test('it does not know the schema 2 parts yet', () async {
      expect(await tableNames(), isNot(contains('workout_day_marks')));
      expect(await columnsOf('step_days'), isNot(contains('source')));
      expect(await columnsOf('app_settings'), hasLength(9));
      expect(await columnsOf('tasks'), isNot(contains('reminder_at_utc')));
      await expectLater(
        db.customStatement(
          'INSERT INTO goal_versions (id, goal_type, enabled, '
          'effective_from_date, created_at_utc) '
          "VALUES ('x', 'workout_daily', 0, '2026-05-01', 1)",
        ),
        violatesConstraint,
      );
    });
  });

  group('step workout_day_marks (BS-99)', () {
    test(
      'creates the table with its columns and nothing else changes',
      () async {
        final schemaBefore = await schemaLines(db);
        await SchemaMigrations.workoutDayMarks.run(db);
        expect(await columnsOf('workout_day_marks'), [
          'created_at_utc',
          'updated_at_utc',
          'row_version',
          'deleted_at_utc',
          'id',
          'local_date',
          'kind',
          'timezone_id',
        ]);
        final schemaAfter = await schemaLines(db);
        final added = schemaAfter.toSet().difference(schemaBefore.toSet());
        expect(
          added.map((line) => line.split(':').first),
          unorderedEquals([
            'table workout_day_marks (workout_day_marks)',
            'index workout_day_marks_active_date (workout_day_marks)',
          ]),
        );
        expect(schemaBefore.toSet().difference(schemaAfter.toSet()), isEmpty);
        await expectNoV1ValueChanged();
      },
    );

    test(
      'the new table is empty, accepts both kinds and rejects others',
      () async {
        await SchemaMigrations.workoutDayMarks.run(db);
        expect(
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM workout_day_marks')
                  .getSingle())
              .read<int>('n'),
          0,
        );
        Future<void> insert(String id, String date, String kind) =>
            db.customStatement(
              'INSERT INTO workout_day_marks (created_at_utc, updated_at_utc, '
              'id, local_date, kind, timezone_id) '
              "VALUES (1, 1, '$id', '$date', '$kind', 'Europe/Berlin')",
            );
        await insert('a', '2026-05-01', 'rest');
        await insert('b', '2026-05-02', 'skipped');
        await expectLater(
          insert('c', '2026-05-03', 'sick'),
          violatesConstraint,
        );
        final row = await db
            .customSelect(
              "SELECT row_version, deleted_at_utc FROM workout_day_marks WHERE id = 'a'",
            )
            .getSingle();
        expect(
          row.read<int>('row_version'),
          1,
          reason: 'default of the audit column',
        );
        expect(row.readNullable<int>('deleted_at_utc'), isNull);
      },
    );

    test(
      'at most one active mark per day; a deleted one frees the day',
      () async {
        await SchemaMigrations.workoutDayMarks.run(db);
        Future<void> insert(String id, {bool deleted = false}) =>
            db.customStatement(
              'INSERT INTO workout_day_marks (created_at_utc, updated_at_utc, '
              'deleted_at_utc, id, local_date, kind, timezone_id) '
              "VALUES (1, 1, ${deleted ? 5 : 'NULL'}, '$id', '2026-05-01', "
              "'rest', 'Europe/Berlin')",
            );
        await insert('a');
        await expectLater(insert('b'), violatesConstraint);
        await db.customStatement(
          "UPDATE workout_day_marks SET deleted_at_utc = 9 WHERE id = 'a'",
        );
        await insert('c');
        await insert('d', deleted: true);
        await expectLater(insert('e'), violatesConstraint);
      },
    );

    test('running it twice changes nothing', () async {
      await SchemaMigrations.workoutDayMarks.run(db);
      final once = await schemaLines(db);
      await SchemaMigrations.workoutDayMarks.run(db);
      expect(await schemaLines(db), once);
    });
  });

  group('step workout_daily_goal_type (BS-99): the goal_versions rebuild', () {
    const insertDaily =
        'INSERT INTO goal_versions (id, goal_type, target_integer, enabled, '
        'effective_from_date, created_at_utc) '
        "VALUES ('daily-1', 'workout_daily', 1, 1, '2026-05-01', 1)";

    test('keeps every row with every value and in the same order', () async {
      final goalsBefore = before['goal_versions']!;
      expect(goalsBefore, hasLength(8), reason: 'the fixture has 8 versions');
      await SchemaMigrations.workoutDailyGoalType.run(db);
      expect(await columnsOf('goal_versions'), v1Columns['goal_versions']);
      await expectNoV1ValueChanged();
    });

    test('now allows workout_daily and still rejects unknown types', () async {
      await SchemaMigrations.workoutDailyGoalType.run(db);
      await db.customStatement(insertDaily);
      await expectLater(
        db.customStatement(
          'INSERT INTO goal_versions (id, goal_type, enabled, '
          'effective_from_date, created_at_utc) '
          "VALUES ('x', 'calories', 1, '2026-05-01', 1)",
        ),
        violatesConstraint,
      );
      for (final type in [
        'water',
        'steps',
        'weight_entry',
        'focus_minutes',
        'task_completion',
        'workout_weekly',
        'workout_daily',
      ]) {
        await db.customStatement(
          'INSERT INTO goal_versions (id, goal_type, enabled, '
          'effective_from_date, created_at_utc) '
          "VALUES ('t-$type', '$type', 1, '2031-01-01', 1)",
        );
      }
    });

    test('keeps the uniqueness of goal type and effective date', () async {
      await SchemaMigrations.workoutDailyGoalType.run(db);
      await db.customStatement(insertDaily);
      await expectLater(
        db.customStatement(insertDaily.replaceFirst("'daily-1'", "'daily-2'")),
        violatesConstraint,
        reason: 'same goal type and date',
      );
      // An existing version of the fixture is still unique per type and date.
      final existing = await db
          .customSelect(
            'SELECT goal_type, effective_from_date FROM goal_versions LIMIT 1',
          )
          .getSingle();
      await expectLater(
        db.customStatement(
          'INSERT INTO goal_versions (id, goal_type, enabled, '
          "effective_from_date, created_at_utc) VALUES ('dup', "
          "'${existing.read<String>('goal_type')}', 1, "
          "'${existing.read<String>('effective_from_date')}', 1)",
        ),
        violatesConstraint,
      );
    });

    test('keeps the other column checks and the index', () async {
      await SchemaMigrations.workoutDailyGoalType.run(db);
      await expectLater(
        db.customStatement(
          'INSERT INTO goal_versions (id, goal_type, target_integer, enabled, '
          'effective_from_date, created_at_utc) '
          "VALUES ('z', 'water', 0, 1, '2031-01-01', 1)",
        ),
        violatesConstraint,
        reason: 'target_integer must be positive',
      );
      await expectLater(
        db.customStatement(
          'INSERT INTO goal_versions (id, goal_type, enabled, '
          'effective_from_date, created_at_utc) '
          "VALUES ('z', 'water', 2, '2031-01-01', 1)",
        ),
        violatesConstraint,
        reason: 'enabled is a boolean',
      );
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND tbl_name = 'goal_versions' AND sql IS NOT NULL",
          )
          .map((row) => row.read<String>('name'))
          .get();
      expect(indexes, ['goal_versions_type_date']);
    });

    test('leaves every other table as it was', () async {
      final others = {
        for (final entry in (await schemaLines(
          db,
        )).map((line) => MapEntry(line.split(' ')[1], line)))
          entry.key: entry.value,
      }..removeWhere((name, _) => name.startsWith('goal_versions'));
      await SchemaMigrations.workoutDailyGoalType.run(db);
      final after = {
        for (final entry in (await schemaLines(
          db,
        )).map((line) => MapEntry(line.split(' ')[1], line)))
          entry.key: entry.value,
      }..removeWhere((name, _) => name.startsWith('goal_versions'));
      expect(after, others);
    });

    test('running it twice rebuilds nothing again', () async {
      await SchemaMigrations.workoutDailyGoalType.run(db);
      final once = await schemaLines(db);
      await SchemaMigrations.workoutDailyGoalType.run(db);
      expect(await schemaLines(db), once);
      await expectNoV1ValueChanged();
    });

    test('a failure while copying leaves goal_versions untouched', () async {
      // A row that violates the new table makes the copy fail: simulate it
      // with a goal type the new CHECK does not know. The old table has the
      // CHECK of schema 1, so such a row can only exist in a damaged file.
      await db.customStatement('PRAGMA ignore_check_constraints = ON');
      await db.customStatement(
        'INSERT INTO goal_versions (id, goal_type, enabled, '
        'effective_from_date, created_at_utc) '
        "VALUES ('damaged', 'calories', 1, '2026-06-01', 1)",
      );
      await db.customStatement('PRAGMA ignore_check_constraints = OFF');
      final damaged = await rowsOfAllTables(db, v1Columns);
      await expectLater(
        db.transaction(() => SchemaMigrations.workoutDailyGoalType.run(db)),
        throwsA(anything),
      );
      expect(await rowsOfAllTables(db, v1Columns), damaged);
      final sql =
          (await db
                  .customSelect(
                    "SELECT sql FROM sqlite_master WHERE name = 'goal_versions'",
                  )
                  .getSingle())
              .read<String>('sql');
      expect(sql, isNot(contains('workout_daily')));
      expect(
        await tableNames(),
        isNot(contains('goal_versions_new')),
        reason: 'the transaction took the temporary table back as well',
      );
    });
  });

  group('step step_day_source (BS-97)', () {
    test('every existing day becomes manual and no value changes', () async {
      await SchemaMigrations.stepDaySource.run(db);
      expect((await columnsOf('step_days')).last, 'source');
      final rows = await db
          .customSelect('SELECT source, deleted_at_utc FROM step_days')
          .get();
      expect(rows, hasLength(10), reason: 'including the soft deleted day');
      expect(rows.map((r) => r.read<String>('source')).toSet(), {'manual'});
      await expectNoV1ValueChanged();
    });

    test(
      'new rows default to manual, health is allowed, others are not',
      () async {
        await SchemaMigrations.stepDaySource.run(db);
        Future<void> insert(String id, String date, [String? source]) {
          final column = source == null ? '' : ', source';
          final value = source == null ? '' : ", '$source'";
          return db.customStatement(
            'INSERT INTO step_days (created_at_utc, updated_at_utc, id, '
            'local_date, steps, timezone_id$column) '
            "VALUES (1, 1, '$id', '$date', 100, 'Europe/Berlin'$value)",
          );
        }

        await insert('a', '2026-06-01');
        await insert('b', '2026-06-02', 'health');
        await insert('c', '2026-06-03', 'manual');
        await expectLater(
          insert('d', '2026-06-04', 'watch'),
          violatesConstraint,
        );
        await expectLater(insert('e', '2026-06-05', ''), violatesConstraint);
        final defaulted = await db
            .customSelect("SELECT source FROM step_days WHERE id = 'a'")
            .getSingle();
        expect(defaulted.read<String>('source'), 'manual');
      },
    );

    test(
      'keeps the step range check and the one active day per date',
      () async {
        await SchemaMigrations.stepDaySource.run(db);
        await expectLater(
          db.customStatement(
            'INSERT INTO step_days (created_at_utc, updated_at_utc, id, '
            'local_date, steps, timezone_id) '
            "VALUES (1, 1, 'x', '2026-06-01', 100001, 'Europe/Berlin')",
          ),
          violatesConstraint,
        );
        final active = await db
            .customSelect(
              'SELECT local_date FROM step_days WHERE deleted_at_utc IS NULL '
              'LIMIT 1',
            )
            .getSingle();
        await expectLater(
          db.customStatement(
            'INSERT INTO step_days (created_at_utc, updated_at_utc, id, '
            "local_date, steps, timezone_id) VALUES (1, 1, 'dup', "
            "'${active.read<String>('local_date')}', 100, 'Europe/Berlin')",
          ),
          violatesConstraint,
        );
      },
    );

    test('running it twice changes nothing', () async {
      await SchemaMigrations.stepDaySource.run(db);
      final once = await schemaLines(db);
      await SchemaMigrations.stepDaySource.run(db);
      expect(await schemaLines(db), once);
    });
  });

  group('step health_steps_settings (BS-97)', () {
    test(
      'the settings keep their values; the new ones are off and empty',
      () async {
        await SchemaMigrations.healthStepsSettings.run(db);
        final row = await db
            .customSelect('SELECT * FROM app_settings')
            .getSingle();
        expect(row.read<String>('theme_mode'), 'oled');
        expect(row.read<int>('notifications_enabled'), 1);
        expect(row.read<int>('health_steps_sync_enabled'), 0);
        expect(row.readNullable<int>('health_steps_last_sync_at_utc'), isNull);
        expect((await columnsOf('app_settings')).sublist(9), [
          'health_steps_sync_enabled',
          'health_steps_last_sync_at_utc',
        ]);
        await expectNoV1ValueChanged();
      },
    );

    test('the switch is a boolean; the last sync takes any instant', () async {
      await SchemaMigrations.healthStepsSettings.run(db);
      await db.customStatement(
        'UPDATE app_settings SET health_steps_sync_enabled = 1, '
        'health_steps_last_sync_at_utc = 1775000000000',
      );
      await expectLater(
        db.customStatement(
          'UPDATE app_settings SET health_steps_sync_enabled = 2',
        ),
        violatesConstraint,
      );
      await db.customStatement(
        'UPDATE app_settings SET health_steps_last_sync_at_utc = NULL',
      );
    });

    test('keeps the singleton rule of the settings row', () async {
      await SchemaMigrations.healthStepsSettings.run(db);
      await expectLater(
        db.customStatement(
          'INSERT INTO app_settings (created_at_utc, updated_at_utc, id) '
          "VALUES (1, 1, 'other')",
        ),
        violatesConstraint,
      );
    });

    test('running it twice changes nothing', () async {
      await SchemaMigrations.healthStepsSettings.run(db);
      final once = await schemaLines(db);
      await SchemaMigrations.healthStepsSettings.run(db);
      expect(await schemaLines(db), once);
    });
  });

  group('step task_reminder (BS-111)', () {
    test('no task has a reminder afterwards and no value changes', () async {
      await SchemaMigrations.taskReminder.run(db);
      expect((await columnsOf('tasks')).sublist(14), [
        'reminder_at_utc',
        'reminder_local_date',
        'reminder_timezone_id',
      ]);
      final rows = await db
          .customSelect(
            'SELECT reminder_at_utc, reminder_local_date, '
            'reminder_timezone_id FROM tasks',
          )
          .get();
      expect(rows, hasLength(4));
      for (final row in rows) {
        expect(row.data.values, everyElement(isNull));
      }
      await expectNoV1ValueChanged();
    });

    test('the three columns are all set or all null', () async {
      await SchemaMigrations.taskReminder.run(db);
      Future<void> set(String sets) => db.customStatement(
        "UPDATE tasks SET $sets WHERE title = 'Zahnarzttermin buchen'",
      );
      await set(
        "reminder_at_utc = 1775000000000, reminder_local_date = '2026-04-01', "
        "reminder_timezone_id = 'Europe/Berlin'",
      );
      await set(
        'reminder_at_utc = NULL, reminder_local_date = NULL, '
        'reminder_timezone_id = NULL',
      );
      await expectLater(
        set('reminder_at_utc = 1775000000000'),
        violatesConstraint,
        reason: 'an instant without date and zone',
      );
      await expectLater(
        set("reminder_local_date = '2026-04-01'"),
        violatesConstraint,
        reason: 'a date without an instant',
      );
      await expectLater(
        set(
          "reminder_at_utc = 1775000000000, reminder_local_date = '2026-04-01'",
        ),
        violatesConstraint,
        reason: 'no zone',
      );
      await expectLater(
        set("reminder_at_utc = 1775000000000, reminder_timezone_id = 'UTC'"),
        violatesConstraint,
        reason: 'no date',
      );
    });

    test('the completion rules of schema 1 still hold', () async {
      await SchemaMigrations.taskReminder.run(db);
      await expectLater(
        db.customStatement(
          'INSERT INTO tasks (created_at_utc, updated_at_utc, id, title, '
          "completed_at_utc) VALUES (1, 1, 'x', 'Teil', 5)",
        ),
        violatesConstraint,
        reason: 'completed_at_utc needs the date and the eligibility',
      );
      await db.customStatement(
        'INSERT INTO tasks (created_at_utc, updated_at_utc, id, title, '
        'completed_at_utc, completed_local_date, completion_eligibility, '
        'reminder_at_utc, reminder_local_date, reminder_timezone_id) '
        "VALUES (1, 1, 'ok', 'Fertig', 5, '2026-04-01', 1, 6, '2026-04-01', 'UTC')",
      );
    });

    test('running it twice changes nothing', () async {
      await SchemaMigrations.taskReminder.run(db);
      final once = await schemaLines(db);
      await SchemaMigrations.taskReminder.run(db);
      expect(await schemaLines(db), once);
    });
  });

  group('the whole upgrade from schema 1 to 2 (BS-98)', () {
    Future<AppDatabase> freshDatabase() async {
      final fresh = createTestDatabase();
      await fresh.customSelect('SELECT 1').get();
      return fresh;
    }

    test('lists the five steps in order with their tickets', () {
      expect(SchemaMigrations.toVersion2.map((s) => s.name), [
        'workout_day_marks',
        'workout_daily_goal_type',
        'step_day_source',
        'health_steps_settings',
        'task_reminder',
      ]);
      expect(SchemaMigrations.toVersion2.map((s) => s.ticket), [
        'BS-99',
        'BS-99',
        'BS-97',
        'BS-97',
        'BS-111',
      ]);
      expect(
        SchemaMigrations.toVersion2.map((s) => s.name).toSet(),
        hasLength(5),
      );
      expect(AppDatabase.currentSchemaVersion, 2);
    });

    test('gives exactly the structure of a freshly created schema 2', () async {
      await SchemaMigrations.upgrade(db, from: 1, to: 2);
      final fresh = await freshDatabase();
      addTearDown(fresh.close);
      expect(await schemaLines(db), await schemaLines(fresh));
      expect(await columnsOfAllTables(db), await columnsOfAllTables(fresh));
    });

    test(
      'keeps every value of every schema 1 column of all 19 tables',
      () async {
        await SchemaMigrations.upgrade(db, from: 1, to: 2);
        await expectNoV1ValueChanged();
        expect(await rowCounts(db), {
          for (final entry in before.entries) entry.key: entry.value.length,
          'workout_day_marks': 0,
        });
        expect(await integrityCheck(db), ['ok']);
        expect(await foreignKeyViolations(db), isEmpty);
      },
    );

    test('running the upgrade a second time is harmless', () async {
      await SchemaMigrations.upgrade(db, from: 1, to: 2);
      final once = await schemaLines(db);
      await SchemaMigrations.upgrade(db, from: 1, to: 2);
      expect(await schemaLines(db), once);
      await expectNoV1ValueChanged();
    });

    test('is a no-op when the file is already at schema 2', () async {
      final fresh = await freshDatabase();
      addTearDown(fresh.close);
      final schema = await schemaLines(fresh);
      await SchemaMigrations.upgrade(fresh, from: 2, to: 2);
      expect(await schemaLines(fresh), schema);
    });

    test('foreign keys are on again after the upgrade', () async {
      expect(
        (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
          'foreign_keys',
        ),
        1,
      );
      await SchemaMigrations.upgrade(db, from: 1, to: 2);
      expect(
        (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
          'foreign_keys',
        ),
        1,
      );
    });

    test('a failing step rolls the whole upgrade back', () async {
      final schemaBefore = await schemaLines(db);
      await expectLater(
        SchemaMigrations.runSteps(db, [
          SchemaMigrations.workoutDayMarks,
          SchemaMigrations.workoutDailyGoalType,
          SchemaMigrations.stepDaySource,
          SchemaMigrationStep(
            name: 'broken',
            ticket: 'BS-98',
            run: (database) =>
                database.customStatement('SELECT * FROM nowhere'),
          ),
        ]),
        throwsA(anything),
      );
      expect(await schemaLines(db), schemaBefore);
      await expectNoV1ValueChanged();
      expect(await userVersion(db), 1);
      expect(
        (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
          'foreign_keys',
        ),
        1,
        reason: 'foreign keys are switched on again after a failure',
      );
    });

    test(
      'a database of a newer schema is refused and left untouched',
      () async {
        final newer = AppDatabase(
          v1FixtureExecutor(extraSql: 'PRAGMA user_version = 3;'),
        );
        addTearDown(newer.close);
        await expectLater(
          newer.customSelect('SELECT 1').get(),
          throwsA(isA<UnsupportedSchemaDowngrade>()),
        );
      },
    );
  });

  group('opening the schema 1 file with the real app code', () {
    test(
      'also when foreign keys are on while the upgrade starts (BS-98)',
      () async {
        // The upgrade switches them off for the table rebuild and on again.
        final upgraded = AppDatabase(
          v1FixtureExecutor(extraSql: 'PRAGMA foreign_keys = ON;'),
        );
        addTearDown(upgraded.close);
        await upgraded.customSelect('SELECT 1').get();
        expect(await userVersion(upgraded), 2);
        expect(await rowsOfAllTables(upgraded, v1Columns), before);
        expect(await foreignKeyViolations(upgraded), isEmpty);
        expect(
          (await upgraded.customSelect('PRAGMA foreign_keys').getSingle())
              .read<int>('foreign_keys'),
          1,
        );
      },
    );

    test('migrates to schema 2 and keeps every row (AT02, BS-98)', () async {
      final upgraded = AppDatabase(v1FixtureExecutor());
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();
      expect(await userVersion(upgraded), 2);
      expect(await rowsOfAllTables(upgraded, v1Columns), before);
      expect(await integrityCheck(upgraded), ['ok']);
      expect(await foreignKeyViolations(upgraded), isEmpty);
      expect(
        (await upgraded.customSelect('PRAGMA foreign_keys').getSingle())
            .read<int>('foreign_keys'),
        1,
      );
    });
  });

  group(
    'what the migration strategy of v0.1.0 does with a schema 2 file (BS-98)',
    () {
      test('it refuses the file and changes nothing', () async {
        // v0.1.0 has schema version 1 and a strategy without `onUpgrade`: Drift
        // treats a file with a higher version as an upgrade it cannot do and
        // fails. This is a model of that strategy, not the released app.
        final directory = await Directory.systemTemp.createTemp('v010_');
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/self_improvement.sqlite');
        final current = AppDatabase(NativeDatabase(file));
        await current.into(current.weightEntries).insert(weightRow());
        await current.close();

        final v010 = _V010Database(NativeDatabase(file));
        await expectLater(
          v010.customSelect('SELECT 1').get(),
          throwsA(anything),
        );
        try {
          await v010.close();
        } on Object {
          // A database that failed to open may fail to close.
        }

        final again = AppDatabase(NativeDatabase(file));
        addTearDown(again.close);
        expect(await userVersion(again), 2);
        expect(await again.select(again.weightEntries).get(), hasLength(1));
      });
    },
  );
}

/// The migration strategy of v0.1.0: create everything, no upgrade steps.
class _V010Database extends AppDatabase {
  _V010Database(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
