/// Chart series of the analysis: one value per day of the period.
///
/// A chart is only a presentation of the data of the cards and the table. Every
/// series carries an explicit marker per day and a complete text summary, so
/// the UI can offer an accessible alternative:
///
/// - Steps and water: a day without a record is value `0` with the marker
///   [DayMarker.notRecorded] ("Nicht erfasst"), a recorded zero is value `0`
///   with [DayMarker.recorded]. A 0 bar is never mistaken for a measurement.
/// - Activity series (workouts, focus, tasks): a day without activity is a
///   plain 0 ([DayMarker.noActivity]).
/// - Weight: only measured days have a value (`null` otherwise, never a zero
///   fill); the weight of a day is the LAST measurement of the day.
/// - Habits: value = fulfilled habits, [ChartPoint.outOf] = applicable habits;
///   a day without an applicable habit is [DayMarker.notApplicable].
library;

import 'package:self_improvement/core/analysis/domain/analysis_dates.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_texts.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/core/analysis/domain/period_stats.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// What a day of a series stands for.
enum DayMarker {
  /// A value was recorded (a recorded 0 included).
  recorded,

  /// Nothing was recorded (steps, water, weight): "Nicht erfasst".
  notRecorded,

  /// An activity metric without activity on this day: a plain 0.
  noActivity,

  /// The metric does not apply on this day (no habit active).
  notApplicable,
}

/// The unit of the values of a chart series.
enum ChartUnit {
  /// Steps.
  steps,

  /// Millilitres (water).
  milliliters,

  /// Grams (weight).
  grams,

  /// Minutes, possibly fractional (focus time).
  minutes,

  /// A plain count (workouts, tasks, habits).
  count,
}

/// One day of a chart series.
final class ChartPoint {
  const ChartPoint({
    required this.date,
    required this.index,
    required this.value,
    required this.outOf,
    required this.marker,
    required this.dayLabel,
    required this.dateLabel,
    required this.valueText,
    required this.semanticsLabel,
  });

  final LocalDate date;

  /// Position in the series: 0 is the oldest day, `days - 1` is today. Use it
  /// as the x value.
  final int index;

  /// The value to plot in the unit of the series; `null` where nothing is to
  /// be plotted (weight on unmeasured days, habits on days without habit).
  final double? value;

  /// Habits only: the number of applicable habits that day; otherwise `null`.
  final int? outOf;

  final DayMarker marker;

  /// Two letter weekday from the calendar: `Sa`.
  final String dayLabel;

  /// Day and month: `03.10.`.
  final String dateLabel;

  /// The value as text: `7.450`, `Nicht erfasst`, `2 von 3`, `–`.
  final String valueText;

  /// The day for screen readers: `Samstag, 03.10.2026: 7.450 Schritte`.
  final String semanticsLabel;

  /// Whether a value was recorded on this day.
  bool get isRecorded => marker == DayMarker.recorded;
}

/// A value series over the days of the period, oldest first, today last.
final class ChartSeries {
  ChartSeries({
    required this.metric,
    required this.title,
    required this.unit,
    required List<ChartPoint> points,
    required this.maxValue,
    required this.hasData,
    required this.summary,
  }) : points = List.unmodifiable(points);

  final AnalysisMetric metric;

  /// German title: `Schritte pro Tag`.
  final String title;

  /// The unit of [ChartPoint.value].
  final ChartUnit unit;

  /// Exactly one point per day of the period.
  final List<ChartPoint> points;

  /// The largest plotted value (0 without values), for axis scaling.
  final double maxValue;

  /// Whether the period has any data for this series.
  final bool hasData;

  /// The complete text alternative of the chart (German).
  final String summary;

  /// The points that carry a plottable value (weight: only measured days).
  List<ChartPoint> get plottedPoints =>
      points.where((point) => point.value != null).toList(growable: false);
}

