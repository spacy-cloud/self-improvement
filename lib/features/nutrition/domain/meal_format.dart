/// German display texts for meals: counts, calories and the success messages
/// shown with the undo snackbar. Pure functions without locale data.
library;

import 'package:self_improvement/features/nutrition/domain/meal_summary.dart';
import 'package:self_improvement/shared/number_format.dart';

/// The hint shown next to the known calories when at least one meal has no
/// calorie value (also when no meal has one).
const String kcalIncompleteLabel = 'Kalorien unvollständig';

/// `0 Mahlzeiten`, `1 Mahlzeit`, `3 Mahlzeiten`.
String formatMealCount(int count) =>
    count == 1 ? '1 Mahlzeit' : '$count Mahlzeiten';

/// Calories with a thousands dot: `450 kcal`, `1.250 kcal`.
String formatKcal(int kcal) => '${formatThousands(kcal)} kcal';

/// The one-line day summary the overview and the dashboard card show:
///
/// - no meals: `Noch keine Mahlzeit`
/// - all with calories: `3 Mahlzeiten · 1.250 kcal`
/// - some missing: `3 Mahlzeiten · 800 kcal · Kalorien unvollständig`
/// - all missing: `2 Mahlzeiten · Kalorien unvollständig` (no calorie figure,
///   never "0 kcal")
String mealSummaryText(MealSummary summary) {
  if (!summary.hasMeals) {
    return 'Noch keine Mahlzeit';
  }
  final parts = <String>[formatMealCount(summary.mealCount)];
  final known = summary.knownKcal;
  if (known != null) {
    parts.add(formatKcal(known));
  }
  if (summary.isIncomplete) {
    parts.add(kcalIncompleteLabel);
  }
  return parts.join(' · ');
}

/// Snackbar text after a saved meal.
const String mealSavedMessage = 'Mahlzeit gespeichert';

/// Snackbar text after an edit.
const String mealUpdatedMessage = 'Mahlzeit aktualisiert';

/// Snackbar text after a delete.
const String mealDeletedMessage = 'Mahlzeit gelöscht';
