import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/step_page.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/step_progress.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/text_action_button.dart';

/// Top bar of the four numbered steps: a round back button, the four-segment
/// progress and "Überspringen".
///
/// One row at normal text size and enough width. With large text or on a very
/// narrow screen the progress moves to its own line below back and skip, so
/// neither button is squeezed or clipped. Both buttons keep a 48 x 48 target;
/// `null` callbacks disable them while the completion runs.
class OnboardingTopBar extends StatelessWidget {
  const OnboardingTopBar({
    required this.current,
    required this.total,
    required this.onBack,
    required this.onSkip,
    super.key,
  });

  /// Number of filled progress segments (1 to [total]).
  final int current;

  /// Number of numbered steps.
  final int total;

  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final margin = onboardingPageMargin(context);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final back = AppIconButton(
      icon: AppIcon.back.data,
      onPressed: onBack,
      semanticLabel: 'Zurück',
      filled: true,
    );
    final skip = TextActionButton(
      label: 'Überspringen',
      onPressed: onSkip,
      hint: 'Schließt die Einrichtung mit Standardwerten ab',
    );
    final progress = StepProgress(current: current, total: total);
    return Padding(
      // The visible circle (40 of 48) lines up with the page margin.
      padding: EdgeInsets.fromLTRB(margin - 4, AppSpacing.s8, margin - 8, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // back (48), gaps, the narrowest useful progress (80), the skip text
          // (about 100 at normal size) and its padding.
          final compact =
              constraints.maxWidth < 48 + 24 + 80 + 32 + 100 * scale;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(children: <Widget>[back, const Spacer(), skip]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s4,
                    AppSpacing.s4,
                    AppSpacing.s8,
                    0,
                  ),
                  child: progress,
                ),
              ],
            );
          }
          return Row(
            children: <Widget>[
              back,
              const SizedBox(width: AppSpacing.s12),
              Expanded(child: progress),
              const SizedBox(width: AppSpacing.s12),
              skip,
            ],
          );
        },
      ),
    );
  }
}
