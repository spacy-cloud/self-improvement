import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// Glyph and accent of an onboarding option, as drawn in the approved design.
/// Two glyphs (arrow down, heart, star) are plain Material icons because the
/// design system's icon set has no equivalent.
typedef OptionLook = ({IconData icon, AppAccent accent});

/// The look of a motivation goal card, by its stable id.
OptionLook motivationGoalLook(String id) => switch (id) {
  'lose_weight' => (
    icon: Icons.arrow_downward_rounded,
    accent: AppAccent.primary,
  ),
  'get_fitter' => (icon: AppIcon.workout.data, accent: AppAccent.workout),
  'move_more' => (icon: AppIcon.steps.data, accent: AppAccent.steps),
  'live_healthier' => (
    icon: Icons.favorite_border_rounded,
    accent: AppAccent.water,
  ),
  _ => (icon: AppIcon.habits.data, accent: AppAccent.habits),
};

/// The look of a module card. The nutrition module shows the drop in the water
/// colour, as the design does ("Wasser & Ernährung").
OptionLook moduleLook(ModuleId module) => switch (module) {
  ModuleId.body => (icon: AppIcon.weight.data, accent: AppAccent.weight),
  ModuleId.nutrition => (icon: AppIcon.water.data, accent: AppAccent.water),
  ModuleId.focus => (icon: AppIcon.focus.data, accent: AppAccent.focus),
  ModuleId.tasks => (icon: AppIcon.habits.data, accent: AppAccent.habits),
  ModuleId.gamification => (
    icon: Icons.star_outline_rounded,
    accent: AppAccent.gamification,
  ),
};

/// The look of a daily goal row.
OptionLook goalLook(GoalType type) => switch (type) {
  GoalType.steps => (icon: AppIcon.steps.data, accent: AppAccent.steps),
  GoalType.water => (icon: AppIcon.water.data, accent: AppAccent.water),
  GoalType.workoutWeekly => (
    icon: AppIcon.workout.data,
    accent: AppAccent.workout,
  ),
  _ => (icon: AppIcon.check.data, accent: AppAccent.primary),
};