/// Builds the chart series of the active modules for the days of [period].
///
/// [days] may be sparse: a missing day counts as nothing recorded.
/// [current] must be the aggregate of the same period (it feeds the summary
/// texts, so the texts and the cards cannot disagree).
///
/// Order: steps, water, weight, workouts, focus, tasks, habits.
List<ChartSeries> buildChartSeries({
  required AnalysisPeriodSpec period,
  required Map<LocalDate, AnalysisDay> days,
  required PeriodStats current,
  required Set<ModuleId> activeModules,
}) {
  final dates = period.currentDays;
  final list = [
    for (final date in dates) days[date] ?? AnalysisDay(date: date),
  ];
  final header = period.headerText;
  return [
    if (activeModules.contains(ModuleId.body))
      _stepsSeries(list, current.steps, header),
    if (activeModules.contains(ModuleId.nutrition))
      _waterSeries(list, current.water, header),
    if (activeModules.contains(ModuleId.body))
      _weightSeries(list, current.weight, header),
    if (activeModules.contains(ModuleId.focus))
      _workoutsSeries(list, current.workouts, header),
    if (activeModules.contains(ModuleId.focus))
      _focusSeries(list, current.focus, header),
    if (activeModules.contains(ModuleId.tasks))
      _tasksSeries(list, current.tasks, header),
    if (activeModules.contains(ModuleId.tasks))
      _habitsSeries(list, current.habits, header),
  ];
}

ChartPoint _point({
  required AnalysisDay day,
  required int index,
  required double? value,
  int? outOf,
  required DayMarker marker,
  required String valueText,
  required String spoken,
}) => ChartPoint(
  date: day.date,
  index: index,
  value: value,
  outOf: outOf,
  marker: marker,
  dayLabel: weekdayShort(day.date),
  dateLabel: formatDayMonth(day.date),
  valueText: valueText,
  semanticsLabel: '${formatLongWeekdayDate(day.date)}: $spoken',
);

double _maxOf(List<ChartPoint> points) {
  var max = 0.0;
  for (final point in points) {
    final value = point.value;
    if (value != null && value > max) {
      max = value;
    }
  }
  return max;
}

ChartSeries _series({
  required AnalysisMetric metric,
  required String title,
  required ChartUnit unit,
  required List<ChartPoint> points,
  required bool hasData,
  required String header,
  required String body,
}) => ChartSeries(
  metric: metric,
  title: title,
  unit: unit,
  points: points,
  maxValue: _maxOf(points),
  hasData: hasData,
  summary: hasData
      ? '$title, $header. $body'
      : '$title, $header. $analysisNoDataText.',
);

/// The point with the highest value (the earliest one on a tie), or `null`.
ChartPoint? _peak(List<ChartPoint> points) {
  ChartPoint? best;
  for (final point in points) {
    final value = point.value;
    if (value == null || point.marker != DayMarker.recorded) {
      continue;
    }
    if (best == null || value > best.value!) {
      best = point;
    }
  }
  return best;
}

ChartSeries _stepsSeries(
  List<AnalysisDay> days,
  StepsStats stats,
  String header,
) {
  final points = [
    for (var i = 0; i < days.length; i++)
      if (days[i].stepsRecorded case final steps?)
        _point(
          day: days[i],
          index: i,
          value: steps.toDouble(),
          marker: DayMarker.recorded,
          valueText: formatThousands(steps),
          spoken: spokenFigureValue(FigureUnit.steps, steps.toDouble()),
        )
      else
        _point(
          day: days[i],
          index: i,
          value: 0,
          marker: DayMarker.notRecorded,
          valueText: analysisNotRecordedText,
          spoken: 'nicht erfasst',
        ),
  ];
  final peak = _peak(points);
  final average = stats.average;
  return _series(
    metric: AnalysisMetric.steps,
    title: 'Schritte pro Tag',
    unit: ChartUnit.steps,
    points: points,
    hasData: stats.hasData,
    header: header,
    body:
        'An ${stats.recordedDays} von ${stats.periodDays} Tagen erfasst. '
        'Durchschnitt ${spokenFigureValue(FigureUnit.steps, average ?? 0)} '
        'pro erfasstem Tag. '
        'Höchster Wert ${spokenFigureValue(FigureUnit.steps, peak?.value ?? 0)} '
        'am ${formatLongWeekdayDate(peak?.date ?? days.first.date)}.',
  );
}

