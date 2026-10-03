import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/analysis/data/analysis_data_source.dart';
import 'package:self_improvement/core/analysis/data/analysis_repository.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/analysis/domain/workout_week.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';

final analysisDataSourceProvider = Provider<AnalysisDataSource>(
  (ref) => AnalysisDataSource(
    database: ref.watch(appDatabaseProvider),
    dayStatus: ref.watch(dayStatusRepositoryProvider),
  ),
);

final analysisRepositoryProvider = Provider<AnalysisRepository>(
  (ref) => AnalysisRepository(
    database: ref.watch(appDatabaseProvider),
    source: ref.watch(analysisDataSourceProvider),
  ),
);

/// The selected period length: 7, 30 or 90 days, default 7.
final analysisPeriodProvider =
    NotifierProvider<AnalysisPeriodNotifier, AnalysisPeriodLength>(
      AnalysisPeriodNotifier.new,
    );

class AnalysisPeriodNotifier extends Notifier<AnalysisPeriodLength> {
  @override
  AnalysisPeriodLength build() => AnalysisPeriodLength.days7;

  /// Selects another length. Selecting the current one changes nothing.
  void select(AnalysisPeriodLength length) {
    if (length != state) {
      state = length;
    }
  }
}

/// The selected period anchored at today. Changes when the selection or the
/// calendar day changes (`todayProvider`).
final analysisPeriodSpecProvider = Provider<AnalysisPeriodSpec>(
  (ref) => AnalysisPeriodSpec(
    length: ref.watch(analysisPeriodProvider),
    today: ref.watch(todayProvider),
  ),
);

/// The analysis report of the selected period (7, 30 or 90 days ending today,
/// today included), recomputed when the data, the selection or the day
/// changes. A stream built on `watchComputed`: never recomputed per widget
/// build. While another period loads the previous report stays available as
/// the previous value of the `AsyncValue`.
final analysisReportProvider = StreamProvider<AnalysisReport>(
  (ref) => ref
      .watch(analysisRepositoryProvider)
      .watch(ref.watch(analysisPeriodSpecProvider)),
);

/// The workout week card of today (current Monday-to-Sunday week to date
/// against the same weekdays of the previous week), independent of the
/// selected period. The dashboard can reuse it.
final workoutWeekCardProvider = StreamProvider<WorkoutWeekCard>(
  (ref) => ref
      .watch(analysisRepositoryProvider)
      .watchWorkoutWeek(ref.watch(todayProvider)),
);
