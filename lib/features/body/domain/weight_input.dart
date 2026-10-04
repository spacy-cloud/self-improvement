/// Strict parsing and stepping of the weight input field (kilograms).
library;

/// Smallest accepted weight in grams (20.0 kg). A product filter, not a
/// medical norm.
const int minWeightGrams = 20000;

/// Largest accepted weight in grams (350.0 kg).
const int maxWeightGrams = 350000;

/// Step of the plus/minus buttons (0.1 kg).
const int weightStepGrams = 100;

/// Why a weight text was rejected.
enum WeightKgError {
  /// Nothing entered.
  empty,

  /// Not a plain decimal number (letters, exponent, NaN, Infinity, thousands
  /// separators, mixed or repeated separators, signs).
  invalidFormat,

  /// More than one decimal place; the user must correct it, no silent rounding.
  tooManyDecimals,

  /// Below 20,0 kg.
  belowMinimum,

  /// Above 350,0 kg.
  aboveMaximum,
}

/// Result of [parseWeightKg].
sealed class WeightKgParseResult {
  const WeightKgParseResult();
}

/// A valid weight in integer grams (a multiple of 100).
final class WeightKgParsed extends WeightKgParseResult {
  const WeightKgParsed(this.grams);

  final int grams;
}

/// A rejected input with the reason.
final class WeightKgInvalid extends WeightKgParseResult {
  const WeightKgInvalid(this.error);

  final WeightKgError error;
}

final RegExp _plainDecimal = RegExp(r'^(\d+)(?:[.,](\d+))?$');

/// Parses a weight in kilograms typed by the user.
///
/// Comma or period, at most one decimal place. `71`, `71,5` and `71.5` are
/// valid; `71,55` is [WeightKgError.tooManyDecimals]. No thousands separators,
/// exponents, signs, NaN or Infinity. Range 20,0 to 350,0 inclusive.
WeightKgParseResult parseWeightKg(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return const WeightKgInvalid(WeightKgError.empty);
  }
  final match = _plainDecimal.firstMatch(text);
  if (match == null) {
    return const WeightKgInvalid(WeightKgError.invalidFormat);
  }
  final decimals = match.group(2);
  if (decimals != null && decimals.length > 1) {
    return const WeightKgInvalid(WeightKgError.tooManyDecimals);
  }
  final integerPart = match.group(1)!;
  // Guard against absurdly long inputs before parsing.
  if (integerPart.replaceFirst(RegExp(r'^0+'), '').length > 4) {
    return const WeightKgInvalid(WeightKgError.aboveMaximum);
  }
  final tenths =
      int.parse(integerPart) * 10 +
      (decimals == null ? 0 : int.parse(decimals));
  final grams = tenths * 100;
  if (grams < minWeightGrams) {
    return const WeightKgInvalid(WeightKgError.belowMinimum);
  }
  if (grams > maxWeightGrams) {
    return const WeightKgInvalid(WeightKgError.aboveMaximum);
  }
  return WeightKgParsed(grams);
}

/// Applies a plus/minus step to the current text.
///
/// Starts from the parsed [currentText]; if that is not valid, from
/// [fallbackGrams] (e.g. the unconfirmed last value). Returns null if there is
/// nothing to step from. The result is clamped to the valid range.
int? stepWeightGrams({
  required String currentText,
  required int direction,
  int? fallbackGrams,
}) {
  final parsed = parseWeightKg(currentText);
  final base = switch (parsed) {
    WeightKgParsed(:final grams) => grams,
    WeightKgInvalid() => fallbackGrams,
  };
  if (base == null) {
    return null;
  }
  return (base + direction * weightStepGrams).clamp(
    minWeightGrams,
    maxWeightGrams,
  );
}
