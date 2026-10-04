/// The table alternative of the analysis: the same data and formulas as the
/// cards, as accessible rows and columns.
///
/// - [AnalysisTable.periodTable]: one row per figure with current value,
///   previous value, change and coverage. The rows are the very same
///   [AnalysisFigure] objects as in the cards, so the numbers cannot differ.
/// - [AnalysisTable.weekTable]: the same for the workout week card.
/// - [AnalysisTable.dayTable]: one row per day of the period with the daily
///   values and the markers "Nicht erfasst" (steps, water, weight) and "–"
///   (does not apply). Oldest day first, as in the charts.
///
/// Every row also carries a complete sentence for screen readers.
library;

import 'package:self_improvement/core/analysis/domain/analysis_cards.dart';
import 'package:self_improvement/core/analysis/domain/analysis_charts.dart';
import 'package:self_improvement/core/analysis/domain/analysis_dates.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_figures.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_texts.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/core/analysis/domain/workout_week.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// A table of figures (metric rows).
final class AnalysisFigureTable {
  AnalysisFigureTable({
    required this.caption,
    required List<String> headers,
    required List<AnalysisFigure> rows,
  }) : headers = List.unmodifiable(headers),
       rows = List.unmodifiable(rows);

  /// A description of the whole table (for the accessible table semantics).
  final String caption;

  /// Column headers: `Kennzahl`, the current range, the previous range,
  /// `Veränderung`, `Erfassung` (or `Wochenziel`).
  final List<String> headers;

  /// One row per figure. Cells: `tableLabel`, `currentText`, `previousText`,
  /// `changeText`, `coverage?.text`; `spokenText` is the row for screen
  /// readers.
  final List<AnalysisFigure> rows;
}

/// One cell of the per-day table.
final class AnalysisCell {
  const AnalysisCell({
    required this.text,
    required this.spoken,
    required this.marker,
  });

  /// The visible text: `7.450`, `Nicht erfasst`, `2 von 3`, `–`.
  final String text;

  /// The spoken text.
  final String spoken;

  /// What the cell stands for (a recorded value, not recorded, ...).
  final DayMarker marker;
}

/// One day of the per-day table.
final class AnalysisDayRow {
  AnalysisDayRow({
    required this.date,
    required this.dayText,
    required List<AnalysisCell> cells,
    required this.semanticsLabel,
  }) : cells = List.unmodifiable(cells);

  final LocalDate date;

  /// `Sa, 03.10.`
  final String dayText;

  /// One cell per column of [AnalysisDayTable.headers] (without the day
  /// column).
  final List<AnalysisCell> cells;

  /// The whole row: `Samstag, 03.10.2026: Schritte 7.450, Wasser nicht
  /// erfasst, ...`.
  final String semanticsLabel;
}

/// The per-day table.
final class AnalysisDayTable {
  AnalysisDayTable({
    required this.caption,
    required List<String> headers,
    required List<AnalysisDayRow> rows,
  }) : headers = List.unmodifiable(headers),
       rows = List.unmodifiable(rows);

  final String caption;

  /// The headers of the value columns (the day column is implicit and always
  /// first): only active modules have columns.
  final List<String> headers;

  /// One row per day, oldest first, today last.
  final List<AnalysisDayRow> rows;
}

/// All table views of the analysis.
final class AnalysisTable {
  const AnalysisTable({
    required this.periodTable,
    required this.weekTable,
    required this.dayTable,
  });

  /// Metric rows: current period against the previous period.
  final AnalysisFigureTable periodTable;

  /// Workout week rows, `null` when the focus module is off.
  final AnalysisFigureTable? weekTable;

  /// The daily values.
  final AnalysisDayTable dayTable;
}

/// A column of the per-day table.
final class _DayColumn {
  const _DayColumn(this.header, this.cell);

  final String header;
  final AnalysisCell Function(AnalysisDay day) cell;
}

AnalysisCell _recordedOrNot(bool recorded, String text, String spoken) =>
    recorded
    ? AnalysisCell(text: text, spoken: spoken, marker: DayMarker.recorded)
    : const AnalysisCell(
        text: analysisNotRecordedText,
        spoken: 'nicht erfasst',
        marker: DayMarker.notRecorded,
      );

