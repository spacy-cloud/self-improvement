import 'package:flutter/foundation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// A stored weight measurement.
@immutable
final class WeightEntry {
  const WeightEntry({
    required this.id,
    required this.weightGrams,
    required this.occurredAtUtc,
    required this.localDate,
    required this.timezoneId,
    required this.beforeToilet,
    required this.afterDrinking,
    required this.afterEating,
    required this.rowVersion,
    required this.gamificationEligible,
    this.note,
  });

  final String id;

  /// Integer grams (71,5 kg is 71500).
  final int weightGrams;

  final DateTime occurredAtUtc;

  /// Business date frozen when the measurement was taken.
  final LocalDate localDate;

  final String timezoneId;
  final bool beforeToilet;
  final bool afterDrinking;
  final bool afterEating;
  final String? note;

  /// Incremented on every change; used for conflict detection.
  final int rowVersion;

  /// Frozen at creation (was gamification enabled then).
  final bool gamificationEligible;

  /// "Nüchtern" is only derived text: true when neither eating nor drinking
  /// was flagged. The app makes no claim about measurement quality.
  bool get isFasted => !afterEating && !afterDrinking;
}

/// User input for creating or editing a measurement.
@immutable
final class WeightDraft {
  const WeightDraft({
    required this.weightGrams,
    required this.occurredAtUtc,
    this.beforeToilet = false,
    this.afterDrinking = false,
    this.afterEating = false,
    this.note,
  });

  final int weightGrams;
  final DateTime occurredAtUtc;
  final bool beforeToilet;
  final bool afterDrinking;
  final bool afterEating;

  /// Free text, at most 500 characters after trimming; empty means none.
  final String? note;
}
