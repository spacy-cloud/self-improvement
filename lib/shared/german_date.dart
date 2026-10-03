/// Deterministic German date texts without locale data (identical in tests,
/// on device and independent of the system locale). The UI language is German.
library;

import 'package:self_improvement/shared/local_date.dart';

const List<String> _weekdaysLong = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];

const List<String> _weekdaysShort = [
  'Mo.',
  'Di.',
  'Mi.',
  'Do.',
  'Fr.',
  'Sa.',
  'So.',
];

const List<String> _weekdaysTwo = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

const List<String> _monthsLong = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

const List<String> _monthsShort = [
  'Jan.',
  'Feb.',
  'März',
  'Apr.',
  'Mai',
  'Juni',
  'Juli',
  'Aug.',
  'Sep.',
  'Okt.',
  'Nov.',
  'Dez.',
];

/// `Montag` for a Monday.
String weekdayLong(LocalDate date) => _weekdaysLong[date.weekday - 1];

/// `Mo.` for a Monday.
String weekdayShort(LocalDate date) => _weekdaysShort[date.weekday - 1];

/// `Mo` for a Monday (chart axes).
String weekdayTwoLetters(LocalDate date) => _weekdaysTwo[date.weekday - 1];

/// `September` for month 9.
String monthLong(int month) => _monthsLong[month - 1];

/// `Montag, 14. September`.
String formatDateLong(LocalDate date) =>
    '${weekdayLong(date)}, ${date.day}. ${monthLong(date.month)}';

/// `Mo., 14. Sep.`; with [contextYear] a different year is appended
/// (`Mo., 14. Sep. 2025`).
String formatDateShort(LocalDate date, {int? contextYear}) {
  final base = '${weekdayShort(date)}, ${formatDayMonth(date)}';
  return contextYear != null && date.year != contextYear
      ? '$base ${date.year}'
      : base;
}

/// `14. Sep.`.
String formatDayMonth(LocalDate date) =>
    '${date.day}. ${_monthsShort[date.month - 1]}';

/// `SEPTEMBER 2026` (month group headers).
String formatMonthYearUpper(LocalDate date) =>
    '${monthLong(date.month).toUpperCase()} ${date.year}';

/// `Heute`, `Gestern`, the weekday name within the last six days, otherwise
/// the short date (`Mo., 14. Sep.`).
String formatRelativeDay(LocalDate date, LocalDate today) {
  final daysAgo = date.daysUntil(today);
  if (daysAgo == 0) {
    return 'Heute';
  }
  if (daysAgo == 1) {
    return 'Gestern';
  }
  if (daysAgo > 1 && daysAgo < 7) {
    return weekdayLong(date);
  }
  return formatDateShort(date, contextYear: today.year);
}
