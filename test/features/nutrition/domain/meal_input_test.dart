import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/nutrition/domain/meal_input.dart';

void main() {
  /// The parsed calories (null = not given) or the [KcalError] of a rejection.
  Object? outcome(String input) => switch (parseKcal(input)) {
    KcalParsed(:final kcal) => kcal,
    KcalInvalid(:final error) => error,
  };

  test('the limits are 0 and 5000 kcal, names up to 80 characters', () {
    expect(minMealKcal, 0);
    expect(maxMealKcal, 5000);
    expect(maxMealNameLength, 80);
  });

  group('an empty field means "not given"', () {
    test('empty and blank text parse to null, never to 0', () {
      expect(outcome(''), isNull);
      expect(outcome('   '), isNull);
      expect(parseKcal(''), isA<KcalParsed>());
      expect((parseKcal('') as KcalParsed).kcal, isNull);
    });

    test('a deliberate 0 is a value of its own', () {
      expect(outcome('0'), 0);
      expect(outcome('00'), 0);
      expect((parseKcal('0') as KcalParsed).kcal, 0);
    });
  });

  group('range 0 to 5000', () {
    test('both sides of the upper bound: 5000 is valid, 5001 is rejected', () {
      expect(outcome('5000'), 5000);
      expect(outcome('5001'), KcalError.aboveMaximum);
      expect(outcome('99999999999999999999999'), KcalError.aboveMaximum);
    });

    test('typical values are valid', () {
      expect(outcome('1'), 1);
      expect(outcome('450'), 450);
      expect(outcome(' 450 '), 450);
      expect(outcome('0450'), 450);
      expect(outcome('4999'), 4999);
    });
  });

  group('only plain whole numbers are accepted', () {
    test('everything else is rejected, nothing is guessed', () {
      for (final text in [
        '-1',
        '-0',
        '+450',
        '450,5',
        '450.5',
        '1.200',
        '1,200',
        '450 kcal',
        '450kcal',
        'abc',
        '4e2',
        '4 50',
        '٤٥٠',
      ]) {
        expect(outcome(text), KcalError.notAWholeNumber, reason: '"$text"');
      }
    });
  });

  group('German hints', () {
    test('the messages name the range and the way out', () {
      expect(
        kcalErrorMessage(KcalError.notAWholeNumber),
        'Bitte gib die Kalorien als ganze Zahl ein, zum Beispiel 450, '
        'oder lass das Feld leer.',
      );
      expect(
        kcalErrorMessage(KcalError.aboveMaximum),
        'Bitte gib Kalorien zwischen 0 und 5.000 kcal ein oder lass das Feld '
        'leer.',
      );
    });
  });
}
