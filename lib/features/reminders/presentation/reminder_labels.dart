import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';

/// What a [ReminderNotice] lets the user do.
enum ReminderNoticeAction {
  /// Open the settings of the app, where reminders are switched on.
  openAppSettings,

  /// Open the notification settings of the system.
  openSystemSettings,

  /// Read the state again and plan again.
  retry,
}

/// The honest explanation of a state in which a reminder will not be
/// delivered, with the one action that can fix it. Warning tone, error tone
/// for a planning error; the words carry the meaning, not the colour.
@immutable
final class ReminderNotice {
  const ReminderNotice({
    required this.title,
    required this.text,
    required this.actionLabel,
    required this.action,
    this.actionSemanticLabel,
    this.error = false,
  });

  final String title;
  final String text;

  /// Visible text of the action.
  final String actionLabel;

  /// What a screen reader says for the action; defaults to [actionLabel].
  final String? actionSemanticLabel;

  final ReminderNoticeAction action;

  /// Whether it is a failure (error tone) and not a missing permission.
  final bool error;
}

/// German texts of the reminder block as pure functions, so every state has a
/// tested wording. Nothing here claims more than the app knows: it planned
/// reminders, it cannot see whether the system delivered them.
abstract final class ReminderLabels {
  /// Said when the system settings cannot be opened from the app. Neutral on
  /// purpose: the path to the app's settings differs between the platforms.
  static const String settingsNotOpened =
      'Die Systemeinstellungen konnten nicht geöffnet werden. Öffne die '
      'Einstellungen deines Geräts, wähle diese App und erlaube '
      'Benachrichtigungen.';

  /// What the form of a task says when its reminder is set and will not be
  /// delivered as things stand: the switch "Erinnerungen" of the app is off,
  /// the system does not allow notifications, the device cannot show them, or
  /// the last planning failed. `null` when reminders are active: nothing is in
  /// the way. The task and its reminder are saved in every case; the notice
  /// only says honestly that the notification does not arrive yet, and offers
  /// the way out.
  static ReminderNotice? taskNotice(ReminderStatus status) =>
      switch (status.state) {
        ReminderState.off => const ReminderNotice(
          title: 'Erinnerungen sind ausgeschaltet',
          text:
              'Die Aufgabe wird gespeichert. Die Erinnerung kommt erst an, '
              'wenn du Erinnerungen in den Einstellungen einschaltest.',
          actionLabel: 'Einstellungen öffnen',
          actionSemanticLabel: 'Einstellungen für Erinnerungen öffnen',
          action: ReminderNoticeAction.openAppSettings,
        ),
        ReminderState.blocked => const ReminderNotice(
          title: 'Benachrichtigungen sind nicht erlaubt',
          text:
              'Die Aufgabe wird gespeichert. Die Erinnerung kommt erst an, '
              'wenn du Benachrichtigungen in den Systemeinstellungen '
              'erlaubst.',
          actionLabel: 'Systemeinstellungen öffnen',
          actionSemanticLabel:
              'Systemeinstellungen für Benachrichtigungen öffnen',
          action: ReminderNoticeAction.openSystemSettings,
        ),
        ReminderState.unavailable => const ReminderNotice(
          title: 'Benachrichtigungen nicht verfügbar',
          text:
              'Die Aufgabe wird gespeichert. Dieses Gerät meldet keine '
              'Benachrichtigungen oder der Status ließ sich nicht lesen, die '
              'Erinnerung kommt deshalb nicht an.',
          actionLabel: 'Erneut prüfen',
          action: ReminderNoticeAction.retry,
        ),
        ReminderState.schedulingError => ReminderNotice(
          title: 'Planungsfehler',
          text:
              'Die Aufgabe wird gespeichert. '
              '${schedulingErrorText(status.lastError)}',
          actionLabel: 'Wiederholen',
          action: ReminderNoticeAction.retry,
          error: true,
        ),
        ReminderState.active => null,
      };

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
                    'Das System fragt erst, wenn du Erinnerungen einschaltest.',
        NotificationPermission.unavailable =>
          'Systemstatus: Der Status der Benachrichtigungen ist nicht '
              'verfügbar.',
      };

  /// What went wrong while planning, in words, without any platform message.
  static String schedulingErrorText(ReminderErrorCategory? category) {
    final cause = switch (category) {
      ReminderErrorCategory.permission =>
        'Das System hat das Einplanen wegen fehlender Berechtigung '
            'abgelehnt.',
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
