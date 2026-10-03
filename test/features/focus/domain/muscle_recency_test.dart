import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/muscle_recency.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

final LocalDate today = LocalDate(2026, 10, 3);

WorkoutEntry entry(
  LocalDate date,
  List<MuscleGroup> groups, {
  String id = 'w',
}) => WorkoutEntry(
  id: id,
  category: TrainingCategory.strength,
  durationMinutes: 45,
  muscleGroups: groups,
  occurredAtUtc: DateTime.utc(date.year, date.month, date.day, 12),
  localDate: date,
  timezoneId: 'Europe/Berlin',
  rowVersion: 1,
  gamificationEligible: false,
);

void main() {
  group('buildMuscleRecency', () {
    test('lists each trained group once with its latest day, newest first', () {
      final result = buildMuscleRecency([
        entry(LocalDate(2026, 9, 29), [MuscleGroup.legs, MuscleGroup.core]),
        entry(LocalDate(2026, 10, 3), [MuscleGroup.chest, MuscleGroup.core]),
        entry(LocalDate(2026, 10, 1), [MuscleGroup.chest]),
      ], today);
      expect(
        [for (final r in result) (r.group, r.lastTrained.toIso())],
        [
          (MuscleGroup.chest, '2026-10-03'),
          (MuscleGroup.core, '2026-10-03'),
          (MuscleGroup.legs, '2026-09-29'),
        ],
        reason: 'ties keep the canonical order (chest before core)',
      );
    });

    test(
      'a workout without muscle groups names nothing (nothing is guessed)',
      () {
        expect(
          buildMuscleRecency([entry(LocalDate(2026, 10, 3), const [])], today),
          isEmpty,
        );
      },
    );

    test('only the last 28 days count, both edges', () {
      final inside = today.addDays(-(muscleRecencyWindowDays - 1));
      final outside = inside.addDays(-1);
      expect(
        buildMuscleRecency([
          entry(inside, [MuscleGroup.back]),
        ], today).map((r) => r.group),
        [MuscleGroup.back],
      );
      expect(
        buildMuscleRecency([
          entry(outside, [MuscleGroup.back]),
        ], today),
        isEmpty,
      );
    });

    test('entries after today are ignored', () {
      expect(
        buildMuscleRecency([
          entry(today.addDays(1), [MuscleGroup.back]),
        ], today),
        isEmpty,
      );
    });

    test('fresh means at most three days ago', () {
      MuscleRecency at(int daysAgo) => MuscleRecency(
        group: MuscleGroup.legs,
        lastTrained: today.addDays(-daysAgo),
      );
      expect(at(0).daysAgo(today), 0);
      expect(at(3).isFresh(today), isTrue);
      expect(at(4).isFresh(today), isFalse);
    });
  });
}
