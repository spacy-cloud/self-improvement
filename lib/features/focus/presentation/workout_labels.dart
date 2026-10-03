/// German texts of the workout screens that are derived from data (pure Dart:
/// no Flutter import, trivially unit-testable).
library;

import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/muscle_recency.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Second line of a row in the overview: `Kraft · 60 Min. · Mittel`. The
/// intensity is only named when one was chosen.
String workoutMetaLine(WorkoutEntry entry) => [
  entry.category.label,
  '${entry.durationMinutes} Min.',
  ?entry.intensity?.label,
].join(' · ');

/// Second line of a row in the list of all workouts:
/// `Mo., 14. Sep. · Kraft · Mittel`.
String workoutListSubtitle(WorkoutEntry entry, LocalDate today) => [
  formatDateShort(entry.localDate, contextYear: today.year),
  entry.category.label,
  ?entry.intensity?.label,
].join(' · ');

/// The wall clock time of a workout in the zone it was logged in (`17:30`).
String workoutTime(ClockService clock, WorkoutEntry entry) => clock
    .toLocal(entry.occurredAtUtc, timeZoneId: entry.timezoneId)
    .time
    .toIso();

/// Right side of a row in the overview: `Heute · 17:30`, `Donnerstag · 18:10`,
/// `Mo., 7. Sep. · 07:00`.
String workoutWhenText(
  WorkoutEntry entry,
  LocalDate today,
  ClockService clock,
) =>
    '${formatRelativeDay(entry.localDate, today)} · '
    '${workoutTime(clock, entry)}';

/// The selected muscle groups as text (`Brust, Schultern`), or null when none
/// was chosen.
String? muscleGroupsText(List<MuscleGroup> groups) =>
    groups.isEmpty ? null : groups.map((group) => group.label).join(', ');

/// What a screen reader says for a workout row.
String workoutSpoken(WorkoutEntry entry, LocalDate today, ClockService clock) {
  final groups = muscleGroupsText(entry.muscleGroups);
  return [
    entry.displayTitle,
    entry.category.label,
    '${entry.durationMinutes} Minuten',
    ?entry.intensity?.label,
    ?groups,
    '${formatRelativeDay(entry.localDate, today)}, '
        '${workoutTime(clock, entry)} Uhr',
  ].join(', ');
}

/// Header of a week group in the list of all workouts: `Diese Woche`,
/// `Letzte Woche`, otherwise the range `7. Sep. – 13. Sep.`.
String weekGroupLabel(LocalDate weekStart, LocalDate today) {
  final current = today.startOfWeek;
  if (weekStart == current) {
    return 'Diese Woche';
  }
  if (weekStart == current.addDays(-7)) {
    return 'Letzte Woche';
  }
  return '${formatDayMonth(weekStart)} – ${formatDayMonth(weekStart.addDays(6))}';
}

/// What is missing to the weekly goal, in words: `1 fehlt zum Ziel`,
/// `2 fehlen zum Ziel`, `Ziel erreicht`.
String workoutRemainingText(WorkoutWeekSummary summary) {
  if (summary.targetReached) {
    return 'Ziel erreicht';
  }
  final missing = summary.remainingToTarget;
  return missing == 1 ? '1 fehlt zum Ziel' : '$missing fehlen zum Ziel';
}

/// `Ø pro Training` in whole minutes, or null without a workout.
int? workoutAverageMinutes(WorkoutWeekSummary summary) =>
    summary.entryCount == 0
    ? null
    : (summary.totalMinutes / summary.entryCount).round();

/// The week in words for screen readers: the real count (never capped), the
/// goal and the minutes.
String workoutWeekSpoken(WorkoutWeekSummary summary) {
  final count = summary.entryCount;
  final base =
      'Diese Woche $count von ${summary.weeklyTarget} Trainings, '
      '${summary.totalMinutes} Minuten';
  return summary.targetReached
      ? '$base. Wochenziel erreicht.'
      : '$base. ${workoutRemainingText(summary)}.';
}

/// `heute`, `gestern`, `vor 4 Tagen` (lower case, for the muscle chips).
String lastTrainedText(int daysAgo) => switch (daysAgo) {
  <= 0 => 'heute',
  1 => 'gestern',
  _ => 'vor $daysAgo Tagen',
};

/// `Brust, heute` for screen readers.
String muscleRecencySpoken(MuscleRecency recency, LocalDate today) =>
    '${recency.group.label}, zuletzt ${lastTrainedText(recency.daysAgo(today))}';
