import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/dashboard/domain/dashboard_layout.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module.dart';

/// Smallest width of one cell in the two-column card grid. It is the width a
/// cell has on a 360 px wide screen (360 - 2 x 16 page margin - 12 gap, halved):
/// from 360 px on two small cards share a row, below that they stack. Large
/// text (above 130 %) always stacks, see `AdaptiveGrid`.
const double dashboardMinCellWidth = 158;

/// The cards of the dashboard in the order of the user.
///
/// Small cards (the default) share a row two by two; a card marked `fullWidth`
/// by its module (tasks, XP) takes a whole row and ends the current group of
/// small cards, so the user's order is always kept. The card content comes from
/// the descriptor of the module: it is built inside its own [Consumer], so a
/// change of one card's data rebuilds only that card.
///
/// Cards of one row get the same height ([AdaptiveGrid] measures them), so a
/// card must not use a `LayoutBuilder` at its top level (a chart needs a fixed
/// height).
class DashboardCardGrid extends StatelessWidget {
  /// Creates the grid for the shown [entries].
  const DashboardCardGrid({required this.entries, super.key});

  /// The cards to show, in display order.
  final List<DashboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    var small = <Widget>[];

    void flushSmall() {
      if (small.isEmpty) {
        return;
      }
      blocks.add(
        AdaptiveGrid(minCellWidth: dashboardMinCellWidth, children: small),
      );
      small = <Widget>[];
    }

    for (final entry in entries) {
      final card = _CardHost(
        key: ValueKey<String>('dashboard-card-${entry.config.cardId}'),
        descriptor: entry.descriptor,
      );
      if (entry.descriptor.fullWidth) {
        flushSmall();
        blocks.add(card);
      } else {
        small.add(card);
      }
    }
    flushSmall();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < blocks.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.s12),
          blocks[i],
        ],
      ],
    );
  }
}

class _CardHost extends StatelessWidget {
  const _CardHost({required this.descriptor, super.key});

  final DashboardCardDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => descriptor.builder(context, ref),
    );
  }
}
