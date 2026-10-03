/// Typed comparison of one figure between the current period and the directly
/// preceding period of the same length.
///
/// The rules (specification section 12 and ticket BS-71):
///
/// - A comparison needs a fitting base. It is a [NoComparison] ("Noch kein
///   Vergleich") when
///   1. the previous period is not completely inside the usage window, i.e. it
///      starts before the profile start date ([NoComparisonReason.previousPeriodBeforeStart]),
///      or the usage start is unknown ([NoComparisonReason.noUsageStart]),
///   2. the previous or the current period has no data for the figure
///      ([NoComparisonReason.noPreviousData], [NoComparisonReason.noCurrentData]),
///   3. the data of the two periods are not comparable
///      ([NoComparisonReason.incompleteCalories]),
///   4. a percentage is asked for and the previous value is 0 or negative
///      ([NoComparisonReason.previousIsZero]).
///   When several reasons apply, the first one in this order is reported.
/// - Otherwise the result is a [ComparisonDelta] with the difference
///   `current - previous` and, only for [ComparisonKind.relative], the
///   percentage `100 * (current - previous) / previous`.
/// - Averages are compared as averages (each over its own recorded days),
///   never totals of periods with a different coverage.
/// - Deltas are neutral numbers. Nothing in this file implies good or bad.
library;

import 'package:self_improvement/core/analysis/domain/analysis_math.dart';
import 'package:self_improvement/shared/local_date.dart';

/// What a figure measures. It decides number formatting and wording of the
/// ready-made German texts; values of different units are never compared.
enum FigureUnit {
  /// Steps; averages are shown as whole steps.
  steps,

  /// Water in millilitres; shown as litres (`2,15 l`).
  milliliters,

  /// A body weight level in grams; shown as kilograms (`71,5 kg`).
  grams,

  /// A signed weight change in grams; shown as signed kilograms
  /// (`−0,3 kg`).
  gramsChange,

  /// A number of workout entries.
  workouts,

  /// Workout minutes (shown as `45 min` or `1 h 15 min`).
  workoutMinutes,

  /// Completed focus time in seconds; shown in whole minutes.
  focusSeconds,

  /// A number of completed focus sessions.
  focusSessions,

  /// A number of completed tasks.
  tasks,

  /// A number of meals.
  meals,

  /// Kilocalories.
  kcal,

  /// A ratio in percent (0 to 100). A difference of two ratios is a number of
  /// percentage points, never a percentage of a percentage.
  percent,
}

/// How two periods are compared.
enum ComparisonKind {
  /// Difference and percentage of the previous value. Needs a previous value
  /// above 0.
  relative,

  /// Difference only (weight): a percentage of a body weight or of a change
  /// would be meaningless.
  absolute,

  /// Difference of two ratios in percentage points (habits, daily goals).
  percentagePoints,
}

/// Why no comparison is possible. The visible text is always
/// "Noch kein Vergleich"; the reason explains it.
enum NoComparisonReason {
  /// The usage start (profile start date) is unknown.
  noUsageStart,

  /// The previous period starts before the usage start: it is not completely
  /// inside the usage window and must not be compared with a full period.
  previousPeriodBeforeStart,

  /// The previous period has no data for this figure.
  noPreviousData,

  /// The current period has no data for this figure.
  noCurrentData,

  /// A percentage is asked for but the previous value is 0 (or negative).
  previousIsZero,

  /// Known calories are only comparable when both periods are complete.
  incompleteCalories,
}

/// The typed result of a comparison.
sealed class ComparisonResult {
  const ComparisonResult();
}

/// No comparison is possible ("Noch kein Vergleich").
final class NoComparison extends ComparisonResult {
  const NoComparison(this.reason);

  final NoComparisonReason reason;

  @override
  String toString() => 'NoComparison(${reason.name})';
}

/// A comparison with a fitting base.
final class ComparisonDelta extends ComparisonResult {
  const ComparisonDelta({required this.delta, this.percent});

  /// `current - previous` in the unit of the figure (percentage points for
  /// [FigureUnit.percent]). Exactly 0 means unchanged.
  final double delta;

