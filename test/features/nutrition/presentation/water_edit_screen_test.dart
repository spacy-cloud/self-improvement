import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/presentation/water_form_body.dart';

import 'support/nutrition_ui_kit.dart';

String _amountText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(waterAmountFieldKey)).controller!.text;

PrimaryButton _primary(WidgetTester tester) =>
    tester.widget<PrimaryButton>(find.byType(PrimaryButton).last);

void main() {
  group('edit', () {
    testWidgets(
      'the entry is shown, save stays off until something changed, then '
      'saves, reports after the commit and the undo restores it (AT23, AT10)',
      (tester) async {
        final ui = await NutritionUi.create(tester, realProjection: true);
        final entry = await ui.addWater(
          250,
          ago: const Duration(hours: 1),
          note: 'Frühstück',
        );
        await ui.pumpRoute('/water/${entry.id}');

        expect(find.text('Eintrag bearbeiten'), findsOneWidget);
        expect(_amountText(tester), '250');
        expect(find.text('Frühstück'), findsOneWidget);
        expect(find.text('Heute, 09:00 Uhr'), findsOneWidget);
        expect(_primary(tester).onPressed, isNull, reason: 'nothing changed');

        await tester.enterText(find.byKey(waterAmountFieldKey), '300');
        await tester.pump();
        expect(_primary(tester).onPressed, isNotNull);
        await tester.tap(find.text('Änderungen speichern'));
        await ui.until(() => ui.feedback.events.isNotEmpty);

        expect(ui.feedback.last!.message, 'Eintrag aktualisiert');
        expect(await ui.waterTotalMl(), 300);
        expect(await ui.totalXp(), 5);
        await tester.pumpAndSettle();
        expect(find.text('Wasser eintragen'), findsOneWidget);
        expect(find.text('300 ml'), findsWidgets);

        expect(await ui.pressUndo(), UndoResult.undone);
        expect(await ui.waterTotalMl(), 250);
      },
    );

    testWidgets('minus and plus change the amount by 10 ml', (tester) async {
      final ui = await NutritionUi.create(tester);
      final entry = await ui.addWater(250);
      await ui.pumpRoute('/water/${entry.id}');
      await tester.tap(find.bySemanticsLabel('um 10 Milliliter erhöhen'));
      await tester.pump();
      expect(_amountText(tester), '260');
    });

    testWidgets('an amount outside 50 to 2000 ml is rejected, input kept', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      final entry = await ui.addWater(250);
      await ui.pumpRoute('/water/${entry.id}');

      await tester.enterText(find.byKey(waterAmountFieldKey), '49');
      await tester.pump();
      await tester.tap(find.text('Änderungen speichern'));
      await tester.pump();

      expect(
        find.text('Bitte gib eine Menge zwischen 50 und 2.000 ml ein.'),
        findsOneWidget,
      );
      expect(_amountText(tester), '49');
      expect(await ui.waterTotalMl(), 250);
      expect(ui.feedback.events, isEmpty);
    });

    testWidgets(
      'a failed save keeps the input and the retry is the same command '
      '(AT27, AT12)',
      (tester) async {
        late FlakyProjection flaky;
        late RecordingIdGenerator ids;
        final ui = await NutritionUi.create(
          tester,
          projection: (h) => flaky = FlakyProjection(h.projections),
          ids: (h) => ids = RecordingIdGenerator(h.ids),
        );
        final entry = await ui.addWater(250);
        await ui.pumpRoute('/water/${entry.id}');
        await tester.enterText(find.byKey(waterAmountFieldKey), '400');
        await tester.pump();
        final issuedBefore = ids.issued.length;

        flaky.failAfterSync = StateError('disk full');
        await tester.tap(find.text('Änderungen speichern'));
        await ui.until(() => ui.feedback.events.isNotEmpty);

        expect(ui.feedback.last!.kind, 'error');
        expect(
          ui.feedback.last!.message,
          'Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.',
        );
        expect(_amountText(tester), '400');
        expect(await ui.waterTotalMl(), 250);
        final failedId = ids.issued[issuedBefore];

        flaky.failAfterSync = null;
        ui.feedback.last!.onRetry!();
        await ui.until(() => ui.feedback.events.last.kind == 'saved');
        expect(await ui.waterTotalMl(), 400);
        final updates = (await ui.receipts()).where(
          (r) => r.commandType.contains('update'),
        );
        expect(updates.single.commandId, failedId);
      },
    );

    testWidgets('a change made elsewhere is reported, nothing is lost', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      final entry = await ui.addWater(250);
      await ui.pumpRoute('/water/${entry.id}');
      await tester.enterText(find.byKey(waterAmountFieldKey), '400');
      await tester.pump();

      // The same entry is changed behind the open form.
      await tester.runCommand(
        () => ui.water.update(
          commandId: ui.harness.ids.newId(),
          id: entry.id,
          draft: WaterDraft(amountMl: 500, occurredAtUtc: entry.occurredAtUtc),
          expectedRowVersion: entry.rowVersion,
        ),
      );
      await tester.tap(find.text('Änderungen speichern'));
      await ui.until(() => ui.feedback.events.isNotEmpty);

      expect(ui.feedback.last!.kind, 'error');
      expect(_amountText(tester), '400', reason: 'the input is kept');
      expect(await ui.waterTotalMl(), 500);
    });
  });

  group('delete', () {
    testWidgets(
      'asks first, deletes, reports after the commit and the undo restores the '
      'same entry (AT10, AT23)',
      (tester) async {
        final ui = await NutritionUi.create(tester, realProjection: true);
        final entry = await ui.addWater(500, ago: const Duration(hours: 1));
        await ui.pumpRoute('/water/${entry.id}');

        await tester.tap(find.text('Eintrag löschen'));
        await tester.pumpAndSettle();
        expect(find.textContaining('löschen?'), findsOneWidget);
        expect(
          find.text(
            '500 ml werden entfernt. Du kannst es direkt danach rückgängig '
            'machen.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Abbrechen'));
        await tester.pumpAndSettle();
        expect(await ui.waterCount(), 1);

        await tester.tap(find.text('Eintrag löschen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Löschen'));
        await ui.until(() => ui.feedback.events.isNotEmpty);
        await tester.pumpAndSettle();

        expect(ui.feedback.last!.message, 'Eintrag gelöscht');
        expect(await ui.waterCount(), 0);
        expect(await ui.totalXp(), 0);
        expect(find.text('Wasser eintragen'), findsOneWidget, reason: 'left');

        await ui.pressUndo();
        final back = await tester.runAsync(() => ui.water.findById(entry.id));
        expect(back, isNotNull);
        expect(await ui.totalXp(), 5);
      },
    );
  });

  group('leaving', () {
    testWidgets('unchanged input leaves without a question', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.addWater(250, ago: const Duration(hours: 1));
      final router = await ui.pumpRoute('/water');
      await tester.tap(find.text('09:00 Uhr'));
      await tester.pumpAndSettle();
      expect(find.text('Eintrag bearbeiten'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsNothing);
      expect(find.text('Wasser eintragen'), findsOneWidget);
      expect(router.state.uri.path, '/water');
    });

    testWidgets('changed input asks "Änderungen verwerfen?" (back button)', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      final entry = await ui.addWater(250);
      await ui.pumpRoute('/water/${entry.id}');
      await tester.enterText(find.byKey(waterAmountFieldKey), '300');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await tester.tap(find.text('Weiter bearbeiten'));
      await tester.pumpAndSettle();
      expect(_amountText(tester), '300');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await tester.tap(find.text('Verwerfen'));
      await tester.pumpAndSettle();
      expect(find.text('Wasser eintragen'), findsOneWidget);
      expect(await ui.waterTotalMl(), 250, reason: 'nothing was saved');
    });
  });

  group('states', () {
    testWidgets('an entry that does not exist offers the way back', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      final router = await ui.pumpRoute('/water/does-not-exist');
      expect(find.text('Eintrag nicht gefunden'), findsOneWidget);
      await tester.tap(find.text('Zur Übersicht'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/water');
    });

    testWidgets('a load error offers a retry', (tester) async {
      var attempts = 0;
      final ui = await NutritionUi.create(
        tester,
        overrides: [
          waterEntryProvider.overrideWith((ref, id) {
            attempts++;
            if (attempts == 1) {
              return Stream<WaterEntry?>.error(StateError('db'));
            }
            return ref.watch(waterRepositoryProvider).watchById(id);
          }),
        ],
      );
      final entry = await ui.addWater(250);
      await ui.pumpRoute('/water/${entry.id}');
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);

      await tester.tap(find.text('Erneut versuchen'));
      await ui.until(
        () => find.byKey(waterAmountFieldKey).evaluate().isNotEmpty,
      );
      expect(_amountText(tester), '250');
    });

    testWidgets('loading shows a short text', (tester) async {
      final ui = await NutritionUi.create(
        tester,
        overrides: [
          waterEntryProvider.overrideWith(
            (ref, id) => Stream<WaterEntry?>.multi((controller) {}),
          ),
        ],
      );
      await ui.pumpRoute('/water/any');
      expect(find.text('Wird geladen …'), findsOneWidget);
    });
  });
}
