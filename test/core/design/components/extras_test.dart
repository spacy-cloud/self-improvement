import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import '../support/contrast.dart';
import '../support/design_test_harness.dart';

void _noop() {}

void main() {
  setUpAll(loadInterFont);

  group('AppColors.accentTextOnTint', () {
    for (final variant in allVariants) {
      for (final accent in AppAccent.values) {
        test(
          '${variant.name}: ${accent.name} text on its tint is at least 4.5:1',
          () {
            final colors = variant.colors;
            final text = colors.accentTextOnTint(accent);
            expect(
              contrastRatio(text, colors.accentTint(accent)),
              greaterThanOrEqualTo(4.5),
            );
            // Either the accent itself or the primary text colour.
            expect(
              text == colors.accent(accent) || text == colors.textPrimary,
              isTrue,
            );
          },
        );
      }
    }

    test('Light water and steps fall back to the primary text colour', () {
      const light = AppColors.light;
      expect(light.accentTextOnTint(AppAccent.water), light.textPrimary);
      expect(light.accentTextOnTint(AppAccent.steps), light.textPrimary);
      expect(light.accentTextOnTint(AppAccent.primary), light.primaryText);
    });
  });

  group('AppBadge', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics('${variant.name}: tint, text colour and spoken label', (
        tester,
      ) async {
        await pumpDesign(
          tester,
          const Column(
            children: <Widget>[
              AppBadge(label: 'Fast geschafft!', icon: Icons.check_rounded),
              AppBadge(
                label: 'Noch 1,0 l bis zum Ziel',
                accent: AppAccent.water,
              ),
            ],
          ),
          variant: variant,
        );
        final primary = find.ancestor(
          of: find.text('Fast geschafft!'),
          matching: find.byType(DecoratedBox),
        );
        expect(
          (tester.widget<DecoratedBox>(primary.first).decoration
                  as BoxDecoration)
              .color,
          colors.primaryTint,
        );
        expect(textColor(tester, 'Fast geschafft!'), colors.primaryText);
        expect(
          textColor(tester, 'Noch 1,0 l bis zum Ziel'),
          colors.accentTextOnTint(AppAccent.water),
        );
        expect(
          tester.widget<Icon>(find.byIcon(Icons.check_rounded)).color,
          colors.primaryText,
        );
        final node = tester.getSemantics(
          find.bySemanticsLabel('Fast geschafft!'),
        );
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      });
    }

    testSemantics('semanticLabel overrides the spoken text', (tester) async {
      await pumpDesign(
        tester,
        const AppBadge(
          label: '↓ −0,3 kg',
          semanticLabel: '0,3 Kilogramm weniger als beim letzten Eintrag',
        ),
      );
      expect(
        find.bySemanticsLabel('0,3 Kilogramm weniger als beim letzten Eintrag'),
        findsOneWidget,
      );
    });

    testWidgets('wraps on large text without overflow', (tester) async {
      await pumpDesign(
        tester,
        const AppBadge(
          label: 'Noch 1,0 l bis zum Tagesziel erreicht',
          icon: Icons.water_drop_outlined,
          accent: AppAccent.water,
        ),
        width: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('AppSectionHeader', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics('${variant.name}: heading, help text and action', (
        tester,
      ) async {
        var taps = 0;
        await pumpDesign(
          tester,
          AppSectionHeader(
            title: 'Deine Habits',
            subtitle: 'Ein Tippen genügt.',
            actionLabel: 'Bearbeiten',
            onAction: () => taps++,
          ),
          variant: variant,
        );
        expect(textColor(tester, 'Deine Habits'), colors.textPrimary);
        expect(
          tester.widget<Text>(find.text('Deine Habits')).style?.fontSize,
          17,
        );
        expect(textColor(tester, 'Ein Tippen genügt.'), colors.textSecondary);
        expect(textColor(tester, 'Bearbeiten'), colors.primaryText);
        final heading = tester.getSemantics(
          find.bySemanticsLabel('Deine Habits'),
        );
        expect(heading.flagsCollection.isHeader, isTrue);
        final action = tester.getSemantics(find.bySemanticsLabel('Bearbeiten'));
        expect(action.flagsCollection.isButton, isTrue);
        expect(action.rect.height, greaterThanOrEqualTo(48));
        expect(action.rect.width, greaterThanOrEqualTo(48));
        await tester.tap(find.text('Bearbeiten'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(taps, 1);
      });

      testSemantics(
        '${variant.name}: the group variant is an upper-case tertiary label',
        (tester) async {
          await pumpDesign(
            tester,
            const AppSectionHeader.group(title: 'Darstellung'),
            variant: variant,
          );
          expect(find.text('DARSTELLUNG'), findsOneWidget);
          final style = tester.widget<Text>(find.text('DARSTELLUNG')).style!;
          expect(style.color, colors.textTertiary);
          expect(style.letterSpacing, 0.66);
          expect(
            tester
                .getSemantics(find.bySemanticsLabel('DARSTELLUNG'))
                .flagsCollection
                .isHeader,
            isTrue,
          );
        },
      );
    }

    testWidgets(
      'without action there is no button, long titles wrap on large text',
      (tester) async {
        await pumpDesign(
          tester,
          const AppSectionHeader(
            title: 'Heute getrunken und eingetragen',
            subtitle: '4 Einträge',
          ),
          width: 320,
          textScale: 2,
        );
        expect(find.byType(InkWell), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'an action with a long label and title does not overflow at 200 %',
      (tester) async {
        await pumpDesign(
          tester,
          AppSectionHeader(
            title: 'Letzte Einträge der Woche',
            actionLabel: 'Alle anzeigen',
            onAction: () {},
          ),
          width: 320,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('AppListGroup', () {
    testWidgets('puts a divider between rows but not around them', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const AppListGroup(
          children: <Widget>[
            EntryListTile.chevron(title: 'Eins', onTap: _noop),
            EntryListTile.chevron(title: 'Zwei', onTap: _noop),
            EntryListTile.chevron(title: 'Drei', onTap: _noop),
          ],
        ),
      );
      expect(find.byType(Divider), findsNWidgets(2));
      final divider = tester.widget<Divider>(find.byType(Divider).first);
      expect(divider.color, AppColors.light.track);
      expect(divider.indent, 14);
      expect(divider.endIndent, 14);
      expect(find.byType(AppCard), findsOneWidget);
    });

    testWidgets('a single row has no divider and an empty group renders', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const Column(
          children: <Widget>[
            AppListGroup(
              children: <Widget>[
                EntryListTile.chevron(title: 'Eins', onTap: _noop),
              ],
            ),
            AppListGroup(children: <Widget>[]),
          ],
        ),
      );
      expect(find.byType(Divider), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final variant in allVariants) {
      testWidgets('${variant.name}: dividers use the track colour', (
        tester,
      ) async {
        await pumpDesign(
          tester,
          const AppListGroup(
            children: <Widget>[
              EntryListTile.chevron(title: 'Eins', onTap: _noop),
              EntryListTile.chevron(title: 'Zwei', onTap: _noop),
            ],
          ),
          variant: variant,
        );
        expect(
          tester.widget<Divider>(find.byType(Divider)).color,
          variant.colors.track,
        );
      });
    }
  });

  group('PeriodOption badge', () {
    PeriodSelector<String> selector({String selected = 'g'}) {
      return PeriodSelector<String>(
        options: const <PeriodOption<String>>[
          PeriodOption<String>(value: 'a', label: 'Aufgaben', badge: '3 offen'),
          PeriodOption<String>(
            value: 'g',
            label: 'Gewohnheiten',
            badge: '3 / 5',
          ),
        ],
        selected: selected,
        onChanged: (_) {},
      );
    }

    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics(
        '${variant.name}: badges follow the selection and are spoken with the label',
        (tester) async {
          await pumpDesign(tester, selector(), variant: variant);
          expect(find.text('3 offen'), findsOneWidget);
          expect(find.text('3 / 5'), findsOneWidget);
          expect(textColor(tester, '3 / 5'), colors.primaryText);
          expect(textColor(tester, '3 offen'), colors.textSecondary);
          expect(
            tester
                .getSemantics(find.bySemanticsLabel('Gewohnheiten, 3 / 5'))
                .flagsCollection
                .isSelected,
            Tristate.isTrue,
          );
          expect(
            tester
                .getSemantics(find.bySemanticsLabel('Aufgaben, 3 offen'))
                .flagsCollection
                .isSelected,
            Tristate.isFalse,
          );
        },
      );
    }

    testWidgets('the badge wraps below the label on narrow screens at 200 %', (
      tester,
    ) async {
      await pumpDesign(tester, selector(), width: 320, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });
}
