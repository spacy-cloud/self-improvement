import 'package:flutter/foundation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Common data of an activity that can earn XP.
///
/// "First" always means: ordered by [occurredAtUtc], then [createdAtUtc], then
/// [id] compared as a string (see [compareXpEvents]).
@immutable
sealed class XpEventFact {
  const XpEventFact({
    required this.id,
    required this.occurredAtUtc,
    required this.createdAtUtc,
    required this.eligible,
  });

  /// Record id (UUID).
  final String id;

  /// The business time of the event (UTC), for example the measurement time of
  /// an entry or the completion time of a task or session.
  final DateTime occurredAtUtc;

  /// When the record was created (UTC); the tie-breaker after the event time.
  final DateTime createdAtUtc;

  /// The eligibility flag as it was when the record was first created or
  /// completed (`gamification_eligible`, `completion_eligibility`, ...). It is
  /// never recomputed; a record without it earns nothing.
  final bool eligible;
}

/// The award order: event time, then creation time, then id (string compare).
int compareXpEvents(XpEventFact a, XpEventFact b) {
  final byEvent = a.occurredAtUtc.compareTo(b.occurredAtUtc);
  if (byEvent != 0) {
    return byEvent;
  }
  final byCreation = a.createdAtUtc.compareTo(b.createdAtUtc);
  if (byCreation != 0) {
    return byCreation;
  }
  return a.id.compareTo(b.id);
}

/// An active water entry.
final class WaterXpFact extends XpEventFact {
  const WaterXpFact({
    required super.id,
    required super.occurredAtUtc,
    required super.createdAtUtc,
    required super.eligible,
    required this.amountMl,
  });

  final int amountMl;
}

/// An active weight entry.
final class WeightXpFact extends XpEventFact {
  const WeightXpFact({
    required super.id,
    required super.occurredAtUtc,
    required super.createdAtUtc,
    required super.eligible,
  });
}

/// A currently completed task. [occurredAtUtc] is the completion instant; the
/// data layer passes the tasks whose current completion happened on the day.
final class TaskXpFact extends XpEventFact {
  const TaskXpFact({
    required super.id,
    required super.occurredAtUtc,
    required super.createdAtUtc,
    required super.eligible,
  });
}

/// A completed focus session. [occurredAtUtc] is the completion instant; the
/// data layer passes only sessions with status completed whose completion day
/// is the day.
final class FocusXpFact extends XpEventFact {
  const FocusXpFact({
    required super.id,
    required super.occurredAtUtc,
    required super.createdAtUtc,
    required super.eligible,
    required this.accumulatedSeconds,
  });

  /// The saved duration of the session in seconds.
  final int accumulatedSeconds;
}

/// An active manual workout entry.
final class WorkoutXpFact extends XpEventFact {
  const WorkoutXpFact({
    required super.id,
    required super.occurredAtUtc,
    required super.createdAtUtc,
    required super.eligible,
  });
}

/// An active habit check. [occurredAtUtc] is the check instant; the unique
/// (habit, day) pair means a habit appears at most once per day.
final class HabitCheckXpFact extends XpEventFact {
  const HabitCheckXpFact({
    required super.id,
    required super.occurredAtUtc,
    required super.createdAtUtc,
    required super.eligible,
    required this.habitId,
  });

  final String habitId;
}

/// The step record of a day (`step_days`) with its frozen XP decision.
@immutable
final class StepsXpFact {
  const StepsXpFact({
    required this.steps,
    this.reachedGoalEligible,
    this.xpGoalTargetSteps,
  });

  /// The current day value (0 is a value).
  final int steps;

  /// Decided once when an applicable goal was first reached: whether
  /// gamification was on at that moment. `null` until a goal was reached.
  final bool? reachedGoalEligible;

  /// The threshold that was frozen with the decision, in steps. `null` until a
  /// goal was reached.
  final int? xpGoalTargetSteps;

  /// Whether the day earns the steps award: eligible at the first reach and
  /// the current value still reaches the frozen threshold (not today's goal).
  bool get earnsAward {
    final target = xpGoalTargetSteps;
    return reachedGoalEligible == true && target != null && steps >= target;
  }
}

/// All activities of ONE stored local day ([date]) that can earn XP.
///
/// The data layer queries them per stored local date (never per the day of
/// entry): active, not soft-deleted records of that day, grouped as follows.
/// Passing every record of the day (not just the first few) is required, so a
/// later record can take the place of a deleted one.
@immutable
final class XpDayFacts {
  const XpDayFacts({
    required this.date,
    this.water = const [],
    this.weights = const [],
    this.steps,
    this.tasks = const [],
    this.focusSessions = const [],
    this.workouts = const [],
    this.habitChecks = const [],
  });

  final LocalDate date;

  /// Active water entries of the day.
  final List<WaterXpFact> water;

  /// Active weight entries of the day.
  final List<WeightXpFact> weights;

  /// The step day record, or `null` when there is none.
  final StepsXpFact? steps;

  /// Tasks whose current completion happened on the day.
  final List<TaskXpFact> tasks;

  /// Completed focus sessions that were completed on the day.
  final List<FocusXpFact> focusSessions;

  /// Active workout entries of the day.
  final List<WorkoutXpFact> workouts;

  /// Active habit checks of the day.
  final List<HabitCheckXpFact> habitChecks;
}
