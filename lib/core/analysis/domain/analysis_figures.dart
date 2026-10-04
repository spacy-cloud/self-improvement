/// A "figure" is one comparable number of a metric: the unit of a table row
/// and of the lines of a card. Cards and the table are built from the very same
/// figure objects, which is what guarantees that the table shows the same data
/// and formulas as the cards.
library;

import 'package:self_improvement/core/analysis/domain/analysis_dates.dart';
import 'package:self_improvement/core/analysis/domain/analysis_math.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_texts.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Stable keys of the figures (rows of the table, lines of the cards).
abstract final class AnalysisFigureKeys {
  static const String stepsAverage = 'steps.average';
  static const String stepsTotal = 'steps.total';
  static const String waterAverage = 'water.average';
  static const String waterTotal = 'water.total';
  static const String weightChange = 'weight.change';
  static const String weightLast = 'weight.last';
  static const String workoutsCount = 'workouts.count';
  static const String workoutsMinutes = 'workouts.minutes';
  static const String focusMinutes = 'focus.minutes';
  static const String focusSessions = 'focus.sessions';
  static const String tasksCompleted = 'tasks.completed';
  static const String habitsFulfilment = 'habits.fulfilment';
  static const String mealsCount = 'meals.count';
  static const String mealsKcal = 'meals.kcal';
  static const String goalsComplete = 'goals.complete';
  static const String goalsActive = 'goals.active';
  static const String workoutWeekCount = 'workoutWeek.count';
  static const String workoutWeekMinutes = 'workoutWeek.minutes';
}

/// The names of the two compared ranges in texts.
///
/// For the period cards `Letzte 7 Tage` against `Vorherige 7 Tage`; for the
/// workout week `Diese Woche (Mo bis Sa)` against `Vorwoche (Mo bis Sa)`. The
/// labels never call a 30 or 90 day base a "Vorwoche".
final class ComparisonLabels {
  const ComparisonLabels({
    required this.currentTitle,
    required this.previousTitle,
    required this.against,
  });

  /// Labels of a period: `Letzte 7 Tage` / `Vorherige 7 Tage` /
  /// `gegenüber den vorherigen 7 Tagen`.
  factory ComparisonLabels.forPeriod(AnalysisPeriodLength length) =>
      ComparisonLabels(
        currentTitle: length.currentTitle,
        previousTitle: length.previousTitle,
        against: length.againstPrevious,
      );

  /// Labels of the workout week to date of [today]: `Diese Woche (Mo bis Sa)`
  /// / `Vorwoche (Mo bis Sa)` / `gegenüber der Vorwoche (Mo bis Sa)`; on a
  /// Monday just `(Mo)`.
  factory ComparisonLabels.forWeek(LocalDate today) {
    final span = today.weekday == DateTime.monday
        ? 'Mo'
        : 'Mo bis ${weekdayShort(today)}';
    return ComparisonLabels(
      currentTitle: 'Diese Woche ($span)',
      previousTitle: 'Vorwoche ($span)',
      against: 'gegenüber der Vorwoche ($span)',
    );
  }

  /// Name of the current range: `Letzte 7 Tage`.
  final String currentTitle;

  /// Name of the comparison base: `Vorherige 7 Tage`.
  final String previousTitle;

  /// The comparison phrase: `gegenüber den vorherigen 7 Tagen`.
  final String against;
}

/// One comparable number: current value, previous value, the typed comparison
/// and all texts the UI needs.
final class AnalysisFigure {
  const AnalysisFigure({
    required this.key,
    required this.metric,
    required this.label,
    required this.tableLabel,
    required this.unit,
    required this.current,
    required this.previous,
    required this.currentText,
    required this.previousText,
    required this.changeText,
    required this.comparisonText,
    required this.coverage,
    required this.previousCoverage,
    required this.comparison,
    required this.explanation,
    required this.spokenText,
  });

  /// Stable key, see [AnalysisFigureKeys].
  final String key;

  final AnalysisMetric metric;

  /// Short label inside the card of the metric: `Ø pro Tag`.
  final String label;

  /// Unique label of the table row: `Schritte, Ø pro erfasstem Tag`.
  final String tableLabel;

  final FigureUnit unit;

  /// The numeric value of the current period in [unit] (percent for ratio
  /// figures); `null` without data. Never a fake 0.
  final double? current;

  /// The numeric value of the previous period; `null` without data.
  final double? previous;

  /// The current value as text (`7.450`, `2,15 l`), `–` without data. A
  /// weight change with fewer than two measured days reads
  /// `Noch kein Vergleich`.
  final String currentText;

  /// The previous value as text, `–` without data.
  final String previousText;

  /// The change as text: `+7 % (+470)`, `+0,2 kg`, `unverändert`,
  /// `Noch kein Vergleich`, or `–` for figures that are not compared.
  final String changeText;

