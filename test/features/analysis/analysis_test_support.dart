import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:self_improvement/core/analysis/application/analysis_providers.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../core/analysis/analysis_fixtures.dart';

export '../../core/analysis/analysis_fixtures.dart'
    show d2026, referenceDays, refToday, refUsageStart;

/// Today of the pure screen tests: Saturday 2026-10-03, 10:00 Europe/Berlin.
const String analysisNowIso = '2026-10-03T08:00:00Z';

/// Decides what the report provider emits: [call] counts the builds of the
/// provider (1 for the first read, 2 after a period change or a retry), [report]
/// is the report of the selected period.
typedef ReportStream = Stream<AnalysisReport> Function(
  int call,
  AnalysisReport report,
);

Stream<AnalysisReport> _emit(int call, AnalysisReport report) =>
    Stream<AnalysisReport>.value(report);

/// A container whose analysis report is built by the pure engine function from
/// [days] for whatever period is selected (the same recomputation the data
/// layer does, without a database). The report follows the period selection
/// and the day, exactly like the real provider. [stream] lets a test delay,
/// fail or withhold the emission.
ProviderContainer analysisContainer({
  List<AnalysisDay>? days,
  Set<ModuleId>? modules,
  LocalDate? usageStart,
  bool noUsageStart = false,
  int? weeklyTarget = 3,
  bool? hasGoalEver,
  FakeClock? clock,
  ReportStream stream = _emit,
  List<Override> overrides = const <Override>[],
}) {
  var calls = 0;
  final container = ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: <Override>[
      clockProvider.overrideWithValue(clock ?? FakeClock.at(analysisNowIso)),
      analysisReportProvider.overrideWith((ref) {
        final period = ref.watch(analysisPeriodSpecProvider);
        calls++;
        return stream(
          calls,
          buildAnalysisReport(
            period: period,
            days: days ?? referenceDays(),
            usageStart: noUsageStart ? null : (usageStart ?? refUsageStart),
            activeModules: modules ?? ModuleId.values.toSet(),
            workoutWeeklyTarget: weeklyTarget,
            hasApplicableGoalEver: hasGoalEver,
          ),
        );
      }),
      ...overrides,
    ],
  );
  return container;
}

/// Deterministic synthetic days for the longer periods: [count] days ending
/// [today], with gaps (unrecorded steps, water and weight days, days without
/// activity, meals without calories) so every empty-slot rule is exercised.
List<AnalysisDay> syntheticDays({required LocalDate today, int count = 190}) {
  return <AnalysisDay>[
    for (var i = count - 1; i >= 0; i--) _syntheticDay(today.addDays(-i), i),
  ];
}

AnalysisDay _syntheticDay(LocalDate date, int i) {
  final waterEntries = i % 4 == 1 ? 0 : 1 + i % 3;
  final meals = i % 2 == 0 ? 2 : 0;
  return AnalysisDay(
    date: date,
    stepsRecorded: i % 5 == 3
        ? null
        : (i % 7 == 0 ? 0 : 3000 + (i * 733) % 9000),
    waterMl: waterEntries == 0 ? 0 : 500 + (i * 211) % 2200,
    waterEntries: waterEntries,
    weightGrams: i % 3 == 0 ? 72000 - (i * 13) % 1500 : null,
    workoutEntries: i % 6 == 0 ? 1 + i % 2 : 0,
    workoutMinutes: i % 6 == 0 ? 30 + (i % 4) * 15 : 0,
    focusCompletedSeconds: i % 4 == 2 ? 1500 + (i % 3) * 600 : 0,
    focusCompletedSessions: i % 4 == 2 ? 1 : 0,
    tasksCompleted: i % 3,
    mealEntries: meals,
    mealsWithKcal: i % 5 == 0 ? 0 : meals,
    knownKcal: i % 5 == 0 ? 0 : meals * 450,
    applicableGoals: 5,
    fulfilledGoals: i % 6,
    applicableHabits: 2,
    fulfilledHabits: i % 3,
  );
}
