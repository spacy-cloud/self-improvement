import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_calculations.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/domain/weight_overview.dart';
import 'package:self_improvement/features/body/presentation/weight_chart.dart';
import 'package:self_improvement/features/body/presentation/weight_labels.dart';
import 'package:self_improvement/features/body/presentation/weight_routes.dart';
import 'package:self_improvement/features/body/presentation/weight_widgets.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// "Mein Gewicht": current value with the week comparison and the optional
/// goal, the chart of the selected period with its text alternative, the
/// latest measurements and the optional calculated BMI.
class WeightOverviewScreen extends ConsumerWidget {
  const WeightOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(weightOverviewProvider);
    final data = overview.value;
    final hasEntries = data != null && !data.isEmpty;
    return AppScaffold.subpage(
      title: 'Mein Gewicht',
      onBack: () => leaveWeightScreen(context),
      primaryAction: hasEntries
          ? PrimaryButton(
              label: 'Gewicht eintragen',
              icon: AppIcon.plus.data,
              onPressed: () => context.push(WeightRoutes.create),
            )
          : null,
      body: overview.when(
        loading: () => const _Loading(),
        error: (error, stack) =>
            ErrorState(onRetry: () => ref.invalidate(weightEntriesProvider)),
        data: (data) => data.isEmpty
            ? EmptyState(
                title: 'Noch keine Messung',
                message:
                    'Trage dein Gewicht ein, dann siehst du hier deinen '
                    'Verlauf.',
                actionLabel: 'Gewicht eintragen',
                onAction: () => context.push(WeightRoutes.create),
              )
            : _Content(overview: data),
      ),
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
  const _Content({required this.overview});

  final WeightOverview overview;

  /// Number of entries in the "Letzte Einträge" list.
  static const int latestCount = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(clockProvider);
    final today = ref.watch(todayProvider);
    final profile = ref.watch(profileProvider).value;
    final entries = overview.entriesNewestFirst;
    final deltas = deltasToPrevious([
      for (final entry in entries)
        WeightSample(
          id: entry.id,
          occurredAtUtc: entry.occurredAtUtc,
          localDate: entry.localDate,
          grams: entry.weightGrams,
        ),
    ]);
    final oldest = entries.last;
    final startGrams = profile?.startWeightGrams;
    final latest = entries.take(latestCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CurrentCard(
          overview: overview,
          today: today,
          clock: clock,
          startGrams: startGrams,
          targetGrams: profile?.targetWeightGrams,
        ),
        const SizedBox(height: 12),
        _ChartCard(overview: overview, today: today),
        const SizedBox(height: 12),
        AppSectionHeader(
          title: 'Letzte Einträge',
          actionLabel: entries.length > latestCount ? 'Alle anzeigen' : null,
          onAction: entries.length > latestCount
              ? () => context.push(WeightRoutes.all)
              : null,
          actionSemanticLabel: 'Alle Messungen anzeigen',
        ),
        const SizedBox(height: 8),
        AppListGroup(
          children: [
            for (final entry in latest)
              _EntryRow(
                entry: entry,
                today: today,
                time: weightEntryTime(clock, entry),
                delta: deltas[entry.id],
                isStart:
                    startGrams != null &&
                    entry.id == oldest.id &&
                    entry.weightGrams == startGrams,
              ),
          ],
        ),
        if (entries.length > latestCount) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                'Tippe auf einen Eintrag, um ihn zu bearbeiten oder zu '
                'löschen.',
                style: AppTextStyles.captionDefault.copyWith(
                  color: context.tokens.colors.textSecondary,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _BmiCard(overview: overview),
      ],
    );
  }
}

/// "Aktuell": value, time, week comparison and the optional goal progress.
class _CurrentCard extends StatelessWidget {
  const _CurrentCard({
    required this.overview,
    required this.today,
    required this.clock,
    required this.startGrams,
    required this.targetGrams,
  });

  final WeightOverview overview;
  final LocalDate today;
  final ClockService clock;
  final int? startGrams;
  final int? targetGrams;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final current = overview.current!;
    final week = overview.weekDeltaGrams;
    final goal = overview.goal;
    final when =
        '${formatRelativeDay(current.localDate, today)}, '
        '${weightEntryTime(clock, current)}';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                Icon(AppIcon.weight.data, size: 24, color: colors.moduleWeight),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aktuell',
                    style: AppTextStyles.titleCard.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  when,
                  style: AppTextStyles.captionDefault.copyWith(
                    color: colors.textSecondary,
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
                label:
                    'Aktuelles Gewicht ${formatKilograms(current.weightGrams)} '
                    'Kilogramm',
                excludeSemantics: true,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: formatKilograms(current.weightGrams),
                        style: AppTextStyles.displayXl.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      TextSpan(
                        text: ' kg',
                        style: AppTextStyles.titleSection.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (week != null)
                WeightDeltaBadge(deltaGrams: week, since: 'seit letzter Woche')
              else
                const NoComparisonBadge(text: 'Noch kein Wochenvergleich'),
            ],
          ),
          if (goal != null && startGrams != null && targetGrams != null) ...[
            const SizedBox(height: 14),
            _GoalProgress(
              goal: goal,
              startGrams: startGrams!,
              targetGrams: targetGrams!,
            ),
          ] else ...[
            const SizedBox(height: 8),
            EntryListTile.chevron(
              title: 'Zielgewicht festlegen',
              subtitle: 'Optional: Start- und Zielgewicht im Profil ergänzen',
              icon: AppIcon.hint.data,
              accent: AppAccent.weight,
              onTap: () => context.push('/profile/edit'),
            ),
          ],
        ],
      ),
    );
  }
}

