import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/day_snapshot.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  final day = LocalDate(2026, 10, 3);

  WaterEntry entry(
    String id,
    int ml, {
    int hour = 7,
    int minute = 0,
    LocalDate? date,
    DateTime? created,
  }) {
    final when = DateTime.utc(2026, 10, 3, hour, minute);
    return WaterEntry(
      id: id,
      amountMl: ml,
      occurredAtUtc: when,
      localDate: date ?? day,
      timezoneId: 'Europe/Berlin',
      createdAtUtc: created ?? when,
      rowVersion: 1,
      gamificationEligible: true,
    );
  }

  group('waterPercent', () {
    test('is the real percentage rounded half up', () {
      expect(waterPercent(totalMl: 0, targetMl: 2500), 0);
      expect(waterPercent(totalMl: 1250, targetMl: 2500), 50);
      expect(waterPercent(totalMl: 745, targetMl: 1000), 75, reason: '74,5');
      expect(waterPercent(totalMl: 12, targetMl: 2500), 0, reason: '0,48');
      expect(waterPercent(totalMl: 13, targetMl: 2500), 1, reason: '0,52');
    });

    test('is not capped above the target', () {
      expect(waterPercent(totalMl: 2500, targetMl: 2500), 100);
      expect(waterPercent(totalMl: 2800, targetMl: 2500), 112);
      expect(waterPercent(totalMl: 5000, targetMl: 2500), 200);
    });

    test('never shows 100 while the target is not reached', () {
      expect(waterPercent(totalMl: 2475, targetMl: 2500), 99);
      expect(waterPercent(totalMl: 2487, targetMl: 2500), 99);
      expect(
        waterPercent(totalMl: 2490, targetMl: 2500),
        99,
        reason: '99,6 rounds to 100 but the goal is not reached',
      );
      expect(waterPercent(totalMl: 2499, targetMl: 2500), 99);
    });
  });

  group('resolveWaterTarget', () {
    DaySnapshot snapshot({
      int? target = 2500,
      bool applicable = true,
      LocalDate? date,
    }) => DaySnapshot(
      date: date ?? day,
      items: [
        GoalSnapshotItem(
          goalKey: GoalType.water.key,
          module: ModuleId.nutrition,
          target: target,
          applicable: applicable,
        ),
      ],
    );

    GoalVersion version(int target, LocalDate from, {bool enabled = true}) =>
        GoalVersion(
          type: GoalType.water,
          target: target,
          enabled: enabled,
          effectiveFrom: from,
        );

    int? resolve({
      DaySnapshot? snapshot,
      List<GoalVersion> versions = const [],
      bool nutritionEnabled = true,
      LocalDate? profileStart,
      LocalDate? forDay,
    }) => resolveWaterTarget(
      day: forDay ?? day,
      snapshot: snapshot,
      versions: versions,
      nutritionEnabledOnDay: nutritionEnabled,
      profileStart: profileStart,
    );

    test('the frozen snapshot target wins over every goal version', () {
      expect(
        resolve(
          snapshot: snapshot(target: 2500),
          versions: [version(4000, LocalDate(2026, 9, 1))],
        ),
        2500,
      );
    });

    test('a snapshot with a not applicable water item means no target', () {
      expect(resolve(snapshot: snapshot(applicable: false)), isNull);
    });

    test('a snapshot item without a stored target uses the default', () {
      expect(resolve(snapshot: snapshot(target: null)), 2500);
    });

    test('the snapshot decides even when the module flag disagrees', () {
      expect(
        resolve(snapshot: snapshot(target: 3000), nutritionEnabled: false),
        3000,
      );
    });

    test('without a snapshot the goal version in effect decides', () {
      final versions = [
        version(2000, LocalDate(2026, 9, 1)),
        version(3000, LocalDate(2026, 10, 3)),
        version(4000, LocalDate(2026, 10, 4)),
      ];
      expect(resolve(versions: versions), 3000);
      expect(resolve(versions: versions, forDay: LocalDate(2026, 10, 2)), 2000);
      expect(resolve(versions: versions, forDay: LocalDate(2026, 10, 4)), 4000);
    });

    test('without any version the default of 2500 ml applies', () {
      expect(resolve(), 2500);
    });

    test('a switched off goal version means no target', () {
      expect(
        resolve(
          versions: [version(2500, LocalDate(2026, 9, 1), enabled: false)],
        ),
        isNull,
      );
    });

    test('a switched off nutrition module means no target', () {
      expect(resolve(nutritionEnabled: false), isNull);
    });

    test('before the profile start no goal exists', () {
      expect(resolve(profileStart: LocalDate(2026, 10, 4)), isNull);
      expect(resolve(profileStart: LocalDate(2026, 10, 3)), 2500);
      expect(resolve(profileStart: LocalDate(2026, 9, 1)), 2500);
    });
  });

  group('buildWaterToday', () {
    test('an empty day without a target has nothing to show', () {
      final today = buildWaterToday(date: day, entries: [], targetMl: null);
      expect(today.date, day);
      expect(today.totalMl, 0);
      expect(today.isEmpty, isTrue);
      expect(today.entryCount, 0);
      expect(today.hasTarget, isFalse);
      expect(today.targetMl, isNull);
      expect(today.fraction, isNull);
      expect(today.percent, isNull);
      expect(today.remainingMl, isNull);
      expect(today.goalReached, isFalse);
    });

    test(
      'a target that is not positive is no goal and never divides by zero',
      () {
        for (final bad in [0, -250]) {
          final today = buildWaterToday(
            date: day,
            entries: [entry('a', 250)],
            targetMl: bad,
          );
          expect(today.hasTarget, isFalse, reason: '$bad');
          expect(today.fraction, isNull);
          expect(today.percent, isNull);
          expect(today.goalReached, isFalse);
          expect(today.totalMl, 250);
        }
      },
    );

    test('below the target: fraction, percent and remaining', () {
      final today = buildWaterToday(
        date: day,
        entries: [entry('a', 250), entry('b', 500, hour: 8)],
        targetMl: 2500,
      );
      expect(today.totalMl, 750);
      expect(today.targetMl, 2500);
      expect(today.fraction, closeTo(0.3, 1e-12));
      expect(today.percent, 30);
      expect(today.remainingMl, 1750);
      expect(today.goalReached, isFalse);
      expect(today.hasTarget, isTrue);
    });

    test('exactly at the target the goal is reached', () {
      final today = buildWaterToday(
        date: day,
        entries: [entry('a', 1250), entry('b', 1250, hour: 8)],
        targetMl: 2500,
      );
      expect(today.totalMl, 2500);
      expect(today.fraction, 1.0);
      expect(today.percent, 100);
      expect(today.remainingMl, 0);
      expect(today.goalReached, isTrue);
    });

    test('above the target the bar is capped, the real values are kept', () {
      final today = buildWaterToday(
        date: day,
        entries: [entry('a', 1500), entry('b', 1300, hour: 8)],
        targetMl: 2500,
      );
      expect(today.totalMl, 2800, reason: 'the real total is never capped');
      expect(today.fraction, 1.0, reason: 'the bar stops at 100 %');
      expect(today.percent, 112, reason: 'the real percentage is shown');
      expect(today.remainingMl, 0);
      expect(today.goalReached, isTrue);
    });

    test('entries are newest first regardless of the input order', () {
      final today = buildWaterToday(
        date: day,
        entries: [
          entry('early', 250, hour: 6),
          entry('late', 250, hour: 9),
          entry('mid', 250, hour: 7, minute: 30),
        ],
        targetMl: null,
      );
      expect(today.entriesNewestFirst.map((e) => e.id), [
        'late',
        'mid',
        'early',
      ]);
    });

    test('a changed target changes the progress of the same entries', () {
      final entries = [entry('a', 1000)];
      expect(
        buildWaterToday(date: day, entries: entries, targetMl: 2000).percent,
        50,
      );
      expect(
        buildWaterToday(date: day, entries: entries, targetMl: 4000).percent,
        25,
      );
    });

    test('equal models are equal, different ones are not', () {
      WaterToday build(int ml) =>
          buildWaterToday(date: day, entries: [entry('a', ml)], targetMl: 2500);
      expect(build(250), build(250));
      expect(build(250).hashCode, build(250).hashCode);
      expect(build(250), isNot(build(300)));
    });
  });

  group('compareWaterNewestFirst', () {
    test('equal times fall back to the creation time, then the id', () {
      final base = DateTime.utc(2026, 10, 3, 7);
      WaterEntry at(String id, DateTime created) => WaterEntry(
        id: id,
        amountMl: 250,
        occurredAtUtc: base,
        localDate: day,
        timezoneId: 'Europe/Berlin',
        createdAtUtc: created,
        rowVersion: 1,
        gamificationEligible: true,
      );
      final sorted = [
        at('a', base),
        at('c', base.add(const Duration(seconds: 1))),
        at('b', base),
      ]..sort(compareWaterNewestFirst);
      expect(sorted.map((e) => e.id), ['c', 'b', 'a']);
    });
  });

  group('buildWaterHistory', () {
    test('groups per stored local day, newest day first with totals', () {
      final oct2 = LocalDate(2026, 10, 2);
      final history = buildWaterHistory(
        days: 14,
        entries: [
          entry('a', 250, hour: 7, date: oct2),
          entry('b', 500, hour: 9),
          entry('c', 300, hour: 8),
          entry('d', 100, hour: 6, date: oct2),
        ],
        targetFor: (_) => 2500,
      );
      expect(history.days, 14);
      expect(history.isEmpty, isFalse);
      expect(history.daysNewestFirst.map((d) => d.date), [day, oct2]);
      final today = history.daysNewestFirst.first;
      expect(today.totalMl, 800);
      expect(today.entryCount, 2);
      expect(today.entriesNewestFirst.map((e) => e.id), ['b', 'c']);
      final yesterday = history.daysNewestFirst.last;
      expect(yesterday.totalMl, 350);
      expect(yesterday.entriesNewestFirst.map((e) => e.id), ['a', 'd']);
    });

    test('every day carries its own threshold and goal flag', () {
      final oct2 = LocalDate(2026, 10, 2);
      final history = buildWaterHistory(
        days: 7,
        entries: [
          entry('a', 2600, date: oct2),
          entry('b', 2600),
        ],
        targetFor: (d) => d == oct2 ? 2500 : 3000,
      );
      final today = history.daysNewestFirst.first;
      final yesterday = history.daysNewestFirst.last;
      expect(today.targetMl, 3000);
      expect(today.goalReached, isFalse);
      expect(yesterday.targetMl, 2500);
      expect(yesterday.goalReached, isTrue);
    });

    test('a day without any goal is never reached', () {
      final history = buildWaterHistory(
        days: 7,
        entries: [entry('a', 5000)],
        targetFor: (_) => null,
      );
      expect(history.daysNewestFirst.single.targetMl, isNull);
      expect(history.daysNewestFirst.single.goalReached, isFalse);
    });

    test('no entries means an empty history', () {
      final history = buildWaterHistory(
        days: 7,
        entries: [],
        targetFor: (_) => 2500,
      );
      expect(history.isEmpty, isTrue);
      expect(history.daysNewestFirst, isEmpty);
    });
  });

  group('buildWaterGoalSettings', () {
    GoalVersion version(int target, LocalDate from, {bool enabled = true}) =>
        GoalVersion(
          type: GoalType.water,
          target: target,
          enabled: enabled,
          effectiveFrom: from,
        );

    test('without a stored version tomorrow uses the default, no change', () {
      final settings = buildWaterGoalSettings(
        versions: const [],
        today: day,
        todayTargetMl: 2500,
      );
      expect(settings.effectiveFrom, LocalDate(2026, 10, 4));
      expect(settings.tomorrowTargetMl, 2500);
      expect(settings.tomorrowEnabled, isTrue);
      expect(settings.hasPendingChange, isFalse);
    });

    test('a change made today is pending until tomorrow', () {
      final settings = buildWaterGoalSettings(
        versions: [
          version(2500, LocalDate(2026, 9, 1)),
          version(3000, LocalDate(2026, 10, 4)),
        ],
        today: day,
        todayTargetMl: 2500,
      );
      expect(settings.todayTargetMl, 2500);
      expect(settings.tomorrowTargetMl, 3000);
      expect(settings.hasPendingChange, isTrue);
    });

    test('a goal switched off from tomorrow keeps its stored target', () {
      final settings = buildWaterGoalSettings(
        versions: [
          version(2500, LocalDate(2026, 9, 1)),
          version(2500, LocalDate(2026, 10, 4), enabled: false),
        ],
        today: day,
        todayTargetMl: 2500,
      );
      expect(settings.tomorrowEnabled, isFalse);
      expect(settings.tomorrowTargetMl, 2500);
      expect(settings.hasPendingChange, isTrue);
    });

    test('a goal that is off today and stays off has no pending change', () {
      final settings = buildWaterGoalSettings(
        versions: [version(2500, LocalDate(2026, 9, 1), enabled: false)],
        today: day,
        todayTargetMl: null,
      );
      expect(settings.hasPendingChange, isFalse);
      expect(settings.todayTargetMl, isNull);
    });
  });
}
