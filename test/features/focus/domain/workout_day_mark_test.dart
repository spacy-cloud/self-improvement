import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_daily_goal.dart';
import 'package:self_improvement/features/focus/domain/workout_day_mark.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The pure rules of "Wie war dein Tag?" (BS-99): what a day with a workout, a
/// rest day mark or a skipped mark is, which one wins, and the plan of the
/// daily goal.
void main() {
  final today = LocalDate(2026, 10, 3);

  WorkoutEntry workout(
    String id, {
    LocalDate? date,
    int hour = 8,
    String? title,
  }) => WorkoutEntry(
    id: id,
    category: TrainingCategory.strength,
    durationMinutes: 45,
    occurredAtUtc: DateTime.utc(2026, 10, 3, hour),
    localDate: date ?? today,
    timezoneId: 'Europe/Berlin',
    rowVersion: 1,
    gamificationEligible: true,
    title: title,
  );

  WorkoutDayMark mark(
    WorkoutDayMarkKind kind, {
    LocalDate? date,
    String id = 'm1',
  }) => WorkoutDayMark(
    id: id,
    date: date ?? today,
    kind: kind,
    timezoneId: 'Europe/Berlin',
    rowVersion: 1,
  );

  group('WorkoutDayMarkKind', () {
    test('(BS-99) the keys are exactly the persisted keys of the schema', () {
      expect(
        WorkoutDayMarkKind.values.map((kind) => kind.key).toList(),
        SchemaKeys.workoutDayMarkKinds,
      );
    });

    test(
      '(BS-99) tryParse maps every key back and rejects everything else',
      () {
        for (final kind in WorkoutDayMarkKind.values) {
          expect(WorkoutDayMarkKind.tryParse(kind.key), kind);
        }
        for (final bad in ['', 'Rest', 'rest ', 'skip', 'trained', 'open']) {
          expect(WorkoutDayMarkKind.tryParse(bad), isNull, reason: bad);
        }
      },
    );
  });

  group('WorkoutDayState', () {
    test('(BS-99) a day without a workout and without a mark is open', () {
      final state = buildWorkoutDayState(date: today, workouts: const []);
      expect(state.outcome, WorkoutDayOutcome.open);
      expect(state.fulfilled, isFalse);
      expect(state.latest, isNull);
      expect(state.takeBackMark, isNull);
    });

    test('(BS-99) one workout makes it a training day', () {
      final state = buildWorkoutDayState(
        date: today,
        workouts: [workout('w1')],
      );
      expect(state.outcome, WorkoutDayOutcome.trained);
      expect(state.fulfilled, isTrue);
      expect(state.latest!.id, 'w1');
    });

    test('(BS-99) a mark without a workout is a rest day or a skipped day', () {
      final rest = buildWorkoutDayState(
        date: today,
        workouts: const [],
        mark: mark(WorkoutDayMarkKind.rest),
      );
      expect(rest.outcome, WorkoutDayOutcome.rest);
      expect(rest.fulfilled, isTrue);
      expect(rest.takeBackMark!.id, 'm1');

      final skipped = buildWorkoutDayState(
        date: today,
        workouts: const [],
        mark: mark(WorkoutDayMarkKind.skipped),
      );
      expect(skipped.outcome, WorkoutDayOutcome.skipped);
      expect(skipped.fulfilled, isTrue);
    });

    test(
      '(BS-99) a workout wins over a mark; the mark stays and applies again',
      () {
        final both = buildWorkoutDayState(
          date: today,
          workouts: [workout('w1')],
          mark: mark(WorkoutDayMarkKind.rest),
        );
        expect(both.outcome, WorkoutDayOutcome.trained);
        expect(both.mark, isNotNull, reason: 'the mark stays stored');
        expect(both.takeBackMark, isNull, reason: 'it does not decide the day');

        final workoutDeleted = buildWorkoutDayState(
          date: today,
          workouts: const [],
          mark: mark(WorkoutDayMarkKind.rest),
        );
        expect(workoutDeleted.outcome, WorkoutDayOutcome.rest);
      },
    );

    test('(BS-99) only the workouts and the mark of that day count', () {
      final state = buildWorkoutDayState(
        date: today,
        workouts: [
          workout('yesterday', date: today.addDays(-1)),
          workout('tomorrow', date: today.addDays(1)),
        ],
        mark: mark(WorkoutDayMarkKind.rest, date: today.addDays(-1)),
      );
      expect(state.outcome, WorkoutDayOutcome.open);
      expect(state.workouts, isEmpty);
      expect(state.mark, isNull);
    });

    test('(BS-99) the latest workout is the newest by time, then by id', () {
      final state = buildWorkoutDayState(
        date: today,
        workouts: [
          workout('a', hour: 7),
          workout('c', hour: 18),
          workout('b', hour: 18),
        ],
      );
      expect([for (final entry in state.workouts) entry.id], ['c', 'b', 'a']);
      expect(state.latest!.id, 'c');
    });

    test('(BS-99) the number of workouts of the week plays no part', () {
      // The state knows one day only: it cannot depend on a weekly count.
      final one = buildWorkoutDayState(date: today, workouts: [workout('w1')]);
      final three = buildWorkoutDayState(
        date: today,
        workouts: [
          workout('w1'),
          workout('w2', hour: 9),
          workout('w3', hour: 10),
        ],
      );
      expect(one.fulfilled, isTrue);
      expect(three.fulfilled, isTrue);
    });

    test('(BS-99) equal states are equal', () {
      WorkoutDayState state() => buildWorkoutDayState(
        date: today,
        workouts: [workout('w1')],
        mark: mark(WorkoutDayMarkKind.skipped),
      );
      expect(state(), state());
      expect(state().hashCode, state().hashCode);
      expect(
        state(),
        isNot(buildWorkoutDayState(date: today, workouts: const [])),
      );
    });
  });

  group('WorkoutDailyGoalPlan', () {
    GoalVersion version(LocalDate from, {required bool enabled}) => GoalVersion(
      type: GoalType.workoutDaily,
      enabled: enabled,
      effectiveFrom: from,
    );

    test('(BS-99) without a version the goal is off today and tomorrow', () {
      final plan = workoutDailyGoalPlanOn(const [], today);
      expect(plan.today, isFalse);
      expect(plan.tomorrow, isFalse);
      expect(plan.hasPendingChange, isFalse);
    });

    test('(BS-99) a version from tomorrow is a pending change: off today, on tomorrow', () {
      final plan = workoutDailyGoalPlanOn([
        version(today.addDays(1), enabled: true),
      ], today);
      expect(plan.today, isFalse);
      expect(plan.tomorrow, isTrue);
      expect(plan.hasPendingChange, isTrue);
    });

    test('(BS-99) a version from today is on today and tomorrow', () {
      final plan = workoutDailyGoalPlanOn([
        version(today, enabled: true),
      ], today);
      expect(plan, const WorkoutDailyGoalPlan(today: true, tomorrow: true));
    });

    test('(BS-99) switching it off from tomorrow is a pending change too', () {
      final plan = workoutDailyGoalPlanOn([
        version(today.addDays(-5), enabled: true),
        version(today.addDays(1), enabled: false),
      ], today);
      expect(plan.today, isTrue);
      expect(plan.tomorrow, isFalse);
      expect(plan.hasPendingChange, isTrue);
    });
  });
}
