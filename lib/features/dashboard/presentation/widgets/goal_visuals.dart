import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/features/dashboard/domain/goals_day.dart';
import 'package:self_improvement/features/gamification/presentation/widgets/accent_progress_bar.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_widgets.dart'
    show habitVisual;

/// The symbol and the accent colour of a row of "Ziele heute".
typedef GoalVisual = ({IconData icon, AppAccent accent});

/// The symbol and accent of [row]: the ones the module of the goal uses on its
/// own card, so a goal looks the same here and on Home. A habit shows its own
/// symbol.
GoalVisual goalVisual(GoalsDayRow row) {
  final type = row.type;
  if (type == null) {
    final icon = row.habitIcon;
    if (icon == null) {
      return (icon: AppIcon.habit.data, accent: AppAccent.habits);
    }
    final visual = habitVisual(icon);
    return (icon: visual.glyph, accent: visual.accent);
  }
  return switch (type) {
    GoalType.water => (icon: AppIcon.water.data, accent: AppAccent.water),
    GoalType.steps => (icon: AppIcon.steps.data, accent: AppAccent.steps),
    GoalType.focusMinutes => (
      icon: AppIcon.focus.data,
      accent: AppAccent.focus,
    ),
    GoalType.weightEntry => (
      icon: AppIcon.weight.data,
      accent: AppAccent.weight,
    ),
    GoalType.taskCompletion => (
      icon: AppIcon.task.data,
      accent: AppAccent.habits,
    ),
    GoalType.workoutDaily || GoalType.workoutWeekly => (
      icon: AppIcon.workout.data,
      accent: AppAccent.workout,
    ),
  };
}

/// The bar of a row: the design system bar where it has a variant for the
/// accent, the same bar in any other accent otherwise.
Widget goalBar({
  required double value,
  required AppAccent accent,
  required String semanticLabel,
}) {
  final variant = switch (accent) {
    AppAccent.water => AppProgressVariant.water,
    AppAccent.steps => AppProgressVariant.steps,
    AppAccent.focus => AppProgressVariant.focus,
    AppAccent.primary || AppAccent.weight => AppProgressVariant.primary,
    _ => null,
  };
  if (variant == null) {
    return AccentProgressBar(
      value: value,
      accent: accent,
      semanticLabel: semanticLabel,
    );
  }
  return AppProgressBar(
    value: value,
    variant: variant,
    semanticLabel: semanticLabel,
  );
}
