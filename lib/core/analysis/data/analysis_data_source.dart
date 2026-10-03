import 'package:drift/drift.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/analysis/domain/workout_week.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/goals/data/day_facts_source.dart';
import 'package:self_improvement/core/goals/data/day_status_repository.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/domain/goal_keys.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_status_repository.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The raw inputs of one analysis report, as loaded from the database.
///
/// A value object with equality: the repository only rebuilds the report when
/// the inputs really changed.
final class AnalysisInputs {
  AnalysisInputs({
    required this.period,
    required this.usageStart,
    required Set<ModuleId> activeModules,
    required List<AnalysisDay> days,
    required this.workoutWeeklyTarget,
    required this.hasApplicableGoalEver,
  }) : activeModules = Set.unmodifiable(activeModules),
       days = List.unmodifiable(days);

  final AnalysisPeriodSpec period;

  /// The profile start date, `null` before the profile exists.
  final LocalDate? usageStart;

  /// The modules that are active right now.
  final Set<ModuleId> activeModules;

  /// One entry per day of `[period.windowStart, period.today]`, oldest first.
  final List<AnalysisDay> days;

  /// The weekly workout target in effect today; `null` when the weekly goal
  /// is switched off.
  final int? workoutWeeklyTarget;

  /// Whether any live goal ever applied on a stored day.
  final bool hasApplicableGoalEver;

  /// Builds the report from these inputs (pure).
  AnalysisReport toReport() => buildAnalysisReport(
    period: period,
    days: days,
    usageStart: usageStart,
    activeModules: activeModules,
    workoutWeeklyTarget: workoutWeeklyTarget,
    hasApplicableGoalEver: hasApplicableGoalEver,
  );

