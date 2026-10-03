import 'package:flutter/foundation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// A stored drink in millilitres.
@immutable
final class WaterEntry {
  const WaterEntry({
    required this.id,
    required this.amountMl,
    required this.occurredAtUtc,
    required this.localDate,
    required this.timezoneId,
    required this.createdAtUtc,
    required this.rowVersion,
    required this.gamificationEligible,
    this.note,
  });

  final String id;

  /// Integer millilitres, 50 to 2000 per entry.
  final int amountMl;

  /// When the drink happened (UTC).
  final DateTime occurredAtUtc;

  /// Business date frozen when the entry was created (or its time changed).
  /// The day total is the sum over this date, never over a recomputed zone
  /// conversion.
  final LocalDate localDate;

  /// IANA zone frozen together with [localDate].
  final String timezoneId;

  /// When the record was created (UTC); orders entries with equal times.
  final DateTime createdAtUtc;

  /// Optional free text, at most 500 characters; null means none.
  final String? note;

  /// Incremented on every change; used for conflict detection.
  final int rowVersion;

  /// Frozen at creation (was gamification enabled then).
  final bool gamificationEligible;

  @override
  bool operator ==(Object other) =>
      other is WaterEntry &&
      other.id == id &&
      other.amountMl == amountMl &&
      other.occurredAtUtc == occurredAtUtc &&
      other.localDate == localDate &&
      other.timezoneId == timezoneId &&
      other.createdAtUtc == createdAtUtc &&
      other.note == note &&
      other.rowVersion == rowVersion &&
      other.gamificationEligible == gamificationEligible;

  @override
  int get hashCode => Object.hash(
    id,
    amountMl,
    occurredAtUtc,
    localDate,
    timezoneId,
    createdAtUtc,
    note,
    rowVersion,
    gamificationEligible,
  );

  @override
  String toString() => 'WaterEntry($id, $amountMl ml, $localDate)';
}

/// User input for creating or editing a water entry.
@immutable
final class WaterDraft {
  const WaterDraft({
    required this.amountMl,
    required this.occurredAtUtc,
    this.note,
  });

  /// Integer millilitres; valid range 50 to 2000.
  final int amountMl;

  /// When the drink happened (UTC); not in the future, not before 2000-01-01.
  final DateTime occurredAtUtc;

  /// Free text, at most 500 characters after trimming; blank means none.
  final String? note;
}

/// The newest-first order of water entries: later drinks first; equal times
/// fall back to the creation time and finally the id so the order is total.
int compareWaterNewestFirst(WaterEntry a, WaterEntry b) {
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
