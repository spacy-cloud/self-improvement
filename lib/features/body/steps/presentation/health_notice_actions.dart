import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_actions.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_controller.dart';
import 'package:self_improvement/features/body/steps/domain/health_steps_status.dart';
import 'package:self_improvement/features/body/steps/presentation/health_explanation_sheet.dart';

/// Runs the action of a button of a notice or of the card on Home. It is the
/// ONE way the buttons of the Health comparison take: the notice in the
/// settings, the notice on "Meine Schritte" and the warning on the card on Home
/// all call it (BS-97, decision D-033).
///
/// "Zugriff erlauben" shows the explanation first (the sheet that appears when
/// the switch goes on, design frame `4122:509`) and asks the system only after
/// "Weiter zur Systemabfrage". "Nicht jetzt", the close button, the system back
/// action and a tap beside the sheet change nothing: no dialog, nothing is
/// read. The wish can be on without the sheet ever having been shown on this
/// device (a backup was imported with the switch on), so the explanation cannot
/// be left to the switch alone. The other actions (open the system settings,
/// open the install page, compare again) ask nothing from the system and run
/// at once.
Future<void> performHealthNoticeAction(
  BuildContext context,
  WidgetRef ref,
  HealthNoticeAction action,
) async {
  // Everything that needs [ref] is read before the first await: the widget
  // that started the action may be gone when the sheet closes.
  final actions = ref.read(healthStepsActionsProvider);
  if (action == HealthNoticeAction.allowAccess) {
    final status = ref.read(healthStepsStatusProvider);
    final proceed = await showHealthExplanationSheet(
      context,
      sourceName: status.sourceName,
      availability: status.availability,
    );
    if (!proceed || !context.mounted) {
      return;
    }
  }
  await actions.perform(action);
}
