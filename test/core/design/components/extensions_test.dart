import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import '../support/design_test_harness.dart';

void main() {
  group('AppCard error border', () {
    testWidgets('uses the given colour and width instead of the default', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        Builder(
          builder: (context) => AppCard(
            borderColor: context.tokens.colors.error,
            borderWidth: 2,
            child: const Text('Wert'),
          ),
        ),
      );
      final decoration =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(AppCard),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.top.color, AppTokens.light.colors.error);
      expect(border.top.width, 2);
    });

    testWidgets('keeps the decorative 1 px border by default', (tester) async {
      await pumpDesign(tester, const AppCard(child: Text('Wert')));
      final decoration =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(AppCard),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.top.color, AppTokens.light.colors.borderDecorative);
      expect(border.top.width, 1);
    });
  });

  group('QuantityStepper valueWidget', () {
    testWidgets('replaces the read-only value and keeps both buttons', (
      tester,
    ) async {
      var plus = 0;
      await pumpDesign(
        tester,
        QuantityStepper(
          valueText: 'ignored',
          onIncrease: () => plus++,
          onDecrease: () {},
          valueWidget: const SizedBox(
            width: 120,
            child: TextField(key: ValueKey('editable')),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('editable')), findsOneWidget);
      expect(find.text('ignored'), findsNothing);
      await tester.tap(find.byIcon(Icons.add_rounded));
      expect(plus, 1);
    });
  });
}
