import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  WorkoutEntry workout(
    String id,
    LocalDate date, {
    int minutes = 45,
    int hour = 8,
    String? title,
    TrainingCategory category = TrainingCategory.strength,
  }) => WorkoutEntry(
    id: id,
    category: category,
    title: title,
    durationMinutes: minutes,
    occurredAtUtc: DateTime.utc(date.year, date.month, date.day, hour),
    localDate: date,
    timezoneId: 'Europe/Berlin',
    rowVersion: 1,
    gamificationEligible: true,
  );

  // 2026-10-03 is a Saturday; its week is Monday 09-28 to Sunday 10-04.
  final saturday = LocalDate(2026, 10, 3);

  group('the week is Monday to Sunday', () {
    test('Saturday 2026-10-03 belongs to 09-28 .. 10-04', () {
      final summary = buildWorkoutWeekSummary(
        entries: const [],
        today: saturday,
        weeklyTarget: 3,
      );
      expect(summary.weekStart, LocalDate(2026, 9, 28));
      expect(summary.weekEnd, LocalDate(2026, 10, 4));
      expect(summary.weekStart.weekday, DateTime.monday);
      expect(summary.weekEnd.weekday, DateTime.sunday);
    });

    test('Sunday counts to the week that ends, Monday starts a new one', () {
      final entries = [
        workout('sun-before', LocalDate(2026, 9, 27)),
        workout('mon', LocalDate(2026, 9, 28)),
        workout('sun', LocalDate(2026, 10, 4)),
        workout('mon-after', LocalDate(2026, 10, 5)),
      ];
      final thisWeek = buildWorkoutWeekSummary(
        entries: entries,
        today: saturday,
        weeklyTarget: 3,
      );
      expect(thisWeek.entryCount, 2, reason: 'Monday 09-28 and Sunday 10-04');
      expect(thisWeek.latest!.id, 'sun');

      final sunday = buildWorkoutWeekSummary(
        entries: entries,
        today: LocalDate(2026, 10, 4),
        weeklyTarget: 3,
      );
      expect(sunday.weekStart, LocalDate(2026, 9, 28));
      expect(sunday.entryCount, 2);

      final monday = buildWorkoutWeekSummary(
        entries: entries,
        today: LocalDate(2026, 10, 5),
        weeklyTarget: 3,
      );
      expect(monday.weekStart, LocalDate(2026, 10, 5));
      expect(monday.entryCount, 1, reason: 'only 10-05 is in the new week');
      expect(monday.latest!.id, 'mon-after');
    });

    test('on a Monday the previous week is no longer shown', () {
      final summary = buildWorkoutWeekSummary(
        entries: [workout('last-week', LocalDate(2026, 10, 4))],
        today: LocalDate(2026, 10, 5),
        weeklyTarget: 3,
      );
      expect(summary.isEmpty, isTrue);
      expect(summary.latest, isNull);
      expect(summary.latestText, 'Noch kein Workout diese Woche');
      expect(summary.totalMinutes, 0);
    });

    test('the week of a daylight saving change still has seven calendar days', () {
      // Summer time ends on Sunday 2026-10-25 and starts on Sunday 2026-03-29.
      for (final change in [LocalDate(2026, 10, 25), LocalDate(2026, 3, 29)]) {
        final summary = buildWorkoutWeekSummary(
          entries: [
            workout('mon', change.addDays(-6)),
            workout('sun', change),
            workout('next', change.addDays(1)),
            workout('before', change.addDays(-7)),
          ],
          today: change,
          weeklyTarget: 3,
        );
        expect(summary.weekEnd, change);
        expect(summary.weekStart, change.addDays(-6));
        expect(summary.entryCount, 2, reason: '$change');
      }
    });

    test('the year boundary works with calendar arithmetic', () {
      // Thursday 2026-12-31: the week is Monday 12-28 to Sunday 2027-01-03.
      final summary = buildWorkoutWeekSummary(
        entries: [
          workout('a', LocalDate(2026, 12, 28)),
          workout('b', LocalDate(2027, 1, 3)),
          workout('c', LocalDate(2027, 1, 4)),
        ],
        today: LocalDate(2026, 12, 31),
        weeklyTarget: 3,
      );
      expect(summary.weekStart, LocalDate(2026, 12, 28));
      expect(summary.weekEnd, LocalDate(2027, 1, 3));
      expect(summary.entryCount, 2);
    });
  });

  group('count, minutes and the latest workout', () {
    test('counts the entries and sums their minutes', () {
      final summary = buildWorkoutWeekSummary(
        entries: [
          workout('a', LocalDate(2026, 9, 29), minutes: 30),
          workout('b', LocalDate(2026, 10, 1), minutes: 60),
          workout('c', saturday, minutes: 45),
          workout('old', LocalDate(2026, 9, 20), minutes: 999),
        ],
        today: saturday,
        weeklyTarget: 3,
      );
      expect(summary.entryCount, 3);
      expect(summary.totalMinutes, 135);
    });

    test('the latest workout is the one with the latest time, ties by id', () {
      final summary = buildWorkoutWeekSummary(
        entries: [
          workout('b', saturday, hour: 7),
          workout('a', saturday, hour: 9),
          workout('c', LocalDate(2026, 10, 1), hour: 20),
        ],
        today: saturday,
        weeklyTarget: 3,
      );
      expect(summary.latest!.id, 'a');

      final tie = buildWorkoutWeekSummary(
        entries: [workout('a', saturday), workout('b', saturday)],
        today: saturday,
        weeklyTarget: 3,
      );
      expect(tie.latest!.id, 'b', reason: 'same time: the larger id wins');
    });

    test('the latest text is the title or the category name', () {
      final withTitle = buildWorkoutWeekSummary(
        entries: [workout('a', saturday, title: 'Oberkörper A')],
        today: saturday,
        weeklyTarget: 3,
      );
      expect(withTitle.latestText, 'Oberkörper A');
      final withoutTitle = buildWorkoutWeekSummary(
        entries: [workout('a', saturday, category: TrainingCategory.cardio)],
        today: saturday,
        weeklyTarget: 3,
      );
      expect(withoutTitle.latestText, 'Cardio');
    });

    test('no workout this week: the honest empty message', () {
      final summary = buildWorkoutWeekSummary(
        entries: const [],
        today: saturday,
        weeklyTarget: 3,
      );
      expect(summary.entryCount, 0);
      expect(summary.latest, isNull);
      expect(summary.latestText, 'Noch kein Workout diese Woche');
      expect(summary.ringFraction, 0.0);
    });
  });

  group('weekly target and ring', () {
    WorkoutWeekSummary summaryFor(int count, int target) =>
        buildWorkoutWeekSummary(
          entries: [
            for (var i = 0; i < count; i++)
              workout('w$i', LocalDate(2026, 9, 28).addDays(i % 7), hour: i),
          ],
          today: saturday,
          weeklyTarget: target,
        );

    test('the ring is entries / target', () {
      expect(summaryFor(1, 3).ringFraction, closeTo(1 / 3, 1e-9));
      expect(summaryFor(2, 3).ringFraction, closeTo(2 / 3, 1e-9));
      expect(summaryFor(1, 14).ringFraction, closeTo(1 / 14, 1e-9));
    });

    test('the ring is capped at 100 percent, the real count stays', () {
      final reached = summaryFor(3, 3);
      expect(reached.ringFraction, 1.0);
      expect(reached.targetReached, isTrue);
      expect(reached.remainingToTarget, 0);
      final exceeded = summaryFor(5, 3);
      expect(exceeded.ringFraction, 1.0);
      expect(exceeded.entryCount, 5, reason: 'the actual number is shown');
      expect(exceeded.targetReached, isTrue);
      expect(exceeded.remainingToTarget, 0);
    });

    test('below the target: remaining entries are counted', () {
      final summary = summaryFor(1, 3);
      expect(summary.targetReached, isFalse);
      expect(summary.remainingToTarget, 2);
    });

    test('the target range is 1 to 14 entries', () {
      expect(summaryFor(14, 14).ringFraction, 1.0);
      expect(summaryFor(0, 1).ringFraction, 0.0);
      expect(summaryFor(1, 1).targetReached, isTrue);
    });
  });

  group('workoutWeeklyTargetOn', () {
    GoalVersion version(int target, LocalDate from, {bool enabled = true}) =>
        GoalVersion(
          type: GoalType.workoutWeekly,
          target: target,
          enabled: enabled,
          effectiveFrom: from,
        );

    test('defaults to 3 without a stored version', () {
      expect(workoutWeeklyTargetOn(const [], saturday), 3);
    });

    test('uses the version in effect on the day', () {
      final versions = [
        version(3, LocalDate(2026, 9, 1)),
        version(5, LocalDate(2026, 10, 3)),
        version(7, LocalDate(2026, 10, 4)),
      ];
      expect(workoutWeeklyTargetOn(versions, LocalDate(2026, 9, 30)), 3);
      expect(workoutWeeklyTargetOn(versions, saturday), 5);
      expect(workoutWeeklyTargetOn(versions, LocalDate(2026, 10, 4)), 7);
    });

    test('ignores other goal types and the enabled flag', () {
      final versions = [
        GoalVersion(
          type: GoalType.focusMinutes,
          target: 60,
          effectiveFrom: LocalDate(2026, 9, 1),
        ),
        version(2, LocalDate(2026, 9, 1), enabled: false),
      ];
      expect(workoutWeeklyTargetOn(versions, saturday), 2);
    });

    test('stays within 1 to 14', () {
      expect(
        workoutWeeklyTargetOn([version(0, LocalDate(2026, 9, 1))], saturday),
        1,
      );
      expect(
        workoutWeeklyTargetOn([version(99, LocalDate(2026, 9, 1))], saturday),
        14,
      );
      expect(
        workoutWeeklyTargetOn([version(14, LocalDate(2026, 9, 1))], saturday),
        14,
      );
    });
  });
}
