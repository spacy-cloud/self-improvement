/// The metric cards of the analysis, built from the aggregates of the current
/// and the previous period.
///
/// Only cards of ACTIVE modules are built (body: steps, weight; nutrition:
/// water, meals; focus: focus time, workouts; tasks: tasks, habits). The daily
/// goals card belongs to no module and needs at least one applicable goal. The
/// data of deactivated modules is not shown, but never deleted.
library;

import 'package:self_improvement/core/analysis/domain/analysis_dates.dart';
import 'package:self_improvement/core/analysis/domain/analysis_figures.dart';
import 'package:self_improvement/core/analysis/domain/analysis_math.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_texts.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/core/analysis/domain/period_stats.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// One card of the analysis screen.
///
/// The card is a title, a list of [figures] (the first one is the headline
/// figure), optional [details] and a [statusText]. When [hasData] is `false`
/// the UI shows [emptyText] instead of the figures.
final class AnalysisCard {
  AnalysisCard({
    required this.metric,
    required this.hasData,
    required this.emptyText,
    required List<AnalysisFigure> figures,
    List<AnalysisLine> details = const [],
    this.statusText,
    required this.semanticsLabel,
  }) : figures = List.unmodifiable(figures),
       details = List.unmodifiable(details);

  final AnalysisMetric metric;

  /// German title: `Schritte`.
  String get title => metric.title;

  /// The owning module, `null` for the daily goals card.
  ModuleId? get module => metric.module;

  /// Whether the CURRENT period has data for the headline figure. Without
  /// data show [emptyText]; there is never a fake 0.
  final bool hasData;

  /// `Noch keine Daten` (or a more specific empty text).
  final String emptyText;

  /// The figures: headline first. Each one carries current value, previous
  /// value, change, coverage and spoken text.
  final List<AnalysisFigure> figures;

  /// Explanatory lines below the figures (weight from-to, definitions).
  final List<AnalysisLine> details;

  /// A status that has to be visible, for example `Kalorien unvollständig`;
  /// `null` when there is nothing to flag.
  final String? statusText;

  /// The complete card for screen readers.
  final String semanticsLabel;

  /// The headline figure.
  AnalysisFigure get primary => figures.first;
}

String _cardSemantics({
  required AnalysisMetric metric,
  required bool hasData,
  required String emptyText,
  required List<AnalysisFigure> figures,
  required List<AnalysisLine> details,
  required String? statusText,
}) {
  if (!hasData) {
    return '${metric.title}. $emptyText.';
  }
  // Every figure label starts with the title of the metric.
  final buffer = StringBuffer(
    figures.map((figure) => figure.spokenText).join(' '),
  );
  if (statusText != null) {
    buffer.write(' $statusText.');
  }
  for (final detail in details) {
    buffer.write(' ${detail.spoken}');
  }
  return buffer.toString();
}

AnalysisCard _card({
  required AnalysisMetric metric,
  required bool hasData,
  required List<AnalysisFigure> figures,
  List<AnalysisLine> details = const [],
  String? statusText,
  String emptyText = analysisNoDataText,
}) => AnalysisCard(
  metric: metric,
  hasData: hasData,
  emptyText: emptyText,
  figures: figures,
  details: details,
  statusText: statusText,
  semanticsLabel: _cardSemantics(
    metric: metric,
    hasData: hasData,
    emptyText: emptyText,
    figures: figures,
    details: details,
    statusText: statusText,
  ),
);

/// `5/7 Tage erfasst`, spoken `an 5 von 7 Tagen erfasst`.
AnalysisLine _recordedCoverage(int recorded, int total) => AnalysisLine(
  '$recorded/$total Tage erfasst',
  spoken: 'an $recorded von $total Tagen erfasst',
);

/// `3/7 Tage gemessen`, spoken `an 3 von 7 Tagen gemessen`.
AnalysisLine _measuredCoverage(int measured, int total) => AnalysisLine(
  '$measured/$total Tage gemessen',
  spoken: 'an $measured von $total Tagen gemessen',
);

