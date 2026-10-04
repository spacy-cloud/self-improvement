/// Strict parsing of the optional calorie field with German hints.
library;

import 'package:self_improvement/features/nutrition/domain/nutrition_rules.dart';
import 'package:self_improvement/shared/number_format.dart';

/// Smallest accepted calorie value (a deliberate 0 is valid).
const int minMealKcal = 0;

/// Largest accepted calorie value. A technical input limit.
const int maxMealKcal = 5000;

/// Longest meal name in characters after trimming.
const int maxMealNameLength = 80;

/// Why a calorie text was rejected. An empty field is NOT an error: it means
/// "not given".
enum KcalError {
  /// Not a plain whole number (letters, units, decimals, thousands
  /// separators, signs, exponent, other scripts' digits).
  notAWholeNumber,

  /// Above 5000 kcal.
  aboveMaximum,
}

/// Result of [parseKcal].
sealed class KcalParseResult {
  const KcalParseResult();
}

/// A valid input: [kcal] is the value, or null when the field was empty
/// ("not given"). Zero is a value, not "not given".
final class KcalParsed extends KcalParseResult {
  const KcalParsed(this.kcal);

  final int? kcal;
}

/// A rejected calorie text with the reason.
final class KcalInvalid extends KcalParseResult {
  const KcalInvalid(this.error);

  final KcalError error;
}

/// Parses the optional calorie field.
///
/// Empty or blank text is `KcalParsed(null)` (not given). `0` is `KcalParsed(0)`.
/// Whole numbers 0 to 5000 are valid; `450,5`, `1.200`, `450 kcal`, `-1` and
/// `abc` are [KcalError.notAWholeNumber]; anything above 5000 is
/// [KcalError.aboveMaximum].
KcalParseResult parseKcal(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return const KcalParsed(null);
  }
  final kcal = parseDigits(text);
  if (kcal == null) {
    return const KcalInvalid(KcalError.notAWholeNumber);
  }
  if (kcal > maxMealKcal) {
    return const KcalInvalid(KcalError.aboveMaximum);
  }
  return KcalParsed(kcal);
}

/// German hint when the calories are outside 0 to 5000.
final String mealKcalRangeMessage =
    'Bitte gib Kalorien zwischen $minMealKcal und '
    '${formatThousands(maxMealKcal)} kcal ein oder lass das Feld leer.';

/// German hint for [parseKcal] and the repository range check.
String kcalErrorMessage(KcalError error) => switch (error) {
  KcalError.notAWholeNumber =>
    'Bitte gib die Kalorien als ganze Zahl ein, zum Beispiel 450, '
        'oder lass das Feld leer.',
  KcalError.aboveMaximum => mealKcalRangeMessage,
};
