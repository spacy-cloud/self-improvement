import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/data/weight_repository.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/domain/weight_overview.dart';

final weightRepositoryProvider = Provider<WeightRepository>(
  (ref) => WeightRepository(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
  ),
);

/// All active weight measurements, newest first.
final weightEntriesProvider = StreamProvider<List<WeightEntry>>(
  (ref) => ref.watch(weightRepositoryProvider).watchActive(),
);

/// One measurement by id; emits null when it does not exist (any more).
final weightEntryProvider = StreamProvider.family<WeightEntry?, String>(
  (ref, id) => ref.watch(weightRepositoryProvider).watchById(id),
);

/// Selected chart period in days (7, 30 or 90).
final weightPeriodProvider = NotifierProvider<WeightPeriodNotifier, int>(
  WeightPeriodNotifier.new,
);

class WeightPeriodNotifier extends Notifier<int> {
  @override
  int build() => weightPeriods.first;

  void select(int days) {
    assert(weightPeriods.contains(days), 'unsupported period');
    state = days;
  }
}

/// The overview model: measurements, profile goal values, today and period
/// combined. Recomputed only when one of those changes, never per frame.
final weightOverviewProvider = Provider<AsyncValue<WeightOverview>>((ref) {
  final entries = ref.watch(weightEntriesProvider);
  final profile = ref.watch(profileProvider);
  final today = ref.watch(todayProvider);
  final period = ref.watch(weightPeriodProvider);
  return entries.when(
    loading: () => const AsyncLoading(),
    error: AsyncError.new,
    data: (list) {
      final profileValue = profile.value;
      return AsyncData(
        buildWeightOverview(
          entriesNewestFirst: list,
          today: today,
          periodDays: period,
          startWeightGrams: profileValue?.startWeightGrams,
          targetWeightGrams: profileValue?.targetWeightGrams,
          heightCm: profileValue?.heightCm,
          ageYears: profileValue?.ageYears,
        ),
      );
    },
  );
});

/// The dashboard weight card: current value, 7-day curve, week comparison.
final weightCardProvider = Provider<AsyncValue<WeightCardModel>>((ref) {
  final entries = ref.watch(weightEntriesProvider);
  final today = ref.watch(todayProvider);
  return entries.when(
    loading: () => const AsyncLoading(),
    error: AsyncError.new,
    data: (list) =>
        AsyncData(buildWeightCard(entriesNewestFirst: list, today: today)),
  );
});
