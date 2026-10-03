import 'package:flutter/material.dart';
import 'package:self_improvement/core/analysis/domain/analysis_figures.dart';
import 'package:self_improvement/core/analysis/domain/analysis_table.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_visuals.dart';

/// The table of figures (current value, previous value, change and basis) as
/// accessible rows. The rows are the very figures of the cards, so the table
/// shows the same data and formulas. Every row is one block for screen readers
/// that reads the complete sentence of the engine; the visible cells are
/// excluded from the tree, so nothing is read twice.
///
/// A row is two lines: the label of the figure (the formulas have long names
/// such as `Schritte, Ø pro erfasstem Tag`) and below it the three values in
/// the columns of the header, then the basis (`5/7 Tage erfasst`). On large
/// text (above 130 %) every row becomes a block of labelled lines instead of
/// columns, so nothing clips.
class AnalysisFigureTableView extends StatelessWidget {
  const AnalysisFigureTableView({
    required this.table,
    this.hiddenReason,
    super.key,
  });

  final AnalysisFigureTable table;

  /// A reason of a missing comparison that the page already explains once
  /// above the table; the rows then only say "Noch kein Vergleich".
  final NoComparisonReason? hiddenReason;

  /// Space between two value columns.
  static const double columnGap = 8;

  /// Relative widths of the current, previous and change column: the change
  /// column holds the longest texts (`+21 Prozentpunkte`).
  static const List<int> columnFlex = <int>[3, 3, 4];

  /// The narrowest width that still fits the three columns; below it (a
  /// 320 px phone) the rows are blocks of labelled lines.
  static const double minColumnsWidth = 280;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final largeText = useStackedLayout(context);
    final headStyle = AppTextStyles.captionStrong.copyWith(
      color: colors.textSecondary,
    );
    final headers = table.headers;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = largeText || constraints.maxWidth < minColumnsWidth;
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
                  child: _ValueColumns(
                    cells: <Widget>[
                      Text(headers[1], style: headStyle),
                      Text(headers[2], style: headStyle),
                      Text(headers[3], style: headStyle),
                    ],
                  ),
                ),
              ),
            for (final figure in table.rows)
              _FigureRow(
                figure: figure,
                headers: headers,
                stacked: stacked,
                hiddenReason: hiddenReason,
              ),
          ],
        );
      },
    );
  }
}

/// The three value columns of the header and of every row: equal widths with a
/// gap, so values of neighbouring columns never run into each other.
class _ValueColumns extends StatelessWidget {
  const _ValueColumns({required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < cells.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: AnalysisFigureTableView.columnGap),
          Expanded(
            flex: AnalysisFigureTableView.columnFlex[i],
            child: cells[i],
          ),
        ],
      ],
    );
  }
}

class _FigureRow extends StatelessWidget {
  const _FigureRow({
    required this.figure,
    required this.headers,
    required this.stacked,
    required this.hiddenReason,
  });

  final AnalysisFigure figure;
  final List<String> headers;
  final bool stacked;
  final NoComparisonReason? hiddenReason;

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
    final explanation = figure.comparison?.reason == hiddenReason
        ? null
        : figure.explanation;

    final Widget values;
    if (stacked) {
      values = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('${headers[1]}: ${figure.currentText}', style: valueStyle),
          Text('${headers[2]}: ${figure.previousText}', style: valueStyle),
          Text('${headers[3]}: ${figure.changeText}', style: valueStyle),
        ],
      );
    } else {
      values = _ValueColumns(
        cells: <Widget>[
          Text(figure.currentText, style: valueStyle),
          Text(figure.previousText, style: valueStyle),
          Text(figure.changeText, style: valueStyle),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(figure.tableLabel, style: labelStyle),
            const SizedBox(height: 4),
            values,
            for (final line in basis) ...<Widget>[
              const SizedBox(height: 2),
              Text(line, style: secondary),
            ],
            if (explanation != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(explanation, style: secondary),
            ],
          ],
        ),
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
