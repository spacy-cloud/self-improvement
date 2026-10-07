import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/focus/application/workout_day_providers.dart';
import 'package:self_improvement/features/focus/domain/workout_day_mark.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';
import 'package:self_improvement/features/focus/presentation/workout_day_sheet.dart';
import 'package:self_improvement/features/focus/presentation/workout_labels.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The `workout` card of Home for a day that is not today (BS-93): what the day
/// was, from the workouts and the mark of [day] (a workout, a rest day, a
/// skipped day, or nothing recorded).
///
/// It only shows. "Wie war dein Tag?", "Training eintragen" and "Rückgängig"
/// belong to today: a rest day or a skipped day can only be set and taken back
/// for today (BS-99), and a workout for an earlier day is recorded with its
/// form, which the card opens. The weekly numbers are not part of a day and
/// stay on the live card.
class WorkoutPastDayCard extends ConsumerWidget {
  /// Creates the card of [day].
  const WorkoutPastDayCard({required this.day, super.key});

  /// The day shown.
  final LocalDate day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(workoutDayStateOnProvider(day))
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
                ..invalidate(workoutEntriesOnProvider(day))
                ..invalidate(workoutDayMarkOnProvider(day));
            },
          ),
          data: (state) => _build(context, state),
        );
  }

  Widget _build(BuildContext context, WorkoutDayState state) {
    final outcome = state.outcome;
    return MetricCard(
      title: 'Workout',
      value: workoutPastDayValue(state),
      valueStyle: AppTextStyles.titleCard,
      valueIcon: switch (outcome) {
        WorkoutDayOutcome.open => null,
        WorkoutDayOutcome.trained => AppIcon.check.data,
        WorkoutDayOutcome.rest => workoutRestIcon,
        WorkoutDayOutcome.skipped => workoutSkipIcon,
      },
      subtitle: workoutPastDayCaption(state),
      icon: AppIcon.workout.data,
      accent: AppAccent.workout,
      onTap: () => context.push(WorkoutRoutes.overview),
      semanticLabel: 'Workout, ${workoutPastDaySpoken(state)}',
    );
  }
}
