import 'package:flutter/foundation.dart';

/// A calendar date without time zone: the frozen "business date" (Fachdatum)
/// of a record, formatted as `YYYY-MM-DD`.
///
/// All calendar arithmetic is done on the civil calendar (never by adding
/// fixed 24 hour durations to zoned instants), so daylight saving time changes
/// cannot shift a day.
@immutable
final class LocalDate implements Comparable<LocalDate> {
  /// Creates a date; throws [ArgumentError] if it is not a real calendar date.
  factory LocalDate(int year, int month, int day) {
    final date = tryCreate(year, month, day);
    if (date == null) {
      throw ArgumentError('Not a valid calendar date: $year-$month-$day');
    }
    return date;
  }

  const LocalDate._(this.year, this.month, this.day);

  /// Returns `null` when the components are not a real calendar date.
  static LocalDate? tryCreate(int year, int month, int day) {
    if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1) {
      return null;
    }
    if (day > daysInMonth(year, month)) {
      return null;
    }
    return LocalDate._(year, month, day);
  }

  /// Strict parser for `YYYY-MM-DD`; throws [FormatException] otherwise.
  factory LocalDate.parse(String iso) {
    final date = tryParse(iso);
    if (date == null) {
      throw FormatException('Not a YYYY-MM-DD date', iso);
    }
    return date;
  }

  /// Strict parser for `YYYY-MM-DD`; returns `null` for any other input
  /// (no whitespace, no time part, no short forms, real dates only).
  static LocalDate? tryParse(String iso) {
    final match = _isoPattern.firstMatch(iso);
    if (match == null) {
      return null;
    }
    return tryCreate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  /// Takes the wall clock components of [dateTime]. Callers pass a value that
  /// is already expressed in the zone whose calendar day is wanted.
  factory LocalDate.fromDateTime(DateTime dateTime) =>
      LocalDate(dateTime.year, dateTime.month, dateTime.day);

  static final RegExp _isoPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// Number of days of [month] in [year] (Gregorian leap rules).
  static int daysInMonth(int year, int month) {
    switch (month) {
      case 2:
        final leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
        return leap ? 29 : 28;
      case 4:
      case 6:
      case 9:
      case 11:
        return 30;
      default:
        return 31;
    }
  }

  final int year;
  final int month;
  final int day;

  /// ISO weekday: Monday = 1 ... Sunday = 7.
  int get weekday => _asUtc.weekday;

  /// 1-based day of the year.
  int get dayOfYear => _asUtc.difference(DateTime.utc(year)).inDays + 1;

  /// The Monday of the week (Monday to Sunday) containing this date.
  LocalDate get startOfWeek => addDays(-(weekday - DateTime.monday));

  /// The first day of the month containing this date.
  LocalDate get startOfMonth => LocalDate._(year, month, 1);

  /// Calendar arithmetic; [days] may be negative.
  LocalDate addDays(int days) {
    final shifted = DateTime.utc(year, month, day + days);
    return LocalDate._(shifted.year, shifted.month, shifted.day);
  }

  /// Signed number of calendar days from this date to [other].
  int daysUntil(LocalDate other) => other._asUtc.difference(_asUtc).inDays;

  /// Inclusive range `[this, end]`; empty when [end] is before this date.
  Iterable<LocalDate> rangeTo(LocalDate end) sync* {
    final count = daysUntil(end);
    for (var offset = 0; offset <= count; offset++) {
      yield addDays(offset);
    }
  }

  bool isBefore(LocalDate other) => compareTo(other) < 0;

  bool isAfter(LocalDate other) => compareTo(other) > 0;

  bool operator <(LocalDate other) => isBefore(other);

  bool operator <=(LocalDate other) => compareTo(other) <= 0;

  bool operator >(LocalDate other) => isAfter(other);

  bool operator >=(LocalDate other) => compareTo(other) >= 0;

  /// The earlier of two dates.
  static LocalDate earlier(LocalDate a, LocalDate b) => a <= b ? a : b;

  /// The later of two dates.
  static LocalDate later(LocalDate a, LocalDate b) => a >= b ? a : b;

  /// `YYYY-MM-DD`.
  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// Midnight UTC of this civil date; only for pure calendar arithmetic and
  /// formatting, never a business instant.
  DateTime toUtcMidnight() => _asUtc;

  DateTime get _asUtc => DateTime.utc(year, month, day);

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) {
      return year.compareTo(other.year);
    }
    if (month != other.month) {
      return month.compareTo(other.month);
    }
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}
