/// The workout week card: the current Monday-to-Sunday week to date against
/// the same weekdays of the previous week.
///
/// A separate rule from the period cards. Week to date is compared with week
/// to date, never an incomplete week with a complete one:
///
/// ```text
/// today = Saturday 2026-10-03
///   this week  Monday 2026-09-28 .. Saturday 2026-10-03   (Mo bis Sa)
///   last week  Monday 2026-09-21 .. Saturday 2026-09-26   (the same weekdays)
/// ```
///
/// The ring is `completedEntries / weeklyTarget` capped at 100 %, while the
/// real number of entries and minutes stays visible. The target is the weekly
/// goal in effect today (default 3).
library;

import 'package:self_improvement/core/analysis/domain/analysis_dates.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_figures.dart';
import 'package:self_improvement/core/analysis/domain/analysis_math.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/core/analysis/domain/period_stats.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// The default weekly workout target (a goal that has no stored version).
const int defaultWorkoutWeeklyTarget = 3;

/// Everything the workout week card shows.
final class WorkoutWeekCard {
  WorkoutWeekCard({
    required this.today,
    required this.weekStart,
    required this.elapsedDays,
    required this.previousWeekStart,
    required this.previousWeekEnd,
    required this.entries,
    required this.minutes,
    required this.previousEntries,
    required this.previousMinutes,
    required this.weeklyTarget,
    required this.ringFraction,
    required this.ringPercent,
    required this.targetReached,
    required this.progressText,
    required this.rangeText,
    required this.previousRangeText,
    required List<AnalysisFigure> figures,
    required this.semanticsLabel,
  }) : figures = List.unmodifiable(figures);

  /// The local day the card was built for.
  final LocalDate today;

  /// The Monday of the current week.
  final LocalDate weekStart;

  /// Days of the week up to and including today: 1 (Monday) to 7 (Sunday).
  /// Both compared ranges have this length.
  final int elapsedDays;

  /// The Monday of the previous week.
  final LocalDate previousWeekStart;

  /// The same weekday of the previous week as [today] (`today - 7` days).
  final LocalDate previousWeekEnd;

  /// Workout entries of the week to date. The REAL count: it can exceed the
  /// target, only the ring is capped.
  final int entries;

  /// Workout minutes of the week to date (workouts are no focus time).
  final int minutes;

  /// Entries of the same weekdays of the previous week.
  final int previousEntries;

  /// Minutes of the same weekdays of the previous week.
  final int previousMinutes;

  /// The weekly target in effect today, `null` when the weekly goal is
  /// switched off (then there is no ring).
  final int? weeklyTarget;

  /// `entries / weeklyTarget` capped at 1.0, `null` without a target.
  final double? ringFraction;

  /// The ring in whole percent, capped at 100; `null` without a target.
  final int? ringPercent;

  /// Whether the target is reached (`entries >= weeklyTarget`).
  final bool targetReached;

  /// `2 von 3 Workouts`, `3 von 3 Workouts, Wochenziel erreicht`,
  /// `5 Workouts, Wochenziel 3 erreicht`, without a target `2 Workouts` or
  /// `Noch kein Workout diese Woche`.
  final String progressText;

  /// `28.09. bis 03.10.2026, bis heute`.
  final String rangeText;

  /// `Vorwoche: 21.09. bis 26.09.2026`.
  final String previousRangeText;

  /// The figures `workoutWeek.count` and `workoutWeek.minutes`, compared with
  /// the previous week to date by the same rules as the period figures.
  final List<AnalysisFigure> figures;

  /// The whole card for screen readers.
  final String semanticsLabel;

  /// German title: `Workouts diese Woche`.
  String get title => AnalysisMetric.workoutWeek.title;

  /// Whether the week has any workout yet.
  bool get hasData => entries > 0;

  /// The count figure (`workoutWeek.count`).
  AnalysisFigure get countFigure => figures[0];

  /// The minutes figure (`workoutWeek.minutes`).
  AnalysisFigure get minutesFigure => figures[1];
}

