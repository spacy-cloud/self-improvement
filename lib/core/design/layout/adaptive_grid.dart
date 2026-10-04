import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:self_improvement/core/design/internal/text_scale.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_spacing.dart';

/// Responsive card grid: two columns at normal text size and widths down to
/// 320 px, one stacked column when the text scale is above 1.3 or when a cell
/// would be narrower than [minCellWidth] (cards never clip their content).
///
/// Cells of one row have the same height. A last single cell keeps the width of
/// a column.
class AdaptiveGrid extends StatelessWidget {
  /// Creates a grid of [children].
  const AdaptiveGrid({
    required this.children,
    super.key,
    this.spacing = AppSpacing.s12,
    this.minCellWidth = 128,
    this.maxColumns = 2,
    this.stackTextScale = AppSizes.stackTextScale,
  }) : assert(maxColumns >= 1, 'maxColumns must be at least 1');

  /// The cells.
  final List<Widget> children;

  /// Gap between cells, horizontally and vertically.
  final double spacing;

  /// Smallest cell width before the grid switches to fewer columns.
  final double minCellWidth;

  /// Maximum number of columns (2 by default).
  final int maxColumns;

  /// Text scale above which the grid always stacks into one column.
  final double stackTextScale;

  /// Number of columns for [width] and [textScale].
  int columnsFor({required double width, required double textScale}) {
    if (textScale > stackTextScale) {
      return 1;
    }
    var columns = maxColumns;
    while (columns > 1 &&
        (width - spacing * (columns - 1)) / columns < minCellWidth) {
      columns--;
    }
    return columns;
  }

  @override
  Widget build(BuildContext context) {
    final scale = context.textScaleFactor;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(
          width: constraints.maxWidth,
          textScale: scale,
        );
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          if (rows.isNotEmpty) {
            rows.add(SizedBox(height: spacing));
          }
          if (columns == 1) {
            rows.add(children[start]);
            continue;
          }
          final cells = <Widget>[];
          for (var i = 0; i < columns; i++) {
            if (i > 0) {
              cells.add(SizedBox(width: spacing));
            }
            final index = start + i;
            cells.add(
              Expanded(
                child: index < children.length
                    ? children[index]
                    : const SizedBox.shrink(),
              ),
            );
          }
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        );
      },
    );
  }
}

/// Centres [child] and gives it the available width, at most [maxWidth] (720 by
/// default), on wide screens such as tablets and landscape.
class MaxContentWidth extends StatelessWidget {
  /// Creates the wrapper.
  const MaxContentWidth({
    required this.child,
    super.key,
    this.maxWidth = AppSizes.contentMaxWidth,
  });

  /// Content.
  final Widget child;

  /// Maximum width.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? math.min(constraints.maxWidth, maxWidth)
            : maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, child: child),
        );
      },
    );
  }
}
