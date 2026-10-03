import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_intensity.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  group('TrainingCategory', () {
    test('the keys equal the persisted schema contract, in the same order', () {
      expect(
        TrainingCategory.values.map((c) => c.key).toList(),
        SchemaKeys.trainingCategories,
      );
    });

    test('the German names are Kraft, Cardio, Mobility and Sport', () {
      expect(
        {for (final c in TrainingCategory.values) c.key: c.label},
        {
          'strength': 'Kraft',
          'cardio': 'Cardio',
          'mobility': 'Mobility',
          'sport': 'Sport',
        },
      );
    });

    test('the old visible types are not categories', () {
      for (final old in ['upper_body', 'lower_body', 'full_body', 'other']) {
        expect(TrainingCategory.tryParse(old), isNull, reason: old);
      }
      expect(() => TrainingCategory.fromKey('upper_body'), throwsArgumentError);
    });

    test('parsing round-trips every key', () {
      for (final category in TrainingCategory.values) {
        expect(TrainingCategory.tryParse(category.key), category);
        expect(TrainingCategory.fromKey(category.key), category);
      }
    });
  });

  group('MuscleGroup', () {
    test('the keys equal the persisted schema contract, in the same order', () {
      expect(
        MuscleGroup.values.map((g) => g.key).toList(),
        SchemaKeys.muscleGroups,
      );
    });

    test('the single mapping table gives the German labels of the design', () {
      expect(
        {for (final g in MuscleGroup.values) g.key: g.label},
        {
          'chest': 'Brust',
          'shoulders': 'Schultern',
          'back': 'Rücken',
          'biceps': 'Bizeps',
          'triceps': 'Trizeps',
          'legs': 'Beine',
          'core': 'Core',
          'full_body': 'Ganzkörper',
        },
      );
    });

    test('normalize removes duplicates and sorts into the canonical order', () {
      expect(
        MuscleGroup.normalize([
          MuscleGroup.triceps,
          MuscleGroup.chest,
          MuscleGroup.triceps,
          MuscleGroup.back,
          MuscleGroup.chest,
        ]),
        [MuscleGroup.chest, MuscleGroup.back, MuscleGroup.triceps],
      );
      expect(MuscleGroup.normalize(const []), isEmpty);
      expect(
        MuscleGroup.normalize(MuscleGroup.values.reversed),
        MuscleGroup.values,
      );
    });

    test('the normalised list cannot be modified', () {
      final groups = MuscleGroup.normalize([MuscleGroup.core]);
      expect(() => groups.add(MuscleGroup.legs), throwsUnsupportedError);
    });

    test('fromKeys drops unknown keys and duplicates', () {
      expect(
        MuscleGroup.fromKeys(['legs', 'abs', 'chest', 'legs', '', 'Chest']),
        [MuscleGroup.chest, MuscleGroup.legs],
      );
      expect(MuscleGroup.fromKeys(const []), isEmpty);
    });

    test('parsing accepts the keys only', () {
      for (final group in MuscleGroup.values) {
        expect(MuscleGroup.tryParse(group.key), group);
      }
      expect(MuscleGroup.tryParse('fullBody'), isNull);
      expect(
        MuscleGroup.tryParse('Brust'),
        isNull,
        reason: 'labels are no keys',
      );
    });
  });

  group('WorkoutIntensity', () {
    test('the keys equal the persisted schema contract, in the same order', () {
      expect(
        WorkoutIntensity.values.map((i) => i.key).toList(),
        SchemaKeys.workoutIntensities,
      );
    });

    test('the German names are Leicht, Mittel and Hart', () {
      expect(
        {for (final i in WorkoutIntensity.values) i.key: i.label},
        {'low': 'Leicht', 'moderate': 'Mittel', 'high': 'Hart'},
      );
    });

    test('parsing accepts the keys only', () {
      for (final intensity in WorkoutIntensity.values) {
        expect(WorkoutIntensity.tryParse(intensity.key), intensity);
      }
      expect(WorkoutIntensity.tryParse('medium'), isNull);
      expect(WorkoutIntensity.tryParse('Mittel'), isNull);
    });
  });

  group('WorkoutEntry.displayTitle', () {
    WorkoutEntry entry({String? title, TrainingCategory? category}) =>
        WorkoutEntry(
          id: 'w',
          category: category ?? TrainingCategory.strength,
          title: title,
          durationMinutes: 45,
          occurredAtUtc: DateTime.utc(2026, 10, 3, 8),
          localDate: LocalDate(2026, 10, 3),
          timezoneId: 'Europe/Berlin',
          rowVersion: 1,
          gamificationEligible: true,
        );

    test('without a title the German category name is displayed', () {
      expect(entry().displayTitle, 'Kraft');
      expect(entry(category: TrainingCategory.cardio).displayTitle, 'Cardio');
      expect(
        entry(category: TrainingCategory.mobility).displayTitle,
        'Mobility',
      );
      expect(entry(category: TrainingCategory.sport).displayTitle, 'Sport');
    });

    test('a blank title also falls back to the category name', () {
      expect(entry(title: '').displayTitle, 'Kraft');
      expect(entry(title: '   ').displayTitle, 'Kraft');
    });

    test('a custom title wins', () {
      expect(entry(title: 'Oberkörper A').displayTitle, 'Oberkörper A');
    });

    test('entries are values', () {
      expect(entry(title: 'a'), entry(title: 'a'));
      expect(entry(title: 'a').hashCode, entry(title: 'a').hashCode);
      expect(entry(title: 'a'), isNot(entry(title: 'b')));
    });
  });
}