Fraction? _whole(bool hasData, int value) =>
    hasData ? Fraction(value, 1) : null;

/// Builds the cards of the analysis for the active modules.
///
/// - [current] and [previous] are the aggregates of the period and of its
///   directly preceding period.
/// - [usageStart] is the profile start date (comparison base check).
/// - [activeModules] are the modules that are on right now.
/// - [showDailyGoals] decides whether the daily goals card is part of the
///   result (at least one applicable goal ever).
///
/// Order: daily goals, steps, water, weight, workouts, focus, tasks, habits,
/// meals. The order is a suggestion; every card carries its [AnalysisMetric].
List<AnalysisCard> buildAnalysisCards({
  required AnalysisPeriodSpec period,
  required PeriodStats current,
  required PeriodStats previous,
  required LocalDate? usageStart,
  required Set<ModuleId> activeModules,
  required bool showDailyGoals,
}) {
  final factory = FigureFactory(
    labels: ComparisonLabels.forPeriod(period.length),
    baseProblem: period.baseProblem(usageStart),
    usageStart: usageStart,
  );
  return [
    if (showDailyGoals) _goalsCard(factory, current.goals, previous.goals),
    if (activeModules.contains(ModuleId.body))
      _stepsCard(factory, current.steps, previous.steps),
    if (activeModules.contains(ModuleId.nutrition))
      _waterCard(factory, current.water, previous.water),
    if (activeModules.contains(ModuleId.body))
      _weightCard(factory, current.weight, previous.weight),
    if (activeModules.contains(ModuleId.focus))
      _workoutsCard(factory, current.workouts, previous.workouts),
    if (activeModules.contains(ModuleId.focus))
      _focusCard(factory, current.focus, previous.focus),
    if (activeModules.contains(ModuleId.tasks))
      _tasksCard(factory, current.tasks, previous.tasks),
    if (activeModules.contains(ModuleId.tasks))
      _habitsCard(factory, current.habits, previous.habits),
    if (activeModules.contains(ModuleId.nutrition))
      _mealsCard(factory, current.meals, previous.meals),
  ];
}

AnalysisCard _stepsCard(FigureFactory f, StepsStats c, StepsStats p) {
  final coverage = _recordedCoverage(c.recordedDays, c.periodDays);
  final previousCoverage = _recordedCoverage(p.recordedDays, p.periodDays);
  return _card(
    metric: AnalysisMetric.steps,
    hasData: c.hasData,
    figures: [
      f.build(
        key: AnalysisFigureKeys.stepsAverage,
        metric: AnalysisMetric.steps,
        label: 'Ø pro Tag',
        tableLabel: 'Schritte, Ø pro erfasstem Tag',
        unit: FigureUnit.steps,
        current: c.averageFraction,
        previous: p.averageFraction,
        kind: ComparisonKind.relative,
        coverage: coverage,
        previousCoverage: previousCoverage,
      ),
      f.build(
        key: AnalysisFigureKeys.stepsTotal,
        metric: AnalysisMetric.steps,
        label: 'Gesamt',
        tableLabel: 'Schritte, gesamt',
        unit: FigureUnit.steps,
        current: _whole(c.hasData, c.totalSteps),
        previous: _whole(p.hasData, p.totalSteps),
        coverage: coverage,
        previousCoverage: previousCoverage,
      ),
    ],
  );
}

AnalysisCard _waterCard(FigureFactory f, WaterStats c, WaterStats p) {
  final coverage = _recordedCoverage(c.recordedDays, c.periodDays);
  final previousCoverage = _recordedCoverage(p.recordedDays, p.periodDays);
  return _card(
    metric: AnalysisMetric.water,
    hasData: c.hasData,
    figures: [
      f.build(
        key: AnalysisFigureKeys.waterAverage,
        metric: AnalysisMetric.water,
        label: 'Ø pro Tag',
        tableLabel: 'Wasser, Ø pro erfasstem Tag',
        unit: FigureUnit.milliliters,
        current: c.averageFraction,
        previous: p.averageFraction,
        kind: ComparisonKind.relative,
        coverage: coverage,
        previousCoverage: previousCoverage,
      ),
      f.build(
        key: AnalysisFigureKeys.waterTotal,
        metric: AnalysisMetric.water,
        label: 'Gesamt',
        tableLabel: 'Wasser, gesamt',
        unit: FigureUnit.milliliters,
        current: _whole(c.hasData, c.totalMl),
        previous: _whole(p.hasData, p.totalMl),
        coverage: coverage,
        previousCoverage: previousCoverage,
      ),
    ],
  );
}

