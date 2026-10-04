import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';
import 'package:self_improvement/features/focus/presentation/workout_labels.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The glyph of a training category. The glyph differs per category, so the
/// category is never told by colour alone.
IconData workoutCategoryIcon(TrainingCategory category) => switch (category) {
  TrainingCategory.strength => Icons.fitness_center_rounded,
  TrainingCategory.cardio => Icons.directions_run_rounded,
  TrainingCategory.mobility => Icons.self_improvement_rounded,
  TrainingCategory.sport => Icons.sports_basketball_rounded,
};

/// The tint of a training category.
AppAccent workoutCategoryAccent(TrainingCategory category) =>
    switch (category) {
      TrainingCategory.strength => AppAccent.workout,
      TrainingCategory.cardio => AppAccent.water,
      TrainingCategory.mobility => AppAccent.habits,
      TrainingCategory.sport => AppAccent.primary,
    };

/// One workout as a list row. Tapping opens it for editing and deleting.
///
/// The [WorkoutTile.overview] variant shows the category tile, the meta line
/// and when the workout took place; the [WorkoutTile.list] variant (all
/// workouts) shows the date line, the duration and a chevron.
class WorkoutTile extends StatelessWidget {
  const WorkoutTile.overview({
    required this.entry,
    required this.today,
    required this.clock,
    super.key,
  }) : _list = false;

  const WorkoutTile.list({
    required this.entry,
    required this.today,
    required this.clock,
    super.key,
  }) : _list = true;

  final WorkoutEntry entry;
  final LocalDate today;
  final ClockService clock;
  final bool _list;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final semantic =
        '${workoutSpoken(entry, today, clock)}. Tippen zum Bearbeiten';
    void open() => context.push(WorkoutRoutes.edit(entry.id));
    if (_list) {
      return EntryListTile(
        title: entry.displayTitle,
        subtitle: workoutListSubtitle(entry, today),
        semanticLabel: semantic,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '${entry.durationMinutes} Min.',
                textAlign: TextAlign.end,
                style: AppTextStyles.titleCard.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              AppIcon.chevronRight.data,
              size: 20,
              color: colors.textSecondary,
            ),
          ],
        ),
        onTap: open,
      );
    }
    // The "when" text sits at the right edge; on large text it moves into the
    // subtitle, where it can wrap, instead of squeezing the title.
    final stacked =
        MediaQuery.textScalerOf(context).scale(14) / 14 >
        AppSizes.stackTextScale;
    final when = workoutWhenText(entry, today, clock);
    return EntryListTile(
      title: entry.displayTitle,
      subtitle: stacked
          ? '${workoutMetaLine(entry)}\n$when'
          : workoutMetaLine(entry),
      icon: workoutCategoryIcon(entry.category),
      accent: workoutCategoryAccent(entry.category),
      semanticLabel: semantic,
      trailing: stacked
          ? null
          : Text(
              when,
              textAlign: TextAlign.end,
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
      onTap: open,
    );
  }
}
