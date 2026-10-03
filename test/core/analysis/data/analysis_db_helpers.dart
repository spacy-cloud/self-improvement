import 'package:drift/drift.dart';
import 'package:self_improvement/core/analysis/data/analysis_data_source.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Inserts synthetic fact rows with valid constraints for the analysis data
/// tests. Rows are written directly (no commands): the analysis reads the
/// stored facts, the frozen `local_date` columns decide the day.
class AnalysisDb {
  AnalysisDb(this.harness);

  final DataHarness harness;

  AppDatabase get db => harness.database;

  DateTime get _now => harness.clock.nowUtc();

  /// A plausible instant on [date] (10:00 UTC plus [minute] minutes). The
  /// analysis never uses it for the day: only `local_date` counts.
  DateTime at(LocalDate date, {int minute = 0}) =>
      DateTime.utc(date.year, date.month, date.day, 10, minute);

  static const String zone = 'Europe/Berlin';

  Future<void> steps(LocalDate date, int steps, {bool deleted = false}) => db
      .into(db.stepDays)
      .insert(
        StepDaysCompanion.insert(
          id: harness.ids.newId(),
          localDate: date,
          steps: steps,
          timezoneId: zone,
          deletedAtUtc: Value(deleted ? _now : null),
          createdAtUtc: _now,
          updatedAtUtc: _now,
        ),
      );

  Future<void> water(
    LocalDate date,
    int ml, {
    DateTime? occurredAt,
    bool deleted = false,
  }) => db
      .into(db.waterEntries)
      .insert(
        WaterEntriesCompanion.insert(
          id: harness.ids.newId(),
          amountMl: ml,
          occurredAtUtc: occurredAt ?? at(date),
          localDate: date,
          timezoneId: zone,
          gamificationEligible: true,
          deletedAtUtc: Value(deleted ? _now : null),
          createdAtUtc: _now,
          updatedAtUtc: _now,
        ),
      );

  /// A weight measurement; [occurredAt] decides which one is the LAST of the
  /// day (a unique active time per measurement is required by the schema).
  Future<void> weight(
    LocalDate date,
    int grams, {
    DateTime? occurredAt,
    bool deleted = false,
  }) => db
      .into(db.weightEntries)
      .insert(
        WeightEntriesCompanion.insert(
          id: harness.ids.newId(),
          weightGrams: grams,
          occurredAtUtc: occurredAt ?? at(date),
          localDate: date,
          timezoneId: zone,
          gamificationEligible: true,
          deletedAtUtc: Value(deleted ? _now : null),
          createdAtUtc: _now,
          updatedAtUtc: _now,
        ),
      );

  Future<void> workout(
    LocalDate date,
    int minutes, {
    DateTime? occurredAt,
    bool deleted = false,
  }) => db
      .into(db.workoutEntries)
      .insert(
        WorkoutEntriesCompanion.insert(
          id: harness.ids.newId(),
          trainingCategory: 'cardio',
          durationMinutes: minutes,
          occurredAtUtc: occurredAt ?? at(date),
          localDate: date,
          timezoneId: zone,
          gamificationEligible: true,
          deletedAtUtc: Value(deleted ? _now : null),
          createdAtUtc: _now,
          updatedAtUtc: _now,
        ),
      );

