/// Parsing of the manual daily step total typed by the user.
library;

/// Smallest and largest accepted daily total.
const int minStepsPerDay = 0;
const int maxStepsPerDay = 100000;

/// Why a step total text was rejected.
enum StepsError {
  /// Nothing entered.
  empty,

  /// Not a whole number (decimals, signs, letters, exponents, spaces).
  invalidFormat,

  /// Above 100.000.
  aboveMaximum,
}

/// Result of [parseSteps].
sealed class StepsParseResult {
  const StepsParseResult();
}

final class StepsParsed extends StepsParseResult {
  const StepsParsed(this.steps);

  final int steps;
}

final class StepsInvalid extends StepsParseResult {
  const StepsInvalid(this.error);

  final StepsError error;
}

final RegExp _plainDigits = RegExp(r'^\d+$');
final RegExp _germanGrouping = RegExp(r'^\d{1,3}(\.\d{3})+$');

/// Parses a daily step total.
///
/// Whole numbers only: digits, optionally German thousands grouping with dots
/// (`10.000`). `0` is valid (a recorded zero, different from no record).
/// No decimals, signs, exponents or spaces. Range 0 to 100.000.
StepsParseResult parseSteps(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return const StepsInvalid(StepsError.empty);
  }
  final String digits;
  if (_plainDigits.hasMatch(text)) {
    digits = text;
  } else if (_germanGrouping.hasMatch(text)) {
    digits = text.replaceAll('.', '');
  } else {
    return const StepsInvalid(StepsError.invalidFormat);
  }
  final trimmed = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (trimmed.length > 6) {
    return const StepsInvalid(StepsError.aboveMaximum);
  }
  final value = int.parse(trimmed);
  if (value > maxStepsPerDay) {
    return const StepsInvalid(StepsError.aboveMaximum);
  }
  return StepsParsed(value);
}

/// German hint for a rejected input.
String stepsErrorMessage(StepsError error) => switch (error) {
  StepsError.empty => 'Bitte gib deine Schritte ein.',
  StepsError.invalidFormat =>
    'Bitte gib eine ganze Zahl ein, zum Beispiel 7450.',
  StepsError.aboveMaximum => 'Bitte gib höchstens 100.000 Schritte ein.',
};
