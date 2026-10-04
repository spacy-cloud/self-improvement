import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_groups.dart';
import 'package:self_improvement/shared/local_date.dart';

WorkoutEntry entry(String id, LocalDate date, {int minutes = 30}) =>
    WorkoutEntry(
      id: id,
      category: TrainingCategory.cardio,
      durationMinutes: minutes,
      occurredAtUtc: DateTime.utc(date.year, date.month, date.day, 12),
      localDate: date,
      timezoneId: 'Europe/Berlin',
      rowVersion: 1,
      gamificationEligible: false,
    );

void main() {
  group('groupWorkoutsByWeek', () {
    test('Sunday belongs to the week that started on Monday', () {
      final groups = groupWorkoutsByWeek([
        entry('mon-next', LocalDate(2026, 10, 5)),
        entry('sun', LocalDate(2026, 10, 4)),
        entry('mon', LocalDate(2026, 9, 28)),
        entry('sun-before', LocalDate(2026, 9, 27)),
      ]);
      expect(
        [for (final g in groups) (g.weekStart.toIso(), g.weekEnd.toIso())],
        [
          ('2026-10-05', '2026-10-11'),
          ('2026-09-28', '2026-10-04'),
          ('2026-09-21', '2026-09-27'),
        ],
      );
      expect(
        [
          for (final g in groups) [for (final e in g.entries) e.id],
        ],
        [
          ['mon-next'],
          ['sun', 'mon'],
          ['sun-before'],
        ],
      );
    });

    test('a week across the new year is one group', () {
      final groups = groupWorkoutsByWeek([
        entry('jan', LocalDate(2027, 1, 1)),
        entry('dec', LocalDate(2026, 12, 29)),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.weekStart, LocalDate(2026, 12, 28));
      expect(groups.single.weekEnd, LocalDate(2027, 1, 3));
    });

    test(
      'the minutes of a week are summed and an empty list gives no group',
      () {
        final groups = groupWorkoutsByWeek([
          entry('a', LocalDate(2026, 10, 1), minutes: 45),
          entry('b', LocalDate(2026, 9, 30), minutes: 60),
        ]);
        expect(groups.single.totalMinutes, 105);
        expect(groupWorkoutsByWeek(const []), isEmpty);
      },
    );
  });
}
