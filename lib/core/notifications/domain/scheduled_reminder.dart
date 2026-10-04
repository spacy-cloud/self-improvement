import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/notifications/domain/planned_notification.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';

/// One row of the projection of notifications that were handed to the
/// operating system, as a presentation free model.
///
/// This is also what the V1 "notification list" shows: the planned reminders.
/// There is no delivery history; the app cannot know what the system actually
/// showed.
@immutable
final class ScheduledReminder {
  const ScheduledReminder({
    required this.notificationId,
    required this.semanticKey,
    required this.fireAtUtc,
    required this.route,
    this.sourceRuleId,
  });

  /// The persistent positive integer id the operating system knows.
  final int notificationId;

  final String semanticKey;

  /// When the notification is due.
  final DateTime fireAtUtc;

  /// The in-app route (also the payload).
  final String route;

  final String? sourceRuleId;

  /// The kind, or `null` for a damaged row with an unknown key prefix.
  ReminderKind? get kind => ReminderKeys.kindOf(semanticKey);

  @override
  bool operator ==(Object other) =>
      other is ScheduledReminder &&
      other.notificationId == notificationId &&
      other.semanticKey == semanticKey &&
      other.fireAtUtc == fireAtUtc &&
      other.route == route &&
      other.sourceRuleId == sourceRuleId;

  @override
  int get hashCode =>
      Object.hash(notificationId, semanticKey, fireAtUtc, route, sourceRuleId);

  @override
  String toString() => 'ScheduledReminder($notificationId, $semanticKey)';
}
