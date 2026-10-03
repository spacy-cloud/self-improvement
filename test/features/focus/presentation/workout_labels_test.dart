import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/muscle_recency.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_intensity.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';
import 'package:self_improvement/features/focus/presentation/workout_labels.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Saturday 2026-10-03, 10:00 in Berlin.
final FakeClock clock = FakeClock.at('2026-10-03T08:00:00Z');
final LocalDate today = LocalDate(2026, 10, 3);

WorkoutEntry workout({
  TrainingCategory category = TrainingCategory.strength,
  String? title,
  int minutes = 60,
  List<MuscleGroup> groups = const [],
  WorkoutIntensity? intensity,
  DateTime? at,
  LocalDate? date,
  String zone = 'Europe/Berlin',
}) {
  final instant = at ?? DateTime.utc(2026, 10, 3, 15, 30);
  return WorkoutEntry(
    id: 'w1',
    category: category,
    title: title,
    durationMinutes: minutes,
    muscleGroups: groups,
    intensity: intensity,
    occurredAtUtc: instant,
    localDate: date ?? clock.localDateOf(instant, timeZoneId: zone),
    timezoneId: zone,
    rowVersion: 1,
    gamificationEligible: false,
  );
}

WorkoutWeekSummary week({int count = 2, int minutes = 105, int target = 3}) =>
    WorkoutWeekSummary(
      weekStart: LocalDate(2026, 9, 28),
      entryCount: count,
      totalMinutes: minutes,
      weeklyTarget: target,
    );

void main() {
  group('workout rows', () {
    test('the meta line names category, minutes and a chosen intensity', () {
      expect(
        workoutMetaLine(workout(intensity: WorkoutIntensity.moderate)),
        'Kraft · 60 Min. · Mittel',
      );
      expect(
        workoutMetaLine(
          workout(category: TrainingCategory.cardio, minutes: 30),
        ),
        'Cardio · 30 Min.',
        reason: 'no intensity chosen: nothing is invented',
      );
    });

    test('the list subtitle starts with the date', () {
      expect(
        workoutListSubtitle(
          workout(
            date: LocalDate(2026, 9, 14),
            intensity: WorkoutIntensity.high,
          ),
          today,
        ),
        'Mo., 14. Sep. · Kraft · Hart',
      );
    });

    test('"when" is relative within the week and a date beyond it', () {
      expect(workoutWhenText(workout(), today, clock), 'Heute · 17:30');
      expect(
        workoutWhenText(
          workout(at: DateTime.utc(2026, 10, 2, 16, 10)),
          today,
          clock,
        ),
        'Gestern · 18:10',
      );
      expect(
        workoutWhenText(
          workout(at: DateTime.utc(2026, 9, 29, 16, 10)),
          today,
          clock,
        ),
        'Dienstag · 18:10',
      );
      expect(
        workoutWhenText(workout(at: DateTime.utc(2026, 9, 7, 5)), today, clock),
        'Mo., 7. Sep. · 07:00',
      );
    });

    test('the time is shown in the zone the workout was logged in (AT25)', () {
      final entry = workout(
        at: DateTime.utc(2026, 10, 3, 6, 30),
        zone: 'Asia/Tokyo',
      );
      expect(workoutTime(clock, entry), '15:30');
      // The device zone changes later; the stored zone still wins.
      final travelling = FakeClock.at(
        '2026-10-03T08:00:00Z',
        timeZoneId: 'America/New_York',
      );
      expect(workoutTime(travelling, entry), '15:30');
    });

    test('an entry without a title shows the category name', () {
      expect(
        workout(category: TrainingCategory.mobility).displayTitle,
        'Mobility',
      );
      expect(workout(title: 'Upper Body').displayTitle, 'Upper Body');
    });

    test(
      'muscle groups are listed in the canonical order, none gives null',
      () {
        expect(muscleGroupsText(const []), isNull);
        expect(
          muscleGroupsText([MuscleGroup.chest, MuscleGroup.triceps]),
          'Brust, Trizeps',
        );
      },
    );

    test(
      'a screen reader hears title, category, minutes, muscles and time',
      () {
        expect(
          workoutSpoken(
            workout(
              title: 'Upper Body',
              groups: [MuscleGroup.chest, MuscleGroup.back],
              intensity: WorkoutIntensity.moderate,
            ),
            today,
            clock,
          ),
          'Upper Body, Kraft, 60 Minuten, Mittel, Brust, Rücken, '
          'Heute, 17:30 Uhr',
        );
      },
    );
  });

  group('week labels', () {
    test('this week, last week and older weeks as a range', () {
      expect(weekGroupLabel(LocalDate(2026, 9, 28), today), 'Diese Woche');
      expect(weekGroupLabel(LocalDate(2026, 9, 21), today), 'Letzte Woche');
      expect(
        weekGroupLabel(LocalDate(2026, 9, 7), today),
        '7. Sep. – 13. Sep.',
      );
      expect(
        weekGroupLabel(LocalDate(2026, 12, 28), LocalDate(2027, 1, 2)),
        'Diese Woche',
        reason: 'the Monday of the week lies in the old year',
      );
    });

    test('what is missing to the goal, singular and plural', () {
      expect(
        workoutRemainingText(week(count: 2, target: 3)),
        '1 fehlt zum Ziel',
      );
      expect(
        workoutRemainingText(week(count: 1, target: 3)),
        '2 fehlen zum Ziel',
      );
      expect(workoutRemainingText(week(count: 3, target: 3)), 'Ziel erreicht');
      expect(workoutRemainingText(week(count: 5, target: 3)), 'Ziel erreicht');
    });

    test(
      'the average is rounded to whole minutes and absent without entries',
      () {
        expect(workoutAverageMinutes(week(count: 2, minutes: 105)), 53);
        expect(workoutAverageMinutes(week(count: 3, minutes: 100)), 33);
        expect(workoutAverageMinutes(week(count: 0, minutes: 0)), isNull);
      },
    );

    test('the spoken week keeps the real count, never a capped one (F03)', () {
      expect(
        workoutWeekSpoken(week(count: 2)),
        'Diese Woche 2 von 3 Trainings, 105 Minuten. 1 fehlt zum Ziel.',
      );
      expect(
        workoutWeekSpoken(week(count: 5, minutes: 240)),
        'Diese Woche 5 von 3 Trainings, 240 Minuten. Wochenziel erreicht.',
      );
    });
  });

  group('muscle recency', () {
    test('today, yesterday and older days', () {
      expect(lastTrainedText(0), 'heute');
      expect(lastTrainedText(1), 'gestern');
      expect(lastTrainedText(4), 'vor 4 Tagen');
      expect(
        muscleRecencySpoken(
          MuscleRecency(
            group: MuscleGroup.legs,
            lastTrained: LocalDate(2026, 9, 29),
          ),
          today,
        ),
        'Beine, zuletzt vor 4 Tagen',
      );
    });
  });
}
