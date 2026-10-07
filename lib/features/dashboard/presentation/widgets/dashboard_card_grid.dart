import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/dashboard/domain/dashboard_layout.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/shared/local_date.dart';

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
///
/// With a [day] (a day that is not today, BS-93) every card is the one its
/// module builds for that day (`DashboardCardDescriptor.dayBuilder`). A module
/// without such a card has none on that day: the card is left out, and the
/// others close the gap, rather than show today's numbers under another date.
class DashboardCardGrid extends StatelessWidget {
  /// Creates the grid for the shown [entries].
  const DashboardCardGrid({required this.entries, this.day, super.key});

  /// The cards to show, in display order.
  final List<DashboardEntry> entries;

  /// The day the cards show; `null` is today, the live cards.
  final LocalDate? day;

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

    final shownDay = day;
    for (final entry in entries) {
      if (shownDay != null && entry.descriptor.dayBuilder == null) {
        continue;
      }
      final card = _CardHost(
        key: ValueKey<String>('dashboard-card-${entry.config.cardId}'),
        descriptor: entry.descriptor,
        day: shownDay,
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
  const _CardHost({required this.descriptor, required this.day, super.key});

  final DashboardCardDescriptor descriptor;

  /// The day of a card of another day; `null` builds the live card.
  final LocalDate? day;

  @override
  Widget build(BuildContext context) {
    final cardDay = day;
    return Consumer(
      builder: (context, ref, _) => cardDay == null
          ? descriptor.builder(context, ref)
          : descriptor.dayBuilder!(context, ref, cardDay),
    );
  }
}
