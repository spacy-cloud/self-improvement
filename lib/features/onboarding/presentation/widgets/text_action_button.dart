import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/tap_surface.dart';

/// A quiet text button ("Überspringen", "Erneut versuchen") with a tap target
/// of at least 48 x 48. The label wraps on large text.
class TextActionButton extends StatelessWidget {
  const TextActionButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.hint,
    this.color,
  });

  /// Visible and spoken label.
  final String label;

  /// Tap callback; `null` disables the button.
  final VoidCallback? onPressed;

  /// Additional spoken explanation of what happens.
  final String? hint;

  /// Text colour; secondary text by default.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final enabled = onPressed != null;
    final foreground = enabled
        ? (color ?? colors.textSecondary)
        : colors.textTertiary;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      hint: hint,
      onTap: onPressed,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSizes.touchMin,
          minHeight: AppSizes.touchMin,
        ),
        child: TapSurface(
          onTap: onPressed,
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyStrong.copyWith(color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
