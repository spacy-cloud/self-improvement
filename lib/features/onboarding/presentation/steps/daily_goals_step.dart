import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_controller.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_state.dart';
import 'package:self_improvement/features/onboarding/domain/daily_goal_stepper.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/field_error_text.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/goal_stepper_row.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/info_note.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/option_cards.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/option_icons.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/step_header.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/step_page.dart';

/// Screen 5 ("Schritt 4 von 4"): the suggested daily goals, visible with their
/// values and adjustable within the limits of the goal editor. Only goals of
/// the modules chosen in step 2 are listed. Reminders stay off; this step never
/// asks for a system permission.
class DailyGoalsStep extends ConsumerWidget {
  const DailyGoalsStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(
      onboardingControllerProvider.select((state) => state.goalTargets),
    );
    final goalsOff = ref.watch(
      onboardingControllerProvider.select((state) => state.goalsOff),
    );
    final modules = ref.watch(
      onboardingControllerProvider.select((state) => state.enabledModules),
    );
    final errors = ref.watch(
      onboardingControllerProvider.select((state) => state.fieldErrors),
    );
    final controller = ref.read(onboardingControllerProvider.notifier);
    final visible = <GoalType>[
      for (final type in onboardingGoalTypes)
        if (modules.contains(type.module)) type,
    ];

    Widget row(GoalType type) {
      final look = goalLook(type);
      final value = targets[type];
      if (value == null) {
        return ToggleOptionCard(
          title: goalTitle(type),
          subtitle: goalSwitchDescription(type),
          icon: look.icon,
          accent: look.accent,
          enabled: !goalsOff.contains(type),
          onChanged: (on) => controller.setGoalEnabled(type, enabled: on),
        );
      }
      return GoalStepperRow(
        type: type,
        icon: look.icon,
        accent: look.accent,
        value: value,
        onIncrease: steppedGoalTarget(type, value, 1) == null
            ? null
            : () => controller.adjustGoalTarget(type, 1),
        onDecrease: steppedGoalTarget(type, value, -1) == null
            ? null
            : () => controller.adjustGoalTarget(type, -1),
      );
    }

    return StepPage(
      children: <Widget>[
        const StepHeader(
          stepLabel: 'Schritt 4 von ${OnboardingStep.numberedStepCount}',
          title: 'Deine Tagesziele',
          subtitle:
              'Wir haben Startwerte vorgeschlagen. Du kannst sie jederzeit '
              'ändern.',
        ),
        const SizedBox(height: AppSpacing.s16),
        for (final type in visible) ...<Widget>[
          row(type),
          if (errors[type.key] case final message?)
            FieldErrorText(text: message),
          const SizedBox(height: 10),
        ],
        if (visible.isEmpty) ...<Widget>[
          const InfoNote(
            liveRegion: true,
            text:
                'Ohne ausgewählte Bereiche gibt es keine Tagesziele. Wenn du '
                'später einen Bereich einschaltest, gelten die Startwerte.',
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: AppSpacing.s4),
        const InfoNote(
          icon: AppIcon.reminder,
          text:
              'Erinnerungen sind ausgeschaltet. Du kannst sie später in den '
              'Einstellungen einschalten; erst dann fragt das System nach der '
              'Erlaubnis.',
        ),
      ],
    );
  }
}
