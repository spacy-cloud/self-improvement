import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/tokens/app_colors.dart';
import 'package:self_improvement/core/design/tokens/app_radii.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// A rounded tile with an icon in the colour of an [AppAccent]: the icon tile
/// of list rows, menus and habit rows. Decorative: it has no semantics, the
/// text next to it carries the meaning.
class AppIconTile extends StatelessWidget {
  /// Creates an icon tile.
  const AppIconTile({
    required this.icon,
    super.key,
    this.accent = AppAccent.primary,
    this.size = AppSizes.iconTile,
    this.iconSize = 20,
    this.radius = AppRadii.tile,
    this.borderColor,
    this.borderWidth = 0,
  });

  /// The glyph.
  final IconData icon;

  /// Accent role that selects tint and icon colour.
  final AppAccent accent;

  /// Edge length of the tile.
  final double size;

  /// Size of the glyph.
  final double iconSize;

  /// Corner radius.
  final double radius;

  /// Optional border colour (selection state of a picker).
  final Color? borderColor;

  /// Border width; 0 for none.
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.accentTint(accent),
          borderRadius: BorderRadius.circular(radius),
          border: borderWidth > 0 && borderColor != null
              ? Border.all(color: borderColor!, width: borderWidth)
              : null,
        ),
        child: Icon(icon, size: iconSize, color: colors.accent(accent)),
      ),
    );
  }
}
