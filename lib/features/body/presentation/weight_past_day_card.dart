import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/presentation/weight_dashboard_card.dart';
import 'package:self_improvement/features/body/presentation/weight_routes.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The `weight` card of Home for a day that is not today (BS-93): the weight as
/// it stood at the end of [day], with the curve of the seven days ending on it
/// and the comparison with the week before.
///
/// It is the card of today ([WeightCardBody]) built from the measurements up to
/// [day]; a measurement made afterwards is not part of it. It only shows: the
/// action "Gewicht eintragen" is left out (a measurement is recorded with the
/// form, which can take an earlier time). Before the first measurement the card
/// reads "Keine Messung bis zu diesem Tag" and no number.
class WeightPastDayCard extends ConsumerWidget {
  /// Creates the card of [day].
  const WeightPastDayCard({required this.day, super.key});

  /// The day shown.
  final LocalDate day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(weightCardOnProvider(day))
        .when(
          loading: () => MetricCard(
            title: 'Gewicht',
            value: '–',
            icon: AppIcon.weight.data,
            accent: AppAccent.weight,
          ),
          error: (error, stack) =>
              ErrorState(onRetry: () => ref.invalidate(weightEntriesProvider)),
          data: (model) => model.isEmpty
              ? MetricCard(
                  title: 'Gewicht',
                  value: '–',
                  subtitle: 'Keine Messung bis zu diesem Tag',
                  icon: AppIcon.weight.data,
                  accent: AppAccent.weight,
                  onTap: () => context.push(WeightRoutes.overview),
                  semanticLabel: 'Gewicht, keine Messung bis zu diesem Tag',
                )
              : WeightCardBody(model: model, today: day),
        );
  }
}
