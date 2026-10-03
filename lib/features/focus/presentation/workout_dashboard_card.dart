import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';
import 'package:self_improvement/features/focus/presentation/workout_labels.dart';

/// The `workout` card of the dashboard: this week (Monday to Sunday) with the
/// real count against the weekly goal, a ring that stops at 100 % and the
/// minutes. Workouts are not focus time; the numbers here are separate from the
/// focus card.
class WorkoutDashboardCard extends ConsumerWidget {
  const WorkoutDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(workoutWeekSummaryProvider)
        .when(
          loading: () => MetricCard(
            title: 'Workout',
            value: '–',
            icon: AppIcon.workout.data,
            accent: AppAccent.workout,
          ),
          error: (error, stack) => ErrorState(
            onRetry: () {
              ref
                ..invalidate(workoutWeekEntriesProvider)
                ..invalidate(goalVersionsProvider);
            },
          ),
          data: (summary) => _WeekCard(summary: summary),
        );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.summary});

  final WorkoutWeekSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final latest = summary.latest;
    final subtitle = latest == null
        ? workoutNoEntryThisWeekMessage
        : 'Zuletzt: ${latest.displayTitle}';
    final spoken = workoutWeekSpoken(summary);
    return MetricCard(
      title: 'Workout',
      value: '${summary.entryCount}',
      target: '/ ${summary.weeklyTarget} Trainings',
      icon: AppIcon.workout.data,
      accent: AppAccent.workout,
      subtitle: subtitle,
      onTap: () => context.push(WorkoutRoutes.overview),
      semanticLabel: 'Workout, $spoken $subtitle',
      quickAction: MetricCardAction(
        label: 'Training eintragen',
        icon: AppIcon.plus.data,
        accent: AppAccent.workout,
        onPressed: () => context.push(WorkoutRoutes.create),
      ),
      child: Row(
        children: [
          ProgressRing(
            value: summary.ringFraction,
            semanticLabel: spoken,
            size: 44,
            strokeWidth: 6,
            color: colors.moduleWorkout,
            center: Icon(
              summary.targetReached ? AppIcon.check.data : AppIcon.workout.data,
              size: 16,
              color: colors.moduleWorkout,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${summary.totalMinutes} Min. diese Woche',
              style: AppTextStyles.bodyStrong.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
