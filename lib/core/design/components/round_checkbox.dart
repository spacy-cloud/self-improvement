import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/motion/app_motion.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Round checkbox (28 px circle) inside a 48 x 48 tap area. With [squared] the
/// box is a rounded square, the convention for multi-select options (the
/// round form stays for completing a task or habit).
///
/// Checked: button green with a white check mark. Unchecked: surface with a
/// 2 px input border. The state is never colour only: it is announced as
/// checked or unchecked. For habits and tasks pass [checkedStateLabel] and
/// [uncheckedStateLabel] ("erledigt" / "offen") to have the state spoken as a
/// value.
class RoundCheckbox extends StatelessWidget {
  /// Creates a checkbox.
  const RoundCheckbox({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    super.key,
    this.checkedStateLabel,
    this.uncheckedStateLabel,
    this.squared = false,
  });

  /// Whether the box is checked.
  final bool value;

  /// Called with the new value; `null` disables the checkbox.
  final ValueChanged<bool>? onChanged;

  /// Name of the item for screen readers.
  final String semanticLabel;

  /// Spoken state when checked (for example "erledigt").
  final String? checkedStateLabel;

  /// Spoken state when unchecked (for example "offen").
  final String? uncheckedStateLabel;

  /// Rounded square instead of a circle (multi-select options).
  final bool squared;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    final enabled = onChanged != null;
    final stateLabel = value ? checkedStateLabel : uncheckedStateLabel;
    final box = AnimatedContainer(
      duration: motion.fast,
      curve: motion.curve,
      width: AppSizes.checkbox,
      height: AppSizes.checkbox,
      decoration: BoxDecoration(
        color: value ? colors.primaryButton : colors.surface,
        shape: squared ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: squared ? BorderRadius.circular(8) : null,
        border: value ? null : Border.all(color: colors.borderInput, width: 2),
      ),
      child: AnimatedOpacity(
        duration: motion.fast,
        opacity: value ? 1 : 0,
        child: Icon(Icons.check_rounded, size: 16, color: colors.onPrimary),
      ),
    );
    return Semantics(
      container: true,
      checked: value,
      enabled: enabled,
      label: semanticLabel,
      value: stateLabel,
      onTap: enabled ? () => onChanged!(!value) : null,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: AppSizes.touchMin,
        child: InkSurface(
          onTap: enabled ? () => onChanged!(!value) : null,
          shape: squared
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              : const CircleBorder(),
          child: Center(
            child: Opacity(opacity: enabled ? 1 : 0.5, child: box),
          ),
        ),
      ),
    );
  }
}
