import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:self_improvement/core/analysis/domain/analysis_charts.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_visuals.dart';
import 'package:self_improvement/shared/german_date.dart';

/// Height of the plot including the axis labels.
const double analysisChartHeight = 170;

const double _axisHeight = 26;

/// The chart of one series of the report: a line for the weight (only the
/// measured days, a straight connection between them, never a zero for a
/// missing day) and a bar chart for everything else.
///
/// Charts are decorative: they are excluded from the accessibility tree by
/// `ChartSummary`, which carries the same data as a text summary and a table.
/// Colour is never the only cue: the day labels, the empty rail of a day
/// without record and the visible hint under the chart say what is drawn.
class AnalysisSeriesChart extends StatelessWidget {
  const AnalysisSeriesChart({
    required this.series,
    this.referenceValue,
    super.key,
  });

  final ChartSeries series;

  /// A dashed reference line (the average per recorded day of steps and
  /// water), computed by the engine; `null` draws none. The value is named in
  /// the text under the chart, not inside the plot, so it never covers a bar.
  final double? referenceValue;

  @override
  Widget build(BuildContext context) {
    final accent = metricVisual(series.metric).accent;
    if (series.metric == AnalysisMetric.weight) {
      return AnalysisLineChart(series: series, accent: accent);
    }
    return AnalysisBarChart(
      series: series,
      accent: accent,
      referenceValue: referenceValue,
    );
  }
}

/// Bar chart with one bar per day of the period (7, 30 or 90).
///
/// Every day has an empty rail. A recorded value is a bar on its rail, a day
/// without a record (steps, water) keeps the empty rail, and a recorded zero is
/// a thin stub, so "not recorded" and "recorded 0" differ in the picture as
/// well as in the text. Activity series (workouts, focus, tasks) draw a plain
/// 0 as no bar. Habits draw the fulfilled habits on a rail as high as the
/// habits that applied that day.
class AnalysisBarChart extends StatelessWidget {
  const AnalysisBarChart({
    required this.series,
    required this.accent,
    this.referenceValue,
    super.key,
  });

  final ChartSeries series;
  final AppAccent accent;
  final double? referenceValue;

  /// The share of the axis a recorded zero is drawn with, so it stays visible.
  static const double zeroStub = 0.025;

  /// The highest value the axis has to show: the largest bar, the largest rail
  /// of the habit series and the reference line.
  double get _highest {
    var highest = series.maxValue;
    for (final point in series.points) {
      final outOf = point.outOf;
      if (outOf != null && outOf > highest) {
        highest = outOf.toDouble();
      }
    }
    final reference = referenceValue;
    if (reference != null && reference > highest) {
      highest = reference;
    }
    return highest;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    final points = series.points;
    final count = points.length;
    final highest = _highest;
    final maxY = (highest <= 0 ? 1.0 : highest) * 1.2;
    final isHabits = series.metric == AnalysisMetric.habits;
    final marksNotRecorded =
        series.metric == AnalysisMetric.steps ||
        series.metric == AnalysisMetric.water;
    final fill = colors.accentFill(accent);
    final rail = colors.track;
    final reference = referenceValue;

    return SizedBox(
      height: analysisChartHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final perDay = constraints.maxWidth / count;
          final barWidth = (perDay * 0.62).clamp(2.0, 28.0);
          final visible = chartLabelIndexes(
            count: count,
            plotWidth: constraints.maxWidth,
            sample: count <= 7 ? 'Mo' : '28.09.',
            textScaler: MediaQuery.textScalerOf(context),
          );
          return BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(enabled: false),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: _titles(colors, points, visible),
              extraLinesData: ExtraLinesData(
                horizontalLines: <HorizontalLine>[
                  if (reference != null)
                    HorizontalLine(
                      y: reference,
                      color: colors.textSecondary,
                      strokeWidth: 1,
                      dashArray: const <int>[4, 4],
                    ),
                ],
              ),
              barGroups: <BarChartGroupData>[
                for (var i = 0; i < count; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: <BarChartRodData>[
                      BarChartRodData(
                        toY: _barHeight(points[i], maxY, marksNotRecorded),
                        width: barWidth,
                        color: fill,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(math.min(6, barWidth / 2)),
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: isHabits ? (points[i].outOf ?? 0) * 1.0 : maxY,
                          color: rail,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            duration: motion.standard,
            curve: motion.curve,
          );
        },
      ),
    );
  }

  /// The drawn height of a day: nothing without a record, a stub for a recorded
  /// zero of steps and water, otherwise the value.
  static double _barHeight(ChartPoint point, double maxY, bool marksStub) {
    if (point.marker == DayMarker.notRecorded ||
        point.marker == DayMarker.notApplicable) {
      return 0;
    }
    final value = point.value ?? 0;
    if (value <= 0) {
      return marksStub && point.marker == DayMarker.recorded
          ? maxY * zeroStub
          : 0;
    }
    return value;
  }
}

/// Line chart of the weight: the last value of every measured day, straight
/// lines between measured days (no smoothing, no forecast, no zero for a day
/// without a measurement). With a single measurement only its marker and value
/// are drawn.
class AnalysisLineChart extends StatelessWidget {
  const AnalysisLineChart({
    required this.series,
    required this.accent,
    super.key,
  });

