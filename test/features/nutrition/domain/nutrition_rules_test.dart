import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/features/body/domain/weight_validation.dart'
    as weight;
import 'package:self_improvement/features/nutrition/domain/nutrition_rules.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

void main() {
  group('limits stay in sync with the weight form', () {
    test('note length and earliest date are the same technical limits', () {
      expect(maxNutritionNoteLength, weight.maxNoteLength);
      expect(earliestNutritionDate, weight.earliestEventDate);
      expect(earliestNutritionDate, LocalDate(2000, 1, 1));
    });
  });

  group('parseDigits', () {
    test('plain digits parse, leading zeros are allowed', () {
      expect(parseDigits('0'), 0);
      expect(parseDigits('7'), 7);
      expect(parseDigits('007'), 7);
      expect(parseDigits('250'), 250);
      expect(parseDigits('0000000000001'), 1);
      expect(parseDigits('999999999'), 999999999);
    });

    test('anything else is not a whole number', () {
      for (final text in [
        '',
        ' 5',
        '5 ',
        '-5',
        '+5',
        '5.0',
        '5,0',
        '1.000',
        '1e3',
        '0x10',
        'abc',
        '12a',
        '2 50',
        // Digits of other scripts are not accepted.
        '٢٥٠',
        '１２',
      ]) {
        expect(parseDigits(text), isNull, reason: '"$text"');
      }
    });

    test('absurdly long numbers saturate instead of overflowing', () {
      expect(parseDigits('1000000000'), wholeNumberCeiling);
      expect(parseDigits('99999999999999999999999999'), wholeNumberCeiling);
      expect(parseDigits('00000000000000000000'), 0);
    });
  });

  group('normalizeNote', () {
    test('null, empty and blank mean no note', () {
      for (final raw in [null, '', '   ', '\n\t ']) {
        final result = normalizeNote(raw);
        expect(result.note, isNull, reason: '"$raw"');
        expect(result.error, isNull);
      }
    });

    test('the note is trimmed', () {
      expect(normalizeNote('  nach dem Sport  ').note, 'nach dem Sport');
    });

    test('500 characters are fine, 501 are rejected (after trimming)', () {
      expect(normalizeNote('x' * 500).error, isNull);
      expect(normalizeNote('  ${'x' * 500}  ').note, 'x' * 500);
      final tooLong = normalizeNote('x' * 501);
      expect(tooLong.note, isNull);
      expect(tooLong.error, 'Die Notiz darf höchstens 500 Zeichen lang sein.');
    });

    test('characters are counted as code points, like the database does', () {
      // One astral character (mathematical bold A) is two UTF-16 units but one character.
      expect(normalizeNote('\u{1D400}' * 500).error, isNull);
      expect(normalizeNote('\u{1D400}' * 501).error, isNotNull);
      expect(characterCount('\u{1D400}'), 1);
      expect(characterCount('Käse'), 4);
    });
  });

  group('eventTimeError (Berlin clock, now = 2026-10-03 08:00Z)', () {
    final clock = FakeClock.at('2026-10-03T08:00:00Z');
    final now = clock.nowUtc();

    String? error(DateTime when) =>
        eventTimeError(occurredAtUtc: when, nowUtc: now, clock: clock);

    test('now and the past are valid', () {
      expect(error(now), isNull);
      expect(error(now.subtract(const Duration(days: 400))), isNull);
    });

    test('one millisecond after now is the future', () {
      expect(
        error(now.add(const Duration(milliseconds: 1))),
        'Der Zeitpunkt darf nicht in der Zukunft liegen.',
      );
    });

    test('the date must not be before 2000-01-01 in the device zone', () {
      // 1999-12-31 22:59Z is 23:59 in Berlin; 23:00Z is 2000-01-01 00:00.
      expect(
        error(DateTime.utc(1999, 12, 31, 22, 59)),
        'Das Datum darf nicht vor dem 01.01.2000 liegen.',
      );
      expect(error(DateTime.utc(1999, 12, 31, 23)), isNull);
      expect(error(DateTime.utc(2000)), isNull);
    });
  });

  test('the DST gap hint names the first valid time', () {
    expect(
      dstGapMessage(const LocalTime(3, 0)),
      'Diese Uhrzeit gibt es wegen der Zeitumstellung nicht. '
      'Bitte wähle 03:00 Uhr oder später.',
    );
  });
}
