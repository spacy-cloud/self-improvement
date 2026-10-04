/// Groups of the list of all workouts: one group per calendar week, Monday to
/// Sunday (pure).
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The workouts of one week (Monday to Sunday of the frozen local dates).
@immutable
final class WorkoutWeekGroup {
  const WorkoutWeekGroup({required this.weekStart, required this.entries});

  /// The Monday of the week.
  final LocalDate weekStart;

  /// Newest first (the order they were given in).
  final List<WorkoutEntry> entries;

  /// The Sunday of the week.
  LocalDate get weekEnd => weekStart.addDays(6);

  int get totalMinutes =>
      entries.fold(0, (sum, entry) => sum + entry.durationMinutes);
}

/// Groups [entriesNewestFirst] by the week of their local date, newest week
/// first. Within a week the given order is kept.
List<WorkoutWeekGroup> groupWorkoutsByWeek(
  Iterable<WorkoutEntry> entriesNewestFirst,
) {
  final byWeek = <LocalDate, List<WorkoutEntry>>{};
  for (final entry in entriesNewestFirst) {
    byWeek.putIfAbsent(entry.localDate.startOfWeek, () => []).add(entry);
  }
  final weeks = byWeek.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final week in weeks)
      WorkoutWeekGroup(
        weekStart: week,
        entries: List.unmodifiable(byWeek[week]!),
      ),
  ];
}
