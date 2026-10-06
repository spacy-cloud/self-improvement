import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_labels.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_routes.dart';

/// The `steps` card of the dashboard: today's total against the goal. Before a
/// total was entered it shows no number, only the way to enter one.
///
/// The action below the card stays after the first entry of the day (BS-108):
/// the total is a sum that changes during the day and saving replaces it, so
/// the card keeps the way to update it (see [_stepsAction]).
class StepsDashboardCard extends ConsumerWidget {
  const StepsDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(stepsTodayProvider);
    return today.when(
      loading: () => const MetricCard(
        title: 'Schritte',
        value: '–',
        icon: Icons.directions_walk_rounded,
        accent: AppAccent.steps,
      ),
      error: (error, stack) =>
          ErrorState(onRetry: () => ref.invalidate(stepsTodayProvider)),
      data: (state) {
        if (!state.recorded) {
          return MetricCard(
            title: 'Schritte',
            value: '–',
            subtitle: 'Heute noch nicht eingetragen',
            icon: AppIcon.steps.data,
            accent: AppAccent.steps,
            onTap: () => context.push(StepsRoutes.overview),
            semanticLabel: 'Schritte, heute noch nicht eingetragen',
            quickAction: _stepsAction(context, recorded: false),
          );
        }
        final progress = state.progress;
        final target = stepsTargetText(progress);
        final percent = progress.percent;
        return MetricCard(
          title: 'Schritte',
          value: stepsText(progress.steps),
          target: target,
          progress: percent == null ? null : progress.fraction,
          progressVariant: AppProgressVariant.steps,
          progressSemanticLabel: percent == null
              ? null
              : 'Fortschritt zum Tagesziel: $percent Prozent',
          subtitle: percent == null
              ? 'Kein Tagesziel aktiv'
              : (progress.reached ? 'Ziel erreicht' : '$percent % erreicht'),
          icon: AppIcon.steps.data,
          accent: AppAccent.steps,
          onTap: () => context.push(StepsRoutes.overview),
          quickAction: _stepsAction(context, recorded: true),
        );
      },
    );
  }
}

/// The quick action of the card. Both states open the form for today: it
/// already knows an existing total, says so and replaces it on saving (it never
/// adds). Before the first entry the action enters the total ("+ Schritte
/// eintragen"); afterwards it updates it ("Schritte aktualisieren", without a
/// plus, because nothing is added).
MetricCardAction _stepsAction(BuildContext context, {required bool recorded}) =>
    MetricCardAction(
      label: recorded ? 'Schritte aktualisieren' : 'Schritte eintragen',
      icon: recorded ? null : AppIcon.plus.data,
      accent: AppAccent.steps,
      onPressed: () => context.push(StepsRoutes.create),
    );
