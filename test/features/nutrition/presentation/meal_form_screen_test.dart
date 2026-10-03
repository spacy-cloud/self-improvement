import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/presentation/meal_form_screen.dart';

import 'support/nutrition_ui_kit.dart';

String _text(WidgetTester tester, Key key) => tester
    .widget<TextField>(
      find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
    )
    .controller!
    .text;

Future<void> _fill(
  WidgetTester tester, {
  String? name,
  String? kcal,
  String? note,
}) async {
  if (name != null) {
    await tester.enterText(find.byKey(mealNameFieldKey), name);
  }
  if (kcal != null) {
    await tester.enterText(find.byKey(mealKcalFieldKey), kcal);
  }
  if (note != null) {
    await tester.enterText(find.byKey(mealNoteFieldKey), note);
  }
  await tester.pump();
}

Future<void> _save(
  WidgetTester tester, {
  String label = 'Mahlzeit speichern',
}) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
}

/// The only active meal of today, read from the database.
Future<MealEntry> _theMeal(NutritionUi ui) async =>
    (await ui.mealsOn(uiToday)).single;

void main() {
  group('create', () {
    testWidgets(
      'a name alone is saved WITHOUT calories (not 0), reports after the '
      'commit, earns no XP and the undo removes it (AT14, N02)',
      (tester) async {
        final ui = await NutritionUi.create(tester, realProjection: true);
        final router = await ui.pumpRoute('/');
        unawaited(router.push('/nutrition/new'));
        await tester.pumpAndSettle();
        expect(find.text('Mahlzeit eintragen'), findsOneWidget);

        await _fill(tester, name: 'Apfel');
        await _save(tester);
        await ui.until(() => ui.feedback.events.isNotEmpty);
        await tester.pumpAndSettle();

        expect(ui.feedback.last!.message, 'Mahlzeit gespeichert');
        final meal = await _theMeal(ui);
        expect(meal.name, 'Apfel');
        expect(meal.kcal, isNull, reason: 'not given is not 0');
        expect(meal.note, isNull);
        expect(meal.occurredAtUtc, ui.harness.clock.nowUtc());
        expect(await ui.totalXp(), 0, reason: 'no XP for meals');
        expect(router.state.uri.path, '/', reason: 'back on the dashboard');

        expect(await ui.pressUndo(), UndoResult.undone);
        expect(await ui.mealsOn(uiToday), isEmpty);
      },
    );

    testWidgets('a deliberate 0 kcal is saved as 0 (AT14)', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/nutrition/new');
      await _fill(tester, name: 'Wasser mit Zitrone', kcal: '0');
      await _save(tester);
      await ui.until(() => ui.feedback.events.isNotEmpty);
      expect((await _theMeal(ui)).kcal, 0);
    });

    testWidgets('name, calories and note are stored as typed (trimmed name)', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/nutrition/new');
      await _fill(
        tester,
        name: '  Linsencurry mit Reis  ',
        kcal: '650',
        note: 'mit Kokosmilch',
      );
      await _save(tester);
      await ui.until(() => ui.feedback.events.isNotEmpty);

      final meal = await _theMeal(ui);
      expect(meal.name, 'Linsencurry mit Reis');
      expect(meal.kcal, 650);
      expect(meal.note, 'mit Kokosmilch');
    });

    testWidgets('a date and time can be chosen with the pickers', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/nutrition/new');
      await _fill(tester, name: 'Frühstück');
      await tester.tap(find.text('Zeitpunkt'));
      await tester.pumpAndSettle();
      expect(find.text('Datum der Mahlzeit'), findsOneWidget);
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Uhrzeit der Mahlzeit'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Gestern, 10:00 Uhr'), findsOneWidget);

      await _save(tester);
      await ui.until(() => ui.feedback.events.isNotEmpty);
      expect((await ui.mealsOn(uiToday.addDays(-1))).single.name, 'Frühstück');
    });
  });

  group('validation (N02, C05)', () {
    testWidgets('an empty or blank name is rejected, input kept', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/nutrition/new');
      await _fill(tester, name: '   ', kcal: '450');
      await _save(tester);

      expect(find.text('Bitte gib einen Namen ein.'), findsOneWidget);
      expect(_text(tester, mealKcalFieldKey), '450');
      expect(ui.feedback.events, isEmpty);
      expect(await ui.mealsOn(uiToday), isEmpty);
    });

    for (final (length, valid) in [(80, true), (81, false)]) {
      testWidgets(
        'a name of $length characters is ${valid ? 'saved' : 'rejected'}',
        (tester) async {
          final ui = await NutritionUi.create(tester);
          await ui.pumpRoute('/nutrition/new');
          await _fill(tester, name: 'n' * length);
          await _save(tester);
          if (valid) {
            await ui.until(() => ui.feedback.events.isNotEmpty);
            expect((await _theMeal(ui)).name, hasLength(80));
          } else {
            expect(
              find.text('Der Name darf höchstens 80 Zeichen lang sein.'),
              findsOneWidget,
            );
            expect(_text(tester, mealNameFieldKey), hasLength(81));
            expect(ui.feedback.events, isEmpty);
          }
        },
      );
    }

    for (final (kcal, valid) in [
      ('0', true),
      ('5000', true),
      ('5001', false),
      ('-1', false),
      ('450,5', false),
      ('abc', false),
    ]) {
      testWidgets('calories "$kcal" are ${valid ? 'saved' : 'rejected'}', (
        tester,
      ) async {
        final ui = await NutritionUi.create(tester);
        await ui.pumpRoute('/nutrition/new');
        await _fill(tester, name: 'Test', kcal: kcal);
        await _save(tester);
        if (valid) {
          await ui.until(() => ui.feedback.events.isNotEmpty);
          expect((await _theMeal(ui)).kcal, int.parse(kcal));
        } else {
          final expected = kcal == '5001'
              ? 'Bitte gib Kalorien zwischen 0 und 5.000 kcal ein oder lass das '
                    'Feld leer.'
              : 'Bitte gib die Kalorien als ganze Zahl ein, zum Beispiel 450, '
                    'oder lass das Feld leer.';
          expect(find.text(expected), findsOneWidget);
          expect(_text(tester, mealKcalFieldKey), kcal);
          expect(_text(tester, mealNameFieldKey), 'Test');
          expect(ui.feedback.events, isEmpty);
        }
      });
    }

    testWidgets('all field errors appear at once and are announced', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/nutrition/new');
      await _fill(tester, name: '', kcal: '5001');
      await _save(tester);

      expect(find.text('Bitte gib einen Namen ein.'), findsOneWidget);
      expect(
        find.textContaining('Bitte gib Kalorien zwischen 0 und 5.000'),
        findsOneWidget,
      );
      final announced = tester.getSemantics(
        find.bySemanticsLabel('Bitte gib einen Namen ein.').first,
      );
      expect(
        announced.flagsCollection.isLiveRegion,
        isTrue,
        reason: 'the hint is announced when it appears',
      );
    });

    testWidgets('typing clears the hint of that field', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/nutrition/new');
      await _save(tester);
      expect(find.text('Bitte gib einen Namen ein.'), findsOneWidget);
      await _fill(tester, name: 'A');
      expect(find.text('Bitte gib einen Namen ein.'), findsNothing);
    });

    testWidgets('a note is cut at 500 characters (no hidden overflow)', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/nutrition/new');
      await _fill(tester, name: 'Test', note: 'x' * 501);
      expect(_text(tester, mealNoteFieldKey), hasLength(500));
      await _save(tester);
      await ui.until(() => ui.feedback.events.isNotEmpty);
      expect((await _theMeal(ui)).note, hasLength(500));
    });
  });

  group('save safety', () {
    testWidgets('a double tap on save stores one meal (AT12)', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/nutrition/new');
      await _fill(tester, name: 'Apfel');

      await tester.tap(find.byType(PrimaryButton).last);
      await tester.tap(find.byType(PrimaryButton).last, warnIfMissed: false);
      await ui.until(() => ui.feedback.events.isNotEmpty);
      await tester.pumpAndSettle();

      expect(await ui.mealsOn(uiToday), hasLength(1));
      expect(await ui.receipts(), hasLength(1));
    });

    testWidgets(
      'a failed save keeps all input and the retry is the same command '
      '(AT27, AT12)',
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
        await ui.pumpRoute('/nutrition/new');
        await _fill(tester, name: 'Apfel', kcal: '80', note: 'Bio');

        await _save(tester);
        await ui.until(() => ui.feedback.events.isNotEmpty);

        expect(ui.feedback.last!.kind, 'error');
        expect(
          ui.feedback.last!.message,
          'Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.',
        );
        expect(_text(tester, mealNameFieldKey), 'Apfel');
        expect(_text(tester, mealKcalFieldKey), '80');
        expect(_text(tester, mealNoteFieldKey), 'Bio');
        expect(
          await ui.mealsOn(uiToday),
          isEmpty,
          reason: 'nothing was stored',
        );
        expect(await ui.totalXp(), 0);
        final failedId = ids.issued.first;

        flaky.failAfterSync = null;
        ui.feedback.last!.onRetry!();
        await ui.until(() => ui.feedback.events.last.kind == 'saved');

        expect((await _theMeal(ui)).name, 'Apfel');
        final receipts = await ui.receipts();
        expect(receipts, hasLength(1));
        expect(receipts.single.commandId, failedId);
      },
    );

    testWidgets('the keyboard keeps the save button reachable at 200 % text', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute(
        '/nutrition/new',
        size: const Size(320, 640),
        textScale: 2.0,
        viewInsets: const EdgeInsets.only(bottom: 260),
      );
      await _fill(tester, name: 'Apfel');
      final button = find.byType(PrimaryButton);
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(640 - 260 + 1));
      await tester.tap(button);
      await ui.until(() => ui.feedback.events.isNotEmpty);
      expect((await _theMeal(ui)).name, 'Apfel');
      expect(tester.takeException(), isNull);
    });
  });

  group('leaving', () {
    testWidgets('an untouched form leaves without a question', (tester) async {
      final ui = await NutritionUi.create(tester);
      final router = await ui.pumpRoute('/');
      unawaited(router.push('/nutrition/new'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsNothing);
      expect(router.state.uri.path, '/');
    });

    testWidgets(
      'typed input asks "Änderungen verwerfen?" (back and system back)',
      (tester) async {
        final ui = await NutritionUi.create(tester);
        final router = await ui.pumpRoute('/');
        unawaited(router.push('/nutrition/new'));
        await tester.pumpAndSettle();
        await _fill(tester, name: 'Apfel');

        await tester.tap(find.bySemanticsLabel('Zurück'));
        await tester.pumpAndSettle();
        expect(find.text('Änderungen verwerfen?'), findsOneWidget);
        await tester.tap(find.text('Weiter bearbeiten'));
        await tester.pumpAndSettle();
        expect(_text(tester, mealNameFieldKey), 'Apfel');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Änderungen verwerfen?'), findsOneWidget);
        await tester.tap(find.text('Verwerfen'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/');
        expect(await ui.mealsOn(uiToday), isEmpty);
      },
    );
  });

  group('edit and delete', () {
    testWidgets(
      'shows the stored values, save stays off until changed, then saves with '
      'undo (AT23)',
      (tester) async {
        final ui = await NutritionUi.create(tester);
        final meal = await ui.addMeal('Apfel', kcal: 80, note: 'Bio');
        await ui.pumpRoute('/nutrition/${meal.id}');

        expect(find.text('Mahlzeit bearbeiten'), findsOneWidget);
        expect(_text(tester, mealNameFieldKey), 'Apfel');
        expect(_text(tester, mealKcalFieldKey), '80');
        expect(_text(tester, mealNoteFieldKey), 'Bio');
        expect(
          tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
          isNull,
          reason: 'nothing changed yet',
        );

        await _fill(tester, name: 'Birne', kcal: '');
        await _save(tester, label: 'Änderungen speichern');
        await ui.until(() => ui.feedback.events.isNotEmpty);

        expect(ui.feedback.last!.message, 'Mahlzeit aktualisiert');
        final changed = await _theMeal(ui);
        expect(changed.name, 'Birne');
        expect(changed.kcal, isNull, reason: 'cleared means not given');

        expect(await ui.pressUndo(), UndoResult.undone);
        final back = await _theMeal(ui);
        expect(back.name, 'Apfel');
        expect(back.kcal, 80);
      },
    );

    testWidgets('a calorie value can be cleared and set to a deliberate 0', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      final meal = await ui.addMeal('Tee', kcal: 40);
      await ui.pumpRoute('/nutrition/${meal.id}');
      await _fill(tester, kcal: '0');
      await _save(tester, label: 'Änderungen speichern');
      await ui.until(() => ui.feedback.events.isNotEmpty);
      expect((await _theMeal(ui)).kcal, 0);
    });

    testWidgets(
      'delete asks first, reports after the commit and the undo restores the '
      'same meal (AT23)',
      (tester) async {
        final ui = await NutritionUi.create(tester);
        final meal = await ui.addMeal('Apfel', kcal: 80);
        await ui.pumpRoute('/nutrition/${meal.id}');

        await tester.ensureVisible(find.text('Mahlzeit löschen'));
        await tester.tap(find.text('Mahlzeit löschen'));
        await tester.pumpAndSettle();
        expect(find.text('Mahlzeit „Apfel“ löschen?'), findsOneWidget);
        await tester.tap(find.text('Abbrechen'));
        await tester.pumpAndSettle();
        expect(ui.feedback.events, isEmpty);

        await tester.tap(find.text('Mahlzeit löschen'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(SecondaryButton, 'Löschen'));
        await ui.until(() => ui.feedback.events.isNotEmpty);
        await tester.pumpAndSettle();

        expect(ui.feedback.last!.message, 'Mahlzeit gelöscht');
        expect(await ui.mealsOn(uiToday), isEmpty);

        await ui.pressUndo();
        final back = await tester.runAsync(() => ui.meals.findById(meal.id));
        expect(back, isNotNull);
        expect(back!.kcal, 80);
      },
    );

    testWidgets('a meal that does not exist offers the way back', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      final router = await ui.pumpRoute('/nutrition/does-not-exist');
      expect(find.text('Mahlzeit nicht gefunden'), findsOneWidget);
      await tester.tap(find.text('Zur Übersicht'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/nutrition');
    });

    testWidgets('a load error offers a retry', (tester) async {
      var attempts = 0;
      final ui = await NutritionUi.create(
        tester,
        overrides: [
          mealEntryProvider.overrideWith((ref, id) {
            attempts++;
            if (attempts == 1) {
              return Stream<MealEntry?>.error(StateError('db'));
            }
            return ref.watch(mealRepositoryProvider).watchById(id);
          }),
        ],
      );
      final meal = await ui.addMeal('Apfel', kcal: 80);
      await ui.pumpRoute('/nutrition/${meal.id}');
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await ui.until(() => find.byKey(mealNameFieldKey).evaluate().isNotEmpty);
      expect(_text(tester, mealNameFieldKey), 'Apfel');
    });
  });
}
