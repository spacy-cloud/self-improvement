import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/reminders/presentation/reminder_labels.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// The wording of every state of the reminder block (AT28, C08).
void main() {
  ReminderStatus status({
    bool wanted = true,
    NotificationPermission permission = NotificationPermission.granted,
    int count = 0,
    ReminderErrorCategory? error,
  }) => ReminderStatus(
    wanted: wanted,
    permission: permission,
    scheduledCount: count,
    lastError: error,
  );

  group('stateSubtitle', () {
    test('off, whatever the permission is', () {
      for (final permission in NotificationPermission.values) {
        expect(
          ReminderLabels.stateSubtitle(
            status(wanted: false, permission: permission, count: 3),
          ),
          'Aus',
        );
      }
    });

    test('blocked and unavailable come from the device', () {
      expect(
        ReminderLabels.stateSubtitle(
          status(permission: NotificationPermission.denied),
        ),
        'Im System blockiert',
      );
      expect(
        ReminderLabels.stateSubtitle(
          status(permission: NotificationPermission.unavailable),
        ),
        'Auf diesem Gerät nicht verfügbar',
      );
    });

    test('a planning error beats "active"', () {
      expect(
        ReminderLabels.stateSubtitle(
          status(count: 4, error: ReminderErrorCategory.platform),
        ),
        'Planungsfehler',
      );
    });

    test('active tells what was planned, never what was delivered', () {
      expect(
        ReminderLabels.stateSubtitle(status()),
        'Eingeschaltet, aktuell nichts geplant',
      );
      expect(
        ReminderLabels.stateSubtitle(status(count: 14)),
        'Eingeschaltet, 14 geplant',
      );
    });

    test('the number of reminders still ahead wins over the stored rows', () {
      expect(
        ReminderLabels.stateSubtitle(status(count: 14), planned: 13),
        'Eingeschaltet, 13 geplant',
      );
      expect(
        ReminderLabels.stateSubtitle(status(count: 2), planned: 0),
        'Eingeschaltet, aktuell nichts geplant',
      );
    });
  });

  group('permissionLine shows the real device state', () {
    test('granted', () {
      expect(
        ReminderLabels.permissionLine(status()),
        'Systemstatus: Benachrichtigungen sind erlaubt.',
      );
    });

    test('denied while off: not asked yet, no alarm', () {
      final line = ReminderLabels.permissionLine(
        status(wanted: false, permission: NotificationPermission.denied),
      );
      expect(line, contains('noch nicht erlaubt'));
      expect(line, contains('Das System fragt erst, wenn du Erinnerungen'));
    });

    test('denied after the user asked: blocked', () {
      expect(
        ReminderLabels.permissionLine(
          status(permission: NotificationPermission.denied),
        ),
        'Systemstatus: Benachrichtigungen sind blockiert.',
      );
    });

    test('unavailable', () {
      expect(
        ReminderLabels.permissionLine(
          status(permission: NotificationPermission.unavailable),
        ),
        contains('nicht verfügbar'),
      );
    });
  });

  group('schedulingErrorText', () {
    test('names the cause without a platform message', () {
      expect(
        ReminderLabels.schedulingErrorText(ReminderErrorCategory.permission),
        contains('fehlender Berechtigung'),
      );
      expect(
        ReminderLabels.schedulingErrorText(ReminderErrorCategory.platform),
        contains('Das System hat das Einplanen abgelehnt.'),
      );
      expect(
        ReminderLabels.schedulingErrorText(ReminderErrorCategory.storage),
        contains('nicht gespeichert werden'),
      );
      expect(
        ReminderLabels.schedulingErrorText(ReminderErrorCategory.unknown),
        contains('unerwarteter Fehler'),
      );
      expect(
        ReminderLabels.schedulingErrorText(null),
        contains('unerwarteter Fehler'),
      );
    });

    test('always says that the entries are safe', () {
      for (final category in <ReminderErrorCategory?>[
        ...ReminderErrorCategory.values,
        null,
      ]) {
        expect(
          ReminderLabels.schedulingErrorText(category),
          endsWith('Deine Einträge sind davon nicht betroffen.'),
        );
      }
    });
  });

  group('slots', () {
    test('slot texts', () {
      expect(ReminderLabels.slot(10), '10:00');
      expect(ReminderLabels.slot(18), '18:00');
      expect(ReminderLabels.slotSpoken(10), '10 Uhr');
    });
  });

  group('when', () {
    final today = LocalDate(2026, 10, 3);
    LocalDateTime at(LocalDate date, int hour, int minute) =>
        LocalDateTime(date, LocalTime(hour, minute));

    test('today, tomorrow, later this year, another year', () {
      expect(ReminderLabels.when(at(today, 14, 0), today), 'Heute, 14:00 Uhr');
      expect(
        ReminderLabels.when(at(today.addDays(1), 7, 30), today),
        'Morgen, 07:30 Uhr',
      );
      expect(
        ReminderLabels.when(at(today.addDays(2), 18, 5), today),
        'Mo., 5. Okt., 18:05 Uhr',
      );
      expect(
        ReminderLabels.when(at(LocalDate(2027, 1, 2), 10, 0), today),
        'Sa., 2. Jan. 2027, 10:00 Uhr',
      );
    });

    test('midnight and the last minute of the day', () {
      expect(ReminderLabels.when(at(today, 0, 0), today), 'Heute, 00:00 Uhr');
      expect(ReminderLabels.when(at(today, 23, 59), today), 'Heute, 23:59 Uhr');
    });
  });
}
