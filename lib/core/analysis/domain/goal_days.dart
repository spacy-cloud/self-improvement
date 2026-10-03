/// The days of the daily goals strip: how many of the goals that applied on a
/// day were fulfilled. The rule "complete day" lives here and nowhere else in
/// the UI, so the strip and the complete-day figure cannot disagree.
library;

import 'package:self_improvement/core/analysis/domain/analysis_dates.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_texts.dart';
import 'package:self_improvement/shared/local_date.dart';

/// One day of the daily goals strip.
final class GoalDay {
  const GoalDay({
    required this.date,
    required this.applicableGoals,
    required this.fulfilledGoals,
  });

  /// Reads the goal figures of [day].
  factory GoalDay.of(AnalysisDay day) => GoalDay(
    date: day.date,
    applicableGoals: day.applicableGoals,
    fulfilledGoals: day.fulfilledGoals,
  );

  final LocalDate date;

  /// Number of goals that applied on this day (0 without snapshot or goal).
  final int applicableGoals;

  /// Number of applicable goals that were fulfilled.
  final int fulfilledGoals;

  /// Whether at least one goal applied; only such days count in the goal
  /// figures.
  bool get hasGoals => applicableGoals >= 1;

  /// A complete day: at least one applicable goal and all of them fulfilled
  /// (the same rule as `AnalysisDay.isCompleteDay`).
  bool get isComplete => hasGoals && fulfilledGoals == applicableGoals;

  /// `fulfilled / applicable` in 0..1, `null` for a day without goals (never a
  /// fake 0).
  double? get fraction => hasGoals ? fulfilledGoals / applicableGoals : null;

  /// The day for screen readers: `Montag, 28.09.2026: 6 von 6 Tageszielen
  /// erfüllt, Tag komplett`; without goals `keine Tagesziele`.
  String get semanticsLabel {
    final status = hasGoals
        ? '$fulfilledGoals von $applicableGoals '
              '${pluralize(applicableGoals, 'Tagesziel', 'Tageszielen')} '
              'erfüllt${isComplete ? ', Tag komplett' : ''}'
        : 'keine Tagesziele';
    return '${formatLongWeekdayDate(date)}: $status';
  }

  @override
  bool operator ==(Object other) =>
      other is GoalDay &&
      other.date == date &&
      other.applicableGoals == applicableGoals &&
      other.fulfilledGoals == fulfilledGoals;

  @override
  int get hashCode => Object.hash(date, applicableGoals, fulfilledGoals);

  @override
  String toString() => 'GoalDay($date, $fulfilledGoals/$applicableGoals)';
}

/// One [GoalDay] per day of the current period, oldest first, today last. A
/// missing day counts as a day without goals.
List<GoalDay> buildGoalDays({
  required AnalysisPeriodSpec period,
  required Map<LocalDate, AnalysisDay> days,
}) => [
  for (final date in period.currentDays)
    GoalDay.of(days[date] ?? AnalysisDay(date: date)),
];
