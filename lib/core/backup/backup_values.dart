import 'package:self_improvement/shared/local_date.dart';

/// Pure helpers for the scalar value formats of the backup contract.
abstract final class BackupValues {
  static final RegExp _instantPattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3})Z$',
  );

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// Formats a UTC instant as `YYYY-MM-DDTHH:mm:ss.SSSZ` (millisecond
  /// precision, always `Z`). Sub-millisecond parts are dropped.
  static String formatInstant(DateTime instant) {
    final utc = instant.toUtc();
    String pad(int value, int width) => value.toString().padLeft(width, '0');
    return '${pad(utc.year, 4)}-${pad(utc.month, 2)}-${pad(utc.day, 2)}'
        'T${pad(utc.hour, 2)}:${pad(utc.minute, 2)}:${pad(utc.second, 2)}'
        '.${pad(utc.millisecond, 3)}Z';
  }

  /// Strict inverse of [formatInstant]: exactly four year digits, a real
  /// calendar date, hour 00-23, minute and second 00-59, exactly three
  /// fractional digits and the `Z` suffix. Returns `null` for anything else
  /// (offsets, missing milliseconds, `24:00`, `2026-02-30`, ...).
  static DateTime? tryParseInstant(String text) {
    final match = _instantPattern.firstMatch(text);
    if (match == null) {
      return null;
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    final millisecond = int.parse(match.group(7)!);
    if (LocalDate.tryCreate(year, month, day) == null ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      return null;
    }
    return DateTime.utc(year, month, day, hour, minute, second, millisecond);
  }

  /// Canonical lower case UUID shape `8-4-4-4-12` hexadecimal digits.
  static bool isUuid(String text) => _uuidPattern.hasMatch(text);

  /// Number of characters the way SQLite's `length()` counts them: Unicode
  /// code points, not UTF-16 code units (an emoji counts once).
  static int characterCount(String text) => text.runes.length;

  /// Whether [text] contains characters that cannot be stored faithfully: the
  /// NUL character (SQLite `length()` stops at it) or unpaired UTF-16
  /// surrogates (not valid Unicode text).
  static bool hasInvalidCharacters(String text) {
    final units = text.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit == 0) {
        return true;
      }
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (i + 1 >= units.length) {
          return true;
        }
        final next = units[i + 1];
        if (next < 0xDC00 || next > 0xDFFF) {
          return true;
        }
        i++;
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        return true;
      }
    }
    return false;
  }
}
