import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/domain/meal_summary.dart';
import 'package:self_improvement/features/nutrition/presentation/meal_labels.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_routes.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The `nutrition` card of Home for a day that is not today (BS-93): the number
/// of meals of [day] and the sum of the KNOWN calories, as on the live card (a
/// missing calorie value is never counted as 0, no rating, no goal).
///
/// It only shows: no "Mahlzeit eintragen" (an entry made from here would be
/// recorded for today). The card opens the meals screen, where an earlier meal
/// is recorded with its form. A day without a meal reads "Keine Mahlzeit
/// eingetragen" and no number.
class NutritionPastDayCard extends ConsumerWidget {
  /// Creates the card of [day].
  const NutritionPastDayCard({required this.day, super.key});

  /// The day shown.
  final LocalDate day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(mealsDayProvider(day))
        .when(
          loading: () => MetricCard(
            title: 'Ernährung',
            value: '–',
            icon: AppIcon.meal.data,
            accent: AppAccent.nutrition,
          ),
          // Not `ErrorState`: it measures its width with a LayoutBuilder, which
          // the card grid (equal row heights) cannot measure.
          error: (error, stack) => MetricCard(
            title: 'Ernährung',
            value: '–',
            subtitle: 'Daten konnten nicht geladen werden',
            icon: AppIcon.meal.data,
            accent: AppAccent.nutrition,
            semanticLabel: 'Ernährung, Daten konnten nicht geladen werden',
            quickAction: MetricCardAction(
              label: 'Erneut versuchen',
              icon: AppIcon.retry.data,
              accent: AppAccent.nutrition,
              onPressed: () => ref.invalidate(mealsDayProvider(day)),
            ),
          ),
          data: (model) => model.isEmpty
              ? MetricCard(
                  title: 'Ernährung',
                  value: '–',
                  subtitle: 'Keine Mahlzeit eingetragen',
                  icon: AppIcon.meal.data,
                  accent: AppAccent.nutrition,
                  onTap: () => context.push(NutritionRoutes.overview),
                  semanticLabel: 'Ernährung, keine Mahlzeit eingetragen',
                )
              : _filled(context, model.summary),
        );
  }

  Widget _filled(BuildContext context, MealSummary summary) {
    final subtitle = mealCardSubtitle(summary);
    return MetricCard(
      title: 'Ernährung',
      value: '${summary.mealCount}',
      unit: summary.mealCount == 1 ? 'Mahlzeit' : 'Mahlzeiten',
      subtitle: subtitle.isEmpty ? null : subtitle,
      icon: AppIcon.meal.data,
      accent: AppAccent.nutrition,
      onTap: () => context.push(NutritionRoutes.overview),
      semanticLabel: 'Ernährung an diesem Tag: ${mealSummarySpoken(summary)}',
    );
  }
}
