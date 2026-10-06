import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';

/// One named, independently testable step of a schema upgrade.
///
/// A step is written in plain SQL and refers to nothing but the tables as they
/// were when the step was written, never to the current table classes: a later
/// schema version changes those classes, and an old step must keep doing what
/// it did. Every step is idempotent (it checks what is already there), so that
/// a run that was interrupted after the commit but before SQLite's
/// `user_version` was raised can simply start again.
final class SchemaMigrationStep {
  const SchemaMigrationStep({
    required this.name,
    required this.ticket,
    required this.run,
  });

  /// Stable identifier of the step (also used in the tests and the docs).
  final String name;

  /// The Jira ticket whose feature needs the step.
  final String ticket;

  /// Runs the step on [database]. Called inside the transaction of
  /// [SchemaMigrations.upgrade].
  final Future<void> Function(AppDatabase database) run;
}

/// The database was written by a newer schema version than this app knows.
///
/// A downgrade is refused; the data stays untouched and the start-up reports
/// a migration failure (which never deletes anything).
final class UnsupportedSchemaDowngrade implements Exception {
  const UnsupportedSchemaDowngrade({required this.from, required this.to});

  /// The `user_version` found in the file.
  final int from;

  /// The schema version of this app.
  final int to;

  @override
  String toString() => 'UnsupportedSchemaDowngrade(from: $from, to: $to)';
}

/// The additive migration from schema 1 to schema 2 (BS-98, data contract v2).
///
/// Schema 2 prepares the data of three features of the release v0.2.0, so that
/// each of them only adds repositories, commands and screens on top:
///
/// - BS-99 (daily workout goal): the table `workout_day_marks` and the goal
///   type `workout_daily` in the CHECK of `goal_versions.goal_type`;
/// - BS-97 (steps from the health app): `step_days.source` and two settings in
///   `app_settings`;
/// - BS-111 (reminder per task): three `reminder_*` columns in `tasks`.
///
/// Everything is additive. Rows that exist keep every value; new columns have
/// the defaults named below. The only rebuild of a table is `goal_versions`
/// (SQLite cannot change a CHECK constraint in place); all its rows and its
/// uniqueness are kept.
///
/// ## How the steps run
///
/// [upgrade] switches foreign keys off (SQLite cannot do that inside a
/// transaction), runs all steps of the range in ONE transaction and switches
/// foreign keys on again. Either all steps are applied or none: a failure
/// rolls back, the file stays at schema 1 and the next start tries again. The
/// start-up reports it as a migration failure and never deletes data.
abstract final class SchemaMigrations {
  /// The steps of the upgrade to schema 2, in the order they run.
  static const List<SchemaMigrationStep> toVersion2 = [
    workoutDayMarks,
    workoutDailyGoalType,
    stepDaySource,
    healthStepsSettings,
    taskReminder,
  ];

  /// BS-99: the table of rest and skipped days (new, empty).
  static const SchemaMigrationStep workoutDayMarks = SchemaMigrationStep(
    name: 'workout_day_marks',
    ticket: 'BS-99',
    run: _createWorkoutDayMarks,
  );

  /// BS-99: allow `workout_daily` in `goal_versions.goal_type`. Rebuilds the
  /// table (copy, drop, rename) with all rows, the uniqueness of goal type and
  /// date, and the index.
  static const SchemaMigrationStep workoutDailyGoalType = SchemaMigrationStep(
    name: 'workout_daily_goal_type',
    ticket: 'BS-99',
    run: _allowWorkoutDailyGoalType,
  );

  /// BS-97: `step_days.source`; every existing row becomes `manual`.
  static const SchemaMigrationStep stepDaySource = SchemaMigrationStep(
    name: 'step_day_source',
    ticket: 'BS-97',
    run: _addStepDaySource,
  );

