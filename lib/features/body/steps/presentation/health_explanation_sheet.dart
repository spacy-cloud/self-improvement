import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';
import 'package:self_improvement/features/reminders/presentation/sheet_frame.dart';

/// Explains what "Schritte aus Health übernehmen" does BEFORE anything is
/// asked from the system (design frame `4122:509`). Returns true when the user
/// continues; "Nicht jetzt", the close button, the barrier and the system back
/// action return false and nothing changes.
///
/// The sheet appears every time the switch goes on. The system dialog itself is
/// started by the caller after "Weiter zur Systemabfrage". When the interface
/// is not installed or outdated no dialog can follow; the sheet says so and
/// the primary button reads "Einschalten".
Future<bool> showHealthExplanationSheet(
  BuildContext context, {
  required String sourceName,
  required HealthAvailability? availability,
}) async {
  final choice = await showAppModalSheet<bool>(
    context,
    builder: (_) => HealthExplanationSheet(
      sourceName: sourceName,
      availability: availability,
    ),
  );
  return choice ?? false;
}

/// Content of the explanation sheet.
class HealthExplanationSheet extends StatelessWidget {
  const HealthExplanationSheet({
    required this.sourceName,
    required this.availability,
    super.key,
  });

  /// How the interface is called, for example `Health Connect`.
  final String sourceName;

  /// What the device said about the interface; null when it is not known.
  final HealthAvailability? availability;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final note = switch (availability) {
      HealthAvailability.missing =>
        '$sourceName ist auf diesem Gerät nicht installiert. Du kannst den '
            'Schalter trotzdem einschalten und es danach installieren.',
      HealthAvailability.updateRequired =>
        '$sourceName ist auf diesem Gerät veraltet. Du kannst den Schalter '
            'trotzdem einschalten und es danach aktualisieren.',
      _ => null,
    };
    return AppSheetFrame(
      title: 'Schritte aus Health übernehmen?',
      onClose: () => Navigator.of(context).pop(false),
      footer: <Widget>[
        PrimaryButton(
          label: note == null ? 'Weiter zur Systemabfrage' : 'Einschalten',
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          label: 'Nicht jetzt',
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
      children: <Widget>[
        SheetBadge(icon: AppIcon.heart.data, accent: AppAccent.steps),
        const SizedBox(height: 12),
        Text(
          'Die App liest deine Schritte aus $sourceName: nur lesend, nur '
          'Schritte, nur auf diesem Gerät. Von Hand eingetragene Tage bleiben '
          'unverändert.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyRegular.copyWith(
            color: colors.textSecondary,
          ),
        ),
        if (note != null) ...<Widget>[
          const SizedBox(height: 12),
          SheetMessage(text: note),
        ],
      ],
    );
  }
}
