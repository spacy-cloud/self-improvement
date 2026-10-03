import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/water_format.dart';
import 'package:self_improvement/features/nutrition/domain/water_input.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_routes.dart';
import 'package:self_improvement/features/nutrition/presentation/water_quick_add.dart';
import 'package:self_improvement/shared/number_format.dart';

/// The `water` card of the dashboard: today's real total with the target, the
/// progress bar (capped at 100 %, the real numbers stay visible) and the quick
/// add buttons "+250 ml" and "+500 ml". One tap on a button is one saved entry
/// (one operation from the dashboard to the commit); the buttons sit outside
/// the card body, so they never open the water screen.
class WaterDashboardCard extends ConsumerWidget {
  const WaterDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(waterTodayProvider);
    return today.when(
      loading: () => MetricCard(
        title: 'Wasser',
        value: '–',
        icon: AppIcon.water.data,
        accent: AppAccent.water,
      ),
      // Not `ErrorState`: it measures its width with a LayoutBuilder, which the
      // card grid (equal row heights) cannot measure.
      error: (error, stack) => MetricCard(
        title: 'Wasser',
        value: '–',
        subtitle: 'Daten konnten nicht geladen werden',
        icon: AppIcon.water.data,
        accent: AppAccent.water,
        semanticLabel: 'Wasser, Daten konnten nicht geladen werden',
        quickAction: MetricCardAction(
          label: 'Erneut versuchen',
          icon: AppIcon.retry.data,
          accent: AppAccent.water,
          onPressed: () => ref.invalidate(waterTodayProvider),
        ),
      ),
      data: (model) => _Filled(model: model),
    );
  }
}

class _Filled extends ConsumerWidget {
  const _Filled({required this.model});

  final WaterToday model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = model.targetMl;
    final label = waterProgressLabel(model);
    return MetricCard(
      title: 'Wasser',
      value: formatLiters(model.totalMl),
      unit: target == null ? 'l' : null,
      target: target == null ? null : '/ ${formatWaterLiters(target)}',
      icon: AppIcon.water.data,
      accent: AppAccent.water,
      progress: model.fraction,
      progressVariant: AppProgressVariant.water,
      progressSemanticLabel: label,
      subtitle: _subtitle(model),
      onTap: () => context.push(WaterRoutes.screen),
      semanticLabel: label,
      quickAction: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const WaterQuickAddFailureNotice(compact: true),
          Wrap(
            spacing: 8,
            children: [
              for (final amount in waterQuickAmountsMl)
                MetricCardAction(
                  label: formatWaterMl(amount),
                  icon: AppIcon.plus.data,
                  accent: AppAccent.water,
                  semanticLabel: '$amount Milliliter Wasser hinzufügen',
                  onPressed: () => runWaterQuickAdd(ref, amount),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The line under the bar: the real percentage (also above 100 %), the reached
  /// goal as text, or why there is no progress.
  static String _subtitle(WaterToday model) {
    final percent = model.percent;
    if (model.targetMl == null || percent == null) {
      return 'Kein Tagesziel aktiv';
    }
    if (model.goalReached) {
      return percent > 100
          ? 'Tagesziel erreicht · $percent %'
          : 'Tagesziel erreicht';
    }
    return model.isEmpty ? 'Noch nichts eingetragen' : '$percent % erreicht';
  }
}
