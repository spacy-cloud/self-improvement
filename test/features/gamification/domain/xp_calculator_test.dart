import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/gamification/domain/xp_award.dart';
import 'package:self_improvement/features/gamification/domain/xp_calculator.dart';
import 'package:self_improvement/features/gamification/domain/xp_facts.dart';
import 'package:self_improvement/features/gamification/domain/xp_reconciliation.dart';
import 'package:self_improvement/features/gamification/domain/xp_rules.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  final profileStart = LocalDate(2026, 9, 1);
  final day = LocalDate(2026, 10, 3);
  final origin = DateTime.utc(2026, 10, 3, 6);

  /// An instant [minute] minutes after the origin (UTC, no calendar maths).
  DateTime at(int minute) => origin.add(Duration(minutes: minute));

  WaterXpFact water(
    String id, {
    int ml = 250,
    int minute = 0,
    int? created,
    bool eligible = true,
  }) => WaterXpFact(
    id: id,
    occurredAtUtc: at(minute),
    createdAtUtc: at(created ?? minute),
    eligible: eligible,
    amountMl: ml,
  );

  WeightXpFact weight(String id, {int minute = 0, bool eligible = true}) =>
      WeightXpFact(
        id: id,
        occurredAtUtc: at(minute),
        createdAtUtc: at(minute),
        eligible: eligible,
      );

  TaskXpFact task(
    String id, {
    int minute = 0,
    int? created,
    bool eligible = true,
  }) => TaskXpFact(
    id: id,
    occurredAtUtc: at(minute),
    createdAtUtc: at(created ?? minute),
    eligible: eligible,
  );

  FocusXpFact focus(
    String id, {
    int seconds = 1500,
    int minute = 0,
    int? created,
    bool eligible = true,
  }) => FocusXpFact(
    id: id,
    occurredAtUtc: at(minute),
    createdAtUtc: at(created ?? minute),
    eligible: eligible,
    accumulatedSeconds: seconds,
  );

  WorkoutXpFact workout(String id, {int minute = 0, bool eligible = true}) =>
      WorkoutXpFact(
        id: id,
        occurredAtUtc: at(minute),
        createdAtUtc: at(minute),
        eligible: eligible,
      );

  HabitCheckXpFact check(
    String id,
    String habitId, {
    int minute = 0,
    int? created,
    bool eligible = true,
  }) => HabitCheckXpFact(
    id: id,
    occurredAtUtc: at(minute),
    createdAtUtc: at(created ?? minute),
    eligible: eligible,
    habitId: habitId,
  );

  List<XpAward> awardsOf(XpDayFacts facts, {LocalDate? start}) =>
      computeDayAwards(facts, profileStart: start ?? profileStart);

  int total(Iterable<XpAward> awards) =>
      awards.fold(0, (sum, award) => sum + award.points);

  List<String> keys(Iterable<XpAward> awards) =>
      awards.map((award) => award.key).toList();

  group('water: first four entries of at least 100 ml, 5 XP each', () {
    test('99 ml earns nothing, 100 ml earns 5 XP', () {
      expect(
        awardsOf(XpDayFacts(date: day, water: [water('w1', ml: 99)])),
        isEmpty,
      );
      final awards = awardsOf(
        XpDayFacts(date: day, water: [water('w1', ml: 100)]),
      );
      expect(keys(awards), ['water:w1']);
      expect(total(awards), 5);
    });

    test('the award describes its entry', () {
      final awards = awardsOf(XpDayFacts(date: day, water: [water('w1')]));
      expect(
        awards.single,
        XpAward(
          key: 'water:w1',
          date: day,
          source: XpSource.water,
          sourceId: 'w1',
          points: 5,
        ),
      );
      expect(awards.single.ruleVersion, 1);
    });

    test('the fourth entry still earns, the fifth and sixth do not', () {
      final entries = [for (var i = 1; i <= 6; i++) water('w$i', minute: i)];
      for (var count = 1; count <= 6; count++) {
        final awards = awardsOf(
          XpDayFacts(date: day, water: entries.take(count).toList()),
        );
        expect(
          awards,
          hasLength(count <= 4 ? count : 4),
          reason: '$count entries',
        );
        expect(total(awards), (count <= 4 ? count : 4) * 5);
      }
      final all = awardsOf(XpDayFacts(date: day, water: entries));
      expect(keys(all), ['water:w1', 'water:w2', 'water:w3', 'water:w4']);
      expect(total(all), 20);
    });

    test('entries below 100 ml do not take one of the four places', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          water: [
            water('s1', ml: 50, minute: 1),
            water('s2', ml: 99, minute: 2),
            water('a', minute: 3),
            water('b', minute: 4),
            water('c', minute: 5),
            water('d', minute: 6),
            water('e', minute: 7),
          ],
        ),
      );
      expect(keys(awards), ['water:a', 'water:b', 'water:c', 'water:d']);
    });

    test('amounts are not added up: two small entries earn nothing', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          water: [water('a', ml: 60, minute: 1), water('b', ml: 60, minute: 2)],
        ),
      );
      expect(awards, isEmpty);
    });

    test('entries that were not eligible earn nothing and take no place', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          water: [
            water('x1', minute: 1, eligible: false),
            water('x2', minute: 2, eligible: false),
            water('a', minute: 3),
            water('b', minute: 4),
            water('c', minute: 5),
            water('d', minute: 6),
            water('e', minute: 7),
          ],
        ),
      );
      expect(keys(awards), ['water:a', 'water:b', 'water:c', 'water:d']);
    });

    test('"first" is decided by event time, not by the order of the input', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          water: [
            water('late', minute: 90),
            water('c', minute: 30),
            water('a', minute: 10),
            water('d', minute: 40),
            water('b', minute: 20),
          ],
        ),
      );
      expect(keys(awards), ['water:a', 'water:b', 'water:c', 'water:d']);
    });
  });

  group('weight: 10 XP once per day', () {
    test('no entry earns nothing', () {
      expect(awardsOf(XpDayFacts(date: day)), isEmpty);
    });

    test('one eligible entry earns 10 XP under the day key', () {
      final awards = awardsOf(XpDayFacts(date: day, weights: [weight('m1')]));
      expect(
        awards.single,
        XpAward(
          key: 'weight:2026-10-03',
          date: day,
          source: XpSource.weight,
          points: 10,
        ),
      );
      expect(awards.single.sourceId, isNull);
    });

    test('several entries still earn only once', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          weights: [
            weight('m1', minute: 1),
            weight('m2', minute: 2),
            weight('m3', minute: 3),
          ],
        ),
      );
      expect(total(awards), 10);
      expect(awards, hasLength(1));
    });

    test('one eligible entry among ineligible ones is enough', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          weights: [weight('m1', eligible: false), weight('m2', minute: 5)],
        ),
      );
      expect(total(awards), 10);
    });

    test('only ineligible entries earn nothing', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          weights: [
            weight('m1', eligible: false),
            weight('m2', eligible: false),
          ],
        ),
      );
      expect(awards, isEmpty);
    });
  });

  group('steps: 10 XP once per day at the frozen threshold', () {
    StepsXpFact steps(
      int value, {
      bool? eligible = true,
      int? target = 10000,
    }) => StepsXpFact(
      steps: value,
      reachedGoalEligible: eligible,
      xpGoalTargetSteps: target,
    );

    List<XpAward> forSteps(StepsXpFact? fact) =>
        awardsOf(XpDayFacts(date: day, steps: fact));

    test('no step record earns nothing', () {
      expect(forSteps(null), isEmpty);
    });

    test('the frozen threshold is the boundary', () {
      expect(forSteps(steps(9999)), isEmpty);
      final reached = forSteps(steps(10000));
      expect(
        reached.single,
        XpAward(
          key: 'steps:2026-10-03',
          date: day,
          source: XpSource.steps,
          points: 10,
        ),
      );
      expect(forSteps(steps(10001)), hasLength(1));
      expect(forSteps(steps(100000)), hasLength(1));
    });

    test('a later correction below the frozen threshold removes the award', () {
      expect(forSteps(steps(10500)), hasLength(1));
      expect(forSteps(steps(8000)), isEmpty);
      expect(forSteps(steps(10500)), hasLength(1));
    });

    test('the frozen threshold counts, whatever the goal is today', () {
      // Frozen at 8000 when first reached; the goal was raised for later days.
      expect(forSteps(steps(8000, target: 8000)), hasLength(1));
      expect(forSteps(steps(9000, target: 8000)), hasLength(1));
      expect(forSteps(steps(7999, target: 8000)), isEmpty);
    });

    test('reached while gamification was off is never awarded', () {
      expect(forSteps(steps(12000, eligible: false)), isEmpty);
    });

    test('without a decision there is no claim', () {
      expect(forSteps(steps(12000, eligible: null, target: null)), isEmpty);
      expect(forSteps(steps(12000, eligible: true, target: null)), isEmpty);
    });

    test('earnsAward follows the same rule', () {
      expect(steps(10000).earnsAward, isTrue);
      expect(steps(9999).earnsAward, isFalse);
      expect(steps(10000, eligible: false).earnsAward, isFalse);
      expect(steps(10000, eligible: null).earnsAward, isFalse);
      expect(steps(10000, target: null).earnsAward, isFalse);
      expect(const StepsXpFact(steps: 0).earnsAward, isFalse);
    });
  });

  group('task: first five completed tasks, 10 XP each', () {
    test('five tasks earn 50 XP, the sixth earns nothing', () {
      final tasks = [for (var i = 1; i <= 6; i++) task('t$i', minute: i)];
      final five = awardsOf(
        XpDayFacts(date: day, tasks: tasks.take(5).toList()),
      );
      expect(total(five), 50);
      expect(keys(five), [
        'task:t1',
        'task:t2',
        'task:t3',
        'task:t4',
        'task:t5',
      ]);
      final six = awardsOf(XpDayFacts(date: day, tasks: tasks));
      expect(total(six), 50);
      expect(keys(six), isNot(contains('task:t6')));
    });

    test('the award is attributed to the task', () {
      final awards = awardsOf(XpDayFacts(date: day, tasks: [task('t1')]));
      expect(
        awards.single,
        XpAward(
          key: 'task:t1',
          date: day,
          source: XpSource.task,
          sourceId: 't1',
          points: 10,
        ),
      );
    });

    test('an earlier completion takes the place of the latest one', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          tasks: [
            task('t1', minute: 10),
            task('t2', minute: 20),
            task('t3', minute: 30),
            task('t4', minute: 40),
            task('t5', minute: 50),
            task('t0', minute: 5),
          ],
        ),
      );
      expect(keys(awards), [
        'task:t0',
        'task:t1',
        'task:t2',
        'task:t3',
        'task:t4',
      ]);
    });

    test('ineligible tasks earn nothing and take no place', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          tasks: [
            task('x', minute: 1, eligible: false),
            for (var i = 1; i <= 5; i++) task('t$i', minute: 10 + i),
          ],
        ),
      );
      expect(total(awards), 50);
      expect(keys(awards), isNot(contains('task:x')));
    });
  });

  group('focus: first four sessions of at least 300 seconds, 10 XP each', () {
    test('299 seconds earn nothing, 300 seconds earn 10 XP', () {
      expect(
        awardsOf(
          XpDayFacts(date: day, focusSessions: [focus('f1', seconds: 299)]),
        ),
        isEmpty,
      );
      final awards = awardsOf(
        XpDayFacts(date: day, focusSessions: [focus('f1', seconds: 300)]),
      );
      expect(
        awards.single,
        XpAward(
          key: 'focus:f1',
          date: day,
          source: XpSource.focus,
          sourceId: 'f1',
          points: 10,
        ),
      );
    });

    test('the fourth session earns, the fifth does not', () {
      final sessions = [for (var i = 1; i <= 5; i++) focus('f$i', minute: i)];
      final four = awardsOf(
        XpDayFacts(date: day, focusSessions: sessions.take(4).toList()),
      );
      expect(total(four), 40);
      final five = awardsOf(XpDayFacts(date: day, focusSessions: sessions));
      expect(total(five), 40);
      expect(keys(five), ['focus:f1', 'focus:f2', 'focus:f3', 'focus:f4']);
    });

    test('short sessions take no place and earn nothing', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          focusSessions: [
            focus('s1', seconds: 120, minute: 1),
            focus('s2', seconds: 299, minute: 2),
            focus('a', minute: 3),
            focus('b', minute: 4),
            focus('c', minute: 5),
            focus('d', minute: 6),
            focus('e', minute: 7),
          ],
        ),
      );
      expect(keys(awards), ['focus:a', 'focus:b', 'focus:c', 'focus:d']);
    });

    test('ineligible sessions earn nothing', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          focusSessions: [focus('f1', eligible: false), focus('f2', minute: 5)],
        ),
      );
      expect(keys(awards), ['focus:f2']);
    });
  });

  group('workout: 15 XP once per day', () {
    test('one eligible entry earns 15 XP under the day key', () {
      final awards = awardsOf(XpDayFacts(date: day, workouts: [workout('o1')]));
      expect(
        awards.single,
        XpAward(
          key: 'workout:2026-10-03',
          date: day,
          source: XpSource.workout,
          points: 15,
        ),
      );
    });

    test('several entries still earn only once', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          workouts: [
            workout('o1', minute: 1),
            workout('o2', minute: 2),
            workout('o3', minute: 3),
          ],
        ),
      );
      expect(total(awards), 15);
    });

    test('ineligible entries earn nothing', () {
      expect(
        awardsOf(
          XpDayFacts(date: day, workouts: [workout('o1', eligible: false)]),
        ),
        isEmpty,
      );
      expect(
        total(
          awardsOf(
            XpDayFacts(
              date: day,
              workouts: [
                workout('o1', eligible: false),
                workout('o2', minute: 3),
              ],
            ),
          ),
        ),
        15,
      );
    });
  });

  group('habit: first five checks, 5 XP each', () {
    test('the key and source contain the habit and the day', () {
      final awards = awardsOf(
        XpDayFacts(date: day, habitChecks: [check('c1', 'habit-a')]),
      );
      expect(
        awards.single,
        XpAward(
          key: 'habit:habit-a:2026-10-03',
          date: day,
          source: XpSource.habit,
          sourceId: 'habit-a',
          points: 5,
        ),
      );
    });

    test('the fifth check earns, the sixth does not', () {
      final checks = [
        for (var i = 1; i <= 6; i++) check('c$i', 'h$i', minute: i),
      ];
      final five = awardsOf(
        XpDayFacts(date: day, habitChecks: checks.take(5).toList()),
      );
      expect(total(five), 25);
      final six = awardsOf(XpDayFacts(date: day, habitChecks: checks));
      expect(total(six), 25);
      expect(keys(six), [for (var i = 1; i <= 5; i++) 'habit:h$i:2026-10-03']);
    });

    test('ineligible checks earn nothing and take no place', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          habitChecks: [
            check('x', 'hx', minute: 1, eligible: false),
            for (var i = 1; i <= 5; i++) check('c$i', 'h$i', minute: 10 + i),
          ],
        ),
      );
      expect(total(awards), 25);
      expect(keys(awards).any((key) => key.contains('hx')), isFalse);
    });

    test('an earlier check takes the place of the latest one', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          habitChecks: [
            for (var i = 1; i <= 5; i++) check('c$i', 'h$i', minute: 10 + i),
            check('c0', 'h0', minute: 1),
          ],
        ),
      );
      expect(
        keys(awards),
        ['h0', 'h1', 'h2', 'h3', 'h4'].map((h) => 'habit:$h:2026-10-03'),
      );
    });
  });

  group('days, limits and determinism', () {
    test('a day without facts earns nothing', () {
      expect(awardsOf(XpDayFacts(date: day)), isEmpty);
    });

    test('nothing is earned when no record was eligible', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          water: [water('w1', eligible: false)],
          weights: [weight('m1', eligible: false)],
          steps: const StepsXpFact(
            steps: 20000,
            reachedGoalEligible: false,
            xpGoalTargetSteps: 10000,
          ),
          tasks: [task('t1', eligible: false)],
          focusSessions: [focus('f1', eligible: false)],
          workouts: [workout('o1', eligible: false)],
          habitChecks: [check('c1', 'h1', eligible: false)],
        ),
      );
      expect(awards, isEmpty);
    });

    test('a saturated day is capped at 170 XP from 21 awards', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          water: [for (var i = 1; i <= 9; i++) water('w$i', minute: i)],
          weights: [weight('m1'), weight('m2', minute: 1)],
          steps: const StepsXpFact(
            steps: 15000,
            reachedGoalEligible: true,
            xpGoalTargetSteps: 10000,
          ),
          tasks: [for (var i = 1; i <= 9; i++) task('t$i', minute: i)],
          focusSessions: [for (var i = 1; i <= 9; i++) focus('f$i', minute: i)],
          workouts: [workout('o1'), workout('o2', minute: 1)],
          habitChecks: [
            for (var i = 1; i <= 9; i++) check('c$i', 'h$i', minute: i),
          ],
        ),
      );
      expect(awards, hasLength(4 + 1 + 1 + 5 + 4 + 1 + 5));
      expect(total(awards), 20 + 10 + 10 + 50 + 40 + 15 + 25);
      expect(total(awards), 170);
      expect(
        keys(awards).toSet(),
        hasLength(awards.length),
        reason: 'unique keys',
      );
      expect(
        awards.every((award) => award.ruleVersion == XpRules.ruleVersion),
        isTrue,
      );
      expect(awards.every((award) => award.date == day), isTrue);
    });

    test('awards are ordered by source and then by the award order', () {
      final awards = awardsOf(
        XpDayFacts(
          date: day,
          water: [water('w2', minute: 2), water('w1', minute: 1)],
          weights: [weight('m1')],
          steps: const StepsXpFact(
            steps: 10000,
            reachedGoalEligible: true,
            xpGoalTargetSteps: 10000,
          ),
          tasks: [task('t1')],
          focusSessions: [focus('f1')],
          workouts: [workout('o1')],
          habitChecks: [check('c1', 'h1')],
        ),
      );
      expect(keys(awards), [
        'water:w1',
        'water:w2',
        'weight:2026-10-03',
        'steps:2026-10-03',
        'task:t1',
        'focus:f1',
        'workout:2026-10-03',
        'habit:h1:2026-10-03',
      ]);
    });

    test('the result does not depend on the order of the input facts', () {
      final waters = [for (var i = 1; i <= 7; i++) water('w$i', minute: i)];
      final forward = awardsOf(XpDayFacts(date: day, water: waters));
      final backward = awardsOf(
        XpDayFacts(date: day, water: waters.reversed.toList()),
      );
      expect(backward, forward);
      expect(awardsOf(XpDayFacts(date: day, water: waters)), forward);
    });

    test('the result cannot be modified afterwards', () {
      final awards = awardsOf(XpDayFacts(date: day, water: [water('w1')]));
      expect(awards.clear, throwsUnsupportedError);
    });
  });

  group('first means: event time, then creation time, then id', () {
    // Five qualifying facts of one source; the sixth in award order loses.
    // [build] makes a fact with the given id and times.
    void expectLastLoses<T extends XpEventFact>({
      required String name,
      required int limit,
      required T Function(String id, int occurred, int created) build,
      required XpDayFacts Function(List<T> facts) wrap,
      required String Function(String id) keyOf,
    }) {
      // 1. Distinct event times beat the creation time.
      final byEvent = [
        for (var i = 0; i <= limit; i++) build('e$i', 10 + i, 100 - i),
      ];
      expect(keys(awardsOf(wrap(byEvent.reversed.toList()))), [
        for (var i = 0; i < limit; i++) keyOf('e$i'),
      ], reason: '$name: event time decides');

      // 2. Same event time: the creation time decides.
      final byCreation = [
        for (var i = 0; i <= limit; i++) build('c${limit - i}', 10, 20 + i),
      ];
      expect(keys(awardsOf(wrap(byCreation.reversed.toList()))), [
        for (var i = 0; i < limit; i++) keyOf('c${limit - i}'),
      ], reason: '$name: creation time decides');

      // 3. Same event and creation time: the id (string comparison) decides.
      final ids = [
        'id-a',
        'id-b',
        'id-c',
        'id-d',
        'id-e',
        'id-f',
      ].take(limit + 1);
      final byId = [for (final id in ids) build(id, 10, 20)];
      expect(keys(awardsOf(wrap(byId.reversed.toList()))), [
        for (final id in ids.take(limit)) keyOf(id),
      ], reason: '$name: id decides');
    }

    test('water', () {
      expectLastLoses<WaterXpFact>(
        name: 'water',
        limit: XpRules.waterMaxAwardsPerDay,
        build: (id, occurred, created) =>
            water(id, minute: occurred, created: created),
        wrap: (facts) => XpDayFacts(date: day, water: facts),
        keyOf: XpKeys.water,
      );
    });

    test('tasks', () {
      expectLastLoses<TaskXpFact>(
        name: 'task',
        limit: XpRules.taskMaxAwardsPerDay,
        build: (id, occurred, created) =>
            task(id, minute: occurred, created: created),
        wrap: (facts) => XpDayFacts(date: day, tasks: facts),
        keyOf: XpKeys.task,
      );
    });

    test('focus sessions', () {
      expectLastLoses<FocusXpFact>(
        name: 'focus',
        limit: XpRules.focusMaxAwardsPerDay,
        build: (id, occurred, created) =>
            focus(id, minute: occurred, created: created),
        wrap: (facts) => XpDayFacts(date: day, focusSessions: facts),
        keyOf: XpKeys.focus,
      );
    });

    test('habit checks', () {
      expectLastLoses<HabitCheckXpFact>(
        name: 'habit',
        limit: XpRules.habitMaxAwardsPerDay,
        build: (id, occurred, created) =>
            check('check-$id', id, minute: occurred, created: created),
        wrap: (facts) => XpDayFacts(date: day, habitChecks: facts),
        keyOf: (habitId) => XpKeys.habit(habitId, day),
      );
    });

    test('compareXpEvents orders by the three keys', () {
      final early = water('b', minute: 1, created: 50);
      final late = water('a', minute: 2, created: 1);
      expect(compareXpEvents(early, late), lessThan(0));
      expect(compareXpEvents(late, early), greaterThan(0));
      final created1 = water('z', minute: 5, created: 1);
      final created2 = water('a', minute: 5, created: 2);
      expect(compareXpEvents(created1, created2), lessThan(0));
      final idA = water('id-a', minute: 5, created: 5);
      final idB = water('id-b', minute: 5, created: 5);
      expect(compareXpEvents(idA, idB), lessThan(0));
      expect(compareXpEvents(idB, idA), greaterThan(0));
      expect(compareXpEvents(idA, water('id-a', minute: 5, created: 5)), 0);
    });
  });

  group('replacement when an earlier record disappears', () {
    test('the next water entry moves up, the total does not rise', () {
      final entries = [for (var i = 1; i <= 5; i++) water('w$i', minute: i)];
      final before = awardsOf(XpDayFacts(date: day, water: entries));
      expect(keys(before), ['water:w1', 'water:w2', 'water:w3', 'water:w4']);
      expect(total(before), 20);

      final afterDelete = awardsOf(
        XpDayFacts(
          date: day,
          water: entries.where((entry) => entry.id != 'w2').toList(),
        ),
      );
      expect(keys(afterDelete), [
        'water:w1',
        'water:w3',
        'water:w4',
        'water:w5',
      ]);
      expect(total(afterDelete), 20, reason: 'replaced, not added');
    });

    test('the next task moves up when a completion is reopened', () {
      final tasks = [for (var i = 1; i <= 6; i++) task('t$i', minute: i)];
      final reopened = awardsOf(
        XpDayFacts(
          date: day,
          tasks: tasks.where((entry) => entry.id != 't1').toList(),
        ),
      );
      expect(keys(reopened), [
        'task:t2',
        'task:t3',
        'task:t4',
        'task:t5',
        'task:t6',
      ]);
      expect(total(reopened), 50);
    });

    test('a deleted entry that was beyond the limit changes nothing', () {
      final entries = [for (var i = 1; i <= 5; i++) water('w$i', minute: i)];
      final before = awardsOf(XpDayFacts(date: day, water: entries));
      final after = awardsOf(
        XpDayFacts(
          date: day,
          water: entries.where((entry) => entry.id != 'w5').toList(),
        ),
      );
      expect(after, before);
    });

    test('with fewer entries than places the total drops', () {
      final entries = [for (var i = 1; i <= 3; i++) water('w$i', minute: i)];
      final after = awardsOf(
        XpDayFacts(date: day, water: entries.take(2).toList()),
      );
      expect(total(after), 10);
    });
  });

  group('profile start', () {
    XpDayFacts activeDay(LocalDate date) => XpDayFacts(
      date: date,
      water: [water('w1')],
      weights: [weight('m1')],
      tasks: [task('t1')],
      focusSessions: [focus('f1')],
      workouts: [workout('o1')],
      habitChecks: [check('c1', 'h1')],
      steps: const StepsXpFact(
        steps: 10000,
        reachedGoalEligible: true,
        xpGoalTargetSteps: 10000,
      ),
    );

    test('events before the profile start earn no XP', () {
      expect(awardsOf(activeDay(profileStart.addDays(-1))), isEmpty);
      expect(awardsOf(activeDay(LocalDate(2020, 1, 1))), isEmpty);
    });

    test('the profile start day itself earns XP', () {
      final awards = awardsOf(activeDay(profileStart));
      expect(total(awards), 5 + 10 + 10 + 10 + 10 + 15 + 5);
      expect(awards.every((award) => award.date == profileStart), isTrue);
    });

    test('later days earn XP', () {
      expect(awardsOf(activeDay(profileStart.addDays(40))), isNotEmpty);
    });
  });

  group('random days (fixed seed)', () {
    /// The rule restated independently: the first [limit] qualifying facts by
    /// (event time, creation time, id).
    List<String> firstIds(Iterable<XpEventFact> facts, int limit) {
      final eligible = facts.where((fact) => fact.eligible).toList()
        ..sort((a, b) {
          var byTime = a.occurredAtUtc.compareTo(b.occurredAtUtc);
          if (byTime == 0) {
            byTime = a.createdAtUtc.compareTo(b.createdAtUtc);
          }
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
      return eligible.take(limit).map((fact) => fact.id).toList();
    }

    XpDayFacts randomDay(Random random) {
      var counter = 0;
      String nextId() =>
          '${random.nextInt(1 << 30).toRadixString(16).padLeft(8, '0')}-${counter++}';
      // Few distinct minutes, so ties on event and creation time happen often.
      int minute() => random.nextInt(6);
      bool eligible() => random.nextDouble() < 0.8;
      List<T> many<T>(T Function() make) => [
        for (var i = random.nextInt(9); i > 0; i--) make(),
      ];
      return XpDayFacts(
        date: day,
        water: many(
          () => water(
            nextId(),
            ml: [50, 99, 100, 250, 500][random.nextInt(5)],
            minute: minute(),
            created: minute(),
            eligible: eligible(),
          ),
        ),
        weights: many(() => weight(nextId(), eligible: eligible())),
        steps: random.nextBool()
            ? StepsXpFact(
                steps: random.nextInt(20000),
                reachedGoalEligible: [true, false, null][random.nextInt(3)],
                xpGoalTargetSteps: random.nextBool() ? 10000 : null,
              )
            : null,
        tasks: many(
          () => task(
            nextId(),
            minute: minute(),
            created: minute(),
            eligible: eligible(),
          ),
        ),
        focusSessions: many(
          () => focus(
            nextId(),
            seconds: [120, 299, 300, 1500][random.nextInt(4)],
            minute: minute(),
            created: minute(),
            eligible: eligible(),
          ),
        ),
        workouts: many(() => workout(nextId(), eligible: eligible())),
        habitChecks: many(
          () => check(
            nextId(),
            nextId(),
            minute: minute(),
            created: minute(),
            eligible: eligible(),
          ),
        ),
      );
    }

    test('awards follow the rules, limits and the order of the facts', () {
      final random = Random(99);
      for (var round = 0; round < 300; round++) {
        final facts = randomDay(random);
        final awards = awardsOf(facts);
        final reason = 'round $round';

        expect(
          awards
              .where((a) => a.source == XpSource.water)
              .map((a) => a.sourceId),
          firstIds(
            facts.water.where((f) => f.amountMl >= 100),
            XpRules.waterMaxAwardsPerDay,
          ),
          reason: reason,
        );
        expect(
          awards.where((a) => a.source == XpSource.task).map((a) => a.sourceId),
          firstIds(facts.tasks, XpRules.taskMaxAwardsPerDay),
          reason: reason,
        );
        expect(
          awards
              .where((a) => a.source == XpSource.focus)
              .map((a) => a.sourceId),
          firstIds(
            facts.focusSessions.where((f) => f.accumulatedSeconds >= 300),
            XpRules.focusMaxAwardsPerDay,
          ),
          reason: reason,
        );
        expect(
          awards
              .where((a) => a.source == XpSource.habit)
              .map((a) => a.key.split(':')[1]),
          firstIds(facts.habitChecks, XpRules.habitMaxAwardsPerDay).map(
            (checkId) => facts.habitChecks
                .firstWhere((fact) => fact.id == checkId)
                .habitId,
          ),
          reason: reason,
        );
        expect(
          awards.any((a) => a.source == XpSource.weight),
          facts.weights.any((fact) => fact.eligible),
          reason: reason,
        );
        expect(
          awards.any((a) => a.source == XpSource.workout),
          facts.workouts.any((fact) => fact.eligible),
          reason: reason,
        );
        expect(
          awards.any((a) => a.source == XpSource.steps),
          facts.steps?.earnsAward ?? false,
          reason: reason,
        );

        expect(total(awards), lessThanOrEqualTo(170), reason: reason);
        expect(keys(awards).toSet(), hasLength(awards.length), reason: reason);
        expect(awards.every((a) => a.points > 0), isTrue, reason: reason);
      }
    });

    test('the result does not depend on the order of the input', () {
      final random = Random(5);
      for (var round = 0; round < 100; round++) {
        final facts = randomDay(random);
        final shuffled = XpDayFacts(
          date: day,
          water: [...facts.water]..shuffle(random),
          weights: [...facts.weights]..shuffle(random),
          steps: facts.steps,
          tasks: [...facts.tasks]..shuffle(random),
          focusSessions: [...facts.focusSessions]..shuffle(random),
          workouts: [...facts.workouts]..shuffle(random),
          habitChecks: [...facts.habitChecks]..shuffle(random),
        );
        expect(awardsOf(shuffled), awardsOf(facts), reason: 'round $round');
      }
    });

    test('removing a record never raises the total and reconciles cleanly', () {
      final random = Random(11);
      for (var round = 0; round < 100; round++) {
        final facts = randomDay(random);
        if (facts.water.isEmpty) {
          continue;
        }
        final before = awardsOf(facts);
        final withoutFirst = XpDayFacts(
          date: day,
          water: facts.water.skip(1).toList(),
          weights: facts.weights,
          steps: facts.steps,
          tasks: facts.tasks,
          focusSessions: facts.focusSessions,
          workouts: facts.workouts,
          habitChecks: facts.habitChecks,
        );
        final after = awardsOf(withoutFirst);
        expect(
          total(after),
          lessThanOrEqualTo(total(before)),
          reason: 'round $round',
        );
        final change = reconcileAwards(existing: before, desired: after);
        final applied = {
          for (final award in before)
            if (!change.toDeleteKeys.contains(award.key)) award.key: award,
          for (final award in change.toUpsert) award.key: award,
        };
        expect(
          reconcileAwards(existing: applied.values, desired: after).isEmpty,
          isTrue,
          reason: 'round $round',
        );
        expect(total(applied.values), total(after), reason: 'round $round');
      }
    });
  });

  group('keys and sources', () {
    test('award keys have the persisted formats', () {
      final date = LocalDate(2026, 3, 9);
      expect(XpKeys.water('e1'), 'water:e1');
      expect(XpKeys.weight(date), 'weight:2026-03-09');
      expect(XpKeys.steps(date), 'steps:2026-03-09');
      expect(XpKeys.task('t1'), 'task:t1');
      expect(XpKeys.focus('s1'), 'focus:s1');
      expect(XpKeys.workout(date), 'workout:2026-03-09');
      expect(XpKeys.habit('h1', date), 'habit:h1:2026-03-09');
    });

    test('source keys are stable and parse back', () {
      expect(
        {for (final source in XpSource.values) source: source.key},
        {
          XpSource.water: 'water',
          XpSource.weight: 'weight',
          XpSource.steps: 'steps',
          XpSource.task: 'task',
          XpSource.focus: 'focus',
          XpSource.workout: 'workout',
          XpSource.habit: 'habit',
        },
      );
      for (final source in XpSource.values) {
        expect(XpSource.tryParse(source.key), source);
      }
      expect(XpSource.tryParse('meal'), isNull);
      expect(XpSource.tryParse(''), isNull);
    });

    test('an award never carries negative points', () {
      expect(
        () => XpAward(
          key: 'water:x',
          date: day,
          source: XpSource.water,
          points: -1,
        ),
        throwsAssertionError,
      );
    });

    test('awards compare by value', () {
      XpAward base({int points = 5, LocalDate? date, String? sourceId}) =>
          XpAward(
            key: 'water:x',
            date: date ?? day,
            source: XpSource.water,
            sourceId: sourceId ?? 'x',
            points: points,
          );
      expect(base(), base());
      expect(base().hashCode, base().hashCode);
      expect(base(), isNot(base(points: 6)));
      expect(base(), isNot(base(date: day.addDays(1))));
      expect(base(), isNot(base(sourceId: 'y')));
    });
  });
}
