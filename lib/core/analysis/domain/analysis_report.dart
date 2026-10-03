/// The analysis report: one pure function from per-day inputs to everything
/// the analysis screen shows.
library;

import 'package:self_improvement/core/analysis/domain/analysis_cards.dart';
import 'package:self_improvement/core/analysis/domain/analysis_charts.dart';
import 'package:self_improvement/core/analysis/domain/analysis_dates.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_table.dart';
import 'package:self_improvement/core/analysis/domain/analysis_texts.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/core/analysis/domain/period_stats.dart';
import 'package:self_improvement/core/analysis/domain/workout_week.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Everything the analysis screen shows for one period.
///
/// - [cards]: the metric cards of the ACTIVE modules (plus the daily goals
///   card when at least one goal ever applied). The data of deactivated
///   modules is not shown, but never deleted.
/// - [workoutWeek]: the separate Monday-to-Sunday workout week card (focus
///   module), `null` when the module is off.
/// - [charts]: one series per chart of an active module, with a text summary.
/// - [table]: the table alternative with the same figures as the cards.
/// - [current] / [previous]: the typed aggregates of the two periods.
///
/// All texts are German, ready to display, and free of judgement: no colours
/// or wording imply good or bad. There is no sleep, no distance and no
/// calorie value without data.
final class AnalysisReport {
  AnalysisReport({
    required this.period,
    required this.usageStart,
    required Set<ModuleId> activeModules,
    required this.current,
    required this.previous,
    required List<AnalysisCard> cards,
    required this.workoutWeek,
    required List<ChartSeries> charts,
    required this.table,
    required this.comparisonBaseProblem,
    required this.comparisonNote,
  }) : activeModules = Set.unmodifiable(activeModules),
       cards = List.unmodifiable(cards),
       charts = List.unmodifiable(charts);

  /// The period (length and today) this report is about.
  final AnalysisPeriodSpec period;

  /// The profile start date: nothing counts as "usage" before it; `null`
  /// when unknown.
  final LocalDate? usageStart;

  /// The modules that were active when the report was built.
  final Set<ModuleId> activeModules;

  /// Aggregates of the current period.
  final PeriodStats current;

  /// Aggregates of the directly preceding period of the same length.
  final PeriodStats previous;

  final List<AnalysisCard> cards;

  final WorkoutWeekCard? workoutWeek;

  final List<ChartSeries> charts;

  final AnalysisTable table;

  /// `null` when the previous period lies completely inside the usage window.
  /// Otherwise the reason why every comparison reads "Noch kein Vergleich".
  final NoComparisonReason? comparisonBaseProblem;

  /// A neutral hint when comparisons are not possible yet, for example `Ein
  /// Vergleich mit den vorherigen 7 Tagen ist ab dem 10.10.2026 möglich.`;
  /// `null` when the base fits.
  final String? comparisonNote;

  /// Header: `27.09. bis 03.10.2026, inklusive heute`.
  String get periodText => period.headerText;

  /// `Vorherige 7 Tage: 20.09. bis 26.09.2026`.
  String get previousPeriodText => period.previousHeaderText;

  /// Whether the previous period lies completely inside the usage window.
  bool get previousPeriodComparable => comparisonBaseProblem == null;

  /// Whether there is any card or week card to show.
  bool get hasCards => cards.isNotEmpty || workoutWeek != null;

  /// Whether no module is active at all.
  bool get noModuleActive => activeModules.isEmpty;

  /// Whether anything was recorded in the current period. `false` means the
  /// screen shows its honest empty state ("Noch keine Daten").
  ///
  /// The daily goals card alone does not count: goals that applied while
  /// nothing was recorded (a fresh start) are no data. It counts as soon as
  /// one goal was fulfilled on a day of the period.
  bool get hasAnyData =>
      cards.any(
        (card) => card.metric == AnalysisMetric.dailyGoals
            ? current.goals.activeDays > 0
            : card.hasData,
      ) ||
      (workoutWeek?.hasData ?? false);

  /// The card of [metric], or `null` when it is not part of the report (the
  /// module is off).
  AnalysisCard? cardFor(AnalysisMetric metric) {
    for (final card in cards) {
      if (card.metric == metric) {
        return card;
      }
    }
    return null;
  }

