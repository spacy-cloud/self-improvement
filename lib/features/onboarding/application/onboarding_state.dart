import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/onboarding/domain/daily_goal_stepper.dart';

/// The five screens in the designed order: the welcome screen and four
/// numbered steps.
enum OnboardingStep {
  welcome,
  goals,
  modules,
  body,
  dailyGoals;

  /// How many numbered steps follow the welcome screen ("Schritt 1 von 4").
  static const int numberedStepCount = 4;

  bool get isFirst => this == welcome;

  bool get isLast => this == dailyGoals;

  /// 1 to 4 for the numbered steps, `null` for the welcome screen.
  int? get number => this == welcome ? null : index;

  /// The following step, or `null` on the last one.
  OnboardingStep? get next => isLast ? null : values[index + 1];

  /// The previous step, or `null` on the first one.
  OnboardingStep? get previous => isFirst ? null : values[index - 1];
}

/// What the user triggered when a completion attempt failed (drives the retry).
enum OnboardingSubmitKind { finish, skip }

/// Everything the onboarding flow holds in memory.
///
/// Nothing here is persisted before the single completion command: closing the
/// app (or process death) in the middle of the flow simply starts it again.
@immutable
final class OnboardingState {
  const OnboardingState({
    required this.step,
    required this.movedBackward,
    required this.motivationGoals,
    required this.enabledModules,
    required this.nameText,
    required this.heightText,
    required this.ageText,
    required this.weightText,
    required this.goalTargets,
    required this.goalsOff,
    required this.fieldErrors,
    required this.focusRequest,
    required this.submitting,
    required this.completed,
    this.submitFailure,
    this.failedSubmit,
  });

  /// The fresh state: welcome screen, nothing selected, all five modules on,
  /// the default daily goals (all switched on), empty personal fields.
  factory OnboardingState.initial() => OnboardingState(
    step: OnboardingStep.welcome,
    movedBackward: false,
    motivationGoals: const <String>{},
    enabledModules: Set<ModuleId>.unmodifiable(ModuleId.values),
    nameText: '',
    heightText: '',
    ageText: '',
    weightText: '',
    goalTargets: Map<GoalType, int>.unmodifiable(defaultGoalTargets()),
    goalsOff: const <GoalType>{},
    fieldErrors: const <String, String>{},
    focusRequest: 0,
    submitting: false,
    completed: false,
  );

  final OnboardingStep step;

  /// Whether the last step change went backwards (drives the slide direction).
  final bool movedBackward;

  /// Selected motivation goal ids (`lose_weight`, ...). Empty by default.
  final Set<String> motivationGoals;

  /// Modules that stay on. May become empty.
  final Set<ModuleId> enabledModules;

  /// What the user typed (comma or period for the weight). Blank means "not
  /// given" for every one of them.
  final String nameText;
  final String heightText;
  final String ageText;
  final String weightText;

  /// Current value of every stepper goal (steps, water, focus, workouts).
  final Map<GoalType, int> goalTargets;

  /// The on/off goals (task, weight entry) the user switched off. Empty by
  /// default: every suggested goal starts on.
  final Set<GoalType> goalsOff;

  /// Field key (`ProfileFields`, `GoalType.key`) to German hint.
  final Map<String, String> fieldErrors;

  /// Counts failed validations; the body step moves the focus to the first
  /// field with an error whenever it changes.
  final int focusRequest;

  /// True while the completion command runs; further submits are ignored.
  final bool submitting;

  /// True once the completion committed (the screen is about to leave).
  final bool completed;

  /// The failure of the last completion attempt, or `null`.
  final AppFailure? submitFailure;

  /// Which action [submitFailure] belongs to.
  final OnboardingSubmitKind? failedSubmit;

  /// Whether the user changed anything compared to the fresh state. Skipping
  /// asks for a confirmation then, because skipping discards the input.
  bool get hasUserInput =>
      motivationGoals.isNotEmpty ||
      enabledModules.length != ModuleId.values.length ||
      nameText.trim().isNotEmpty ||
      heightText.trim().isNotEmpty ||
      ageText.trim().isNotEmpty ||
      weightText.trim().isNotEmpty ||
      goalsOff.isNotEmpty ||
      !mapEquals(goalTargets, defaultGoalTargets());

  /// Whether any action must be ignored right now.
  bool get busy => submitting || completed;

  OnboardingState copyWith({
    OnboardingStep? step,
    bool? movedBackward,
    Set<String>? motivationGoals,
    Set<ModuleId>? enabledModules,
    String? nameText,
    String? heightText,
    String? ageText,
    String? weightText,
    Map<GoalType, int>? goalTargets,
    Set<GoalType>? goalsOff,
    Map<String, String>? fieldErrors,
    int? focusRequest,
    bool? submitting,
    bool? completed,
    AppFailure? Function()? submitFailure,
    OnboardingSubmitKind? Function()? failedSubmit,
  }) => OnboardingState(
    step: step ?? this.step,
    movedBackward: movedBackward ?? this.movedBackward,
    motivationGoals: motivationGoals ?? this.motivationGoals,
    enabledModules: enabledModules ?? this.enabledModules,
    nameText: nameText ?? this.nameText,
    heightText: heightText ?? this.heightText,
    ageText: ageText ?? this.ageText,
    weightText: weightText ?? this.weightText,
    goalTargets: goalTargets ?? this.goalTargets,
    goalsOff: goalsOff ?? this.goalsOff,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    focusRequest: focusRequest ?? this.focusRequest,
    submitting: submitting ?? this.submitting,
    completed: completed ?? this.completed,
    submitFailure: submitFailure == null ? this.submitFailure : submitFailure(),
    failedSubmit: failedSubmit == null ? this.failedSubmit : failedSubmit(),
  );
}
