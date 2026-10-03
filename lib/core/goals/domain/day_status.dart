import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/goals/domain/day_snapshot.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Aggregated activity of one local day, computed from active records only
/// (never from stored "fulfilled" flags).
///
/// Aggregates the data layer queries for the day [date] (stored local dates,
/// soft-deleted records excluded):
/// - water: sum of active water entry amounts in ml,
/// - steps: the step day value, or `null` when no step record exists (a
///   recorded 0 is a value),
/// - weight: count of active weight entries,
/// - focus: sum of `accumulated_seconds` of completed sessions whose completion
///   day is [date] (aborted and discarded sessions excluded),
/// - tasks: count of tasks whose current completion happened on [date],
/// - habits: ids of habits with an active check on [date].
@immutable
final class DayFacts {
  const DayFacts({
    required this.date,
    this.waterMl = 0,
    this.stepsRecorded,
    this.weightEntries = 0,
    this.focusCompletedSeconds = 0,
    this.tasksCompleted = 0,
    this.habitIdsChecked = const <String>{},
  });

  final LocalDate date;
  final int waterMl;

  /// `null` means "no record for this day"; 0 is a recorded value.
  final int? stepsRecorded;
  final int weightEntries;
  final int focusCompletedSeconds;
  final int tasksCompleted;
  final Set<String> habitIdsChecked;
}

/// Progress of one goal of a day.
@immutable
final class GoalProgress {
  const GoalProgress({
    required this.goalKey,
    required this.module,
    required this.target,
    required this.applicable,
    required this.fulfilled,
    required this.current,
  });

  final String goalKey;
  final ModuleId module;

  /// The frozen threshold in goal units (ml, steps, minutes, 1 for the on/off
  /// goals); `null` for habits.
  final int? target;

  /// Whether the goal counts on this day.
  final bool applicable;

  /// Whether the goal is reached. Only an applicable goal can be fulfilled.
  final bool fulfilled;

  /// The day's value in the unit of [target]: ml, steps (`null` without a
  /// record), entries, whole completed focus minutes, completed tasks, or
  /// 1 / 0 for a checked / unchecked habit.
  final int? current;
}

/// The evaluated day: per-goal progress plus the two day classifications.
///
/// "Active" and "complete" are deliberately separate: a day is active for the
/// streak when at least one applicable goal is fulfilled, and complete for the
/// analysis when it has applicable goals and all of them are fulfilled.
@immutable
final class DayStatus {
  DayStatus({required this.date, required List<GoalProgress> goals})
    : goals = List.unmodifiable(goals),
      applicableCount = goals.where((goal) => goal.applicable).length,
      fulfilledCount = goals
          .where((goal) => goal.applicable && goal.fulfilled)
          .length;

  final LocalDate date;

  /// All goals of the snapshot in snapshot order (not applicable ones too).
  final List<GoalProgress> goals;

  final int applicableCount;
  final int fulfilledCount;

  /// Whether the day counts for the streak: at least one applicable goal is
  /// fulfilled. Without applicable goals a day is never active.
  bool get isActive => fulfilledCount >= 1;

  /// Whether the day counts as a complete day for the analysis: there is at
  /// least one applicable goal and all applicable goals are fulfilled.
  bool get isComplete =>
      applicableCount >= 1 && fulfilledCount == applicableCount;

  /// Whether the day has applicable goals; without them the UI shows an empty
  /// state ("no daily goals yet") and never a 0/0 ring.
  bool get hasApplicableGoals => applicableCount >= 1;

  /// `fulfilledCount / applicableCount` in 0..1, `null` without applicable
  /// goals.
  double? get ringFraction =>
      applicableCount == 0 ? null : fulfilledCount / applicableCount;
}

/// Evaluates [snapshot] against the [facts] of the same day.
///
/// Rules: water sum >= target; steps recorded and value >= target; weight
/// entries >= 1; completed focus seconds >= target minutes * 60; completed
/// tasks >= 1; habit checked. A goal that is not applicable in the snapshot
/// never counts. Snapshot items that are neither a daily goal type nor a habit
/// (for example the weekly workout goal or an unknown key) are ignored.
DayStatus computeDayStatus(DaySnapshot snapshot, DayFacts facts) {
  assert(
    snapshot.date == facts.date,
    'Snapshot and facts must describe the same day',
  );
  final goals = <GoalProgress>[];
  for (final item in snapshot.items) {
    final progress = _progressOf(item, facts);
    if (progress != null) {
      goals.add(progress);
    }
  }
  return DayStatus(date: snapshot.date, goals: goals);
}

GoalProgress? _progressOf(GoalSnapshotItem item, DayFacts facts) {
  final habitId = item.habitId;
  if (habitId != null) {
    final checked = facts.habitIdsChecked.contains(habitId);
    return GoalProgress(
      goalKey: item.goalKey,
      module: item.module,
      target: null,
      applicable: item.applicable,
      fulfilled: item.applicable && checked,
      current: checked ? 1 : 0,
    );
  }
  final type = item.type;
  if (type == null || !type.isDaily) {
    return null;
  }
  final target = type.resolveTarget(item.target);
  final steps = facts.stepsRecorded;
  final (int? current, bool reached) = switch (type) {
    GoalType.water => (facts.waterMl, facts.waterMl >= target),
    GoalType.steps => (steps, steps != null && steps >= target),
    GoalType.weightEntry => (
      facts.weightEntries,
      facts.weightEntries >= target,
    ),
    GoalType.focusMinutes => (
      facts.focusCompletedSeconds ~/ 60,
      facts.focusCompletedSeconds >= target * 60,
    ),
    GoalType.taskCompletion => (
      facts.tasksCompleted,
      facts.tasksCompleted >= target,
    ),
    // Filtered out above (not a daily goal); listed for exhaustiveness.
    GoalType.workoutWeekly => (null, false),
  };
  return GoalProgress(
    goalKey: item.goalKey,
    module: item.module,
    target: target,
    applicable: item.applicable,
    fulfilled: item.applicable && reached,
    current: current,
  );
}
