import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/domain/notification_routes.dart';
import 'package:self_improvement/core/notifications/domain/reminder_inputs.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/core/notifications/domain/reminder_planner.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/reminder_texts.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/planner_fixtures.dart';

/// The reminder of a single task in the planner (BS-111): one instant under
/// the key `task:<id>`, not limited by the seven day horizon, competing for
/// the 40 places like every other reminder.
void main() {
  setUpAll(TimeZones.ensureInitialized);

  final planner = ReminderPlanner(clock: FakeClock.at('2026-10-03T00:00:00Z'));

  /// "now" is 2026-10-03 08:30 in Berlin (06:30Z, summer time).
  final now = DateTime.utc(2026, 10, 3, 6, 30);

  group('what is planned', () {
    test(
      'one notification at the instant, under task:<id>, with the task route '
      'and a neutral title (BS-111, AT28)',
      () {
        final at = now.add(const Duration(hours: 3));
        final plan = planner.plan(
          plannerInputs(
            now: now,
            tasks: [taskInput(1, at: at)],
          ),
        );
        final notification = plan.notifications.single;
        expect(notification.semanticKey, 'task:${uuid(1)}');
        expect(notification.kind, ReminderKind.task);
        expect(notification.fireAtUtc, at);
        expect(notification.route, '/tasks/${uuid(1)}');
        expect(notification.route, NotificationRoutes.taskEdit(uuid(1)));
        expect(notification.title, ReminderTexts.taskTitle);
        expect(notification.sourceRuleId, isNull);
        expect(plan.limitReached, isFalse);
      },
    );

    test('the title is neutral: it names no task, no date and no time '
        '(BS-111, AT28)', () {
      expect(
        ReminderTexts.titleFor(ReminderKind.task),
        'Erinnerung an deine Aufgabe',
      );
      // Habits and tasks are user text: neither title may reach a lock screen.
      expect(ReminderTexts.taskTitle, isNot(contains(':')));
      expect(ReminderTexts.taskTitle, isNot(matches(RegExp(r'\d'))));
    });

    test('an instant that is not strictly ahead is never planned (BS-111)', () {
      final plan = planner.plan(
        plannerInputs(
          now: now,
          tasks: [
            taskInput(1, at: now),
            taskInput(2, at: now.subtract(const Duration(minutes: 1))),
            taskInput(3, at: now.subtract(const Duration(days: 40))),
            taskInput(4, at: now.add(const Duration(milliseconds: 1))),
          ],
        ),
      );
      expect(planKeys(plan), ['task:${uuid(4)}']);
    });

    test(
      'several tasks give one notification each, soonest first (BS-111)',
      () {
        final plan = planner.plan(
          plannerInputs(
            now: now,
            tasks: [
              taskInput(3, at: now.add(const Duration(days: 2))),
              taskInput(1, at: now.add(const Duration(hours: 5))),
              taskInput(2, at: now.add(const Duration(hours: 1))),
            ],
          ),
        );
        expect(planKeys(plan), [
          'task:${uuid(2)}',
          'task:${uuid(1)}',
          'task:${uuid(3)}',
        ]);
      },
    );

    test(
      'a task id that is not a UUID falls back to the task list, never into a '
      'payload (BS-111)',
      () {
        final plan = planner.plan(
          plannerInputs(
            now: now,
            tasks: [
              TaskReminderInput(
                id: 'Steuer & mehr',
                reminderAtUtc: now.add(const Duration(hours: 1)),
              ),
            ],
          ),
        );
        expect(plan.notifications.single.route, NotificationRoutes.tasks);
      },
    );
  });

  group('the horizon does not apply to a task reminder (BS-111)', () {
    test('a reminder in three weeks and in a year is planned at once', () {
      final plan = planner.plan(
        plannerInputs(
          now: now,
          tasks: [
            taskInput(1, at: now.add(const Duration(days: 21))),
            taskInput(2, at: now.add(const Duration(days: 365))),
          ],
        ),
      );
      expect(planKeys(plan), ['task:${uuid(1)}', 'task:${uuid(2)}']);
    });

    test('habits and water keep the seven days next to it (regression)', () {
      final plan = planner.plan(
        plannerInputs(
          now: now,
          habits: [habitInput(7, time: const LocalTime(20, 0))],
          water: [waterSlot(10)],
          tasks: [taskInput(1, at: now.add(const Duration(days: 30)))],
        ),
      );
      final keys = planKeys(plan);
      expect(keys.where((k) => k.startsWith('habit:')), hasLength(7));
      expect(keys.where((k) => k.startsWith('water:')), hasLength(7));
      expect(keys.where((k) => k.startsWith('task:')), hasLength(1));
      expect(keys, isNot(contains('habit:${uuid(7)}:2026-10-10')));
    });
  });

  group('switches', () {
    final inputs = [taskInput(1, at: DateTime.utc(2026, 10, 3, 9))];

    test('reminders off: nothing is planned (BS-111, AT28)', () {
      final plan = planner.plan(
        plannerInputs(now: now, wanted: false, tasks: inputs),
      );
      expect(plan.notifications, isEmpty);
      expect(plan.skipped, ReminderPlanSkip.remindersOff);
    });

    test('permission denied or unavailable: nothing is planned '
        '(BS-111, AT28)', () {
      for (final permission in [
        NotificationPermission.denied,
        NotificationPermission.unavailable,
      ]) {
        final plan = planner.plan(
          plannerInputs(now: now, permission: permission, tasks: inputs),
        );
        expect(plan.notifications, isEmpty, reason: permission.name);
        expect(plan.skipped, ReminderPlanSkip.permissionMissing);
      }
    });

    test('module tasks off removes task reminders, water and focus stay '
        '(BS-111)', () {
      final plan = planner.plan(
        plannerInputs(
          now: now,
          modules: {ModuleId.nutrition, ModuleId.focus},
          habits: [habitInput(7)],
          water: [waterSlot(12)],
          tasks: inputs,
        ),
      );
      expect(plan.notifications.map((n) => n.kind).toSet(), {
        ReminderKind.water,
      });
    });

    test('module tasks on again brings the reminder back (BS-111)', () {
      final plan = planner.plan(plannerInputs(now: now, tasks: inputs));
      expect(planKeys(plan), ['task:${uuid(1)}']);
    });
  });

  group('order and the cap of 40 (BS-111)', () {
    test('at the same instant: focus end, task, habit, water', () {
      // 10:00 Berlin = 08:00Z. The focus session ends exactly then, too.
      final at = DateTime.utc(2026, 10, 3, 8);
      final plan = planner.plan(
        plannerInputs(
          now: now,
          habits: [habitInput(1, time: const LocalTime(10, 0))],
          water: [waterSlot(10)],
          tasks: [taskInput(2, at: at)],
          focus: runningFocus(
            segmentStart: DateTime.utc(2026, 10, 3, 7, 35),
            planned: 1500,
          ),
        ),
      );
      expect(planKeys(plan).take(4), [
        'focus_end:${uuid(90)}',
        'task:${uuid(2)}',
        'habit:${uuid(1)}:2026-10-03',
        'water:2026-10-03:10:00',
      ]);
    });

    test('a task reminder takes one of the 40 places and is itself cut when it '
        'is the farthest', () {
      // Five water slots (35 in seven days) and a daily habit (7): 42.
      ReminderInputs inputs(DateTime at) => plannerInputs(
        now: now,
        water: allWaterSlots,
        habits: [habitInput(1, time: const LocalTime(20, 0))],
        tasks: [taskInput(9, at: at)],
      );

      final near = planner.plan(inputs(now.add(const Duration(days: 2))));
      expect(
        near.notifications,
        hasLength(ReminderPlanner.defaultMaxNotifications),
      );
      expect(planKeys(near), contains('task:${uuid(9)}'));
      // 43 due, 40 kept.
      expect(near.droppedByLimit, 3);
      expect(near.limitReached, isTrue);

      final far = planner.plan(inputs(now.add(const Duration(days: 60))));
      expect(far.notifications, hasLength(40));
      expect(planKeys(far), isNot(contains('task:${uuid(9)}')));
      expect(far.droppedByLimit, 3);
      expect(far.limitReached, isTrue);
    });

    test('the far reminder gets its place on a later run, when the nearer ones '
        'have passed', () {
      List<String> planAt(DateTime at) => planKeys(
        planner.plan(
          plannerInputs(
            now: at,
            water: allWaterSlots,
            habits: [habitInput(1, time: const LocalTime(20, 0))],
            tasks: [taskInput(9, at: DateTime.utc(2026, 10, 12, 9))],
          ),
        ),
      );

      // On 2026-10-03 the reminder of 2026-10-12 is nine days away: after
      // everything in the seven day window, so beyond place 40.
      expect(planAt(now), isNot(contains('task:${uuid(9)}')));
      // Five days later the window has moved and it is one of the nearest.
      expect(
        planAt(now.add(const Duration(days: 5))),
        contains('task:${uuid(9)}'),
      );
    });

    test('with iOS in mind: the cap stays below the 64 pending notifications '
        'it keeps', () {
      expect(ReminderPlanner.defaultMaxNotifications, lessThan(64));
      final many = [
        for (var i = 1; i <= 100; i++)
          taskInput(i, at: now.add(Duration(hours: i))),
      ];
      final plan = planner.plan(plannerInputs(now: now, tasks: many));
      expect(plan.notifications, hasLength(40));
      expect(plan.droppedByLimit, 60);
      // The nearest 40 are kept, in order.
      expect(planKeys(plan).first, 'task:${uuid(1)}');
      expect(planKeys(plan).last, 'task:${uuid(40)}');
    });
  });

  group('time zones and clock changes (BS-111, AT25)', () {
    test('the instant does not follow the device zone, a habit does', () {
      final at = DateTime.utc(2026, 10, 5, 16, 45);
      ({DateTime task, DateTime habit}) summary(String zone) {
        final plan = planner.plan(
          plannerInputs(
            now: now,
            zone: zone,
            habits: [habitInput(1, time: const LocalTime(20, 0))],
            tasks: [taskInput(2, at: at)],
          ),
        );
        return (
          task: planned(plan, 'task:${uuid(2)}').fireAtUtc,
          habit: planned(plan, 'habit:${uuid(1)}:2026-10-05').fireAtUtc,
        );
      }

      final berlinPlan = summary(berlin);
      final newYorkPlan = summary(newYork);
      expect(berlinPlan.task, at);
      expect(newYorkPlan.task, at);
      expect(berlinPlan.habit, isNot(newYorkPlan.habit));
    });

    test(
      'instants around the two clock changes of Berlin are kept exactly',
      () {
        // 2026-03-29: 02:00 CET jumps to 03:00 CEST (01:00Z). 2026-10-25: 03:00
        // CEST falls back to 02:00 CET (01:00Z); 02:30 local exists twice.
        final march = DateTime.utc(2026, 3, 28, 12);
        final marchPlan = planner.plan(
          plannerInputs(
            now: march,
            tasks: [
              taskInput(1, at: DateTime.utc(2026, 3, 29, 0, 59)),
              taskInput(2, at: DateTime.utc(2026, 3, 29, 1)),
              taskInput(3, at: DateTime.utc(2026, 3, 29, 1, 1)),
            ],
          ),
        );
        expect(marchPlan.notifications.map((n) => n.fireAtUtc), [
          DateTime.utc(2026, 3, 29, 0, 59),
          DateTime.utc(2026, 3, 29, 1),
          DateTime.utc(2026, 3, 29, 1, 1),
        ]);

        final october = DateTime.utc(2026, 10, 24, 12);
        final octoberPlan = planner.plan(
          plannerInputs(
            now: october,
            tasks: [
              // 02:30 CEST (first) and 02:30 CET (second occurrence).
              taskInput(1, at: DateTime.utc(2026, 10, 25, 0, 30)),
              taskInput(2, at: DateTime.utc(2026, 10, 25, 1, 30)),
            ],
          ),
        );
        expect(octoberPlan.notifications.map((n) => n.fireAtUtc), [
          DateTime.utc(2026, 10, 25, 0, 30),
          DateTime.utc(2026, 10, 25, 1, 30),
        ]);
        expect(octoberPlan.notifications, hasLength(2));
      },
    );
  });
}
