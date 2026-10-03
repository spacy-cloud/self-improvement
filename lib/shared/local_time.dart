import 'package:flutter/foundation.dart';

/// A wall clock time of day (`HH:mm`), e.g. for reminders. No time zone.
@immutable
final class LocalTime implements Comparable<LocalTime> {
  /// Creates a time; throws [ArgumentError] for out of range components.
  const LocalTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24, 'hour out of range'),
      assert(minute >= 0 && minute < 60, 'minute out of range');

  /// Strict parser for `HH:mm`; returns `null` for any other input.
  static LocalTime? tryParse(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) {
      return null;
    }
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) {
      return null;
    }
    return LocalTime(hour, minute);
  }

  /// Strict parser for `HH:mm`; throws [FormatException] otherwise.
  factory LocalTime.parse(String value) {
    final time = tryParse(value);
    if (time == null) {
      throw FormatException('Not an HH:mm time', value);
    }
    return time;
  }

  static final RegExp _pattern = RegExp(r'^(\d{2}):(\d{2})$');

  final int hour;
  final int minute;

  /// Minutes since midnight.
  int get minutesOfDay => hour * 60 + minute;

  /// `HH:mm`.
  String toIso() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(LocalTime other) => minutesOfDay.compareTo(other.minutesOfDay);

  @override
  bool operator ==(Object other) =>
      other is LocalTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => toIso();
}