ChartSeries _waterSeries(
  List<AnalysisDay> days,
  WaterStats stats,
  String header,
) {
  final points = [
    for (var i = 0; i < days.length; i++)
      if (days[i].waterIsRecorded)
        _point(
          day: days[i],
          index: i,
          value: days[i].waterMl.toDouble(),
          marker: DayMarker.recorded,
          valueText: formatFigureValue(
            FigureUnit.milliliters,
            days[i].waterMl.toDouble(),
          ),
          spoken: spokenFigureValue(
            FigureUnit.milliliters,
            days[i].waterMl.toDouble(),
          ),
        )
      else
        _point(
          day: days[i],
          index: i,
          value: 0,
          marker: DayMarker.notRecorded,
          valueText: analysisNotRecordedText,
          spoken: 'nicht erfasst',
        ),
  ];
  final peak = _peak(points);
  final average = stats.average;
  return _series(
    metric: AnalysisMetric.water,
    title: 'Wasser pro Tag',
    unit: ChartUnit.milliliters,
    points: points,
    hasData: stats.hasData,
    header: header,
    body:
        'An ${stats.recordedDays} von ${stats.periodDays} Tagen erfasst. '
        'Durchschnitt '
        '${spokenFigureValue(FigureUnit.milliliters, average ?? 0)} '
        'pro erfasstem Tag. '
        'Höchster Wert '
        '${spokenFigureValue(FigureUnit.milliliters, peak?.value ?? 0)} '
        'am ${formatLongWeekdayDate(peak?.date ?? days.first.date)}.',
  );
}

ChartSeries _weightSeries(
  List<AnalysisDay> days,
  WeightStats stats,
  String header,
) {
  final points = [
    for (var i = 0; i < days.length; i++)
      if (days[i].weightGrams case final grams?)
        _point(
          day: days[i],
          index: i,
          value: grams.toDouble(),
          marker: DayMarker.recorded,
          valueText: formatFigureValue(FigureUnit.grams, grams.toDouble()),
          spoken: spokenFigureValue(FigureUnit.grams, grams.toDouble()),
        )
      else
        _point(
          day: days[i],
          index: i,
          value: null,
          marker: DayMarker.notRecorded,
          valueText: analysisNotRecordedText,
          spoken: 'nicht erfasst',
        ),
  ];
  final first = stats.first;
  final last = stats.last;
  final change = stats.changeGrams;
  final String body;
  if (first == null || last == null) {
    body = '';
  } else if (change == null) {
    body =
        'Eine Messung: '
        '${spokenFigureValue(FigureUnit.grams, last.grams.toDouble())} '
        'am ${formatLongWeekdayDate(last.date)}. Noch kein Vergleich.';
  } else {
    body =
        'An ${stats.measuredDays} von ${stats.periodDays} Tagen gemessen. '
        'Von ${spokenFigureValue(FigureUnit.grams, first.grams.toDouble())} '
        'am ${formatLongWeekdayDate(first.date)} auf '
        '${spokenFigureValue(FigureUnit.grams, last.grams.toDouble())} '
        'am ${formatLongWeekdayDate(last.date)}. '
        'Änderung '
        '${spokenFigureValue(FigureUnit.gramsChange, change.toDouble())}.';
  }
  return _series(
    metric: AnalysisMetric.weight,
    title: 'Gewicht, letzter Wert des Tages',
    unit: ChartUnit.grams,
    points: points,
    hasData: stats.hasData,
    header: header,
    body: body,
  );
}

ChartSeries _workoutsSeries(
  List<AnalysisDay> days,
  WorkoutStats stats,
  String header,
) {
  final points = [
    for (var i = 0; i < days.length; i++)
      _point(
        day: days[i],
        index: i,
        value: days[i].workoutEntries.toDouble(),
        marker: days[i].workoutEntries > 0
            ? DayMarker.recorded
            : DayMarker.noActivity,
        valueText: '${days[i].workoutEntries}',
        spoken: days[i].workoutEntries == 0
            ? 'kein Workout'
            : spokenFigureValue(
                FigureUnit.workouts,
                days[i].workoutEntries.toDouble(),
              ),
      ),
  ];
  return _series(
    metric: AnalysisMetric.workouts,
    title: 'Workouts pro Tag',
    unit: ChartUnit.count,
    points: points,
    hasData: stats.hasData,
    header: header,
    body:
        'Insgesamt '
        '${spokenFigureValue(FigureUnit.workouts, stats.entries.toDouble())} '
        'an ${stats.activeDays} '
        '${pluralize(stats.activeDays, 'Tag', 'Tagen')}, '
        '${spokenFigureValue(FigureUnit.workoutMinutes, stats.minutes.toDouble())} '
        'gesamt.',
  );
}