AnalysisCell _activity(bool active, String text, String spoken, String none) =>
    AnalysisCell(
      text: text,
      spoken: active ? spoken : none,
      marker: active ? DayMarker.recorded : DayMarker.noActivity,
    );

List<_DayColumn> _columns({
  required Set<ModuleId> activeModules,
  required bool showDailyGoals,
}) => [
  if (activeModules.contains(ModuleId.body))
    _DayColumn('Schritte', (day) {
      final steps = day.stepsRecorded;
      return _recordedOrNot(
        steps != null,
        steps == null ? '' : formatThousands(steps),
        steps == null ? '' : spokenFigureValue(FigureUnit.steps, steps * 1.0),
      );
    }),
  if (activeModules.contains(ModuleId.nutrition))
    _DayColumn(
      'Wasser',
      (day) => _recordedOrNot(
        day.waterIsRecorded,
        formatFigureValue(FigureUnit.milliliters, day.waterMl * 1.0),
        spokenFigureValue(FigureUnit.milliliters, day.waterMl * 1.0),
      ),
    ),
  if (activeModules.contains(ModuleId.body))
    _DayColumn('Gewicht', (day) {
      final grams = day.weightGrams;
      return _recordedOrNot(
        grams != null,
        grams == null ? '' : formatFigureValue(FigureUnit.grams, grams * 1.0),
        grams == null ? '' : spokenFigureValue(FigureUnit.grams, grams * 1.0),
      );
    }),
  if (activeModules.contains(ModuleId.focus))
    _DayColumn(
      'Workouts',
      (day) => _activity(
        day.workoutEntries > 0,
        '${day.workoutEntries}',
        spokenFigureValue(FigureUnit.workouts, day.workoutEntries * 1.0),
        'kein Workout',
      ),
    ),
  if (activeModules.contains(ModuleId.focus))
    _DayColumn(
      'Fokuszeit',
      (day) => _activity(
        day.focusCompletedSessions > 0,
        formatFocusDuration(day.focusCompletedSeconds),
        spokenFocusDuration(day.focusCompletedSeconds),
        'keine Fokuszeit',
      ),
    ),
  if (activeModules.contains(ModuleId.tasks))
    _DayColumn(
      'Aufgaben',
      (day) => _activity(
        day.tasksCompleted > 0,
        '${day.tasksCompleted}',
        '${spokenFigureValue(FigureUnit.tasks, day.tasksCompleted * 1.0)} '
            'erledigt',
        'keine Aufgabe erledigt',
      ),
    ),
  if (activeModules.contains(ModuleId.tasks))
    _DayColumn(
      'Gewohnheiten',
      (day) => day.applicableHabits > 0
          ? AnalysisCell(
              text: '${day.fulfilledHabits} von ${day.applicableHabits}',
              spoken:
                  '${day.fulfilledHabits} von ${day.applicableHabits} '
                  '${pluralize(day.applicableHabits, 'Gewohnheit', 'Gewohnheiten')} '
                  'erfüllt',
              marker: day.fulfilledHabits > 0
                  ? DayMarker.recorded
                  : DayMarker.noActivity,
            )
          : const AnalysisCell(
              text: analysisDashText,
              spoken: 'keine Gewohnheit aktiv',
              marker: DayMarker.notApplicable,
            ),
    ),
  if (activeModules.contains(ModuleId.nutrition))
    _DayColumn(
      'Mahlzeiten',
      (day) => _activity(
        day.mealEntries > 0,
        '${day.mealEntries}',
        spokenFigureValue(FigureUnit.meals, day.mealEntries * 1.0),
        'keine Mahlzeit',
      ),
    ),
  if (activeModules.contains(ModuleId.nutrition))
    _DayColumn('Kalorien (bekannt)', _kcalCell),
  if (showDailyGoals)
    _DayColumn(
      'Tagesziele',
      (day) => day.hasApplicableGoals
          ? AnalysisCell(
              text: '${day.fulfilledGoals} von ${day.applicableGoals}',
              spoken:
                  '${day.fulfilledGoals} von ${day.applicableGoals} '
                  '${pluralize(day.applicableGoals, 'Tagesziel', 'Tageszielen')} '
                  'erfüllt${day.isCompleteDay ? ', Tag komplett' : ''}',
              marker: day.fulfilledGoals > 0
                  ? DayMarker.recorded
                  : DayMarker.noActivity,
            )
          : const AnalysisCell(
              text: analysisDashText,
              spoken: 'keine Tagesziele',
              marker: DayMarker.notApplicable,
            ),
    ),
];

