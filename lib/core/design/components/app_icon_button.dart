import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Icon button with a 48 x 48 tap area and a 40 px visible circle.
///
/// [semanticLabel] is mandatory (for example "Zurück", "Schließen"). [filled]
/// draws the surface circle with a decorative border (Figma style "Filled"),
/// the plain style has no background.
class AppIconButton extends StatelessWidget {
  /// Creates an icon button.
  const AppIconButton({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    super.key,
    this.filled = false,
    this.iconSize = AppSizes.iconButtonIcon,
    this.iconColor,
  });

  /// Glyph.
  final IconData icon;

  /// Tap callback; `null` disables the button.
  final VoidCallback? onPressed;

  /// Spoken label (required).
  final String semanticLabel;

  /// Filled style (surface circle with border) instead of plain.
  final bool filled;

  /// Glyph size (20 in Figma).
  final double iconSize;

  /// Glyph colour; defaults to the primary text colour.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final enabled = onPressed != null;
    final color =
        iconColor ?? (enabled ? colors.textPrimary : colors.textTertiary);
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: semanticLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: AppSizes.touchMin,
        child: InkSurface(
          onTap: onPressed,
          shape: const CircleBorder(),
          child: Center(
            child: Ink(
              width: AppSizes.iconButtonVisual,
              height: AppSizes.iconButtonVisual,
              decoration: filled
                  ? BoxDecoration(
                      color: colors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.borderDecorative),
                    )
                  : null,
              child: Center(
                child: Icon(icon, size: iconSize, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