  /// BS-97: `app_settings.health_steps_sync_enabled` (off) and
  /// `app_settings.health_steps_last_sync_at_utc` (null).
  static const SchemaMigrationStep healthStepsSettings = SchemaMigrationStep(
    name: 'health_steps_settings',
    ticket: 'BS-97',
    run: _addHealthStepsSettings,
  );

  /// BS-111: `tasks.reminder_at_utc`, `reminder_local_date` and
  /// `reminder_timezone_id`; no task has a reminder afterwards.
  static const SchemaMigrationStep taskReminder = SchemaMigrationStep(
    name: 'task_reminder',
    ticket: 'BS-111',
    run: _addTaskReminder,
  );

  /// Upgrades a database that was opened at schema version [from] to [to].
  ///
  /// Called by the migration strategy of [AppDatabase]; [from] is the
  /// `user_version` of the file. A downgrade throws
  /// [UnsupportedSchemaDowngrade] and changes nothing.
  static Future<void> upgrade(
    AppDatabase database, {
    required int from,
    required int to,
  }) async {
    if (from > to) {
      throw UnsupportedSchemaDowngrade(from: from, to: to);
    }
    await runSteps(database, [if (from < 2 && to >= 2) ...toVersion2]);
  }

  /// Runs [steps] in ONE transaction with foreign keys switched off (SQLite
  /// cannot change that inside a transaction) and switches them on again
  /// afterwards, also after a failure. A failing step rolls all of them back.
  static Future<void> runSteps(
    AppDatabase database,
    List<SchemaMigrationStep> steps,
  ) async {
    if (steps.isEmpty) {
      return;
    }
    final foreignKeys = await database
        .customSelect('PRAGMA foreign_keys')
        .getSingle();
    final foreignKeysWereOn = foreignKeys.read<int>('foreign_keys') == 1;
    if (foreignKeysWereOn) {
      await database.customStatement('PRAGMA foreign_keys = OFF');
    }
    try {
      await database.transaction(() async {
        for (final step in steps) {
          await step.run(database);
        }
      });
    } finally {
      if (foreignKeysWereOn) {
        await database.customStatement('PRAGMA foreign_keys = ON');
      }
    }
  }

  // ------------------------------------------------------------------ BS-99