AnalysisCell _kcalCell(AnalysisDay day) {
  if (day.mealEntries == 0) {
    return const AnalysisCell(
      text: analysisDashText,
      spoken: 'keine Mahlzeit',
      marker: DayMarker.notApplicable,
    );
  }
  if (day.mealsWithKcal == 0) {
    return const AnalysisCell(
      text: 'Keine Angabe',
      spoken: 'keine Kalorienangabe',
      marker: DayMarker.notRecorded,
    );
  }
  final kcal = formatFigureValue(FigureUnit.kcal, day.knownKcal * 1.0);
  final spoken = spokenFigureValue(FigureUnit.kcal, day.knownKcal * 1.0);
  if (day.mealsWithKcal < day.mealEntries) {
    return AnalysisCell(
      text: '$kcal ($analysisCaloriesIncompleteText)',
      spoken: '$spoken, $analysisCaloriesIncompleteText',
      marker: DayMarker.recorded,
    );
  }
  return AnalysisCell(text: kcal, spoken: spoken, marker: DayMarker.recorded);
}

/// Builds the table views.
///
/// - [cards] are the cards of the report (the metric rows are their figures,
///   in card order).
/// - [workoutWeek] is the week card, `null` when the focus module is off.
/// - [days] holds the per-day inputs (may be sparse).
AnalysisTable buildAnalysisTable({
  required AnalysisPeriodSpec period,
  required List<AnalysisCard> cards,
  required WorkoutWeekCard? workoutWeek,
  required Map<LocalDate, AnalysisDay> days,
  required Set<ModuleId> activeModules,
  required bool showDailyGoals,
}) {
  final length = period.length;
  final periodTable = AnalysisFigureTable(
    caption:
        'Kennzahlen der letzten ${length.days} Tage '
        '(${period.headerText}) im Vergleich mit den vorherigen '
        '${length.days} Tagen (${period.previousRangeText})',
    headers: [
      'Kennzahl',
      length.currentTitle,
      length.previousTitle,
      'Veränderung',
      'Erfassung',
    ],
    rows: [for (final card in cards) ...card.figures],
  );

  AnalysisFigureTable? weekTable;
  if (workoutWeek != null) {
    final labels = ComparisonLabels.forWeek(workoutWeek.today);
    weekTable = AnalysisFigureTable(
      caption:
          'Workouts diese Woche (${workoutWeek.rangeText}) im Vergleich mit '
          'der Vorwoche (${workoutWeek.previousRangeText})',
      headers: [
        'Kennzahl',
        labels.currentTitle,
        labels.previousTitle,
        'Veränderung',
        'Wochenziel',
      ],
      rows: workoutWeek.figures,
    );
  }

  final columns = _columns(
    activeModules: activeModules,
    showDailyGoals: showDailyGoals,
  );
  final rows = <AnalysisDayRow>[];
  for (final date in period.currentDays) {
    final day = days[date] ?? AnalysisDay(date: date);
    final cells = [for (final column in columns) column.cell(day)];
    final spokenCells = [
      for (var i = 0; i < columns.length; i++)
        '${columns[i].header} ${cells[i].spoken}',
    ];
    rows.add(
      AnalysisDayRow(
        date: date,
        dayText: formatShortWeekdayDate(date),
        cells: cells,
        semanticsLabel:
            '${formatLongWeekdayDate(date)}: ${spokenCells.join(', ')}',
      ),
    );
  }
  final dayTable = AnalysisDayTable(
    caption: 'Werte pro Tag, ${period.headerText}',
    headers: [for (final column in columns) column.header],
    rows: rows,
  );

  return AnalysisTable(
    periodTable: periodTable,
    weekTable: weekTable,
    dayTable: dayTable,
  );
}
