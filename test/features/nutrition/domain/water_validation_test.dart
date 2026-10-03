import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_validation.dart';

void main() {
  // "now" is 2026-10-03 08:00Z = 10:00 in Berlin.
  final clock = FakeClock.at('2026-10-03T08:00:00Z');
  final now = clock.nowUtc();

  WaterDraft draft({int ml = 250, DateTime? when, String? note}) => WaterDraft(
    amountMl: ml,
    occurredAtUtc: when ?? DateTime.utc(2026, 10, 3, 7),
    note: note,
  );

  WaterDraft validate(WaterDraft d) =>
      validateWaterDraft(d, nowUtc: now, clock: clock);

  ValidationFailure failure(WaterDraft d) {
    try {
      validate(d);
    } on ValidationFailure catch (error) {
      return error;
    }
    fail('expected a ValidationFailure');
  }

  group('amount', () {
    test('49 and 2001 are rejected, 50 and 2000 are valid', () {
      expect(
        failure(draft(ml: 49)).fieldErrors[WaterFields.amount],
        'Bitte gib eine Menge zwischen 50 und 2.000 ml ein.',
      );
      expect(
        failure(draft(ml: 2001)).fieldErrors.keys,
        contains(WaterFields.amount),
      );
      expect(validate(draft(ml: 50)).amountMl, 50);
      expect(validate(draft(ml: 2000)).amountMl, 2000);
    });

    test('zero and negative amounts are rejected', () {
      for (final ml in [0, -1, -250]) {
        expect(
          failure(draft(ml: ml)).fieldErrors.keys,
          contains(WaterFields.amount),
          reason: '$ml',
        );
      }
    });
  });

  group('time', () {
    test('now is valid, one millisecond later is the future', () {
      expect(validate(draft(when: now)).occurredAtUtc, now);
      final error = failure(
        draft(when: now.add(const Duration(milliseconds: 1))),
      );
      expect(
        error.fieldErrors[WaterFields.occurredAt],
        'Der Zeitpunkt darf nicht in der Zukunft liegen.',
      );
    });

    test('before 2000-01-01 (Berlin) is rejected, from then on valid', () {
      final error = failure(draft(when: DateTime.utc(1999, 12, 31, 22, 59)));
      expect(
        error.fieldErrors[WaterFields.occurredAt],
        'Das Datum darf nicht vor dem 01.01.2000 liegen.',
      );
      validate(draft(when: DateTime.utc(1999, 12, 31, 23)));
    });
  });

  group('note', () {
    test('is trimmed and blank means none', () {
      expect(validate(draft(note: '  nach dem Sport ')).note, 'nach dem Sport');
      expect(validate(draft(note: '   ')).note, isNull);
      expect(validate(draft()).note, isNull);
    });

    test('500 characters are fine, 501 are rejected after trimming', () {
      expect(validate(draft(note: 'x' * 500)).note, 'x' * 500);
      expect(validate(draft(note: ' ${'x' * 500} ')).note, 'x' * 500);
      expect(
        failure(draft(note: 'x' * 501)).fieldErrors[WaterFields.note],
        'Die Notiz darf höchstens 500 Zeichen lang sein.',
      );
    });
  });

  test('all errors are reported together', () {
    final error = failure(
      draft(ml: 10, when: now.add(const Duration(minutes: 1)), note: 'x' * 501),
    );
    expect(
      error.fieldErrors.keys,
      unorderedEquals([
        WaterFields.amount,
        WaterFields.occurredAt,
        WaterFields.note,
      ]),
    );
  });

  test('a valid draft is returned unchanged except for the note', () {
    final result = validate(draft(ml: 300, note: ' x '));
    expect(result.amountMl, 300);
    expect(result.occurredAtUtc, DateTime.utc(2026, 10, 3, 7));
    expect(result.note, 'x');
  });
}
