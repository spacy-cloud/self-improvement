import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/body/steps/domain/step_day.dart';
import 'package:self_improvement/features/body/steps/domain/steps_input.dart';
import 'package:self_improvement/shared/local_date.dart';

int? steps(String input) => switch (parseSteps(input)) {
  StepsParsed(steps: final value) => value,
  StepsInvalid() => null,
};

StepsError? error(String input) => switch (parseSteps(input)) {
  StepsParsed() => null,
  StepsInvalid(error: final e) => e,
};

void main() {
  group('parsing', () {
    test('whole numbers and German grouping are valid, zero included', () {
      expect(steps('0'), 0);
      expect(steps('7450'), 7450);
      expect(steps('7.450'), 7450);
      expect(steps(' 10.000 '), 10000);
      expect(steps('100000'), 100000);
      expect(steps('100.000'), 100000);
      expect(steps('007'), 7);
      expect(steps('00'), 0);
    });

    test('empty is its own error', () {
      expect(error(''), StepsError.empty);
      expect(error('   '), StepsError.empty);
    });

    test('above 100.000 is rejected on both sides of the limit', () {
      expect(error('100001'), StepsError.aboveMaximum);
      expect(error('100.001'), StepsError.aboveMaximum);
      expect(error('9999999'), StepsError.aboveMaximum);
      expect(error('123456789012345678901234'), StepsError.aboveMaximum);
    });

    test('anything else is an invalid format', () {
      for (final bad in [
        '7450,5',
        '7450.5',
        '-1',
        '+5',
        '1e3',
        'NaN',
        'abc',
        '7 450',
        '7,450',
        '1.00',
        '1.0000',
        '.5',
        '5.',
        '٧٤٥٠',
      ]) {
        expect(error(bad), StepsError.invalidFormat, reason: 'input "$bad"');
      }
    });
  });

  group('validation', () {
    final today = LocalDate(2026, 10, 3);

    test('date must not be in the future and not before 2000-01-01', () {
      validateStepDay(steps: 100, date: today, today: today);
      validateStepDay(steps: 100, date: LocalDate(2000, 1, 1), today: today);
      expect(
        () => validateStepDay(
          steps: 100,
          date: LocalDate(2026, 10, 4),
          today: today,
        ),
        throwsA(anything),
      );
      expect(
        () => validateStepDay(
          steps: 100,
          date: LocalDate(1999, 12, 31),
          today: today,
        ),
        throwsA(anything),
      );
      expect(
        () => validateStepDay(steps: 100001, date: today, today: today),
        throwsA(anything),
      );
      expect(
        () => validateStepDay(steps: -1, date: today, today: today),
        throwsA(anything),
      );
    });
  });

  group('progress', () {
    test(
      'bar is capped, the real percent is not (7.450 of 10.000 is 75 %)',
      () {
        const p = StepsProgress(steps: 7450, target: 10000);
        expect(p.fraction, closeTo(0.745, 1e-9));
        expect(p.percent, 75);
        expect(p.reached, isFalse);
        const over = StepsProgress(steps: 12000, target: 10000);
        expect(over.fraction, 1);
        expect(over.percent, 120);
        expect(over.reached, isTrue);
      },
    );

    test('the percentage is never 100 while the target is not reached', () {
      for (final (steps, percent) in <(int, int)>[
        (9949, 99),
        (9950, 99),
        (9999, 99),
        (10000, 100),
        (10049, 100),
        (10050, 101),
        (7450, 75),
      ]) {
        final progress = StepsProgress(steps: steps, target: 10000);
        expect(progress.percent, percent, reason: '$steps of 10000');
        expect(progress.percent == 100, progress.reached && steps < 10050);
      }
    });

    test('without a target there is no bar and no percent', () {
      const p = StepsProgress(steps: 5000, target: null);
      expect(p.fraction, 0);
      expect(p.percent, isNull);
      expect(p.reached, isFalse);
    });
  });
}
