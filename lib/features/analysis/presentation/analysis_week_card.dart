import 'package:flutter/material.dart';
import 'package:self_improvement/core/analysis/domain/analysis_figures.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/core/analysis/domain/workout_week.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_visuals.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_widgets.dart';

/// The separate workout week card: the current Monday-to-Sunday week up to
/// today against the same weekdays of the previous week, independent of the
/// selected period. A week to date is never compared with a whole week.
///
/// The ring shows the entries of the week against the weekly target and is
/// capped at 100 %, while the real number of workouts stays visible in the
/// text. Without a weekly target there is no ring. The whole card is one block
/// for screen readers (the label of the engine).
class AnalysisWeekCard extends StatelessWidget {
  const AnalysisWeekCard({required this.week, this.hiddenReason, super.key});

  final WorkoutWeekCard week;

  /// A reason of a missing comparison that the screen already says in the
  /// same words above the cards (an unknown usage start); the card then does
  /// not repeat it. A week has its own comparison base, so every other reason
  /// is spelled out here.
  final NoComparisonReason? hiddenReason;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final visual = metricVisual(week.countFigure.metric);
    final secondary = AppTextStyles.captionDefault.copyWith(
      color: colors.textSecondary,
    );
    final ring = week.ringFraction;
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          week.progressText,
          style: AppTextStyles.bodyStrong.copyWith(color: colors.textPrimary),
        ),
        for (final figure in week.figures) ...<Widget>[
          const SizedBox(height: 10),
          _WeekFigure(
            figure: figure,
            explain:
                identical(figure, week.countFigure) &&
                figure.comparison?.reason != hiddenReason,
          ),
        ],
        const SizedBox(height: 8),
        Text(week.previousRangeText, style: secondary),
      ],
    );
    return AppCard(
      child: Semantics(
        container: true,
        label: week.semanticsLabel,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppIconTile(icon: visual.icon.data, accent: visual.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        week.title,
                        style: AppTextStyles.titleCard.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(week.rangeText, style: secondary),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (ring == null)
              summary
            else if (useStackedLayout(context))
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Ring(week: week, fraction: ring),
                  const SizedBox(height: 12),
                  summary,
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Ring(week: week, fraction: ring),
                  const SizedBox(width: 16),
                  Expanded(child: summary),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.week, required this.fraction});

  final WorkoutWeekCard week;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return ProgressRing(
      value: fraction,
      semanticLabel: week.progressText,
      size: 84,
      strokeWidth: 9,
      color: colors.accentFill(AppAccent.workout),
      center: Text(
        '${week.entries}',
        style: AppTextStyles.titleScreen.copyWith(color: colors.textPrimary),
      ),
    );
  }
}

/// A figure of the week card: its label, the current value, the weekly target
/// (count only) and the change against the previous week to date or the reason
/// why there is none.
class _WeekFigure extends StatelessWidget {
  const _WeekFigure({required this.figure, required this.explain});

  final AnalysisFigure figure;

  /// Whether the reason of a missing comparison is spelled out (once, at the
  /// count; the minutes share it).
  final bool explain;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final secondary = AppTextStyles.captionDefault.copyWith(
      color: colors.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(figure.label, style: secondary),
        Text(
          figure.currentText,
          style: AppTextStyles.titleCard.copyWith(color: colors.textPrimary),
        ),
        if (figure.coverage != null)
          Text(figure.coverage!.text, style: secondary),
        if (figure.isCompared) ...<Widget>[
          const SizedBox(height: 4),
          FigureComparison(figure: figure, showExplanation: explain),
        ],
      ],
    );
  }
}