  /// `100 * (current - previous) / previous`; only for
  /// [ComparisonKind.relative], otherwise `null`.
  final double? percent;

  /// [percent] rounded half away from zero to a whole percent.
  int? get percentRounded => percent?.round();

  @override
  String toString() => 'ComparisonDelta(delta: $delta, percent: $percent)';
}

/// Current and previous value of one figure plus the typed comparison.
///
/// [current] and [previous] are `null` when the period has no data for the
/// figure (never a fake 0). Values are in the unit of [unit]: steps, ml,
/// grams, counts, minutes (workouts), seconds (focus), kcal or percent.
final class PeriodComparison {
  const PeriodComparison({
    required this.unit,
    required this.current,
    required this.previous,
    required this.result,
  });

  final FigureUnit unit;
  final double? current;
  final double? previous;
  final ComparisonResult result;

  /// Whether a comparison with a fitting base exists.
  bool get isAvailable => result is ComparisonDelta;

  /// `current - previous`, `null` without a comparison.
  double? get delta => switch (result) {
    ComparisonDelta(:final delta) => delta,
    NoComparison() => null,
  };

  /// Relative change in percent, `null` without a comparison or for kinds
  /// without a percentage.
  double? get percent => switch (result) {
    ComparisonDelta(:final percent) => percent,
    NoComparison() => null,
  };

  /// [percent] rounded half away from zero.
  int? get percentRounded => percent?.round();

  /// The reason when no comparison is possible, otherwise `null`.
  NoComparisonReason? get reason => switch (result) {
    NoComparison(:final reason) => reason,
    ComparisonDelta() => null,
  };
}

/// Checks whether the previous period fits the usage window.
///
/// The previous period has to lie COMPLETELY inside the usage window, i.e. it
/// must not start before [usageStart] (the profile start date). Otherwise the
/// result says why no comparison is allowed; `null` means the base fits.
/// A comparison base that is only partly inside the window would compare a
/// partial period with a full one.
NoComparisonReason? comparisonBaseProblem({
  required LocalDate previousStart,
  required LocalDate? usageStart,
}) {
  if (usageStart == null) {
    return NoComparisonReason.noUsageStart;
  }
  if (previousStart.isBefore(usageStart)) {
    return NoComparisonReason.previousPeriodBeforeStart;
  }
  return null;
}

/// Compares [current] with [previous].
///
/// [current] and [previous] are `null` when the period has no data for the
/// figure. [baseProblem] is the result of the usage window check (see
/// [NoComparisonReason.previousPeriodBeforeStart]); [dataProblem] marks data
/// that are present but not comparable (see
/// [NoComparisonReason.incompleteCalories]). The checks run in the order
/// documented at the top of this library.
///
/// Percentages and deltas come from exact integer arithmetic
/// (`100 * (cN * pD - pN * cD) / (cD * pN)`), so rounding to a whole percent
/// is deterministic.
PeriodComparison comparePeriods({
  required FigureUnit unit,
  required ComparisonKind kind,
  required Fraction? current,
  required Fraction? previous,
  NoComparisonReason? baseProblem,
  NoComparisonReason? dataProblem,
}) {
  final ComparisonResult result;
  if (baseProblem != null) {
    result = NoComparison(baseProblem);
  } else if (previous == null) {
    result = const NoComparison(NoComparisonReason.noPreviousData);
  } else if (current == null) {
    result = const NoComparison(NoComparisonReason.noCurrentData);
  } else if (dataProblem != null) {
    result = NoComparison(dataProblem);
  } else if (kind == ComparisonKind.relative && previous.numerator <= 0) {
    result = const NoComparison(NoComparisonReason.previousIsZero);
  } else {
    // (cN / cD) - (pN / pD) = cross / (cD * pD)
    final cross =
        current.numerator * previous.denominator -
        previous.numerator * current.denominator;
    final delta = cross / (current.denominator * previous.denominator);
    final percent = kind == ComparisonKind.relative
        ? (100 * cross) / (current.denominator * previous.numerator)
        : null;
    result = ComparisonDelta(delta: delta, percent: percent);
  }
  return PeriodComparison(
    unit: unit,
    current: current?.value,
    previous: previous?.value,
    result: result,
  );
}
