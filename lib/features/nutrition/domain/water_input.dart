/// Strict parsing of the water amount and the daily water target typed by the
/// user, with German hints.
library;

import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/features/nutrition/domain/nutrition_rules.dart';
import 'package:self_improvement/shared/number_format.dart';

/// Smallest accepted amount of one entry in ml. A technical input limit.
const int minWaterEntryMl = 50;

/// Largest accepted amount of one entry in ml. A technical input limit.
const int maxWaterEntryMl = 2000;

/// The amounts of the one-tap quick add buttons, in the order they are shown.
const List<int> waterQuickAmountsMl = [250, 500];

/// Step of the plus/minus buttons of the custom amount in ml.
const int waterAmountStepMl = 10;

/// Value the custom amount buttons start from when nothing valid is typed.
const int waterAmountStartMl = 250;

/// Smallest daily water target in ml (from the goal definition).
int get minWaterGoalMl => GoalType.water.minTarget;

/// Largest daily water target in ml (from the goal definition).
int get maxWaterGoalMl => GoalType.water.maxTarget;

/// Step of the daily water target in ml (from the goal definition).
int get waterGoalStepMl => GoalType.water.step;

/// Daily water target used before the user chose one, in ml.
int get defaultWaterGoalMl => GoalType.water.defaultTarget;

/// Why an amount text was rejected.
enum WaterMlError {
  /// Nothing entered.
  empty,

  /// Not a plain whole number (letters, units, decimals, thousands
  /// separators, signs, exponent, other scripts' digits).
  notAWholeNumber,

  /// Below 50 ml (including 0).
  belowMinimum,

  /// Above 2000 ml.
  aboveMaximum,
}

/// Result of [parseWaterMl].
sealed class WaterMlParseResult {
  const WaterMlParseResult();
}

/// A valid amount in ml.
final class WaterMlParsed extends WaterMlParseResult {
  const WaterMlParsed(this.ml);

  final int ml;
}

/// A rejected amount text with the reason.
final class WaterMlInvalid extends WaterMlParseResult {
  const WaterMlInvalid(this.error);

  final WaterMlError error;
}

/// Parses the amount of one entry typed by the user.
///
/// Whole millilitres only: `250` and ` 250 ` are valid, `250,5`, `1.500`,
/// `250 ml`, `-5` and `abc` are [WaterMlError.notAWholeNumber] (no silent
/// interpretation). Range 50 to 2000 inclusive.
WaterMlParseResult parseWaterMl(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return const WaterMlInvalid(WaterMlError.empty);
  }
  final ml = parseDigits(text);
  if (ml == null) {
    return const WaterMlInvalid(WaterMlError.notAWholeNumber);
  }
  if (ml < minWaterEntryMl) {
    return const WaterMlInvalid(WaterMlError.belowMinimum);
  }
  if (ml > maxWaterEntryMl) {
    return const WaterMlInvalid(WaterMlError.aboveMaximum);
  }
  return WaterMlParsed(ml);
}

/// Applies a plus/minus step to the typed amount: [direction] times
/// [waterAmountStepMl] from the typed whole number, clamped to 50 to 2000 ml.
/// When the text is not a whole number (empty, letters), the result is
/// [startMl] itself, so the first press shows a sensible starting amount.
int stepWaterMl({
  required String currentText,
  required int direction,
  int startMl = waterAmountStartMl,
}) {
  final typed = parseDigits(currentText.trim());
  if (typed == null) {
    return startMl;
  }
  return (typed + direction * waterAmountStepMl).clamp(
    minWaterEntryMl,
    maxWaterEntryMl,
  );
}

/// German hint for [parseWaterMl] and the repository range check.
String waterMlErrorMessage(WaterMlError error) => switch (error) {
  WaterMlError.empty => 'Bitte gib die Menge in Millilitern ein.',
  WaterMlError.notAWholeNumber =>
    'Bitte gib eine ganze Zahl in Millilitern ein, zum Beispiel 250.',
  WaterMlError.belowMinimum ||
  WaterMlError.aboveMaximum => waterAmountRangeMessage,
};

/// German hint when the amount is outside 50 to 2000 ml.
final String waterAmountRangeMessage =
    'Bitte gib eine Menge zwischen $minWaterEntryMl und '
    '${formatThousands(maxWaterEntryMl)} ml ein.';

/// Why a daily target text was rejected.
enum WaterGoalError {
  /// Nothing entered.
  empty,

  /// Not a plain whole number.
  notAWholeNumber,

  /// Below 250 ml.
  belowMinimum,

  /// Above 10000 ml.
  aboveMaximum,

  /// Inside the range but not a multiple of 50 ml.
  notOnStep,
}

/// Result of [parseWaterGoalMl].
sealed class WaterGoalParseResult {
  const WaterGoalParseResult();
}

/// A valid daily target in ml.
final class WaterGoalParsed extends WaterGoalParseResult {
  const WaterGoalParsed(this.ml);

  final int ml;
}

/// A rejected target text with the reason.
final class WaterGoalInvalid extends WaterGoalParseResult {
  const WaterGoalInvalid(this.error);

  final WaterGoalError error;
}

/// Parses the daily water target typed by the user: whole millilitres from
/// 250 to 10000 in steps of 50 (the rule of the water goal definition).
WaterGoalParseResult parseWaterGoalMl(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return const WaterGoalInvalid(WaterGoalError.empty);
  }
  final ml = parseDigits(text);
  if (ml == null) {
    return const WaterGoalInvalid(WaterGoalError.notAWholeNumber);
  }
  return switch (GoalType.water.validateTarget(ml)) {
    GoalTargetValidation.valid => WaterGoalParsed(ml),
    GoalTargetValidation.belowMinimum => const WaterGoalInvalid(
      WaterGoalError.belowMinimum,
    ),
    GoalTargetValidation.aboveMaximum => const WaterGoalInvalid(
      WaterGoalError.aboveMaximum,
    ),
    GoalTargetValidation.notOnStep => const WaterGoalInvalid(
      WaterGoalError.notOnStep,
    ),
  };
}

/// German hint for [parseWaterGoalMl] and the goal range check.
String waterGoalErrorMessage(WaterGoalError error) => switch (error) {
  WaterGoalError.empty => 'Bitte gib dein Tagesziel in Millilitern ein.',
  WaterGoalError.notAWholeNumber =>
    'Bitte gib eine ganze Zahl in Millilitern ein, zum Beispiel 2500.',
  WaterGoalError.belowMinimum || WaterGoalError.aboveMaximum =>
    'Bitte gib ein Tagesziel zwischen ${formatThousands(minWaterGoalMl)} und '
        '${formatThousands(maxWaterGoalMl)} ml ein.',
  WaterGoalError.notOnStep =>
    'Das Tagesziel geht in $waterGoalStepMl-ml-Schritten, '
        'zum Beispiel ${formatThousands(defaultWaterGoalMl)} ml.',
};

/// Applies a plus/minus step to the typed target: [direction] times 50 ml,
/// starting from the parsed [currentText] or, when that is not valid, from
/// [fallbackMl]. Returns null if there is nothing to step from. The result is
/// clamped to the valid range.
int? stepWaterGoalMl({
  required String currentText,
  required int direction,
  int? fallbackMl,
}) {
  final parsed = parseWaterGoalMl(currentText);
  final base = switch (parsed) {
    WaterGoalParsed(:final ml) => ml,
    WaterGoalInvalid() => fallbackMl,
  };
  if (base == null) {
    return null;
  }
  return (base + direction * waterGoalStepMl).clamp(
    minWaterGoalMl,
    maxWaterGoalMl,
  );
}
