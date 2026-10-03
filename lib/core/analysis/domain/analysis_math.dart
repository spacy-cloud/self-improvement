/// Small exact-arithmetic helpers of the analysis domain.
///
/// Averages and ratios are kept as integer pairs ([Fraction]) until the last
/// step, so percentages and deltas are never distorted by accumulated floating
/// point noise: every derived double is a single division of two integers.
library;

/// An exact rational number `numerator / denominator` with a positive
/// denominator.
///
/// Examples: an average of steps is `Fraction(totalSteps, recordedDays)`; a
/// fulfilment ratio in percent is `Fraction(100 * fulfilled, applicable)`.
final class Fraction {
  const Fraction(this.numerator, this.denominator)
    : assert(denominator > 0, 'The denominator must be positive');

  final int numerator;
  final int denominator;

  /// The quotient as a double: one correctly rounded division.
  double get value => numerator / denominator;

  /// The quotient rounded half away from zero.
  int get rounded => roundedQuotient(numerator, denominator);

  @override
  String toString() => '$numerator/$denominator';
}

/// `numerator / denominator` rounded half away from zero, in integer
/// arithmetic (`7/2` is 4, `-7/2` is -4, `5/3` is 2, `1/3` is 0).
int roundedQuotient(int numerator, int denominator) {
  assert(denominator > 0, 'The denominator must be positive');
  final magnitude = (2 * numerator.abs() + denominator) ~/ (2 * denominator);
  return numerator < 0 ? -magnitude : magnitude;
}
