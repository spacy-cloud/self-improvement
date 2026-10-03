import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import '../support/design_test_harness.dart';

void main() {
  setUpAll(loadInterFont);

  group('PrimaryButton', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics(
        '${variant.name}: default state uses the button colour with on-primary text',
        (tester) async {
          await pumpDesign(
            tester,
            PrimaryButton(label: 'Eintrag speichern', onPressed: () {}),
            variant: variant,
          );
          final button = find.byType(PrimaryButton);
          expect(materialOf(tester, button).color, colors.primaryButton);
          expect(textColor(tester, 'Eintrag speichern'), colors.onPrimary);
          expect(tester.getSize(button).height, greaterThanOrEqualTo(56));
          expect(tester.getSize(button).width, 393 - 32);
          final flags = tester.getSemantics(button).flagsCollection;
          expect(flags.isButton, isTrue);
          expect(flags.isEnabled, Tristate.isTrue);
          expect(tester.getSemantics(button).label, 'Eintrag speichern');
        },
      );

      testSemantics(
        '${variant.name}: disabled state uses track and tertiary text, no tap action',
        (tester) async {
          await pumpDesign(
            tester,
            const PrimaryButton(label: 'Eintrag speichern', onPressed: null),
            variant: variant,
          );
          final button = find.byType(PrimaryButton);
          expect(materialOf(tester, button).color, colors.track);
          expect(textColor(tester, 'Eintrag speichern'), colors.textTertiary);
          final node = tester.getSemantics(button);
          expect(node.flagsCollection.isEnabled, Tristate.isFalse);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isFalse,
          );
        },
      );

      testSemantics(
        '${variant.name}: loading shows the loading text, is announced and ignores taps',
        (tester) async {
          var taps = 0;
          await pumpDesign(
            tester,
            PrimaryButton(
              label: 'Eintrag speichern',
              onPressed: () => taps++,
              loading: true,
            ),
            variant: variant,
          );
          expect(find.text('Wird gespeichert …'), findsOneWidget);
          expect(find.text('Eintrag speichern'), findsNothing);
          final button = find.byType(PrimaryButton);
          expect(materialOf(tester, button).color, colors.primaryButton);
          final node = tester.getSemantics(button);
          expect(node.label, 'Wird gespeichert …');
          expect(node.flagsCollection.isLiveRegion, isTrue);
          expect(node.flagsCollection.isEnabled, Tristate.isFalse);
          await tester.tap(button);
          await tester.pump();
          expect(taps, 0);
        },
      );
    }

    testWidgets('a tap calls the callback exactly once', (tester) async {
      var taps = 0;
      await pumpDesign(
        tester,
        PrimaryButton(label: 'Speichern', onPressed: () => taps++),
      );
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 1);
    });

    testWidgets('the pressed state shows a ripple on the button surface', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        PrimaryButton(label: 'Speichern', onPressed: () {}),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PrimaryButton)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final inkWell = tester.widget<InkWell>(find.byType(InkWell));
      expect(inkWell.onTap, isNotNull);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testSemantics('semantic label can be overridden', (tester) async {
      await pumpDesign(
        tester,
        PrimaryButton(
          label: 'Speichern',
          semanticLabel: 'Gewicht speichern',
          onPressed: () {},
        ),
      );
      expect(
        tester.getSemantics(find.byType(PrimaryButton)).label,
        'Gewicht speichern',
      );
    });

    testWidgets('grows with large text instead of clipping', (tester) async {
      await pumpDesign(
        tester,
        PrimaryButton(
          label: 'Ersten Eintrag hinzufügen und speichern',
          onPressed: () {},
        ),
        width: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(PrimaryButton)).height,
        greaterThan(56),
      );
    });

    testWidgets('expand: false shrinks to the content and works inside a Row', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        Row(
          children: <Widget>[
            PrimaryButton(label: 'Speichern', onPressed: () {}, expand: false),
            PrimaryButton(label: 'Speichern', onPressed: () {}),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(PrimaryButton).first).width,
        lessThan(200),
      );
    });

    testWidgets('an icon is shown in front of the label', (tester) async {
      await pumpDesign(
        tester,
        PrimaryButton(label: 'Hinzufügen', icon: Icons.add, onPressed: () {}),
      );
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });

  group('SecondaryButton', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics(
        '${variant.name}: default uses the input border and primary text',
        (tester) async {
          await pumpDesign(
            tester,
            SecondaryButton(label: 'Abbrechen', onPressed: () {}),
            variant: variant,
          );
          final button = find.byType(SecondaryButton);
          final shape =
              materialOf(tester, button).shape! as RoundedRectangleBorder;
          expect(shape.side.color, colors.borderInput);
          expect(shape.side.width, 1.5);
          expect(materialOf(tester, button).color, colors.surface);
          expect(textColor(tester, 'Abbrechen'), colors.textPrimary);
          expect(tester.getSize(button).height, greaterThanOrEqualTo(52));
          expect(tester.getSemantics(button).label, 'Abbrechen');
        },
      );

      testWidgets(
        '${variant.name}: danger uses the error colour for border and text',
        (tester) async {
          await pumpDesign(
            tester,
            SecondaryButton(
              label: 'Zurücksetzen …',
              danger: true,
              onPressed: () {},
            ),
            variant: variant,
          );
          final shape =
              materialOf(tester, find.byType(SecondaryButton)).shape!
                  as RoundedRectangleBorder;
          expect(shape.side.color, colors.error);
          expect(textColor(tester, 'Zurücksetzen …'), colors.error);
        },
      );

      testSemantics(
        '${variant.name}: disabled uses tertiary text and is not tappable',
        (tester) async {
          await pumpDesign(
            tester,
            const SecondaryButton(label: 'Abbrechen', onPressed: null),
            variant: variant,
          );
          expect(textColor(tester, 'Abbrechen'), colors.textTertiary);
          final node = tester.getSemantics(find.byType(SecondaryButton));
          expect(node.flagsCollection.isEnabled, Tristate.isFalse);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isFalse,
          );
        },
      );
    }

    testWidgets('a tap calls the callback', (tester) async {
      var taps = 0;
      await pumpDesign(
        tester,
        SecondaryButton(label: 'Abbrechen', onPressed: () => taps++),
      );
      await tester.tap(find.byType(SecondaryButton));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 1);
    });

    testWidgets('autofocus puts the initial focus on the button', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        SecondaryButton(label: 'Abbrechen', autofocus: true, onPressed: () {}),
      );
      await tester.pump();
      final focusContext = FocusManager.instance.primaryFocus?.context;
      expect(focusContext, isNotNull);
      var inside = false;
      focusContext!.visitAncestorElements((element) {
        if (element.widget is SecondaryButton) {
          inside = true;
          return false;
        }
        return true;
      });
      expect(inside, isTrue);
    });
  });

  group('AppIconButton', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics(
        '${variant.name}: plain has a 48 x 48 target without background',
        (tester) async {
          await pumpDesign(
            tester,
            AppIconButton(
              icon: Icons.chevron_left,
              semanticLabel: 'Zurück',
              onPressed: () {},
            ),
            variant: variant,
          );
          final button = find.byType(AppIconButton);
          expect(tester.getSize(button), const Size(48, 48));
          expect(semanticsSize(tester, button), const Size(48, 48));
          expect(tester.getSemantics(button).label, 'Zurück');
          expect(find.byType(Ink), findsOneWidget);
          final ink = tester.widget<Ink>(find.byType(Ink));
          expect(ink.decoration, isNull);
          expect(tester.getSize(find.byType(Ink)), const Size(40, 40));
        },
      );

      testWidgets(
        '${variant.name}: filled draws the surface circle with the decorative border',
        (tester) async {
          await pumpDesign(
            tester,
            AppIconButton(
              icon: Icons.chevron_left,
              semanticLabel: 'Zurück',
              filled: true,
              onPressed: () {},
            ),
            variant: variant,
          );
          final ink = tester.widget<Ink>(find.byType(Ink));
          final decoration = ink.decoration! as BoxDecoration;
          expect(decoration.color, colors.surface);
          expect(decoration.shape, BoxShape.circle);
          expect(
            (decoration.border! as Border).top.color,
            colors.borderDecorative,
          );
          expect(tester.getSize(find.byType(Ink)), const Size(40, 40));
        },
      );
    }

    testWidgets('the whole 48 px area is tappable, not only the 40 px circle', (
      tester,
    ) async {
      var taps = 0;
      await pumpDesign(
        tester,
        Center(
          child: AppIconButton(
            icon: Icons.close,
            semanticLabel: 'Schließen',
            onPressed: () => taps++,
          ),
        ),
        scrollable: false,
      );
      final center = tester.getCenter(find.byType(AppIconButton));
      await tester.tapAt(center + const Offset(21, 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 1);
    });

    testSemantics('disabled button has no tap action', (tester) async {
      await pumpDesign(
        tester,
        const AppIconButton(
          icon: Icons.close,
          semanticLabel: 'Schließen',
          onPressed: null,
        ),
      );
      final node = tester.getSemantics(find.byType(AppIconButton));
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    });
  });
}
