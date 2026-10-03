import 'package:flutter/foundation.dart';

/// The frozen XP decision of a step day (`reached_goal_eligible` and
/// `xp_goal_target_steps`). Both are `null` until an applicable goal was first
/// reached.
@immutable
final class StepsEligibility {
  const StepsEligibility({
    required this.reachedGoalEligible,
    required this.xpGoalTargetSteps,
  });

  /// No decision yet: early input below the threshold creates no claim.
  static const StepsEligibility undecided = StepsEligibility(
    reachedGoalEligible: null,
    xpGoalTargetSteps: null,
  );

  /// Whether gamification was on when the goal was first reached.
  final bool? reachedGoalEligible;

  /// The threshold that was applicable at that moment.
  final int? xpGoalTargetSteps;

  @override
  bool operator ==(Object other) =>
      other is StepsEligibility &&
      other.reachedGoalEligible == reachedGoalEligible &&
      other.xpGoalTargetSteps == xpGoalTargetSteps;

  @override
  int get hashCode => Object.hash(reachedGoalEligible, xpGoalTargetSteps);

  @override
  String toString() =>
      'StepsEligibility(eligible: $reachedGoalEligible, '
      'target: $xpGoalTargetSteps)';
}

/// Decides, when a step day is saved, what to store as its XP decision.
///
/// 1. A decision that already exists (`existingReachedGoalEligible != null`)
///    is kept unchanged, whatever the new value, the current goal or the
///    gamification switch say. In particular a goal that was reached while
///    gamification was off is never awarded retroactively.
/// 2. Otherwise, if an applicable goal exists and [newSteps] reaches it, the
///    threshold is frozen as `xpGoalTargetSteps` and `reachedGoalEligible` is
///    set once from [gamificationEnabled].
/// 3. Otherwise nothing is decided: early input below the threshold creates no
///    claim.
///
/// Inputs for the data layer: [applicableTarget] is the steps threshold of the
/// day's snapshot if the goal is applicable that day (see
/// `DaySnapshot.applicableTargetFor`), otherwise `null`; the existing values
/// are those of the stored step day (`null` for a new row).
StepsEligibility decideStepsEligibility({
  required int newSteps,
  required int? applicableTarget,
  required bool gamificationEnabled,
  required bool? existingReachedGoalEligible,
  required int? existingXpGoalTargetSteps,
}) {
  if (existingReachedGoalEligible != null) {
    return StepsEligibility(
      reachedGoalEligible: existingReachedGoalEligible,
      xpGoalTargetSteps: existingXpGoalTargetSteps,
    );
  }
  if (applicableTarget != null && newSteps >= applicableTarget) {
    return StepsEligibility(
      reachedGoalEligible: gamificationEnabled,
      xpGoalTargetSteps: applicableTarget,
    );
  }
  return StepsEligibility.undecided;
}
