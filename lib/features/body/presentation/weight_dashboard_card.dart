import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_overview.dart';
import 'package:self_improvement/features/body/presentation/weight_chart.dart';
import 'package:self_improvement/features/body/presentation/weight_labels.dart';
import 'package:self_improvement/features/body/presentation/weight_routes.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// The `weight` card of the dashboard: current value, the last seven days as a
/// small curve and the neutral week comparison. Without a measurement it shows
/// no number, only the way to enter one.
class WeightDashboardCard extends ConsumerWidget {
  const WeightDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(weightCardProvider);
    final today = ref.watch(todayProvider);
    return card.when(
      loading: () => const MetricCard(
        title: 'Gewicht',
        value: '–',
        icon: Icons.monitor_weight_outlined,
        accent: AppAccent.weight,
      ),
      error: (error, stack) =>
          ErrorState(onRetry: () => ref.invalidate(weightEntriesProvider)),
      data: (model) => model.isEmpty
          ? MetricCard(
              title: 'Gewicht',
              value: '–',
              subtitle: 'Noch keine Messung',
              icon: AppIcon.weight.data,
              accent: AppAccent.weight,
              onTap: () => context.push(WeightRoutes.overview),
              semanticLabel: 'Gewicht, noch keine Messung',
              quickAction: MetricCardAction(
                label: 'Gewicht eintragen',
                icon: AppIcon.plus.data,
                accent: AppAccent.weight,
                onPressed: () => context.push(WeightRoutes.create),
              ),
            )
          : _FilledCard(model: model, today: today),
    );
  }
}

class _FilledCard extends StatelessWidget {
  const _FilledCard({required this.model, required this.today});

  final WeightCardModel model;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final week = model.weekDeltaGrams;
    final value = formatKilograms(model.current!.weightGrams);
    final weekText = week == null
        ? 'Noch kein Wochenvergleich'
        : '${weightDeltaText(week).replaceAll('  ', ' ')} in 7 Tagen';
    return MetricCard(
      title: 'Gewicht',
      value: value,
      unit: 'kg',
      icon: AppIcon.weight.data,
      accent: AppAccent.weight,
      onTap: () => context.push(WeightRoutes.overview),
      semanticLabel:
          'Gewicht, $value Kilogramm, '
          '${week == null ? 'noch kein Wochenvergleich' : '${weightDeltaSpoken(week)} in 7 Tagen'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeightSparkline(points: model.points, today: today),
          const SizedBox(height: 6),
          Text(
            weekText,
            style: AppTextStyles.captionStrong.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
