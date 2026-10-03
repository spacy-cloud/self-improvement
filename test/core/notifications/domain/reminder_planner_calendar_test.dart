import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/domain/planned_notification.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/core/notifications/domain/reminder_planner.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/planner_fixtures.dart';

void main() {
  setUpAll(TimeZones.ensureInitialized);

  final clock = FakeClock.at('2026-10-03T00:00:00Z');
  final planner = ReminderPlanner(clock: clock);

  /// The wall clock time of a planned instant, in [zone].
  String wallClock(PlannedNotification n, String zone) {
    final local = clock.toLocal(n.fireAtUtc, timeZoneId: zone);
    return '${local.date} ${local.time}';
  }

  group('global cap of 40 notifications', () {
    // 08:30 local; 12 habits at 09:00 are due at the same instant every day.
    final now = DateTime.utc(2026, 10, 3, 6, 30);
    final habits = [for (var n = 1; n <= 12; n++) habitInput(n)];

    test('keeps the earliest 40 and reports what was left out', () {
      final plan = planner.plan(plannerInputs(now: now, habits: habits));
      // 12 habits * 7 days = 84 are due: three whole days (36) and four
      // reminders of the fourth day fit.
      expect(plan.notifications, hasLength(40));
      expect(plan.droppedByLimit, 44);
      expect(plan.limitReached, isTrue);
      expect(planKeys(plan).last, 'habit:${uuid(4)}:2026-10-06');
      expect(planKeys(plan), isNot(contains('habit:${uuid(5)}:2026-10-06')));
    });

    test('is ordered by fire time', () {
      final plan = planner.plan(plannerInputs(now: now, habits: habits));
      final times = plan.notifications.map((n) => n.fireAtUtc).toList();
      expect(times, [...times]..sort());
    });

    test('both sides of the limit: 40 fit, 41 lose exactly one', () {
      // 40 notifications: 40 habits are due once each if only today counts.
      final oneDay = ReminderPlanner(clock: clock, horizonDays: 1);
      final fits = oneDay.plan(
        plannerInputs(
          now: now,
          habits: [for (var n = 1; n <= 40; n++) habitInput(n)],
        ),
      );
      expect(fits.notifications, hasLength(40));
      expect(fits.droppedByLimit, 0);
      expect(fits.limitReached, isFalse);

      final over = oneDay.plan(
        plannerInputs(
          now: now,
          habits: [for (var n = 1; n <= 41; n++) habitInput(n)],
        ),
      );
      expect(over.notifications, hasLength(40));
      expect(over.droppedByLimit, 1);
      expect(over.limitReached, isTrue);
      // The dropped one is the last by key.
      expect(planKeys(over), isNot(contains('habit:${uuid(41)}:2026-10-03')));
    });

    test('a custom cap is honoured', () {
      final small = ReminderPlanner(clock: clock, maxNotifications: 3);
      final plan = small.plan(plannerInputs(now: now, habits: [habitInput(1)]));
      expect(plan.notifications, hasLength(3));
      expect(plan.droppedByLimit, 4);
    });

    test('the focus end comes first when it is due at the same instant', () {
      // The focus session ends at 09:00 local = 07:00Z, exactly when day one
      // of 41 habits is due.
      final plan = planner.plan(
        plannerInputs(
          now: now,
          habits: [for (var n = 1; n <= 41; n++) habitInput(n)],
          focus: runningFocus(
            segmentStart: DateTime.utc(2026, 10, 3, 6, 30),
            planned: 1800,
          ),
        ),
      );
      expect(plan.notifications, hasLength(40));
      expect(plan.notifications.first.kind, ReminderKind.focusEnd);
      expect(plan.notifications.first.fireAtUtc, DateTime.utc(2026, 10, 3, 7));
      // The 39 other places at the same instant go to habits, by key.
      expect(
        plan.notifications.skip(1).every((n) => n.kind == ReminderKind.habit),
        isTrue,
      );
      expect(planKeys(plan)[1], 'habit:${uuid(1)}:2026-10-03');
    });

    test('equal times order habits before water, then by key', () {
      // 10:00 local is 08:00Z: water slot 10 and a habit at 10:00.
      final plan = planner.plan(
        plannerInputs(
          now: now,
          water: [waterSlot(10)],
          habits: [habitInput(1, time: const LocalTime(10, 0))],
        ),
      );
      expect(planKeys(plan).take(2), [
        'habit:${uuid(1)}:2026-10-03',
        'water:2026-10-03:10:00',
      ]);
    });

    test('the same input gives the same plan', () {
      final first = planner.plan(plannerInputs(now: now, habits: habits));
      final second = planner.plan(plannerInputs(now: now, habits: habits));
      expect(first.notifications, second.notifications);
    });
  });

  group('daylight saving time', () {
    group('spring forward on 2026-03-29 (23 hour day)', () {
      // 09:00 local on 2026-03-28 (CET, 08:00Z).
      final now = DateTime.utc(2026, 3, 28, 8);

      test('water slots keep their local wall clock time on the short day', () {
        final plan = planner.plan(
          plannerInputs(now: now, water: allWaterSlots),
        );
        final byDay = <String, List<String>>{};
        for (final n in plan.notifications) {
          final local = clock.toLocal(n.fireAtUtc, timeZoneId: berlin);
          byDay.putIfAbsent('${local.date}', () => []).add('${local.time}');
        }
        for (final day in [
          '2026-03-28',
          '2026-03-29',
          '2026-03-30',
          '2026-04-03',
        ]) {
          expect(byDay[day], [
            '10:00',
            '12:00',
            '14:00',
            '16:00',
            '18:00',
          ], reason: day);
        }
        expect(byDay.keys, hasLength(7));
      });

      test('the instants follow the offset change, not 24 hour blocks', () {
        final plan = planner.plan(
          plannerInputs(now: now, water: [waterSlot(10)]),
        );
        // CET (UTC+1) before the change, CEST (UTC+2) from 01:00Z.
        expect(
          planned(plan, 'water:2026-03-28:10:00').fireAtUtc,
          DateTime.utc(2026, 3, 28, 9),
        );
        expect(
          planned(plan, 'water:2026-03-29:10:00').fireAtUtc,
          DateTime.utc(2026, 3, 29, 8),
        );
        expect(
          planned(plan, 'water:2026-03-30:10:00').fireAtUtc,
          DateTime.utc(2026, 3, 30, 8),
        );
        // The short day is 23 hours long.
        final gap = planned(plan, 'water:2026-03-29:10:00').fireAtUtc
            .difference(planned(plan, 'water:2026-03-28:10:00').fireAtUtc);
        expect(gap, const Duration(hours: 23));
      });

      test('a time inside the gap is shifted to the first time after it', () {
        // 02:00 to 02:59 do not exist on 2026-03-29; 03:00 CEST is 01:00Z.
        final plan = planner.plan(
          plannerInputs(
            now: DateTime.utc(2026, 3, 27, 10),
            habits: [
              habitInput(1, time: const LocalTime(2, 30)),
              habitInput(2, time: const LocalTime(2, 0)),
              habitInput(3, time: const LocalTime(2, 59)),
              habitInput(4, time: const LocalTime(3, 0)),
              habitInput(5, time: const LocalTime(1, 59)),
            ],
          ),
        );
        DateTime fire(int n, String day) =>
            planned(plan, 'habit:${uuid(n)}:$day').fireAtUtc;

        // Shifted to 03:00 CEST = 01:00Z; the key keeps the configured date.
        expect(fire(1, '2026-03-29'), DateTime.utc(2026, 3, 29, 1));
        expect(fire(2, '2026-03-29'), DateTime.utc(2026, 3, 29, 1));
        expect(fire(3, '2026-03-29'), DateTime.utc(2026, 3, 29, 1));
        // 03:00 is valid and not shifted; 01:59 is before the gap.
        expect(fire(4, '2026-03-29'), DateTime.utc(2026, 3, 29, 1));
        expect(fire(5, '2026-03-29'), DateTime.utc(2026, 3, 29, 0, 59));
        // The days around the gap are normal: 02:30 CET and CEST.
        expect(fire(1, '2026-03-28'), DateTime.utc(2026, 3, 28, 1, 30));
        expect(fire(1, '2026-03-30'), DateTime.utc(2026, 3, 30, 0, 30));
        expect(
          wallClock(planned(plan, 'habit:${uuid(1)}:2026-03-29'), berlin),
          '2026-03-29 03:00',
        );
      });

      test(
        'a shifted reminder still counts once and is stable across runs',
        () {
          final inputs = plannerInputs(
            now: DateTime.utc(2026, 3, 27, 10),
            habits: [habitInput(1, time: const LocalTime(2, 30))],
          );
          final first = planner.plan(inputs);
          final second = planner.plan(inputs);
          expect(
            planKeys(first).where((k) => k.endsWith('2026-03-29')),
            hasLength(1),
          );
          expect(first.notifications, second.notifications);
        },
      );
    });

    group('fall back on 2026-10-25 (25 hour day)', () {
      // 08:00 local on 2026-10-24 (CEST, 06:00Z).
      final now = DateTime.utc(2026, 10, 24, 6);

      test('water slots keep their local wall clock time on the long day', () {
        final plan = planner.plan(
          plannerInputs(now: now, water: allWaterSlots),
        );
        final byDay = <String, List<String>>{};
        for (final n in plan.notifications) {
          final local = clock.toLocal(n.fireAtUtc, timeZoneId: berlin);
          byDay.putIfAbsent('${local.date}', () => []).add('${local.time}');
        }
        for (final day in [
          '2026-10-24',
          '2026-10-25',
          '2026-10-26',
          '2026-10-30',
        ]) {
          expect(byDay[day], [
            '10:00',
            '12:00',
            '14:00',
            '16:00',
            '18:00',
          ], reason: day);
        }
        expect(byDay.keys, hasLength(7));
      });

      test('the instants follow the offset change, not 24 hour blocks', () {
        final plan = planner.plan(
          plannerInputs(now: now, water: [waterSlot(10)]),
        );
        // CEST (UTC+2) up to 01:00Z on the 25th, then CET (UTC+1).
        expect(
          planned(plan, 'water:2026-10-24:10:00').fireAtUtc,
          DateTime.utc(2026, 10, 24, 8),
        );
        expect(
          planned(plan, 'water:2026-10-25:10:00').fireAtUtc,
          DateTime.utc(2026, 10, 25, 9),
        );
        expect(
          planned(plan, 'water:2026-10-26:10:00').fireAtUtc,
          DateTime.utc(2026, 10, 26, 9),
        );
        // The long day is 25 hours long.
        final gap = planned(plan, 'water:2026-10-25:10:00').fireAtUtc
            .difference(planned(plan, 'water:2026-10-24:10:00').fireAtUtc);
        expect(gap, const Duration(hours: 25));
      });

      test('a doubled time is planned once, at its first occurrence', () {
        // 02:00 to 02:59 occur twice: CEST (00:xxZ) and again as CET (01:xxZ).
        final plan = planner.plan(
          plannerInputs(
            now: now,
            habits: [
              habitInput(1, time: const LocalTime(2, 30)),
              habitInput(2, time: const LocalTime(3, 0)),
              habitInput(3, time: const LocalTime(1, 59)),
            ],
          ),
        );
        expect(
          planKeys(plan)
              .where((k) => k.startsWith('habit:${uuid(1)}:2026-10-25')),
          hasLength(1),
        );
        expect(
          planned(plan, 'habit:${uuid(1)}:2026-10-25').fireAtUtc,
          DateTime.utc(2026, 10, 25, 0, 30),
          reason: 'first occurrence, 02:30 CEST',
        );
        // 03:00 exists once, as CET.
        expect(
          planned(plan, 'habit:${uuid(2)}:2026-10-25').fireAtUtc,
          DateTime.utc(2026, 10, 25, 2),
        );
        expect(
          planned(plan, 'habit:${uuid(3)}:2026-10-25').fireAtUtc,
          DateTime.utc(2026, 10, 24, 23, 59),
        );
      });
    });
  });

  group('time zone', () {
    test('the same slot is planned at another instant in a new zone', () {
      final now = DateTime.utc(2026, 10, 3, 6, 30);
      final inBerlin = planner.plan(
        plannerInputs(now: now, water: [waterSlot(10)]),
      );
      final inNewYork = planner.plan(
        plannerInputs(now: now, zone: newYork, water: [waterSlot(10)]),
      );
      // Same semantic key for the same local day and time, new instant.
      const key = 'water:2026-10-04:10:00';
      expect(planned(inBerlin, key).fireAtUtc, DateTime.utc(2026, 10, 4, 8));
      expect(planned(inNewYork, key).fireAtUtc, DateTime.utc(2026, 10, 4, 14));
      expect(wallClock(planned(inNewYork, key), newYork), '2026-10-04 10:00');
    });

    test('the horizon starts on the local day of the new zone', () {
      // 23:30Z on the 3rd: already the 4th in Berlin, still the 3rd in
      // New York (UTC-4 in summer).
      final now = DateTime.utc(2026, 10, 3, 23, 30);
      final inBerlin = planner.plan(
        plannerInputs(now: now, water: [waterSlot(20)]),
      );
      final inNewYork = planner.plan(
        plannerInputs(now: now, zone: newYork, water: [waterSlot(20)]),
      );
      expect(planKeys(inBerlin).first, 'water:2026-10-04:20:00');
      expect(planKeys(inNewYork).first, 'water:2026-10-03:20:00');
      expect(
        planned(inNewYork, 'water:2026-10-03:20:00').fireAtUtc,
        DateTime.utc(2026, 10, 4, 0),
      );
    });

    test('a habit stays at its wall clock time after the zone changed', () {
      final now = DateTime.utc(2026, 10, 3, 6, 30);
      final plan = planner.plan(
        plannerInputs(
          now: now,
          zone: newYork,
          habits: [habitInput(1, time: const LocalTime(7, 5))],
        ),
      );
      expect(
        wallClock(planned(plan, 'habit:${uuid(1)}:2026-10-04'), newYork),
        '2026-10-04 07:05',
      );
    });
  });
}