  /// The chart series of [metric], or `null`.
  ChartSeries? chartFor(AnalysisMetric metric) {
    for (final series in charts) {
      if (series.metric == metric) {
        return series;
      }
    }
    return null;
  }
}

/// Builds the [AnalysisReport] for [period] from the per-day inputs.
///
/// Pure and deterministic: the same inputs give the same report, nothing is
/// read from a clock or a database.
///
/// - [days]: the per-day inputs; they should cover `[period.windowStart,
///   period.today]` (the current and the previous period). A missing day
///   counts as "nothing recorded". If a date appears twice the last entry
///   wins.
/// - [usageStart]: the profile start date. The previous period has to lie
///   completely inside the usage window (it must not start before this date)
///   for any comparison.
/// - [activeModules]: the modules that are on; cards and series of other
///   modules are left out.
/// - [workoutWeeklyTarget]: the weekly workout target in effect today (default
///   [defaultWorkoutWeeklyTarget]); `null` when the weekly goal is off.
/// - [hasApplicableGoalEver]: whether the daily goals card is part of the
///   report: at least one goal applied on some day. When `null` it is derived
///   from [days].
AnalysisReport buildAnalysisReport({
  required AnalysisPeriodSpec period,
  required Iterable<AnalysisDay> days,
  required LocalDate? usageStart,
  required Set<ModuleId> activeModules,
  int? workoutWeeklyTarget = defaultWorkoutWeeklyTarget,
  bool? hasApplicableGoalEver,
}) {
  final byDate = <LocalDate, AnalysisDay>{
    for (final day in days) day.date: day,
  };
  final all = byDate.values.toList(growable: false);
  final current = computePeriodStats(
    days: all,
    start: period.start,
    end: period.end,
  );
  final previous = computePeriodStats(
    days: all,
    start: period.previousStart,
    end: period.previousEnd,
  );
  final showDailyGoals =
      hasApplicableGoalEver ?? all.any((day) => day.hasApplicableGoals);

  final cards = buildAnalysisCards(
    period: period,
    current: current,
    previous: previous,
    usageStart: usageStart,
    activeModules: activeModules,
    showDailyGoals: showDailyGoals,
  );
  final workoutWeek = activeModules.contains(ModuleId.focus)
      ? buildWorkoutWeekCard(
          today: period.today,
          days: all,
          usageStart: usageStart,
          weeklyTarget: workoutWeeklyTarget,
        )
      : null;
  final charts = buildChartSeries(
    period: period,
    days: byDate,
    current: current,
    activeModules: activeModules,
  );
  final table = buildAnalysisTable(
    period: period,
    cards: cards,
    workoutWeek: workoutWeek,
    days: byDate,
    activeModules: activeModules,
    showDailyGoals: showDailyGoals,
  );

  final baseProblem = period.baseProblem(usageStart);
  return AnalysisReport(
    period: period,
    usageStart: usageStart,
    activeModules: activeModules,
    current: current,
    previous: previous,
    cards: cards,
    workoutWeek: workoutWeek,
    charts: charts,
    table: table,
    comparisonBaseProblem: baseProblem,
    comparisonNote: _comparisonNote(period, baseProblem, usageStart),
  );
}

String? _comparisonNote(
  AnalysisPeriodSpec period,
  NoComparisonReason? baseProblem,
  LocalDate? usageStart,
) {
  switch (baseProblem) {
    case null:
      return null;
    case NoComparisonReason.noUsageStart:
      return noComparisonExplanation(NoComparisonReason.noUsageStart);
    case NoComparisonReason.previousPeriodBeforeStart:
      final from = period.comparisonAvailableFrom(usageStart);
      return from == null
          ? null
          : 'Ein Vergleich mit ${period.length.previousDative} ist ab dem '
                '${formatFullDate(from)} möglich.';
    case NoComparisonReason.noPreviousData ||
        NoComparisonReason.noCurrentData ||
        NoComparisonReason.previousIsZero ||
        NoComparisonReason.incompleteCalories:
      return null;
  }
}
