import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/features/nutrition/domain/water_input.dart';

void main() {
  group('amount of one entry (parseWaterMl)', () {
    int? parsed(String input) => switch (parseWaterMl(input)) {
      WaterMlParsed(:final ml) => ml,
      WaterMlInvalid() => null,
    };

    WaterMlError? error(String input) => switch (parseWaterMl(input)) {
      WaterMlParsed() => null,
      WaterMlInvalid(:final error) => error,
    };

    test('the limits are 50 and 2000 ml', () {
      expect(minWaterEntryMl, 50);
      expect(maxWaterEntryMl, 2000);
    });

    test('both sides of the lower bound: 49 is rejected, 50 is valid', () {
      expect(error('49'), WaterMlError.belowMinimum);
      expect(parsed('50'), 50);
      expect(error('0'), WaterMlError.belowMinimum);
      expect(error('00'), WaterMlError.belowMinimum);
    });

    test('both sides of the upper bound: 2000 is valid, 2001 is rejected', () {
      expect(parsed('2000'), 2000);
      expect(error('2001'), WaterMlError.aboveMaximum);
      expect(error('10000'), WaterMlError.aboveMaximum);
    });

    test('the quick amounts and common values are valid', () {
      expect(parsed('250'), 250);
      expect(parsed('500'), 500);
      expect(parsed('1999'), 1999);
      expect(parsed(' 250 '), 250);
      expect(parsed('0250'), 250);
    });

    test('absurdly long input is above the maximum, never an exception', () {
      expect(error('99999999999999999999999999'), WaterMlError.aboveMaximum);
      expect(error('1000000000'), WaterMlError.aboveMaximum);
    });

    test('empty and blank input is its own error', () {
      expect(error(''), WaterMlError.empty);
      expect(error('   '), WaterMlError.empty);
    });

    test('only plain whole millilitres are accepted, nothing is guessed', () {
      for (final text in [
        '250,5',
        '250.5',
        '1.500',
        '1,500',
        '1,5',
        '250 ml',
        '250ml',
        '-250',
        '+250',
        'abc',
        '2e3',
        '2 50',
        '250,',
        ',5',
        '0x10',
        '٢٥٠',
        '２５０',
      ]) {
        expect(error(text), WaterMlError.notAWholeNumber, reason: '"$text"');
      }
    });

    test('every error has a German hint', () {
      expect(
        waterMlErrorMessage(WaterMlError.empty),
        'Bitte gib die Menge in Millilitern ein.',
      );
      expect(
        waterMlErrorMessage(WaterMlError.notAWholeNumber),
        'Bitte gib eine ganze Zahl in Millilitern ein, zum Beispiel 250.',
      );
      expect(
        waterMlErrorMessage(WaterMlError.belowMinimum),
        'Bitte gib eine Menge zwischen 50 und 2.000 ml ein.',
      );
      expect(
        waterMlErrorMessage(WaterMlError.aboveMaximum),
        waterAmountRangeMessage,
      );
    });
  });

  group('quick amounts', () {
    test('are 250 and 500 ml and both are valid entry amounts', () {
      expect(waterQuickAmountsMl, [250, 500]);
      for (final ml in waterQuickAmountsMl) {
        expect(ml, inInclusiveRange(minWaterEntryMl, maxWaterEntryMl));
      }
    });
  });

  group('daily target (parseWaterGoalMl)', () {
    int? parsed(String input) => switch (parseWaterGoalMl(input)) {
      WaterGoalParsed(:final ml) => ml,
      WaterGoalInvalid() => null,
    };

    WaterGoalError? error(String input) => switch (parseWaterGoalMl(input)) {
      WaterGoalParsed() => null,
      WaterGoalInvalid(:final error) => error,
    };

    test('the constants come from the water goal definition', () {
      expect(minWaterGoalMl, GoalType.water.minTarget);
      expect(maxWaterGoalMl, GoalType.water.maxTarget);
      expect(waterGoalStepMl, GoalType.water.step);
      expect(defaultWaterGoalMl, 2500);
      expect(
        (minWaterGoalMl, maxWaterGoalMl, waterGoalStepMl),
        (250, 10000, 50),
      );
    });

    test('250 to 10000 in steps of 50 are valid', () {
      expect(parsed('250'), 250);
      expect(parsed('300'), 300);
      expect(parsed('2500'), 2500);
      expect(parsed('2550'), 2550);
      expect(parsed('10000'), 10000);
      expect(parsed(' 3000 '), 3000);
    });

    test('both sides of the range bounds', () {
      expect(error('249'), WaterGoalError.belowMinimum);
      expect(error('200'), WaterGoalError.belowMinimum);
      expect(error('0'), WaterGoalError.belowMinimum);
      expect(error('10001'), WaterGoalError.aboveMaximum);
      expect(error('10050'), WaterGoalError.aboveMaximum);
    });

    test('values between the steps are rejected', () {
      expect(error('2525'), WaterGoalError.notOnStep);
      expect(error('260'), WaterGoalError.notOnStep);
      expect(error('251'), WaterGoalError.notOnStep);
      expect(error('9999'), WaterGoalError.notOnStep);
    });

    test('empty and non-numbers', () {
      expect(error(''), WaterGoalError.empty);
      expect(error('  '), WaterGoalError.empty);
      expect(error('2,5'), WaterGoalError.notAWholeNumber);
      expect(error('2500 ml'), WaterGoalError.notAWholeNumber);
      expect(error('abc'), WaterGoalError.notAWholeNumber);
      expect(error('-2500'), WaterGoalError.notAWholeNumber);
    });

    test('every error has a German hint', () {
      expect(
        waterGoalErrorMessage(WaterGoalError.empty),
        'Bitte gib dein Tagesziel in Millilitern ein.',
      );
      expect(
        waterGoalErrorMessage(WaterGoalError.notAWholeNumber),
        'Bitte gib eine ganze Zahl in Millilitern ein, zum Beispiel 2500.',
      );
      expect(
        waterGoalErrorMessage(WaterGoalError.belowMinimum),
        'Bitte gib ein Tagesziel zwischen 250 und 10.000 ml ein.',
      );
      expect(
        waterGoalErrorMessage(WaterGoalError.aboveMaximum),
        'Bitte gib ein Tagesziel zwischen 250 und 10.000 ml ein.',
      );
      expect(
        waterGoalErrorMessage(WaterGoalError.notOnStep),
        'Das Tagesziel geht in 50-ml-Schritten, zum Beispiel 2.500 ml.',
      );
    });
  });

  group('stepWaterGoalMl', () {
    test('steps by 50 ml from the typed value', () {
      expect(
        stepWaterGoalMl(currentText: '2500', direction: 1, fallbackMl: 1000),
        2550,
      );
      expect(
        stepWaterGoalMl(currentText: '2500', direction: -1, fallbackMl: 1000),
        2450,
      );
    });

    test('an invalid text steps from the fallback', () {
      expect(
        stepWaterGoalMl(currentText: '25x', direction: 1, fallbackMl: 3000),
        3050,
      );
      expect(
        stepWaterGoalMl(currentText: '2525', direction: -1, fallbackMl: 3000),
        2950,
      );
    });

    test('nothing to step from returns null', () {
      expect(stepWaterGoalMl(currentText: '', direction: 1), isNull);
    });

    test('the result is clamped to the valid range', () {
      expect(stepWaterGoalMl(currentText: '10000', direction: 1), 10000);
      expect(stepWaterGoalMl(currentText: '250', direction: -1), 250);
      expect(stepWaterGoalMl(currentText: '9950', direction: 1), 10000);
      expect(stepWaterGoalMl(currentText: '300', direction: -1), 250);
      // An off-step value cannot be stepped from; the fallback is used.
      expect(stepWaterGoalMl(currentText: '9975', direction: 1), isNull);
      expect(
        stepWaterGoalMl(currentText: '9975', direction: 1, fallbackMl: 9999),
        10000,
      );
    });
  });
}
