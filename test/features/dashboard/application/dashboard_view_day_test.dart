import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/dashboard/application/dashboard_providers.dart';
import 'package:self_improvement/features/dashboard/application/day_browser_providers.dart';
import 'package:self_improvement/features/dashboard/application/goals_today_providers.dart';
import 'package:self_improvement/features/dashboard/domain/goals_day.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The model of Home for the day that is shown (BS-93), over the real database
/// and the real projection: the status of THAT day (the snapshot of that day
/// and the facts of that day), the goals that counted then, and the page "Ziele
/// heute" built from it.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late ProviderContainer container;

  // Saturday, 3 October 2026, 10:00 in Berlin.
  final today = LocalDate(2026, 10, 3);
  final day = LocalDate(2026, 10, 1);

  Future<void> start({bool workoutGoal = false}) async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(
      startedOn: LocalDate(2026, 9, 1),
      workoutDailyGoal: workoutGoal,
    );
    container = harness.createContainer();
  }

  tearDown(() => harness.dispose());

  Future<DashboardView> view() async {
    // Wait until the view is complete: the streams answer one after the other.
    final completer = Completer<DashboardView>();
    final subscription = container.listen<AsyncValue<DashboardView>>(
      dashboardViewProvider,
      (_, next) {
        if (next.hasValue && !completer.isCompleted) {
          completer.complete(next.requireValue);
        }
      },
      fireImmediately: true,
    );
    final model = await completer.future;
    subscription.close();
    return model;
  }

  /// The status of [on], read with a listener: Riverpod pauses a provider that
  /// nobody listens to, so a plain read would wait for ever.
  Future<DayStatus?> statusOf(LocalDate on) async {
    final subscription = container.listen<AsyncValue<DayStatus?>>(
      dayStatusProvider(on),
      (_, _) {},
    );
    addTearDown(subscription.close);
    return container.read(dayStatusProvider(on).future);
  }

  Future<DayStatus?> liveStatus() async {
    final subscription = container.listen<AsyncValue<DayStatus?>>(
      todayStatusProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    return container.read(todayStatusProvider.future);
  }

  /// Water for [on] in entries of at most 2000 ml (the limit of one entry).
  Future<void> addWater(LocalDate on, int ml, {int hour = 1}) async {
    var left = ml;
    var at = hour;
    while (left > 0) {
      final part = left > 2000 ? 2000 : left;
      await container
          .read(waterRepositoryProvider)
          .create(
            commandId: harness.ids.newId(),
            draft: WaterDraft(
              amountMl: part,
              occurredAtUtc: DateTime.utc(on.year, on.month, on.day, at++),
            ),
          );
      left -= part;
    }
  }

  group('the status of the day shown (BS-93, C04)', () {
    test('(BS-93, C04) today: the model carries the status of today, from the '
        'stream everyone reads', () async {
      await start();
      await addWater(today, 1000);
      final model = await view();
      expect(model.day.isToday, isTrue);
      expect(model.dayStatus!.date, today);
      expect(model.dayStatus!.progressOf(GoalType.water)!.current, 1000);
      expect(model.today, today);
    });

    test('(BS-93, C04) a day before today: the model carries the status of '
        'that day and the facts of that day', () async {
      await start();
      await addWater(today, 1000);
      await addWater(day, 2600);
      container.read(selectedDayProvider.notifier).select(day);
      final model = await view();
      expect(model.day.date, day);
      expect(model.day.isToday, isFalse);
      expect(model.today, today, reason: 'today is still today');
      final status = model.dayStatus!;
      expect(status.date, day);
      final water = status.progressOf(GoalType.water)!;
      expect(water.current, 2600);
      expect(water.target, 2500);
      expect(water.fulfilled, isTrue);
      expect(status.fulfilledCount, 1);
      expect(status.applicableCount, 5);
    });

    test(
      '(BS-93, C04) the status follows a record made for that day',
      () async {
        await start();
        container.read(selectedDayProvider.notifier).select(day);
        final subscription = container.listen<AsyncValue<DashboardView>>(
          dashboardViewProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);
        var model = await view();
        expect(model.dayStatus!.fulfilledCount, 0);
        await addWater(day, 2500);
        // The streams deliver on the next turns of the event loop.
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          model = container.read(dashboardViewProvider).requireValue;
          if (model.dayStatus!.fulfilledCount == 1) {
            break;
          }
        }
        expect(model.dayStatus!.fulfilledCount, 1);
      },
    );

    test('(BS-93) the numbers are those of the status stream of the day: the '
        'ring cannot disagree with it', () async {
      await start();
      await addWater(day, 1200);
      container.read(selectedDayProvider.notifier).select(day);
      final model = await view();
      final direct = (await statusOf(day))!;
      expect(model.dayStatus!.fulfilledCount, direct.fulfilledCount);
      expect(model.dayStatus!.applicableCount, direct.applicableCount);
      expect(
        model.dayStatus!.progressOf(GoalType.water)!.current,
        direct.progressOf(GoalType.water)!.current,
      );
    });

    test('(BS-93) the status of today and the status of the same day read '
        'as a day agree', () async {
      await start();
      await addWater(today, 1700);
      final live = await liveStatus();
      final asDay = await statusOf(today);
      expect(asDay!.fulfilledCount, live!.fulfilledCount);
      expect(asDay.progressOf(GoalType.water)!.current, 1700);
    });
  });

  group('the goals the day had (BS-93, AT24, C04)', () {
    test('(BS-93, AT24, C04) a goal changed from tomorrow does not change the '
        'day before: its status keeps the old target', () async {
      await start();
      await addWater(today, 2600);
      await container
          .read(goalsCommandsProvider)
          .update(
            commandId: harness.ids.newId(),
            changes: <GoalType, GoalSetting>{
              GoalType.water: const GoalSetting(target: 3000),
            },
          );
      // The next morning.
      harness.clock.advance(const Duration(days: 1));
      container.read(todayProvider.notifier).refresh();
      final tomorrow = container.read(todayProvider);
      expect(tomorrow, LocalDate(2026, 10, 4));

      final yesterday = await statusOf(today);
      final water = yesterday!.progressOf(GoalType.water)!;
      expect(water.target, 2500, reason: 'the goal of that day');
      expect(water.fulfilled, isTrue);

      final live = await statusOf(tomorrow);
      expect(live!.progressOf(GoalType.water)!.target, 3000);
      expect(live.progressOf(GoalType.water)!.fulfilled, isFalse);
    });

    test('(BS-93, AT24) a goal switched off from tomorrow still counts on the '
        'day before', () async {
      await start();
      await container
          .read(goalsCommandsProvider)
          .update(
            commandId: harness.ids.newId(),
            changes: <GoalType, GoalSetting>{
              GoalType.steps: const GoalSetting(enabled: false),
            },
          );
      harness.clock.advance(const Duration(days: 1));
      container.read(todayProvider.notifier).refresh();
      final before = await statusOf(today);
      final after = await statusOf(container.read(todayProvider));
      expect(before!.applicableCount, 5);
      expect(after!.applicableCount, 4);
      expect(before.progressOf(GoalType.steps)!.applicable, isTrue);
      expect(after.progressOf(GoalType.steps)!.applicable, isFalse);
    });

    test('(BS-93) a day before the profile started has no status', () async {
      await start();
      final status = await statusOf(LocalDate(2026, 8, 31));
      expect(status, isNull);
    });
  });

  group('"Ziele heute" for the day (BS-93, BS-100)', () {
    Future<GoalsDay> page() async {
      final completer = Completer<GoalsDay>();
      final subscription = container.listen<AsyncValue<GoalsDay>>(
        goalsTodayProvider,
        (_, next) {
          if (next.hasValue && !completer.isCompleted) {
            completer.complete(next.requireValue);
          }
        },
        fireImmediately: true,
      );
      final model = await completer.future;
      subscription.close();
      return model;
    }

    test('(BS-93) today is today: the weekly goal may be shown', () async {
      await start();
      await addWater(today, 500);
      final model = await page();
      expect(model.isToday, isTrue);
      expect(model.date, today);
    });

    test('(BS-93) a day before today is "vergangener Tag": no weekly goal, the '
        'words of the past, the numbers of that day', () async {
      await start();
      await addWater(day, 2600);
      container.read(selectedDayProvider.notifier).select(day);
      final model = await page();
      expect(model.isToday, isFalse);
      expect(model.date, day);
      expect(model.weekly, isNull);
      expect(model.fulfilled, 1);
      expect(model.applicable, 5);
      final water = model.rows.firstWhere((row) => row.type == GoalType.water);
      expect(water.detail, '2,6 von 2,5 l · 104 %');
      expect(water.isReached, isTrue);
      expect(
        model.rows.firstWhere((row) => row.type == GoalType.weightEntry).detail,
        'Nicht gewogen',
      );
    });

    test('(BS-93, BS-99) "Workout heute" of a day before today is answered by '
        'the workout or the mark of THAT day', () async {
      await start(workoutGoal: true);
      final twoDaysAgo = LocalDate(2026, 10, 1);
      final yesterday = LocalDate(2026, 10, 2);
      await container
          .read(workoutDayMarkRepositoryProvider)
          .mark(
            commandId: harness.ids.newId(),
            kind: WorkoutDayMarkKind.rest,
            date: twoDaysAgo,
          );
      await container
          .read(workoutRepositoryProvider)
          .create(
            commandId: harness.ids.newId(),
            draft: WorkoutDraft(
              category: TrainingCategory.strength,
              durationMinutes: 45,
              occurredAtUtc: DateTime.utc(2026, 10, 2, 8),
            ),
          );
      container.read(selectedDayProvider.notifier).select(twoDaysAgo);
      var model = await page();
      var row = model.rows.firstWhere((r) => r.type == GoalType.workoutDaily);
      expect(row.status, GoalRowStatus.rest);

      container.read(selectedDayProvider.notifier).select(yesterday);
      model = await page();
      row = model.rows.firstWhere((r) => r.type == GoalType.workoutDaily);
      expect(model.date, yesterday);
      expect(row.status, GoalRowStatus.reached);
      expect(row.detail, '1 Training eingetragen');
    });

    test('(BS-93) the ring of the page and the ring of Home count the same '
        'object', () async {
      await start();
      await addWater(day, 2600);
      container.read(selectedDayProvider.notifier).select(day);
      final model = await page();
      final home = await view();
      expect(model.fulfilled, home.dayStatus!.fulfilledCount);
      expect(model.applicable, home.dayStatus!.applicableCount);
    });
  });
}
