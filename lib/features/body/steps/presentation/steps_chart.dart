import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// Bar chart of the daily step totals: one bar per recorded day, no bar (and
/// no zero) for days without a record, a dashed line at the current goal.
///
/// Bars that reached their goal are drawn strong, the others light; the colour
/// is never the only cue because the screen carries the same values as text and
/// table (see `ChartSummary`), so the chart is excluded from the accessibility
/// tree there.
class StepsBarChart extends StatelessWidget {
  const StepsBarChart({
    required this.days,
    required this.today,
    required this.target,
    super.key,
  });

  /// One entry per day of the window, newest first (provider order).
  final List<StepsHistoryDay> days;

  final LocalDate today;

  /// The goal that applies today; null draws no goal line.
  final int? target;

  /// Height of the plot including the axis labels.
  static const double height = 190;

  static const double _axisHeight = 26;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    final ordered = days.reversed.toList();
    final count = ordered.length;
    var highest = target ?? 0;
    for (final day in ordered) {
      if (day.recorded && day.progress.steps > highest) {
        highest = day.progress.steps;
      }
    }
    final maxY = (highest == 0 ? 1000 : highest) * 1.2;
    final labelStyle = AppTextStyles.captionDefault;
    final textScaler = MediaQuery.textScalerOf(context);
    final goal = target;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final perDay = constraints.maxWidth / count;
          final barWidth = (perDay * 0.62).clamp(2.0, 28.0);
          final visible = _labelIndexes(
            count: count,
            plotWidth: constraints.maxWidth,
            sample: count <= 7 ? 'Heute' : '28. Sep.',
            style: labelStyle,
            textScaler: textScaler,
          );
          return BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(enabled: false),
              gridData: const FlGridData(show: false),
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
                      if (!visible.contains(index) ||
                          index < 0 ||
                          index >= count) {
                        return const SizedBox.shrink();
                      }
                      final isToday = index == count - 1;
                      final date = ordered[index].date;
                      final text = isToday
                          ? 'Heute'
                          : (count <= 7
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
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  if (goal != null)
                    HorizontalLine(
                      y: goal.toDouble(),
                      color: colors.textSecondary,
                      strokeWidth: 1,
                      dashArray: const [4, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(bottom: 2),
                        style: AppTextStyles.captionStrong.copyWith(
                          color: colors.textSecondary,
                        ),
                        labelResolver: (line) =>
                            'Ziel ${formatThousands(goal)}',
                      ),
                    ),
                ],
              ),
              barGroups: [
                for (var i = 0; i < count; i++)
                  if (ordered[i].recorded)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: ordered[i].progress.steps.toDouble(),
                          width: barWidth,
                          color: _barColor(colors, ordered[i]),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(math.min(6, barWidth / 2)),
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

  static Color _barColor(AppColors colors, StepsHistoryDay day) {
    final base = colors.moduleSteps;
    if (day.progress.target == null) {
      return base.withValues(alpha: 0.6);
    }
    return day.progress.reached ? base : base.withValues(alpha: 0.35);
  }

  /// The axis positions that get a label: counted from today backwards so that
  /// "Heute" is always shown, spaced so that labels never overlap.
  static Set<int> _labelIndexes({
    required int count,
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
    final perDay = plotWidth / count;
    final step = math.max(1, (labelWidth / perDay).ceil());
    return {for (var i = count - 1; i >= 0; i -= step) i};
  }
}