  /// A focus session. [status] `completed` needs [completedOn]; every other
  /// status must not have one (schema checks). At most one session may be
  /// open (`running`, `paused`, `awaiting_confirmation`).
  Future<void> focus({
    required int seconds,
    LocalDate? completedOn,
    String status = 'completed',
    bool deleted = false,
    DateTime? startedAt,
  }) {
    final planned = seconds < 300 ? 300 : seconds;
    return db
        .into(db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            id: harness.ids.newId(),
            category: 'reading',
            plannedSeconds: planned,
            accumulatedSeconds: Value(seconds),
            startedAtUtc: startedAt ?? _now,
            endedAtUtc: Value(status == 'paused' ? null : _now),
            completedLocalDate: Value(
              status == 'completed' ? completedOn : null,
            ),
            timezoneId: zone,
            status: status,
            deletedAtUtc: Value(deleted ? _now : null),
            createdAtUtc: _now,
            updatedAtUtc: _now,
          ),
        );
  }

  /// A task; [completedOn] `null` is an open task (also a reopened one).
  Future<void> task({LocalDate? completedOn, bool deleted = false}) => db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: harness.ids.newId(),
          title: 'Aufgabe',
          completedAtUtc: Value(completedOn == null ? null : at(completedOn)),
          completedLocalDate: Value(completedOn),
          timezoneId: Value(completedOn == null ? null : zone),
          completionEligibility: Value(completedOn == null ? null : true),
          deletedAtUtc: Value(deleted ? _now : null),
          createdAtUtc: _now,
          updatedAtUtc: _now,
        ),
      );

  Future<void> meal(LocalDate date, {int? kcal, bool deleted = false}) => db
      .into(db.mealEntries)
      .insert(
        MealEntriesCompanion.insert(
          id: harness.ids.newId(),
          name: 'Mahlzeit',
          kcal: Value(kcal),
          occurredAtUtc: at(date),
          localDate: date,
          timezoneId: zone,
          deletedAtUtc: Value(deleted ? _now : null),
          createdAtUtc: _now,
          updatedAtUtc: _now,
        ),
      );

  Future<String> habit(
    LocalDate startedOn, {
    LocalDate? archivedFrom,
    String? id,
  }) async {
    final habitId = id ?? harness.ids.newId();
    await db
        .into(db.habits)
        .insert(
          HabitsCompanion.insert(
            id: habitId,
            title: 'Gewohnheit',
            startedLocalDate: startedOn,
            archivedFromDate: Value(archivedFrom),
            createdAtUtc: _now,
            updatedAtUtc: _now,
          ),
        );
    return habitId;
  }

  Future<void> habitCheck(String habitId, LocalDate date) => db
      .into(db.habitChecks)
      .insert(
        HabitChecksCompanion.insert(
          id: harness.ids.newId(),
          habitId: habitId,
          localDate: date,
          checkedAtUtc: at(date),
          timezoneId: zone,
          eligibility: true,
          createdAtUtc: _now,
          updatedAtUtc: _now,
        ),
      );

  /// Soft-deletes (or restores with `false`) a habit like the habit delete
  /// command and its undo do.
  Future<void> setHabitDeleted(String habitId, {required bool deleted}) =>
      (db.update(db.habits)..where((h) => h.id.equals(habitId))).write(
        HabitsCompanion(deletedAtUtc: Value(deleted ? _now : null)),
      );

  /// Appends a module status change.
  Future<void> moduleStatus(
    ModuleId module,
    LocalDate date,
    bool enabled, {
    required DateTime effectiveAt,
  }) => db
      .into(db.moduleStatusHistory)
      .insert(
        ModuleStatusHistoryCompanion.insert(
          id: harness.ids.newId(),
          moduleId: module.key,
          effectiveAtUtc: effectiveAt,
          localDate: date,
          enabled: enabled,
        ),
      );

  /// Adds a goal version (changes apply from [effectiveFrom] on).
  Future<void> goalVersion(
    GoalType type,
    LocalDate effectiveFrom, {
    int? target,
    bool enabled = true,
  }) => db
      .into(db.goalVersions)
      .insert(
        GoalVersionsCompanion.insert(
          id: harness.ids.newId(),
          goalType: type.key,
          targetInteger: Value(target),
          enabled: enabled,
          effectiveFromDate: effectiveFrom,
          createdAtUtc: _now,
        ),
      );

  /// A data source over the harness database.
  AnalysisDataSource source() => AnalysisDataSource(
    database: db,
    dayStatus: harness.dayStatusRepository(),
  );
}
