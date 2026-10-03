import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/tokens/app_radii.dart';
import 'package:self_improvement/core/design/tokens/app_shadows.dart';
import 'package:self_improvement/core/design/tokens/app_spacing.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Standard card: surface fill, 1 px decorative border, radius 16, soft shadow.
/// The height always hugs the content (cards grow with large text).
///
/// With [onTap] the whole card is one button (ripple, focus, semantics).
class AppCard extends StatelessWidget {
  /// Creates a card.
  const AppCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(AppSpacing.s16),
    this.margin,
    this.onTap,
    this.semanticLabel,
    this.radius = AppRadii.card,
    this.showShadow = true,
  });

  /// Card content.
  final Widget child;

  /// Inner padding (16 by default; use [EdgeInsets.zero] for list groups).
  final EdgeInsetsGeometry padding;

  /// Outer margin.
  final EdgeInsetsGeometry? margin;

  /// Makes the card tappable.
  final VoidCallback? onTap;

  /// Spoken label of a tappable card; replaces the child texts. Without it the
  /// texts inside the card are merged into one button.
  final String? semanticLabel;

  /// Corner radius.
  final double radius;

  /// Whether the card casts its soft shadow.
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final borderRadius = BorderRadius.circular(radius);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = MergeSemantics(
        child: Semantics(
          button: true,
          label: semanticLabel,
          onTap: onTap,
          excludeSemantics: semanticLabel != null,
          child: InkSurface(
            onTap: onTap,
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            child: content,
          ),
        ),
      );
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: borderRadius,
        border: Border.all(color: colors.borderDecorative),
        boxShadow: showShadow ? AppShadows.card(colors.shadow) : null,
      ),
      child: ClipRRect(borderRadius: borderRadius, child: content),
    );
  }
}
