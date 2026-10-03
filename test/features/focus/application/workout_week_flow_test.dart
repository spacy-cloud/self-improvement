import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/data/day_facts_source.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/manual_tick_source.dart';

/// Acceptance flows AT20 and AT23 for workouts with the REAL projection (XP
/// and goal snapshots) and the week providers.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late ProviderContainer container;

  // Saturday 2026-10-03 (the week is Monday 09-28 to Sunday 10-04).
  final today = LocalDate(2026, 10, 3);

  setUp(() async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    container = harness.createContainer();
    container.listen(workoutWeekSummaryProvider, (_, _) {});
  });
  tearDown(() => harness.dispose());

  /// The current summary, after the streams had time to deliver.
  Future<WorkoutWeekSummary> summary() async {
    await container.read(workoutWeekEntriesProvider.future);
    await container.read(goalVersionsProvider.future);
    await settle();
    return container.read(workoutWeekSummaryProvider).requireValue;
  }

  Future<String> log({
    DateTime? when,
    int minutes = 45,
    TrainingCategory category = TrainingCategory.strength,
    String? title,
  }) async {
    final outcome = await container
        .read(workoutRepositoryProvider)
        .create(
          commandId: harness.ids.newId(),
          draft: WorkoutDraft(
            category: category,
            durationMinutes: minutes,
            occurredAtUtc: when ?? DateTime.utc(2026, 10, 3, 7),
            title: title,
          ),
        );
    return outcome.entityId!;
  }

  Future<void> move(String id, DateTime when) async {
    final repository = container.read(workoutRepositoryProvider);
    final entry = (await repository.findById(id))!;
    await repository.update(
      commandId: harness.ids.newId(),
      id: id,
      draft: WorkoutDraft(
        category: entry.category,
        durationMinutes: entry.durationMinutes,
        occurredAtUtc: when,
      ),
      expectedRowVersion: entry.rowVersion,
    );
  }

  Future<List<XpAwardRow>> awards() =>
      harness.database.select(harness.database.xpAwards).get();

  Future<int> focusSecondsOn(LocalDate day) async =>
      (await DayFactsSource(harness.database).factsFor(day))
          .focusCompletedSeconds;

  group('AT20: logging a workout', () {
    test('without a workout the week shows the honest empty state', () async {
      final result = await summary();
      expect(result.isEmpty, isTrue);
      expect(result.entryCount, 0);
      expect(result.totalMinutes, 0);
      expect(result.weeklyTarget, 3, reason: 'default 3 per week');
      expect(result.ringFraction, 0.0);
      expect(result.latest, isNull);
      expect(result.latestText, 'Noch kein Workout diese Woche');
      expect(result.weekStart, LocalDate(2026, 9, 28));
    });

    test(
      'count, minutes, ring and latest workout follow every entry',
      () async {
        await log(
          when: DateTime.utc(2026, 9, 29, 6),
          minutes: 30,
          category: TrainingCategory.cardio,
        );
        var result = await summary();
        expect(result.entryCount, 1);
        expect(result.totalMinutes, 30);
        expect(result.ringFraction, closeTo(1 / 3, 1e-9));
        expect(result.latestText, 'Cardio');

        await log(
          when: DateTime.utc(2026, 10, 1, 17),
          minutes: 60,
          title: 'Beine',
        );
        result = await summary();
        expect(result.entryCount, 2);
        expect(result.totalMinutes, 90);
        expect(result.ringFraction, closeTo(2 / 3, 1e-9));
        expect(result.latestText, 'Beine');

        await log(minutes: 45);
        result = await summary();
        expect(result.entryCount, 3);
        expect(result.totalMinutes, 135);
        expect(result.ringFraction, 1.0);
        expect(result.targetReached, isTrue);
      },
    );

    test(
      'the ring is capped at 100 percent while the real count stays',
      () async {
        for (var i = 0; i < 5; i++) {
          await log(
            when: DateTime.utc(2026, 9, 28 + (i % 6), i + 1),
            minutes: 20,
          );
        }
        final result = await summary();
        expect(result.entryCount, 5);
        expect(result.totalMinutes, 100);
        expect(result.ringFraction, 1.0);
        expect(result.remainingToTarget, 0);
      },
    );

    test('only the current Monday-to-Sunday week counts', () async {
      await log(when: DateTime.utc(2026, 9, 27, 10)); // Sunday of last week
      await log(when: DateTime.utc(2026, 9, 28, 10)); // Monday
      final result = await summary();
      expect(result.entryCount, 1);
      expect(result.latest!.localDate, LocalDate(2026, 9, 28));
    });

    test('earns 15 XP once per day, another day earns again', () async {
      await log(when: DateTime.utc(2026, 10, 3, 6));
      expect(await harness.totalXp(), 15);
      await log(when: DateTime.utc(2026, 10, 3, 7));
      await log(when: DateTime.utc(2026, 10, 3, 8));
      expect(await harness.totalXp(), 15, reason: 'once per day');
      await log(when: DateTime.utc(2026, 10, 2, 7));
      expect(await harness.totalXp(), 30);
      final keys = (await awards()).map((a) => a.awardKey).toList()..sort();
      expect(keys, ['workout:2026-10-02', 'workout:2026-10-03']);
    });

    test('a workout is not part of the day ring or the daily goals', () async {
      await log();
      final status = (await harness.dayStatusRepository().statusFor(today))!;
      expect(
        status.goals.map((g) => g.goalKey),
        isNot(contains(GoalType.workoutWeekly.key)),
      );
    });

    test('workouts do not count as focus time and focus time is no workout (no double counting)', () async {
      await log(minutes: 120);
      expect(await focusSecondsOn(today), 0);

      final ticker = ManualTickSource();
      final focusContainer = harness.createContainer(
        overrides: [focusTickSourceProvider.overrideWithValue(ticker)],
      );
      final focus = focusContainer.read(focusRepositoryProvider);
      final started = await focus.start(
        commandId: harness.ids.newId(),
        category: FocusCategory.learning,
        plannedSeconds: 1800,
      );
      harness.clock.advance(const Duration(minutes: 30));
      await focus.save(commandId: harness.ids.newId(), id: started.entityId!);

      expect(await focusSecondsOn(today), 1800, reason: 'only the session');
      final result = await summary();
      expect(result.entryCount, 1, reason: 'the focus session is no workout');
      expect(result.totalMinutes, 120);
      final focusStatus = (await harness.dayStatusRepository().statusFor(
        today,
      ))!.goals.singleWhere((g) => g.goalKey == GoalType.focusMinutes.key);
      expect(
        focusStatus.current,
        30,
        reason: '120 workout minutes add nothing',
      );
    });
  });

  group('AT23: correcting the past', () {
    test(
      'moving a workout into the previous week moves count and XP',
      () async {
        final id = await log(when: DateTime.utc(2026, 10, 3, 7));
        expect((await summary()).entryCount, 1);
        expect((await awards()).single.awardKey, 'workout:2026-10-03');

        await move(id, DateTime.utc(2026, 9, 27, 7)); // Sunday, last week
        expect((await summary()).entryCount, 0);
        expect((await awards()).single.awardKey, 'workout:2026-09-27');
        expect(await harness.totalXp(), 15, reason: 'no double award');

        await move(id, DateTime.utc(2026, 9, 28, 7)); // Monday, this week
        final result = await summary();
        expect(result.entryCount, 1);
        expect(result.latest!.id, id);
        expect((await awards()).single.awardKey, 'workout:2026-09-28');
      },
    );

    test('moving the Sunday workout to Monday changes the week', () async {
      harness.clock.setNow(DateTime.utc(2026, 10, 6, 12));
      container.read(todayProvider.notifier).refresh();
      final id = await log(when: DateTime.utc(2026, 10, 4, 10)); // Sunday
      final newWeek = await summary();
      expect(newWeek.weekStart, LocalDate(2026, 10, 5));
      expect(
        newWeek.entryCount,
        0,
        reason: 'Sunday belongs to the week before',
      );

      await move(id, DateTime.utc(2026, 10, 5, 10)); // Monday
      expect((await summary()).entryCount, 1);
      expect((await awards()).single.awardKey, 'workout:2026-10-05');
    });

    test(
      'a second entry on the old day keeps the old award when the first moves',
      () async {
        final first = await log(when: DateTime.utc(2026, 10, 3, 6));
        await log(when: DateTime.utc(2026, 10, 3, 7));
        expect(await harness.totalXp(), 15);
        await move(first, DateTime.utc(2026, 10, 2, 6));
        expect((await awards()).map((a) => a.awardKey).toList()..sort(), [
          'workout:2026-10-02',
          'workout:2026-10-03',
        ]);
        expect(await harness.totalXp(), 30);
      },
    );

    test('deleting takes the XP back, the next entry of the day moves up, undo restores', () async {
      final a = await log(when: DateTime.utc(2026, 10, 3, 6));
      final b = await log(when: DateTime.utc(2026, 10, 3, 7));
      final repository = container.read(workoutRepositoryProvider);
      await repository.delete(commandId: harness.ids.newId(), id: a);
      expect(await harness.totalXp(), 15, reason: 'the second entry qualifies');
      final deleted = await repository.delete(
        commandId: harness.ids.newId(),
        id: b,
      );
      expect(await harness.totalXp(), 0);
      expect((await summary()).entryCount, 0);
      await deleted.undo!.run(harness.ids.newId());
      expect(await harness.totalXp(), 15);
      expect((await summary()).entryCount, 1);
    });

    test('the week summary follows an undo of an edit', () async {
      final id = await log(when: DateTime.utc(2026, 10, 3, 7), minutes: 45);
      final repository = container.read(workoutRepositoryProvider);
      final entry = (await repository.findById(id))!;
      final edited = await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: WorkoutDraft(
          category: TrainingCategory.cardio,
          durationMinutes: 90,
          occurredAtUtc: entry.occurredAtUtc,
          muscleGroups: const [MuscleGroup.legs],
        ),
        expectedRowVersion: entry.rowVersion,
      );
      expect((await summary()).totalMinutes, 90);
      await edited.undo!.run(harness.ids.newId());
      expect((await summary()).totalMinutes, 45);
    });
  });

  group('the week follows the calendar', () {
    test(
      'a new Monday starts an empty week, all workouts stay in the list',
      () async {
        harness.clock.setNow(DateTime.utc(2026, 10, 4, 18)); // Sunday evening
        container.read(todayProvider.notifier).refresh();
        await log(when: DateTime.utc(2026, 10, 4, 17));
        expect((await summary()).entryCount, 1);

        harness.clock.setNow(DateTime.utc(2026, 10, 5, 6)); // Monday morning
        container.read(todayProvider.notifier).refresh();
        final monday = await summary();
        expect(monday.weekStart, LocalDate(2026, 10, 5));
        expect(monday.entryCount, 0);
        expect(monday.latestText, 'Noch kein Workout diese Woche');
        container.listen(workoutEntriesProvider, (_, _) {});
        expect(
          await container.read(workoutEntriesProvider.future),
          hasLength(1),
        );
      },
    );

    test(
      'around the end of summer time the frozen local date decides the week',
      () async {
        // Berlin: summer time ends on Sunday 2026-10-25 at 01:00Z.
        harness.clock.setNow(DateTime.utc(2026, 10, 26, 12));
        container.read(todayProvider.notifier).refresh();
        final lastNight = await log(when: DateTime.utc(2026, 10, 24, 22, 30));
        final afterwards = await log(when: DateTime.utc(2026, 10, 25, 23, 30));
        final repository = container.read(workoutRepositoryProvider);
        expect(
          (await repository.findById(lastNight))!.localDate,
          LocalDate(2026, 10, 25),
          reason: '00:30 CEST on Sunday',
        );
        expect(
          (await repository.findById(afterwards))!.localDate,
          LocalDate(2026, 10, 26),
          reason: '00:30 CET on Monday',
        );
        // Today is Monday 10-26: only the Monday workout is in the week.
        final result = await summary();
        expect(result.weekStart, LocalDate(2026, 10, 26));
        expect(result.entryCount, 1);
        expect(result.latest!.id, afterwards);
      },
    );

    test(
      'a later time zone change does not move the week of existing workouts',
      () async {
        final id = await log(when: DateTime.utc(2026, 10, 3, 7));
        harness.clock.setTimeZone('Pacific/Auckland');
        expect(
          (await container.read(workoutRepositoryProvider).findById(id))!
              .localDate,
          today,
        );
      },
    );
  });

  group('the weekly target (goal version in effect)', () {
    test(
      'a changed target applies from tomorrow and then drives the ring',
      () async {
        await log(when: DateTime.utc(2026, 10, 3, 7));
        expect((await summary()).weeklyTarget, 3);
        await container
            .read(goalsCommandsProvider)
            .update(
              commandId: harness.ids.newId(),
              changes: {GoalType.workoutWeekly: const GoalSetting(target: 5)},
            );
        var result = await summary();
        expect(result.weeklyTarget, 3, reason: 'edits take effect tomorrow');
        expect(result.ringFraction, closeTo(1 / 3, 1e-9));

        harness.clock.setNow(DateTime.utc(2026, 10, 4, 8));
        container.read(todayProvider.notifier).refresh();
        result = await summary();
        expect(result.weeklyTarget, 5);
        expect(result.entryCount, 1, reason: 'Sunday is still the same week');
        expect(result.ringFraction, closeTo(1 / 5, 1e-9));
      },
    );

    test('a stored version for today is used immediately', () async {
      await harness.database
          .into(harness.database.goalVersions)
          .insert(
            GoalVersionsCompanion.insert(
              id: harness.ids.newId(),
              goalType: GoalType.workoutWeekly.key,
              targetInteger: const Value(14),
              enabled: true,
              effectiveFromDate: today,
              createdAtUtc: harness.clock.nowUtc(),
            ),
          );
      expect((await summary()).weeklyTarget, 14);
    });
  });
}
