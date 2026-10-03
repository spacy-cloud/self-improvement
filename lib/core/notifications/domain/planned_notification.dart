import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Builds and reads the semantic keys of planned notifications.
///
/// A semantic key names *what* is reminded, independent of the integer id the
/// operating system needs and of the exact fire time:
///
/// - `water:2026-10-03:10:00`: the water slot at 10:00 on that local day
/// - `habit:<habitId>:2026-10-03`: the reminder of one habit on that local day
/// - `focus_end:<sessionId>`: the end of one focus session
///
/// The key stays the same when the fire time moves (the habit time was edited,
/// the time zone changed), which is how a reconcile run recognizes a
/// notification it already handed to the system and reschedules it under the
/// same integer id.
abstract final class ReminderKeys {
  static String water(LocalDate day, LocalTime time) =>
      '${ReminderKind.water.key}:${day.toIso()}:${time.toIso()}';

  static String habit(String habitId, LocalDate day) =>
      '${ReminderKind.habit.key}:$habitId:${day.toIso()}';

  static String focusEnd(String sessionId) =>
      '${ReminderKind.focusEnd.key}:$sessionId';

  /// The kind encoded in [semanticKey]; `null` for an unknown prefix.
  static ReminderKind? kindOf(String semanticKey) {
    final separator = semanticKey.indexOf(':');
    if (separator <= 0) {
      return null;
    }
    return ReminderKind.tryParse(semanticKey.substring(0, separator));
  }
}

/// One notification the planner wants the operating system to deliver.
@immutable
final class PlannedNotification {
  const PlannedNotification({
    required this.semanticKey,
    required this.kind,
    required this.fireAtUtc,
    required this.route,
    required this.title,
    this.sourceRuleId,
  });

  /// Stable identity, see [ReminderKeys].
  final String semanticKey;

  final ReminderKind kind;

  /// When the notification is due (UTC instant, never in the past at the time
  /// the plan was made).
  final DateTime fireAtUtc;

  /// The known in-app route; it is also the notification payload.
  final String route;

  /// Neutral German title (no health values, no user text).
  final String title;

  /// The `reminder_rules` row this notification comes from (water slots);
  /// `null` for habit reminders and the focus end.
  final String? sourceRuleId;

  @override
  bool operator ==(Object other) =>
      other is PlannedNotification &&
      other.semanticKey == semanticKey &&
      other.kind == kind &&
      other.fireAtUtc == fireAtUtc &&
      other.route == route &&
      other.title == title &&
      other.sourceRuleId == sourceRuleId;

  @override
  int get hashCode =>
      Object.hash(semanticKey, kind, fireAtUtc, route, title, sourceRuleId);

  @override
  String toString() => 'PlannedNotification($semanticKey at $fireAtUtc)';
}
