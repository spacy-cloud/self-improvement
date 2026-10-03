import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/meal_format.dart';
import 'package:self_improvement/features/nutrition/domain/meal_summary.dart';
import 'package:self_improvement/shared/number_format.dart';

/// What a meal row shows on the right: the calories, or `Keine Angabe` when
/// none were given. A deliberate 0 is shown as `0 kcal`, never as no value.
String mealKcalText(MealEntry meal) {
  final kcal = meal.kcal;
  return kcal == null ? 'Keine Angabe' : formatKcal(kcal);
}

/// Spoken calories of a meal.
String mealKcalSpoken(MealEntry meal) {
  final kcal = meal.kcal;
  return kcal == null
      ? 'ohne Kalorienangabe'
      : '${formatThousands(kcal)} Kilokalorien';
}

/// `1 Mahlzeit ohne Kalorienangabe`, `2 Mahlzeiten ohne Kalorienangabe`.
String mealsWithoutKcalText(MealSummary summary) {
  final count = summary.mealsWithoutKcal;
  return count == 1
      ? '1 Mahlzeit ohne Kalorienangabe'
      : '$count Mahlzeiten ohne Kalorienangabe';
}

/// The incomplete hint with the number of meals behind it:
/// `Kalorien unvollständig: 1 Mahlzeit ohne Kalorienangabe`.
String mealIncompleteHint(MealSummary summary) =>
    '$kcalIncompleteLabel: ${mealsWithoutKcalText(summary)}';

/// The line under the count on the dashboard card:
/// `1.070 kcal bekannt`, `800 kcal bekannt · Kalorien unvollständig`, or only
/// `Kalorien unvollständig` when no meal has calories (never `0 kcal`).
String mealCardSubtitle(MealSummary summary) {
  final known = summary.knownKcal;
  final parts = <String>[
    if (known != null) '${formatKcal(known)} bekannt',
    if (summary.isIncomplete) kcalIncompleteLabel,
  ];
  return parts.join(' · ');
}

/// Spoken summary of a day of meals for screen readers.
String mealSummarySpoken(MealSummary summary) {
  if (!summary.hasMeals) {
    return 'Noch keine Mahlzeit';
  }
  final known = summary.knownKcal;
  return [
    formatMealCount(summary.mealCount),
    if (known != null) '${formatThousands(known)} Kilokalorien bekannt',
    if (summary.isIncomplete) kcalIncompleteLabel,
  ].join(', ');
}
