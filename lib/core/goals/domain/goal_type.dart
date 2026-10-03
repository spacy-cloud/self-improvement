import 'package:self_improvement/core/modules/module_id.dart';

/// Outcome of [GoalType.validateTarget]: a plain value instead of an exception,
/// so the goal editor can map every case to a field message.
enum GoalTargetValidation {
  /// The value is acceptable and may be saved.
  valid,

  /// Smaller than [GoalType.minTarget].
  belowMinimum,

  /// Larger than [GoalType.maxTarget].
  aboveMaximum,

  /// Inside the range, but not reachable in [GoalType.step] increments counted
  /// from [GoalType.minTarget].
  notOnStep;

  /// Whether the value may be saved.
  bool get isValid => this == valid;
}

/// The goal kinds the app knows. The string [key] is a stable technical
/// contract (database rows, backup) and never changes.
///
/// Five of them are daily goals that form the day ring; [workoutWeekly] is a
/// weekly display value only. Nutrition (meals) and XP are not goals at all.
enum GoalType {
  /// Drinking goal in millilitres per day (250 to 10000 in steps of 50).
  water(
    'water',
    module: ModuleId.nutrition,
    isDaily: true,
    defaultTarget: 2500,
    minTarget: 250,
    maxTarget: 10000,
    step: 50,
  ),

  /// Steps per day (100 to 100000).
  steps(
    'steps',
    module: ModuleId.body,
    isDaily: true,
    defaultTarget: 10000,
    minTarget: 100,
    maxTarget: 100000,
  ),

  /// "Record at least one weight entry": an on/off switch, fixed target 1.
  weightEntry(
    'weight_entry',
    module: ModuleId.body,
    isDaily: true,
    defaultTarget: 1,
    minTarget: 1,
    maxTarget: 1,
  ),

  /// Completed focus minutes per day (5 to 180).
  focusMinutes(
    'focus_minutes',
    module: ModuleId.focus,
    isDaily: true,
    defaultTarget: 25,
    minTarget: 5,
    maxTarget: 180,
  ),

  /// "Complete at least one task today": an on/off switch, fixed target 1.
  taskCompletion(
    'task_completion',
    module: ModuleId.tasks,
    isDaily: true,
    defaultTarget: 1,
    minTarget: 1,
    maxTarget: 1,
  ),

  /// Workout entries per Monday-to-Sunday week (1 to 14). Not a daily goal:
  /// it is never part of the day ring, a day snapshot or the streak.
  workoutWeekly(
    'workout_weekly',
    module: ModuleId.focus,
    isDaily: false,
    defaultTarget: 3,
    minTarget: 1,
    maxTarget: 14,
  );

  const GoalType(
    this.key, {
    required this.module,
    required this.isDaily,
    required this.defaultTarget,
    required this.minTarget,
    required this.maxTarget,
    this.step = 1,
  });

  /// Stable persisted identifier. For daily goals it doubles as the goal key
  /// of snapshot rows (habits use [habitGoalKey] instead).
  final String key;

  /// The module that must be active for the goal to apply.
  final ModuleId module;

  /// Whether the goal is part of the day ring (all but [workoutWeekly]).
  final bool isDaily;

  /// Planning default in the unit of the goal (ml, steps, minutes, count).
  final int defaultTarget;

  /// Smallest valid target.
  final int minTarget;

  /// Largest valid target.
  final int maxTarget;

  /// Valid targets are `minTarget + k * step`.
  final int step;

  /// Whether the goal is an on/off switch with the fixed target 1 (weight
  /// entry and task completion): only the enabled flag is user-editable.
  bool get isSwitch => minTarget == maxTarget;

  /// The daily goal types in enum order: the order of snapshot items.
  static final List<GoalType> dailyTypes = List.unmodifiable(
    values.where((type) => type.isDaily),
  );

  /// Returns the type for a persisted [key], or `null` when unknown.
  static GoalType? tryParse(String key) {
    for (final type in values) {
      if (type.key == key) {
        return type;
      }
    }
    return null;
  }

  /// Checks a user supplied [target] against range and step of this type.
  GoalTargetValidation validateTarget(int target) {
    if (target < minTarget) {
      return GoalTargetValidation.belowMinimum;
    }
    if (target > maxTarget) {
      return GoalTargetValidation.aboveMaximum;
    }
    if ((target - minTarget) % step != 0) {
      return GoalTargetValidation.notOnStep;
    }
    return GoalTargetValidation.valid;
  }

  /// The threshold to use for a stored [target]: the fixed value for switch
  /// goals (a stored value is ignored), otherwise the stored value, or the
  /// [defaultTarget] when none was stored.
  int resolveTarget(int? target) =>
      isSwitch ? defaultTarget : (target ?? defaultTarget);
}
