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

  group('ChartSummary headerTrailing', () {
    testSemantics('the control next to the title stays operable and spoken', (
      tester,
    ) async {
      var selected = 7;
      // The real font keeps the title narrow (the test font is very wide).
      await tester.runAsync(loadInterFont);
      await pumpDesign(
        tester,
        StatefulBuilder(
          builder: (context, setState) => ChartSummary(
            title: 'Verlauf',
            summary: 'Gewicht sinkt von 72,7 auf 71,5 kg.',
            columns: const ['Gewicht'],
            rows: const [
              ChartSummaryRow(label: 'Mo., 14. Sep.', values: ['71,5 kg']),
            ],
            chart: const SizedBox(height: 40),
            headerTrailing: PeriodSelector<int>(
              options: const [
                PeriodOption(value: 7, label: '7 T', semanticLabel: '7 Tage'),
                PeriodOption(
                  value: 30,
                  label: '30 T',
                  semanticLabel: '30 Tage',
                ),
                PeriodOption(value: 90, label: '3 M', semanticLabel: '90 Tage'),
              ],
              selected: selected,
              onChanged: (days) => setState(() => selected = days),
            ),
          ),
        ),
      );
      expect(find.text('Verlauf'), findsOneWidget);
      final title = tester.getTopLeft(find.text('Verlauf'));
      final selector = tester.getTopLeft(find.byType(PeriodSelector<int>));
      expect(
        selector.dx,
        greaterThan(title.dx + 100),
        reason: 'fits in one line at normal text: control on the right',
      );
      await tester.tap(find.text('30 T'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected, 30);
      expect(find.bySemanticsLabel('30 Tage'), findsOneWidget);
    });

    testWidgets('on large text the control moves below the title', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        ChartSummary(
          title: 'Verlauf',
          summary: 'x',
          rows: const [],
          headerTrailing: PeriodSelector.days(
            selectedDays: 7,
            onChanged: (_) {},
          ),
        ),
        width: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      final title = tester.getTopLeft(find.text('Verlauf'));
      final selector = tester.getTopLeft(find.byType(PeriodSelector<int>));
      expect(selector.dy, greaterThan(title.dy));
    });
  });
}
