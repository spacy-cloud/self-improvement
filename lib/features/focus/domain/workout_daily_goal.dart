import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Whether "Workout heute" is switched on today and from tomorrow (a change
/// saved in the goal editor applies from tomorrow).
@immutable
final class WorkoutDailyGoalPlan {
  const WorkoutDailyGoalPlan({required this.today, required this.tomorrow});

  final bool today;
  final bool tomorrow;

  /// A change that is saved but not valid yet.
  bool get hasPendingChange => today != tomorrow;

  @override
  bool operator ==(Object other) =>
      other is WorkoutDailyGoalPlan &&
      other.today == today &&
      other.tomorrow == tomorrow;

  @override
  int get hashCode => Object.hash(today, tomorrow);
}

/// The plan of "Workout heute" from the stored goal versions: no version means
/// off.
WorkoutDailyGoalPlan workoutDailyGoalPlanOn(
  Iterable<GoalVersion> versions,
  LocalDate today,
) => WorkoutDailyGoalPlan(
  today: effectiveGoalOrDefault(versions, GoalType.workoutDaily, today).enabled,
  tomorrow: effectiveGoalOrDefault(
    versions,
    GoalType.workoutDaily,
    nextEffectiveDate(today),
  ).enabled,
);
