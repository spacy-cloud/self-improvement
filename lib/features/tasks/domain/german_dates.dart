/// Small German date texts used by the task and habit read models.
///
/// Implemented without locale data (like `shared/number_format.dart`) so the
/// output is identical in tests, on the device and in every system locale.
library;

import 'package:self_improvement/shared/local_date.dart';

const List<String> _weekdayAbbreviations = [
  'Mo.',
  'Di.',
  'Mi.',
  'Do.',
  'Fr.',
  'Sa.',
  'So.',
];

/// `2026-10-02` -> `02.10.2026`.
String formatGermanDate(LocalDate date) =>
    '${_two(date.day)}.${_two(date.month)}.${date.year}';

/// `2026-10-02` -> `02.10.` (no year).
String formatGermanDayMonth(LocalDate date) =>
    '${_two(date.day)}.${_two(date.month)}.';

/// `2026-10-02` -> `Fr., 02.10.` (abbreviated weekday, no year).
String formatGermanWeekdayDate(LocalDate date) =>
    '${_weekdayAbbreviations[date.weekday - 1]}, ${formatGermanDayMonth(date)}';

String _two(int value) => value.toString().padLeft(2, '0');
