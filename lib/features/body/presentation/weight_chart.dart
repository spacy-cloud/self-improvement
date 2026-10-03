import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/body/domain/weight_calculations.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// Line chart of the daily weight: one point per day (the last measurement of
/// that day), a straight connection between measured days, no smoothing, no
/// forecast and no artificial zero for missing days (specification 6.2).
///
/// With a single point only the marker and its value are drawn. The chart is
/// decorative: the screen offers the same values as text and table (see
/// `ChartSummary`), so it is excluded from the accessibility tree there.
class WeightChart extends StatelessWidget {
  const WeightChart({
    required this.points,
    required this.today,
    required this.periodDays,
    super.key,
  });

  /// Measured days, ascending. Must not be empty.
  final List<WeightDayPoint> points;

  final LocalDate today;

  /// Length of the window in local days, ending today (7, 30 or 90).
  final int periodDays;

  /// Height of the plot including the axis labels.
  static const double height = 170;

  static const double _horizontalPadding = 10;
  static const double _axisHeight = 26;

  @override
  Widget build(BuildContext context) {
    assert(points.isNotEmpty, 'the empty state is handled by the screen');
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    final start = today.addDays(-(periodDays - 1));
    final lastIndex = periodDays - 1;
    final spots = [
      for (final point in points)
        FlSpot(start.daysUntil(point.date).toDouble(), point.grams / 1000),
    ];
    final values = [for (final spot in spots) spot.y];
    final lowest = values.reduce(math.min);
    final highest = values.reduce(math.max);
    final margin = math.max(0.4, (highest - lowest) * 0.3);
    final minY = lowest - margin;
    final maxY = highest + margin;
    final manyPoints = spots.length > 31;
    final labelStyle = AppTextStyles.captionDefault;
    final textScaler = MediaQuery.textScalerOf(context);

    final line = LineChartBarData(
      spots: spots,
      barWidth: 2.5,
      color: colors.primary,
      dotData: FlDotData(
        getDotPainter: (spot, percent, bar, index) {
          final isLast = index == spots.length - 1;
          if (isLast) {
            return FlDotCirclePainter(
              radius: 5,
              color: colors.primary,
              strokeWidth: 3,
              strokeColor: colors.surface,
            );
          }
          return FlDotCirclePainter(
            radius: manyPoints ? 0 : 3.5,
            color: colors.surface,
            strokeWidth: manyPoints ? 0 : 2,
            strokeColor: colors.primary,
          );
        },
      ),
      belowBarData: BarAreaData(
        show: spots.length > 1,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.primary.withValues(alpha: 0.22),
            colors.primary.withValues(alpha: 0),
          ],
        ),
      ),
    );

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plotWidth = constraints.maxWidth - 2 * _horizontalPadding;
          final visibleLabels = _labelIndexes(
            lastIndex: lastIndex,
            plotWidth: plotWidth,
            sample: periodDays == 7 ? 'Heute' : '28. Sep.',
            style: labelStyle,
            textScaler: textScaler,
          );
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: lastIndex.toDouble(),
                minY: minY,
                maxY: maxY,
                lineBarsData: [line],
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: (maxY - minY) / 3,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: colors.track,
                    strokeWidth: 1,
                    dashArray: const [4, 4],
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
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
                        if (!visibleLabels.contains(index)) {
                          return const SizedBox.shrink();
                        }
                        final isToday = index == lastIndex;
                        final date = start.addDays(index);
                        final text = isToday
                            ? 'Heute'
                            : (periodDays == 7
                                  ? weekdayTwoLetters(date)
                                  : formatDayMonth(date));
                        return SideTitleWidget(
                          meta: meta,
                          space: 8,
                          fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                          child: Text(
                            text,
                            maxLines: 1,
                            style: labelStyle.copyWith(
                              color: isToday
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                              fontWeight: isToday ? FontWeight.w600 : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
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
                    getTooltipItems: (touched) => [
                      for (final spot in touched)
                        LineTooltipItem(
                          formatKilograms((spot.y * 1000).round()),
                          AppTextStyles.captionStrong.copyWith(
                            color: colors.background,
                          ),
                        ),
                    ],
                  ),
                ),
                showingTooltipIndicators: [
                  ShowingTooltipIndicators([
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

  /// The axis positions that get a label: counted from today backwards so
  /// that "Heute" is always shown, spaced so that labels never overlap at the
  /// current text scale.
  static Set<int> _labelIndexes({
    required int lastIndex,
    required double plotWidth,
    required String sample,
    required TextStyle style,
    required TextScaler textScaler,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: sample, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final labelWidth = painter.width + 10;
    painter.dispose();
    final perDay = lastIndex == 0 ? plotWidth : plotWidth / lastIndex;
    final step = math.max(1, (labelWidth / perDay).ceil());
    return {for (var i = lastIndex; i >= 0; i -= step) i};
  }
}

/// Tiny curve of the dashboard card: the last seven days without axes. A
/// single measurement shows only its marker. Decorative: the card carries the
/// values as text.
class WeightSparkline extends StatelessWidget {
  const WeightSparkline({
    required this.points,
    required this.today,
    super.key,
    this.height = 34,
  });

  final List<WeightDayPoint> points;
  final LocalDate today;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(height: height);
    }
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    final start = today.addDays(-6);
    final spots = [
      for (final point in points)
        FlSpot(start.daysUntil(point.date).toDouble(), point.grams / 1000),
    ];
    final values = [for (final spot in spots) spot.y];
    final lowest = values.reduce(math.min);
    final highest = values.reduce(math.max);
    final margin = math.max(0.3, (highest - lowest) * 0.25);
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: 6,
              minY: lowest - margin,
              maxY: highest + margin,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  barWidth: 2,
                  color: colors.primary,
                  dotData: FlDotData(
                    checkToShowDot: (spot, bar) => spot == bar.spots.last,
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                          radius: 3.5,
                          color: colors.primary,
                          strokeWidth: 2,
                          strokeColor: colors.surface,
                        ),
                  ),
                  belowBarData: BarAreaData(
                    show: spots.length > 1,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colors.primary.withValues(alpha: 0.2),
                        colors.primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            duration: motion.standard,
            curve: motion.curve,
          ),
        ),
      ),
    );
  }
}
