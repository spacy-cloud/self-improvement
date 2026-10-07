import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';

/// User visible German texts of the reminder feature.
///
/// Notification texts are neutral on purpose: they never contain health
/// values and never the title of a habit or a task (user text). A
/// notification appears on the lock screen, so it must not reveal private
/// content.
abstract final class ReminderTexts {
  /// Title of a water reminder.
  static const String waterTitle = 'Zeit für ein Glas Wasser';

  /// Title of a habit reminder. The habit's own title is deliberately unused.
  static const String habitTitle = 'Zeit für deine Gewohnheit';

  /// Title of a task reminder. The task's own title is deliberately unused.
  static const String taskTitle = 'Erinnerung an deine Aufgabe';

  /// Title of the focus end notification.
  static const String focusEndTitle = 'Deine Fokuszeit ist vorbei';

  /// The notification title for [kind].
  static String titleFor(ReminderKind kind) => switch (kind) {
    ReminderKind.water => waterTitle,
    ReminderKind.habit => habitTitle,
    ReminderKind.task => taskTitle,
    ReminderKind.focusEnd => focusEndTitle,
  };

  /// Name of the Android notification channel as the system settings show it.
  static const String channelName = 'Erinnerungen';

  /// Description of the Android notification channel.
  static const String channelDescription =
      'Erinnerungen an Wasser, Gewohnheiten, Aufgaben und das Ende deiner '
      'Fokuszeit.';

  /// Shown by the settings screen when more reminders are due than the global
  /// limit allows (`ReminderStatus.planLimitReached`).
  static const String limitNotice =
      'Bei sehr vielen Erinnerungen wird nur ein Teil im Voraus geplant, die '
      'nächsten zuerst. Der Rest wird beim nächsten Öffnen der App ergänzt.';

  /// Honest note about delivery, for the settings screen.
  static const String deliveryNotice =
      'Erinnerungen sind lokal und ungenau getaktet. Das System kann sie um '
      'einige Minuten verzögern. Nach einem erzwungenen Beenden der App '
      'kommen sie erst wieder an, wenn du die App erneut geöffnet hast.';
}
