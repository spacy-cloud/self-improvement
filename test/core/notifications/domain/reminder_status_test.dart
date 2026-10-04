import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';

void main() {
  ReminderStatus status({
    bool wanted = true,
    NotificationPermission permission = NotificationPermission.granted,
    int scheduled = 3,
    ReminderErrorCategory? error,
    int failed = 0,
    bool limit = false,
    DateTime? next,
  }) => ReminderStatus(
    wanted: wanted,
    permission: permission,
    scheduledCount: scheduled,
    lastError: error,
    failedCount: failed,
    planLimitReached: limit,
    nextFireAtUtc: next,
  );

  group('derived state', () {
    test('reminders are off by default, whatever the system says', () {
      for (final permission in NotificationPermission.values) {
        expect(
          status(wanted: false, permission: permission).state,
          ReminderState.off,
        );
      }
    });

    test('wanted and refused by the system is blocked, honestly', () {
      final blocked = status(permission: NotificationPermission.denied);
      expect(blocked.state, ReminderState.blocked);
      expect(blocked.isBlocked, isTrue);
      expect(blocked.canRetry, isFalse);
    });

    test('wanted but without notification support is unavailable', () {
      expect(
        status(permission: NotificationPermission.unavailable).state,
        ReminderState.unavailable,
      );
    });

    test('wanted, allowed and planned is active', () {
      final active = status();
      expect(active.state, ReminderState.active);
      expect(active.isBlocked, isFalse);
      expect(active.canRetry, isFalse);
    });

    test('a failed run is a scheduling error with a retry', () {
      final failed = status(error: ReminderErrorCategory.platform, failed: 2);
      expect(failed.state, ReminderState.schedulingError);
      expect(failed.canRetry, isTrue);
    });

    test(
      'a missing permission is shown as blocked, not as a scheduling error',
      () {
        final blocked = status(
          permission: NotificationPermission.denied,
          error: ReminderErrorCategory.permission,
        );
        expect(blocked.state, ReminderState.blocked);
      },
    );
  });

  group('value semantics', () {
    test('equal statuses are equal and hash alike', () {
      final a = status(next: DateTime.utc(2026, 10, 3, 8));
      final b = status(next: DateTime.utc(2026, 10, 3, 8));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('every field takes part in equality', () {
      final base = status();
      expect(base, isNot(status(wanted: false)));
      expect(base, isNot(status(permission: NotificationPermission.denied)));
      expect(base, isNot(status(scheduled: 4)));
      expect(base, isNot(status(error: ReminderErrorCategory.storage)));
      expect(base, isNot(status(failed: 1)));
      expect(base, isNot(status(limit: true)));
      expect(base, isNot(status(next: DateTime.utc(2026))));
    });
  });
}
