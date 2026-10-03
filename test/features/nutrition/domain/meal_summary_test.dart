import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/meal_format.dart';
import 'package:self_improvement/features/nutrition/domain/meal_summary.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  final day = LocalDate(2026, 10, 3);

  MealEntry meal(
    String id, {
    int? kcal,
    int hour = 7,
    LocalDate? date,
    String name = 'Mahlzeit',
  }) {
    final when = DateTime.utc(2026, 10, 3, hour);
    return MealEntry(
      id: id,
      name: name,
      kcal: kcal,
      occurredAtUtc: when,
      localDate: date ?? day,
      timezoneId: 'Europe/Berlin',
      createdAtUtc: when,
      rowVersion: 1,
    );
  }

  group('summarizeMeals (AT14)', () {
    test('no meals: nothing to say, no calorie sum', () {
      final summary = summarizeMeals(const []);
      expect(summary.mealCount, 0);
      expect(summary.hasMeals, isFalse);
      expect(summary.completeness, KcalCompleteness.none);
      expect(summary.knownKcal, isNull);
      expect(summary.isIncomplete, isFalse);
    });

    test('all meals with calories: complete, the sum is exact', () {
      final summary = summarizeMeals([
        meal('a', kcal: 400),
        meal('b', kcal: 650),
      ]);
      expect(summary.mealCount, 2);
      expect(summary.mealsWithKcal, 2);
      expect(summary.mealsWithoutKcal, 0);
      expect(summary.knownKcal, 1050);
      expect(summary.completeness, KcalCompleteness.complete);
      expect(summary.isIncomplete, isFalse);
    });

    test('a mix: the known sum is a lower bound and the day is incomplete', () {
      final summary = summarizeMeals([
        meal('a', kcal: 400),
        meal('b'),
        meal('c', kcal: 300),
      ]);
      expect(summary.mealCount, 3);
      expect(summary.mealsWithKcal, 2);
      expect(summary.mealsWithoutKcal, 1);
      expect(summary.knownKcal, 700);
      expect(summary.completeness, KcalCompleteness.incomplete);
      expect(summary.isIncomplete, isTrue);
    });

    test('all meals without calories: NO sum, never 0 (no invented value)', () {
      final summary = summarizeMeals([meal('a'), meal('b'), meal('c')]);
      expect(summary.mealCount, 3);
      expect(summary.mealsWithKcal, 0);
      expect(summary.knownKcal, isNull, reason: 'a missing value is not 0');
      expect(summary.completeness, KcalCompleteness.incomplete);
    });

    test('a deliberate 0 is a known value and differs from missing', () {
      final onlyZero = summarizeMeals([meal('a', kcal: 0)]);
      expect(onlyZero.knownKcal, 0, reason: 'the user said 0');
      expect(onlyZero.completeness, KcalCompleteness.complete);

      final zeroAndMissing = summarizeMeals([meal('a', kcal: 0), meal('b')]);
      expect(zeroAndMissing.knownKcal, 0);
      expect(zeroAndMissing.completeness, KcalCompleteness.incomplete);

      final missingOnly = summarizeMeals([meal('b')]);
      expect(missingOnly.knownKcal, isNull);
    });

    test('works for any set of meals, for example a whole period', () {
      final summary = summarizeMeals([
        meal('a', kcal: 500, date: LocalDate(2026, 10, 1)),
        meal('b', date: LocalDate(2026, 10, 2)),
        meal('c', kcal: 250),
      ]);
      expect(summary.mealCount, 3);
      expect(summary.knownKcal, 750);
      expect(summary.completeness, KcalCompleteness.incomplete);
    });
  });

  group('buildMealDay', () {
    test('lists the meals newest first with the summary', () {
      final built = buildMealDay(
        date: day,
        entries: [
          meal('early', hour: 6, kcal: 300),
          meal('late', hour: 18),
          meal('noon', hour: 12, kcal: 600),
        ],
      );
      expect(built.date, day);
      expect(built.isEmpty, isFalse);
      expect(built.entriesNewestFirst.map((m) => m.id), [
        'late',
        'noon',
        'early',
      ]);
      expect(built.summary.mealCount, 3);
      expect(built.summary.knownKcal, 900);
      expect(built.summary.completeness, KcalCompleteness.incomplete);
    });

    test('a day without meals is empty with the "none" summary', () {
      final built = buildMealDay(date: day, entries: const []);
      expect(built.isEmpty, isTrue);
      expect(built.summary.completeness, KcalCompleteness.none);
    });

    test('equal models are equal, different ones are not', () {
      MealDay build(int? kcal) => buildMealDay(
        date: day,
        entries: [meal('a', kcal: kcal)],
      );
      expect(build(100), build(100));
      expect(build(100).hashCode, build(100).hashCode);
      expect(build(100), isNot(build(null)));
      expect(build(0), isNot(build(null)), reason: '0 is not "not given"');
    });
  });

  group('compareMealNewestFirst', () {
    test('equal times fall back to the creation time, then the id', () {
      final base = DateTime.utc(2026, 10, 3, 7);
      MealEntry at(String id, DateTime created) => MealEntry(
        id: id,
        name: 'x',
        occurredAtUtc: base,
        localDate: day,
        timezoneId: 'Europe/Berlin',
        createdAtUtc: created,
        rowVersion: 1,
      );
      final sorted = [
        at('a', base),
        at('c', base.add(const Duration(seconds: 1))),
        at('b', base),
      ]..sort(compareMealNewestFirst);
      expect(sorted.map((m) => m.id), ['c', 'b', 'a']);
    });
  });

  group('buildMealHistory', () {
    test('groups per stored local day, newest day first, each summarised', () {
      final oct2 = LocalDate(2026, 10, 2);
      final history = buildMealHistory(
        days: 14,
        entries: [
          meal('a', kcal: 400, date: oct2),
          meal('b', hour: 9),
          meal('c', hour: 8, kcal: 200),
        ],
      );
      expect(history.days, 14);
      expect(history.isEmpty, isFalse);
      expect(history.daysNewestFirst.map((d) => d.date), [day, oct2]);
      expect(history.daysNewestFirst.first.summary.mealCount, 2);
      expect(history.daysNewestFirst.first.summary.knownKcal, 200);
      expect(
        history.daysNewestFirst.first.summary.completeness,
        KcalCompleteness.incomplete,
      );
      expect(
        history.daysNewestFirst.last.summary.completeness,
        KcalCompleteness.complete,
      );
    });

    test('no meals means an empty history', () {
      expect(buildMealHistory(days: 7, entries: const []).isEmpty, isTrue);
    });
  });

  group('display texts', () {
    MealSummary summary(List<MealEntry> meals) => summarizeMeals(meals);

    test('counts', () {
      expect(formatMealCount(0), '0 Mahlzeiten');
      expect(formatMealCount(1), '1 Mahlzeit');
      expect(formatMealCount(2), '2 Mahlzeiten');
      expect(formatMealCount(12), '12 Mahlzeiten');
    });

    test('calories with a thousands dot', () {
      expect(formatKcal(0), '0 kcal');
      expect(formatKcal(450), '450 kcal');
      expect(formatKcal(1250), '1.250 kcal');
    });

    test('the one-line day summary for every combination', () {
      expect(mealSummaryText(summary(const [])), 'Noch keine Mahlzeit');
      expect(
        mealSummaryText(summary([meal('a', kcal: 1250)])),
        '1 Mahlzeit · 1.250 kcal',
      );
      expect(
        mealSummaryText(summary([meal('a', kcal: 400), meal('b', kcal: 400)])),
        '2 Mahlzeiten · 800 kcal',
      );
      expect(
        mealSummaryText(summary([meal('a', kcal: 400), meal('b')])),
        '2 Mahlzeiten · 400 kcal · Kalorien unvollständig',
      );
    });

    test('all missing: the incomplete hint and no calorie figure at all', () {
      final text = mealSummaryText(summary([meal('a'), meal('b')]));
      expect(text, '2 Mahlzeiten · Kalorien unvollständig');
      expect(text, isNot(contains('kcal')));
      expect(text, isNot(contains('0')));
    });

    test('a deliberate zero is stated as 0 kcal', () {
      expect(
        mealSummaryText(summary([meal('a', kcal: 0)])),
        '1 Mahlzeit · 0 kcal',
      );
    });

    test('constants', () {
      expect(kcalIncompleteLabel, 'Kalorien unvollständig');
      expect(mealSavedMessage, 'Mahlzeit gespeichert');
      expect(mealUpdatedMessage, 'Mahlzeit aktualisiert');
      expect(mealDeletedMessage, 'Mahlzeit gelöscht');
    });
  });
}
