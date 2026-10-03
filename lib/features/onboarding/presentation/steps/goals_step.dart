import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_controller.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_state.dart';
import 'package:self_improvement/features/onboarding/domain/onboarding_options.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/option_cards.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/option_icons.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/step_header.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/step_page.dart';

/// Screen 2 ("Schritt 1 von 4"): the voluntary motivation goals. Nothing is
/// preselected; choosing none is fine, and no recommendation or number is
/// derived from the choice.
class GoalsStep extends ConsumerWidget {
  const GoalsStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      onboardingControllerProvider.select((state) => state.motivationGoals),
    );
    final controller = ref.read(onboardingControllerProvider.notifier);
    return StepPage(
      children: <Widget>[
        const StepHeader(
          stepLabel: 'Schritt 1 von ${OnboardingStep.numberedStepCount}',
          title: 'Was ist dein Ziel?',
          subtitle: 'Wähle alles aus, was auf dich zutrifft.',
        ),
        const SizedBox(height: AppSpacing.s16),
        for (final option in OnboardingOptions.motivationGoals) ...<Widget>[
          GoalOptionCard(
            title: option.title,
            subtitle: option.subtitle,
            icon: motivationGoalLook(option.id).icon,
            accent: motivationGoalLook(option.id).accent,
            selected: selected.contains(option.id),
            onChanged: (_) => controller.toggleMotivationGoal(option.id),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