AnalysisLine? _weightDetail(WeightStats stats) {
  final first = stats.first;
  final last = stats.last;
  if (first == null || last == null) {
    return null;
  }
  String kg(int grams) => formatFigureValue(FigureUnit.grams, grams.toDouble());
  String spokenKg(int grams) =>
      spokenFigureValue(FigureUnit.grams, grams.toDouble());
  if (stats.measuredDays < 2) {
    return AnalysisLine(
      'Eine Messung: ${kg(last.grams)} (${formatDayMonth(last.date)})',
      spoken:
          'Eine Messung: ${spokenKg(last.grams)} '
          'am ${formatLongWeekdayDate(last.date)}',
    );
  }
  return AnalysisLine(
    'Von ${kg(first.grams)} (${formatDayMonth(first.date)}) '
    'auf ${kg(last.grams)} (${formatDayMonth(last.date)})',
    spoken:
        'Von ${spokenKg(first.grams)} am ${formatLongWeekdayDate(first.date)} '
        'auf ${spokenKg(last.grams)} am ${formatLongWeekdayDate(last.date)}',
  );
}

AnalysisCard _weightCard(FigureFactory f, WeightStats c, WeightStats p) {
  final coverage = _measuredCoverage(c.measuredDays, c.periodDays);
  final previousCoverage = _measuredCoverage(p.measuredDays, p.periodDays);
  final change = c.changeGrams;
  final previousChange = p.changeGrams;
  final detail = _weightDetail(c);
  return _card(
    metric: AnalysisMetric.weight,
    hasData: c.hasData,
    figures: [
      f.build(
        key: AnalysisFigureKeys.weightChange,
        metric: AnalysisMetric.weight,
        label: 'Änderung im Zeitraum',
        tableLabel: 'Gewicht, Änderung vom ersten zum letzten Wert',
        unit: FigureUnit.gramsChange,
        current: change == null ? null : Fraction(change, 1),
        previous: previousChange == null ? null : Fraction(previousChange, 1),
        kind: ComparisonKind.absolute,
        coverage: coverage,
        previousCoverage: previousCoverage,
        // One measured day is data, but no change yet.
        noCurrentText: c.hasData ? analysisNoComparisonText : null,
      ),
      f.build(
        key: AnalysisFigureKeys.weightLast,
        metric: AnalysisMetric.weight,
        label: 'Letzter Wert',
        tableLabel: 'Gewicht, letzter Wert',
        unit: FigureUnit.grams,
        current: c.last == null ? null : Fraction(c.last!.grams, 1),
        previous: p.last == null ? null : Fraction(p.last!.grams, 1),
        kind: ComparisonKind.absolute,
        coverage: coverage,
        previousCoverage: previousCoverage,
      ),
    ],
    details: [?detail],
  );
}

AnalysisCard _workoutsCard(FigureFactory f, WorkoutStats c, WorkoutStats p) {
  return _card(
    metric: AnalysisMetric.workouts,
    hasData: c.hasData,
    figures: [
      f.build(
        key: AnalysisFigureKeys.workoutsCount,
        metric: AnalysisMetric.workouts,
        label: 'Anzahl',
        tableLabel: 'Workouts, Anzahl',
        unit: FigureUnit.workouts,
        current: _whole(c.hasData, c.entries),
        previous: _whole(p.hasData, p.entries),
        kind: ComparisonKind.relative,
      ),
      f.build(
        key: AnalysisFigureKeys.workoutsMinutes,
        metric: AnalysisMetric.workouts,
        label: 'Dauer gesamt',
        tableLabel: 'Workouts, Dauer gesamt',
        unit: FigureUnit.workoutMinutes,
        current: _whole(c.hasData, c.minutes),
        previous: _whole(p.hasData, p.minutes),
        kind: ComparisonKind.relative,
      ),
    ],
  );
}

