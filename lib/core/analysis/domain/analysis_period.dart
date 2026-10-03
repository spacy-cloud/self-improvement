/// The analysis periods and their calendar arithmetic.
///
/// A period is 7, 30 or 90 local calendar days ending TODAY, today included
/// ("inklusive heute"). Its comparison base is the directly preceding period
/// of the SAME length. All dates are business dates (`LocalDate`); only
/// calendar arithmetic is used, never 24 hour durations, so daylight saving
/// time, month and year boundaries cannot shift a day.
library;

import 'package:self_improvement/core/analysis/domain/analysis_dates.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The selectable period lengths.
enum AnalysisPeriodLength {
  days7(7),
  days30(30),
  days90(90);

  const AnalysisPeriodLength(this.days);

  /// Number of calendar days, today included.
  final int days;

  /// The length for [days], or `null` when it is not 7, 30 or 90.
  static AnalysisPeriodLength? tryFromDays(int days) {
    for (final length in values) {
      if (length.days == days) {
        return length;
      }
    }
    return null;
  }

  /// Label of the selector: `7 Tage`.
  String get label => '$days Tage';

  /// Spoken label of the selector: `Zeitraum 7 Tage`.
  String get semanticsLabel => 'Zeitraum $days Tage';

  /// Name of the comparison base inside a sentence: `vorherige 7 Tage`.
  /// Never a blanket "Vorwoche": 30 and 90 days are no weeks.
  String get previousLabel => 'vorherige $days Tage';

  /// The comparison base as the start of a sentence or a column header:
  /// `Vorherige 7 Tage`.
  String get previousTitle => 'Vorherige $days Tage';

  /// The comparison base in the dative: `den vorherigen 7 Tagen`.
  String get previousDative => 'den vorherigen $days Tagen';

  /// The comparison phrase: `gegenüber den vorherigen 7 Tagen`.
  String get againstPrevious => 'gegenüber $previousDative';

  /// Title of the current period: `Letzte 7 Tage`.
  String get currentTitle => 'Letzte $days Tage';
}

/// One analysis period with its comparison base, anchored at [today].
///
/// ```text
/// today = 2026-10-03, 7 days
///   current   2026-09-27 .. 2026-10-03   (header: 27.09. bis 03.10.2026, inklusive heute)
///   previous  2026-09-20 .. 2026-09-26   (the 7 days before)
/// ```
///
/// The first and last days are included: day `-6` (`-29`, `-89`) belongs to
/// the current period, day `-7` (`-30`, `-90`) to the previous one.
final class AnalysisPeriodSpec {
  const AnalysisPeriodSpec({required this.length, required this.today});

  final AnalysisPeriodLength length;

  /// The local calendar day "today" (injected, never read from a clock here).
  final LocalDate today;

  /// Number of days of the current and of the previous period.
  int get days => length.days;

  /// First day of the current period (inclusive).
  LocalDate get start => today.addDays(1 - days);

  /// Last day of the current period: today (inclusive).
  LocalDate get end => today;

  /// First day of the previous period (inclusive).
  LocalDate get previousStart => today.addDays(1 - 2 * days);

  /// Last day of the previous period (inclusive): the day before [start].
  LocalDate get previousEnd => today.addDays(-days);

  /// First day of the combined range that has to be loaded: [previousStart].
  LocalDate get windowStart => previousStart;

  bool containsCurrent(LocalDate day) =>
      !day.isBefore(start) && !day.isAfter(end);

  bool containsPrevious(LocalDate day) =>
      !day.isBefore(previousStart) && !day.isAfter(previousEnd);

  /// The days of the current period, oldest first, today last.
  List<LocalDate> get currentDays => start.rangeTo(end).toList(growable: false);

  /// The days of the previous period, oldest first.
  List<LocalDate> get previousDays =>
      previousStart.rangeTo(previousEnd).toList(growable: false);

  /// Whether the previous period fits the usage window: `null` when it lies
  /// completely inside (it does not start before [usageStart]), otherwise the
  /// reason why no comparison is allowed. See [comparisonBaseProblem].
  NoComparisonReason? baseProblem(LocalDate? usageStart) =>
      comparisonBaseProblem(
        previousStart: previousStart,
        usageStart: usageStart,
      );

  /// The first day on which this period length can be compared at all: the
  /// day the previous period starts exactly on [usageStart]. `null` when the
  /// usage start is unknown.
  LocalDate? comparisonAvailableFrom(LocalDate? usageStart) =>
      usageStart?.addDays(2 * days - 1);

  /// Header of the current period: `27.09. bis 03.10.2026, inklusive heute`.
  String get headerText => '${formatDateRange(start, end)}, inklusive heute';

  /// Date range of the previous period: `20.09. bis 26.09.2026`.
  String get previousRangeText => formatDateRange(previousStart, previousEnd);

  /// Header of the previous period: `Vorherige 7 Tage: 20.09. bis 26.09.2026`.
  String get previousHeaderText =>
      '${length.previousTitle}: $previousRangeText';

  /// Spoken header: `Zeitraum 7 Tage, 27.09. bis 03.10.2026, inklusive heute`.
  String get semanticsLabel => '${length.semanticsLabel}, $headerText';

  @override
  bool operator ==(Object other) =>
      other is AnalysisPeriodSpec &&
      other.length == length &&
      other.today == today;

  @override
  int get hashCode => Object.hash(length, today);

  @override
  String toString() => 'AnalysisPeriodSpec(${length.days} days, $today)';
}
