import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/features/reminders/presentation/sheet_frame.dart';

/// What the user decided in the permission sheet.
enum ReminderPermissionChoice {
  /// Continue to the system permission dialog.
  askSystem,

  /// Grant the permission in the system settings instead.
  openSettings,

  /// Not now; reminders stay off. Also the result of closing the sheet.
  later,
}

/// Explains why reminders need the notification permission and shows what the
/// device says about it right now (Figma 4055:317, "Erinnerungen erlauben").
///
/// The sheet appears only after the user switched reminders on and the
/// permission is not granted; nothing asks for the permission earlier. The
/// system dialog itself is opened by the caller after the user chose
/// [ReminderPermissionChoice.askSystem]. Android cannot tell "never asked"
/// from "refused" and "blocked for good", so the way to the system settings is
/// always offered here.
Future<ReminderPermissionChoice> showReminderPermissionSheet(
  BuildContext context, {
  required NotificationPermission permission,
}) async {
  final choice = await showAppModalSheet<ReminderPermissionChoice>(
    context,
    builder: (_) => ReminderPermissionSheet(permission: permission),
  );
  return choice ?? ReminderPermissionChoice.later;
}

/// Content of the permission sheet.
class ReminderPermissionSheet extends StatelessWidget {
  const ReminderPermissionSheet({required this.permission, super.key});

  /// The permission as the device reports it when the sheet opens.
  final NotificationPermission permission;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    void choose(ReminderPermissionChoice choice) =>
        Navigator.of(context).pop(choice);
    final String state = switch (permission) {
      NotificationPermission.granted =>
        'Android-Status: Benachrichtigungen sind erlaubt.',
      NotificationPermission.denied =>
        'Android-Status: Benachrichtigungen sind für diese App nicht erlaubt.',
      NotificationPermission.unavailable =>
        'Android-Status: Der Status der Benachrichtigungen ist nicht '
            'verfügbar.',
    };
    return AppSheetFrame(
      title: 'Erinnerungen erlauben?',
      onClose: () => choose(ReminderPermissionChoice.later),
      footer: <Widget>[
        PrimaryButton(
          label: 'Weiter zur Android-Abfrage',
          onPressed: () => choose(ReminderPermissionChoice.askSystem),
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          label: 'Einstellungen öffnen',
          semanticLabel: 'Systemeinstellungen für Benachrichtigungen öffnen',
          onPressed: () => choose(ReminderPermissionChoice.openSettings),
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          label: 'Später',
          autofocus: true,
          onPressed: () => choose(ReminderPermissionChoice.later),
        ),
      ],
      children: <Widget>[
        SheetBadge(icon: AppIcon.reminder.data, accent: AppAccent.primary),
        const SizedBox(height: 12),
        Text(
          'Die App erinnert dich nur an das, was du einschaltest, zum '
          'Beispiel ans Trinken. Keine Werbung, alles bleibt auf deinem '
          'Gerät. Dafür fragt Android einmal nach deiner Erlaubnis.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyRegular.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        SheetMessage(text: state),
        const SizedBox(height: 8),
        const SheetMessage(
          text:
              'Zeigt Android keine Abfrage mehr, erlaube Benachrichtigungen '
              'in den Systemeinstellungen. Erinnerungen kommen ungefähr zur '
              'gewählten Zeit; Android kann sie verzögern.',
        ),
      ],
    );
  }
}
