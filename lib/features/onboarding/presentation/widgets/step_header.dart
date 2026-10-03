import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// Heading block of a numbered step: "Schritt N von 4", the title and an
/// optional explanation.
///
/// The caption and the title are one heading for screen readers and a live
/// region, so the change of the step is announced ("Schritt 2 von 4: Was
/// willst du nutzen?").
class StepHeader extends StatelessWidget {
  const StepHeader({
    required this.stepLabel,
    required this.title,
    super.key,
    this.subtitle,
  });

  /// For example "Schritt 1 von 4".
  final String stepLabel;

  final String title;

  /// Explanation below the title.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final subtitle = this.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          container: true,
          header: true,
          liveRegion: true,
          label: '$stepLabel: $title',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                stepLabel,
                style: AppTextStyles.captionStrong.copyWith(
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                title,
                style: AppTextStyles.titleScreen.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s8),
          Text(
            subtitle,
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
