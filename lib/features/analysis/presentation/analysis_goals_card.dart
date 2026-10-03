import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:self_improvement/core/analysis/domain/analysis_cards.dart';
import 'package:self_improvement/core/analysis/domain/analysis_texts.dart';
import 'package:self_improvement/core/analysis/domain/goal_days.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_visuals.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_widgets.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The hero card "Tagesziele komplett" (Figma 4033:2): the number of complete
/// days of the days that had goals (`5 von 7 Tagen`), the change against the
/// previous period and, for the 7 day period, the strip of the days with their
/// goal ring.
///
/// A complete day has at least one applicable goal and all fulfilled; only
/// days with at least one goal count. The numbers come from the engine card;
/// the strip from `AnalysisReport.goalDays`, which uses the same rule.
class AnalysisGoalsCard extends StatelessWidget {
  const AnalysisGoalsCard({
    required this.card,
    required this.completeDays,
    required this.daysWithGoals,
    required this.goalDays,
    required this.today,
    this.hiddenReason,
    super.key,
  });

  /// The daily goals card of the report.
  final AnalysisCard card;

  /// Complete days of the current period (the numerator).
  final int completeDays;

  /// Days of the current period that had at least one applicable goal.
  final int daysWithGoals;

  /// One entry per day of the current period, oldest first.
  final List<GoalDay> goalDays;

  final LocalDate today;

  /// A reason of a missing comparison that the screen already explains once
  /// (the previous period lies before the usage start).
  final NoComparisonReason? hiddenReason;

  /// The strip is drawn for one week only: longer periods are listed day by
  /// day in the table.
  static const int stripMaxDays = 7;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final complete = card.figures.first;
    final active = card.figures.length > 1 ? card.figures[1] : null;
    final secondary = AppTextStyles.captionDefault.copyWith(
      color: colors.textSecondary,
    );
    final showStrip = card.hasData && goalDays.length <= stripMaxDays;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            container: true,
            label: card.semanticsLabel,
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Tagesziele komplett',
                  style: AppTextStyles.titleCard.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                if (!card.hasData)
                  Text(
                    card.emptyText,
                    style: AppTextStyles.bodyRegular.copyWith(
                      color: colors.textSecondary,
                    ),
                  )
                else ...<Widget>[
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: '$completeDays von $daysWithGoals',
                              style: AppTextStyles.titleScreen.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                            TextSpan(
                              text:
                                  ' ${pluralize(daysWithGoals, 'Tag', 'Tagen')}',
                              style: AppTextStyles.bodyRegular.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ComparisonPill(figure: complete),
                    ],
                  ),
                  if (!complete.hasComparison &&
                      complete.explanation != null &&
                      complete.comparison?.reason != hiddenReason) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(complete.explanation!, style: secondary),
                  ],
                  if (active?.coverage != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(active!.coverage!.text, style: secondary),
                  ],
                ],
              ],
            ),
          ),
          if (showStrip) ...<Widget>[
            const SizedBox(height: 14),
            _GoalStrip(days: goalDays, today: today),
          ],
          if (card.hasData) ...<Widget>[
            for (final line in card.details) ...<Widget>[
              const SizedBox(height: 8),
              Text(line.text, style: secondary),
            ],
          ],
        ],
      ),
    );
  }
}

/// The strip of the days of the week: a check for a complete day, a ring for
/// a day with fulfilled goals, an empty ring for a day that had goals but none
/// fulfilled and a dash for a day without goals. The weekday under each marker
/// (`Heute` for today) and the spoken sentence of every day carry the state, so
/// the colour is never the only cue.
class _GoalStrip extends StatelessWidget {
  const _GoalStrip({required this.days, required this.today});

  final List<GoalDay> days;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final label =
        'Tagesziele pro Tag: '
        '${days.map((day) => day.semanticsLabel).join('. ')}';
    final scale = textScaleOf(context).clamp(1.0, 1.6);
    final scaler = MediaQuery.textScalerOf(context);
    // Every day is as wide as the wider of its marker and its label, so the
    // days sit evenly across the card on one row (also on a 320 px phone) and
    // pack to the left when large text needs more rows.
    final widths = <double>[
      for (final day in days)
        math.max(
              _StripDay.marker * scale,
              _labelWidth(_StripDay.labelOf(day, day.date == today), scaler),
            ) +
            2,
    ];
    final total = widths.fold<double>(0, (sum, width) => sum + width);
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gaps = days.length - 1;
          final free = constraints.maxWidth - total;
          final spacing = gaps > 0 && free / gaps >= 4 ? free / gaps : 8.0;
          return Wrap(
            spacing: spacing,
            runSpacing: 10,
            children: <Widget>[
              for (var i = 0; i < days.length; i++)
                SizedBox(
                  width: widths[i],
                  child: _StripDay(
                    day: days[i],
                    isToday: days[i].date == today,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static double _labelWidth(String text, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTextStyles.captionDefault.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

class _StripDay extends StatelessWidget {
  const _StripDay({required this.day, required this.isToday});

  final GoalDay day;
  final bool isToday;

  static const double marker = 30;

  /// The label under the marker: the weekday, `Heute` for today.
  static String labelOf(GoalDay day, bool isToday) =>
      isToday ? 'Heute' : weekdayTwoLetters(day.date);

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final scale = textScaleOf(context).clamp(1.0, 1.6);
    final size = marker * scale;
    final Widget markerWidget;
    if (day.isComplete) {
      markerWidget = SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primary,
            shape: BoxShape.circle,
          ),
          child: Icon(
            AppIcon.check.data,
            size: 18 * scale,
            color: colors.onPrimary,
          ),
        ),
      );
    } else {
      markerWidget = ProgressRing(
        value: day.fraction ?? 0,
        semanticLabel: day.semanticsLabel,
        size: marker,
        strokeWidth: 4,
        color: colors.primary,
        center: day.hasGoals
            ? null
            : Text(
                analysisDashText,
                style: AppTextStyles.captionStrong.copyWith(
                  color: colors.textSecondary,
                ),
              ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        markerWidget,
        const SizedBox(height: 4),
        Text(
          labelOf(day, isToday),
          maxLines: 1,
          style: AppTextStyles.captionDefault.copyWith(
            color: isToday ? colors.textPrimary : colors.textSecondary,
            fontWeight: isToday ? FontWeight.w700 : null,
          ),
        ),
      ],
    );
  }
}
