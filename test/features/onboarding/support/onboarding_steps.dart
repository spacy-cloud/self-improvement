import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_state.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/goal_stepper_row.dart';

import '../../../support/pump_app.dart';
import 'onboarding_test_env.dart';

/// Taps [finder] and lets the transition end.
Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The one primary button at the bottom ("Los geht’s", "Weiter", "Fertig").
Finder get primaryButton => find.byType(PrimaryButton);

/// The round back button of the top bar.
Finder get backButton => find.byType(AppIconButton);

/// Taps the primary button and waits for the step change.
Future<void> tapPrimary(WidgetTester tester) =>
    tapAndSettle(tester, primaryButton);

/// Goes forward from the welcome screen to [target] with the primary button.
/// The body step must stay valid on the way.
Future<void> goToStep(WidgetTester tester, OnboardingStep target) async {
  for (var i = 0; i < target.index; i++) {
    await tapPrimary(tester);
  }
}

/// The text field of the body row [name] (`name`, `age`, `height`, `weight`).
Finder bodyField(String name) => find.descendant(
  of: find.byKey(ValueKey<String>('onboarding-$name')),
  matching: find.byType(TextField),
);

/// Types [text] into the body row [name].
Future<void> typeInto(WidgetTester tester, String name, String text) async {
  await tester.enterText(bodyField(name), text);
  await tester.pump();
}

/// The text typed into the body row [name].
String typedIn(WidgetTester tester, String name) =>
    tester.widget<TextField>(bodyField(name)).controller!.text;

/// The goal row titled [title] on the last step.
Finder goalRow(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(GoalStepperRow));

/// The plus or minus button of the goal row titled [title].
Finder stepperButton(String title, {required bool plus}) => find.descendant(
  of: goalRow(title),
  matching: find.byIcon(plus ? Icons.add_rounded : Icons.remove_rounded),
);

/// Taps the plus or minus button of a goal row [times] times.
Future<void> tapStepper(
  WidgetTester tester,
  String title, {
  required bool plus,
  int times = 1,
}) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(stepperButton(title, plus: plus));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// The stepper widget of the goal row titled [title].
QuantityStepper stepperOf(WidgetTester tester, String title) =>
    tester.widget<QuantityStepper>(
      find.descendant(
        of: goalRow(title),
        matching: find.byType(QuantityStepper),
      ),
    );

/// The cards whose check box is on (the selected motivation goals), by title.
List<String> selectedGoalTitles(WidgetTester tester) {
  final selected = <String>[];
  for (final card in tester.widgetList<RoundCheckbox>(
    find.byType(RoundCheckbox),
  )) {
    if (card.value) {
      selected.add(card.semanticLabel);
    }
  }
  return selected;
}

/// Taps the last step's button and waits until the flow left for the
/// dashboard.
Future<void> finishAndWaitForExit(
  WidgetTester tester,
  OnboardingEnv env,
) async {
  await tester.tap(primaryButton);
  await tester.pump();
  await tester.pumpUntil(
    () => env.exits.isNotEmpty,
    reason: 'the flow leaves after the command committed',
  );
  await tester.pumpAndSettle();
}

/// Counts how often the app asked the system to close (Android back on the
/// root screen).
class SystemExits {
  int count = 0;
}

/// Records `SystemNavigator.pop` instead of closing the test app.
SystemExits trackSystemExits(WidgetTester tester) {
  final exits = SystemExits();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') {
        exits.count++;
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return exits;
}

/// Presses Android back (button or gesture).
Future<void> pressSystemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}
