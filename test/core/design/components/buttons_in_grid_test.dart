import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import '../support/design_test_harness.dart';

/// The card rows of `AdaptiveGrid` ask their children for intrinsic heights.
/// A `LayoutBuilder` inside a button threw there; the dashboard shows error
/// states and buttons inside such cards, so this must keep working.
void main() {
  testWidgets('the error state and both buttons work inside grid rows', (
    tester,
  ) async {
    await pumpDesign(
      tester,
      SingleChildScrollView(
        child: AdaptiveGrid(
          children: [
            ErrorState(onRetry: () {}),
            AppCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PrimaryButton(label: 'Speichern', onPressed: () {}),
                  const SizedBox(height: 8),
                  SecondaryButton(label: 'Abbrechen', onPressed: () {}),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('Speichern'), findsOneWidget);
  });

  testWidgets(
    'a button in a row keeps its natural width, in a column it fills',
    (tester) async {
      await pumpDesign(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PrimaryButton(label: 'Los', expand: false, onPressed: () {}),
              ],
            ),
            PrimaryButton(label: 'Voll', onPressed: () {}),
          ],
        ),
      );

      final natural = tester.getSize(find.widgetWithText(PrimaryButton, 'Los'));
      final filled = tester.getSize(find.widgetWithText(PrimaryButton, 'Voll'));
      expect(natural.width, lessThan(200));
      expect(filled.width, greaterThan(300));
      expect(tester.takeException(), isNull);
    },
  );
}
