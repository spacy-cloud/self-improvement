import 'package:flutter/material.dart';
import 'package:self_improvement/core/analysis/domain/analysis_cards.dart';
import 'package:self_improvement/core/analysis/domain/analysis_figures.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_visuals.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_widgets.dart';

/// One card of the analysis grid (Figma 4033:2): icon tile and title, the
/// headline value with its label and coverage (`Ø pro Tag`, `5/7 Tage
/// erfasst`), the comparison with the previous period, further figures, the
/// definitions and a visible status such as `Kalorien unvollständig`.
///
/// Every number and text comes from the [AnalysisCard] of the engine, so the
/// card, the table and the spoken label cannot disagree. Without data the card
/// says so (`Noch keine Daten`) and shows no number, never a fake 0. The whole
/// card is one block for screen readers (the label of the engine).
class AnalysisMetricCard extends StatelessWidget {
  const AnalysisMetricCard({required this.card, super.key});

  final AnalysisCard card;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final visual = metricVisual(card.metric);
    return AppCard(
      child: Semantics(
        container: true,
        label: card.semanticsLabel,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // A title that does not fit beside the icon moves below it instead
            // of breaking inside the word (narrow cells, large text).
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                AppIconTile(icon: visual.icon.data, accent: visual.accent),
                Text(
                  card.title,
                  style: AppTextStyles.bodyStrong.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (card.hasData)
              _CardFigures(card: card)
            else
              Text(
                card.emptyText,
                style: AppTextStyles.bodyRegular.copyWith(
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CardFigures extends StatelessWidget {
  const _CardFigures({required this.card});

  final AnalysisCard card;

  /// The figure that is shown big: the first one with a value (the weight
  /// change of a single measurement has none yet, then the last value leads).
  AnalysisFigure get _headline => card.figures.firstWhere(
    (figure) => figure.current != null,
    orElse: () => card.primary,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final headline = _headline;
    final secondary = AppTextStyles.captionDefault.copyWith(
      color: colors.textSecondary,
    );
    final others = card.figures
        .where((figure) => !identical(figure, headline))
        .toList(growable: false);
    // The reason of a missing comparison is spelled out once per distinct
    // sentence, so a card does not repeat it for every figure.
    final shown = <String>{?headline.explanation};
    bool explain(AnalysisFigure figure) {
      final text = figure.explanation;
      return text != null && shown.add(text);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // A long value shrinks instead of breaking its digits.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            headline.currentText,
            maxLines: 1,
            style: AppTextStyles.titleScreen.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(headline.label, style: secondary),
        if (headline.coverage != null)
          Text(headline.coverage!.text, style: secondary),
        if (headline.isCompared) ...<Widget>[
          const SizedBox(height: 8),
          FigureComparison(figure: headline),
        ],
        for (final figure in others) ...<Widget>[
          const SizedBox(height: 12),
          _FurtherFigure(figure: figure, explain: explain(figure)),
        ],
        for (final line in card.details) ...<Widget>[
          const SizedBox(height: 8),
          Text(line.text, style: secondary),
        ],
        if (card.statusText != null) ...<Widget>[
          const SizedBox(height: 8),
          AppBadge(
            label: card.statusText!,
            accent: AppAccent.nutrition,
            icon: AppIcon.info.data,
          ),
        ],
      ],
    );
  }
}

/// A further figure of a card: its label, the value, the basis and, when it is
/// compared, the change below.
class _FurtherFigure extends StatelessWidget {
  const _FurtherFigure({required this.figure, required this.explain});

  final AnalysisFigure figure;

  /// Whether the reason of a missing comparison is spelled out.
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
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            figure.currentText,
            maxLines: 1,
            style: AppTextStyles.titleCard.copyWith(color: colors.textPrimary),
          ),
        ),
        if (figure.coverage != null)
          Text(figure.coverage!.text, style: secondary),
        // A figure without a value (calories without any entry) already says
        // so; a second "Noch kein Vergleich" would only repeat it.
        if (figure.isCompared && figure.current != null) ...<Widget>[
          const SizedBox(height: 4),
          FigureComparison(figure: figure, showExplanation: explain),
        ],
      ],
    );
  }
}
