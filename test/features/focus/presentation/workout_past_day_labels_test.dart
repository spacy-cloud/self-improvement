import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_day_mark.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/presentation/workout_labels.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The words of the Workout card for a day that is not today (BS-93): what the
/// day was, from its workouts and its mark; a day without either is a dash and
/// "Kein Training eingetragen", not a zero.
void main() {
  final day = LocalDate(2026, 10, 1);

  WorkoutEntry workout(
    String id, {
    String? title,
    int hour = 8,
    List<MuscleGroup> groups = const <MuscleGroup>[],
  }) => WorkoutEntry(
    id: id,
    category: TrainingCategory.strength,
    durationMinutes: 45,
    occurredAtUtc: DateTime.utc(2026, 10, 1, hour),
    localDate: day,
    timezoneId: 'Europe/Berlin',
    rowVersion: 1,
    gamificationEligible: true,
    title: title,
    muscleGroups: groups,
  );

  WorkoutDayState state({
    List<WorkoutEntry> workouts = const <WorkoutEntry>[],
    WorkoutDayMarkKind? kind,
  }) => buildWorkoutDayState(
    date: day,
    workouts: workouts,
    mark: kind == null
        ? null
        : WorkoutDayMark(
            id: 'm',
            date: day,
            kind: kind,
            timezoneId: 'Europe/Berlin',
            rowVersion: 1,
          ),
  );

  test('(BS-93) a day without a workout and a mark is a dash and says so', () {
    final open = state();
    expect(workoutPastDayValue(open), '–');
    expect(workoutPastDayCaption(open), 'Kein Training eingetragen');
    expect(workoutPastDaySpoken(open), 'Kein Training eingetragen');
  });

  test('(BS-93) a workout shows its title and its muscle groups', () {
    final trained = state(
      workouts: <WorkoutEntry>[
        workout(
          'a',
          title: 'Oberkörper',
          groups: <MuscleGroup>[MuscleGroup.chest, MuscleGroup.shoulders],
        ),
      ],
    );
    expect(workoutPastDayValue(trained), 'Oberkörper');
    expect(workoutPastDayCaption(trained), 'Brust, Schultern');
    expect(workoutPastDaySpoken(trained), 'Oberkörper, Brust, Schultern');
  });

  test(
    '(BS-93) a workout without groups shows its kind, duration and so on',
    () {
      final trained = state(
        workouts: <WorkoutEntry>[workout('a', title: 'Runde')],
      );
      expect(workoutPastDayCaption(trained), 'Kraft · 45 Min.');
    },
  );

  test('(BS-93) several workouts say how many the day had; the title is the '
      'newest one', () {
    final trained = state(
      workouts: <WorkoutEntry>[
        workout('a', title: 'Morgens', hour: 6),
        workout('b', title: 'Abends', hour: 17),
      ],
    );
    expect(workoutPastDayValue(trained), 'Abends');
    expect(workoutPastDayCaption(trained), '2 Trainings an diesem Tag');
  });

  test('(BS-93) a rest day and a skipped day are named, with what they are '
      'worth', () {
    final rest = state(kind: WorkoutDayMarkKind.rest);
    final skipped = state(kind: WorkoutDayMarkKind.skipped);
    expect(workoutPastDayValue(rest), 'Ruhetag');
    expect(workoutPastDayValue(skipped), 'Übersprungen');
    expect(workoutPastDayCaption(rest), workoutDayMarkCounts);
    expect(workoutPastDayCaption(skipped), workoutDayMarkCounts);
    expect(
      workoutPastDaySpoken(rest),
      'Ruhetag, Zählt als erreicht, keine XP. Die Streak bleibt.',
    );
  });

  test('(BS-93) a workout wins over a mark of the same day', () {
    final both = state(
      workouts: <WorkoutEntry>[workout('a', title: 'Lauf')],
      kind: WorkoutDayMarkKind.rest,
    );
    expect(workoutPastDayValue(both), 'Lauf');
  });

  test('(BS-93) nothing says "heute"', () {
    for (final s in <WorkoutDayState>[
      state(),
      state(workouts: <WorkoutEntry>[workout('a'), workout('b', hour: 9)]),
      state(kind: WorkoutDayMarkKind.rest),
    ]) {
      expect(workoutPastDayCaption(s), isNot(contains('heute')));
    }
  });
}