  final ChartSeries series;
  final AppAccent accent;

  static const double _horizontalPadding = 10;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    final points = series.points;
    final count = points.length;
    final measured = series.plottedPoints;
    final spots = <FlSpot>[
      for (final point in measured)
        FlSpot(point.index.toDouble(), point.value! / 1000),
    ];
    final values = <double>[for (final spot in spots) spot.y];
    final lowest = values.reduce(math.min);
    final highest = values.reduce(math.max);
    final margin = math.max(0.4, (highest - lowest) * 0.3);
    final fill = colors.accentFill(accent);
    final manyPoints = spots.length > 31;
    final line = LineChartBarData(
      spots: spots,
      barWidth: 2.5,
      color: fill,
      dotData: FlDotData(
        getDotPainter: (spot, percent, bar, index) {
          final isLast = index == spots.length - 1;
          if (isLast) {
            return FlDotCirclePainter(
              radius: 5,
              color: fill,
              strokeWidth: 3,
              strokeColor: colors.surface,
            );
          }
          return FlDotCirclePainter(
            radius: manyPoints ? 0 : 3.5,
            color: colors.surface,
            strokeWidth: manyPoints ? 0 : 2,
            strokeColor: fill,
          );
        },
      ),
      belowBarData: BarAreaData(
        show: spots.length > 1,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            fill.withValues(alpha: 0.22),
            fill.withValues(alpha: 0),
          ],
        ),
      ),
    );

    return SizedBox(
      height: analysisChartHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plotWidth = constraints.maxWidth - 2 * _horizontalPadding;
          final visible = chartLabelIndexes(
            count: count,
            plotWidth: plotWidth,
            sample: count <= 7 ? 'Mo' : '28.09.',
            textScaler: MediaQuery.textScalerOf(context),
          );
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (count - 1).toDouble(),
                minY: lowest - margin,
                maxY: highest + margin,
                lineBarsData: <LineChartBarData>[line],
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval:
                      (highest + margin - (lowest - margin)) / 3,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: colors.track,
                    strokeWidth: 1,
                    dashArray: const <int>[4, 4],
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: _titles(colors, points, visible),
                lineTouchData: LineTouchData(
                  enabled: false,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) => colors.textPrimary,
                    tooltipBorderRadius: BorderRadius.circular(8),
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    tooltipMargin: 10,
                    fitInsideHorizontally: true,
                    getTooltipItems: (touched) => <LineTooltipItem>[
                      for (final _ in touched)
                        LineTooltipItem(
                          measured.last.valueText,
                          AppTextStyles.captionStrong.copyWith(
                            color: colors.background,
                          ),
                        ),
                    ],
                  ),
                ),
                showingTooltipIndicators: <ShowingTooltipIndicators>[
                  ShowingTooltipIndicators(<LineBarSpot>[
                    LineBarSpot(line, 0, line.spots.last),
                  ]),
                ],
              ),
              duration: motion.standard,
              curve: motion.curve,
            ),
          );
        },
      ),
    );
  }
}

/// The bottom axis: the weekday for a week, the date for longer periods, and
/// `Heute` at the last day; only the positions of [visible] get a label.
FlTitlesData _titles(
  AppColors colors,
  List<ChartPoint> points,
  Set<int> visible,
) {
  final count = points.length;
  final labelStyle = AppTextStyles.captionDefault;
  return FlTitlesData(
    leftTitles: const AxisTitles(),
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: _axisHeight,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final index = value.round();
          if (!visible.contains(index) || index < 0 || index >= count) {
            return const SizedBox.shrink();
          }
          final isToday = index == count - 1;
          final point = points[index];
          final text = isToday
              ? 'Heute'
              : (count <= 7 ? weekdayTwoLetters(point.date) : point.dateLabel);
          return SideTitleWidget(
            meta: meta,
            space: 8,
            fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
            child: Text(
              text,
              maxLines: 1,
              style: labelStyle.copyWith(
                color: isToday ? colors.textPrimary : colors.textSecondary,
                fontWeight: isToday ? FontWeight.w600 : null,
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// The axis positions that get a label, counted from today backwards so that
/// `Heute` is always shown, spaced so that labels never overlap at the current
/// text scale. The spacing follows the widest label that can occur: the
/// semi-bold `Heute` or the longer of the two day texts ([sample]).
Set<int> chartLabelIndexes({
  required int count,
  required double plotWidth,
  required String sample,
  required TextScaler textScaler,
}) {
  double widthOf(String text, FontWeight? weight) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTextStyles.captionDefault.copyWith(fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  final labelWidth =
      math.max(widthOf('Heute', FontWeight.w600), widthOf(sample, null)) + 10;
  final perDay = count <= 1 ? plotWidth : plotWidth / count;
  final step = math.max(1, (labelWidth / perDay).ceil());
  return <int>{for (var i = count - 1; i >= 0; i -= step) i};
}
