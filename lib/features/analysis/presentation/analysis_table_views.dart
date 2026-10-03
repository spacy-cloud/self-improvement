import 'package:flutter/material.dart';
import 'package:self_improvement/core/analysis/domain/analysis_figures.dart';
import 'package:self_improvement/core/analysis/domain/analysis_table.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_visuals.dart';

/// The table of figures (current value, previous value, change and basis) as
/// accessible rows. The rows are the very figures of the cards, so the table
/// shows the same data and formulas. Every row is one block for screen readers
/// that reads the complete sentence of the engine; the visible cells are
/// excluded from the tree, so nothing is read twice.
///
/// On large text (above 130 %) every row becomes a block of labelled lines
/// instead of columns, so nothing clips.
class AnalysisFigureTableView extends StatelessWidget {
  const AnalysisFigureTableView({required this.table, super.key});

  final AnalysisFigureTable table;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final stacked = useStackedLayout(context);
    final headStyle = AppTextStyles.captionStrong.copyWith(
      color: colors.textSecondary,
    );
    final headers = table.headers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!stacked)
          ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.borderInput, width: 1.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    flex: _labelFlex,
                    child: Text(headers[0], style: headStyle),
                  ),
                  for (var i = 1; i <= 3; i++)
                    Expanded(
                      flex: _valueFlexes[i - 1],
                      child: Text(
                        headers[i],
                        textAlign: TextAlign.end,
                        style: headStyle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        for (final figure in table.rows)
          _FigureRow(figure: figure, headers: headers, stacked: stacked),
      ],
    );
  }

  static const int _labelFlex = 34;
  static const List<int> _valueFlexes = <int>[20, 20, 26];
}

class _FigureRow extends StatelessWidget {
  const _FigureRow({
    required this.figure,
    required this.headers,
    required this.stacked,
  });

  final AnalysisFigure figure;
  final List<String> headers;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final labelStyle = AppTextStyles.bodyDefault.copyWith(
      color: colors.textPrimary,
    );
    final valueStyle = AppTextStyles.bodyRegular.copyWith(
      color: colors.textPrimary,
    );
    final secondary = AppTextStyles.captionDefault.copyWith(
      color: colors.textSecondary,
    );
    final basisHeader = headers.length > 4 ? headers[4] : 'Erfassung';
    final basis = <String>[
      if (figure.coverage != null) '$basisHeader: ${figure.coverage!.text}',
      if (figure.previousCoverage != null)
        '${headers[2]}: ${figure.previousCoverage!.text}',
    ];
    final explanation = figure.explanation;

    final Widget content;
    if (stacked) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(figure.tableLabel, style: labelStyle),
          const SizedBox(height: 2),
          Text('${headers[1]}: ${figure.currentText}', style: valueStyle),
          Text('${headers[2]}: ${figure.previousText}', style: valueStyle),
          Text('${headers[3]}: ${figure.changeText}', style: valueStyle),
          for (final line in basis) Text(line, style: secondary),
          if (explanation != null) Text(explanation, style: secondary),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: AnalysisFigureTableView._labelFlex,
                child: Text(figure.tableLabel, style: labelStyle),
              ),
              Expanded(
                flex: AnalysisFigureTableView._valueFlexes[0],
                child: Text(
                  figure.currentText,
                  textAlign: TextAlign.end,
                  style: valueStyle,
                ),
              ),
              Expanded(
                flex: AnalysisFigureTableView._valueFlexes[1],
                child: Text(
                  figure.previousText,
                  textAlign: TextAlign.end,
                  style: valueStyle,
                ),
              ),
              Expanded(
                flex: AnalysisFigureTableView._valueFlexes[2],
                child: Text(
                  figure.changeText,
                  textAlign: TextAlign.end,
                  style: valueStyle,
                ),
              ),
            ],
          ),
          for (final line in basis) ...<Widget>[
            const SizedBox(height: 2),
            Text(line, style: secondary),
          ],
          if (explanation != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(explanation, style: secondary),
          ],
        ],
      );
    }
    return Semantics(
      container: true,
      label: figure.spokenText,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.track)),
        ),
        child: content,
      ),
    );
  }
}

/// The per-day table: one block per day (oldest first, today last) with every
/// value of the active modules as a labelled pair. A day for which nothing was
/// recorded reads `Nicht erfasst` (steps, water, weight) instead of a 0, a day
/// to which a metric does not apply reads `–`.
///
/// Every day is one block for screen readers that reads the sentence of the
/// engine (`Samstag, 03.10.2026: Schritte 7.450, Wasser nicht erfasst, ...`).
class AnalysisDayTableView extends StatelessWidget {
  const AnalysisDayTableView({required this.table, super.key});

  final AnalysisDayTable table;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final labelStyle = AppTextStyles.captionDefault.copyWith(
      color: colors.textSecondary,
    );
    final valueStyle = AppTextStyles.bodyRegular.copyWith(
      color: colors.textPrimary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final row in table.rows)
          Semantics(
            container: true,
            label: row.semanticsLabel,
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.track)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    row.dayText,
                    style: AppTextStyles.bodyStrong.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: <Widget>[
                      for (var i = 0; i < table.headers.length; i++)
                        Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              TextSpan(
                                text: '${table.headers[i]}  ',
                                style: labelStyle,
                              ),
                              TextSpan(
                                text: row.cells[i].text,
                                style: valueStyle,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