ChartSeries _focusSeries(
  List<AnalysisDay> days,
  FocusStats stats,
  String header,
) {
  final points = [
    for (var i = 0; i < days.length; i++)
      _point(
        day: days[i],
        index: i,
        value: days[i].focusCompletedSeconds / 60,
        marker: days[i].focusCompletedSessions > 0
            ? DayMarker.recorded
            : DayMarker.noActivity,
        valueText: formatFocusDuration(days[i].focusCompletedSeconds),
        spoken: days[i].focusCompletedSessions == 0
            ? 'keine Fokuszeit'
            : spokenFocusDuration(days[i].focusCompletedSeconds),
      ),
  ];
  return _series(
    metric: AnalysisMetric.focus,
    title: 'Fokuszeit pro Tag',
    unit: ChartUnit.minutes,
    points: points,
    hasData: stats.hasData,
    header: header,
    body:
        'Insgesamt ${spokenFocusDuration(stats.completedSeconds)} in '
        '${spokenFigureValue(FigureUnit.focusSessions, stats.completedSessions.toDouble())} '
        'an ${stats.activeDays} '
        '${pluralize(stats.activeDays, 'Tag', 'Tagen')}.',
  );
}

ChartSeries _tasksSeries(
  List<AnalysisDay> days,
  TaskStats stats,
  String header,
) {
  final points = [
    for (var i = 0; i < days.length; i++)
      _point(
        day: days[i],
        index: i,
        value: days[i].tasksCompleted.toDouble(),
        marker: days[i].tasksCompleted > 0
            ? DayMarker.recorded
            : DayMarker.noActivity,
        valueText: '${days[i].tasksCompleted}',
        spoken: days[i].tasksCompleted == 0
            ? 'keine Aufgabe erledigt'
            : '${spokenFigureValue(FigureUnit.tasks, days[i].tasksCompleted.toDouble())} erledigt',
      ),
  ];
  return _series(
    metric: AnalysisMetric.tasks,
    title: 'Erledigte Aufgaben pro Tag',
    unit: ChartUnit.count,
    points: points,
    hasData: stats.hasData,
    header: header,
    body:
        'Insgesamt '
        '${spokenFigureValue(FigureUnit.tasks, stats.completed.toDouble())} '
        'erledigt an ${stats.activeDays} '
        '${pluralize(stats.activeDays, 'Tag', 'Tagen')}.',
  );
}

ChartSeries _habitsSeries(
  List<AnalysisDay> days,
  HabitStats stats,
  String header,
) {
  final points = [
    for (var i = 0; i < days.length; i++)
      if (days[i].applicableHabits > 0)
        _point(
          day: days[i],
          index: i,
          value: days[i].fulfilledHabits.toDouble(),
          outOf: days[i].applicableHabits,
          marker: days[i].fulfilledHabits > 0
              ? DayMarker.recorded
              : DayMarker.noActivity,
          valueText:
              '${days[i].fulfilledHabits} von ${days[i].applicableHabits}',
          spoken:
              '${days[i].fulfilledHabits} von ${days[i].applicableHabits} '
              '${pluralize(days[i].applicableHabits, 'Gewohnheit', 'Gewohnheiten')} '
              'erfüllt',
        )
      else
        _point(
          day: days[i],
          index: i,
          value: null,
          marker: DayMarker.notApplicable,
          valueText: analysisDashText,
          spoken: 'keine Gewohnheit aktiv',
        ),
  ];
  final percent = stats.ratioPercentRounded;
  return _series(
    metric: AnalysisMetric.habits,
    title: 'Erfüllte Gewohnheiten pro Tag',
    unit: ChartUnit.count,
    points: points,
    hasData: stats.hasData,
    header: header,
    body:
        '${formatThousands(stats.fulfilledHabitDays)} von '
        '${formatThousands(stats.applicableHabitDays)} '
        '${pluralize(stats.applicableHabitDays, 'Habit-Tag', 'Habit-Tagen')} '
        'erfüllt${percent == null ? '' : ', $percent Prozent'}.',
  );
}
