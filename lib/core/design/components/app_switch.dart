import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/motion/app_motion.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Toggle: 44 x 26 track with a white knob inside a 48 x 48 tap area.
///
/// On uses the toggle green, off uses the input border grey. The change is
/// animated for 150 ms and immediate with reduced motion. [semanticLabel] names
/// the setting; the state is announced as a toggle (on or off).
class AppSwitch extends StatelessWidget {
  /// Creates a toggle.
  const AppSwitch({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    super.key,
  });

  /// Whether the toggle is on.
  final bool value;

  /// Called with the new value; `null` disables the toggle.
  final ValueChanged<bool>? onChanged;

  /// Name of the setting for screen readers.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    final enabled = onChanged != null;
    const inset = (AppSizes.toggleHeight - AppSizes.toggleKnob) / 2;
    final track = AnimatedContainer(
      duration: motion.fast,
      curve: motion.curve,
      width: AppSizes.toggleWidth,
      height: AppSizes.toggleHeight,
      decoration: BoxDecoration(
        color: value ? colors.toggleOn : colors.borderInput,
        borderRadius: BorderRadius.circular(AppSizes.toggleHeight / 2),
      ),
      child: Stack(
        children: <Widget>[
          AnimatedPositioned(
            duration: motion.fast,
            curve: motion.curve,
            top: inset,
            left: value
                ? AppSizes.toggleWidth - AppSizes.toggleKnob - inset
                : inset,
            child: Container(
              key: const ValueKey<String>('app_switch_knob'),
              width: AppSizes.toggleKnob,
              height: AppSizes.toggleKnob,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      onTap: enabled ? () => onChanged!(!value) : null,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: AppSizes.touchMin,
        child: InkSurface(
          onTap: enabled ? () => onChanged!(!value) : null,
          shape: const CircleBorder(),
          child: Center(
            child: Opacity(opacity: enabled ? 1 : 0.5, child: track),
          ),
        ),
      ),
    );
  }
}
