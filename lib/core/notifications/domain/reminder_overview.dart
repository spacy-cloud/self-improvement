import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/scheduled_reminder.dart';

/// What the V1 notification list shows: the planned reminders together with
/// the permission status. There is no delivery history; the app only knows
/// what it planned.
@immutable
final class ReminderOverview {
  const ReminderOverview({required this.status, required this.reminders});

  /// The wish, the real permission, the count and the last error.
  final ReminderStatus status;

  /// The planned reminders, soonest first.
  final List<ScheduledReminder> reminders;

  /// Whether nothing is planned.
  bool get isEmpty => reminders.isEmpty;
}
