import 'package:flutter/material.dart';
import 'package:self_improvement/core/analysis/domain/analysis_charts.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/analysis/domain/analysis_texts.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_charts.dart';

/// The charts of the selected period, one card per series with data. Every
/// chart comes with its text summary and the table of the very same values
/// (`ChartSummary`): the chart is decorative, the text and the table carry the
/// meaning. A series without data is not drawn; its card in the grid says
/// `Noch keine Daten`.
class AnalysisChartSection extends StatelessWidget {
  const AnalysisChartSection({required this.report, super.key});

  final AnalysisReport report;

  @override
  Widget build(BuildContext context) {
    final charts = <ChartSeries>[
      for (final series in report.charts)
        if (series.hasData) series,
    ];
    if (charts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(title: 'Verlauf', subtitle: report.periodText),
        const SizedBox(height: 8),
        for (final series in charts) ...<Widget>[
          // The key keeps the expanded table of a chart when the period
          // changes and other charts appear or disappear.
          AnalysisChartCard(
            key: ValueKey<AnalysisMetric>(series.metric),
            report: report,
            series: series,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// One chart with its text alternative and its table.
class AnalysisChartCard extends StatelessWidget {
  const AnalysisChartCard({
    required this.report,
    required this.series,
    super.key,
  });

  final AnalysisReport report;
  final ChartSeries series;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final reference = _reference();
    final hint = _hint(series.metric, reference?.label);
    return ChartSummary(
      title: series.title,
      summary: series.summary,
      columns: <String>[series.metric.title],
      rows: <ChartSummaryRow>[
        for (final point in series.points)
          ChartSummaryRow(
            label: '${point.dayLabel}, ${point.dateLabel}',
            values: <String>[point.valueText],
          ),
      ],
      chart: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AnalysisSeriesChart(series: series, referenceValue: reference?.value),
          if (hint != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              hint,
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The average per recorded day of steps and water (the figure of the
  /// card), drawn as a dashed line.
  ({double value, String label})? _reference() {
    switch (series.metric) {
      case AnalysisMetric.steps:
        final average = report.current.steps.average;
        return average == null
            ? null
            : (
                value: average,
                label: 'Ø ${formatFigureValue(FigureUnit.steps, average)}',
              );
      case AnalysisMetric.water:
        final average = report.current.water.average;
        return average == null
            ? null
            : (
                value: average,
                label:
                    'Ø ${formatFigureValue(FigureUnit.milliliters, average)}',
              );
      case _:
        return null;
    }
  }

  /// The visible explanation of what the dashed line, an empty slot or a
  /// missing point means; [average] is the text of the average line.
  static String? _hint(AnalysisMetric metric, String? average) =>
      switch (metric) {
        AnalysisMetric.steps || AnalysisMetric.water =>
          '${average == null ? '' : 'Gestrichelte Linie: $average pro '
                        'erfasstem Tag. '}'
              'Tage ohne Balken sind nicht erfasst. Ein schmaler Strich ist '
              'eine erfasste 0.',
        AnalysisMetric.weight => 'Nur Tage mit Messung sind eingezeichnet.',
        AnalysisMetric.habits =>
          'Balken: erfüllte Gewohnheiten. Schiene: Gewohnheiten, die an dem '
              'Tag galten.',
        _ => null,
      };
}