class _GoalProgress extends StatelessWidget {
  const _GoalProgress({
    required this.goal,
    required this.startGrams,
    required this.targetGrams,
  });

  final WeightGoalState goal;
  final int startGrams;
  final int targetGrams;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final percent = (goal.progress * 100).round();
    final secondary = AppTextStyles.captionDefault.copyWith(
      color: colors.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppProgressBar(
          value: goal.progress,
          semanticLabel: goal.reached
              ? 'Zielgewicht erreicht'
              : 'Fortschritt zum Zielgewicht: $percent Prozent',
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 2,
          children: [
            Text('Start ${formatKilograms(startGrams)} kg', style: secondary),
            Text(
              weightGoalRemainingText(goal),
              style: AppTextStyles.captionStrong.copyWith(
                color: goal.reached ? colors.primaryText : colors.textPrimary,
              ),
            ),
            Text('Ziel ${formatKilograms(targetGrams)} kg', style: secondary),
          ],
        ),
      ],
    );
  }
}

class _ChartCard extends ConsumerWidget {
  const _ChartCard({required this.overview, required this.today});

  final WeightOverview overview;
  final LocalDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = overview.points;
    final days = overview.periodDays;
    return ChartSummary(
      title: 'Verlauf',
      summary: weightChartSummary(points, days, today),
      columns: const ['Gewicht'],
      rows: [
        for (final point in points)
          ChartSummaryRow(
            label: formatDateShort(point.date, contextYear: today.year),
            values: ['${formatKilograms(point.grams)} kg'],
          ),
      ],
      chart: points.isEmpty
          ? null
          : WeightChart(points: points, today: today, periodDays: days),
      headerTrailing: PeriodSelector<int>(
        options: [
          for (final option in weightPeriods)
            PeriodOption<int>(
              value: option,
              label: weightPeriodLabel(option),
              semanticLabel: weightPeriodSpoken(option),
            ),
        ],
        selected: days,
        semanticLabel: 'Zeitraum',
        onChanged: (value) =>
            ref.read(weightPeriodProvider.notifier).select(value),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.today,
    required this.time,
    required this.delta,
    required this.isStart,
  });

  final WeightEntry entry;
  final LocalDate today;
  final String time;
  final int? delta;
  final bool isStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final title = formatRelativeDay(entry.localDate, today);
    final meta = weightMetaLine(time, entry, isStart: isStart);
    final value = '${formatKilograms(entry.weightGrams)} kg';
    return EntryListTile(
      title: title,
      subtitle: meta,
      semanticLabel:
          '$title, $meta, $value'
          '${delta == null ? '' : ', ${weightDeltaSpoken(delta!)}'}. '
          'Tippen zum Bearbeiten',
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: AppTextStyles.titleCard.copyWith(color: colors.textPrimary),
          ),
          if (delta != null)
            Text(
              weightDeltaText(delta!).replaceAll('  ', ' '),
              style: AppTextStyles.captionStrong.copyWith(
                color: colors.textSecondary,
              ),
            ),
        ],
      ),
      onTap: () => context.push(WeightRoutes.edit(entry.id)),
    );
  }
}

class _BmiCard extends StatelessWidget {
  const _BmiCard({required this.overview});

  final WeightOverview overview;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final bmi = overview.bmi;
    if (bmi == null) {
      return AppListGroup(
        children: [
          EntryListTile.chevron(
            title: 'BMI anzeigen',
            subtitle: 'Größe und Alter im Profil ergänzen',
            icon: AppIcon.info.data,
            accent: AppAccent.weight,
            onTap: () => context.push('/profile/edit'),
          ),
        ],
      );
    }
    final value = formatTenths(bmi.tenths);
    return AppCard(
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Rechnerischer BMI',
                    style: AppTextStyles.titleCard.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  value,
                  style: AppTextStyles.titleScreen.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Rein rechnerischer Wert aus Gewicht und Größe, ohne Bewertung '
              'und ohne Aussage über deine Gesundheit.',
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
