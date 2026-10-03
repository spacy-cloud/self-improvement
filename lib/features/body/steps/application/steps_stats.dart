import 'package:flutter/foundation.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Figures of the steps overview over one window of local days.
///
/// Days without a record are "Nicht erfasst": they are neither zero nor part
/// of the average. A recorded 0 does count.
@immutable
final class StepsStats {
  const StepsStats({
    required this.windowDays,
    required this.recordedDays,
    required this.reachedDays,
    required this.hasTarget,
    this.averageSteps,
    this.bestDate,
    this.bestSteps,
  });

  /// Length of the window in days (7, 30 or 90).
  final int windowDays;

  /// Days of the window with a recorded total.
  final int recordedDays;

  /// Recorded days on which the goal that applied then was reached.
  final int reachedDays;

  /// True if at least one day of the window had an applicable goal.
  final bool hasTarget;

  /// Average of the recorded days, rounded half up; null without a record.
  final int? averageSteps;

  /// The recorded day with the most steps (the latest one on a tie).
  final LocalDate? bestDate;
  final int? bestSteps;

  bool get isEmpty => recordedDays == 0;
}

/// Computes the figures of [days] (newest first, one entry per day of the
/// window, as delivered by `stepsHistoryProvider`).
StepsStats computeStepsStats(List<StepsHistoryDay> days) {
  var recorded = 0;
  var reached = 0;
  var sum = 0;
  var hasTarget = false;
  LocalDate? bestDate;
  int? bestSteps;
  for (final day in days) {
    if (day.progress.target != null) {
      hasTarget = true;
    }
    if (!day.recorded) {
      continue;
    }
    recorded++;
    sum += day.progress.steps;
    if (day.progress.reached) {
      reached++;
    }
    if (bestSteps == null || day.progress.steps > bestSteps) {
      bestSteps = day.progress.steps;
      bestDate = day.date;
    }
  }
  return StepsStats(
    windowDays: days.length,
    recordedDays: recorded,
    reachedDays: reached,
    hasTarget: hasTarget,
    averageSteps: recorded == 0 ? null : (sum * 2 + recorded) ~/ (2 * recorded),
    bestDate: bestDate,
    bestSteps: bestSteps,
  );
}
