import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/meal_validation.dart';

void main() {
  // "now" is 2026-10-03 08:00Z = 10:00 in Berlin.
  final clock = FakeClock.at('2026-10-03T08:00:00Z');
  final now = clock.nowUtc();

  MealDraft draft({
    String name = 'Haferflocken',
    int? kcal,
    DateTime? when,
    String? note,
  }) => MealDraft(
    name: name,
    kcal: kcal,
    occurredAtUtc: when ?? DateTime.utc(2026, 10, 3, 6),
    note: note,
  );

  MealDraft validate(MealDraft d) =>
      validateMealDraft(d, nowUtc: now, clock: clock);

  ValidationFailure failure(MealDraft d) {
    try {
      validate(d);
    } on ValidationFailure catch (error) {
      return error;
    }
    fail('expected a ValidationFailure');
  }

  group('name', () {
    test('1 character is valid, empty and blank are rejected', () {
      expect(validate(draft(name: 'x')).name, 'x');
      expect(
        failure(draft(name: '')).fieldErrors[MealFields.name],
        'Bitte gib einen Namen ein.',
      );
      expect(
        failure(draft(name: '   ')).fieldErrors[MealFields.name],
        'Bitte gib einen Namen ein.',
      );
    });

    test('80 characters are valid, 81 are rejected', () {
      expect(validate(draft(name: 'a' * 80)).name, 'a' * 80);
      expect(
        failure(draft(name: 'a' * 81)).fieldErrors[MealFields.name],
        'Der Name darf höchstens 80 Zeichen lang sein.',
      );
    });

    test('the name is trimmed before it is measured', () {
      expect(validate(draft(name: '  Müsli  ')).name, 'Müsli');
      expect(validate(draft(name: ' ${'a' * 80} ')).name, 'a' * 80);
      expect(
        failure(draft(name: ' ${'a' * 81} ')).fieldErrors.keys,
        contains(MealFields.name),
      );
    });

    test('characters are counted as code points like the database does', () {
      expect(validate(draft(name: '\u{1D400}' * 80)).name, '\u{1D400}' * 80);
      expect(
        failure(draft(name: '\u{1D400}' * 81)).fieldErrors.keys,
        contains(MealFields.name),
      );
    });
  });

  group('calories', () {
    test('not given (null) is valid and stays null', () {
      expect(validate(draft()).kcal, isNull);
    });

    test('a deliberate 0 is valid and stays 0, not null', () {
      expect(validate(draft(kcal: 0)).kcal, 0);
    });

    test('5000 is valid, 5001 and negative values are rejected', () {
      expect(validate(draft(kcal: 5000)).kcal, 5000);
      expect(
        failure(draft(kcal: 5001)).fieldErrors[MealFields.kcal],
        'Bitte gib Kalorien zwischen 0 und 5.000 kcal ein oder lass das Feld '
        'leer.',
      );
      expect(
        failure(draft(kcal: -1)).fieldErrors.keys,
        contains(MealFields.kcal),
      );
    });
  });

  group('time', () {
    test('now is valid, one millisecond later is the future', () {
      expect(validate(draft(when: now)).occurredAtUtc, now);
      expect(
        failure(draft(when: now.add(const Duration(milliseconds: 1))))
            .fieldErrors[MealFields.occurredAt],
        'Der Zeitpunkt darf nicht in der Zukunft liegen.',
      );
    });

    test('before 2000-01-01 (Berlin) is rejected, from then on valid', () {
      expect(
        failure(draft(when: DateTime.utc(1999, 12, 31, 22, 59)))
            .fieldErrors[MealFields.occurredAt],
        'Das Datum darf nicht vor dem 01.01.2000 liegen.',
      );
      validate(draft(when: DateTime.utc(1999, 12, 31, 23)));
    });
  });

  group('note', () {
    test('is trimmed, blank means none', () {
      expect(validate(draft(note: ' mit Beeren ')).note, 'mit Beeren');
      expect(validate(draft(note: '   ')).note, isNull);
    });

    test('500 characters are fine, 501 are rejected', () {
      expect(validate(draft(note: 'x' * 500)).note, 'x' * 500);
      expect(
        failure(draft(note: 'x' * 501)).fieldErrors[MealFields.note],
        'Die Notiz darf höchstens 500 Zeichen lang sein.',
      );
    });
  });

  test('all errors are reported together', () {
    final error = failure(
      draft(
        name: '',
        kcal: 6000,
        when: now.add(const Duration(minutes: 1)),
        note: 'x' * 501,
      ),
    );
    expect(
      error.fieldErrors.keys,
      unorderedEquals([
        MealFields.name,
        MealFields.kcal,
        MealFields.occurredAt,
        MealFields.note,
      ]),
    );
  });
}
