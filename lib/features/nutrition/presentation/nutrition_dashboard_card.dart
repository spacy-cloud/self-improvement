import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/domain/meal_summary.dart';
import 'package:self_improvement/features/nutrition/presentation/meal_labels.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_routes.dart';

/// The `nutrition` card of the dashboard: number of today's meals and the sum of
/// the KNOWN calories. Missing calories are never counted as 0: the card says
/// "Kalorien unvollständig" instead. No rating, no calorie goal. Without a meal
/// it shows no number, only the way to enter one.
class NutritionDashboardCard extends ConsumerWidget {
  const NutritionDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(mealsTodayProvider);
    return today.when(
      loading: () => MetricCard(
        title: 'Ernährung',
        value: '–',
        icon: AppIcon.meal.data,
        accent: AppAccent.nutrition,
      ),
      error: (error, stack) =>
          ErrorState(onRetry: () => ref.invalidate(mealsTodayProvider)),
      data: (day) => day.isEmpty
          ? MetricCard(
              title: 'Ernährung',
              value: '–',
              subtitle: 'Noch keine Mahlzeit',
              icon: AppIcon.meal.data,
              accent: AppAccent.nutrition,
              onTap: () => context.push(NutritionRoutes.overview),
              semanticLabel: 'Ernährung, noch keine Mahlzeit',
              quickAction: _AddMealAction(),
            )
          : _Filled(summary: day.summary),
    );
  }
}

class _AddMealAction extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MetricCardAction(
      label: 'Mahlzeit eintragen',
      icon: AppIcon.plus.data,
      accent: AppAccent.nutrition,
      onPressed: () => context.push(NutritionRoutes.create),
    );
  }
}

class _Filled extends StatelessWidget {
  const _Filled({required this.summary});

  final MealSummary summary;

  @override
  Widget build(BuildContext context) {
    final subtitle = mealCardSubtitle(summary);
    return MetricCard(
      title: 'Ernährung',
      value: '${summary.mealCount}',
      unit: summary.mealCount == 1 ? 'Mahlzeit' : 'Mahlzeiten',
      subtitle: subtitle.isEmpty ? null : subtitle,
      icon: AppIcon.meal.data,
      accent: AppAccent.nutrition,
      onTap: () => context.push(NutritionRoutes.overview),
      semanticLabel: 'Ernährung heute: ${mealSummarySpoken(summary)}',
      quickAction: _AddMealAction(),
    );
  }
}
