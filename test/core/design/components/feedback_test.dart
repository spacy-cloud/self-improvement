import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import '../support/design_test_harness.dart';

/// A page with buttons that trigger the snack bar helpers.
class _SnackHost extends StatelessWidget {
  const _SnackHost({required this.onUndo, required this.onRetry});

  final VoidCallback onUndo;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TextButton(
          onPressed: () => showUndoSnackBar(
            context,
            message: 'Messung gelöscht',
            onUndo: onUndo,
          ),
          child: const Text('undo'),
        ),
        TextButton(
          onPressed: () => showSuccessSnackBar(
            context,
            message: 'Gewicht gespeichert · +10 XP',
          ),
          child: const Text('success'),
        ),
        TextButton(
          onPressed: () => showErrorSnackBar(
            context,
            message: 'Speichern fehlgeschlagen',
            onRetry: onRetry,
          ),
          child: const Text('error'),
        ),
        TextButton(
          onPressed: () => showErrorSnackBar(
            context,
            message: 'Konnte nicht geladen werden',
          ),
          child: const Text('error without retry'),
        ),
      ],
    );
  }
}

Future<void> _show(WidgetTester tester, String trigger) async {
  await tester.tap(find.text(trigger));
  await tester.pump();
  // Enter animation of the snack bar.
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  setUpAll(loadInterFont);

  group('UndoSnackBar visual', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics('${variant.name}: undo, success and error as designed', (
        tester,
      ) async {
        await pumpDesign(
          tester,
          Column(
            children: <Widget>[
              UndoSnackBar.undo(
                key: const ValueKey<String>('undo'),
                message: '„Wäsche waschen“ erledigt',
                onAction: () {},
              ),
              const SizedBox(height: 8),
              const UndoSnackBar.success(
                key: ValueKey<String>('success'),
                message: 'Gewicht gespeichert · +10 XP',
              ),
              const SizedBox(height: 8),
              UndoSnackBar.error(
                key: const ValueKey<String>('error'),
                message: 'Speichern fehlgeschlagen',
                onAction: () {},
              ),
            ],
          ),
          variant: variant,
        );

        Color surfaceOf(String key) {
          final box = find.descendant(
            of: find.byKey(ValueKey<String>(key)),
            matching: find.byType(DecoratedBox),
          );
          return ((tester.widget<DecoratedBox>(box.first).decoration)
                  as BoxDecoration)
              .color!;
        }

        expect(surfaceOf('undo'), colors.snackBarSurface);
        expect(surfaceOf('success'), colors.snackBarSurface);
        expect(surfaceOf('error'), colors.snackBarErrorSurface);
        for (final key in <String>['undo', 'success', 'error']) {
          expect(
            tester.getSize(find.byKey(ValueKey<String>(key))).height,
            greaterThanOrEqualTo(56),
          );
        }
        expect(
          textColor(tester, '„Wäsche waschen“ erledigt'),
          colors.onSnackBar,
        );
        expect(textColor(tester, 'Rückgängig'), colors.snackBarAction);
        expect(textColor(tester, 'Erneut'), colors.snackBarErrorAction);

        // The success variant has no action.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('success')),
            matching: find.byType(InkWell),
          ),
          findsNothing,
        );

        final action = tester.getSemantics(find.bySemanticsLabel('Rückgängig'));
        expect(action.flagsCollection.isButton, isTrue);
        expect(action.rect.height, greaterThanOrEqualTo(48));
        expect(action.rect.width, greaterThanOrEqualTo(48));
      });
    }

    testWidgets('the error variant without callback shows no action', (
      tester,
    ) async {
      await pumpDesign(tester, const UndoSnackBar.error(message: 'Fehler'));
      expect(find.text('Erneut'), findsNothing);
    });

    testWidgets('the message wraps and the bar grows on large text', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        UndoSnackBar.error(
          message: 'Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.',
          onAction: () {},
        ),
        width: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(UndoSnackBar)).height, greaterThan(56));
    });
  });

  group('snack bar helpers', () {
    testWidgets('the undo snack bar stays for 8 seconds and then disappears', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        _SnackHost(onUndo: () {}, onRetry: () {}),
        scrollable: false,
      );
      await _show(tester, 'undo');
      expect(find.text('Messung gelöscht'), findsOneWidget);
      expect(find.text('Rückgängig'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 7000));
      expect(find.text('Messung gelöscht'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(find.text('Messung gelöscht'), findsNothing);
    });

    testWidgets('the 8 second window is the documented constant', (
      tester,
    ) async {
      expect(AppSnackBarDurations.undo, const Duration(seconds: 8));
      expect(AppSnackBarDurations.success, const Duration(seconds: 4));
    });

    testWidgets('tapping Rückgängig calls onUndo once and hides the bar', (
      tester,
    ) async {
      var undone = 0;
      await pumpDesign(
        tester,
        _SnackHost(onUndo: () => undone++, onRetry: () {}),
        scrollable: false,
      );
      await _show(tester, 'undo');
      await tester.tap(find.text('Rückgängig'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(undone, 1);
      expect(find.text('Messung gelöscht'), findsNothing);
    });

    testWidgets('a new snack bar replaces the visible one', (tester) async {
      await pumpDesign(
        tester,
        _SnackHost(onUndo: () {}, onRetry: () {}),
        scrollable: false,
      );
      await _show(tester, 'undo');
      await _show(tester, 'success');
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Messung gelöscht'), findsNothing);
      expect(find.text('Gewicht gespeichert · +10 XP'), findsOneWidget);
    });

    testWidgets('the success snack bar disappears after 4 seconds', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        _SnackHost(onUndo: () {}, onRetry: () {}),
        scrollable: false,
      );
      await _show(tester, 'success');
      await tester.pump(const Duration(milliseconds: 3000));
      expect(find.text('Gewicht gespeichert · +10 XP'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expect(find.text('Gewicht gespeichert · +10 XP'), findsNothing);
    });

    testWidgets('an error with retry stays until the user retries', (
      tester,
    ) async {
      var retries = 0;
      await pumpDesign(
        tester,
        _SnackHost(onUndo: () {}, onRetry: () => retries++),
        scrollable: false,
      );
      await _show(tester, 'error');
      await tester.pump(const Duration(seconds: 60));
      expect(find.text('Speichern fehlgeschlagen'), findsOneWidget);
      await tester.tap(find.text('Erneut'));
      await tester.pumpAndSettle();
      expect(retries, 1);
      expect(find.text('Speichern fehlgeschlagen'), findsNothing);
    });

    testWidgets('an error without retry disappears after 6 seconds', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        _SnackHost(onUndo: () {}, onRetry: () {}),
        scrollable: false,
      );
      await _show(tester, 'error without retry');
      expect(find.text('Erneut'), findsNothing);
      await tester.pump(const Duration(milliseconds: 5000));
      expect(find.text('Konnte nicht geladen werden'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expect(find.text('Konnte nicht geladen werden'), findsNothing);
    });

    testSemantics('the message is announced as a live region', (tester) async {
      await pumpDesign(
        tester,
        _SnackHost(onUndo: () {}, onRetry: () {}),
        scrollable: false,
      );
      await _show(tester, 'undo');
      final live = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true,
      );
      expect(live, findsWidgets);
      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Messung gelöscht')),
      );
      expect(node.flagsCollection.isLiveRegion, isTrue);
      expect(find.bySemanticsLabel('Rückgängig'), findsOneWidget);
    });

    testWidgets(
      'the snack bar floats with a 16 px margin like the Figma frame',
      (tester) async {
        await pumpDesign(
          tester,
          _SnackHost(onUndo: () {}, onRetry: () {}),
          scrollable: false,
        );
        await _show(tester, 'undo');
        final rect = tester.getRect(find.byType(UndoSnackBar));
        expect(rect.left, 16);
        expect(rect.right, 393 - 16);
        expect(rect.bottom, 852 - 16);
        expect(rect.height, greaterThanOrEqualTo(56));
      },
    );
  });

  group('EmptyState', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics(
        '${variant.name}: card with illustration, title, text and primary action',
        (tester) async {
          var taps = 0;
          await pumpDesign(
            tester,
            EmptyState(
              title: 'Noch keine Daten',
              message: 'Trag deinen ersten Wert ein, dann erscheint hier dein Verlauf.',
              actionLabel: 'Ersten Eintrag hinzufügen',
              onAction: () => taps++,
            ),
            variant: variant,
          );
          expect(textColor(tester, 'Noch keine Daten'), colors.textPrimary);
          expect(
            textColor(
              tester,
              'Trag deinen ersten Wert ein, dann erscheint hier dein Verlauf.',
            ),
            colors.textSecondary,
          );
          final decorated = find.descendant(
            of: find.byType(EmptyState),
            matching: find.byType(DecoratedBox),
          );
          final card =
              tester.widget<DecoratedBox>(decorated.first).decoration
                  as BoxDecoration;
          expect(card.color, colors.surface);
          expect(card.borderRadius, AppRadii.sheetBorder);
          expect((card.border! as Border).top.color, colors.borderDecorative);
          expect(find.byType(PrimaryButton), findsOneWidget);
          expect(
            tester
                .getSemantics(
                  find.bySemanticsLabel('Ersten Eintrag hinzufügen'),
                )
                .flagsCollection
                .isButton,
            isTrue,
          );
          await tester.tap(find.byType(PrimaryButton));
          await tester.pump(const Duration(milliseconds: 400));
          expect(taps, 1);
        },
      );
    }

    testWidgets('without an action no button is shown', (tester) async {
      await pumpDesign(
        tester,
        const EmptyState(title: 'Leer', message: 'Nichts da.'),
      );
      expect(find.byType(PrimaryButton), findsNothing);
    });

    testWidgets('the free variant has no card and shrinks the button', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        EmptyState(
          title: 'Leer',
          message: 'Nichts da.',
          actionLabel: 'Hinzufügen',
          onAction: () {},
          card: false,
        ),
      );
      expect(
        tester.getSize(find.byType(PrimaryButton)).width,
        lessThan(393 - 32 - 40),
      );
    });

    testWidgets('wraps and grows on large text without overflow', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        EmptyState(
          title: 'Noch keine Daten vorhanden',
          message:
              'Trag deinen ersten Wert ein, dann erscheint hier dein Verlauf.',
          actionLabel: 'Ersten Eintrag hinzufügen',
          onAction: () {},
        ),
        width: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ErrorState', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics(
        '${variant.name}: error illustration, German defaults and retry',
        (tester) async {
          var retries = 0;
          await pumpDesign(
            tester,
            ErrorState(onRetry: () => retries++),
            variant: variant,
          );
          expect(
            find.text('Daten konnten nicht geladen werden'),
            findsOneWidget,
          );
          expect(
            find.text(
              'Deine Einträge sind sicher gespeichert. Versuche es noch einmal.',
            ),
            findsOneWidget,
          );
          final tint = find.descendant(
            of: find.byType(ErrorState),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).shape == BoxShape.circle,
            ),
          );
          expect(
            (tester.widget<Container>(tint).decoration! as BoxDecoration).color,
            colors.errorTint,
          );
          expect(
            tester.widget<Icon>(find.byIcon(AppIcon.cloudOff.data)).color,
            colors.error,
          );
          expect(find.byType(SecondaryButton), findsOneWidget);
          final live = tester.getSemantics(
            find.bySemanticsLabel(RegExp('Daten konnten nicht')),
          );
          expect(live.flagsCollection.isLiveRegion, isTrue);
          await tester.tap(find.byType(SecondaryButton));
          await tester.pump(const Duration(milliseconds: 400));
          expect(retries, 1);
        },
      );
    }

    testWidgets('title, text and retry label can be replaced', (tester) async {
      await pumpDesign(
        tester,
        ErrorState(
          onRetry: () {},
          title: 'Sicherung nicht lesbar',
          message: 'Die Datei ist beschädigt.',
          retryLabel: 'Andere Datei wählen',
        ),
      );
      expect(find.text('Sicherung nicht lesbar'), findsOneWidget);
      expect(find.text('Die Datei ist beschädigt.'), findsOneWidget);
      expect(find.text('Andere Datei wählen'), findsOneWidget);
    });

    testWidgets(
      'the free variant is centred on the page without overflow at 200 %',
      (tester) async {
        await pumpDesign(
          tester,
          ErrorState(onRetry: () {}, card: false),
          width: 320,
          height: 568,
          textScale: 2,
          scrollable: false,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ConfirmationSheet', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics(
        '${variant.name}: destructive content with handle, texts and two buttons',
        (tester) async {
          var confirms = 0;
          var cancels = 0;
          await pumpDesign(
            tester,
            ConfirmationSheet(
              title: 'Eintrag löschen?',
              message: 'Der Eintrag wird entfernt.',
              confirmLabel: 'Löschen',
              onConfirm: () => confirms++,
              onCancel: () => cancels++,
            ),
            variant: variant,
          );
          expect(textColor(tester, 'Eintrag löschen?'), colors.textPrimary);
          expect(
            textColor(tester, 'Der Eintrag wird entfernt.'),
            colors.textSecondary,
          );
          expect(textColor(tester, 'Löschen'), colors.error);
          expect(textColor(tester, 'Abbrechen'), colors.textPrimary);
          final decoration =
              tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: find.byType(ConfirmationSheet),
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration;
          expect(decoration.color, colors.surface);
          expect(decoration.borderRadius, AppRadii.sheetBorder);

          // The destructive action comes first, the safe action last.
          expect(
            tester.getTopLeft(find.text('Löschen')).dy,
            lessThan(tester.getTopLeft(find.text('Abbrechen')).dy),
          );
          final title = tester.getSemantics(
            find.bySemanticsLabel('Eintrag löschen?').last,
          );
          expect(title.flagsCollection.isHeader, isTrue);

          await tester.tap(find.text('Löschen'));
          await tester.tap(find.text('Abbrechen'));
          await tester.pump(const Duration(milliseconds: 400));
          expect(confirms, 1);
          expect(cancels, 1);
        },
      );
    }

    testWidgets('a non-destructive sheet does not use the error colour', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        ConfirmationSheet(
          title: 'Ohne Speichern verlassen?',
          message: 'Deine Eingaben gehen verloren.',
          confirmLabel: 'Verlassen',
          destructive: false,
          onConfirm: () {},
          onCancel: () {},
        ),
      );
      expect(textColor(tester, 'Verlassen'), AppColors.light.textPrimary);
    });

    testWidgets('"Abbrechen" takes the initial focus (safe default)', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        ConfirmationSheet(
          title: 'Eintrag löschen?',
          message: 'Der Eintrag wird entfernt.',
          confirmLabel: 'Löschen',
          onConfirm: () {},
          onCancel: () {},
        ),
      );
      await tester.pump();
      final focusContext = FocusManager.instance.primaryFocus?.context;
      expect(focusContext, isNotNull);
      var insideCancel = false;
      focusContext!.visitAncestorElements((element) {
        final widget = element.widget;
        if (widget is SecondaryButton) {
          insideCancel = widget.label == 'Abbrechen';
          return false;
        }
        return true;
      });
      expect(insideCancel, isTrue);
    });
  });

  group('showConfirmationSheet', () {
    Widget host(ValueChanged<bool> onResult) {
      return Builder(
        builder: (context) => Column(
          children: <Widget>[
            TextButton(
              onPressed: () async {
                final result = await showConfirmationSheet(
                  context,
                  title: 'Eintrag löschen?',
                  message: 'Der Eintrag wird entfernt.',
                  confirmLabel: 'Löschen',
                );
                onResult(result);
              },
              child: const Text('open'),
            ),
            const Text('Hintergrund'),
          ],
        ),
      );
    }

    testWidgets('confirming returns true', (tester) async {
      final results = <bool>[];
      await pumpDesign(tester, host(results.add), scrollable: false);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Eintrag löschen?'), findsOneWidget);
      await tester.tap(find.text('Löschen'));
      await tester.pumpAndSettle();
      expect(results, <bool>[true]);
      expect(find.text('Eintrag löschen?'), findsNothing);
    });

    testWidgets('cancelling returns false', (tester) async {
      final results = <bool>[];
      await pumpDesign(tester, host(results.add), scrollable: false);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(results, <bool>[false]);
    });

    testWidgets('the system back gesture closes the sheet as cancel', (
      tester,
    ) async {
      final results = <bool>[];
      await pumpDesign(tester, host(results.add), scrollable: false);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Eintrag löschen?'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Eintrag löschen?'), findsNothing);
      expect(results, <bool>[false]);
    });

    testWidgets('tapping the barrier closes the sheet as cancel', (
      tester,
    ) async {
      final results = <bool>[];
      await pumpDesign(tester, host(results.add), scrollable: false);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(196, 40));
      await tester.pumpAndSettle();
      expect(find.text('Eintrag löschen?'), findsNothing);
      expect(results, <bool>[false]);
    });

    testWidgets('the background is inactive while the sheet is open', (
      tester,
    ) async {
      final results = <bool>[];
      await pumpDesign(tester, host(results.add), scrollable: false);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // The "open" button is covered by the barrier: tapping it only dismisses.
      await tester.tap(find.text('open'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Eintrag löschen?'), findsNothing);
      expect(results, <bool>[false]);
    });

    testWidgets(
      'the default focus is "Abbrechen" and the barrier has a German label',
      (tester) async {
        final results = <bool>[];
        await pumpDesign(tester, host(results.add), scrollable: false);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final focusContext = FocusManager.instance.primaryFocus?.context;
        expect(focusContext, isNotNull);
        var label = '';
        focusContext!.visitAncestorElements((element) {
          final widget = element.widget;
          if (widget is SecondaryButton) {
            label = widget.label;
            return false;
          }
          return true;
        });
        expect(label, 'Abbrechen');
        final barrier = tester.widget<ModalBarrier>(
          find.byType(ModalBarrier).last,
        );
        expect(barrier.semanticsLabel, 'Schließen');
        expect(barrier.color, AppColors.light.scrim);
      },
    );

    testSemantics('the sheet names the route and is a scoped modal', (
      tester,
    ) async {
      final results = <bool>[];
      await pumpDesign(tester, host(results.add), scrollable: false);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final node = tester.getSemantics(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.scopesRoute == true &&
              w.properties.label == 'Eintrag löschen?',
        ),
      );
      expect(node.flagsCollection.namesRoute, isTrue);
      expect(node.flagsCollection.scopesRoute, isTrue);
    });

    testWidgets('large text on a small screen scrolls instead of overflowing', (
      tester,
    ) async {
      final results = <bool>[];
      await pumpDesign(
        tester,
        host(results.add),
        width: 320,
        height: 568,
        textScale: 2,
        scrollable: false,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(results, <bool>[false]);
    });

    testWidgets('a non-destructive sheet confirms with true', (tester) async {
      final results = <bool>[];
      await pumpDesign(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              results.add(
                await showConfirmationSheet(
                  context,
                  title: 'Verlassen?',
                  message: 'Eingaben gehen verloren.',
                  confirmLabel: 'Verlassen',
                  cancelLabel: 'Bleiben',
                  destructive: false,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
        scrollable: false,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Bleiben'), findsOneWidget);
      await tester.tap(find.text('Verlassen'));
      await tester.pumpAndSettle();
      expect(results, <bool>[true]);
    });
  });
}
