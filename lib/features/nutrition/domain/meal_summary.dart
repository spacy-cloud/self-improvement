import 'package:flutter/foundation.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Default length of the meal history window in local days (including today).
const int defaultMealHistoryDays = 14;

/// How complete the calorie information of a set of meals is.
enum KcalCompleteness {
  /// No meals: nothing to say about calories.
  none,

  /// Every meal has a calorie value (a deliberate 0 counts as given).
  complete,

  /// At least one meal has no calorie value: the UI shows "Kalorien
  /// unvollständig" and the known sum is only a lower bound.
  incomplete,
}

/// Meal count and the sum of the KNOWN calories of a set of meals (one day or
/// any period).
///
/// A missing calorie value is never counted as 0: when no meal has a value,
/// [knownKcal] is null and the UI makes no calorie claim at all. A deliberate
/// 0 is a known value and counts (as 0).
@immutable
final class MealSummary {
  const MealSummary({
    required this.mealCount,
    required this.mealsWithKcal,
    required this.knownKcal,
    required this.completeness,
  });

  /// Number of meals.
  final int mealCount;

  /// Number of meals with a calorie value (zero included).
  final int mealsWithKcal;

  /// Sum of the given calorie values; null exactly when [mealsWithKcal] is 0.
  final int? knownKcal;

  final KcalCompleteness completeness;

  /// Number of meals without a calorie value.
  int get mealsWithoutKcal => mealCount - mealsWithKcal;

  bool get hasMeals => mealCount > 0;

  /// Whether the UI must add "Kalorien unvollständig".
  bool get isIncomplete => completeness == KcalCompleteness.incomplete;

  @override
  bool operator ==(Object other) =>
      other is MealSummary &&
      other.mealCount == mealCount &&
      other.mealsWithKcal == mealsWithKcal &&
      other.knownKcal == knownKcal &&
      other.completeness == completeness;

  @override
  int get hashCode =>
      Object.hash(mealCount, mealsWithKcal, knownKcal, completeness);

  @override
  String toString() =>
      'MealSummary($mealCount meals, known: $knownKcal, ${completeness.name})';
}

/// Summarises [meals]. Pure; also usable for a whole analysis period.
MealSummary summarizeMeals(Iterable<MealEntry> meals) {
  var count = 0;
  var withKcal = 0;
  var sum = 0;
  for (final meal in meals) {
    count++;
    final kcal = meal.kcal;
    if (kcal != null) {
      withKcal++;
      sum += kcal;
    }
  }
  return MealSummary(
    mealCount: count,
    mealsWithKcal: withKcal,
    knownKcal: withKcal == 0 ? null : sum,
    completeness: count == 0
        ? KcalCompleteness.none
        : (withKcal == count
              ? KcalCompleteness.complete
              : KcalCompleteness.incomplete),
  );
}

/// The meals of one local day with their summary.
@immutable
final class MealDay {
  const MealDay({
    required this.date,
    required this.entriesNewestFirst,
    required this.summary,
  });

  final LocalDate date;

  /// The day's active meals, newest first.
  final List<MealEntry> entriesNewestFirst;

  final MealSummary summary;

  bool get isEmpty => entriesNewestFirst.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is MealDay &&
      other.date == date &&
      other.summary == summary &&
      listEquals(other.entriesNewestFirst, entriesNewestFirst);

  @override
  int get hashCode =>
      Object.hash(date, summary, Object.hashAll(entriesNewestFirst));
}

/// Builds the model of [date] from its active [entries] (any order). Pure.
MealDay buildMealDay({
  required LocalDate date,
  required Iterable<MealEntry> entries,
}) {
  final sorted = [...entries]..sort(compareMealNewestFirst);
  return MealDay(
    date: date,
    entriesNewestFirst: List.unmodifiable(sorted),
    summary: summarizeMeals(sorted),
  );
}

/// Meals grouped per local day, newest day first. Only days with at least one
/// meal appear.
@immutable
final class MealHistory {
  const MealHistory({required this.days, required this.daysNewestFirst});

  /// Length of the window in local days, including today.
  final int days;

  final List<MealDay> daysNewestFirst;

  bool get isEmpty => daysNewestFirst.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is MealHistory &&
      other.days == days &&
      listEquals(other.daysNewestFirst, daysNewestFirst);

  @override
  int get hashCode => Object.hash(days, Object.hashAll(daysNewestFirst));
}

/// Groups [entries] (any order) per stored local day, newest day first. Pure.
MealHistory buildMealHistory({
  required int days,
  required Iterable<MealEntry> entries,
}) {
  final byDay = <LocalDate, List<MealEntry>>{};
  for (final entry in entries) {
    byDay.putIfAbsent(entry.localDate, () => []).add(entry);
  }
  final dates = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return MealHistory(
    days: days,
    daysNewestFirst: List.unmodifiable([
      for (final date in dates) buildMealDay(date: date, entries: byDay[date]!),
    ]),
  );
}
