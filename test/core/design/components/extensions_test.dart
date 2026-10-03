import 'dart:ui' show CheckedState;

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

  group('EntryListTile.check', () {
    testSemantics('the whole row toggles and reads as one checkable row', (
      tester,
    ) async {
      final changes = <bool>[];
      var value = false;
      await pumpDesign(
        tester,
        StatefulBuilder(
          builder: (context, setState) => EntryListTile.check(
            title: 'Vor dem Klo',
            subtitle: 'Noch nicht auf Toilette gewesen',
            icon: Icons.wc_rounded,
            value: value,
            onToggle: (next) {
              changes.add(next);
              setState(() => value = next);
            },
          ),
        ),
      );
      final row = tester.getSemantics(find.bySemanticsLabel(RegExp('Vor dem')));
      expect(row.flagsCollection.isChecked, CheckedState.isFalse);
      expect(row.rect.height, greaterThanOrEqualTo(48));

      await tester.tap(find.text('Vor dem Klo'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(changes, [true]);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(RegExp('Vor dem')))
            .flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );
    });

    testWidgets('without a callback the row is disabled', (tester) async {
      await pumpDesign(
        tester,
        const EntryListTile.check(
          title: 'Nach dem Essen',
          value: false,
          onToggle: null,
        ),
      );
      await tester.tap(find.text('Nach dem Essen'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
