import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';

/// German texts of the reminder block as pure functions, so every state has a
/// tested wording. Nothing here claims more than the app knows: it planned
/// reminders, it cannot see whether the system delivered them.
abstract final class ReminderLabels {
  /// `10:00` for the slot at 10 o'clock.
  static String slot(int hour) => '${hour.toString().padLeft(2, '0')}:00';

  /// What a screen reader says for a slot chip: `10 Uhr`.
  static String slotSpoken(int hour) => '$hour Uhr';

  /// The line under the title of the master switch. [planned] is the number
  /// of reminders that are still ahead; it defaults to the engine's count.
  static String stateSubtitle(ReminderStatus status, {int? planned}) {
    final count = planned ?? status.scheduledCount;
    return switch (status.state) {
      ReminderState.off => 'Aus',
      ReminderState.blocked => 'Im System blockiert',
      ReminderState.unavailable => 'Auf diesem Gerät nicht verfügbar',
      ReminderState.schedulingError => 'Planungsfehler',
      ReminderState.active =>
        count == 0
            ? 'Eingeschaltet, aktuell nichts geplant'
            : 'Eingeschaltet, $count geplant',
    };
  }

  /// The device permission as the app reads it, shown at the foot of the block.
  static String permissionLine(ReminderStatus status) =>
      switch (status.permission) {
        NotificationPermission.granted =>
          'Systemstatus: Benachrichtigungen sind erlaubt.',
        NotificationPermission.denied =>
          status.wanted
              ? 'Systemstatus: Benachrichtigungen sind blockiert.'
              : 'Systemstatus: Benachrichtigungen sind noch nicht erlaubt. '
                    'Android fragt erst, wenn du Erinnerungen einschaltest.',
        NotificationPermission.unavailable =>
          'Systemstatus: Der Status der Benachrichtigungen ist nicht '
              'verfügbar.',
      };

  /// What went wrong while planning, in words, without any platform message.
  static String schedulingErrorText(ReminderErrorCategory? category) {
    final cause = switch (category) {
      ReminderErrorCategory.permission =>
        'Android hat das Einplanen wegen fehlender Berechtigung abgelehnt.',
      ReminderErrorCategory.platform =>
        'Das System hat das Einplanen abgelehnt.',
      ReminderErrorCategory.storage =>
        'Die geplanten Erinnerungen konnten nicht gespeichert werden.',
      ReminderErrorCategory.unknown || null =>
        'Ein unerwarteter Fehler ist '
            'aufgetreten.',
    };
    return '$cause Deine Einträge sind davon nicht betroffen.';
  }

  /// `Heute, 14:00 Uhr`, `Morgen, 07:30 Uhr`, later `Mo., 5. Okt., 18:00 Uhr`.
  static String when(LocalDateTime local, LocalDate today) {
    final daysAhead = today.daysUntil(local.date);
    final day = switch (daysAhead) {
      0 => 'Heute',
      1 => 'Morgen',
      _ => formatDateShort(local.date, contextYear: today.year),
    };
    return '$day, ${local.time.toIso()} Uhr';
  }
}