  /// The change with its base, for the card:
  /// `+7 % (+470) gegenüber den vorherigen 7 Tagen` or `Noch kein
  /// Vergleich`; `null` for figures that are not compared.
  final String? comparisonText;

  /// How the current value is made up: `5/7 Tage erfasst`; `null` for figures
  /// without a basis line.
  final AnalysisLine? coverage;

  /// The same for the previous period.
  final AnalysisLine? previousCoverage;

  /// The typed comparison; `null` for figures that are never compared
  /// (totals).
  final PeriodComparison? comparison;

  /// Why there is no comparison (one neutral sentence); `null` when the
  /// comparison is available or the figure is not compared.
  final String? explanation;

  /// The whole row as one sentence for screen readers.
  final String spokenText;

  /// Whether the figure takes part in the period comparison at all.
  bool get isCompared => comparison != null;

  /// Whether a comparison with a fitting base exists.
  bool get hasComparison => comparison?.isAvailable ?? false;
}

/// Builds [AnalysisFigure]s with consistent rules and texts.
final class FigureFactory {
  const FigureFactory({
    required this.labels,
    required this.baseProblem,
    required this.usageStart,
  });

  final ComparisonLabels labels;

  /// Set when the previous range is not completely inside the usage window.
  final NoComparisonReason? baseProblem;

  /// The profile start date; used in explanations.
  final LocalDate? usageStart;

  /// Creates a figure.
  ///
  /// [current] and [previous] are `null` when the range has no data for the
  /// figure. [kind] `null` means "not compared" (a reference value such as a
  /// total). [noCurrentText] / [noPreviousText] replace the dash when a range
  /// has no value.
  AnalysisFigure build({
    required String key,
    required AnalysisMetric metric,
    required String label,
    required String tableLabel,
    required FigureUnit unit,
    required Fraction? current,
    required Fraction? previous,
    ComparisonKind? kind,
    NoComparisonReason? dataProblem,
    AnalysisLine? coverage,
    AnalysisLine? previousCoverage,
    String? noCurrentText,
    String? noPreviousText,
  }) {
    final comparison = kind == null
        ? null
        : comparePeriods(
            unit: unit,
            kind: kind,
            current: current,
            previous: previous,
            baseProblem: baseProblem,
            dataProblem: dataProblem,
          );
    final currentText = current == null
        ? (noCurrentText ?? analysisDashText)
        : formatFigureValue(unit, current.value);
    final previousText = previous == null
        ? (noPreviousText ?? analysisDashText)
        : formatFigureValue(unit, previous.value);
    final reason = comparison?.reason;
    return AnalysisFigure(
      key: key,
      metric: metric,
      label: label,
      tableLabel: tableLabel,
      unit: unit,
      current: current?.value,
      previous: previous?.value,
      currentText: currentText,
      previousText: previousText,
      changeText: comparison == null
          ? analysisDashText
          : formatChange(comparison),
      comparisonText: comparison == null
          ? null
          : formatComparisonSentence(comparison, labels.against),
      coverage: coverage,
      previousCoverage: previousCoverage,
      comparison: comparison,
      explanation: reason == null
          ? null
          : noComparisonExplanation(reason, usageStart: usageStart),
      spokenText: _spokenFigure(
        tableLabel: tableLabel,
        unit: unit,
        current: current,
        previous: previous,
        comparison: comparison,
        coverage: coverage,
        previousCoverage: previousCoverage,
        noCurrentSpoken: noCurrentText ?? 'keine Daten',
        noPreviousSpoken: noPreviousText ?? 'keine Daten',
      ),
    );
  }

  String _spokenFigure({
    required String tableLabel,
    required FigureUnit unit,
    required Fraction? current,
    required Fraction? previous,
    required PeriodComparison? comparison,
    required AnalysisLine? coverage,
    required AnalysisLine? previousCoverage,
    required String noCurrentSpoken,
    required String noPreviousSpoken,
  }) {
    final buffer = StringBuffer('$tableLabel: ');
    buffer.write(
      current == null
          ? noCurrentSpoken
          : spokenFigureValue(unit, current.value),
    );
    if (coverage != null) {
      buffer.write(', ${coverage.spoken}');
    }
    buffer.write('. ${labels.previousTitle}: ');
    buffer.write(
      previous == null
          ? noPreviousSpoken
          : spokenFigureValue(unit, previous.value),
    );
    if (previousCoverage != null) {
      buffer.write(', ${previousCoverage.spoken}');
    }
    buffer.write('.');
    if (comparison != null) {
      buffer.write(' ${spokenComparisonSentence(comparison, labels.against)}.');
    }
    return buffer.toString();
  }
}
