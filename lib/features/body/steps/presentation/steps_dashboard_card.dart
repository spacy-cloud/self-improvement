import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_labels.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_routes.dart';

/// The `steps` card of the dashboard: today's total against the goal. Before a
/// total was entered it shows no number, only the way to enter one.
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
            quickAction: MetricCardAction(
              label: 'Schritte eintragen',
              icon: AppIcon.plus.data,
              accent: AppAccent.steps,
              onPressed: () => context.push(StepsRoutes.create),
            ),
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
        );
      },
    );
  }
}
