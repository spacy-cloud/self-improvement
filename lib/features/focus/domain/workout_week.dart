/// The weekly workout view: Monday to Sunday count, minutes, weekly target and
/// the latest workout (pure; specification section 8.3).
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Shown on the dashboard when no workout exists in the current week.
const String workoutNoEntryThisWeekMessage = 'Noch kein Workout diese Woche';

/// The weekly workout target (1 to 14 entries, default 3) that applies on
/// [day]: the goal version in effect, or the default.
///
/// The weekly target has no on/off switch (it is not a daily goal); a stored
/// `enabled` flag is ignored. The result is kept within the valid range.
int workoutWeeklyTargetOn(Iterable<GoalVersion> versions, LocalDate day) {
  final goal = effectiveGoalOrDefault(versions, GoalType.workoutWeekly, day);
  return GoalType.workoutWeekly
      .resolveTarget(goal.target)
      .clamp(
        GoalType.workoutWeekly.minTarget,
        GoalType.workoutWeekly.maxTarget,
      );
}

/// This week's workouts (Monday to Sunday, local dates as stored) and the
/// progress towards the weekly target.
@immutable
final class WorkoutWeekSummary {
  const WorkoutWeekSummary({
    required this.weekStart,
    required this.entryCount,
    required this.totalMinutes,
    required this.weeklyTarget,
    this.latest,
  });

  /// The Monday of the week.
  final LocalDate weekStart;

  /// The real number of workouts this week (never capped).
  final int entryCount;

  /// The sum of the durations this week in minutes. Workouts are not focus
  /// time; this value is separate from the focus summary.
  final int totalMinutes;

  /// Entries per week to reach (1 to 14, default 3).
  final int weeklyTarget;

  /// The most recent workout of the week, or null: the dashboard then shows
  /// [workoutNoEntryThisWeekMessage].
  final WorkoutEntry? latest;

  /// The Sunday of the week.
  LocalDate get weekEnd => weekStart.addDays(6);

  bool get isEmpty => entryCount == 0;

  /// `entries / target`, capped at 1.0 for the ring; the real count stays in
  /// [entryCount].
  double get ringFraction {
    final fraction = entryCount / weeklyTarget;
    return fraction > 1 ? 1.0 : fraction;
  }

  /// Whether the weekly target is reached or exceeded.
  bool get targetReached => entryCount >= weeklyTarget;

  /// Entries still missing to the target (0 once reached).
  int get remainingToTarget =>
      entryCount >= weeklyTarget ? 0 : weeklyTarget - entryCount;

  /// The text for the latest workout line: its display title, or the "no
  /// workout yet" message.
  String get latestText =>
      latest?.displayTitle ?? workoutNoEntryThisWeekMessage;

  @override
  bool operator ==(Object other) =>
      other is WorkoutWeekSummary &&
      other.weekStart == weekStart &&
      other.entryCount == entryCount &&
      other.totalMinutes == totalMinutes &&
      other.weeklyTarget == weeklyTarget &&
      other.latest == latest;

  @override
  int get hashCode =>
      Object.hash(weekStart, entryCount, totalMinutes, weeklyTarget, latest);
}

/// Builds the summary of the week (Monday to Sunday) containing [today] from
/// [entries] (any entries; only those whose frozen local date lies in the week
/// count). The latest workout is the one with the latest time (ties by id).
WorkoutWeekSummary buildWorkoutWeekSummary({
  required Iterable<WorkoutEntry> entries,
  required LocalDate today,
  required int weeklyTarget,
}) {
  final weekStart = today.startOfWeek;
  final weekEnd = weekStart.addDays(6);
  var count = 0;
  var minutes = 0;
  WorkoutEntry? latest;
  for (final entry in entries) {
    if (entry.localDate < weekStart || entry.localDate > weekEnd) {
      continue;
    }
    count++;
    minutes += entry.durationMinutes;
    if (latest == null || _isLater(entry, latest)) {
      latest = entry;
    }
  }
  return WorkoutWeekSummary(
    weekStart: weekStart,
    entryCount: count,
    totalMinutes: minutes,
    weeklyTarget: weeklyTarget,
    latest: latest,
  );
}

bool _isLater(WorkoutEntry a, WorkoutEntry b) {
  final byTime = a.occurredAtUtc.compareTo(b.occurredAtUtc);
  return byTime != 0 ? byTime > 0 : a.id.compareTo(b.id) > 0;
}
