import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/water_format.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_routes.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// The `water` card of Home for a day that is not today (BS-93): what was
/// drunk on [day] against the target that counted on that day.
///
/// It only shows. There are no quick add buttons: a tap on "+250 ml" would
/// record water for today under the date of another day. The card still opens
/// the water screen, where an entry for an earlier day is recorded with its
/// form. A day without an entry reads "Nichts eingetragen" and no number, never
/// "0 l" (nothing was recorded, which is not the same as drinking nothing).
class WaterPastDayCard extends ConsumerWidget {
  /// Creates the card of [day].
  const WaterPastDayCard({required this.day, super.key});

  /// The day shown.
  final LocalDate day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(waterDayProvider(day))
        .when(
          loading: () => MetricCard(
            title: 'Wasser',
            value: '–',
            icon: AppIcon.water.data,
            accent: AppAccent.water,
          ),
          // Not `ErrorState`: it measures its width with a LayoutBuilder, which
          // the card grid (equal row heights) cannot measure.
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
              onPressed: () => ref.invalidate(waterDayProvider(day)),
            ),
          ),
          data: (model) => _Body(model: model),
        );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.model});

  final WaterToday model;

  @override
  Widget build(BuildContext context) {
    final target = model.targetMl;
    final targetText = target == null ? null : '/ ${formatWaterLiters(target)}';
    final empty = model.isEmpty;
    return MetricCard(
      title: 'Wasser',
      value: empty ? '–' : formatLiters(model.totalMl),
      unit: empty || target != null ? null : 'l',
      target: targetText,
      icon: AppIcon.water.data,
      accent: AppAccent.water,
      progress: empty ? null : model.fraction,
      progressVariant: AppProgressVariant.water,
      progressSemanticLabel: waterDayProgressLabel(model),
      subtitle: waterDaySubtitle(model),
      onTap: () => context.push(WaterRoutes.screen),
      semanticLabel: waterDayProgressLabel(model),
    );
  }
}

/// The line under the bar for a day that is not today: what was reached, or why
/// there is nothing to compare.
String waterDaySubtitle(WaterToday model) {
  if (model.isEmpty) {
    return 'Nichts eingetragen';
  }
  final percent = model.percent;
  if (model.targetMl == null || percent == null) {
    return 'Kein Tagesziel an diesem Tag';
  }
  if (model.goalReached) {
    return percent > 100
        ? 'Tagesziel erreicht · $percent %'
        : 'Tagesziel erreicht';
  }
  return '$percent % erreicht';
}
