import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/database/reactive.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/steps/data/steps_repository.dart';
import 'package:self_improvement/features/body/steps/domain/step_day.dart';
import 'package:self_improvement/shared/local_date.dart';

final stepsRepositoryProvider = Provider<StepsRepository>(
  (ref) => StepsRepository(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
    snapshots: ref.watch(goalSnapshotServiceProvider),
  ),
);

/// The step total of one date, or null ("Keine Angabe").
final stepDayProvider = StreamProvider.family<StepDay?, LocalDate>(
  (ref, date) => ref.watch(stepsRepositoryProvider).watchDay(date),
);

/// One day of the steps history.
@immutable
final class StepsHistoryDay {
  const StepsHistoryDay({
    required this.date,
    required this.progress,
    required this.recorded,
  });

  final LocalDate date;

  /// Steps of the day (0 when [recorded] is false) with that day's target.
  final StepsProgress progress;

  /// False means "Nicht erfasst" (no record), which is not the same as 0.
  final bool recorded;

  int? get steps => recorded ? progress.steps : null;
}

/// State of today's steps card.
@immutable
final class StepsToday {
  const StepsToday({
    required this.date,
    required this.progress,
    required this.recorded,
  });

  final LocalDate date;
  final StepsProgress progress;

  /// False before any total was entered for today.
  final bool recorded;
}

/// Today's total with the target applying today (frozen in today's snapshot).
final stepsTodayProvider = StreamProvider<StepsToday>((ref) {
  final today = ref.watch(todayProvider);
  final database = ref.watch(appDatabaseProvider);
  final repository = ref.watch(stepsRepositoryProvider);
  final snapshots = ref.watch(goalSnapshotServiceProvider);
  return watchComputed(
    database,
    [
      database.stepDays,
      database.dailyGoalSnapshots,
      database.goalVersions,
      database.moduleStatusHistory,
      database.profile,
    ],
    () async {
      await snapshots.ensureForDays([today]);
      final day = await repository.findDay(today);
      final snapshot = await snapshots.snapshotFor(today);
      return StepsToday(
        date: today,
        recorded: day != null,
        progress: StepsProgress(
          steps: day?.steps ?? 0,
          target: snapshot?.applicableTargetFor(GoalType.steps.key),
        ),
      );
    },
  );
});

/// The last [days] local days ending today, newest first. Every day carries the
/// target that applied THEN (snapshot) so "reached" never changes retroactively.
final stepsHistoryProvider = StreamProvider.family<List<StepsHistoryDay>, int>((
  ref,
  days,
) {
  final today = ref.watch(todayProvider);
  final database = ref.watch(appDatabaseProvider);
  final repository = ref.watch(stepsRepositoryProvider);
  final snapshots = ref.watch(goalSnapshotServiceProvider);
  return watchComputed(
    database,
    [
      database.stepDays,
      database.dailyGoalSnapshots,
      database.goalVersions,
      database.moduleStatusHistory,
      database.profile,
    ],
    () async {
      final from = today.addDays(-(days - 1));
      await snapshots.ensureThrough(today);
      final stored = await snapshots.snapshotsBetween(from, today);
      final all = await repository.watchAll().first;
      final byDate = {for (final day in all) day.date: day};
      return [
        for (var offset = 0; offset < days; offset++)
          () {
            final date = today.addDays(-offset);
            final day = byDate[date];
            return StepsHistoryDay(
              date: date,
              recorded: day != null,
              progress: StepsProgress(
                steps: day?.steps ?? 0,
                target: stored[date]?.applicableTargetFor(GoalType.steps.key),
              ),
            );
          }(),
      ];
    },
  );
});

/// Chart periods of the steps overview in days.
const List<int> stepsPeriods = [7, 30, 90];

/// Selected chart period in days (7, 30 or 90).
final stepsPeriodProvider = NotifierProvider<StepsPeriodNotifier, int>(
  StepsPeriodNotifier.new,
);

class StepsPeriodNotifier extends Notifier<int> {
  @override
  int build() => stepsPeriods.first;

  void select(int days) {
    assert(stepsPeriods.contains(days), 'unsupported period');
    state = days;
  }
}
