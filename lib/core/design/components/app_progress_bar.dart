import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/motion/app_motion.dart';
import 'package:self_improvement/core/design/tokens/app_colors.dart';
import 'package:self_improvement/core/design/tokens/app_radii.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Colour variants of [AppProgressBar] (Figma: Primary, Water, Steps, Focus).
enum AppProgressVariant {
  /// Accent fill green.
  primary(AppAccent.primary),

  /// Water blue (chart colour).
  water(AppAccent.water),

  /// Steps magenta.
  steps(AppAccent.steps),

  /// Focus indigo.
  focus(AppAccent.focus);

  const AppProgressVariant(this.accent);

  /// The accent role that colours the fill.
  final AppAccent accent;
}

/// Horizontal progress bar (12 high, fully rounded). The fill is
/// `min(value, 1)` of the width; [value] is clamped to 0..1 (NaN counts as 0).
///
/// The bar is only a picture of a number: always show the value as text next to
/// it or pass [semanticLabel] (for example "75 % vom Tagesziel"). Without a
/// label the bar speaks "Fortschritt" and the percentage.
class AppProgressBar extends StatelessWidget {
  /// Creates a progress bar.
  const AppProgressBar({
    required this.value,
    super.key,
    this.variant = AppProgressVariant.primary,
    this.semanticLabel,
  });

  /// Progress from 0 to 1.
  final double value;

  /// Fill colour variant.
  final AppProgressVariant variant;

  /// Spoken text instead of the default "Fortschritt, N %".
  final String? semanticLabel;

  /// Clamps [raw] to 0..1; NaN becomes 0.
  static double clamp(double raw) {
    if (raw.isNaN) {
      return 0;
    }
    return raw.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    final fraction = clamp(value);
    // 100 % is spoken only when the bar is full: 99,6 rounds to 99.
    final percent = fraction < 1 ? (fraction * 100).round().clamp(0, 99) : 100;
    return Semantics(
      container: true,
      label: semanticLabel ?? 'Fortschritt',
      value: semanticLabel == null ? '$percent %' : null,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.bar),
        child: SizedBox(
          height: AppSizes.progressBar,
          child: ColoredBox(
            color: colors.track,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: fraction),
              duration: motion.standard,
              curve: motion.curve,
              builder: (context, animated, _) {
                return Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: animated,
                    child: DecoratedBox(
                      key: const ValueKey<String>('app_progress_fill'),
                      decoration: BoxDecoration(
                        color: colors.accentFill(variant.accent),
                        borderRadius: BorderRadius.circular(AppRadii.bar),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
