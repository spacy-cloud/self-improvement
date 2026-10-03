import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_intensity.dart';
import 'package:self_improvement/features/focus/domain/workout_validation.dart';

void main() {
  setUpAll(TimeZones.ensureInitialized);

  group('parseWorkoutMinutes', () {
    int? parsed(String input) => switch (parseWorkoutMinutes(input)) {
      WorkoutMinutesParsed(:final minutes) => minutes,
      WorkoutMinutesInvalid() => null,
    };

    WorkoutMinutesError? error(String input) =>
        switch (parseWorkoutMinutes(input)) {
          WorkoutMinutesParsed() => null,
          WorkoutMinutesInvalid(:final error) => error,
        };

    test('accepts whole minutes from 1 to 600', () {
      expect(parsed('1'), 1);
      expect(parsed('45'), 45);
      expect(parsed('60'), 60);
      expect(parsed('600'), 600);
      expect(parsed('  45  '), 45, reason: 'surrounding spaces are trimmed');
      expect(parsed('045'), 45, reason: 'leading zeros are harmless');
    });

    test('rejects an empty input', () {
      expect(error(''), WorkoutMinutesError.empty);
      expect(error('   '), WorkoutMinutesError.empty);
    });

    test('rejects anything that is not a plain whole number', () {
      for (final bad in [
        'abc',
        '45,5',
        '45.5',
        '-5',
        '+5',
        '1e2',
        '4 5',
        '1.000',
        'NaN',
        '０',
        '45min',
      ]) {
        expect(error(bad), WorkoutMinutesError.invalidFormat, reason: bad);
      }
    });

    test('0 is below, 601 above the limits; both sides of each limit', () {
      expect(error('0'), WorkoutMinutesError.belowMinimum);
      expect(error('000'), WorkoutMinutesError.belowMinimum);
      expect(parsed('1'), 1);
      expect(parsed('600'), 600);
      expect(error('601'), WorkoutMinutesError.aboveMaximum);
      expect(error('99999'), WorkoutMinutesError.aboveMaximum);
      expect(
        error('123456789012345678901234567890'),
        WorkoutMinutesError.aboveMaximum,
        reason: 'absurdly long input never overflows',
      );
    });

    test('the German messages', () {
      expect(
        workoutMinutesErrorMessage(WorkoutMinutesError.empty),
        'Bitte gib die Dauer in Minuten ein.',
      );
      expect(
        workoutMinutesErrorMessage(WorkoutMinutesError.invalidFormat),
        'Bitte gib eine ganze Zahl ein, zum Beispiel 45.',
      );
      const range = 'Bitte gib eine Dauer zwischen 1 und 600 Minuten ein.';
      expect(
        workoutMinutesErrorMessage(WorkoutMinutesError.belowMinimum),
        range,
      );
      expect(
        workoutMinutesErrorMessage(WorkoutMinutesError.aboveMaximum),
        range,
      );
    });
  });

  group('stepWorkoutMinutes', () {
    test('steps by 5 minutes from a valid value', () {
      expect(stepWorkoutMinutes(currentText: '45', direction: 1), 50);
      expect(stepWorkoutMinutes(currentText: '45', direction: -1), 40);
    });

    test('is clamped to 1 and 600', () {
      expect(stepWorkoutMinutes(currentText: '3', direction: -1), 1);
      expect(stepWorkoutMinutes(currentText: '1', direction: -1), 1);
      expect(stepWorkoutMinutes(currentText: '598', direction: 1), 600);
      expect(stepWorkoutMinutes(currentText: '600', direction: 1), 600);
    });

    test('from an empty or invalid text the first press shows 30 minutes', () {
      expect(stepWorkoutMinutes(currentText: '', direction: 1), 30);
      expect(stepWorkoutMinutes(currentText: '', direction: -1), 30);
      expect(stepWorkoutMinutes(currentText: 'abc', direction: 1), 30);
      expect(stepWorkoutMinutes(currentText: '0', direction: 1), 30);
    });

    test('the constants match the design', () {
      expect(workoutDurationStepMinutes, 5);
      expect(workoutDurationStartMinutes, 30);
      expect(minWorkoutMinutes, 1);
      expect(maxWorkoutMinutes, 600);
      expect(maxWorkoutTitleLength, 80);
      expect(maxWorkoutNoteLength, 500);
    });
  });

  group('validateWorkoutDraft', () {
    // 2026-10-03 08:00Z = 10:00 in Berlin.
    final now = DateTime.utc(2026, 10, 3, 8);
    final clock = FakeClock(now);

    WorkoutDraft draft({
      TrainingCategory category = TrainingCategory.strength,
      int minutes = 45,
      DateTime? at,
      String? title,
      List<MuscleGroup> groups = const [],
      WorkoutIntensity? intensity,
      String? note,
    }) => WorkoutDraft(
      category: category,
      durationMinutes: minutes,
      occurredAtUtc: at ?? DateTime.utc(2026, 10, 3, 7),
      title: title,
      muscleGroups: groups,
      intensity: intensity,
      note: note,
    );

    WorkoutDraft validate(WorkoutDraft d) =>
        validateWorkoutDraft(d, nowUtc: now, clock: clock);

    ValidationFailure failure(WorkoutDraft d) {
      try {
        validate(d);
      } on ValidationFailure catch (error) {
        return error;
      }
      fail('expected a ValidationFailure');
    }

    test('a minimal draft is valid and gets no invented optional values', () {
      final result = validate(draft());
      expect(result.title, isNull);
      expect(result.muscleGroups, isEmpty);
      expect(result.intensity, isNull);
      expect(result.note, isNull);
      expect(result.durationMinutes, 45);
      expect(result.category, TrainingCategory.strength);
    });

    test('duration: 1 and 600 are valid, 0 and 601 are rejected', () {
      validate(draft(minutes: 1));
      validate(draft(minutes: 600));
      for (final bad in [0, 601, -1, 100000]) {
        expect(
          failure(draft(minutes: bad)).fieldErrors[WorkoutFields.duration],
          'Bitte gib eine Dauer zwischen 1 und 600 Minuten ein.',
          reason: '$bad',
        );
      }
    });

    test('title: 80 characters are valid, 81 are rejected', () {
      expect(validate(draft(title: 'x' * 80)).title, 'x' * 80);
      expect(
        failure(draft(title: 'x' * 81)).fieldErrors[WorkoutFields.title],
        'Der Titel darf höchstens 80 Zeichen lang sein.',
      );
    });

    test('title: the limit applies after trimming and counts characters', () {
      expect(validate(draft(title: ' ${'x' * 80} ')).title, 'x' * 80);
      expect(validate(draft(title: '😀' * 80)).title, '😀' * 80);
      expect(failure(draft(title: '😀' * 81)).fieldErrors.keys, [
        WorkoutFields.title,
      ]);
    });

    test('a blank title becomes null (the category name is displayed)', () {
      expect(validate(draft(title: '')).title, isNull);
      expect(validate(draft(title: '   ')).title, isNull);
      expect(validate(draft(title: '  Beine  ')).title, 'Beine');
    });

    test('note: 500 are valid, 501 are rejected, blank becomes null', () {
      expect(validate(draft(note: 'n' * 500)).note, 'n' * 500);
      expect(
        failure(draft(note: 'n' * 501)).fieldErrors[WorkoutFields.note],
        'Die Notiz darf höchstens 500 Zeichen lang sein.',
      );
      expect(validate(draft(note: '  ')).note, isNull);
      expect(validate(draft(note: ' ok ')).note, 'ok');
    });

    test(
      'time: not in the future (now is valid, one millisecond later is not)',
      () {
        validate(draft(at: now));
        expect(
          failure(draft(at: now.add(const Duration(milliseconds: 1))))
              .fieldErrors[WorkoutFields.occurredAt],
          'Der Zeitpunkt darf nicht in der Zukunft liegen.',
        );
      },
    );

    test('time: not before 2000-01-01 in the device zone', () {
      // 1999-12-31T22:59Z is 23:59 on New Year's Eve in Berlin.
      expect(
        failure(draft(at: DateTime.utc(1999, 12, 31, 22, 59)))
            .fieldErrors[WorkoutFields.occurredAt],
        'Das Datum darf nicht vor dem 01.01.2000 liegen.',
      );
      validate(draft(at: DateTime.utc(1999, 12, 31, 23)));
      validate(draft(at: DateTime.utc(2000)));
    });

    test('muscle groups are deduplicated and put in canonical order', () {
      final result = validate(
        draft(
          groups: [
            MuscleGroup.triceps,
            MuscleGroup.chest,
            MuscleGroup.triceps,
            MuscleGroup.fullBody,
          ],
        ),
      );
      expect(result.muscleGroups, [
        MuscleGroup.chest,
        MuscleGroup.triceps,
        MuscleGroup.fullBody,
      ]);
    });

    test('every category and intensity is accepted', () {
      for (final category in TrainingCategory.values) {
        expect(validate(draft(category: category)).category, category);
      }
      for (final intensity in WorkoutIntensity.values) {
        expect(validate(draft(intensity: intensity)).intensity, intensity);
      }
    });

    test('several errors are reported together', () {
      final error = failure(
        draft(
          minutes: 0,
          at: now.add(const Duration(hours: 1)),
          title: 'x' * 81,
          note: 'n' * 501,
        ),
      );
      expect(
        error.fieldErrors.keys,
        containsAll([
          WorkoutFields.duration,
          WorkoutFields.occurredAt,
          WorkoutFields.title,
          WorkoutFields.note,
        ]),
      );
    });
  });
}
