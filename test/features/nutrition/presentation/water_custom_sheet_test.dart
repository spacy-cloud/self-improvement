import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/nutrition/presentation/water_form_body.dart';

import 'support/nutrition_ui_kit.dart';

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('Eigene Menge'));
  await tester.pumpAndSettle();
  expect(find.text('Eigene Menge'), findsNWidgets(2)); // tile + sheet title
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(waterAmountFieldKey), text);
  await tester.pump();
}

PrimaryButton _primary(WidgetTester tester) =>
    tester.widget<PrimaryButton>(find.byType(PrimaryButton).last);

void main() {
  group('amount limits (N01)', () {
    for (final (ml, valid, saved) in [
      (49, false, ''),
      (50, true, '50 ml hinzugefügt'),
      (2000, true, '2.000 ml hinzugefügt'),
      (2001, false, ''),
    ]) {
      testWidgets(
        '$ml ml is ${valid ? 'saved as a real entry' : 'rejected with a hint'}',
        (tester) async {
          final ui = await NutritionUi.create(tester);
          await ui.pumpRoute('/water');
          await _openSheet(tester);
          await _type(tester, '$ml');

          _primary(tester).onPressed!();
          if (valid) {
            await ui.until(() => ui.feedback.events.isNotEmpty);
            expect(ui.feedback.last!.message, saved);
            expect(await ui.waterTotalMl(), ml);
            await tester.pumpAndSettle();
            expect(find.text('Eigene Menge'), findsOneWidget, reason: 'closed');
          } else {
            await tester.pump();
            expect(
              find.text('Bitte gib eine Menge zwischen 50 und 2.000 ml ein.'),
              findsOneWidget,
            );
            expect(await ui.waterCount(), 0);
            expect(ui.feedback.events, isEmpty);
            expect(
              tester
                  .widget<TextField>(find.byKey(waterAmountFieldKey))
                  .controller!
                  .text,
              '$ml',
              reason: 'the input is kept',
            );
          }
        },
      );
    }

    testWidgets('an empty amount asks for the amount', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await _openSheet(tester);

      expect(_primary(tester).label, 'Menge hinzufügen');
      _primary(tester).onPressed!();
      await tester.pump();
      expect(
        find.text('Bitte gib die Menge in Millilitern ein.'),
        findsOneWidget,
      );
      expect(await ui.waterCount(), 0);
    });

    testWidgets('only digits can be typed', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await _openSheet(tester);
      await _type(tester, '2a5,0 ml');
      expect(
        tester
            .widget<TextField>(find.byKey(waterAmountFieldKey))
            .controller!
            .text,
        '250',
      );
    });
  });

  group('stepper', () {
    testWidgets('starts at 250 ml and moves in 10 ml steps within the limits', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await _openSheet(tester);

      String text() => tester
          .widget<TextField>(find.byKey(waterAmountFieldKey))
          .controller!
          .text;
      Future<void> tapStep(String label) async {
        await tester.tap(find.bySemanticsLabel(label));
        await tester.pump();
      }

      await tapStep('um 10 Milliliter erhöhen');
      expect(text(), '250', reason: 'the first press shows the start value');
      await tapStep('um 10 Milliliter erhöhen');
      expect(text(), '260');
      await tapStep('um 10 Milliliter verringern');
      await tapStep('um 10 Milliliter verringern');
      expect(text(), '240');
      expect(_primary(tester).label, '240 ml hinzufügen');

      await _type(tester, '55');
      await tapStep('um 10 Milliliter verringern');
      expect(text(), '50', reason: 'clamped to the smallest amount');
      var stepper = tester.widget<QuantityStepper>(
        find.byType(QuantityStepper),
      );
      expect(stepper.onDecrease, isNull, reason: 'minus is off at 50 ml');

      await _type(tester, '1995');
      await tapStep('um 10 Milliliter erhöhen');
      expect(text(), '2000', reason: 'clamped to the largest amount');
      stepper = tester.widget<QuantityStepper>(find.byType(QuantityStepper));
      expect(stepper.onIncrease, isNull, reason: 'plus is off at 2000 ml');
    });
  });

  group('saving', () {
    testWidgets(
      'saves amount and note at the current time, reports after the commit and the undo removes the entry (N01, AT10)',
      (tester) async {
        final ui = await NutritionUi.create(tester, realProjection: true);
        await ui.pumpRoute('/water');
        await _openSheet(tester);
        await _type(tester, '330');
        await tester.enterText(find.byType(TextField).last, 'nach dem Sport');
        await tester.pump();
        expect(_primary(tester).label, '330 ml hinzufügen');

        _primary(tester).onPressed!();
        await ui.until(() => ui.feedback.events.isNotEmpty);

        expect(ui.feedback.last!.message, '330 ml hinzugefügt');
        final today = await tester.runAsync(() => ui.water.loadToday(uiToday));
        final entry = today!.entriesNewestFirst.single;
        expect(entry.amountMl, 330);
        expect(entry.note, 'nach dem Sport');
        expect(entry.occurredAtUtc, ui.harness.clock.nowUtc());
        expect(await ui.totalXp(), 5);

        await ui.pressUndo();
        expect(await ui.waterCount(), 0);
        expect(await ui.totalXp(), 0);
      },
    );

    testWidgets('a date and time can be chosen with the pickers', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await _openSheet(tester);
      await _type(tester, '200');
      expect(find.text('Heute, 10:00 Uhr'), findsOneWidget);

      await tester.tap(find.text('Zeitpunkt'));
      await tester.pumpAndSettle();
      expect(find.text('Datum der Trinkmenge'), findsOneWidget);
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Uhrzeit der Trinkmenge'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Gestern, 10:00 Uhr'), findsOneWidget);

      _primary(tester).onPressed!();
      await ui.until(() => ui.feedback.events.isNotEmpty);
      final yesterday = await tester.runAsync(
        () => ui.water.loadHistory(today: uiToday, days: 14),
      );
      expect(yesterday!.daysNewestFirst.single.date, uiToday.addDays(-1));
      expect(yesterday.daysNewestFirst.single.totalMl, 200);
    });

    testWidgets('a double tap on save stores one entry (AT12)', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await _openSheet(tester);
      await _type(tester, '300');

      await tester.tap(find.byType(PrimaryButton).last);
      await tester.tap(find.byType(PrimaryButton).last, warnIfMissed: false);
      await ui.until(() => ui.feedback.events.isNotEmpty);
      await tester.pumpAndSettle();

      expect(await ui.waterCount(), 1);
      expect((await ui.receipts()), hasLength(1));
      expect(ui.feedback.events, hasLength(1));
    });

    testWidgets(
      'a failed save keeps the input, says so inside the form and the retry is the same command (AT27, AT12)',
      (tester) async {
        late FlakyProjection flaky;
        late RecordingIdGenerator ids;
        final ui = await NutritionUi.create(
          tester,
          realProjection: true,
          projection: (h) => flaky = FlakyProjection(h.projections),
          ids: (h) => ids = RecordingIdGenerator(h.ids),
        );
        flaky.failAfterSync = StateError('disk full');
        await ui.pumpRoute('/water');
        await _openSheet(tester);
        await _type(tester, '330');

        _primary(tester).onPressed!();
        await ui.until(
          () => find
              .text('Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.')
              .evaluate()
              .isNotEmpty,
          reason: 'inline failure',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(waterAmountFieldKey))
              .controller!
              .text,
          '330',
        );
        expect(await ui.waterCount(), 0);
        expect(await ui.totalXp(), 0);
        expect(_primary(tester).label, '330 ml hinzufügen');
        final failedId = ids.issued.first;

        flaky.failAfterSync = null;
        await tester.tap(find.text('Erneut versuchen'));
        await ui.until(() => ui.feedback.events.isNotEmpty);

        expect(await ui.waterCount(), 1);
        final receipts = await ui.receipts();
        expect(receipts, hasLength(1));
        expect(receipts.single.commandId, failedId);
        expect(await ui.totalXp(), 5);
      },
    );

    testWidgets('the keyboard action saves like the button', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await _openSheet(tester);
      await tester.tap(find.byKey(waterAmountFieldKey));
      await tester.enterText(find.byKey(waterAmountFieldKey), '150');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await ui.until(() => ui.feedback.events.isNotEmpty);
      expect(ui.feedback.last!.message, '150 ml hinzugefügt');
    });
  });

  group('leaving', () {
    testWidgets('closing without input needs no question', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await _openSheet(tester);

      await tester.tap(iconButtonLabelled('Schließen'));
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsNothing);
      expect(find.text('Eigene Menge'), findsOneWidget, reason: 'sheet gone');
    });

    testWidgets('input asks "Änderungen verwerfen?" (close button)', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await _openSheet(tester);
      await _type(tester, '300');

      await tester.tap(iconButtonLabelled('Schließen'));
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);

      await tester.tap(find.text('Weiter bearbeiten'));
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(waterAmountFieldKey))
            .controller!
            .text,
        '300',
        reason: 'the input survives "Weiter bearbeiten"',
      );

      await tester.tap(iconButtonLabelled('Schließen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verwerfen'));
      await tester.pumpAndSettle();
      expect(find.text('Eigene Menge'), findsOneWidget, reason: 'sheet gone');
      expect(await ui.waterCount(), 0);
    });

    testWidgets('Android back asks as well', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await _openSheet(tester);
      await _type(tester, '300');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
    });
  });

  group('a rejected save', () {
    testWidgets('puts the focus on the invalid amount field', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await _openSheet(tester);
      await _type(tester, '49');

      _primary(tester).onPressed!();
      await tester.pump();

      expect(
        find.text('Bitte gib eine Menge zwischen 50 und 2.000 ml ein.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(waterAmountFieldKey))
            .focusNode!
            .hasFocus,
        isTrue,
        reason: 'the first invalid field is read together with its hint',
      );
    });
  });

  group('a rejected note', () {
    testWidgets('puts the focus on the note when only the note is invalid', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await _openSheet(tester);
      await _type(tester, '300');
      // The field counts characters, the rule counts code points: 101 family
      // emojis are 101 characters for the field and 505 code points for the
      // rule of 500.
      final note = find.byType(TextField).last;
      await tester.enterText(
        note,
        '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}' * 101,
      );
      await tester.pump();

      _primary(tester).onPressed!();
      await tester.pump();

      expect(
        find.text('Die Notiz darf höchstens 500 Zeichen lang sein.'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(note).focusNode!.hasFocus, isTrue);
      expect(
        tester
            .widget<TextField>(find.byKey(waterAmountFieldKey))
            .focusNode!
            .hasFocus,
        isFalse,
      );
    });
  });

  group('small screens', () {
    testWidgets(
      'with the keyboard open at 200 % text the button is reachable',
      (tester) async {
        final ui = await NutritionUi.create(tester);
        await ui.pumpRoute(
          '/water',
          size: const Size(320, 640),
          textScale: 2.0,
          viewInsets: const EdgeInsets.only(bottom: 260),
        );
        await ui.reveal(find.text('Eigene Menge'));
        await tester.tap(find.text('Eigene Menge'));
        await tester.pumpAndSettle();
        await _type(tester, '300');

        final button = find.text('300 ml hinzufügen');
        await tester.ensureVisible(button);
        final rect = tester.getRect(button);
        expect(rect.bottom, lessThanOrEqualTo(640 - 260 + 1));
        await tester.tap(button);
        await ui.until(() => ui.feedback.events.isNotEmpty);
        expect(await ui.waterTotalMl(), 300);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
