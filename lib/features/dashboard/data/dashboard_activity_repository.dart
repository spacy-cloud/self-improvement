import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/reactive.dart';

/// Answers one question for the dashboard: has the user recorded anything yet?
///
/// It is only used to show the welcome hint on the first day; every number on
/// the dashboard comes from the module cards and the day status. Deleted
/// records do not count, and neither does a discarded focus session.
class DashboardActivityRepository {
  DashboardActivityRepository(this._database);

  final AppDatabase _database;

  /// Tables the answer depends on.
  List<ResultSetImplementation<dynamic, dynamic>> get _tables => [
    _database.waterEntries,
    _database.weightEntries,
    _database.stepDays,
    _database.mealEntries,
    _database.workoutEntries,
    _database.focusSessions,
    _database.tasks,
    _database.habits,
  ];

  /// Re-emits whenever one of the record tables changes.
  Stream<bool> watchHasAnyEntry() =>
      watchComputed(_database, _tables, hasAnyEntry);

  /// True when at least one record of any module exists.
  Future<bool> hasAnyEntry() async {
    final row = await _database
        .customSelect(
          'SELECT 1 AS hit WHERE '
          'EXISTS (SELECT 1 FROM water_entries WHERE deleted_at_utc IS NULL) OR '
          'EXISTS (SELECT 1 FROM weight_entries WHERE deleted_at_utc IS NULL) OR '
          'EXISTS (SELECT 1 FROM step_days WHERE deleted_at_utc IS NULL) OR '
          'EXISTS (SELECT 1 FROM meal_entries WHERE deleted_at_utc IS NULL) OR '
          'EXISTS (SELECT 1 FROM workout_entries WHERE deleted_at_utc IS NULL) OR '
          "EXISTS (SELECT 1 FROM focus_sessions WHERE deleted_at_utc IS NULL AND status <> 'discarded') OR "
          'EXISTS (SELECT 1 FROM tasks WHERE deleted_at_utc IS NULL) OR '
          'EXISTS (SELECT 1 FROM habits WHERE deleted_at_utc IS NULL)',
        )
        .getSingleOrNull();
    return row != null;
  }
}
