import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Value stepper: minus button, value with unit, plus button.
///
/// Both buttons have 48 x 48 tap areas (40 px circles) and are spoken as
/// "verringern" and "erhöhen"; the value and unit are read as one live
/// region, so every change is announced. The value wraps on large text.
class QuantityStepper extends StatelessWidget {
  /// Creates a stepper.
  const QuantityStepper({
    required this.valueText,
    required this.onIncrease,
    required this.onDecrease,
    super.key,
    this.unit,
    this.increaseLabel = 'erhöhen',
    this.decreaseLabel = 'verringern',
    this.valueSemanticLabel,
    this.valueStyle,
    this.expand = false,
  });

  /// Formatted value, for example "71,5".
  final String valueText;

  /// Unit shown after the value, for example "kg".
  final String? unit;

  /// Increase callback; `null` disables the plus button (maximum reached).
  final VoidCallback? onIncrease;

  /// Decrease callback; `null` disables the minus button (minimum reached).
  final VoidCallback? onDecrease;

  /// Spoken label of the plus button.
  final String increaseLabel;

  /// Spoken label of the minus button.
  final String decreaseLabel;

  /// Spoken value (defaults to "valueText unit").
  final String? valueSemanticLabel;

  /// Text style of the value (Display/L by default).
  final TextStyle? valueStyle;

  /// Whether the stepper fills the width and centres the value between the
  /// buttons.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final text = unit == null ? valueText : '$valueText $unit';
    final value = Semantics(
      container: true,
      liveRegion: true,
      label: valueSemanticLabel ?? text,
      excludeSemantics: true,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: (valueStyle ?? AppTextStyles.displayL).copyWith(
          color: colors.textPrimary,
        ),
      ),
    );
    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _StepButton(
          icon: Icons.remove_rounded,
          label: decreaseLabel,
          onPressed: onDecrease,
        ),
        const SizedBox(width: 4),
        Flexible(child: value),
        const SizedBox(width: 4),
        _StepButton(
          icon: Icons.add_rounded,
          label: increaseLabel,
          onPressed: onIncrease,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final enabled = onPressed != null;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
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
              decoration: BoxDecoration(
                color: enabled ? colors.primaryTint : colors.track,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 20,
                  color: enabled ? colors.primaryText : colors.textTertiary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