  static Future<void> _createWorkoutDayMarks(AppDatabase database) async {
    await database.customStatement(
      'CREATE TABLE IF NOT EXISTS "workout_day_marks" ('
      '"created_at_utc" INTEGER NOT NULL, '
      '"updated_at_utc" INTEGER NOT NULL, '
      '"row_version" INTEGER NOT NULL DEFAULT 1 CHECK(row_version >= 1), '
      '"deleted_at_utc" INTEGER NULL, '
      '"id" TEXT NOT NULL, '
      '"local_date" TEXT NOT NULL, '
      '"kind" TEXT NOT NULL CHECK(kind IN (\'rest\',\'skipped\')), '
      '"timezone_id" TEXT NOT NULL, '
      'PRIMARY KEY ("id"))',
    );
    await database.customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS workout_day_marks_active_date '
      'ON workout_day_marks (local_date) WHERE deleted_at_utc IS NULL',
    );
  }

  static Future<void> _allowWorkoutDailyGoalType(AppDatabase database) async {
    final table = await _tableSql(database, 'goal_versions');
    if (table == null || table.contains("'workout_daily'")) {
      return; // already rebuilt (or no such table: nothing to rebuild)
    }
    // The twelve-step procedure of the SQLite documentation (foreign keys are
    // off and the whole upgrade runs in one transaction): new table, copy,
    // drop the old one, rename, re-create the index.
    await database.customStatement('DROP TABLE IF EXISTS "goal_versions_new"');
    await database.customStatement(
      'CREATE TABLE "goal_versions_new" ('
      '"id" TEXT NOT NULL, '
      '"goal_type" TEXT NOT NULL CHECK(goal_type IN ('
      "'water','steps','weight_entry','focus_minutes','task_completion',"
      "'workout_weekly','workout_daily')), "
      '"target_integer" INTEGER NULL CHECK(target_integer IS NULL OR '
      'target_integer > 0), '
      '"enabled" INTEGER NOT NULL CHECK ("enabled" IN (0, 1)), '
      '"effective_from_date" TEXT NOT NULL, '
      '"created_at_utc" INTEGER NOT NULL, '
      'PRIMARY KEY ("id"), '
      'UNIQUE ("goal_type", "effective_from_date"))',
    );
    await database.customStatement(
      'INSERT INTO "goal_versions_new" '
      '("id", "goal_type", "target_integer", "enabled", '
      '"effective_from_date", "created_at_utc") '
      'SELECT "id", "goal_type", "target_integer", "enabled", '
      '"effective_from_date", "created_at_utc" '
      'FROM "goal_versions" ORDER BY rowid',
    );
    await database.customStatement('DROP TABLE "goal_versions"');
    await database.customStatement(
      'ALTER TABLE "goal_versions_new" RENAME TO "goal_versions"',
    );
    await database.customStatement(
      'CREATE INDEX goal_versions_type_date '
      'ON goal_versions (goal_type, effective_from_date)',
    );
  }

  // ------------------------------------------------------------------ BS-97

  static Future<void> _addStepDaySource(AppDatabase database) => _addColumn(
    database,
    table: 'step_days',
    column: 'source',
    definition:
        '"source" TEXT NOT NULL DEFAULT \'manual\' '
        "CHECK(source IN ('manual','health'))",
  );

  static Future<void> _addHealthStepsSettings(AppDatabase database) async {
    await _addColumn(
      database,
      table: 'app_settings',
      column: 'health_steps_sync_enabled',
      definition:
          '"health_steps_sync_enabled" INTEGER NOT NULL DEFAULT 0 '
          'CHECK ("health_steps_sync_enabled" IN (0, 1))',
    );
    await _addColumn(
      database,
      table: 'app_settings',
      column: 'health_steps_last_sync_at_utc',
      definition: '"health_steps_last_sync_at_utc" INTEGER NULL',
    );
  }

  // ----------------------------------------------------------------- BS-111

  static Future<void> _addTaskReminder(AppDatabase database) async {
    await _addColumn(
      database,
      table: 'tasks',
      column: 'reminder_at_utc',
      definition: '"reminder_at_utc" INTEGER NULL',
    );
    await _addColumn(
      database,
      table: 'tasks',
      column: 'reminder_local_date',
      definition:
          '"reminder_local_date" TEXT NULL '
          'CHECK((reminder_at_utc IS NULL) = (reminder_local_date IS NULL))',
    );
    await _addColumn(
      database,
      table: 'tasks',
      column: 'reminder_timezone_id',
      definition:
          '"reminder_timezone_id" TEXT NULL '
          'CHECK((reminder_at_utc IS NULL) = (reminder_timezone_id IS NULL))',
    );
  }

  // ---------------------------------------------------------------- helpers

  /// Adds [column] to [table] unless it exists. SQLite places the new column
  /// behind the last one and in front of the table constraints, which is where
  /// the column classes of the schema put it.
  static Future<void> _addColumn(
    AppDatabase database, {
    required String table,
    required String column,
    required String definition,
  }) async {
    final columns = await _columnNames(database, table);
    if (columns.contains(column)) {
      return;
    }
    await database.customStatement(
      'ALTER TABLE "$table" ADD COLUMN $definition',
    );
  }

  static Future<List<String>> _columnNames(
    AppDatabase database,
    String table,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT name FROM pragma_table_info(?1)',
          variables: [Variable<String>(table)],
        )
        .get();
    return [for (final row in rows) row.read<String>('name')];
  }

  /// The `CREATE TABLE` statement SQLite stores for [table], or null.
  static Future<String?> _tableSql(AppDatabase database, String table) async {
    final rows = await database
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?1",
          variables: [Variable<String>(table)],
        )
        .get();
    return rows.isEmpty ? null : rows.single.readNullable<String>('sql');
  }
}
