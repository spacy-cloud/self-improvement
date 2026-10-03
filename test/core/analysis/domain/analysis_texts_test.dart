import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/domain/analysis_math.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_texts.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../analysis_fixtures.dart';

void main() {
  Fraction f(int numerator, [int denominator = 1]) =>
      Fraction(numerator, denominator);

  PeriodComparison comparison(
    FigureUnit unit,
    ComparisonKind kind,
    Fraction? current,
    Fraction? previous,
  ) => comparePeriods(
    unit: unit,
    kind: kind,
    current: current,
    previous: previous,
  );

  test(
    'the unit separator is a no-break space and the minus is a true minus',
    () {
      expect(analysisNbsp, ' ');
      expect(nb, analysisNbsp);
      expect(formatFigureDelta(FigureUnit.steps, -5), startsWith(minus));
      expect(formatFigureDelta(FigureUnit.steps, -5), isNot(startsWith('-')));
    },
  );

  group('values with units', () {
    test('steps use the thousands dot and no unit', () {
      expect(formatFigureValue(FigureUnit.steps, 7450), '7.450');
      expect(formatFigureValue(FigureUnit.steps, 7449.5), '7.450');
      expect(formatFigureValue(FigureUnit.steps, 0), '0');
      expect(formatFigureValue(FigureUnit.steps, 100000), '100.000');
    });

    test('water is shown in litres, rounded to 10 ml (half up)', () {
      expect(formatFigureValue(FigureUnit.milliliters, 1687.5), '1,69${nb}l');
      expect(formatFigureValue(FigureUnit.milliliters, 1685), '1,69${nb}l');
      expect(formatFigureValue(FigureUnit.milliliters, 1684), '1,68${nb}l');
      expect(formatFigureValue(FigureUnit.milliliters, 2500), '2,5${nb}l');
      expect(formatFigureValue(FigureUnit.milliliters, 2000), '2${nb}l');
      expect(formatFigureValue(FigureUnit.milliliters, 1500), '1,5${nb}l');
      expect(formatFigureValue(FigureUnit.milliliters, 50), '0,05${nb}l');
      expect(formatFigureValue(FigureUnit.milliliters, 0), '0${nb}l');
      expect(formatFigureValue(FigureUnit.milliliters, 10000), '10${nb}l');
    });

    test('weight is shown in kilograms with one decimal comma', () {
      expect(formatFigureValue(FigureUnit.grams, 71500), '71,5${nb}kg');
      expect(formatFigureValue(FigureUnit.grams, 70000), '70,0${nb}kg');
    });

    test('a weight change has a sign and the true minus', () {
      expect(
        formatFigureValue(FigureUnit.gramsChange, -300),
        '$minus'
        '0,3${nb}kg',
      );
      expect(formatFigureValue(FigureUnit.gramsChange, 500), '+0,5${nb}kg');
      expect(formatFigureValue(FigureUnit.gramsChange, 0), '0,0${nb}kg');
      expect(
        formatFigureValue(FigureUnit.gramsChange, -1200),
        '${minus}1,2${nb}kg',
      );
    });

    test('counts are plain numbers', () {
      expect(formatFigureValue(FigureUnit.workouts, 3), '3');
      expect(formatFigureValue(FigureUnit.focusSessions, 12), '12');
      expect(formatFigureValue(FigureUnit.tasks, 1250), '1.250');
      expect(formatFigureValue(FigureUnit.meals, 0), '0');
    });

    test('workout minutes switch to hours', () {
      expect(formatFigureValue(FigureUnit.workoutMinutes, 0), '0${nb}min');
      expect(formatFigureValue(FigureUnit.workoutMinutes, 45), '45${nb}min');
      expect(formatFigureValue(FigureUnit.workoutMinutes, 59), '59${nb}min');
      expect(formatFigureValue(FigureUnit.workoutMinutes, 60), '1${nb}h');
      expect(
        formatFigureValue(FigureUnit.workoutMinutes, 75),
        '1${nb}h 15${nb}min',
      );
      expect(
        formatFigureValue(FigureUnit.workoutMinutes, 135),
        '2${nb}h 15${nb}min',
      );
      expect(formatFigureValue(FigureUnit.workoutMinutes, 600), '10${nb}h');
    });

    test('focus time shows whole completed minutes', () {
      expect(formatFigureValue(FigureUnit.focusSeconds, 0), '0${nb}min');
      expect(formatFigureValue(FigureUnit.focusSeconds, 59), '<${nb}1${nb}min');
      expect(formatFigureValue(FigureUnit.focusSeconds, 60), '1${nb}min');
      expect(formatFigureValue(FigureUnit.focusSeconds, 119), '1${nb}min');
      expect(formatFigureValue(FigureUnit.focusSeconds, 3000), '50${nb}min');
      expect(
        formatFigureValue(FigureUnit.focusSeconds, 3900),
        '1${nb}h 5${nb}min',
      );
      expect(formatFigureValue(FigureUnit.focusSeconds, 3600), '1${nb}h');
    });

    test('kilocalories and percent', () {
      expect(formatFigureValue(FigureUnit.kcal, 1500), '1.500${nb}kcal');
      expect(formatFigureValue(FigureUnit.kcal, 0), '0${nb}kcal');
      expect(formatFigureValue(FigureUnit.percent, 54.5454), '55$nb%');
      expect(formatFigureValue(FigureUnit.percent, 0), '0$nb%');
      expect(formatFigureValue(FigureUnit.percent, 100), '100$nb%');
    });
  });

  group('spoken values spell the units out', () {
    test('steps and litres', () {
      expect(spokenFigureValue(FigureUnit.steps, 1), '1 Schritt');
      expect(spokenFigureValue(FigureUnit.steps, 7450), '7.450 Schritte');
      expect(spokenFigureValue(FigureUnit.milliliters, 1690), '1,69 Liter');
      expect(spokenFigureValue(FigureUnit.milliliters, 1000), '1 Liter');
    });

    test('kilograms with plus and minus for changes', () {
      expect(spokenFigureValue(FigureUnit.grams, 71500), '71,5 Kilogramm');
      expect(
        spokenFigureValue(FigureUnit.gramsChange, -300),
        'minus 0,3 Kilogramm',
      );
      expect(
        spokenFigureValue(FigureUnit.gramsChange, 500),
        'plus 0,5 Kilogramm',
      );
    });

    test('counts use the right noun and number', () {
      expect(spokenFigureValue(FigureUnit.workouts, 1), '1 Workout');
      expect(spokenFigureValue(FigureUnit.workouts, 3), '3 Workouts');
      expect(spokenFigureValue(FigureUnit.focusSessions, 1), '1 Sitzung');
      expect(spokenFigureValue(FigureUnit.focusSessions, 2), '2 Sitzungen');
      expect(spokenFigureValue(FigureUnit.tasks, 1), '1 Aufgabe');
      expect(spokenFigureValue(FigureUnit.tasks, 6), '6 Aufgaben');
      expect(spokenFigureValue(FigureUnit.meals, 1), '1 Mahlzeit');
      expect(spokenFigureValue(FigureUnit.meals, 5), '5 Mahlzeiten');
    });

    test('durations', () {
      expect(spokenFigureValue(FigureUnit.workoutMinutes, 0), '0 Minuten');
      expect(spokenFigureValue(FigureUnit.workoutMinutes, 1), '1 Minute');
      expect(spokenFigureValue(FigureUnit.workoutMinutes, 45), '45 Minuten');
      expect(spokenFigureValue(FigureUnit.workoutMinutes, 60), '1 Stunde');
      expect(
        spokenFigureValue(FigureUnit.workoutMinutes, 75),
        '1 Stunde 15 Minuten',
      );
      expect(spokenFigureValue(FigureUnit.workoutMinutes, 120), '2 Stunden');
      expect(
        spokenFigureValue(FigureUnit.focusSeconds, 3900),
        '1 Stunde 5 Minuten',
      );
      expect(
        spokenFigureValue(FigureUnit.focusSeconds, 59),
        'weniger als eine Minute',
      );
      expect(spokenFigureValue(FigureUnit.focusSeconds, 0), '0 Minuten');
    });

    test('kilocalories and percent', () {
      expect(spokenFigureValue(FigureUnit.kcal, 1), '1 Kilokalorie');
      expect(spokenFigureValue(FigureUnit.kcal, 1500), '1.500 Kilokalorien');
      expect(spokenFigureValue(FigureUnit.percent, 55), '55 Prozent');
    });
  });

  group('signed differences', () {
    test('steps', () {
      expect(formatFigureDelta(FigureUnit.steps, 470), '+470');
      expect(formatFigureDelta(FigureUnit.steps, -470), '${minus}470');
      expect(formatFigureDelta(FigureUnit.steps, 1234), '+1.234');
      expect(formatFigureDelta(FigureUnit.steps, 0), '0');
      expect(
        formatFigureDelta(FigureUnit.steps, 0.3),
        '0',
        reason: 'a difference below the shown precision has no sign',
      );
    });

    test('litres', () {
      expect(formatFigureDelta(FigureUnit.milliliters, 187.5), '+0,19${nb}l');
      expect(
        formatFigureDelta(FigureUnit.milliliters, -1250),
        '${minus}1,25${nb}l',
      );
      expect(formatFigureDelta(FigureUnit.milliliters, 4), '0${nb}l');
    });

    test('kilograms', () {
      expect(formatFigureDelta(FigureUnit.gramsChange, 200), '+0,2${nb}kg');
      expect(
        formatFigureDelta(FigureUnit.gramsChange, -300),
        '${minus}0,3${nb}kg',
      );
      expect(formatFigureDelta(FigureUnit.grams, -400), '${minus}0,4${nb}kg');
      expect(formatFigureDelta(FigureUnit.gramsChange, 0), '0,0${nb}kg');
    });

    test('counts, minutes, calories and percentage points', () {
      expect(formatFigureDelta(FigureUnit.workouts, 1), '+1');
      expect(formatFigureDelta(FigureUnit.tasks, -2), '${minus}2');
      expect(formatFigureDelta(FigureUnit.workoutMinutes, 45), '+45${nb}min');
      expect(
        formatFigureDelta(FigureUnit.workoutMinutes, -75),
        '${minus}1${nb}h 15${nb}min',
      );
      expect(formatFigureDelta(FigureUnit.focusSeconds, 900), '+15${nb}min');
      expect(
        formatFigureDelta(FigureUnit.focusSeconds, -3600),
        '${minus}1${nb}h',
      );
      expect(
        formatFigureDelta(FigureUnit.focusSeconds, 30),
        '0${nb}min',
        reason: 'below one minute',
      );
      expect(formatFigureDelta(FigureUnit.kcal, 120), '+120${nb}kcal');
      expect(
        formatFigureDelta(FigureUnit.percent, 46.4286),
        '+46${nb}Prozentpunkte',
      );
      expect(
        formatFigureDelta(FigureUnit.percent, -14),
        '${minus}14${nb}Prozentpunkte',
      );
      expect(formatFigureDelta(FigureUnit.percent, 0.2), '0${nb}Prozentpunkte');
    });

    test('spoken differences use plus and minus', () {
      expect(spokenFigureDelta(FigureUnit.steps, 470), 'plus 470 Schritte');
      expect(spokenFigureDelta(FigureUnit.steps, -1), 'minus 1 Schritt');
      expect(spokenFigureDelta(FigureUnit.steps, 0), analysisUnchangedText);
      expect(
        spokenFigureDelta(FigureUnit.milliliters, 187.5),
        'plus 0,19 Liter',
      );
      expect(
        spokenFigureDelta(FigureUnit.gramsChange, -300),
        'minus 0,3 Kilogramm',
      );
      expect(spokenFigureDelta(FigureUnit.workouts, 1), 'plus 1 Workout');
      expect(
        spokenFigureDelta(FigureUnit.workoutMinutes, 75),
        'plus 1 Stunde 15 Minuten',
      );
      expect(
        spokenFigureDelta(FigureUnit.focusSeconds, 900),
        'plus 15 Minuten',
      );
      expect(
        spokenFigureDelta(FigureUnit.kcal, -120),
        'minus 120 Kilokalorien',
      );
      expect(
        spokenFigureDelta(FigureUnit.percent, 46.4286),
        'plus 46 Prozentpunkte',
      );
      expect(spokenFigureDelta(FigureUnit.percent, 1), 'plus 1 Prozentpunkt');
      expect(spokenFigureDelta(FigureUnit.percent, 0.2), analysisUnchangedText);
    });
  });

  group('percentage changes', () {
    test('sign, true minus and whole percent', () {
      expect(formatPercentChange(7.38), '+7$nb%');
      expect(formatPercentChange(-3.2), '${minus}3$nb%');
      expect(formatPercentChange(12.5), '+13$nb%');
      expect(formatPercentChange(-12.5), '${minus}13$nb%');
      expect(formatPercentChange(0.4), '0$nb%');
      expect(formatPercentChange(-0.4), '0$nb%');
      expect(formatPercentChange(1250.4), '+1.250$nb%');
    });

    test('spoken', () {
      expect(spokenPercentChange(7.38), 'plus 7 Prozent');
      expect(spokenPercentChange(-3.2), 'minus 3 Prozent');
      expect(spokenPercentChange(0.2), '0 Prozent');
    });
  });

  group('the change of a comparison', () {
    test('relative: percentage and difference', () {
      final c = comparison(
        FigureUnit.steps,
        ComparisonKind.relative,
        f(8000),
        f(7450),
      );
      expect(formatChange(c), '+7$nb% (+550)');
      expect(spokenChange(c), 'plus 7 Prozent, plus 550 Schritte');
      expect(
        formatComparisonSentence(c, AnalysisPeriodLength.days7.againstPrevious),
        '+7$nb% (+550) gegenüber den vorherigen 7 Tagen',
      );
      expect(
        spokenComparisonSentence(
          c,
          AnalysisPeriodLength.days30.againstPrevious,
        ),
        'plus 7 Prozent, plus 550 Schritte gegenüber den vorherigen 30 Tagen',
      );
    });

    test('water: 1687.5 ml against 1500 ml', () {
      final c = comparison(
        FigureUnit.milliliters,
        ComparisonKind.relative,
        f(6750, 4),
        f(3000, 2),
      );
      expect(formatChange(c), '+13$nb% (+0,19${nb}l)');
    });

    test('a decrease uses the true minus', () {
      final c = comparison(
        FigureUnit.workouts,
        ComparisonKind.relative,
        f(1),
        f(4),
      );
      expect(
        formatChange(c),
        '$minus'
        '75$nb% (${minus}3)',
      );
      expect(spokenChange(c), 'minus 75 Prozent, minus 3 Workouts');
    });

    test('weight: only the difference', () {
      final c = comparison(
        FigureUnit.gramsChange,
        ComparisonKind.absolute,
        f(-300),
        f(-500),
      );
      expect(formatChange(c), '+0,2${nb}kg');
      expect(spokenChange(c), 'plus 0,2 Kilogramm');
    });

    test('ratios: percentage points', () {
      final c = comparison(
        FigureUnit.percent,
        ComparisonKind.percentagePoints,
        f(600, 8),
        f(200, 7),
      );
      expect(formatChange(c), '+46${nb}Prozentpunkte');
      expect(spokenChange(c), 'plus 46 Prozentpunkte');
    });

    test('an exactly unchanged value reads "unverändert"', () {
      final c = comparison(
        FigureUnit.steps,
        ComparisonKind.relative,
        f(100),
        f(100),
      );
      expect(formatChange(c), 'unverändert');
      expect(spokenChange(c), 'unverändert');
      expect(
        formatComparisonSentence(c, 'gegenüber den vorherigen 7 Tagen'),
        'unverändert gegenüber den vorherigen 7 Tagen',
      );
    });

    test('no comparison is always "Noch kein Vergleich"', () {
      final c = comparison(
        FigureUnit.steps,
        ComparisonKind.relative,
        f(5),
        f(0),
      );
      expect(formatChange(c), 'Noch kein Vergleich');
      expect(spokenChange(c), 'Noch kein Vergleich');
      expect(formatComparisonSentence(c, 'gegenüber x'), 'Noch kein Vergleich');
      expect(spokenComparisonSentence(c, 'gegenüber x'), 'Noch kein Vergleich');
      expect(analysisNoComparisonText, 'Noch kein Vergleich');
    });
  });

  group('explanations are neutral sentences', () {
    test('every reason has a text', () {
      for (final reason in NoComparisonReason.values) {
        expect(
          noComparisonExplanation(reason, usageStart: LocalDate(2026, 9, 25)),
          isNotEmpty,
        );
      }
    });

    test('the usage start is named for a base before the start', () {
      expect(
        noComparisonExplanation(
          NoComparisonReason.previousPeriodBeforeStart,
          usageStart: LocalDate(2026, 9, 25),
        ),
        'Der Vergleichszeitraum liegt nicht vollständig in der '
        'Nutzungszeit (Start: 25.09.2026).',
      );
      expect(
        noComparisonExplanation(NoComparisonReason.previousPeriodBeforeStart),
        'Der Vergleichszeitraum liegt nicht vollständig in der Nutzungszeit.',
      );
    });

    test('the other reasons', () {
      expect(
        noComparisonExplanation(NoComparisonReason.noPreviousData),
        'Im Vergleichszeitraum liegen keine Daten vor.',
      );
      expect(
        noComparisonExplanation(NoComparisonReason.noCurrentData),
        'Im aktuellen Zeitraum liegen keine Daten vor.',
      );
      expect(
        noComparisonExplanation(NoComparisonReason.previousIsZero),
        'Der Vergleichswert ist 0.',
      );
      expect(
        noComparisonExplanation(NoComparisonReason.incompleteCalories),
        'Kalorien sind nicht in beiden Zeiträumen vollständig.',
      );
      expect(
        noComparisonExplanation(NoComparisonReason.noUsageStart),
        'Der Nutzungsstart ist noch nicht bekannt.',
      );
    });
  });

  group('constants of the honesty rules', () {
    test('markers', () {
      expect(analysisNotRecordedText, 'Nicht erfasst');
      expect(analysisNoDataText, 'Noch keine Daten');
      expect(analysisCaloriesIncompleteText, 'Kalorien unvollständig');
      expect(analysisDashText, '–');
    });

    test('pluralize chooses the singular only for exactly one', () {
      expect(pluralize(1, 'Tag', 'Tagen'), 'Tag');
      expect(pluralize(0, 'Tag', 'Tagen'), 'Tagen');
      expect(pluralize(2, 'Tag', 'Tagen'), 'Tagen');
    });
  });
}
