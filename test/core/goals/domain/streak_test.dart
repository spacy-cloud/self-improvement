import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/day_snapshot.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';

/// [length] consecutive days starting at [from].
List<LocalDate> run(LocalDate from, int length) => [
  for (var i = 0; i < length; i++) from.addDays(i),
];

/// A pure predicate over a fixed set of active days.
bool Function(LocalDate) activeOn(Iterable<LocalDate> days) =>
    days.toSet().contains;

void main() {
  final today = LocalDate(2026, 10, 3);
  final yesterday = today.addDays(-1);
  final longAgo = LocalDate(2026, 1, 1);

  StreakSummary streak({
    LocalDate? now,
    LocalDate? start,
    required Iterable<LocalDate> active,
  }) => computeStreak(
    today: now ?? today,
    profileStart: start ?? longAgo,
    isActiveDay: activeOn(active),
  );

  group('current streak', () {
    test('without any active day everything is zero', () {
      final summary = streak(active: const []);
      expect(summary.current, 0);
      expect(summary.longest, 0);
      expect(summary.activeDays, 0);
      expect(summary.todayActive, isFalse);
      expect(summary.nextMilestone, 3);
      expect(summary.daysUntilNextMilestone, 3);
    });

    test('today alone makes a streak of one', () {
      final summary = streak(active: [today]);
      expect(summary.current, 1);
      expect(summary.longest, 1);
      expect(summary.activeDays, 1);
      expect(summary.todayActive, isTrue);
    });

    test('AT22: yesterday active and today still open keeps the streak', () {
      final summary = streak(active: run(today.addDays(-5), 5));
      expect(summary.todayActive, isFalse);
      expect(summary.current, 5, reason: 'lasts until the end of today');
      expect(summary.longest, 5);
      expect(summary.activeDays, 5);
      expect(summary.lastSevenDays.last.status, StreakDayStatus.todayOpen);
    });

    test('today active extends the run that ends yesterday', () {
      final summary = streak(active: run(today.addDays(-4), 5));
      expect(summary.todayActive, isTrue);
      expect(summary.current, 5);
      expect(summary.longest, 5);
      expect(summary.lastSevenDays.last.status, StreakDayStatus.active);
    });

    test('yesterday inactive and today still open means 0', () {
      final summary = streak(active: run(today.addDays(-8), 6));
      expect(summary.current, 0);
      expect(summary.longest, 6, reason: 'the best streak is kept');
      expect(summary.activeDays, 6);
      expect(summary.todayActive, isFalse);
    });

    test('today active after a gap starts a new streak of one', () {
      final summary = streak(active: [...run(today.addDays(-9), 6), today]);
      expect(summary.current, 1);
      expect(summary.longest, 6);
      expect(summary.activeDays, 7);
    });

    test('a gap in the middle splits the runs', () {
      final active = [
        ...run(today.addDays(-9), 3),
        ...run(today.addDays(-5), 5),
      ];
      final summary = streak(active: active);
      expect(summary.current, 5, reason: 'run ends yesterday, today open');
      expect(summary.longest, 5);
      expect(summary.activeDays, 8);
    });

    test('the longest run can lie in the past', () {
      final active = [
        ...run(today.addDays(-30), 10),
        ...run(today.addDays(-2), 3),
      ];
      final summary = streak(active: active);
      expect(summary.todayActive, isTrue);
      expect(summary.current, 3);
      expect(summary.longest, 10);
      expect(summary.activeDays, 13);
    });

    test('a run that ends before yesterday no longer counts as current', () {
      final summary = streak(active: run(today.addDays(-10), 4));
      expect(summary.current, 0);
      expect(summary.longest, 4);
    });

    test('active days are counted once each, independent of order', () {
      final days = [today, yesterday, today.addDays(-3), today.addDays(-20)];
      final summary = streak(active: days);
      expect(summary.activeDays, 4);
      expect(summary.current, 2);
      expect(summary.longest, 2);
    });
  });

  group('profile start', () {
    test('nothing before the profile start counts', () {
      final everyDay = run(LocalDate(2025, 1, 1), 2000);
      final summary = streak(start: today.addDays(-3), active: everyDay);
      expect(summary.current, 4);
      expect(summary.longest, 4);
      expect(summary.activeDays, 4);
    });

    test('the predicate is only asked for days from start up to today', () {
      final asked = <LocalDate>[];
      computeStreak(
        today: today,
        profileStart: today.addDays(-3),
        isActiveDay: (day) {
          asked.add(day);
          return true;
        },
      );
      expect(asked.toSet(), run(today.addDays(-3), 4).toSet());
      expect(asked.any((day) => day.isBefore(today.addDays(-3))), isFalse);
      expect(asked.any((day) => day.isAfter(today)), isFalse);
    });

    test('profile started today: open, then active', () {
      final open = streak(start: today, active: const []);
      expect(open.current, 0);
      expect(open.longest, 0);
      expect(open.activeDays, 0);
      expect(open.todayActive, isFalse);
      expect(open.lastSevenDays.map((day) => day.status), [
        ...List.filled(6, StreakDayStatus.beforeStart),
        StreakDayStatus.todayOpen,
      ]);
      final active = streak(start: today, active: [today]);
      expect(active.current, 1);
      expect(active.longest, 1);
      expect(active.activeDays, 1);
      expect(active.todayActive, isTrue);
    });

    test('a profile start in the future yields an empty streak', () {
      var asked = 0;
      final summary = computeStreak(
        today: today,
        profileStart: today.addDays(2),
        isActiveDay: (day) {
          asked++;
          return true;
        },
      );
      expect(asked, 0);
      expect(summary.current, 0);
      expect(summary.longest, 0);
      expect(summary.activeDays, 0);
      expect(summary.todayActive, isFalse);
      expect(
        summary.lastSevenDays.every(
          (day) => day.status == StreakDayStatus.beforeStart,
        ),
        isTrue,
      );
    });
  });

  group('calendar boundaries', () {
    test('month boundary', () {
      final now = LocalDate(2026, 11, 2);
      final summary = streak(now: now, active: run(LocalDate(2026, 10, 29), 5));
      expect(summary.current, 5);
      expect(summary.longest, 5);
    });

    test('year boundary', () {
      final now = LocalDate(2027, 1, 3);
      final summary = streak(now: now, active: run(LocalDate(2026, 12, 29), 6));
      expect(summary.current, 6);
      expect(summary.longest, 6);
      expect(summary.activeDays, 6);
    });

    test('February in a leap year and in a common year', () {
      final leap = streak(
        now: LocalDate(2028, 3, 2),
        active: run(LocalDate(2028, 2, 27), 5),
      );
      expect(leap.current, 5, reason: '27, 28, 29 February, 1, 2 March');
      final common = streak(
        now: LocalDate(2026, 3, 2),
        active: run(LocalDate(2026, 2, 27), 4),
      );
      expect(common.current, 4, reason: '27, 28 February, 1, 2 March');
    });

    test('spring daylight saving day (2026-03-29) is one ordinary day', () {
      final active = run(LocalDate(2026, 3, 27), 5);
      final summary = streak(now: LocalDate(2026, 3, 31), active: active);
      expect(summary.current, 5);
      expect(summary.longest, 5);
      final onTheDay = streak(now: LocalDate(2026, 3, 29), active: active);
      expect(onTheDay.current, 3);
      expect(onTheDay.activeDays, 3);
      expect(
        onTheDay.lastSevenDays.map((day) => day.date),
        run(LocalDate(2026, 3, 23), 7),
      );
    });

    test('autumn daylight saving day (2026-10-25) is one ordinary day', () {
      final active = run(LocalDate(2026, 10, 23), 5);
      final summary = streak(now: LocalDate(2026, 10, 27), active: active);
      expect(summary.current, 5);
      expect(summary.longest, 5);
      final onTheDay = streak(now: LocalDate(2026, 10, 25), active: active);
      expect(onTheDay.current, 3);
      expect(
        onTheDay.lastSevenDays.map((day) => day.date),
        run(LocalDate(2026, 10, 19), 7),
      );
    });

    test('a missing day on a daylight saving date still breaks the run', () {
      final active = [
        ...run(LocalDate(2026, 3, 25), 4),
        ...run(LocalDate(2026, 3, 30), 2),
      ];
      final summary = streak(now: LocalDate(2026, 3, 31), active: active);
      expect(summary.current, 2);
      expect(summary.longest, 4);
    });

    test('a long streak of 400 days', () {
      final summary = streak(
        start: today.addDays(-399),
        active: run(today.addDays(-399), 400),
      );
      expect(summary.current, 400);
      expect(summary.longest, 400);
      expect(summary.activeDays, 400);
      expect(summary.nextMilestone, 500);
    });
  });

  group('last seven days', () {
    test('seven entries, oldest first, ending with today', () {
      final summary = streak(active: const []);
      expect(summary.lastSevenDays, hasLength(7));
      expect(
        summary.lastSevenDays.map((day) => day.date),
        run(LocalDate(2026, 9, 27), 7),
        reason: 'crosses the month boundary',
      );
      expect(summary.lastSevenDays.last.date, today);
    });

    test('active, inactive and open days are told apart', () {
      final summary = streak(
        active: [today.addDays(-6), today.addDays(-4), yesterday],
      );
      expect(summary.lastSevenDays.map((day) => day.status).toList(), [
        StreakDayStatus.active,
        StreakDayStatus.inactive,
        StreakDayStatus.active,
        StreakDayStatus.inactive,
        StreakDayStatus.inactive,
        StreakDayStatus.active,
        StreakDayStatus.todayOpen,
      ]);
    });

    test('today active is shown as active, not open', () {
      final summary = streak(active: [today]);
      expect(summary.lastSevenDays.last.status, StreakDayStatus.active);
      expect(summary.lastSevenDays.last.active, isTrue);
    });

    test('days before the profile start are marked as such', () {
      final summary = streak(
        start: today.addDays(-3),
        active: [today.addDays(-3), yesterday],
      );
      expect(summary.lastSevenDays.map((day) => day.status).toList(), [
        StreakDayStatus.beforeStart,
        StreakDayStatus.beforeStart,
        StreakDayStatus.beforeStart,
        StreakDayStatus.active,
        StreakDayStatus.inactive,
        StreakDayStatus.active,
        StreakDayStatus.todayOpen,
      ]);
    });

    test('only an active day is flagged as active', () {
      for (final status in StreakDayStatus.values) {
        expect(
          StreakDay(date: today, status: status).active,
          status == StreakDayStatus.active,
        );
      }
    });
  });

  group('milestones', () {
    test('smallest of 3/7/14/30/60/100 above the current streak', () {
      const expected = {
        0: 3,
        1: 3,
        2: 3,
        3: 7,
        6: 7,
        7: 14,
        13: 14,
        14: 30,
        29: 30,
        30: 60,
        59: 60,
        60: 100,
        99: 100,
        100: 200,
        101: 200,
        199: 200,
        200: 300,
        299: 300,
        999: 1000,
      };
      expected.forEach((current, milestone) {
        expect(nextStreakMilestone(current), milestone, reason: '$current');
      });
    });

    test('the summary carries the milestone of its current streak', () {
      final summary = streak(active: run(today.addDays(-5), 6));
      expect(summary.current, 6);
      expect(summary.nextMilestone, 7);
      expect(summary.daysUntilNextMilestone, 1);
      final reached = streak(active: run(today.addDays(-6), 7));
      expect(reached.current, 7);
      expect(reached.nextMilestone, 14);
      expect(reached.daysUntilNextMilestone, 7);
    });
  });

  group('retroactive corrections', () {
    final fullRun = run(today.addDays(-9), 10);

    test('removing a day in the past lowers streak and best streak', () {
      final before = streak(active: fullRun);
      expect(before.current, 10);
      expect(before.longest, 10);
      final corrected = streak(
        active: fullRun.where((day) => day != today.addDays(-5)),
      );
      expect(corrected.current, 5, reason: 'only the days after the gap');
      expect(corrected.longest, 5);
      expect(corrected.activeDays, 9);
    });

    test('adding a missing past day merges two runs', () {
      final withGap = fullRun.where((day) => day != today.addDays(-5));
      final gapped = streak(active: withGap);
      expect(gapped.longest, 5);
      final repaired = streak(active: [...withGap, today.addDays(-5)]);
      expect(repaired.current, 10);
      expect(repaired.longest, 10);
    });

    test('undoing the only activity of today falls back to yesterday', () {
      final withToday = streak(active: run(today.addDays(-3), 4));
      expect(withToday.current, 4);
      final undone = streak(active: run(today.addDays(-3), 3));
      expect(undone.current, 3, reason: 'today is open again, not broken');
      expect(undone.todayActive, isFalse);
    });

    test('a corrected yesterday with today still open resets to 0', () {
      final streakWithYesterday = streak(active: run(today.addDays(-3), 3));
      expect(streakWithYesterday.current, 3);
      final corrected = streak(
        active: run(today.addDays(-3), 3).where((day) => day != yesterday),
      );
      expect(corrected.current, 0);
      expect(corrected.longest, 2);
    });
  });

  group('with day statuses', () {
    DaySnapshot snapshotOn(
      LocalDate day, {
      bool Function(ModuleId module)? enabled,
    }) => buildDaySnapshot(
      day: day,
      profileStart: LocalDate(2026, 9, 1),
      versions: const [],
      isModuleEnabledOn: (module, _) => enabled == null || enabled(module),
      habits: const [],
    )!;

    test('a day without applicable goals is inactive and breaks the run', () {
      DayStatus status(LocalDate day) {
        // The day before yesterday has no applicable goals at all.
        final noGoals = day == today.addDays(-2);
        return computeDayStatus(
          snapshotOn(day, enabled: noGoals ? (_) => false : null),
          DayFacts(date: day, waterMl: 9999, weightEntries: 1),
        );
      }

      final summary = computeStreak(
        today: today,
        profileStart: LocalDate(2026, 9, 1),
        isActiveDay: (day) => status(day).isActive,
      );
      expect(status(today.addDays(-2)).isActive, isFalse);
      expect(status(today.addDays(-2)).ringFraction, isNull);
      expect(summary.todayActive, isTrue);
      expect(summary.current, 2, reason: 'today and yesterday; no free day');
    });

    test('a complete day and a day with one goal count the same', () {
      final one = computeDayStatus(
        snapshotOn(today),
        DayFacts(date: today, weightEntries: 1),
      );
      final all = computeDayStatus(
        snapshotOn(today),
        DayFacts(
          date: today,
          waterMl: 2500,
          stepsRecorded: 10000,
          weightEntries: 1,
          focusCompletedSeconds: 1500,
          tasksCompleted: 1,
        ),
      );
      expect(one.isActive, isTrue);
      expect(one.isComplete, isFalse);
      expect(all.isActive, isTrue);
      expect(all.isComplete, isTrue);
      expect(
        streak(active: [today]).current,
        1,
        reason: 'streak only needs one fulfilled goal',
      );
    });

    test('a masked module can change whether a day is active', () {
      final facts = DayFacts(date: today, waterMl: 2500);
      final withNutrition = computeDayStatus(snapshotOn(today), facts);
      final masked = computeDayStatus(
        snapshotOn(today, enabled: (module) => module != ModuleId.nutrition),
        facts,
      );
      expect(withNutrition.isActive, isTrue);
      expect(masked.isActive, isFalse);
    });
  });

  group('habit series', () {
    HabitSeries series({
      LocalDate? now,
      LocalDate? start,
      LocalDate? archivedFrom,
      required Iterable<LocalDate> checked,
    }) => computeHabitSeries(
      today: now ?? today,
      habitStart: start ?? longAgo,
      archivedFrom: archivedFrom,
      isChecked: activeOn(checked),
    );

    test('a habit started today and not checked yet has no series', () {
      final result = series(start: today, checked: const []);
      expect(result, const HabitSeries(current: 0, longest: 0));
    });

    test('checked today: series of one', () {
      final result = series(start: today, checked: [today]);
      expect(result, const HabitSeries(current: 1, longest: 1));
    });

    test('an open today does not break the series yet', () {
      final result = series(checked: run(today.addDays(-3), 3));
      expect(result.current, 3);
      expect(result.longest, 3);
    });

    test('checked today extends the series', () {
      final result = series(checked: run(today.addDays(-3), 4));
      expect(result.current, 4);
      expect(result.longest, 4);
    });

    test('an unchecked past day breaks the series', () {
      final result = series(
        checked: [
          ...run(today.addDays(-6), 2),
          ...run(today.addDays(-3), 1),
          yesterday,
        ],
      );
      expect(result.current, 1, reason: 'only yesterday; today still open');
      expect(result.longest, 2);
    });

    test('yesterday unchecked and today open means 0', () {
      final result = series(checked: run(today.addDays(-6), 4));
      expect(result.current, 0);
      expect(result.longest, 4);
    });

    test('only days from the habit start count', () {
      final asked = <LocalDate>[];
      final result = computeHabitSeries(
        today: today,
        habitStart: today.addDays(-2),
        archivedFrom: null,
        isChecked: (day) {
          asked.add(day);
          return true;
        },
      );
      expect(result, const HabitSeries(current: 3, longest: 3));
      expect(asked.toSet(), run(today.addDays(-2), 3).toSet());
    });

    test('archived from tomorrow still counts today', () {
      final archivedFrom = today.addDays(1);
      expect(
        series(archivedFrom: archivedFrom, checked: run(today.addDays(-2), 3)),
        const HabitSeries(current: 3, longest: 3),
      );
      expect(
        series(archivedFrom: archivedFrom, checked: run(today.addDays(-3), 3)),
        const HabitSeries(current: 3, longest: 3),
        reason: 'today is applicable but open: not broken yet',
      );
    });

    test('archived from today: the series is frozen at yesterday', () {
      final asked = <LocalDate>[];
      final frozen = computeHabitSeries(
        today: today,
        habitStart: today.addDays(-10),
        archivedFrom: today,
        isChecked: (day) {
          asked.add(day);
          return day.isAfter(today.addDays(-5));
        },
      );
      expect(frozen, const HabitSeries(current: 4, longest: 4));
      expect(asked.any((day) => !day.isBefore(today)), isFalse);
    });

    test('archived in the past: kept when the last day was checked', () {
      final archivedFrom = today.addDays(-5);
      final result = series(
        archivedFrom: archivedFrom,
        checked: run(archivedFrom.addDays(-3), 3),
      );
      expect(result, const HabitSeries(current: 3, longest: 3));
    });

    test('archived in the past: 0 when the last applicable day was missed', () {
      final archivedFrom = today.addDays(-5);
      final result = series(
        archivedFrom: archivedFrom,
        checked: run(archivedFrom.addDays(-4), 3),
      );
      expect(result, const HabitSeries(current: 0, longest: 3));
    });

    test('a habit that never applies has no series', () {
      expect(
        series(start: today.addDays(2), checked: [today, yesterday]),
        const HabitSeries(current: 0, longest: 0),
      );
      expect(
        series(start: today, archivedFrom: today, checked: [today, yesterday]),
        const HabitSeries(current: 0, longest: 0),
      );
    });

    test('month, year and daylight saving boundaries', () {
      expect(
        series(
          now: LocalDate(2027, 1, 2),
          checked: run(LocalDate(2026, 12, 30), 4),
        ),
        const HabitSeries(current: 4, longest: 4),
      );
      expect(
        series(
          now: LocalDate(2026, 3, 30),
          checked: run(LocalDate(2026, 3, 28), 3),
        ),
        const HabitSeries(current: 3, longest: 3),
      );
      expect(
        series(
          now: LocalDate(2026, 10, 26),
          checked: run(LocalDate(2026, 10, 24), 3),
        ),
        const HabitSeries(current: 3, longest: 3),
      );
    });

    test('follows the same calendar rule as the global streak', () {
      final patterns = <List<LocalDate>>[
        const [],
        [today],
        run(today.addDays(-5), 5),
        run(today.addDays(-4), 5),
        [...run(today.addDays(-12), 4), ...run(today.addDays(-3), 4)],
        [...run(today.addDays(-12), 4), yesterday],
      ];
      for (final checked in patterns) {
        final global = streak(start: today.addDays(-20), active: checked);
        final habit = series(start: today.addDays(-20), checked: checked);
        expect(habit.current, global.current, reason: '$checked');
        expect(habit.longest, global.longest, reason: '$checked');
      }
    });

    test('retroactively adding a check repairs the series', () {
      final broken = series(
        checked: [...run(today.addDays(-6), 3), ...run(today.addDays(-2), 2)],
      );
      expect(broken.current, 2);
      final repaired = series(checked: run(today.addDays(-6), 7));
      expect(repaired.current, 7);
      expect(repaired.longest, 7);
    });
  });
}
