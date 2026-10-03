import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/domain/meal_summary.dart';

import 'support/nutrition_ui_kit.dart';

void main() {
  group('today', () {
    testWidgets('counts the meals, sums the KNOWN calories and says "Kalorien '
        'unvollständig" for a missing value (AT14, N02)', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.addMeal(
        'Haferflocken mit Beeren',
        kcal: 420,
        ago: const Duration(hours: 1, minutes: 50),
      );
      await ui.addMeal(
        'Linsencurry mit Reis',
        kcal: 650,
        ago: const Duration(hours: 1),
      );
      await ui.addMeal('Apfel', ago: const Duration(minutes: 20));
      await ui.pumpRoute('/nutrition');

      expect(find.text('Ernährung'), findsOneWidget);
      expect(find.text('3 Mahlzeiten'), findsOneWidget);
      expect(richText('1.070 kcal bekannt'), findsOneWidget);
      expect(
        find.text('Kalorien unvollständig: 1 Mahlzeit ohne Kalorienangabe'),
        findsOneWidget,
      );
      expect(find.text('420 kcal'), findsOneWidget);
      expect(find.text('650 kcal'), findsOneWidget);
      expect(find.text('Keine Angabe'), findsOneWidget);
      expect(find.text('0 kcal'), findsNothing, reason: 'no invented zero');
      expect(
        find.text(
          'Kalorien sind freiwillig. Ohne Angabe wird nichts geschätzt.',
        ),
        findsOneWidget,
      );
      // Newest meal first.
      final apfel = tester.getTopLeft(find.text('Apfel')).dy;
      final curry = tester.getTopLeft(find.text('Linsencurry mit Reis')).dy;
      expect(apfel, lessThan(curry));
    });

    testWidgets('only missing calories show no calorie figure at all (AT14)', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.addMeal('Apfel', ago: const Duration(hours: 1));
      await ui.addMeal('Brot');
      await ui.pumpRoute('/nutrition');

      expect(find.text('Keine Kalorien angegeben'), findsOneWidget);
      expect(
        find.text('Kalorien unvollständig: 2 Mahlzeiten ohne Kalorienangabe'),
        findsOneWidget,
      );
      expect(find.textContaining('kcal bekannt'), findsNothing);
      expect(find.text('0 kcal'), findsNothing);
      expect(find.text('Keine Angabe'), findsNWidgets(2));
    });

    testWidgets(
      'complete calories show no hint, a deliberate 0 counts (AT14)',
      (tester) async {
        final ui = await NutritionUi.create(tester);
        await ui.addMeal(
          'Wasser mit Zitrone',
          kcal: 0,
          ago: const Duration(hours: 1),
        );
        await ui.addMeal('Apfel', kcal: 80);
        await ui.pumpRoute('/nutrition');

        expect(richText('80 kcal bekannt'), findsOneWidget);
        expect(find.text('0 kcal'), findsOneWidget, reason: 'the zero is real');
        expect(find.textContaining('unvollständig'), findsNothing);
        expect(find.text('Keine Angabe'), findsNothing);
      },
    );

    testWidgets('there is no rating, no calorie goal and no XP (N02)', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester, realProjection: true);
      await ui.addMeal('Apfel', kcal: 80);
      await ui.pumpRoute('/nutrition');
      expect(find.textContaining('Ziel'), findsNothing);
      expect(find.textContaining('XP'), findsNothing);
      expect(await ui.totalXp(), 0);
    });

    testWidgets('a day without a meal says so and offers the form', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.addMeal('Apfel', kcal: 80, ago: const Duration(days: 1));
      final router = await ui.pumpRoute('/nutrition');

      expect(find.text('Heute noch keine Mahlzeit'), findsOneWidget);
      expect(find.text('Noch keine Mahlzeit'), findsOneWidget);
      await tester.tap(find.text('Mahlzeit eintragen'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/nutrition/new');
    });
  });

  group('earlier days', () {
    testWidgets('are listed with their own summary and open for editing', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.addMeal('Apfel', kcal: 80, ago: const Duration(hours: 1));
      final pasta = await ui.addMeal(
        'Pasta',
        kcal: 700,
        ago: const Duration(days: 1, hours: 2),
      );
      await ui.addMeal('Salat', ago: const Duration(days: 1, hours: 3));
      await ui.pumpRoute('/nutrition');

      await ui.reveal(find.text('Gestern'));
      expect(
        find.text('2 Mahlzeiten · 700 kcal · Kalorien unvollständig'),
        findsOneWidget,
      );
      await ui.reveal(find.text('Pasta'));
      await tester.tap(find.text('Pasta'));
      await tester.pumpAndSettle();
      expect(find.text('Mahlzeit bearbeiten'), findsOneWidget);
      expect(find.text(pasta.name), findsWidgets);
    });

    testWidgets('older days can be revealed, then the end is announced', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.addMeal('Suppe', kcal: 200, ago: const Duration(days: 25));
      await ui.addMeal('Apfel', kcal: 80, ago: const Duration(hours: 1));
      await ui.pumpRoute('/nutrition');
      expect(find.text('Suppe'), findsNothing);

      await ui.reveal(find.text('Ältere Tage anzeigen'));
      await tester.tap(find.text('Ältere Tage anzeigen'));
      await ui.settle();
      await ui.reveal(find.text('Suppe'));

      await ui.reveal(find.text('Ältere Tage anzeigen'));
      await tester.tap(find.text('Ältere Tage anzeigen'));
      await ui.settle();
      await ui.reveal(find.text('Keine älteren Einträge.'));
      expect(find.text('Ältere Tage anzeigen'), findsNothing);
    });
  });

  group('states', () {
    testWidgets('nothing at all shows the first-use state with its action', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      final router = await ui.pumpRoute('/nutrition');

      expect(find.text('Noch keine Mahlzeit'), findsOneWidget);
      expect(find.text('Mahlzeit eintragen'), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
      // No demo entries anywhere.
      expect(find.textContaining('kcal'), findsNothing);
      await tester.tap(find.text('Mahlzeit eintragen'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/nutrition/new');
    });

    testWidgets('shows a short loading text while the data is read', (
      tester,
    ) async {
      final ui = await NutritionUi.create(
        tester,
        overrides: [
          mealsTodayProvider.overrideWith(
            (ref) => Stream<MealDay>.multi((controller) {}),
          ),
        ],
      );
      await ui.pumpRoute('/nutrition');
      expect(find.text('Wird geladen …'), findsOneWidget);
    });

    testWidgets('a load error offers a retry that reads again', (tester) async {
      var attempts = 0;
      final ui = await NutritionUi.create(
        tester,
        overrides: [
          mealsTodayProvider.overrideWith((ref) {
            attempts++;
            if (attempts == 1) {
              return Stream<MealDay>.error(StateError('db'));
            }
            return ref
                .watch(mealRepositoryProvider)
                .watchDay(ref.watch(todayProvider));
          }),
        ],
      );
      await ui.pumpRoute('/nutrition');
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);

      await tester.tap(find.text('Erneut versuchen'));
      await ui.until(
        () => find.text('Noch keine Mahlzeit').evaluate().isNotEmpty,
        reason: 'data after the retry',
      );
    });
  });

  group('row actions', () {
    testWidgets('tapping a meal opens it for editing', (tester) async {
      final ui = await NutritionUi.create(tester);
      final meal = await ui.addMeal('Apfel', kcal: 80);
      final router = await ui.pumpRoute('/nutrition');
      await tester.tap(find.text('Apfel'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/nutrition/${meal.id}');
    });

    testWidgets('the menu offers edit and delete with its own close button', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      final meal = await ui.addMeal('Apfel', kcal: 80);
      final router = await ui.pumpRoute('/nutrition');

      await tester.tap(iconButtonLabelled('Aktionen für Apfel'));
      await tester.pumpAndSettle();
      expect(find.text('Bearbeiten'), findsOneWidget);
      expect(find.text('Löschen'), findsOneWidget);

      await tester.tap(iconButtonLabelled('Schließen'));
      await tester.pumpAndSettle();
      expect(find.text('Bearbeiten'), findsNothing);

      await tester.tap(iconButtonLabelled('Aktionen für Apfel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bearbeiten'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/nutrition/${meal.id}');
    });

    testWidgets(
      'delete through the menu asks first, reports after the commit and the '
      'undo restores the same meal (AT23)',
      (tester) async {
        final ui = await NutritionUi.create(tester);
        final meal = await ui.addMeal('Apfel', kcal: 80);
        await ui.pumpRoute('/nutrition');

        await tester.tap(iconButtonLabelled('Aktionen für Apfel'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Löschen'));
        await tester.pumpAndSettle();
        expect(find.text('Mahlzeit „Apfel“ löschen?'), findsOneWidget);

        await tester.tap(find.text('Abbrechen'));
        await tester.pumpAndSettle();
        expect(ui.feedback.events, isEmpty);
        expect(find.text('Apfel'), findsOneWidget);

        await tester.tap(iconButtonLabelled('Aktionen für Apfel'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Löschen'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(SecondaryButton, 'Löschen'));
        await ui.until(() => ui.feedback.events.isNotEmpty);

        expect(ui.feedback.last!.message, 'Mahlzeit gelöscht');
        await tester.pumpAndSettle();
        expect(find.text('Apfel'), findsNothing);
        expect(find.text('Noch keine Mahlzeit'), findsOneWidget);

        expect(await ui.pressUndo(), UndoResult.undone);
        final back = await tester.runAsync(() => ui.meals.findById(meal.id));
        expect(back, isNotNull, reason: 'the SAME id is restored');
        expect(find.text('Apfel'), findsOneWidget);
      },
    );

    testWidgets('a failed delete leaves the meal and offers a retry', (
      tester,
    ) async {
      late FlakyProjection flaky;
      final ui = await NutritionUi.create(
        tester,
        projection: (h) => flaky = FlakyProjection(h.projections),
      );
      await ui.addMeal('Apfel', kcal: 80);
      await ui.pumpRoute('/nutrition');

      flaky.failAfterSync = StateError('disk full');
      await tester.tap(iconButtonLabelled('Aktionen für Apfel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SecondaryButton, 'Löschen'));
      await ui.until(() => ui.feedback.events.isNotEmpty);

      expect(ui.feedback.last!.kind, 'error');
      expect(
        ui.feedback.last!.message,
        'Löschen fehlgeschlagen. Die Mahlzeit ist unverändert.',
      );
      expect(find.text('Apfel'), findsOneWidget);
      flaky.failAfterSync = null;
      ui.feedback.last!.onRetry!();
      await ui.until(() => ui.feedback.events.last.kind == 'saved');
      await tester.pumpAndSettle();
      expect(find.text('Apfel'), findsNothing);
    });
  });
}
