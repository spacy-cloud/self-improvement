import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/components/app_card.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// A card that groups list rows (for example `EntryListTile`s) and separates
/// them with the hairline divider of the design. The card has no inner padding;
/// the rows bring their own.
class AppListGroup extends StatelessWidget {
  /// Creates a group of [children].
  const AppListGroup({
    required this.children,
    super.key,
    this.dividerIndent = 14,
  });

  /// The rows.
  final List<Widget> children;

  /// Space between the card edge and the ends of the divider.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: dividerIndent,
                endIndent: dividerIndent,
                color: colors.track,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}
