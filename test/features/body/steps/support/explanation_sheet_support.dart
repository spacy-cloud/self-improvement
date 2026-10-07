import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/body/steps/presentation/health_explanation_sheet.dart';

/// The ways to close the explanation sheet of "Schritte aus Health übernehmen"
/// WITHOUT going on (BS-97): none of them may ask the system or read a step.
enum SheetDismissal {
  /// The secondary button.
  notNow('"Nicht jetzt"'),

  /// The close button in the title row.
  closeButton('the close button'),

  /// A tap on the barrier beside the sheet.
  barrier('a tap beside the sheet'),

  /// The system back action.
  systemBack('the system back action');

  const SheetDismissal(this.label);

  /// How the test names the way.
  final String label;
}

/// Closes the open [HealthExplanationSheet] the way [how] says and lets the
/// page settle with [settle].
Future<void> dismissExplanationSheet(
  WidgetTester tester,
  SheetDismissal how,
  Future<void> Function() settle,
) async {
  switch (how) {
    case SheetDismissal.notNow:
      await tester.tap(find.text('Nicht jetzt'));
    case SheetDismissal.closeButton:
      await tester.tap(
        find.descendant(
          of: find.byType(HealthExplanationSheet),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AppIconButton && widget.semanticLabel == 'Schließen',
          ),
        ),
      );
    case SheetDismissal.barrier:
      await tester.tapAt(const Offset(10, 10));
    case SheetDismissal.systemBack:
      await tester.binding.handlePopRoute();
  }
  await settle();
}