AnalysisCard _focusCard(FigureFactory f, FocusStats c, FocusStats p) {
  return _card(
    metric: AnalysisMetric.focus,
    hasData: c.hasData,
    figures: [
      f.build(
        key: AnalysisFigureKeys.focusMinutes,
        metric: AnalysisMetric.focus,
        label: 'Fokuszeit gesamt',
        tableLabel: 'Fokuszeit, gesamt',
        unit: FigureUnit.focusSeconds,
        current: _whole(c.hasData, c.completedSeconds),
        previous: _whole(p.hasData, p.completedSeconds),
        kind: ComparisonKind.relative,
      ),
      f.build(
        key: AnalysisFigureKeys.focusSessions,
        metric: AnalysisMetric.focus,
        label: 'Sitzungen',
        tableLabel: 'Fokuszeit, abgeschlossene Sitzungen',
        unit: FigureUnit.focusSessions,
        current: _whole(c.hasData, c.completedSessions),
        previous: _whole(p.hasData, p.completedSessions),
        kind: ComparisonKind.relative,
      ),
    ],
    details: const [
      AnalysisLine(
        'Es zählen nur abgeschlossene Sitzungen. Workouts sind keine '
        'Fokuszeit.',
      ),
    ],
  );
}

AnalysisCard _tasksCard(FigureFactory f, TaskStats c, TaskStats p) {
  return _card(
    metric: AnalysisMetric.tasks,
    hasData: c.hasData,
    figures: [
      f.build(
        key: AnalysisFigureKeys.tasksCompleted,
        metric: AnalysisMetric.tasks,
        label: 'Erledigt',
        tableLabel: 'Aufgaben, erledigt',
        unit: FigureUnit.tasks,
        current: _whole(c.hasData, c.completed),
        previous: _whole(p.hasData, p.completed),
        kind: ComparisonKind.relative,
      ),
    ],
  );
}

AnalysisLine _habitCoverage(HabitStats stats) => AnalysisLine(
  '${formatThousands(stats.fulfilledHabitDays)} von '
  '${formatThousands(stats.applicableHabitDays)} '
  '${pluralize(stats.applicableHabitDays, 'Habit-Tag', 'Habit-Tagen')} '
  'erfüllt',
);

AnalysisCard _habitsCard(FigureFactory f, HabitStats c, HabitStats p) {
  return _card(
    metric: AnalysisMetric.habits,
    hasData: c.hasData,
    figures: [
      f.build(
        key: AnalysisFigureKeys.habitsFulfilment,
        metric: AnalysisMetric.habits,
        label: 'Erfüllte Habit-Tage',
        tableLabel: 'Gewohnheiten, erfüllte Habit-Tage',
        unit: FigureUnit.percent,
        current: c.ratioPercentFraction,
        previous: p.ratioPercentFraction,
        kind: ComparisonKind.percentagePoints,
        coverage: c.hasData ? _habitCoverage(c) : null,
        previousCoverage: p.hasData ? _habitCoverage(p) : null,
      ),
    ],
    details: const [
      AnalysisLine(
        'Ein Habit-Tag ist eine Gewohnheit an einem Tag, an dem sie galt.',
      ),
    ],
  );
}

AnalysisLine? _kcalCoverage(MealStats stats) => switch (stats.completeness) {
  MealCompleteness.none => null,
  MealCompleteness.complete => AnalysisLine(
    'Kalorien vollständig (${formatThousands(stats.meals)} '
    '${pluralize(stats.meals, 'Mahlzeit', 'Mahlzeiten')})',
  ),
  MealCompleteness.incomplete => AnalysisLine(
    '$analysisCaloriesIncompleteText: '
    '${formatThousands(stats.mealsWithKcal)} von '
    '${formatThousands(stats.meals)} '
    '${pluralize(stats.meals, 'Mahlzeit', 'Mahlzeiten')} mit Angabe',
  ),
};

