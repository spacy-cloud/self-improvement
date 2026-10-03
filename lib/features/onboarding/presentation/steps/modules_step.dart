import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_controller.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_state.dart';
import 'package:self_improvement/features/onboarding/domain/onboarding_options.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/info_note.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/option_cards.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/option_icons.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/step_header.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/step_page.dart';

/// Screen 3 ("Schritt 2 von 4"): which of the five bundled modules to use.
/// All start switched on; switching all off is allowed and explained.
class ModulesStep extends ConsumerWidget {
  const ModulesStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      onboardingControllerProvider.select((state) => state.enabledModules),
    );
    final controller = ref.read(onboardingControllerProvider.notifier);
    return StepPage(
      children: <Widget>[
        const StepHeader(
          stepLabel: 'Schritt 2 von ${OnboardingStep.numberedStepCount}',
          title: 'Was willst du nutzen?',
          subtitle:
              'Wähle deine Bereiche. Du kannst sie jederzeit in den '
              'Einstellungen ändern.',
        ),
        const SizedBox(height: AppSpacing.s16),
        for (final option in OnboardingOptions.modules) ...<Widget>[
          ToggleOptionCard(
            title: option.title,
            subtitle: option.subtitle,
            icon: moduleLook(option.module).icon,
            accent: moduleLook(option.module).accent,
            enabled: enabled.contains(option.module),
            onChanged: (value) =>
                controller.setModuleEnabled(option.module, enabled: value),
          ),
          const SizedBox(height: 10),
        ],
        if (enabled.isEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.s8),
          const InfoNote(
            liveRegion: true,
            text:
                'Alle Bereiche sind ausgeschaltet. Du kannst trotzdem '
                'fortfahren und sie später in den Einstellungen einschalten.',
          ),
        ],
      ],
    );
  }
}
