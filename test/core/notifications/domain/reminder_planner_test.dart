import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/domain/notification_route_resolver.dart';
import 'package:self_improvement/core/notifications/domain/notification_routes.dart';
import 'package:self_improvement/core/notifications/domain/reminder_inputs.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/core/notifications/domain/reminder_planner.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/planner_fixtures.dart';

void main() {
  setUpAll(TimeZones.ensureInitialized);

  // The planner only uses the zone arithmetic of the clock.
  final planner = ReminderPlanner(clock: FakeClock.at('2026-10-03T00:00:00Z'));

  /// "now" is 2026-10-03 08:30 in Berlin (06:30Z, summer time).
  final morning = DateTime.utc(2026, 10, 3, 6, 30);

  /// 12:30 local on the same day.
  final noonish = DateTime.utc(2026, 10, 3, 10, 30);

  group('master switch and permission', () {
    test('reminders are off: nothing is planned', () {
      final plan = planner.plan(
        plannerInputs(now: morning, wanted: false, water: allWaterSlots),
      );
      expect(plan.notifications, isEmpty);
      expect(plan.skipped, ReminderPlanSkip.remindersOff);
    });

    test('permission denied: nothing is planned', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          permission: NotificationPermission.denied,
          water: allWaterSlots,
        ),
      );
      expect(plan.notifications, isEmpty);
      expect(plan.skipped, ReminderPlanSkip.permissionMissing);
    });

    test('permission unavailable: nothing is planned', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          permission: NotificationPermission.unavailable,
          water: allWaterSlots,
        ),
      );
      expect(plan.notifications, isEmpty);
      expect(plan.skipped, ReminderPlanSkip.permissionMissing);
    });

    test('the master switch wins over a missing permission', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          wanted: false,
          permission: NotificationPermission.denied,
          water: allWaterSlots,
        ),
      );
      expect(plan.skipped, ReminderPlanSkip.remindersOff);
    });

    test('wanted and permitted: planned, not skipped', () {
      final plan = planner.plan(
        plannerInputs(now: morning, water: allWaterSlots),
      );
      expect(plan.skipped, isNull);
      expect(plan.notifications, isNotEmpty);
    });

    test('nothing configured gives an empty plan that is not a skip', () {
      final plan = planner.plan(plannerInputs(now: morning));
      expect(plan.notifications, isEmpty);
      expect(plan.skipped, isNull);
      expect(plan.limitReached, isFalse);
    });
  });

  group('horizon of seven local calendar days', () {
    test('plans today and the next six days, not the seventh', () {
      final plan = planner.plan(
        plannerInputs(now: morning, water: [waterSlot(10)]),
      );
      expect(planKeys(plan), [
        'water:2026-10-03:10:00',
        'water:2026-10-04:10:00',
        'water:2026-10-05:10:00',
        'water:2026-10-06:10:00',
        'water:2026-10-07:10:00',
        'water:2026-10-08:10:00',
        'water:2026-10-09:10:00',
      ]);
      expect(planKeys(plan), isNot(contains('water:2026-10-10:10:00')));
    });

    test('a slot that already passed today leaves exactly six days', () {
      final plan = planner.plan(
        plannerInputs(now: noonish, water: [waterSlot(10)]),
      );
      expect(planKeys(plan).first, 'water:2026-10-04:10:00');
      expect(plan.notifications, hasLength(6));
      expect(planKeys(plan).last, 'water:2026-10-09:10:00');
    });

    test('the horizon is counted in calendar days around the clock change', () {
      // 23:30 local on 2026-10-24, the evening before the clocks go back.
      final plan = planner.plan(
        plannerInputs(
          now: DateTime.utc(2026, 10, 24, 21, 30),
          water: [waterSlot(10)],
        ),
      );
      expect(planKeys(plan).first, 'water:2026-10-25:10:00');
      expect(planKeys(plan).last, 'water:2026-10-30:10:00');
      expect(plan.notifications, hasLength(6));
    });

    test('a custom horizon is honoured', () {
      final short = ReminderPlanner(
        clock: FakeClock.at('2026-10-03T00:00:00Z'),
        horizonDays: 2,
      );
      final plan = short.plan(
        plannerInputs(now: morning, water: [waterSlot(10)]),
      );
      expect(planKeys(plan), [
        'water:2026-10-03:10:00',
        'water:2026-10-04:10:00',
      ]);
    });
  });

  group('past times', () {
    test('slots that already passed today are not planned', () {
      final plan = planner.plan(
        plannerInputs(now: noonish, water: allWaterSlots),
      );
      final today = planKeys(plan)
          .where((k) => k.startsWith('water:2026-10-03'));
      expect(today, [
        'water:2026-10-03:14:00',
        'water:2026-10-03:16:00',
        'water:2026-10-03:18:00',
      ]);
    });

    test('a time exactly now is not in the future and is not planned', () {
      // 12:00 local is 10:00Z.
      final atNow = planner.plan(
        plannerInputs(
          now: DateTime.utc(2026, 10, 3, 10),
          water: [waterSlot(12)],
        ),
      );
      expect(planKeys(atNow).first, 'water:2026-10-04:12:00');

      final oneMinuteBefore = planner.plan(
        plannerInputs(
          now: DateTime.utc(2026, 10, 3, 9, 59),
          water: [waterSlot(12)],
        ),
      );
      expect(planKeys(oneMinuteBefore).first, 'water:2026-10-03:12:00');
    });
  });

  group('water', () {
    test('plans every enabled slot with the neutral text and the route', () {
      final plan = planner.plan(
        plannerInputs(now: morning, water: allWaterSlots),
      );
      final first = planned(plan, 'water:2026-10-03:10:00');
      expect(first.kind, ReminderKind.water);
      expect(first.fireAtUtc, DateTime.utc(2026, 10, 3, 8));
      expect(first.route, NotificationRoutes.water);
      expect(first.title, 'Zeit für ein Glas Wasser');
      expect(first.sourceRuleId, 'rule-10');
      expect(plan.notifications, hasLength(5 * 7));
    });

    test('a disabled slot is not planned', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          water: [waterSlot(10), waterSlot(12, enabled: false)],
        ),
      );
      expect(planKeys(plan).where((k) => k.contains(':12:00')), isEmpty);
      expect(planKeys(plan).where((k) => k.contains(':10:00')), hasLength(7));
    });

    test('module nutrition off: no water reminders, others unaffected', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          modules: {ModuleId.tasks, ModuleId.focus},
          water: allWaterSlots,
          habits: [habitInput(1)],
        ),
      );
      expect(plan.notifications.map((n) => n.kind).toSet(), {
        ReminderKind.habit,
      });
    });

    test('a reached goal drops the remaining water of today only', () {
      // 12:30 local: today would still have 14, 16 and 18 o'clock.
      final plan = planner.plan(
        plannerInputs(
          now: noonish,
          water: allWaterSlots,
          waterGoalReached: true,
        ),
      );
      expect(
        planKeys(plan).where((k) => k.startsWith('water:2026-10-03')),
        isEmpty,
      );
      expect(
        planKeys(plan).where((k) => k.startsWith('water:2026-10-04')),
        hasLength(5),
      );
      expect(plan.notifications, hasLength(6 * 5));
    });

    test('a reached goal does not touch habit reminders of today', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          water: allWaterSlots,
          waterGoalReached: true,
          habits: [habitInput(1, time: const LocalTime(20, 0))],
        ),
      );
      expect(planKeys(plan), contains('habit:${uuid(1)}:2026-10-03'));
    });

    test('an unreached goal leaves today untouched', () {
      final plan = planner.plan(
        plannerInputs(now: noonish, water: allWaterSlots),
      );
      expect(
        planKeys(plan).where((k) => k.startsWith('water:2026-10-03')),
        hasLength(3),
      );
    });

    test('duplicate slots at one time give one notification, stable', () {
      final a = WaterReminderRule(id: 'b-rule', time: const LocalTime(10, 0));
      final b = WaterReminderRule(id: 'a-rule', time: const LocalTime(10, 0));
      final forward = planner.plan(plannerInputs(now: morning, water: [a, b]));
      final backward = planner.plan(plannerInputs(now: morning, water: [b, a]));
      expect(forward.notifications, hasLength(7));
      expect(forward.notifications, backward.notifications);
      expect(planned(forward, 'water:2026-10-03:10:00').sourceRuleId, 'a-rule');
    });
  });

  group('habits', () {
    final today = LocalDate(2026, 10, 3);

    test(
      'plans the individual time with the neutral text and detail route',
      () {
        final plan = planner.plan(
          plannerInputs(
            now: morning,
            habits: [habitInput(1, time: const LocalTime(18, 30))],
          ),
        );
        final first = planned(plan, 'habit:${uuid(1)}:2026-10-03');
        expect(first.kind, ReminderKind.habit);
        expect(first.fireAtUtc, DateTime.utc(2026, 10, 3, 16, 30));
        expect(first.route, '/habits/${uuid(1)}');
        expect(first.title, 'Zeit für deine Gewohnheit');
        expect(first.sourceRuleId, isNull);
        expect(plan.notifications, hasLength(7));
      },
    );

    test('a habit without reminder time is not planned', () {
      final plan = planner.plan(
        plannerInputs(now: morning, habits: [habitInput(1, time: null)]),
      );
      expect(plan.notifications, isEmpty);
    });

    test('a habit started today applies from today on', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          habits: [habitInput(1, time: const LocalTime(18, 0), started: today)],
        ),
      );
      expect(planKeys(plan).first, 'habit:${uuid(1)}:2026-10-03');
      expect(plan.notifications, hasLength(7));
    });

    test('a habit started tomorrow does not apply today', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          habits: [
            habitInput(
              1,
              time: const LocalTime(18, 0),
              started: today.addDays(1),
            ),
          ],
        ),
      );
      expect(planKeys(plan).first, 'habit:${uuid(1)}:2026-10-04');
      expect(plan.notifications, hasLength(6));
    });

    test('archived from tomorrow on: it still applies today, then it ends', () {
      // The user archives today: archivedFrom is tomorrow.
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          habits: [
            habitInput(
              1,
              time: const LocalTime(18, 0),
              archivedFrom: today.addDays(1),
            ),
          ],
        ),
      );
      expect(planKeys(plan), ['habit:${uuid(1)}:2026-10-03']);
    });

    test('archived from today on: it no longer applies, not even today', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          habits: [
            habitInput(1, time: const LocalTime(18, 0), archivedFrom: today),
          ],
        ),
      );
      expect(plan.notifications, isEmpty);
    });

    test('archived from the day after tomorrow: two more reminders', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          habits: [
            habitInput(
              1,
              time: const LocalTime(18, 0),
              archivedFrom: today.addDays(3),
            ),
          ],
        ),
      );
      expect(planKeys(plan), [
        'habit:${uuid(1)}:2026-10-03',
        'habit:${uuid(1)}:2026-10-04',
        'habit:${uuid(1)}:2026-10-05',
      ]);
    });

    test('a soft deleted habit is never reminded', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          habits: [habitInput(1, deleted: true), habitInput(2)],
        ),
      );
      expect(planKeys(plan).where((k) => k.contains(uuid(1))), isEmpty);
      expect(planKeys(plan).where((k) => k.contains(uuid(2))), isNotEmpty);
    });

    test('module tasks off: no habit reminders, others unaffected', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          modules: {ModuleId.nutrition, ModuleId.focus},
          habits: [habitInput(1)],
          water: [waterSlot(10)],
        ),
      );
      expect(plan.notifications.map((n) => n.kind).toSet(), {
        ReminderKind.water,
      });
    });

    test('several habits are planned independently', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          habits: [
            habitInput(1, time: const LocalTime(20, 0)),
            habitInput(2, time: const LocalTime(21, 15)),
          ],
        ),
      );
      expect(plan.notifications, hasLength(14));
      expect(
        planned(plan, 'habit:${uuid(2)}:2026-10-03').fireAtUtc,
        DateTime.utc(2026, 10, 3, 19, 15),
      );
    });
  });

  group('focus end', () {
    // 08:10 local, a segment running since 08:00 local (06:00Z).
    final now = DateTime.utc(2026, 10, 3, 6, 10);
    final segmentStart = DateTime.utc(2026, 10, 3, 6);

    test('a running session gets one notification at the end of the plan', () {
      final plan = planner.plan(
        plannerInputs(
          now: now,
          focus: runningFocus(segmentStart: segmentStart, planned: 1500),
        ),
      );
      expect(plan.notifications, hasLength(1));
      final end = plan.notifications.single;
      expect(end.semanticKey, 'focus_end:${uuid(90)}');
      expect(end.kind, ReminderKind.focusEnd);
      expect(end.fireAtUtc, DateTime.utc(2026, 10, 3, 6, 25));
      expect(end.route, NotificationRoutes.focusSession);
      expect(end.title, 'Deine Fokuszeit ist vorbei');
      expect(end.sourceRuleId, isNull);
    });

    test('the planned remaining time comes from the persisted segment', () {
      // 300 s were already accumulated: 1200 s remain after the segment start.
      final plan = planner.plan(
        plannerInputs(
          now: now,
          focus: runningFocus(
            segmentStart: segmentStart,
            planned: 1500,
            accumulated: 300,
          ),
        ),
      );
      expect(
        plan.notifications.single.fireAtUtc,
        DateTime.utc(2026, 10, 3, 6, 20),
      );
    });

    test('a resumed session is planned again from its new segment', () {
      // Paused with 600 s done: no notification.
      final paused = planner.plan(
        plannerInputs(
          now: DateTime.utc(2026, 10, 3, 6, 30),
          focus: FocusEndInput(
            sessionId: uuid(90),
            status: OpenFocusStatus.paused,
            plannedSeconds: 1500,
            accumulatedSeconds: 600,
          ),
        ),
      );
      expect(paused.notifications, isEmpty);

      // Resumed at 06:40Z: 900 s remain.
      final resumed = planner.plan(
        plannerInputs(
          now: DateTime.utc(2026, 10, 3, 6, 40),
          focus: runningFocus(
            segmentStart: DateTime.utc(2026, 10, 3, 6, 40),
            planned: 1500,
            accumulated: 600,
          ),
        ),
      );
      expect(
        resumed.notifications.single.fireAtUtc,
        DateTime.utc(2026, 10, 3, 6, 55),
      );
    });

    test('a session awaiting confirmation has no notification', () {
      final plan = planner.plan(
        plannerInputs(
          now: now,
          focus: FocusEndInput(
            sessionId: uuid(90),
            status: OpenFocusStatus.awaitingConfirmation,
            plannedSeconds: 1500,
            accumulatedSeconds: 1500,
          ),
        ),
      );
      expect(plan.notifications, isEmpty);
    });

    test('a running session whose end already passed has no notification', () {
      final plan = planner.plan(
        plannerInputs(
          now: DateTime.utc(2026, 10, 3, 7),
          focus: runningFocus(segmentStart: segmentStart, planned: 1500),
        ),
      );
      expect(plan.notifications, isEmpty);
    });

    test('an end exactly now is not in the future', () {
      final plan = planner.plan(
        plannerInputs(
          now: DateTime.utc(2026, 10, 3, 6, 25),
          focus: runningFocus(segmentStart: segmentStart, planned: 1500),
        ),
      );
      expect(plan.notifications, isEmpty);
    });

    test('module focus off: no notification', () {
      final plan = planner.plan(
        plannerInputs(
          now: now,
          modules: {ModuleId.nutrition, ModuleId.tasks},
          focus: runningFocus(segmentStart: segmentStart),
        ),
      );
      expect(plan.notifications, isEmpty);
    });

    test('reminders off: no focus notification either', () {
      final plan = planner.plan(
        plannerInputs(
          now: now,
          wanted: false,
          focus: runningFocus(segmentStart: segmentStart),
        ),
      );
      expect(plan.notifications, isEmpty);
    });

    test('a session without a segment start cannot be planned', () {
      final plan = planner.plan(
        plannerInputs(
          now: now,
          focus: FocusEndInput(
            sessionId: uuid(90),
            status: OpenFocusStatus.running,
            plannedSeconds: 1500,
            accumulatedSeconds: 0,
          ),
        ),
      );
      expect(plan.notifications, isEmpty);
    });

    test('a clock moved back does not move the planned end', () {
      // The persisted segment started "in the future" of the current clock;
      // the end stays segment start plus remaining time.
      final plan = planner.plan(
        plannerInputs(
          now: DateTime.utc(2026, 10, 3, 5, 50),
          focus: runningFocus(segmentStart: segmentStart),
        ),
      );
      expect(
        plan.notifications.single.fireAtUtc,
        DateTime.utc(2026, 10, 3, 6, 25),
      );
    });
  });

  group('payload and texts', () {
    test('every payload is a known route and nothing else', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          water: allWaterSlots,
          habits: [
            habitInput(1),
            habitInput(2, time: const LocalTime(7, 5)),
          ],
          focus: runningFocus(segmentStart: morning),
        ),
      );
      expect(plan.notifications, isNotEmpty);
      for (final notification in plan.notifications) {
        final target = NotificationRouteResolver.parse(notification.route);
        expect(target, isNotNull, reason: notification.route);
        expect(target!.route, notification.route);
        expect(
          notification.route.length,
          lessThanOrEqualTo(NotificationRouteResolver.maxPayloadLength),
        );
      }
    });

    test('titles are the neutral texts and carry no user text or values', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          water: allWaterSlots,
          habits: [habitInput(1)],
          focus: runningFocus(segmentStart: morning),
        ),
      );
      expect(plan.notifications.map((n) => n.title).toSet(), {
        'Zeit für ein Glas Wasser',
        'Zeit für deine Gewohnheit',
        'Deine Fokuszeit ist vorbei',
      });
      for (final notification in plan.notifications) {
        expect(notification.title, isNot(matches(RegExp(r'\d'))));
      }
    });

    test('a habit id that is not a UUID never enters a payload', () {
      final plan = planner.plan(
        plannerInputs(
          now: morning,
          habits: [
            HabitReminderInput(
              id: 'Lesen & mehr',
              startedOn: LocalDate(2026, 1, 1),
              reminderTime: const LocalTime(20, 0),
            ),
          ],
        ),
      );
      expect(plan.notifications, isNotEmpty);
      expect(plan.notifications.map((n) => n.route).toSet(), {
        NotificationRoutes.habits,
      });
    });
  });
}
