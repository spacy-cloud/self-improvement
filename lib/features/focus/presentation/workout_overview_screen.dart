import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/application/workout_ui_providers.dart';
import 'package:self_improvement/features/focus/domain/muscle_recency.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';
import 'package:self_improvement/features/focus/presentation/focus_widgets.dart';
import 'package:self_improvement/features/focus/presentation/workout_labels.dart';
import 'package:self_improvement/features/focus/presentation/workout_widgets.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Route of the goals editor (the weekly goal is changed there).
const String _goalsRoute = '/goals';

/// "Meine Workouts": this week (Monday to Sunday) against the weekly goal, the
/// muscle groups trained last and the latest workouts. The ring is capped at
/// 100 %; the real count and minutes stay visible next to it.
class WorkoutOverviewScreen extends ConsumerWidget {
  const WorkoutOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(workoutLatestProvider);
    final hasEntries = (latest.value ?? const <WorkoutEntry>[]).isNotEmpty;
    return AppScaffold.subpage(
      title: 'Meine Workouts',
      onBack: () => leaveFocusScreen(context),
      primaryAction: hasEntries
          ? PrimaryButton(
              label: 'Training eintragen',
              icon: AppIcon.plus.data,
              onPressed: () => context.push(WorkoutRoutes.create),
            )
          : null,
      body: latest.when(
        loading: () => const ScreenLoading(),
        error: (error, stack) => ErrorState(
          onRetry: () => ref.invalidate(
            workoutEntriesPageProvider(workoutOverviewLatestCount),
          ),
        ),
        data: (entries) => entries.isEmpty
            ? EmptyState(
                title: 'Noch kein Training',
                message:
                    'Trage dein erstes Training ein, dann siehst du hier '
                    'deine Woche.',
                actionLabel: 'Training eintragen',
                onAction: () => context.push(WorkoutRoutes.create),
                icon: AppIcon.workout,
                accent: AppAccent.workout,
              )
            : _Content(entries: entries),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.entries});

  final List<WorkoutEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final today = ref.watch(todayProvider);
    final clock = ref.watch(clockProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _WeekCard(),
        const SizedBox(height: 12),
        const _RecencyCard(),
        AppSectionHeader(
          title: 'Letzte Trainings',
          actionLabel: 'Alle anzeigen',
          actionSemanticLabel: 'Alle Trainings anzeigen',
          onAction: () => context.push(WorkoutRoutes.all),
        ),
        const SizedBox(height: 8),
        AppListGroup(
          children: [
            for (final entry in entries)
              WorkoutTile.overview(entry: entry, today: today, clock: clock),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            'Tippe auf ein Training, um es zu bearbeiten oder zu löschen.',
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _GoalLink(),
      ],
    );
  }
}

/// "Diese Woche": count against the goal, the ring and three numbers.
class _WeekCard extends ConsumerWidget {
  const _WeekCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(workoutWeekSummaryProvider)
        .when(
          loading: () => const AppCard(child: ScreenLoading()),
          error: (error, stack) => ErrorState(
            onRetry: () {
              ref
                ..invalidate(workoutWeekEntriesProvider)
                ..invalidate(goalVersionsProvider);
            },
          ),
          data: (summary) => _WeekCardBody(summary: summary),
        );
  }
}

class _WeekCardBody extends StatelessWidget {
  const _WeekCardBody({required this.summary});

  final WorkoutWeekSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final reached = summary.targetReached;
    final average = workoutAverageMinutes(summary);
    final missing = summary.remainingToTarget;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeading(
            icon: AppIcon.workout.data,
            title: 'Diese Woche',
            accent: AppAccent.workout,
            trailing: 'Ziel: ${summary.weeklyTarget}× pro Woche',
          ),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            label: workoutWeekSpoken(summary),
            excludeSemantics: true,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${summary.entryCount} / ${summary.weeklyTarget}',
                        style: AppTextStyles.displayL.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      TextSpan(
                        text: ' Trainings',
                        style: AppTextStyles.bodyRegular.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                ProgressRing(
                  value: summary.ringFraction,
                  semanticLabel: workoutWeekSpoken(summary),
                  size: 64,
                  strokeWidth: 8,
                  color: colors.moduleWorkout,
                  center: Icon(
                    reached ? AppIcon.check.data : AppIcon.workout.data,
                    size: 24,
                    color: colors.moduleWorkout,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _StatsRow(
            stats: [
              _StatData(
                value: '${summary.totalMinutes} Min.',
                label: 'Trainingszeit',
              ),
              _StatData(
                value: average == null ? '–' : '$average Min.',
                label: 'Ø pro Training',
              ),
              _StatData(
                value: reached
                    ? 'Erreicht'
                    : missing == 1
                    ? '1 fehlt'
                    : '$missing fehlen',
                label: reached ? 'Wochenziel' : 'zum Ziel',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatData {
  const _StatData({required this.value, required this.label});

  final String value;
  final String label;
}

/// Three numbers side by side with dividers; stacked on large text.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final List<_StatData> stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final stacked = scale > AppSizes.stackTextScale;
    final cells = [for (final stat in stats) _Stat(data: stat)];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cells.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    cells[i],
                  ],
                ],
              )
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < cells.length; i++) ...[
                      if (i > 0)
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: colors.borderDecorative,
                        ),
                      Expanded(child: cells[i]),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.data});

  final _StatData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      label: '${data.label}: ${data.value}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            data.value,
            textAlign: TextAlign.center,
            style: AppTextStyles.titleCard.copyWith(color: colors.textPrimary),
          ),
          Text(
            data.label,
            textAlign: TextAlign.center,
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Zuletzt trainiert": the muscle groups of the last four weeks with the day
/// they were trained last. Hidden while no workout names a muscle group.
class _RecencyCard extends ConsumerWidget {
  const _RecencyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final today = ref.watch(todayProvider);
    final list = ref.watch(workoutMuscleRecencyProvider).value;
    if (list == null || list.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Zuletzt trainiert',
                    style: AppTextStyles.titleSection.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                ExcludeSemantics(
                  child: Wrap(
                    spacing: 12,
                    children: [
                      _LegendDot(color: colors.moduleWorkout, label: 'frisch'),
                      _LegendDot(
                        color: colors.textTertiary,
                        label: 'länger her',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final recency in list)
                  _MuscleChip(recency: recency, today: today),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTextStyles.captionDefault.copyWith(
            color: context.tokens.colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _MuscleChip extends StatelessWidget {
  const _MuscleChip({required this.recency, required this.today});

  final MuscleRecency recency;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final fresh = recency.isFresh(today);
    return Semantics(
      container: true,
      label: muscleRecencySpoken(recency, today),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fresh ? colors.tintWorkout : colors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: fresh ? colors.moduleWorkout : colors.textTertiary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  recency.group.label,
                  style: AppTextStyles.bodyStrong.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                lastTrainedText(recency.daysAgo(today)),
                style: AppTextStyles.captionDefault.copyWith(
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

/// The weekly goal is changed in the goals editor; changes apply from
/// tomorrow.
class _GoalLink extends ConsumerWidget {
  const _GoalLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(workoutWeekSummaryProvider).value?.weeklyTarget;
    return AppListGroup(
      children: [
        EntryListTile.chevron(
          title: 'Wochenziel ändern',
          subtitle: target == null
              ? 'Änderungen gelten ab morgen.'
              : 'Aktuell $target Trainings pro Woche. '
                    'Änderungen gelten ab morgen.',
          icon: AppIcon.settings.data,
          accent: AppAccent.workout,
          onTap: () => context.push(_goalsRoute),
        ),
      ],
    );
  }
}
