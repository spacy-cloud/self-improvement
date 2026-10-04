/// "Zuletzt trainiert": when each muscle group was trained last (pure).
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

/// How many days back the recency view looks (today included). Groups that
/// were not trained within this window are not listed.
const int muscleRecencyWindowDays = 28;

/// A group counts as "fresh" while it was trained at most this many days ago.
const int muscleFreshDays = 3;

/// The last training day of one muscle group.
@immutable
final class MuscleRecency {
  const MuscleRecency({required this.group, required this.lastTrained});

  final MuscleGroup group;
  final LocalDate lastTrained;

  /// Whole days between the last training and [today] (0 = today).
  int daysAgo(LocalDate today) => lastTrained.daysUntil(today);

  /// Whether the group was trained recently.
  bool isFresh(LocalDate today) => daysAgo(today) <= muscleFreshDays;

  @override
  bool operator ==(Object other) =>
      other is MuscleRecency &&
      other.group == group &&
      other.lastTrained == lastTrained;

  @override
  int get hashCode => Object.hash(group, lastTrained);
}

/// The groups named by [entries] with their latest training day, most recently
/// trained first (ties in the canonical group order). Only entries within the
/// [muscleRecencyWindowDays] before [today] count; a group without a muscle
/// selection in any entry is not listed (nothing is guessed).
List<MuscleRecency> buildMuscleRecency(
  Iterable<WorkoutEntry> entries,
  LocalDate today,
) {
  final earliest = today.addDays(-(muscleRecencyWindowDays - 1));
  final latest = <MuscleGroup, LocalDate>{};
  for (final entry in entries) {
    final date = entry.localDate;
    if (date < earliest || date > today) {
      continue;
    }
    for (final group in entry.muscleGroups) {
      final known = latest[group];
      if (known == null || date > known) {
        latest[group] = date;
      }
    }
  }
  final result = [
    for (final group in MuscleGroup.values)
      if (latest.containsKey(group))
        MuscleRecency(group: group, lastTrained: latest[group]!),
  ];
  // List.sort is not stable: compare the canonical index as the tie breaker.
  result.sort((a, b) {
    final byDate = b.lastTrained.compareTo(a.lastTrained);
    return byDate != 0 ? byDate : a.group.index.compareTo(b.group.index);
  });
  return result;
}
