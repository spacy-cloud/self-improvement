import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/body/steps/domain/steps_input.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The manual step total of one local date.
@immutable
final class StepDay {
  const StepDay({
    required this.id,
    required this.date,
    required this.steps,
    required this.rowVersion,
    this.reachedGoalEligible,
    this.xpGoalTargetSteps,
  });

  final String id;
  final LocalDate date;

  /// 0 is a recorded value; a missing day has no [StepDay] at all.
  final int steps;

  final int rowVersion;

  /// Frozen decision when an applicable goal was first reached (null before).
  final bool? reachedGoalEligible;

  /// The threshold that was frozen with that decision.
  final int? xpGoalTargetSteps;
}

/// Field keys of the steps form.
abstract final class StepsFields {
  static const String steps = 'steps';
  static const String date = 'date';
}

/// Earliest accepted date (technical minimum, same as every event form).
final LocalDate earliestStepsDate = LocalDate(2000, 1, 1);

/// Validates the date and value of a manual total. Throws
/// [ValidationFailure] with German field hints.
void validateStepDay({
  required int steps,
  required LocalDate date,
  required LocalDate today,
}) {
  final errors = <String, String>{};
  if (steps < minStepsPerDay || steps > maxStepsPerDay) {
    errors[StepsFields.steps] = 'Bitte gib höchstens 100.000 Schritte ein.';
  }
  if (date.isAfter(today)) {
    errors[StepsFields.date] = 'Das Datum darf nicht in der Zukunft liegen.';
  } else if (date.isBefore(earliestStepsDate)) {
    errors[StepsFields.date] =
        'Das Datum darf nicht vor dem 01.01.2000 liegen.';
  }
  if (errors.isNotEmpty) {
    throw ValidationFailure(errors);
  }
}

/// Progress of a day towards its step target.
@immutable
final class StepsProgress {
  const StepsProgress({required this.steps, required this.target});

  final int steps;

  /// The applicable target, or null if there is none (goal off/module off).
  final int? target;

  /// Bar value: `min(steps / target, 1)`; 0 without a target.
  double get fraction =>
      target == null || target == 0 ? 0 : (steps / target!).clamp(0.0, 1.0);

  /// Real percentage, rounded half up, also above 100 %; null without a
  /// target. It is never 100 while the target is not reached (9,950 of 10,000
  /// steps shows `99`), so "100 %" and [reached] always agree.
  int? get percent {
    final goal = target;
    if (goal == null || goal == 0) {
      return null;
    }
    final rounded = (steps * 200 + goal) ~/ (2 * goal);
    return steps < goal && rounded > 99 ? 99 : rounded;
  }

  bool get reached => target != null && steps >= target!;
}
