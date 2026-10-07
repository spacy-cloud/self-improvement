import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

/// A rest day or a skipped day (BS-99): the fact that the user answered "Wie
/// war dein Tag?" without a workout. One active mark per local day at most.
///
/// A mark fulfils the optional daily goal "Workout heute" like a workout does,
/// earns no XP and does not count for the weekly workout goal.
@immutable
final class WorkoutDayMark {
  const WorkoutDayMark({
    required this.id,
    required this.date,
    required this.kind,
    required this.timezoneId,
    required this.rowVersion,
  });

  final String id;

  /// The local business day the mark applies to (frozen when it was set).
  final LocalDate date;

  final WorkoutDayMarkKind kind;

  /// IANA zone in effect when the mark was set.
  final String timezoneId;

  /// Optimistic version; the undo of a mark checks it.
  final int rowVersion;

  @override
  bool operator ==(Object other) =>
      other is WorkoutDayMark &&
      other.id == id &&
      other.date == date &&
      other.kind == kind &&
      other.timezoneId == timezoneId &&
      other.rowVersion == rowVersion;

  @override
  int get hashCode => Object.hash(id, date, kind, timezoneId, rowVersion);

  @override
  String toString() => 'WorkoutDayMark($id, $date, ${kind.key})';
}

/// How one day answers "Wie war dein Tag?".
enum WorkoutDayOutcome {
  /// No workout and no mark: the day is still open.
  open,

  /// At least one workout was logged on the day.
  trained,

  /// No workout, marked as a rest day.
  rest,

  /// No workout, marked as skipped.
  skipped,
}

/// The workouts and the mark of one local day, and what they make of it.
///
/// A workout always wins over a mark: a day with a workout is a training day,
/// whatever was marked before (the mark stays stored and applies again when the
/// workouts of the day are deleted). The weekly workout goal plays no part.
@immutable
final class WorkoutDayState {
  const WorkoutDayState({
    required this.date,
    required this.workouts,
    this.mark,
  });

  final LocalDate date;

  /// The active workouts of [date], newest first.
  final List<WorkoutEntry> workouts;

  /// The active mark of [date], or `null`.
  final WorkoutDayMark? mark;

  WorkoutDayOutcome get outcome {
    if (workouts.isNotEmpty) {
      return WorkoutDayOutcome.trained;
    }
    return switch (mark?.kind) {
      WorkoutDayMarkKind.rest => WorkoutDayOutcome.rest,
      WorkoutDayMarkKind.skipped => WorkoutDayOutcome.skipped,
      null => WorkoutDayOutcome.open,
    };
  }

  /// Whether the day counts for the daily workout goal.
  bool get fulfilled => outcome != WorkoutDayOutcome.open;

  /// The latest workout of the day, or `null`.
  WorkoutEntry? get latest => workouts.isEmpty ? null : workouts.first;

  /// The mark that can be taken back: only while it decides the day, which
  /// is the case without a workout.
  WorkoutDayMark? get takeBackMark => workouts.isEmpty ? mark : null;

  @override
  bool operator ==(Object other) =>
      other is WorkoutDayState &&
      other.date == date &&
      other.mark == mark &&
      listEquals(other.workouts, workouts);

  @override
  int get hashCode => Object.hash(date, mark, Object.hashAll(workouts));
}

/// Builds the state of [date] from any [workouts] (only those whose frozen local
/// date is [date] count) and the [mark] of that day (ignored when it belongs to
/// another day).
WorkoutDayState buildWorkoutDayState({
  required LocalDate date,
  required Iterable<WorkoutEntry> workouts,
  WorkoutDayMark? mark,
}) {
  final ofDay = [
    for (final entry in workouts)
      if (entry.localDate == date) entry,
  ]..sort(_newestFirst);
  return WorkoutDayState(
    date: date,
    workouts: List.unmodifiable(ofDay),
    mark: mark != null && mark.date == date ? mark : null,
  );
}

int _newestFirst(WorkoutEntry a, WorkoutEntry b) {
  final byTime = b.occurredAtUtc.compareTo(a.occurredAtUtc);
  return byTime != 0 ? byTime : b.id.compareTo(a.id);
}
