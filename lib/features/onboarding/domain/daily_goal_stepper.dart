import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/shared/number_format.dart';

/// Goals with a value the user can raise or lower with plus and minus, in
/// display order: steps and water per day, focus minutes per day and workouts
/// per week.
const List<GoalType> onboardingStepperGoals = <GoalType>[
  GoalType.steps,
  GoalType.water,
  GoalType.focusMinutes,
  GoalType.workoutWeekly,
];

/// The two "at least one per day" goals. Their target is fixed at 1 (see
/// [GoalType.isSwitch]); the user only decides whether the goal is on.
const List<GoalType> onboardingSwitchGoals = <GoalType>[
  GoalType.taskCompletion,
  GoalType.weightEntry,
];

/// Every goal the last step suggests, in display order: the stepper goals,
/// then the two on/off goals. The optional daily workout goal ("Workout
/// heute", off by default) is not suggested here: it is switched on in the goal
/// editor.
const List<GoalType> onboardingGoalTypes = <GoalType>[
  ...onboardingStepperGoals,
  ...onboardingSwitchGoals,
];

/// The starting value of every stepper goal: the default of its type (steps
/// 10000, water 2500 ml, focus 25 minutes, workouts 3 per week).
Map<GoalType, int> defaultGoalTargets() => <GoalType, int>{
  for (final type in onboardingStepperGoals) type: type.defaultTarget,
};

/// How far one tap on plus or minus moves [type]: 500 steps, one glass of
/// 250 ml, 5 minutes, one workout.
int goalStepSize(GoalType type) => switch (type) {
  GoalType.steps => 500,
  GoalType.water => 250,
  GoalType.focusMinutes => 5,
  GoalType.workoutWeekly => 1,
  _ => type.step,
};

/// The value after one plus ([direction] > 0) or minus ([direction] < 0) tap,
/// or `null` when [current] already sits at that end of the valid range.
///
/// Values snap to the step grid (a value of 100 steps goes to 500, not 600) and
/// stay inside `minTarget`..`maxTarget`, so every result passes
/// `GoalType.validateTarget`.
int? steppedGoalTarget(GoalType type, int current, int direction) {
  if (direction == 0) {
    return null;
  }
  final size = goalStepSize(type);
  final snapped = direction > 0
      ? (current ~/ size + 1) * size
      : ((current - 1) ~/ size) * size;
  final next = snapped.clamp(type.minTarget, type.maxTarget);
  return next == current ? null : next;
}

/// The number shown in the stepper: `10.000`, `2,5`, `25`, `3`.
String goalValueText(GoalType type, int target) => switch (type) {
  GoalType.steps => formatThousands(target),
  GoalType.water => formatLiters(target),
  _ => '$target',
};

/// The unit shown behind the number, or `null` for none.
String? goalUnitText(GoalType type) => switch (type) {
  GoalType.water => 'l',
  GoalType.focusMinutes => 'Min.',
  GoalType.workoutWeekly => '×',
  _ => null,
};

/// The row title of [type].
String goalTitle(GoalType type) => switch (type) {
  GoalType.steps => 'Schritte',
  GoalType.water => 'Wasser',
  GoalType.focusMinutes => 'Fokus',
  GoalType.workoutWeekly => 'Workouts',
  GoalType.taskCompletion => 'Aufgaben',
  GoalType.weightEntry => 'Gewicht',
  GoalType.workoutDaily => 'Workout heute',
};

/// The period under the row title: `pro Tag` or `pro Woche`.
String goalPeriod(GoalType type) => type.isDaily ? 'pro Tag' : 'pro Woche';

/// What an on/off goal asks for, as one line under its title.
String goalSwitchDescription(GoalType type) => switch (type) {
  GoalType.taskCompletion => 'Mindestens 1 Aufgabe pro Tag erledigen',
  GoalType.weightEntry => '1 Gewichtseintrag pro Tag',
  _ => goalPeriod(type),
};

/// The value as a spoken sentence, for example `2,5 Liter pro Tag`.
String goalSpokenValue(GoalType type, int target) => switch (type) {
  GoalType.steps => '${goalValueText(type, target)} Schritte pro Tag',
  GoalType.water => '${goalValueText(type, target)} Liter pro Tag',
  GoalType.focusMinutes => '$target Minuten Fokus pro Tag',
  GoalType.workoutWeekly =>
    target == 1 ? '1 Workout pro Woche' : '$target Workouts pro Woche',
  _ => goalValueText(type, target),
};

/// Spoken label of the plus button of [type].
String goalIncreaseLabel(GoalType type) => switch (type) {
  GoalType.steps => 'Schrittziel erhöhen',
  GoalType.water => 'Wasserziel erhöhen',
  GoalType.focusMinutes => 'Fokusziel erhöhen',
  GoalType.workoutWeekly => 'Wochenziel für Workouts erhöhen',
  _ => 'erhöhen',
};

/// Spoken label of the minus button of [type].
String goalDecreaseLabel(GoalType type) => switch (type) {
  GoalType.steps => 'Schrittziel verringern',
  GoalType.water => 'Wasserziel verringern',
  GoalType.focusMinutes => 'Fokusziel verringern',
  GoalType.workoutWeekly => 'Wochenziel für Workouts verringern',
  _ => 'verringern',
};
