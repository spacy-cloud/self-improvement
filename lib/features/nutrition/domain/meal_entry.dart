import 'package:flutter/foundation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// A stored meal. [kcal] is optional: null means "not given", a deliberate 0
/// is a value of its own.
@immutable
final class MealEntry {
  const MealEntry({
    required this.id,
    required this.name,
    required this.occurredAtUtc,
    required this.localDate,
    required this.timezoneId,
    required this.createdAtUtc,
    required this.rowVersion,
    this.kcal,
    this.note,
  });

  final String id;

  /// 1 to 80 characters, trimmed.
  final String name;

  /// Integer kilocalories 0 to 5000, or null when the user gave none. Never
  /// derived from the name.
  final int? kcal;

  /// When the meal happened (UTC).
  final DateTime occurredAtUtc;

  /// Business date frozen when the meal was created (or its time changed).
  final LocalDate localDate;

  /// IANA zone frozen together with [localDate].
  final String timezoneId;

  /// When the record was created (UTC); orders meals with equal times.
  final DateTime createdAtUtc;

  /// Optional free text, at most 500 characters; null means none.
  final String? note;

  /// Incremented on every change; used for conflict detection.
  final int rowVersion;

  /// Whether the user gave a calorie value (a deliberate 0 counts).
  bool get hasKcal => kcal != null;

  @override
  bool operator ==(Object other) =>
      other is MealEntry &&
      other.id == id &&
      other.name == name &&
      other.kcal == kcal &&
      other.occurredAtUtc == occurredAtUtc &&
      other.localDate == localDate &&
      other.timezoneId == timezoneId &&
      other.createdAtUtc == createdAtUtc &&
      other.note == note &&
      other.rowVersion == rowVersion;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kcal,
    occurredAtUtc,
    localDate,
    timezoneId,
    createdAtUtc,
    note,
    rowVersion,
  );

  @override
  String toString() => 'MealEntry($id, $localDate, kcal: $kcal)';
}

/// User input for creating or editing a meal.
@immutable
final class MealDraft {
  const MealDraft({
    required this.name,
    required this.occurredAtUtc,
    this.kcal,
    this.note,
  });

  /// The meal name; trimmed by validation, 1 to 80 characters afterwards.
  final String name;

  /// Integer kilocalories 0 to 5000; null means "not given" (NOT zero).
  final int? kcal;

  /// When the meal happened (UTC); not in the future, not before 2000-01-01.
  final DateTime occurredAtUtc;

  /// Free text, at most 500 characters after trimming; blank means none.
  final String? note;
}

/// The newest-first order of meals: later meals first; equal times fall back
/// to the creation time and finally the id so the order is total.
int compareMealNewestFirst(MealEntry a, MealEntry b) {
  final byTime = b.occurredAtUtc.compareTo(a.occurredAtUtc);
  if (byTime != 0) {
    return byTime;
  }
  final byCreation = b.createdAtUtc.compareTo(a.createdAtUtc);
  if (byCreation != 0) {
    return byCreation;
  }
  return b.id.compareTo(a.id);
}
