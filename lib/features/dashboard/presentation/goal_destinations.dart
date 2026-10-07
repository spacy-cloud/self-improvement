import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/features/body/presentation/weight_routes.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_routes.dart';
import 'package:self_improvement/features/dashboard/domain/goals_day.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_routes.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_routes.dart';

/// Where a tap on a goal of "Ziele heute" leads: the page of its module.
@immutable
final class GoalDestination {
  const GoalDestination(this.route, {this.isTab = false});

  /// The route to open (a tab may carry a query: `/habits?tab=tasks`).
  final String route;

  /// Whether the route is a tab of the shell. A tab is switched to with `go`
  /// (like the task card on Home does), every other page is pushed over the
  /// shell so that back returns to "Ziele heute".
  final bool isTab;

  @override
  bool operator ==(Object other) =>
      other is GoalDestination && other.route == route && other.isTab == isTab;

  @override
  int get hashCode => Object.hash(route, isTab);

  @override
  String toString() => 'GoalDestination($route${isTab ? ', tab' : ''})';
}

/// The destination of a goal, the ONE place that says which goal belongs to
/// which page:
///
/// - water: the water page, steps: the steps overview, weight: the weight
///   overview, focus: the focus start page,
/// - "Workout heute" and the weekly workout goal: the workout area,
/// - "Aufgabe erledigen": the task list (tab Habits, `?tab=tasks`),
/// - a habit: the habit list (tab Habits).
///
/// A goal of a module that is switched off never gets a row, so a destination
/// is only reached for an active module; the module routes are guarded anyway
/// (`guardModuleRoutes`).
GoalDestination goalDestination(GoalsDayRow row) {
  final type = row.type;
  if (type == null) {
    return const GoalDestination(HabitRoutes.tab, isTab: true);
  }
  return switch (type) {
    GoalType.water => const GoalDestination(WaterRoutes.screen),
    GoalType.steps => const GoalDestination(StepsRoutes.overview),
    GoalType.weightEntry => const GoalDestination(WeightRoutes.overview),
    GoalType.focusMinutes => const GoalDestination(FocusRoutes.start),
    GoalType.workoutDaily ||
    GoalType.workoutWeekly => const GoalDestination(WorkoutRoutes.overview),
    GoalType.taskCompletion => const GoalDestination(
      TaskRoutes.list,
      isTab: true,
    ),
  };
}

/// Opens the page of the goal of [row].
void openGoal(BuildContext context, GoalsDayRow row) {
  final destination = goalDestination(row);
  if (destination.isTab) {
    context.go(destination.route);
  } else {
    unawaited(context.push<void>(destination.route));
  }
}
