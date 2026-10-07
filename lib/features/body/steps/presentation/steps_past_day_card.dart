import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/body/steps/domain/step_source.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_labels.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_routes.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The `steps` card of Home for a day that is not today (BS-93): the total of
/// [day] against the target that counted on that day.
///
/// It only shows. The action "Schritte eintragen" and the Health row of the
/// live card are left out: they belong to today, and an entry for an earlier
/// day is made with the form of the steps screen, which the card opens. A day
/// without a total reads "Keine Schritte eingetragen" and no number: nothing
/// was recorded, which is not the same as walking nothing.
class StepsPastDayCard extends ConsumerWidget {
  /// Creates the card of [day].
  const StepsPastDayCard({required this.day, super.key});

  /// The day shown.
  final LocalDate day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(stepsDayProvider(day))
        .when(
          loading: () => MetricCard(
            title: 'Schritte',
            value: '–',
            icon: AppIcon.steps.data,
            accent: AppAccent.steps,
          ),
          error: (error, stack) =>
              ErrorState(onRetry: () => ref.invalidate(stepsDayProvider(day))),
          data: (state) => _build(context, state),
        );
  }

  Widget _build(BuildContext context, StepsToday state) {
    void open() => context.push(StepsRoutes.overview);
    if (!state.recorded) {
      return MetricCard(
        title: 'Schritte',
        value: '–',
        subtitle: 'Keine Schritte eingetragen',
        icon: AppIcon.steps.data,
        accent: AppAccent.steps,
        onTap: open,
        semanticLabel: 'Schritte, keine Schritte eingetragen',
      );
    }
    final progress = state.progress;
    final target = stepsTargetText(progress);
    final percent = progress.percent;
    final subtitle = percent == null
        ? 'Kein Tagesziel an diesem Tag'
        : (progress.reached ? 'Ziel erreicht' : '$percent % erreicht');
    final source = state.source == StepSource.health ? ', aus Health' : '';
    return MetricCard(
      title: 'Schritte',
      value: stepsText(progress.steps),
      target: target,
      progress: percent == null ? null : progress.fraction,
      progressVariant: AppProgressVariant.steps,
      progressSemanticLabel: percent == null
          ? null
          : 'Fortschritt zum Tagesziel: $percent Prozent',
      subtitle: subtitle,
      icon: AppIcon.steps.data,
      accent: AppAccent.steps,
      onTap: open,
      semanticLabel:
          'Schritte, ${stepsText(progress.steps)}'
          '${target == null ? '' : ' $target'}, $subtitle$source',
    );
  }
}
