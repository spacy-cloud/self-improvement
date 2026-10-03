import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/body/presentation/weight_labels.dart';

/// Neutral pill that tells a change in weight with arrow, sign and context
/// ("↓ −0,3 kg seit dem letzten Eintrag"). The colour never carries the
/// meaning and is not green or red: a change is neither good nor bad
/// (specification 6.2); green is reserved for reaching the goal.
class WeightDeltaBadge extends StatelessWidget {
  const WeightDeltaBadge({
    required this.deltaGrams,
    required this.since,
    super.key,
  });

  final int deltaGrams;

  /// Short context, for example "seit dem letzten Eintrag".
  final String since;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      label: '${weightDeltaSpoken(deltaGrams)} $since',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.track,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: weightDeltaText(deltaGrams),
                  style: AppTextStyles.captionStrong.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                TextSpan(
                  text: '  $since',
                  style: AppTextStyles.captionDefault.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill with the placeholder text when no comparison exists, for example
/// "Noch kein Vergleich".
class NoComparisonBadge extends StatelessWidget {
  const NoComparisonBadge({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.track,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          text,
          style: AppTextStyles.captionDefault.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Error message directly at a field: icon and text on the error tint, never
/// colour alone. Announced when it appears.
class FieldErrorMessage extends StatelessWidget {
  const FieldErrorMessage({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorTint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(AppIcon.error.data, size: 14, color: colors.error),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: AppTextStyles.captionStrong.copyWith(
                    color: colors.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
