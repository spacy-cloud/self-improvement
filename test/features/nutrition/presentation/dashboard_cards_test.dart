import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/meal_summary.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';

import 'support/nutrition_ui_kit.dart';

Finder _pill(String text) => find.widgetWithText(MetricCardAction, text);

void main() {
  group('water card', () {
    testWidgets(
      'shows the real total, the target, the bar and the percentage (N01)',
      (tester) async {
        final ui = await NutritionUi.create(tester);
        await ui.addWater(1000, ago: const Duration(hours: 2));
        await ui.addWater(500, ago: const Duration(hours: 1));
        await ui.pumpRoute('/');

        expect(find.text('Wasser'), findsOneWidget);
        expect(richText('1,5 / 2,5 l'), findsOneWidget);
        expect(find.text('60 % erreicht'), findsOneWidget);
        expect(
          tester.widget<AppProgressBar>(find.byType(AppProgressBar)).value,
          closeTo(0.6, 1e-9),
        );
        expect(
          find.bySemanticsLabel(
            'Wasser heute: 1,5 l von 2,5 l, 60 Prozent erreicht.',
          ),
          findsWidgets,
        );
      },
    );

    testWidgets(
      '+250 ml is ONE operation from the dashboard to the commit, it does not '
      'open the water screen and the undo takes amount and XP back (AT10)',
      (tester) async {
        final ui = await NutritionUi.create(tester, realProjection: true);
        final router = await ui.pumpRoute('/');

        await tester.tap(_pill('250 ml'));
        await ui.until(() => ui.feedback.events.isNotEmpty);

        expect(ui.feedback.last!.kind, 'saved');
        expect(ui.feedback.last!.message, '250 ml hinzugefügt');
        expect(router.state.uri.path, '/', reason: 'the detail stays closed');
        expect(await ui.waterTotalMl(), 250);
        expect(await ui.totalXp(), 5);
        expect(richText('0,25 / 2,5 l'), findsOneWidget);
        expect(find.text('10 % erreicht'), findsOneWidget);

        expect(await ui.pressUndo(), UndoResult.undone);
        expect(await ui.waterTotalMl(), 0);
        expect(await ui.totalXp(), 0);
        expect(richText('0 / 2,5 l'), findsOneWidget);
      },
    );

    testWidgets('+500 ml adds the second amount', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/');
      await tester.tap(_pill('500 ml'));
      await ui.until(() => ui.feedback.events.isNotEmpty);
      expect(ui.feedback.last!.message, '500 ml hinzugefügt');
      expect(await ui.waterTotalMl(), 500);
    });

    testWidgets('independent taps are separate entries (AT12, N01)', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/');
      await tester.tap(_pill('250 ml'));
      await tester.tap(_pill('250 ml'));
      await tester.tap(_pill('500 ml'));
      await ui.until(() => ui.feedback.events.length == 3);
      expect(await ui.waterCount(), 3);
      expect(await ui.waterTotalMl(), 1000);
      expect(
        (await ui.receipts()).map((r) => r.commandId).toSet(),
        hasLength(3),
      );
    });

    testWidgets('tapping the card body opens the water screen', (tester) async {
      final ui = await NutritionUi.create(tester);
      final router = await ui.pumpRoute('/');
      await tester.tap(find.text('Wasser'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/water');
      expect(find.text('Wasser eintragen'), findsOneWidget);
    });

    testWidgets(
      'a failed quick add stores nothing, the card says so and the retry is '
      'the same command (AT27, AT12)',
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
        await ui.pumpRoute('/');

        await tester.tap(_pill('250 ml'));
        await ui.until(() => ui.feedback.events.isNotEmpty);

        expect(ui.feedback.last!.kind, 'error');
        expect(
          find.text('Speichern fehlgeschlagen. Es wurde nichts hinzugefügt.'),
          findsOneWidget,
        );
        expect(await ui.waterCount(), 0);
        expect(await ui.totalXp(), 0);
        expect(richText('0 / 2,5 l'), findsOneWidget);
        final failedId = ids.issued.first;

        flaky.failAfterSync = null;
        await tester.tap(find.text('Erneut versuchen'));
        await ui.until(() => ui.feedback.events.last.kind == 'saved');

        expect(await ui.waterCount(), 1);
        expect((await ui.receipts()).single.commandId, failedId);
        expect(find.text('Erneut versuchen'), findsNothing);
      },
    );

    testWidgets('an empty day shows 0 and says nothing was entered', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/');
      expect(richText('0 / 2,5 l'), findsOneWidget);
      expect(find.text('Noch nichts eingetragen'), findsOneWidget);
    });

    testWidgets(
      'above the goal the bar is full while the real percentage stays '
      'visible (N01)',
      (tester) async {
        final ui = await NutritionUi.create(tester);
        await ui.addWater(1500, ago: const Duration(hours: 2));
        await ui.addWater(1300, ago: const Duration(hours: 1));
        await ui.pumpRoute('/');

        expect(
          tester.widget<AppProgressBar>(find.byType(AppProgressBar)).value,
          1.0,
        );
        expect(richText('2,8 / 2,5 l'), findsOneWidget);
        expect(find.text('Tagesziel erreicht · 112 %'), findsOneWidget);
      },
    );

    testWidgets('without a goal there is no bar, only the real total', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.addWater(750, ago: const Duration(hours: 1));
      await tester.runAsync(() async {
        await ui.database.customStatement(
          "UPDATE goal_versions SET enabled = 0 WHERE goal_type = 'water'",
        );
      });
      await ui.pumpRoute('/');
      await tester.pumpAndSettle();
      expect(find.byType(AppProgressBar), findsNothing);
      expect(find.text('Kein Tagesziel aktiv'), findsOneWidget);
      expect(richText('0,75 l'), findsOneWidget);
    });

    testWidgets('loading shows a dash, a load error offers a retry', (
      tester,
    ) async {
      var attempts = 0;
      final ui = await NutritionUi.create(
        tester,
        overrides: [
          waterTodayProvider.overrideWith((ref) {
            attempts++;
            if (attempts == 1) {
              return Stream<WaterToday>.error(StateError('db'));
            }
            return ref
                .watch(waterRepositoryProvider)
                .watchToday(ref.watch(todayProvider));
          }),
        ],
      );
      await ui.pumpRoute('/');
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await ui.until(() => richText('0 / 2,5 l').evaluate().isNotEmpty);
    });
  });

  group('nutrition card', () {
    testWidgets('without a meal it shows no number and the way to add one', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      final router = await ui.pumpRoute('/');
      expect(find.text('Ernährung'), findsOneWidget);
      expect(find.text('Noch keine Mahlzeit'), findsOneWidget);
      expect(find.text('–'), findsOneWidget);

      await tester.tap(_pill('Mahlzeit eintragen'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/nutrition/new');
    });

    testWidgets(
      'counts the meals and sums the known calories; missing ones say '
      '"Kalorien unvollständig" (AT14)',
      (tester) async {
        final ui = await NutritionUi.create(tester);
        await ui.addMeal(
          'Haferflocken',
          kcal: 420,
          ago: const Duration(hours: 2),
        );
        await ui.addMeal(
          'Linsencurry',
          kcal: 650,
          ago: const Duration(hours: 1),
        );
        await ui.addMeal('Apfel');
        await ui.pumpRoute('/');

        expect(richText('3 Mahlzeiten'), findsOneWidget);
        expect(
          find.text('1.070 kcal bekannt · Kalorien unvollständig'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            'Ernährung heute: 3 Mahlzeiten, 1.070 Kilokalorien bekannt, '
            'Kalorien unvollständig',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('only missing calories make no calorie claim at all (AT14)', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.addMeal('Apfel', ago: const Duration(hours: 1));
      await ui.addMeal('Brot');
      await ui.pumpRoute('/');

      expect(find.text('Kalorien unvollständig'), findsOneWidget);
      expect(find.textContaining('kcal'), findsNothing);
      expect(find.textContaining('0 kcal'), findsNothing);
    });

    testWidgets('complete calories show no hint; a deliberate 0 is a value', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.addMeal('Wasser mit Zitrone', kcal: 0);
      await ui.pumpRoute('/');

      expect(find.text('0 kcal bekannt'), findsOneWidget);
      expect(find.textContaining('unvollständig'), findsNothing);
      expect(richText('1 Mahlzeit'), findsOneWidget);
    });

    testWidgets('the card body opens the overview', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.addMeal('Apfel', kcal: 80);
      final router = await ui.pumpRoute('/');
      await tester.tap(find.text('Ernährung'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/nutrition');
    });

    testWidgets('a load error offers a retry', (tester) async {
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
      await ui.pumpRoute('/');
      expect(find.text('Daten konnten nicht geladen werden'), findsWidgets);
      await tester.tap(find.text('Erneut versuchen').last);
      await ui.until(
        () => find.text('Noch keine Mahlzeit').evaluate().isNotEmpty,
      );
    });
  });

  group('both cards in the dashboard grid', () {
    for (final size in responsiveSizes) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${size.width.toInt()} px at ${scale * 100} % text', (
          tester,
        ) async {
          final ui = await NutritionUi.create(tester);
          await ui.addWater(1500, ago: const Duration(hours: 1));
          await ui.addMeal('Haferflocken mit Beeren', kcal: 420);
          await ui.addMeal('Apfel', ago: const Duration(hours: 1));
          await ui.pumpRoute('/', size: size, textScale: scale);
          expect(tester.takeException(), isNull);
          expect(find.text('Wasser'), findsOneWidget);
          expect(find.text('Ernährung'), findsOneWidget);
        });
      }
    }
  });
}
