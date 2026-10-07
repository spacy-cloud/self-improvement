import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// The quiet icon tile of the rows on the settings pages: a muted surface and
/// an icon in the secondary text colour (rows that belong to no module accent).
/// Decorative, so it has no semantics: the text of the row carries the meaning.
class NeutralIconTile extends StatelessWidget {
  const NeutralIconTile(this.icon, {super.key});

  /// The glyph.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return ExcludeSemantics(
      child: Container(
        width: AppSizes.iconTile,
        height: AppSizes.iconTile,
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadii.tile),
        ),
        child: Icon(icon, size: 20, color: colors.textSecondary),
      ),
    );
  }
}
