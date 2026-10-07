import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/converters.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/database/schema_migrations.dart';
import 'package:self_improvement/core/database/tables/body_tables.dart';
import 'package:self_improvement/core/database/tables/core_tables.dart';
import 'package:self_improvement/core/database/tables/focus_tables.dart';
import 'package:self_improvement/core/database/tables/nutrition_tables.dart';
import 'package:self_improvement/core/database/tables/system_tables.dart';
import 'package:self_improvement/core/database/tables/task_tables.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

part 'app_database.g.dart';

/// The single local SQLite database of the app (schema version 2).
///
/// All durable data lives here; there is no second persistence layer.
/// Foreign keys are enforced and range/enum checks exist on the data level in
/// addition to the UI validation.
@DriftDatabase(
  tables: [
    Profile,
    AppSettings,
    ModuleStatusHistory,
    DashboardCards,
    GoalVersions,
    DailyGoalSnapshots,
    WeightEntries,
    StepDays,
    WaterEntries,
    MealEntries,
    FocusSessions,
    WorkoutEntries,
    Tasks,
    Habits,
    HabitChecks,
    XpAwards,
    CommandReceipts,
    ReminderRules,
    ScheduledNotifications,
    WorkoutDayMarks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Current schema version. Bump together with the named migration steps in
  /// `schema_migrations.dart` (each with its own test) and the backup format
  /// (`AppConfig.backupSchemaVersion`). Version 2 (BS-98) added the data of
  /// BS-99, BS-97 and BS-111; see `SchemaMigrations`.
  static const int currentSchemaVersion = 2;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (migrator, from, to) =>
        SchemaMigrations.upgrade(this, from: from, to: to),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
