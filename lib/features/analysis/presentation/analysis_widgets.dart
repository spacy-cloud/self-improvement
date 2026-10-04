import 'package:flutter/material.dart';
import 'package:self_improvement/core/analysis/domain/analysis_figures.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_visuals.dart';

/// Neutral pill with the change of a figure against the previous period, for
/// example `↑ +7 % (+470) gegenüber den vorherigen 7 Tagen`, or `Noch kein
/// Vergleich` when no comparison with a fitting base exists.
///
/// The colour is the neutral track colour for every direction: a change is
/// neither good nor bad (the analysis judges nothing), and the direction is
/// carried by the arrow and the sign in the text, never by colour alone.
/// Figures that are not compared (totals) draw nothing.
class ComparisonPill extends StatelessWidget {
  const ComparisonPill({required this.figure, super.key});

  final AnalysisFigure figure;

  @override
  Widget build(BuildContext context) {
    final text = figure.comparisonText;
    if (text == null) {
      return const SizedBox.shrink();
    }
    final colors = context.tokens.colors;
    final arrow = figure.hasComparison ? changeArrow(figure.changeText) : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.track,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              if (arrow != null)
                TextSpan(
                  text: '$arrow\u00a0',
                  style: AppTextStyles.captionStrong.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              TextSpan(
                text: text,
                style: figure.hasComparison
                    ? AppTextStyles.captionStrong.copyWith(
                        color: colors.textPrimary,
                      )
                    : AppTextStyles.captionDefault.copyWith(
                        color: colors.textSecondary,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The change of a figure against the previous period as plain text with the
/// direction arrow, for example `↑ +7 % (+470) gegenüber den vorherigen 7
/// Tagen`, or `Noch kein Vergleich`. Used on the metric cards; the hero card
/// uses the [ComparisonPill]. Figures that are not compared draw nothing.
class ComparisonLine extends StatelessWidget {
  const ComparisonLine({required this.figure, super.key});

  final AnalysisFigure figure;

  @override
  Widget build(BuildContext context) {
    final text = figure.comparisonText;
    if (text == null) {
      return const SizedBox.shrink();
    }
    final colors = context.tokens.colors;
    final arrow = figure.hasComparison ? changeArrow(figure.changeText) : null;
    return Text(
      arrow == null ? text : '$arrow\u00a0$text',
      style: figure.hasComparison
          ? AppTextStyles.captionStrong.copyWith(color: colors.textPrimary)
          : AppTextStyles.captionDefault.copyWith(color: colors.textSecondary),
    );
  }
}

/// The comparison of [figure] (a plain line or, with [pill], the pill) and,
/// when no comparison is possible, the one sentence that says why (`Im
/// Vergleichszeitraum liegen keine Daten vor.`).
class FigureComparison extends StatelessWidget {
  const FigureComparison({
    required this.figure,
    this.showExplanation = true,
    this.pill = false,
    super.key,
  });

  final AnalysisFigure figure;

  /// Whether the reason of a missing comparison is shown below the change.
  final bool showExplanation;

  /// Whether the change is drawn as a neutral pill instead of a plain line.
  final bool pill;

  @override
  Widget build(BuildContext context) {
    if (!figure.isCompared) {
      return const SizedBox.shrink();
    }
    final colors = context.tokens.colors;
    final explanation = figure.explanation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (pill)
          ComparisonPill(figure: figure)
        else
          ComparisonLine(figure: figure),
        if (showExplanation && explanation != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            explanation,
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// A short neutral note with an info glyph, for example the hint that a
/// comparison becomes possible on a date.
class AnalysisNote extends StatelessWidget {
  const AnalysisNote({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      label: text,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              AppIcon.info.data,
              size: 16,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A text action in the brand colour with a 48 px tap area (the "Als
/// Tabelle" link of the header line).
class AnalysisLinkAction extends StatelessWidget {
  const AnalysisLinkAction({
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    super.key,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSizes.touchMin,
          minWidth: AppSizes.touchMin,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.controlBorder,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: const RoundedRectangleBorder(
              borderRadius: AppRadii.controlBorder,
            ),
            focusColor: colors.focus.withValues(alpha: 0.2),
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  label,
                  style: AppTextStyles.bodyStrong.copyWith(
                    color: colors.primaryText,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