/// Builds the workout week card for [today].
///
/// [days] hold the workout counts and minutes; they have to cover at least
/// `[previousWeekStart, today]` (at most 13 days back); missing days count as
/// no workout. [weeklyTarget] is the weekly goal in effect today
/// ([defaultWorkoutWeeklyTarget] when no version exists), or `null` when the
/// goal is switched off. [usageStart] is the profile start date: when the
/// previous week-to-date does not lie completely inside the usage window there
/// is no comparison.
WorkoutWeekCard buildWorkoutWeekCard({
  required LocalDate today,
  required Iterable<AnalysisDay> days,
  required LocalDate? usageStart,
  required int? weeklyTarget,
}) {
  final weekStart = today.startOfWeek;
  final elapsedDays = today.weekday;
  final previousWeekStart = weekStart.addDays(-7);
  final previousWeekEnd = today.addDays(-7);

  final list = days.toList(growable: false);
  final current = computePeriodStats(
    days: list,
    start: weekStart,
    end: today,
  ).workouts;
  final previous = computePeriodStats(
    days: list,
    start: previousWeekStart,
    end: previousWeekEnd,
  ).workouts;

  final target = weeklyTarget;
  final entries = current.entries;
  final reached = target != null && entries >= target;
  final ringFraction = target == null
      ? null
      : (entries >= target ? 1.0 : entries / target);
  final ringPercent = target == null
      ? null
      : (entries >= target ? 100 : roundedQuotient(100 * entries, target));

  final progress = _progress(entries, target);

  final labels = ComparisonLabels.forWeek(today);
  final factory = FigureFactory(
    labels: labels,
    baseProblem: comparisonBaseProblem(
      previousStart: previousWeekStart,
      usageStart: usageStart,
    ),
    usageStart: usageStart,
  );
  final figures = [
    factory.build(
      key: AnalysisFigureKeys.workoutWeekCount,
      metric: AnalysisMetric.workoutWeek,
      label: 'Anzahl',
      tableLabel: 'Workouts diese Woche, Anzahl',
      unit: FigureUnit.workouts,
      current: current.hasData ? Fraction(current.entries, 1) : null,
      previous: previous.hasData ? Fraction(previous.entries, 1) : null,
      kind: ComparisonKind.relative,
      coverage: _targetLine(entries, target),
    ),
    factory.build(
      key: AnalysisFigureKeys.workoutWeekMinutes,
      metric: AnalysisMetric.workoutWeek,
      label: 'Dauer gesamt',
      tableLabel: 'Workouts diese Woche, Dauer gesamt',
      unit: FigureUnit.workoutMinutes,
      current: current.hasData ? Fraction(current.minutes, 1) : null,
      previous: previous.hasData ? Fraction(previous.minutes, 1) : null,
      kind: ComparisonKind.relative,
    ),
  ];

  final rangeText = '${formatDateRange(weekStart, today)}, bis heute';
  final previousRangeText =
      'Vorwoche: ${formatDateRange(previousWeekStart, previousWeekEnd)}';
  final semantics = StringBuffer(
    '${AnalysisMetric.workoutWeek.title}, $rangeText. $progress. ',
  )..write(figures.map((figure) => figure.spokenText).join(' '));

  return WorkoutWeekCard(
    today: today,
    weekStart: weekStart,
    elapsedDays: elapsedDays,
    previousWeekStart: previousWeekStart,
    previousWeekEnd: previousWeekEnd,
    entries: entries,
    minutes: current.minutes,
    previousEntries: previous.entries,
    previousMinutes: previous.minutes,
    weeklyTarget: target,
    ringFraction: ringFraction,
    ringPercent: ringPercent,
    targetReached: reached,
    progressText: progress,
    rangeText: rangeText,
    previousRangeText: previousRangeText,
    figures: figures,
    semanticsLabel: semantics.toString(),
  );
}

String _progress(int entries, int? target) {
  String workouts(int count) =>
      '${formatThousands(count)} ${count == 1 ? 'Workout' : 'Workouts'}';
  if (target == null) {
    return entries == 0 ? 'Noch kein Workout diese Woche' : workouts(entries);
  }
  if (entries < target) {
    return '${formatThousands(entries)} von ${formatThousands(target)} '
        'Workouts';
  }
  if (entries == target) {
    return '${formatThousands(entries)} von ${formatThousands(target)} '
        'Workouts, Wochenziel erreicht';
  }
  return '${workouts(entries)}, Wochenziel ${formatThousands(target)} erreicht';
}

AnalysisLine? _targetLine(int entries, int? target) {
  if (target == null) {
    return null;
  }
  if (entries >= target) {
    return AnalysisLine('Wochenziel $target erreicht');
  }
  return AnalysisLine('Wochenziel $target, noch ${target - entries} offen');
}
