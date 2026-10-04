import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/body/domain/weight_input.dart';

int? grams(String input) => switch (parseWeightKg(input)) {
  WeightKgParsed(:final grams) => grams,
  WeightKgInvalid() => null,
};

WeightKgError? error(String input) => switch (parseWeightKg(input)) {
  WeightKgParsed() => null,
  WeightKgInvalid(:final error) => error,
};

void main() {
  group('valid input (AT05)', () {
    test('comma and period are equivalent and stored as integer grams', () {
      expect(grams('71'), 71000);
      expect(grams('71,5'), 71500);
      expect(grams('71.5'), 71500);
      expect(
        grams(' 71,5 '),
        71500,
        reason: 'surrounding whitespace is trimmed',
      );
      expect(grams('71,0'), 71000);
      expect(grams('071,5'), 71500, reason: 'leading zeros do not matter');
    });

    test('range limits are inclusive', () {
      expect(grams('20'), 20000);
      expect(grams('20,0'), 20000);
      expect(grams('350'), 350000);
      expect(grams('350.0'), 350000);
      expect(grams('20,1'), 20100);
      expect(grams('349,9'), 349900);
    });
  });

  group('invalid input', () {
    test('empty and blank', () {
      expect(error(''), WeightKgError.empty);
      expect(error('   '), WeightKgError.empty);
    });

    test('out of range on both sides of each limit (AT05)', () {
      expect(error('19,9'), WeightKgError.belowMinimum);
      expect(error('19.9'), WeightKgError.belowMinimum);
      expect(error('0'), WeightKgError.belowMinimum);
      expect(error('0,0'), WeightKgError.belowMinimum);
      expect(error('350,1'), WeightKgError.aboveMaximum);
      expect(error('351'), WeightKgError.aboveMaximum);
      expect(error('99999'), WeightKgError.aboveMaximum);
      expect(error('12345678901234567890'), WeightKgError.aboveMaximum);
    });

    test(
      'two decimals are a correction hint, never silently rounded (AT05)',
      () {
        expect(error('71,55'), WeightKgError.tooManyDecimals);
        expect(error('71.55'), WeightKgError.tooManyDecimals);
        expect(error('71,50'), WeightKgError.tooManyDecimals);
        expect(error('71,555'), WeightKgError.tooManyDecimals);
      },
    );

    test('anything that is not a plain decimal is an invalid format', () {
      for (final bad in [
        'NaN',
        'nan',
        'Infinity',
        '-Infinity',
        'infinity',
        '1e2',
        '1E2',
        '7e1',
        '-71',
        '+71',
        '71,',
        ',5',
        '.5',
        '71..5',
        '71,,5',
        '71,5,3',
        '71.5,3',
        '71,5.3',
        '1.234,5',
        '1,234.5',
        '1 234',
        '7 1,5',
        '71 kg',
        '7l,5',
        '٧١',
        '71,５',
        'abc',
        '0x10',
      ]) {
        expect(error(bad), WeightKgError.invalidFormat, reason: 'input "$bad"');
      }
    });
  });

  group('plus/minus stepper', () {
    test('steps by 0,1 kg from the typed value', () {
      expect(stepWeightGrams(currentText: '71,5', direction: 1), 71600);
      expect(stepWeightGrams(currentText: '71,5', direction: -1), 71400);
      expect(stepWeightGrams(currentText: '71', direction: 1), 71100);
    });

    test('starts from the fallback when the text is empty or invalid', () {
      expect(
        stepWeightGrams(currentText: '', direction: 1, fallbackGrams: 71800),
        71900,
      );
      expect(
        stepWeightGrams(
          currentText: 'abc',
          direction: -1,
          fallbackGrams: 71800,
        ),
        71700,
      );
    });

    test('has no base without a value and without a fallback', () {
      expect(stepWeightGrams(currentText: '', direction: 1), isNull);
    });

    test('is clamped to the valid range', () {
      expect(stepWeightGrams(currentText: '20', direction: -1), 20000);
      expect(stepWeightGrams(currentText: '350', direction: 1), 350000);
    });
  });
}
