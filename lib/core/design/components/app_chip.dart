import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/motion/app_motion.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Single-choice chip: exactly one chip of a group is selected.
///
/// Selected = check mark, thicker border and tinted fill, never colour only.
/// The chip is at least 48 high; the label wraps with large text.
class AppChoiceChip extends StatelessWidget {
  /// Creates a choice chip.
  const AppChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
    this.semanticLabel,
  });

  /// Chip text.
  final String label;

  /// Whether this chip is the selected one.
  final bool selected;

  /// Called with `true` when the chip is tapped; `null` disables the chip.
  final ValueChanged<bool>? onSelected;

  /// Overrides the spoken label (defaults to [label]).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return _AppChip(
      label: label,
      selected: selected,
      onTap: onSelected == null ? null : () => onSelected!(true),
      semanticLabel: semanticLabel,
      exclusive: true,
    );
  }
}

/// Filter chip: a toggle that can be on or off independently of other chips.
///
/// Looks like [AppChoiceChip]; tapping flips the selection.
class AppFilterChip extends StatelessWidget {
  /// Creates a filter chip.
  const AppFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
    this.semanticLabel,
  });

  /// Chip text.
  final String label;

  /// Whether the filter is on.
  final bool selected;

  /// Called with the new selection; `null` disables the chip.
  final ValueChanged<bool>? onSelected;

  /// Overrides the spoken label (defaults to [label]).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return _AppChip(
      label: label,
      selected: selected,
      onTap: onSelected == null ? null : () => onSelected!(!selected),
      semanticLabel: semanticLabel,
      exclusive: false,
    );
  }
}

class _AppChip extends StatelessWidget {
  const _AppChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.semanticLabel,
    required this.exclusive,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool exclusive;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    final enabled = onTap != null;
    final foreground = !enabled
        ? colors.textTertiary
        : (selected ? colors.primaryText : colors.textPrimary);
    final style = selected
        ? AppTextStyles.bodyStrong
        : AppTextStyles.bodyDefault;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: exclusive,
      enabled: enabled,
      label: semanticLabel ?? label,
      onTap: onTap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSizes.touchMin,
          minWidth: AppSizes.touchMin,
        ),
        child: AnimatedContainer(
          duration: motion.fast,
          curve: motion.curve,
          decoration: ShapeDecoration(
            color: selected ? colors.primaryTint : colors.surface,
            shape: StadiumBorder(
              side: BorderSide(
                color: selected ? colors.primaryButton : colors.borderInput,
                width: selected ? 1.5 : 1,
              ),
            ),
          ),
          child: InkSurface(
            onTap: onTap,
            shape: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (selected) ...<Widget>[
                    Icon(Icons.check_rounded, size: 14, color: foreground),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: style.copyWith(color: foreground),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
