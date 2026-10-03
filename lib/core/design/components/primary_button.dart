import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/internal/button_width.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/tokens/app_radii.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Primary action: filled with the button green, white text, at least 56 high,
/// full width by default. The label wraps and the button grows with large text.
///
/// States: default, pressed (ripple), disabled (`onPressed == null`) and
/// loading ([loading] shows [loadingLabel], ignores taps and is announced as a
/// live region). There is no spinner: the design has no endless animation.
class PrimaryButton extends StatelessWidget {
  /// Creates a primary button.
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.loading = false,
    this.loadingLabel = 'Wird gespeichert …',
    this.icon,
    this.semanticLabel,
    this.expand = true,
  });

  /// Button text.
  final String label;

  /// Tap callback; `null` disables the button.
  final VoidCallback? onPressed;

  /// Shows [loadingLabel] instead of [label] and ignores taps.
  final bool loading;

  /// Text while [loading] (German default).
  final String loadingLabel;

  /// Optional leading icon.
  final IconData? icon;

  /// Overrides the spoken label (defaults to the visible text).
  final String? semanticLabel;

  /// Whether the button fills the available width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final disabled = onPressed == null && !loading;
    final enabled = onPressed != null && !loading;
    final text = loading ? loadingLabel : label;
    final background = disabled ? colors.track : colors.primaryButton;
    final foreground = disabled ? colors.textTertiary : colors.onPrimary;

    Widget content() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (icon != null && !loading) ...<Widget>[
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelButton.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      liveRegion: loading,
      label: semanticLabel != null && !loading ? semanticLabel : text,
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: ButtonWidth(
        expand: expand,
        minWidth: AppSizes.touchMin,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.buttonHeight),
          child: InkSurface(
            onTap: enabled ? onPressed : null,
            color: background,
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadii.buttonBorder,
            ),
            splashColor: colors.onPrimary.withValues(alpha: 0.18),
            highlightColor: colors.onPrimary.withValues(alpha: 0.1),
            child: Center(widthFactor: 1, child: content()),
          ),
        ),
      ),
    );
  }
}
