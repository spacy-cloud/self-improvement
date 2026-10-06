import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/features/focus/application/workout_day_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/workout_day_mark.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';
import 'package:self_improvement/features/focus/presentation/workout_day_sheet.dart';
import 'package:self_improvement/features/focus/presentation/workout_labels.dart';

/// The `workout` card of the dashboard.
///
/// Without the optional daily goal "Workout heute" (the default): this week
/// (Monday to Sunday) with the real count against the weekly goal, a ring that
/// stops at 100 % and the minutes. With the goal on: today only (a workout, a
/// rest day, a skipped day, or still open), and the weekly goal stays out of
/// it: no number of workouts per week decides whether the day is reached.
/// Workouts are not focus time; the numbers here are separate from the focus
/// card.
class WorkoutDashboardCard extends ConsumerWidget {
  const WorkoutDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(workoutDailyGoalAppliesProvider)
        .when(
          loading: _loading,
          error: (error, stack) =>
              ErrorState(onRetry: () => ref.invalidate(todayStatusProvider)),
          data: (daily) => daily ? const _DayCard() : const _WeekCard(),
        );
  }
}

Widget _loading() => MetricCard(
  title: 'Workout',
  value: '–',
  icon: AppIcon.workout.data,
  accent: AppAccent.workout,
);

/// The card of the weekly goal (the daily goal is off).
class _WeekCard extends ConsumerWidget {
  const _WeekCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(workoutWeekSummaryProvider)
        .when(
          loading: _loading,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${summary.totalMinutes} Min.',
                  style: AppTextStyles.bodyStrong.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  'diese Woche',
                  style: AppTextStyles.captionDefault.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The card of the daily goal "Workout heute": today's workout, rest day or
/// skipped day, or the question how the day was (Figma `4123:316`).
class _DayCard extends ConsumerWidget {
  const _DayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(workoutDayStateProvider)
        .when(
          loading: _loading,
          error: (error, stack) => ErrorState(
            onRetry: () {
              ref
                ..invalidate(workoutTodayEntriesProvider)
                ..invalidate(workoutDayMarkTodayProvider);
            },
          ),
          data: (state) => _DayCardBody(state: state),
        );
  }
}

class _DayCardBody extends ConsumerWidget {
  const _DayCardBody({required this.state});

  final WorkoutDayState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outcome = state.outcome;
    final busy = ref.watch(workoutDayActionsProvider);
    return MetricCard(
      title: 'Workout',
      value: workoutDayValue(state),
      valueStyle: AppTextStyles.titleCard,
      valueIcon: switch (outcome) {
        WorkoutDayOutcome.open => null,
        WorkoutDayOutcome.trained => AppIcon.check.data,
        WorkoutDayOutcome.rest => workoutRestIcon,
        WorkoutDayOutcome.skipped => workoutSkipIcon,
      },
      subtitle: workoutDayCaption(state),
      icon: AppIcon.workout.data,
      accent: AppAccent.workout,
      onTap: () => context.push(WorkoutRoutes.overview),
      semanticLabel: 'Workout, ${workoutDaySpoken(state)}',
      quickAction: switch (outcome) {
        WorkoutDayOutcome.open => MetricCardAction(
          label: 'Wie war dein Tag?',
          accent: AppAccent.workout,
          onPressed: () => unawaited(askHowTheDayWas(context, ref)),
        ),
        WorkoutDayOutcome.trained => MetricCardAction(
          label: 'Training eintragen',
          icon: AppIcon.plus.data,
          accent: AppAccent.workout,
          onPressed: () => context.push(WorkoutRoutes.create),
        ),
        WorkoutDayOutcome.rest || WorkoutDayOutcome.skipped => MetricCardAction(
          label: 'Rückgängig',
          semanticLabel: workoutDayTakeBackLabel(state),
          accent: AppAccent.workout,
          onPressed: busy
              ? null
              : () => unawaited(
                  takeBackWorkoutDay(
                    ref.read(workoutDayActionsProvider.notifier),
                    ref.read(feedbackServiceProvider),
                    state.takeBackMark!,
                  ),
                ),
        ),
      },
    );
  }
}
