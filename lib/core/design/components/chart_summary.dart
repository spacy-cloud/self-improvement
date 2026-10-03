import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/components/app_card.dart';
import 'package:self_improvement/core/design/icons/app_icons.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/internal/text_scale.dart';
import 'package:self_improvement/core/design/motion/app_motion.dart';
import 'package:self_improvement/core/design/tokens/app_colors.dart';
import 'package:self_improvement/core/design/tokens/app_radii.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// One row of the table alternative of a chart.
class ChartSummaryRow {
  /// Creates a row: a [label] and one value per column.
  const ChartSummaryRow({required this.label, required this.values});

  /// Row label, for example "Schritte Ø/Tag".
  final String label;

  /// Values in column order, for example `['8.950', '8.290', '+8 %']`.
  final List<String> values;
}

/// Accessible text alternative for a chart: a title, a one sentence [summary]
/// and an expandable table with all values.
///
/// The optional [chart] is excluded from the accessibility tree because the
/// summary and the table replace it; screen readers read the table row by row
/// ("Schritte Ø/Tag: Woche 8.950, Vorwoche 8.290, Änderung +8 %"). On large
/// text the table switches to one block per row.
class ChartSummary extends StatefulWidget {
  /// Creates a chart summary.
  const ChartSummary({
    required this.title,
    required this.summary,
    required this.rows,
    super.key,
    this.columns = const <String>[],
    this.chart,
    this.initiallyExpanded = false,
    this.showTableLabel = 'Als Tabelle anzeigen',
    this.hideTableLabel = 'Tabelle ausblenden',
    this.headerTrailing,
  });

  /// Title of the chart.
  final String title;

  /// Sentence that tells what the chart shows, for example "Gewicht sinkt
  /// über 7 Tage von 72,7 auf 71,5 kg."
  final String summary;

  /// Table rows.
  final List<ChartSummaryRow> rows;

  /// Column headers for the values (without the label column).
  final List<String> columns;

  /// The visual chart (hidden from screen readers).
  final Widget? chart;

  /// Whether the table starts expanded.
  final bool initiallyExpanded;

  /// Label of the toggle while the table is hidden.
  final String showTableLabel;

  /// Label of the toggle while the table is shown.
  final String hideTableLabel;

  /// Interactive control right of the title, for example a `PeriodSelector`.
  /// It stays in the accessibility tree; on large text it moves below the
  /// title.
  final Widget? headerTrailing;

  @override
  State<ChartSummary> createState() => _ChartSummaryState();
}

class _ChartSummaryState extends State<ChartSummary> {
  late bool _expanded = widget.initiallyExpanded;

  Widget _header(BuildContext context, AppColors colors) {
    final title = Semantics(
      container: true,
      header: true,
      child: Text(
        widget.title,
        style: AppTextStyles.titleCard.copyWith(color: colors.textPrimary),
      ),
    );
    final trailing = widget.headerTrailing;
    if (trailing == null) {
      return title;
    }
    // Title left and control right while both fit in one line; otherwise the
    // control moves below the title (large text, narrow screens).
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        title,
        IntrinsicWidth(child: trailing),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    final toggleLabel = _expanded
        ? widget.hideTableLabel
        : widget.showTableLabel;
    final table = Padding(
      padding: const EdgeInsets.only(top: 4),
      child: _SummaryTable(columns: widget.columns, rows: widget.rows),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _header(context, colors),
          if (widget.chart != null) ...<Widget>[
            const SizedBox(height: 12),
            ExcludeSemantics(child: widget.chart),
          ],
          const SizedBox(height: 8),
          Text(
            widget.summary,
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Semantics(
            container: true,
            button: true,
            expanded: _expanded,
            label: toggleLabel,
            onTap: () => setState(() => _expanded = !_expanded),
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
              child: InkSurface(
                onTap: () => setState(() => _expanded = !_expanded),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadii.controlBorder,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          toggleLabel,
                          style: AppTextStyles.bodyStrong.copyWith(
                            color: colors.primaryText,
                          ),
                        ),
                      ),
                      Icon(
                        _expanded ? AppIcon.collapse.data : AppIcon.expand.data,
                        color: colors.primaryText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (motion.reduced)
            (_expanded ? table : const SizedBox.shrink())
          else
            AnimatedSize(
              duration: motion.standard,
              curve: motion.curve,
              alignment: Alignment.topCenter,
              child: _expanded ? table : const SizedBox(width: double.infinity),
            ),
        ],
      ),
    );
  }
}

class _SummaryTable extends StatelessWidget {
  const _SummaryTable({required this.columns, required this.rows});

  final List<String> columns;
  final List<ChartSummaryRow> rows;

  String _rowLabel(ChartSummaryRow row) {
    final parts = <String>[];
    for (var i = 0; i < row.values.length; i++) {
      final header = i < columns.length ? '${columns[i]} ' : '';
      parts.add('$header${row.values[i]}');
    }
    return '${row.label}: ${parts.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final stacked = context.textScaleFactor > AppSizes.stackTextScale;
    final labelStyle = AppTextStyles.bodyDefault.copyWith(
      color: colors.textPrimary,
    );
    final valueStyle = AppTextStyles.bodyRegular.copyWith(
      color: colors.textPrimary,
    );
    final headStyle = AppTextStyles.captionStrong.copyWith(
      color: colors.textSecondary,
    );

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final row in rows)
            Semantics(
              container: true,
              label: _rowLabel(row),
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.track)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(row.label, style: labelStyle),
                    for (var i = 0; i < row.values.length; i++)
                      Text(
                        i < columns.length
                            ? '${columns[i]}: ${row.values[i]}'
                            : row.values[i],
                        style: valueStyle,
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    final valueColumns = rows.isEmpty
        ? columns.length
        : rows.map((r) => r.values.length).reduce((a, b) => a > b ? a : b);

    Widget line({
      required Widget first,
      required List<Widget> rest,
      required BoxBorder border,
      String? label,
    }) {
      final row = Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: border),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(flex: 22, child: first),
            for (final cell in rest) Expanded(flex: 14, child: cell),
          ],
        ),
      );
      if (label == null) {
        return ExcludeSemantics(child: row);
      }
      return Semantics(
        container: true,
        label: label,
        excludeSemantics: true,
        child: row,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (columns.isNotEmpty)
          line(
            first: const SizedBox.shrink(),
            rest: <Widget>[
              for (var i = 0; i < valueColumns; i++)
                Text(
                  i < columns.length ? columns[i] : '',
                  textAlign: TextAlign.end,
                  style: headStyle,
                ),
            ],
            border: Border(
              bottom: BorderSide(color: colors.borderInput, width: 1.5),
            ),
          ),
        for (final row in rows)
          line(
            first: Text(row.label, style: labelStyle),
            rest: <Widget>[
              for (var i = 0; i < valueColumns; i++)
                Text(
                  i < row.values.length ? row.values[i] : '',
                  textAlign: TextAlign.end,
                  style: valueStyle,
                ),
            ],
            border: Border(bottom: BorderSide(color: colors.track)),
            label: _rowLabel(row),
          ),
      ],
    );
  }
}