  @override
  bool operator ==(Object other) {
    if (other is! AnalysisInputs ||
        other.period != period ||
        other.usageStart != usageStart ||
        other.workoutWeeklyTarget != workoutWeeklyTarget ||
        other.hasApplicableGoalEver != hasApplicableGoalEver ||
        other.activeModules.length != activeModules.length ||
        !other.activeModules.containsAll(activeModules) ||
        other.days.length != days.length) {
      return false;
    }
    for (var i = 0; i < days.length; i++) {
      if (other.days[i] != days[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    period,
    usageStart,
    workoutWeeklyTarget,
    hasApplicableGoalEver,
    Object.hashAllUnordered(activeModules),
    Object.hashAll(days),
  );
}

/// The inputs of the workout week card alone (see
/// `AnalysisDataSource.loadWorkoutWeek`).
final class WorkoutWeekInputs {
  WorkoutWeekInputs({
    required this.today,
    required this.usageStart,
    required List<AnalysisDay> days,
    required this.weeklyTarget,
  }) : days = List.unmodifiable(days);

  final LocalDate today;
  final LocalDate? usageStart;

  /// One entry per day of `[today - 13, today]` with the workout figures.
  final List<AnalysisDay> days;

  final int? weeklyTarget;

  @override
  bool operator ==(Object other) {
    if (other is! WorkoutWeekInputs ||
        other.today != today ||
        other.usageStart != usageStart ||
        other.weeklyTarget != weeklyTarget ||
        other.days.length != days.length) {
      return false;
    }
    for (var i = 0; i < days.length; i++) {
      if (other.days[i] != days[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(today, usageStart, weeklyTarget, Object.hashAll(days));
}

/// Loads the per-day inputs of the analysis.
///
/// One grouped SQL query per fact table over the combined range
/// `[today - 2N + 1, today]` (no per-row work in Dart), plus the day statuses
/// of the goal engine, the module statuses, the profile start and the goal
/// versions for the workout target. Business dates are the frozen `local_date`
/// columns; soft-deleted rows never count.
///
/// - **Steps**: the active step record of the day (a recorded 0 is a value).
/// - **Water**: sum and number of the active entries.
/// - **Weight**: the LAST measurement of the day (by measurement time).
/// - **Workouts**: number and minutes of the active entries.
/// - **Focus**: completed sessions only, by their completion date.
/// - **Tasks**: tasks whose current completion date is the day.
/// - **Meals**: number, number with kcal and the sum of the known kcal.
/// - **Goals and habits**: from `DayStatusRepository.statusesBetween`, the
///   same day statuses as the ring and the streak. Habits that are not live
///   (soft-deleted) are left out completely: deleting a habit means it never
///   existed for the statistics, it counts neither as an applicable or
///   fulfilled habit-day nor as an unfulfilled goal of a complete day. Undoing
///   the deletion brings them back.
class AnalysisDataSource {
  AnalysisDataSource({required this._database, required this._dayStatus});

  final AppDatabase _database;
  final DayStatusRepository _dayStatus;

  /// The tables whose changes invalidate the analysis.
  List<ResultSetImplementation<dynamic, dynamic>> get tables => [
    // water, steps, weight, focus sessions, tasks, habit checks and habits
    ...DayFactsSource(_database).tables,
    _database.workoutEntries,
    _database.mealEntries,
    _database.dailyGoalSnapshots,
    _database.goalVersions,
    _database.moduleStatusHistory,
    _database.profile,
  ];

  /// The tables whose changes invalidate the workout week card.
  List<ResultSetImplementation<dynamic, dynamic>> get workoutWeekTables => [
    _database.workoutEntries,
    _database.goalVersions,
    _database.profile,
  ];

  /// Loads everything for [period].
  Future<AnalysisInputs> load(AnalysisPeriodSpec period) async {
    final from = period.windowStart;
    final to = period.today;
    final range = _Range(from, to);

    final steps = <LocalDate, int>{};
    final water = <LocalDate, ({int ml, int entries})>{};
    final weight = <LocalDate, int>{};
    final workouts = <LocalDate, ({int entries, int minutes})>{};
    final focus = <LocalDate, ({int sessions, int seconds})>{};
    final tasks = <LocalDate, int>{};
    final meals = <LocalDate, ({int meals, int withKcal, int kcal})>{};

    await _grouped(
      range,
      'SELECT local_date AS d, steps AS v FROM step_days '
      'WHERE deleted_at_utc IS NULL AND local_date BETWEEN ?1 AND ?2',
      (date, row) => steps[date] = row.read<int>('v'),
    );
    await _grouped(
      range,
      'SELECT local_date AS d, SUM(amount_ml) AS ml, COUNT(*) AS n '
      'FROM water_entries '
      'WHERE deleted_at_utc IS NULL AND local_date BETWEEN ?1 AND ?2 '
      'GROUP BY local_date',
      (date, row) =>
          water[date] = (ml: row.read<int>('ml'), entries: row.read<int>('n')),
    );
    // SQLite returns the bare column of the row that has the maximum, so
    // `weight_grams` is the value of the last measurement of the day.
    await _grouped(
      range,
      'SELECT local_date AS d, weight_grams AS g, MAX(occurred_at_utc) AS t '
      'FROM weight_entries '
      'WHERE deleted_at_utc IS NULL AND local_date BETWEEN ?1 AND ?2 '
      'GROUP BY local_date',
      (date, row) => weight[date] = row.read<int>('g'),
    );
    await _groupedWorkouts(range, workouts);
    await _grouped(
      range,
      'SELECT completed_local_date AS d, COUNT(*) AS n, '
      'SUM(accumulated_seconds) AS s FROM focus_sessions '
      "WHERE status = 'completed' AND deleted_at_utc IS NULL "
      'AND completed_local_date BETWEEN ?1 AND ?2 '
      'GROUP BY completed_local_date',
      (date, row) => focus[date] = (
        sessions: row.read<int>('n'),
        seconds: row.read<int>('s'),
      ),
    );
    await _grouped(
      range,
      'SELECT completed_local_date AS d, COUNT(*) AS n FROM tasks '
      'WHERE completed_at_utc IS NOT NULL AND deleted_at_utc IS NULL '
      'AND completed_local_date BETWEEN ?1 AND ?2 '
      'GROUP BY completed_local_date',
      (date, row) => tasks[date] = row.read<int>('n'),
    );
    await _grouped(
      range,
      'SELECT local_date AS d, COUNT(*) AS n, COUNT(kcal) AS k, '
      'COALESCE(SUM(kcal), 0) AS kcal FROM meal_entries '
      'WHERE deleted_at_utc IS NULL AND local_date BETWEEN ?1 AND ?2 '
      'GROUP BY local_date',
      (date, row) => meals[date] = (
        meals: row.read<int>('n'),
        withKcal: row.read<int>('k'),
        kcal: row.read<int>('kcal'),
      ),
    );

    final liveHabitIds = await _liveHabitIds();
    final statuses = await _dayStatus.statusesBetween(from, to);

    final days = <AnalysisDay>[];
    for (final date in from.rangeTo(to)) {
      var applicable = 0;
      var fulfilled = 0;
      var habitsApplicable = 0;
      var habitsFulfilled = 0;
      final status = statuses[date];
      if (status != null) {
        for (final goal in status.goals) {
          final habitId = habitIdFromKey(goal.goalKey);
          if (habitId != null && !liveHabitIds.contains(habitId)) {
            continue;
          }
          if (!goal.applicable) {
            continue;
          }
          applicable++;
          if (goal.fulfilled) {
            fulfilled++;
          }
          if (habitId != null) {
            habitsApplicable++;
            if (goal.fulfilled) {
              habitsFulfilled++;
            }
          }
        }
      }
      final waterDay = water[date];
      final workoutDay = workouts[date];
      final focusDay = focus[date];
      final mealDay = meals[date];
      days.add(
        AnalysisDay(
          date: date,
          stepsRecorded: steps[date],
          waterMl: waterDay?.ml ?? 0,
          waterEntries: waterDay?.entries ?? 0,
          weightGrams: weight[date],
          workoutEntries: workoutDay?.entries ?? 0,
          workoutMinutes: workoutDay?.minutes ?? 0,
          focusCompletedSeconds: focusDay?.seconds ?? 0,
          focusCompletedSessions: focusDay?.sessions ?? 0,
          tasksCompleted: tasks[date] ?? 0,
          mealEntries: mealDay?.meals ?? 0,
          mealsWithKcal: mealDay?.withKcal ?? 0,
          knownKcal: mealDay?.kcal ?? 0,
          applicableGoals: applicable,
          fulfilledGoals: fulfilled,
          applicableHabits: habitsApplicable,
          fulfilledHabits: habitsFulfilled,
        ),
      );
    }

    final moduleStatuses = await ModuleStatusRepository(_database).statuses();
    return AnalysisInputs(
      period: period,
      usageStart: await _usageStart(),
      activeModules: {
        for (final entry in moduleStatuses.entries)
          if (entry.value) entry.key,
      },
      days: days,
      workoutWeeklyTarget: await _workoutWeeklyTarget(to),
      hasApplicableGoalEver: await _hasApplicableGoalEver(),
    );
  }

  /// Loads the inputs of the workout week card of [today]: the workout days of
  /// `[today - 13, today]` (this week to date and the same weekdays of the
  /// previous week), the weekly target and the usage start.
  Future<WorkoutWeekInputs> loadWorkoutWeek(LocalDate today) async {
    final from = today.addDays(-13);
    final workouts = <LocalDate, ({int entries, int minutes})>{};
    await _groupedWorkouts(_Range(from, today), workouts);
    return WorkoutWeekInputs(
      today: today,
      usageStart: await _usageStart(),
      days: [
        for (final date in from.rangeTo(today))
          AnalysisDay(
            date: date,
            workoutEntries: workouts[date]?.entries ?? 0,
            workoutMinutes: workouts[date]?.minutes ?? 0,
          ),
      ],
      weeklyTarget: await _workoutWeeklyTarget(today),
    );
  }

  // ---------------------------------------------------------------- helpers

  Future<void> _grouped(
    _Range range,
    String sql,
    void Function(LocalDate date, QueryRow row) collect,
  ) async {
    final rows = await _database
        .customSelect(
          sql,
          variables: [
            Variable<String>(range.from.toIso()),
            Variable<String>(range.to.toIso()),
          ],
        )
        .get();
    for (final row in rows) {
      collect(LocalDate.parse(row.read<String>('d')), row);
    }
  }

  Future<void> _groupedWorkouts(
    _Range range,
    Map<LocalDate, ({int entries, int minutes})> into,
  ) => _grouped(
    range,
    'SELECT local_date AS d, COUNT(*) AS n, SUM(duration_minutes) AS m '
    'FROM workout_entries '
    'WHERE deleted_at_utc IS NULL AND local_date BETWEEN ?1 AND ?2 '
    'GROUP BY local_date',
    (date, row) =>
        into[date] = (entries: row.read<int>('n'), minutes: row.read<int>('m')),
  );

  Future<Set<String>> _liveHabitIds() async {
    final rows = await (_database.select(
      _database.habits,
    )..where((h) => h.deletedAtUtc.isNull())).get();
    return {for (final row in rows) row.id};
  }

  Future<LocalDate?> _usageStart() async {
    final profile = await _database.select(_database.profile).getSingleOrNull();
    return profile?.startedLocalDate;
  }

  /// The weekly workout target in effect on [day]; the default 3 without a
  /// stored version, `null` when the stored version switches the goal off.
  Future<int?> _workoutWeeklyTarget(LocalDate day) async {
    final versions = await GoalVersionRepository(_database).all();
    final version = resolveGoalVersion(versions, GoalType.workoutWeekly, day);
    if (version == null) {
      return defaultWorkoutWeeklyTarget;
    }
    return version.enabled
        ? GoalType.workoutWeekly.resolveTarget(version.target)
        : null;
  }

  /// Whether any stored snapshot item applies. Items of habits that are not
  /// live (soft-deleted) do not count.
  Future<bool> _hasApplicableGoalEver() async {
    final rows = await _database
        .customSelect(
          'SELECT EXISTS ('
          'SELECT 1 FROM daily_goal_snapshots s WHERE s.applicable = 1 '
          "AND (substr(s.goal_key, 1, 6) <> 'habit:' "
          'OR substr(s.goal_key, 7) IN '
          '(SELECT id FROM habits WHERE deleted_at_utc IS NULL))'
          ') AS e',
        )
        .get();
    return rows.single.read<int>('e') == 1;
  }
}

class _Range {
  const _Range(this.from, this.to);

  final LocalDate from;
  final LocalDate to;
}
