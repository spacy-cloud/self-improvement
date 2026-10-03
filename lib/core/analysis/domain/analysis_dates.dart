/// German date texts for the analysis, derived from the calendar only.
///
/// A small own formatter on purpose: it needs no locale data initialisation
/// and behaves identically in tests and on the device.
library;

import 'package:self_improvement/shared/local_date.dart';

const List<String> _weekdaysShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

const List<String> _weekdaysLong = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];

String _two(int value) => value.toString().padLeft(2, '0');

/// Day and month with trailing dot: `03.10.`.
String formatDayMonth(LocalDate date) =>
    '${_two(date.day)}.${_two(date.month)}.';

/// Full date: `03.10.2026`.
String formatFullDate(LocalDate date) => '${formatDayMonth(date)}${date.year}';

/// Two letter weekday (Monday first): `Sa`.
String weekdayShort(LocalDate date) => _weekdaysShort[date.weekday - 1];

/// Weekday name: `Samstag`.
String weekdayLong(LocalDate date) => _weekdaysLong[date.weekday - 1];

/// Short weekday with day and month: `Sa, 03.10.`.
String formatShortWeekdayDate(LocalDate date) =>
    '${weekdayShort(date)}, ${formatDayMonth(date)}';

/// Long weekday with the full date: `Samstag, 03.10.2026`.
String formatLongWeekdayDate(LocalDate date) =>
    '${weekdayLong(date)}, ${formatFullDate(date)}';

/// A date range as used in headers: `27.09. bis 03.10.2026`.
///
/// The start omits the year when it equals the year of the end
/// (`30.12.2025 bis 05.01.2026` keeps both years). A single day is just the
/// full date.
String formatDateRange(LocalDate start, LocalDate end) {
  if (start == end) {
    return formatFullDate(end);
  }
  final startText = start.year == end.year
      ? formatDayMonth(start)
      : formatFullDate(start);
  return '$startText bis ${formatFullDate(end)}';
}
