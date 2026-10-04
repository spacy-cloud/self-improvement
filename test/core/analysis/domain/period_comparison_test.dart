import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/domain/analysis_math.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  Fraction f(int numerator, [int denominator = 1]) =>
      Fraction(numerator, denominator);

  PeriodComparison relative(
    Fraction? current,
    Fraction? previous, {
    NoComparisonReason? base,
    NoComparisonReason? data,
  }) => comparePeriods(
    unit: FigureUnit.steps,
    kind: ComparisonKind.relative,
    current: current,
    previous: previous,
    baseProblem: base,
    dataProblem: data,
  );

  group(
    'delta and percentage arithmetic (100 * (current - previous) / previous)',
    () {
      test('8000 against 7450 steps: +550, +7.38 %, shown as 7 %', () {
        final result = relative(f(8000), f(7450));
        expect(result.isAvailable, isTrue);
        expect(result.current, 8000);
        expect(result.previous, 7450);
        expect(result.delta, 550);
        expect(result.percent, closeTo(7.382550335570469, 1e-12));
        expect(result.percentRounded, 7);
        expect(result.reason, isNull);
      });

      test('a decrease is negative', () {
        final result = relative(f(50), f(100));
        expect(result.delta, -50);
        expect(result.percent, -50);
        expect(result.percentRounded, -50);
      });

      test('unchanged values give an exact zero', () {
        final result = relative(f(100), f(100));
        expect(result.isAvailable, isTrue);
        expect(result.delta, 0);
        expect(result.percent, 0);
        expect(result.percentRounded, 0);
      });

      test('doubling is +100 %, a ninth of the base is -88.89 %', () {
        expect(relative(f(200), f(100)).percent, 100);
        expect(relative(f(100), f(900)).percent, closeTo(-88.8889, 1e-3));
        expect(relative(f(100), f(900)).percentRounded, -89);
      });

      test('percentages round half away from zero', () {
        // exact .5 values: 12.5 -> 13, -12.5 -> -13, 0.5 -> 1, -0.5 -> -1
        expect(relative(f(9), f(8)).percent, 12.5);
        expect(relative(f(9), f(8)).percentRounded, 13);
        expect(relative(f(7), f(8)).percent, -12.5);
        expect(relative(f(7), f(8)).percentRounded, -13);
        expect(relative(f(1005), f(1000)).percentRounded, 1);
        expect(relative(f(995), f(1000)).percentRounded, -1);
        // just below the half: 0.4 % -> 0
        expect(relative(f(1004), f(1000)).percentRounded, 0);
        expect(relative(f(996), f(1000)).percentRounded, 0);
        // 1.5 -> 2, 2.5 -> 3
        expect(relative(f(203), f(200)).percentRounded, 2);
        expect(relative(f(205), f(200)).percentRounded, 3);
      });

      test('exact arithmetic: naive double math would round 12.5 % down', () {
        // 15 against an average of 40/3 = 13.33...: the exact percentage is
        // 12.5 (rounds to 13). Dividing first in floating point gives
        // 12.499999999999995 and would show 12.
        final result = relative(f(15), f(40, 3));
        expect(result.percent, 12.5);
        expect(result.percentRounded, 13);
        final negative = relative(f(7), f(280, 3));
        expect(negative.percent, -92.5);
        expect(negative.percentRounded, -93);
      });

      test('averages are compared as averages, not as totals', () {
        // current: 35000 steps on 5 recorded days (7000), previous: 15000 on 3
        // recorded days (5000). The totals would suggest +133 %.
        final result = relative(f(35000, 5), f(15000, 3));
        expect(result.current, 7000);
        expect(result.previous, 5000);
        expect(result.delta, 2000);
        expect(result.percent, 40);
        expect(result.percentRounded, 40);
      });

      test('fractional averages: 1687.5 ml against 1500 ml is +12.5 %', () {
        final result = relative(f(6750, 4), f(3000, 2));
        expect(result.delta, 187.5);
        expect(result.percent, 12.5);
        expect(result.percentRounded, 13);
      });

      test('large values stay exact', () {
        final result = relative(f(9000000, 90), f(8100000, 90));
        expect(result.percent, closeTo(11.111111111, 1e-9));
      });
    },
  );

  group('no comparison without a fitting base', () {
    test('a previous value of 0 gives no percentage ("Nullbasis")', () {
      final result = relative(f(5), f(0));
      expect(result.isAvailable, isFalse);
      expect(result.reason, NoComparisonReason.previousIsZero);
      expect(result.delta, isNull);
      expect(result.percent, isNull);
      expect(result.percentRounded, isNull);
      expect(result.current, 5);
      expect(result.previous, 0, reason: 'the values stay visible');
    });

    test('a negative previous value gives no percentage either', () {
      expect(relative(f(5), f(-3)).reason, NoComparisonReason.previousIsZero);
    });

    test('a previous average of 0 recorded steps (0 / 3) is a zero base', () {
      expect(
        relative(f(7000, 1), f(0, 3)).reason,
        NoComparisonReason.previousIsZero,
      );
    });

    test('no data in the previous period', () {
      final result = relative(f(5), null);
      expect(result.reason, NoComparisonReason.noPreviousData);
      expect(result.previous, isNull);
      expect(result.current, 5);
    });

    test('no data in the current period', () {
      final result = relative(null, f(5));
      expect(result.reason, NoComparisonReason.noCurrentData);
      expect(result.current, isNull);
      expect(result.previous, 5);
    });

    test('no data on either side reports the previous period first', () {
      expect(relative(null, null).reason, NoComparisonReason.noPreviousData);
    });

    test('a base outside the usage window beats every other reason', () {
      expect(
        relative(
          f(5),
          f(4),
          base: NoComparisonReason.previousPeriodBeforeStart,
        ).reason,
        NoComparisonReason.previousPeriodBeforeStart,
      );
      expect(
        relative(
          null,
          null,
          base: NoComparisonReason.previousPeriodBeforeStart,
        ).reason,
        NoComparisonReason.previousPeriodBeforeStart,
      );
      expect(
        relative(f(5), f(0), base: NoComparisonReason.noUsageStart).reason,
        NoComparisonReason.noUsageStart,
      );
    });

    test(
      'incomparable data comes after missing data and before the zero base',
      () {
        expect(
          relative(
            f(5),
            f(4),
            data: NoComparisonReason.incompleteCalories,
          ).reason,
          NoComparisonReason.incompleteCalories,
        );
        expect(
          relative(
            f(5),
            null,
            data: NoComparisonReason.incompleteCalories,
          ).reason,
          NoComparisonReason.noPreviousData,
        );
        expect(
          relative(
            f(5),
            f(0),
            data: NoComparisonReason.incompleteCalories,
          ).reason,
          NoComparisonReason.incompleteCalories,
        );
      },
    );
  });

  group('the other comparison kinds', () {
    test('weight: a difference only, never a percentage', () {
      final result = comparePeriods(
        unit: FigureUnit.gramsChange,
        kind: ComparisonKind.absolute,
        current: f(-300),
        previous: f(-500),
      );
      expect(result.isAvailable, isTrue);
      expect(result.delta, 200);
      expect(result.percent, isNull);
      expect(result.percentRounded, isNull);
    });

    test('a difference works with a zero or negative previous value', () {
      final fromZero = comparePeriods(
        unit: FigureUnit.gramsChange,
        kind: ComparisonKind.absolute,
        current: f(-300),
        previous: f(0),
      );
      expect(fromZero.delta, -300);
      final negative = comparePeriods(
        unit: FigureUnit.gramsChange,
        kind: ComparisonKind.absolute,
        current: f(200),
        previous: f(-100),
      );
      expect(negative.delta, 300);
    });

    test('the absolute kind still needs data on both sides', () {
      expect(
        comparePeriods(
          unit: FigureUnit.grams,
          kind: ComparisonKind.absolute,
          current: f(71500),
          previous: null,
        ).reason,
        NoComparisonReason.noPreviousData,
      );
      expect(
        comparePeriods(
          unit: FigureUnit.grams,
          kind: ComparisonKind.absolute,
          current: null,
          previous: f(71900),
        ).reason,
        NoComparisonReason.noCurrentData,
      );
    });

    test(
      'ratios compare in percentage points and allow a base of 0 percent',
      () {
        // 6 of 8 habit-days (75 %) against 2 of 7 (28.57 %)
        final result = comparePeriods(
          unit: FigureUnit.percent,
          kind: ComparisonKind.percentagePoints,
          current: f(600, 8),
          previous: f(200, 7),
        );
        expect(result.current, 75);
        expect(result.previous, closeTo(28.5714, 1e-3));
        expect(result.delta, closeTo(46.4286, 1e-3));
        expect(result.percent, isNull, reason: 'no percentage of a percentage');

        final fromZero = comparePeriods(
          unit: FigureUnit.percent,
          kind: ComparisonKind.percentagePoints,
          current: f(300, 6),
          previous: f(0, 7),
        );
        expect(fromZero.isAvailable, isTrue);
        expect(fromZero.delta, 50);
      },
    );

    test('exact equality of ratios is an exact zero', () {
      final result = comparePeriods(
        unit: FigureUnit.percent,
        kind: ComparisonKind.percentagePoints,
        current: f(100, 3),
        previous: f(200, 6),
      );
      expect(result.delta, 0);
    });
  });

  group('result types', () {
    test('NoComparison and ComparisonDelta are the two sealed results', () {
      final none = relative(null, f(1)).result;
      final some = relative(f(2), f(1)).result;
      expect(none, isA<NoComparison>());
      expect(some, isA<ComparisonDelta>());
      expect((none as NoComparison).reason, NoComparisonReason.noCurrentData);
      expect((some as ComparisonDelta).delta, 1);
      expect(some.percentRounded, 100);
      expect(none.toString(), contains('noCurrentData'));
      expect(some.toString(), contains('delta: 1.0'));
    });
  });

  group('usage window check', () {
    final previousStart = LocalDate(2026, 9, 20);

    test('inside: the previous period starts on or after the usage start', () {
      expect(
        comparisonBaseProblem(
          previousStart: previousStart,
          usageStart: LocalDate(2026, 9, 20),
        ),
        isNull,
      );
      expect(
        comparisonBaseProblem(
          previousStart: previousStart,
          usageStart: LocalDate(2026, 1, 1),
        ),
        isNull,
      );
    });

    test(
      'a previous period that starts before the usage start does not fit',
      () {
        expect(
          comparisonBaseProblem(
            previousStart: previousStart,
            usageStart: LocalDate(2026, 9, 21),
          ),
          NoComparisonReason.previousPeriodBeforeStart,
        );
      },
    );

    test('an unknown usage start does not fit', () {
      expect(
        comparisonBaseProblem(previousStart: previousStart, usageStart: null),
        NoComparisonReason.noUsageStart,
      );
    });
  });
}
