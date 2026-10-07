import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_actions.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_controller.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/body/steps/domain/health_steps_status.dart';
import 'package:self_improvement/features/body/steps/domain/step_source.dart';
import 'package:self_improvement/features/body/steps/presentation/health_notice_card.dart';
import 'package:self_improvement/features/body/steps/presentation/health_steps_labels.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_labels.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_routes.dart';

/// The `steps` card of the dashboard: today's total against the goal. Before a
/// total was entered it shows no number, only the way to enter one.
///
/// The action below the card stays after the first entry of the day (BS-108):
/// the total is a sum that changes during the day and saving replaces it, so
/// the card keeps the way to update it (see [_stepsAction]).
///
/// Three states more when the comparison with Health is on (BS-97, design
/// frame `4123:316`): while Health delivers, a value from Health shows its
/// source and "Aktualisieren" instead of the action; while it does not (no
/// access, interface missing or outdated) a warning says so with the way out
/// and the last value stays. A value typed in keeps the action of BS-108: it
/// has priority and Health does not touch it.
class StepsDashboardCard extends ConsumerWidget {
  const StepsDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(stepsTodayProvider);
    final health = ref.watch(healthStepsStatusProvider);
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
        final actions = ref.read(healthStepsActionsProvider);
        final warning = healthCardWarning(health);
        if (warning != null) {
          return _build(
            context,
            state: state,
            health: health,
            warning: warning,
            quickAction: _warningAction(health, actions),
          );
        }
        final fromHealth =
            health.reading &&
            (!state.recorded || state.source == StepSource.health);
        if (fromHealth) {
          return _build(
            context,
            state: state,
            health: health,
            quickAction: _HealthSourceRow(
              text: healthCardSourceText(health, ref.watch(clockProvider)),
              refreshLabel: healthRefreshLabel(health),
              onRefresh: health.syncing
                  ? null
                  : () => unawaited(actions.refresh()),
            ),
          );
        }
        return _build(
          context,
          state: state,
          health: health,
          quickAction: _stepsAction(context, recorded: state.recorded),
        );
      },
    );
  }

  /// The card for [state]. [warning] is the chip of a state in which Health
  /// does not deliver; [quickAction] sits below the card body.
  Widget _build(
    BuildContext context, {
    required StepsToday state,
    required HealthStepsStatus health,
    required Widget? quickAction,
    String? warning,
  }) {
    final warningChip = warning == null ? null : _WarningChip(text: warning);
    final healthEmpty = health.reading && warning == null;
    if (!state.recorded) {
      final subtitle = healthEmpty
          ? 'Health meldet für heute noch keine Schritte'
          : 'Heute noch nicht eingetragen';
      return MetricCard(
        title: 'Schritte',
        value: '–',
        subtitle: subtitle,
        icon: AppIcon.steps.data,
        accent: AppAccent.steps,
        onTap: () => context.push(StepsRoutes.overview),
        semanticLabel: warning == null
            ? (healthEmpty
                  ? 'Schritte, heute meldet Health noch keine Schritte'
                  : 'Schritte, heute noch nicht eingetragen')
            : 'Schritte, heute noch nicht eingetragen, $warning',
        quickAction: quickAction,
        child: warningChip,
      );
    }
    final progress = state.progress;
    final target = stepsTargetText(progress);
    final percent = progress.percent;
    final subtitle = percent == null
        ? 'Kein Tagesziel aktiv'
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
      onTap: () => context.push(StepsRoutes.overview),
      semanticLabel: warning == null && state.source != StepSource.health
          ? null
          : 'Schritte, ${stepsText(progress.steps)}'
                '${target == null ? '' : ' $target'}, $subtitle$source'
                '${warning == null ? '' : ', $warning'}',
      quickAction: quickAction,
      child: warningChip,
    );
  }

  Widget? _warningAction(HealthStepsStatus health, HealthStepsActions actions) {
    final button = healthCardWarningAction(health);
    if (button == null) {
      return null;
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: HealthTextAction(
        label: button.label,
        semanticLabel: button.semanticLabel,
        onPressed: () => unawaited(actions.perform(button.action)),
      ),
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

/// The line below a card whose value comes from Health: the heart, `Health ·
/// 09:41` and the refresh button with a 48 x 48 tap area (design `4123:444`).
class _HealthSourceRow extends StatelessWidget {
  const _HealthSourceRow({
    required this.text,
    required this.refreshLabel,
    required this.onRefresh,
  });

  final String text;
  final String refreshLabel;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Icon(AppIcon.heart.data, size: 14, color: colors.moduleSteps),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Semantics(
            container: true,
            liveRegion: true,
            label: text,
            excludeSemantics: true,
            child: Text(
              text,
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
        AppIconButton(
          icon: AppIcon.retry.data,
          iconSize: 18,
          iconColor: colors.primaryText,
          semanticLabel: refreshLabel,
          onPressed: onRefresh,
        ),
      ],
    );
  }
}

/// The warning chip of a card whose Health does not deliver (`Health: kein
/// Zugriff`): glyph and text on the warning tint, never colour alone.
class _WarningChip extends StatelessWidget {
  const _WarningChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.warningTint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(AppIcon.error.data, size: 12, color: colors.warningText),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: AppTextStyles.captionStrong.copyWith(
                    color: colors.warningText,
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
