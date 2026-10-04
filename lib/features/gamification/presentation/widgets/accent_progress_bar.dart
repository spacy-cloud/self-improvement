import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// Progress bar in the colour of an accent (XP and level, streak milestone):
/// the design system bar only offers the variants of the measure cards.
///
/// Same look as `AppProgressBar` (12 high, fully rounded, 200 ms fill, instant
/// with reduced motion). The bar is a picture of a number: [semanticLabel]
/// carries the same numbers as text.
class AccentProgressBar extends StatelessWidget {
  /// Creates a bar for a fraction [value] from 0 to 1.
  const AccentProgressBar({
    required this.value,
    required this.semanticLabel,
    super.key,
    this.accent = AppAccent.gamification,
  });

  /// Progress from 0 to 1 (clamped, NaN counts as 0).
  final double value;

  /// Spoken text of the bar.
  final String semanticLabel;

  /// Accent of the fill.
  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    final fraction = AppProgressBar.clamp(value);
    return Semantics(
      container: true,
      label: semanticLabel,
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
                      key: const ValueKey<String>('accent_progress_fill'),
                      decoration: BoxDecoration(
                        color: colors.accentFill(accent),
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
