import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/day_snapshot.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/goals/domain/goal_keys.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  final day = LocalDate(2026, 10, 3);

  GoalSnapshotItem goal(GoalType type, {int? target, bool applicable = true}) =>
      GoalSnapshotItem(
        goalKey: type.key,
        module: type.module,
        target: target ?? type.defaultTarget,
        applicable: applicable,
      );

  GoalSnapshotItem habit(String id, {bool applicable = true}) =>
      GoalSnapshotItem(
        goalKey: habitGoalKey(id),
        module: ModuleId.tasks,
        target: null,
        applicable: applicable,
      );

  DaySnapshot snapshotOf(List<GoalSnapshotItem> items) =>
      DaySnapshot(date: day, items: items);

  DayStatus statusOf(List<GoalSnapshotItem> items, DayFacts facts) =>
      computeDayStatus(snapshotOf(items), facts);

  /// Status of a snapshot that only has [item], evaluated against [facts].
  GoalProgress progress(GoalSnapshotItem item, DayFacts facts) {
    final status = statusOf([item], facts);
    expect(status.goals, hasLength(1));
    return status.goals.single;
  }

  group('fulfilment at the boundaries', () {
    test('water: sum of entries must reach the target', () {
      final item = goal(GoalType.water, target: 2500);
      for (final (ml, fulfilled) in [
        (0, false),
        (50, false),
        (2499, false),
        (2500, true),
        (2501, true),
        (10000, true),
      ]) {
        final result = progress(item, DayFacts(date: day, waterMl: ml));
        expect(result.fulfilled, fulfilled, reason: '$ml ml');
        expect(result.current, ml);
        expect(result.target, 2500);
      }
    });

    test('water: the smallest target is reached with 250 ml', () {
      final item = goal(GoalType.water, target: 250);
      expect(
        progress(item, DayFacts(date: day, waterMl: 249)).fulfilled,
        isFalse,
      );
      expect(
        progress(item, DayFacts(date: day, waterMl: 250)).fulfilled,
        isTrue,
      );
    });

    test('steps: a recorded value must reach the target', () {
      final item = goal(GoalType.steps, target: 10000);
      for (final (steps, fulfilled) in [
        (9999, false),
        (10000, true),
        (10001, true),
        (100000, true),
      ]) {
        final result = progress(
          item,
          DayFacts(date: day, stepsRecorded: steps),
        );
        expect(result.fulfilled, fulfilled, reason: '$steps steps');
        expect(result.current, steps);
      }
    });

    test('steps: a recorded zero is a value, no record is not', () {
      final item = goal(GoalType.steps, target: 100);
      final zero = progress(item, DayFacts(date: day, stepsRecorded: 0));
      expect(zero.current, 0, reason: 'recorded zero stays visible as 0');
      expect(zero.fulfilled, isFalse);
      final none = progress(item, DayFacts(date: day));
      expect(none.current, isNull, reason: 'no record is "no entry"');
      expect(none.fulfilled, isFalse);
    });

    test('weight entry: at least one entry', () {
      final item = goal(GoalType.weightEntry);
      expect(progress(item, DayFacts(date: day)).fulfilled, isFalse);
      expect(
        progress(item, DayFacts(date: day, weightEntries: 1)).fulfilled,
        isTrue,
      );
      expect(
        progress(item, DayFacts(date: day, weightEntries: 2)).fulfilled,
        isTrue,
      );
      expect(progress(item, DayFacts(date: day, weightEntries: 1)).target, 1);
    });

    test('focus: completed seconds must reach target minutes times 60', () {
      final item = goal(GoalType.focusMinutes, target: 25);
      for (final (seconds, fulfilled, minutes) in [
        (0, false, 0),
        (1439, false, 23),
        (1499, false, 24),
        (1500, true, 25),
        (1501, true, 25),
        (3600, true, 60),
      ]) {
        final result = progress(
          item,
          DayFacts(date: day, focusCompletedSeconds: seconds),
        );
        expect(result.fulfilled, fulfilled, reason: '$seconds s');
        expect(result.current, minutes, reason: 'whole minutes of $seconds s');
      }
    });

    test('focus: smallest and largest targets', () {
      final small = goal(GoalType.focusMinutes, target: 5);
      expect(
        progress(
          small,
          DayFacts(date: day, focusCompletedSeconds: 299),
        ).fulfilled,
        isFalse,
      );
      expect(
        progress(
          small,
          DayFacts(date: day, focusCompletedSeconds: 300),
        ).fulfilled,
        isTrue,
      );
      final large = goal(GoalType.focusMinutes, target: 180);
      expect(
        progress(
          large,
          DayFacts(date: day, focusCompletedSeconds: 10799),
        ).fulfilled,
        isFalse,
      );
      expect(
        progress(
          large,
          DayFacts(date: day, focusCompletedSeconds: 10800),
        ).fulfilled,
        isTrue,
      );
    });

    test('task completion: at least one completed task', () {
      final item = goal(GoalType.taskCompletion);
      expect(progress(item, DayFacts(date: day)).fulfilled, isFalse);
      expect(
        progress(item, DayFacts(date: day, tasksCompleted: 1)).fulfilled,
        isTrue,
      );
      expect(
        progress(item, DayFacts(date: day, tasksCompleted: 4)).fulfilled,
        isTrue,
      );
    });

    test('habit: fulfilled only when this habit is checked', () {
      final item = habit('h1');
      final unchecked = progress(item, DayFacts(date: day));
      expect(unchecked.fulfilled, isFalse);
      expect(unchecked.current, 0);
      expect(unchecked.target, isNull);
      expect(unchecked.module, ModuleId.tasks);
      final otherChecked = progress(
        item,
        DayFacts(date: day, habitIdsChecked: const {'h2'}),
      );
      expect(otherChecked.fulfilled, isFalse);
      final checked = progress(
        item,
        DayFacts(date: day, habitIdsChecked: const {'h1', 'h2'}),
      );
      expect(checked.fulfilled, isTrue);
      expect(checked.current, 1);
    });

    test('the frozen snapshot threshold is used, not the default', () {
      final item = goal(GoalType.water, target: 2000);
      expect(
        progress(item, DayFacts(date: day, waterMl: 2000)).fulfilled,
        isTrue,
      );
      final stricter = goal(GoalType.water, target: 3000);
      expect(
        progress(stricter, DayFacts(date: day, waterMl: 2500)).fulfilled,
        isFalse,
      );
    });

    test('switch goals use the fixed threshold even without a stored one', () {
      final item = GoalSnapshotItem(
        goalKey: GoalType.taskCompletion.key,
        module: ModuleId.tasks,
        target: null,
        applicable: true,
      );
      final result = progress(item, DayFacts(date: day, tasksCompleted: 1));
      expect(result.fulfilled, isTrue);
      expect(result.target, 1);
    });
  });

  group('goals that are not applicable', () {
    test('never count, however much was done', () {
      final facts = DayFacts(
        date: day,
        waterMl: 99999,
        stepsRecorded: 999999,
        weightEntries: 5,
        focusCompletedSeconds: 99999,
        tasksCompleted: 9,
        habitIdsChecked: const {'h1'},
      );
      final status = statusOf([
        for (final type in GoalType.dailyTypes) goal(type, applicable: false),
        habit('h1', applicable: false),
      ], facts);
      expect(status.goals, hasLength(6));
      expect(status.goals.where((g) => g.fulfilled), isEmpty);
      expect(status.applicableCount, 0);
      expect(status.fulfilledCount, 0);
      expect(status.isActive, isFalse);
      expect(status.isComplete, isFalse);
    });

    test('are excluded from the ring but still show their value', () {
      final status = statusOf([
        goal(GoalType.water, target: 2000),
        goal(GoalType.steps, applicable: false),
      ], DayFacts(date: day, waterMl: 2000, stepsRecorded: 12000));
      expect(status.applicableCount, 1);
      expect(status.fulfilledCount, 1);
      expect(status.ringFraction, 1.0);
      expect(status.goals.last.applicable, isFalse);
      expect(status.goals.last.fulfilled, isFalse);
      expect(status.goals.last.current, 12000);
    });
  });

  group('days without applicable goals', () {
    test('an empty snapshot is neither active nor complete', () {
      final status = statusOf(const [], DayFacts(date: day, waterMl: 5000));
      expect(status.goals, isEmpty);
      expect(status.applicableCount, 0);
      expect(status.fulfilledCount, 0);
      expect(status.isActive, isFalse, reason: 'no free streak extension');
      expect(status.isComplete, isFalse, reason: 'no free complete day');
      expect(status.hasApplicableGoals, isFalse);
      expect(status.ringFraction, isNull, reason: 'never a 0/0 ring');
    });

    test('goals that exist but are all switched off behave the same', () {
      final status = statusOf([
        goal(GoalType.water, applicable: false),
        goal(GoalType.taskCompletion, applicable: false),
      ], DayFacts(date: day, waterMl: 5000, tasksCompleted: 3));
      expect(status.isActive, isFalse);
      expect(status.isComplete, isFalse);
      expect(status.ringFraction, isNull);
    });
  });

  group('active day versus complete day', () {
    final threeGoals = [
      goal(GoalType.water, target: 2500),
      goal(GoalType.steps, target: 10000),
      goal(GoalType.weightEntry),
    ];

    test('no fulfilled goal: neither active nor complete, ring is 0', () {
      final status = statusOf(threeGoals, DayFacts(date: day, waterMl: 100));
      expect(status.applicableCount, 3);
      expect(status.fulfilledCount, 0);
      expect(status.isActive, isFalse);
      expect(status.isComplete, isFalse);
      expect(status.hasApplicableGoals, isTrue);
      expect(status.ringFraction, 0.0, reason: 'goals exist: a real 0 %');
    });

    test('one fulfilled goal makes the day active but not complete', () {
      final status = statusOf(
        threeGoals,
        DayFacts(date: day, weightEntries: 1),
      );
      expect(status.fulfilledCount, 1);
      expect(status.isActive, isTrue);
      expect(status.isComplete, isFalse);
      expect(status.ringFraction, closeTo(1 / 3, 1e-12));
    });

    test('two of three is still only active', () {
      final status = statusOf(
        threeGoals,
        DayFacts(date: day, waterMl: 2500, weightEntries: 1),
      );
      expect(status.isActive, isTrue);
      expect(status.isComplete, isFalse);
      expect(status.ringFraction, closeTo(2 / 3, 1e-12));
    });

    test('all fulfilled makes the day active and complete', () {
      final status = statusOf(
        threeGoals,
        DayFacts(
          date: day,
          waterMl: 2500,
          stepsRecorded: 10000,
          weightEntries: 1,
        ),
      );
      expect(status.isActive, isTrue);
      expect(status.isComplete, isTrue);
      expect(status.ringFraction, 1.0);
    });

    test(
      'a single applicable goal that is fulfilled is active and complete',
      () {
        final status = statusOf([
          goal(GoalType.taskCompletion),
        ], DayFacts(date: day, tasksCompleted: 2));
        expect(status.isActive, isTrue);
        expect(status.isComplete, isTrue);
      },
    );

    test('goals that are not applicable do not block a complete day', () {
      final status = statusOf([
        goal(GoalType.water, target: 2500),
        goal(GoalType.steps, applicable: false),
      ], DayFacts(date: day, waterMl: 2500));
      expect(status.applicableCount, 1);
      expect(status.isComplete, isTrue);
    });

    test('habits are goals of the ring like any other', () {
      final items = [goal(GoalType.water), habit('h1'), habit('h2')];
      final facts = DayFacts(date: day, habitIdsChecked: const {'h2'});
      final status = statusOf(items, facts);
      expect(status.applicableCount, 3);
      expect(status.fulfilledCount, 1);
      expect(status.isActive, isTrue);
      expect(status.isComplete, isFalse);
      expect(status.ringFraction, closeTo(1 / 3, 1e-12));
      final done = statusOf([
        habit('h1'),
      ], DayFacts(date: day, habitIdsChecked: const {'h1'}));
      expect(done.isComplete, isTrue);
    });

    test('counts add up for a realistic day', () {
      final items = [
        goal(GoalType.water, target: 2500),
        goal(GoalType.steps, target: 10000),
        goal(GoalType.weightEntry),
        goal(GoalType.focusMinutes, target: 25),
        goal(GoalType.taskCompletion),
        habit('h1'),
      ];
      final status = statusOf(
        items,
        DayFacts(
          date: day,
          waterMl: 1500,
          stepsRecorded: 7450,
          weightEntries: 1,
          focusCompletedSeconds: 1500,
          tasksCompleted: 0,
          habitIdsChecked: const {'h1'},
        ),
      );
      expect(status.applicableCount, 6);
      expect(status.fulfilledCount, 3);
      expect(status.ringFraction, 0.5);
      expect(
        [for (final g in status.goals) (g.goalKey, g.fulfilled)],
        [
          ('water', false),
          ('steps', false),
          ('weight_entry', true),
          ('focus_minutes', true),
          ('task_completion', false),
          ('habit:h1', true),
        ],
      );
    });
  });

  group('snapshot handling', () {
    test('goals keep the order of the snapshot items', () {
      final status = statusOf([
        goal(GoalType.taskCompletion),
        habit('b'),
        goal(GoalType.water),
        habit('a'),
      ], DayFacts(date: day));
      expect(status.goals.map((g) => g.goalKey), [
        'task_completion',
        'habit:b',
        'water',
        'habit:a',
      ]);
      expect(status.date, day);
    });

    test('items that are no daily goal are ignored', () {
      final status = statusOf([
        GoalSnapshotItem(
          goalKey: GoalType.workoutWeekly.key,
          module: ModuleId.focus,
          target: 3,
          applicable: true,
        ),
        const GoalSnapshotItem(
          goalKey: 'bogus',
          module: ModuleId.body,
          target: 1,
          applicable: true,
        ),
        goal(GoalType.water, target: 1000),
      ], DayFacts(date: day, waterMl: 1000));
      expect(status.goals.map((g) => g.goalKey), ['water']);
      expect(status.applicableCount, 1);
      expect(status.isComplete, isTrue);
    });

    test('the result cannot be modified afterwards', () {
      final status = statusOf([goal(GoalType.water)], DayFacts(date: day));
      expect(status.goals.clear, throwsUnsupportedError);
    });

    test('snapshot and facts of different days are rejected', () {
      expect(
        () => computeDayStatus(
          snapshotOf([goal(GoalType.water)]),
          DayFacts(date: day.addDays(1)),
        ),
        throwsAssertionError,
      );
    });
  });

  group('with the snapshot builder', () {
    test(
      'a module change masks the ring of today, reactivation restores it',
      () {
        final facts = DayFacts(date: day, waterMl: 2500, weightEntries: 1);
        DaySnapshot snapshotWith(bool Function(ModuleId module) enabled) =>
            buildDaySnapshot(
              day: day,
              profileStart: LocalDate(2026, 9, 1),
              versions: const [],
              isModuleEnabledOn: (module, _) => enabled(module),
              habits: const [],
            )!;

        final all = computeDayStatus(snapshotWith((m) => true), facts);
        expect(all.applicableCount, 5);
        expect(all.fulfilledCount, 2);

        final noNutrition = computeDayStatus(
          snapshotWith((m) => m != ModuleId.nutrition),
          facts,
        );
        expect(noNutrition.applicableCount, 4);
        expect(noNutrition.fulfilledCount, 1, reason: 'water is masked');

        final back = computeDayStatus(snapshotWith((m) => true), facts);
        expect(back.applicableCount, 5);
        expect(back.fulfilledCount, 2);

        final nothing = computeDayStatus(snapshotWith((m) => false), facts);
        expect(nothing.ringFraction, isNull);
        expect(nothing.isActive, isFalse);
      },
    );
  });
}
