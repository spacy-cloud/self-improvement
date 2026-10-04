import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/presentation/weight_routes.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/body/steps/application/steps_stats.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_chart.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_labels.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_routes.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';

/// "Meine Schritte": today's total against the goal, the chart of the chosen
/// period with its text alternative, the figures of that period and the days
/// that can be corrected.
class StepsOverviewScreen extends ConsumerWidget {
  const StepsOverviewScreen({super.key});

  /// Number of corrigible days listed below the figures.
  static const int listedDays = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(stepsPeriodProvider);
    final todayState = ref.watch(stepsTodayProvider);
    final history = ref.watch(stepsHistoryProvider(period));
    final today = ref.watch(todayProvider);

    final Widget body;
    if (todayState.hasError || history.hasError) {
      body = ErrorState(
        onRetry: () {
          ref
            ..invalidate(stepsTodayProvider)
            ..invalidate(stepsHistoryProvider(period));
        },
      );
    } else if (!todayState.hasValue || !history.hasValue) {
      body = const _Loading();
    } else {
      body = _Content(
        todayState: todayState.requireValue,
        days: history.requireValue,
        period: period,
        today: today,
      );
    }
    return AppScaffold.subpage(
      title: 'Meine Schritte',
      onBack: () => leaveWeightScreen(context),
      primaryAction: PrimaryButton(
        label: 'Schritte eintragen',
        icon: AppIcon.plus.data,
        onPressed: () => context.push(StepsRoutes.create),
      ),
      body: body,
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          'Wird geladen …',
          style: AppTextStyles.bodyRegular.copyWith(
            color: context.tokens.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({
    required this.todayState,
    required this.days,
    required this.period,
    required this.today,
  });

  final StepsToday todayState;
  final List<StepsHistoryDay> days;
  final int period;
  final LocalDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = computeStepsStats(days);
    final recorded = [
      for (final day in days)
        if (day.recorded) day,
    ].take(StepsOverviewScreen.listedDays).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TodayCard(state: todayState, today: today),
        const SizedBox(height: 12),
        ChartSummary(
          title: 'Verlauf',
          summary: stepsChartSummary(stats),
          columns: const ['Schritte', 'Ziel'],
          rows: [
            for (final day in days.reversed)
              ChartSummaryRow(
                label: formatDateShort(day.date, contextYear: today.year),
                values: [
                  day.recorded ? stepsText(day.progress.steps) : '–',
                  stepsDayStatus(day),
                ],
              ),
          ],
          chart: stats.isEmpty
              ? null
              : StepsBarChart(
                  days: days,
                  today: today,
                  target: todayState.progress.target,
                ),
          headerTrailing: PeriodSelector<int>(
            options: [
              for (final option in stepsPeriods)
                PeriodOption<int>(
                  value: option,
                  label: stepsPeriodLabel(option),
                  semanticLabel: stepsPeriodSpoken(option),
                ),
            ],
            selected: period,
            semanticLabel: 'Zeitraum',
            onChanged: (value) =>
                ref.read(stepsPeriodProvider.notifier).select(value),
          ),
        ),
        const SizedBox(height: 12),
        AdaptiveGrid(
          maxColumns: 3,
          minCellWidth: 96,
          children: [
            _StatTile(
              value: stats.averageSteps == null
                  ? '–'
                  : stepsText(stats.averageSteps!),
              label: 'Ø pro Tag',
            ),
            _StatTile(
              value: stats.bestSteps == null
                  ? '–'
                  : stepsText(stats.bestSteps!),
              label: stepsBestDayLabel(stats),
            ),
            _StatTile(
              value: stats.hasTarget
                  ? '${stats.reachedDays} / ${stats.windowDays}'
                  : '–',
              label: stats.hasTarget ? 'Ziel erreicht' : 'Kein Tagesziel',
            ),
          ],
        ),
        if (recorded.isNotEmpty) ...[
          const SizedBox(height: 12),
          const AppSectionHeader(title: 'Eingetragene Tage'),
          const SizedBox(height: 8),
          AppListGroup(
            children: [
              for (final day in recorded) _DayRow(day: day, today: today),
            ],
          ),
        ],
        const SizedBox(height: 12),
        const _HintCard(),
      ],
    );
  }
}

/// "Heute": the total, the remaining steps, the bar and the source.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.state, required this.today});

  final StepsToday state;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final progress = state.progress;
    final target = stepsTargetText(progress);
    final remaining = stepsRemainingText(progress);
    final valueText = state.recorded ? stepsText(progress.steps) : '–';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                Icon(AppIcon.steps.data, size: 24, color: colors.moduleSteps),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Heute',
                    style: AppTextStyles.titleCard.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    formatDateLong(today),
                    textAlign: TextAlign.end,
                    style: AppTextStyles.captionDefault.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                container: true,
                label: state.recorded
                    ? 'Heute $valueText Schritte'
                          '${target == null ? '' : ' $target'}'
                    : 'Heute noch keine Schritte eingetragen',
                excludeSemantics: true,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: valueText,
                          style: AppTextStyles.displayXl.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        if (target != null)
                          TextSpan(
                            text: ' $target',
                            style: AppTextStyles.bodyRegular.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (state.recorded && remaining != null)
                AppBadge(label: remaining, accent: AppAccent.steps),
            ],
          ),
          if (state.recorded && progress.target != null) ...[
            const SizedBox(height: 12),
            AppProgressBar(
              value: progress.fraction,
              variant: AppProgressVariant.steps,
              semanticLabel:
                  'Fortschritt zum Tagesziel: ${progress.percent} Prozent',
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(
                state.recorded
                    ? stepsPercentText(progress)
                    : 'Heute noch nicht eingetragen',
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const _SourceChip(),
            ],
          ),
        ],
      ),
    );
  }
}

/// The source of the numbers: V1 only knows manual totals.
class _SourceChip extends StatelessWidget {
  const _SourceChip();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      label: 'Quelle: Manuell',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.track,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcon.edit.data, size: 14, color: colors.textSecondary),
              const SizedBox(width: 6),
              Text(
                'Quelle: Manuell',
                style: AppTextStyles.captionStrong.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: AppTextStyles.titleSection.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.today});

  final StepsHistoryDay day;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final title = formatRelativeDay(day.date, today);
    final status = stepsDayStatus(day);
    final value = stepsText(day.progress.steps);
    return EntryListTile(
      title: title,
      subtitle: status,
      semanticLabel: '$title, $value Schritte, $status. Tippen zum Bearbeiten',
      trailing: Text(
        value,
        style: AppTextStyles.titleCard.copyWith(color: colors.textPrimary),
      ),
      onTap: () => context.push(StepsRoutes.createFor(day.date)),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      child: MergeSemantics(
        child: Row(
          children: [
            Icon(AppIcon.edit.data, size: 28, color: colors.moduleSteps),
            const SizedBox(width: 12),
            Container(width: 1, height: 44, color: colors.borderInput),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Einmal am Tag eintragen',
                    style: AppTextStyles.captionStrong.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Trag abends deine Gesamtzahl aus Schrittzähler oder Uhr '
                    'ein. Ein neuer Wert für denselben Tag ersetzt den alten.',
                    style: AppTextStyles.captionDefault.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
