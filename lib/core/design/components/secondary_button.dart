import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/internal/button_width.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/tokens/app_radii.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Secondary action: surface fill with a 1.5 px outline, at least 52 high.
///
/// States: default, disabled (`onPressed == null`) and [danger] (error colour
/// for destructive actions such as "Löschen").
class SecondaryButton extends StatelessWidget {
  /// Creates a secondary button.
  const SecondaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.danger = false,
    this.icon,
    this.semanticLabel,
    this.expand = true,
    this.autofocus = false,
  });

  /// Button text.
  final String label;

  /// Tap callback; `null` disables the button.
  final VoidCallback? onPressed;

  /// Destructive variant (error outline and text).
  final bool danger;

  /// Optional leading icon.
  final IconData? icon;

  /// Overrides the spoken label (defaults to the visible text).
  final String? semanticLabel;

  /// Whether the button fills the available width.
  final bool expand;

  /// Whether the button takes the initial focus (safe default in dialogs).
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final enabled = onPressed != null;
    final foreground = !enabled
        ? colors.textTertiary
        : (danger ? colors.error : colors.textPrimary);
    final border = danger && enabled ? colors.error : colors.borderInput;

    Widget content(bool fill) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyStrong.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      onTap: onPressed,
      excludeSemantics: true,
      child: ButtonWidth(
        expand: expand,
        minWidth: AppSizes.touchMin,
        builder: (context, fill) => ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.secondaryButtonHeight,
          ),
          child: InkSurface(
            onTap: onPressed,
            autofocus: autofocus,
            color: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.secondaryButtonBorder,
              side: BorderSide(color: border, width: 1.5),
            ),
            child: Center(widthFactor: fill ? null : 1, child: content(fill)),
          ),
        ),
      ),
    );
  }
}