AnalysisCard _mealsCard(FigureFactory f, MealStats c, MealStats p) {
  final kcalProblem =
      (c.completeness == MealCompleteness.incomplete ||
          p.completeness == MealCompleteness.incomplete)
      ? NoComparisonReason.incompleteCalories
      : null;
  final incomplete = c.completeness == MealCompleteness.incomplete;
  final kcal = c.kcalTotal;
  final previousKcal = p.kcalTotal;
  return _card(
    metric: AnalysisMetric.meals,
    hasData: c.hasData,
    figures: [
      f.build(
        key: AnalysisFigureKeys.mealsCount,
        metric: AnalysisMetric.meals,
        label: 'Anzahl',
        tableLabel: 'Mahlzeiten, Anzahl',
        unit: FigureUnit.meals,
        current: _whole(c.hasData, c.meals),
        previous: _whole(p.hasData, p.meals),
        kind: ComparisonKind.relative,
      ),
      f.build(
        key: AnalysisFigureKeys.mealsKcal,
        metric: AnalysisMetric.meals,
        label: 'Bekannte Kalorien',
        tableLabel: 'Mahlzeiten, bekannte Kalorien',
        unit: FigureUnit.kcal,
        current: kcal == null ? null : Fraction(kcal, 1),
        previous: previousKcal == null ? null : Fraction(previousKcal, 1),
        kind: ComparisonKind.relative,
        dataProblem: kcalProblem,
        coverage: _kcalCoverage(c),
        previousCoverage: _kcalCoverage(p),
      ),
    ],
    statusText: incomplete ? analysisCaloriesIncompleteText : null,
    details: [
      if (incomplete)
        AnalysisLine(
          '${formatThousands(c.mealsWithoutKcal)} von '
          '${formatThousands(c.meals)} '
          '${pluralize(c.meals, 'Mahlzeit', 'Mahlzeiten')} ohne '
          'Kalorienangabe. Die Summe enthält nur bekannte Werte.',
        ),
    ],
  );
}

AnalysisCard _goalsCard(FigureFactory f, GoalStats c, GoalStats p) {
  AnalysisLine complete(GoalStats s) =>
      AnalysisLine('${s.completeDays} von ${s.daysWithGoals} Tagen komplett');
  AnalysisLine active(GoalStats s) =>
      AnalysisLine('${s.activeDays} von ${s.daysWithGoals} Tagen aktiv');
  return _card(
    metric: AnalysisMetric.dailyGoals,
    hasData: c.hasData,
    emptyText: 'Keine Tagesziele in diesem Zeitraum',
    figures: [
      f.build(
        key: AnalysisFigureKeys.goalsComplete,
        metric: AnalysisMetric.dailyGoals,
        label: 'Kompletttage',
        tableLabel: 'Tagesziele, Kompletttage',
        unit: FigureUnit.percent,
        current: c.completeRatioFraction,
        previous: p.completeRatioFraction,
        kind: ComparisonKind.percentagePoints,
        coverage: c.hasData ? complete(c) : null,
        previousCoverage: p.hasData ? complete(p) : null,
      ),
      f.build(
        key: AnalysisFigureKeys.goalsActive,
        metric: AnalysisMetric.dailyGoals,
        label: 'Aktive Tage',
        tableLabel: 'Tagesziele, aktive Tage',
        unit: FigureUnit.percent,
        current: c.activeRatioFraction,
        previous: p.activeRatioFraction,
        kind: ComparisonKind.percentagePoints,
        coverage: c.hasData ? active(c) : null,
        previousCoverage: p.hasData ? active(p) : null,
      ),
    ],
    details: const [
      AnalysisLine(
        'Kompletttag: alle Tagesziele des Tages erfüllt. '
        'Aktiver Tag: mindestens ein Tagesziel erfüllt.',
      ),
      AnalysisLine('Es zählen nur Tage mit mindestens einem Tagesziel.'),
    ],
  );
}
