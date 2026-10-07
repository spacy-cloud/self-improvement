import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Aggregates the stored facts per local day for goal fulfilment.
///
/// One grouped query per fact table over a date range (no per-row work in
/// Dart): water sum, step total (a recorded 0 differs from no record), weight
/// entry count, completed focus seconds on the completion day, tasks completed
/// that day, which habits were checked (only active habits count), the
/// workouts of the day and its rest or skipped mark. Soft deleted rows never
/// count.
class DayFactsSource {
  DayFactsSource(this._database);

  final AppDatabase _database;

  /// Tables whose changes invalidate [factsBetween].
  List<ResultSetImplementation<dynamic, dynamic>> get tables => [
    _database.waterEntries,
    _database.stepDays,
    _database.weightEntries,
    _database.focusSessions,
    _database.tasks,
    _database.habitChecks,
    _database.habits,
    _database.workoutEntries,
    _database.workoutDayMarks,
  ];

  /// Facts for every day in `[from, to]` that has at least one fact. Days
  /// without any fact are absent (callers use [emptyFacts]).
  Future<Map<LocalDate, DayFacts>> factsBetween(
    LocalDate from,
    LocalDate to,
  ) async {
    final start = from.toIso();
    final end = to.toIso();
    final water = <LocalDate, int>{};
    final steps = <LocalDate, int>{};
    final weights = <LocalDate, int>{};
    final focus = <LocalDate, int>{};
    final tasks = <LocalDate, int>{};
    final habits = <LocalDate, Set<String>>{};
    final workouts = <LocalDate, int>{};
    final marks = <LocalDate, WorkoutDayMarkKind>{};

    Future<void> grouped(
      String sql,
      void Function(LocalDate date, QueryRow row) collect,
    ) async {
      final rows = await _database
          .customSelect(sql, variables: [Variable(start), Variable(end)])
          .get();
      for (final row in rows) {
        collect(LocalDate.parse(row.read<String>('d')), row);
      }
    }

    await grouped(
      'SELECT local_date AS d, SUM(amount_ml) AS v FROM water_entries '
      'WHERE deleted_at_utc IS NULL AND local_date BETWEEN ?1 AND ?2 '
      'GROUP BY local_date',
      (date, row) => water[date] = row.read<int>('v'),
    );
    await grouped(
      'SELECT local_date AS d, steps AS v FROM step_days '
      'WHERE deleted_at_utc IS NULL AND local_date BETWEEN ?1 AND ?2',
      (date, row) => steps[date] = row.read<int>('v'),
    );
    await grouped(
      'SELECT local_date AS d, COUNT(*) AS v FROM weight_entries '
      'WHERE deleted_at_utc IS NULL AND local_date BETWEEN ?1 AND ?2 '
      'GROUP BY local_date',
      (date, row) => weights[date] = row.read<int>('v'),
    );
    await grouped(
      'SELECT completed_local_date AS d, SUM(accumulated_seconds) AS v '
      "FROM focus_sessions WHERE status = 'completed' "
      'AND deleted_at_utc IS NULL '
      'AND completed_local_date BETWEEN ?1 AND ?2 '
      'GROUP BY completed_local_date',
      (date, row) => focus[date] = row.read<int>('v'),
    );
    await grouped(
      'SELECT completed_local_date AS d, COUNT(*) AS v FROM tasks '
      'WHERE completed_at_utc IS NOT NULL AND deleted_at_utc IS NULL '
      'AND completed_local_date BETWEEN ?1 AND ?2 '
      'GROUP BY completed_local_date',
      (date, row) => tasks[date] = row.read<int>('v'),
    );
    await grouped(
      'SELECT c.local_date AS d, c.habit_id AS h FROM habit_checks c '
      'JOIN habits h ON h.id = c.habit_id '
      'WHERE c.deleted_at_utc IS NULL AND h.deleted_at_utc IS NULL '
      'AND c.local_date BETWEEN ?1 AND ?2',
      (date, row) =>
          habits.putIfAbsent(date, () => <String>{}).add(row.read<String>('h')),
    );

    await grouped(
      'SELECT local_date AS d, COUNT(*) AS v FROM workout_entries '
      'WHERE deleted_at_utc IS NULL AND local_date BETWEEN ?1 AND ?2 '
      'GROUP BY local_date',
      (date, row) => workouts[date] = row.read<int>('v'),
    );
    await grouped('SELECT local_date AS d, kind AS k FROM workout_day_marks '
        'WHERE deleted_at_utc IS NULL AND local_date BETWEEN ?1 AND ?2', (
      date,
      row,
    ) {
      final kind = WorkoutDayMarkKind.tryParse(row.read<String>('k'));
      if (kind != null) {
        marks[date] = kind;
      }
    });

    final days = <LocalDate>{
      ...water.keys,
      ...steps.keys,
      ...weights.keys,
      ...focus.keys,
      ...tasks.keys,
      ...habits.keys,
      ...workouts.keys,
      ...marks.keys,
    };
    return {
      for (final day in days)
        day: DayFacts(
          date: day,
          waterMl: water[day] ?? 0,
          stepsRecorded: steps[day],
          weightEntries: weights[day] ?? 0,
          focusCompletedSeconds: focus[day] ?? 0,
          tasksCompleted: tasks[day] ?? 0,
          habitIdsChecked: habits[day] ?? const {},
          workoutEntries: workouts[day] ?? 0,
          workoutDayMark: marks[day],
        ),
    };
  }

  /// Facts of a single day (empty facts when nothing was recorded).
  Future<DayFacts> factsFor(LocalDate day) async {
    final map = await factsBetween(day, day);
    return map[day] ?? emptyFacts(day);
  }

  /// Facts of a day without any record.
  static DayFacts emptyFacts(LocalDate day) => DayFacts(
    date: day,
    waterMl: 0,
    stepsRecorded: null,
    weightEntries: 0,
    focusCompletedSeconds: 0,
    tasksCompleted: 0,
    habitIdsChecked: const {},
    workoutEntries: 0,
    workoutDayMark: null,
  );
}
