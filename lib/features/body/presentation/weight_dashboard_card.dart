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
import 'package:self_improvement/shared/german_date.dart';
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
          : WeightCardBody(model: model, today: today),
    );
  }
}

/// The weight card with a measurement: the current value, the curve of the seven
/// days ending on [today] and the week comparison, or only the honest date when
/// the last measurement is older than the curve.
///
/// [today] is the last day of the curve: today on Home, the day shown when Home
/// pages back (BS-93, `WeightPastDayCard`).
class WeightCardBody extends StatelessWidget {
  /// Creates the card for [model], ending on [today].
  const WeightCardBody({required this.model, required this.today, super.key});

  final WeightCardModel model;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final week = model.weekDeltaGrams;
    final current = model.current!;
    final value = formatKilograms(current.weightGrams);
    // The last measurement may be older than the seven days of the curve: then
    // there is no curve and no week comparison, only the honest date.
    final stale = model.points.isEmpty;
    final lastDate = formatDateShort(
      current.localDate,
      contextYear: today.year,
    );
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
      semanticLabel: stale
          ? 'Gewicht, $value Kilogramm, zuletzt am $lastDate'
          : 'Gewicht, $value Kilogramm, '
                '${week == null ? 'noch kein Wochenvergleich' : '${weightDeltaSpoken(week)} in 7 Tagen'}',
      child: stale
          ? Text(
              'Zuletzt $lastDate',
              style: AppTextStyles.captionStrong.copyWith(
                color: colors.textSecondary,
              ),
            )
          : Column(
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
