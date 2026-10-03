import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';

import 'support/nutrition_ui_kit.dart';

void main() {
  group('data states', () {
    testSemantics(
      'shows the real total, the target, the progress and the entries newest '
      'first (N01)',
      (tester) async {
        final ui = await NutritionUi.create(tester);
        await ui.addWater(250, ago: const Duration(hours: 1, minutes: 50));
        await ui.addWater(500, ago: const Duration(minutes: 45));
        await ui.pumpRoute('/water');

        expect(find.text('Wasser eintragen'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            'Wasser heute: 0,75 l von 2,5 l, 30 Prozent erreicht.',
          ),
          findsOneWidget,
        );
        expect(richText('0,75 / 2,5 l'), findsOneWidget);
        expect(find.text('30 %'), findsOneWidget);
        expect(find.text('Noch 1,75 l bis zum Ziel'), findsOneWidget);
        expect(find.text('2 Einträge'), findsOneWidget);
        expect(find.text('250 ml'), findsWidgets);
        expect(find.text('500 ml'), findsWidgets);
        final newer = tester.getTopLeft(find.text('09:15 Uhr')).dy;
        final older = tester.getTopLeft(find.text('08:10 Uhr')).dy;
        expect(newer, lessThan(older), reason: 'newest entry first');
      },
    );

    testWidgets('an empty day shows 0, the full target and no entries (N01)', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');

      expect(richText('0 / 2,5 l'), findsOneWidget);
      expect(find.text('Noch 2,5 l bis zum Ziel'), findsOneWidget);
      expect(find.text('Noch nichts getrunken'), findsOneWidget);
      expect(find.text('0 Einträge'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'the ring stays at 100 % while the real amount and percentage stay '
      'visible (N01)',
      (tester) async {
        final ui = await NutritionUi.create(tester);
        await ui.addWater(1500, ago: const Duration(hours: 2));
        await ui.addWater(1300, ago: const Duration(hours: 1));
        await ui.pumpRoute('/water');

        final ring = tester.widget<ProgressRing>(find.byType(ProgressRing));
        expect(ring.value, 1.0, reason: 'the ring is capped at 100 %');
        expect(find.text('112 %'), findsOneWidget);
        expect(richText('2,8 / 2,5 l'), findsOneWidget);
        expect(find.text('Tagesziel erreicht'), findsOneWidget);
        expect(find.text('Noch 0 l bis zum Ziel'), findsNothing);
        expect(
          await ui.waterCount(),
          2,
          reason: 'no extra record for the goal',
        );
      },
    );

    testWidgets('without a goal only the real total is shown', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.addWater(750, ago: const Duration(hours: 1));
      await tester.runAsync(() async {
        await ui.harness.database.customStatement(
          'UPDATE goal_versions SET enabled = 0 '
          "WHERE goal_type = 'water'",
        );
      });
      await ui.pumpRoute('/water');
      await tester.pumpAndSettle();

      expect(find.text('Kein Tagesziel aktiv'), findsWidgets);
      expect(richText('0,75 l'), findsOneWidget);
      expect(tester.widget<ProgressRing>(find.byType(ProgressRing)).value, 0);
    });

    testWidgets('earlier days follow with their own total and entries (AT23)', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.addWater(250, ago: const Duration(hours: 1));
      await ui.addWater(2000, ago: const Duration(days: 1));
      await ui.addWater(750, ago: const Duration(days: 1, hours: 2));
      await ui.addWater(500, ago: const Duration(days: 3));
      await ui.pumpRoute('/water');

      await ui.reveal(find.text('Gestern'));
      expect(find.text('Gestern'), findsOneWidget);
      expect(
        find.text('2,75 l von 2,5 l · 2 Einträge · Ziel erreicht'),
        findsOneWidget,
      );
      await ui.reveal(find.text('0,5 l von 2,5 l · 1 Eintrag'));
      expect(find.text('0,5 l von 2,5 l · 1 Eintrag'), findsOneWidget);
      expect(find.text('2.000 ml'), findsOneWidget);
    });

    testWidgets('older days can be revealed, then the end is announced', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.addWater(400, ago: const Duration(days: 20));
      await ui.pumpRoute('/water');
      expect(find.text('400 ml'), findsNothing);

      await ui.reveal(find.text('Ältere Tage anzeigen'));
      await tester.tap(find.text('Ältere Tage anzeigen'));
      await ui.settle();
      await ui.reveal(find.text('400 ml'));
      expect(find.text('400 ml'), findsOneWidget);

      await ui.reveal(find.text('Ältere Tage anzeigen'));
      await tester.tap(find.text('Ältere Tage anzeigen'));
      await ui.settle();
      await ui.reveal(find.text('Keine älteren Einträge.'));
      expect(find.text('Ältere Tage anzeigen'), findsNothing);
    });
  });

  group('loading and errors', () {
    testWidgets('shows a short loading text while the data is read', (
      tester,
    ) async {
      final ui = await NutritionUi.create(
        tester,
        overrides: [
          waterTodayProvider.overrideWith(
            (ref) => Stream<WaterToday>.multi((controller) {}),
          ),
        ],
      );
      await ui.pumpRoute('/water');
      expect(find.text('Wird geladen …'), findsOneWidget);
    });

    testWidgets('a load error offers a retry that reads again', (tester) async {
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
      await ui.pumpRoute('/water');
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);

      await tester.tap(find.text('Erneut versuchen'));
      await ui.until(
        () => find.text('Schnell hinzufügen').evaluate().isNotEmpty,
        reason: 'data after the retry',
      );
      expect(find.text('Daten konnten nicht geladen werden'), findsNothing);
    });
  });

  group('quick add', () {
    testWidgets(
      '250 ml saves a real entry, reports after the commit and the undo '
      'removes exactly it (AT10, G01)',
      (tester) async {
        final ui = await NutritionUi.create(tester, realProjection: true);
        await ui.pumpRoute('/water');

        await tester.tap(find.text('Glas'));
        await ui.until(() => ui.feedback.events.isNotEmpty);

        expect(ui.feedback.last!.kind, 'saved');
        expect(ui.feedback.last!.message, '250 ml hinzugefügt');
        expect(ui.feedback.last!.undo, isNotNull);
        expect(await ui.waterTotalMl(), 250);
        expect(await ui.totalXp(), 5);
        expect(find.text('250 ml'), findsWidgets);
        expect(find.text('1 Eintrag'), findsOneWidget);

        expect(await ui.pressUndo(), UndoResult.undone);
        expect(await ui.waterTotalMl(), 0);
        expect(await ui.totalXp(), 0);
        expect(find.text('Noch nichts getrunken'), findsOneWidget);
      },
    );

    testWidgets('500 ml adds the second amount (AT10)', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await tester.tap(find.text('Flasche'));
      await ui.until(() => ui.feedback.events.isNotEmpty);
      expect(ui.feedback.last!.message, '500 ml hinzugefügt');
      expect(await ui.waterTotalMl(), 500);
    });

    testWidgets(
      'two independent taps are two entries with two command ids (AT12, N01)',
      (tester) async {
        final ui = await NutritionUi.create(tester);
        await ui.pumpRoute('/water');

        await tester.tap(find.text('Glas'));
        await tester.tap(find.text('Glas'));
        await ui.until(() => ui.feedback.events.length == 2);

        expect(await ui.waterCount(), 2);
        expect(await ui.waterTotalMl(), 500);
        final ids = (await ui.receipts()).map((r) => r.commandId).toSet();
        expect(ids, hasLength(2), reason: 'every tap is its own command');
      },
    );

    testWidgets(
      'a failed quick add stores nothing and keeps the retry with the SAME '
      'command id (AT27, AT12)',
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

        await tester.tap(find.text('Glas'));
        await ui.until(() => ui.feedback.events.isNotEmpty);

        expect(ui.feedback.last!.kind, 'error');
        expect(
          ui.feedback.last!.message,
          'Speichern fehlgeschlagen. Es wurde nichts hinzugefügt.',
        );
        expect(ui.feedback.last!.onRetry, isNotNull);
        expect(await ui.waterCount(), 0, reason: 'no amount was stored');
        expect(await ui.totalXp(), 0, reason: 'no XP was granted');
        expect(find.text('Noch nichts getrunken'), findsOneWidget);
        final failedId = ids.issued.first;

        flaky.failAfterSync = null;
        await tester.tap(find.text('Erneut versuchen'));
        await ui.until(() => ui.feedback.events.last.kind == 'saved');

        expect(await ui.waterCount(), 1, reason: 'the retry is one entry');
        expect(await ui.totalXp(), 5);
        final receipts = await ui.receipts();
        expect(receipts, hasLength(1));
        expect(receipts.single.commandId, failedId);
        expect(find.text('Erneut versuchen'), findsNothing);
      },
    );

    testWidgets('the failure notice can be dismissed', (tester) async {
      late FlakyProjection flaky;
      final ui = await NutritionUi.create(
        tester,
        projection: (h) => flaky = FlakyProjection(h.projections),
      );
      flaky.failAfterSync = StateError('disk full');
      await ui.pumpRoute('/water');
      await tester.tap(find.text('Flasche'));
      await ui.until(() => ui.feedback.events.isNotEmpty);
      expect(find.text('Schließen'), findsOneWidget);

      await tester.tap(find.text('Schließen'));
      await tester.pump();
      expect(find.text('Erneut versuchen'), findsNothing);
      expect(await ui.waterCount(), 0);
    });

    testWidgets('five quick adds of 250 ml earn at most 20 XP (AT11, G01)', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester, realProjection: true);
      await ui.pumpRoute('/water');
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Glas'));
        await ui.until(() => ui.feedback.events.length == i + 1);
      }
      expect(await ui.waterTotalMl(), 1250);
      expect(await ui.totalXp(), 20);
    });
  });

  group('delete and edit', () {
    testWidgets(
      'delete asks first, reports after the commit and the undo restores the '
      'same entry (AT10, AT27)',
      (tester) async {
        final ui = await NutritionUi.create(tester, realProjection: true);
        final entry = await ui.addWater(
          500,
          ago: const Duration(hours: 1, minutes: 50),
        );
        await ui.pumpRoute('/water');
        expect(await ui.totalXp(), 5);

        await tester.tap(iconButtonLabelled('08:10 Uhr, 500 ml, löschen'));
        await tester.pumpAndSettle();
        expect(find.text('Eintrag von 08:10 Uhr löschen?'), findsOneWidget);

        await tester.tap(find.text('Abbrechen'));
        await tester.pumpAndSettle();
        expect(await ui.waterCount(), 1, reason: 'cancel changes nothing');
        expect(ui.feedback.events, isEmpty);

        await tester.tap(iconButtonLabelled('08:10 Uhr, 500 ml, löschen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Löschen'));
        await ui.until(() => ui.feedback.events.isNotEmpty);

        expect(ui.feedback.last!.message, 'Eintrag gelöscht');
        expect(await ui.waterCount(), 0);
        expect(await ui.totalXp(), 0, reason: 'the XP follows the entry');
        expect(find.text('Noch nichts getrunken'), findsOneWidget);

        expect(await ui.pressUndo(), UndoResult.undone);
        final back = await tester.runAsync(() => ui.water.findById(entry.id));
        expect(back, isNotNull, reason: 'the SAME id is restored');
        expect(await ui.waterTotalMl(), 500);
        expect(await ui.totalXp(), 5);
        expect(find.text('08:10 Uhr'), findsOneWidget);
      },
    );

    testWidgets('a failed delete leaves the entry and offers a retry', (
      tester,
    ) async {
      late FlakyProjection flaky;
      final ui = await NutritionUi.create(
        tester,
        projection: (h) => flaky = FlakyProjection(h.projections),
      );
      await ui.addWater(250, ago: const Duration(hours: 1));
      await ui.pumpRoute('/water');

      flaky.failAfterSync = StateError('disk full');
      await tester.tap(iconButtonLabelled('löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen'));
      await ui.until(() => ui.feedback.events.isNotEmpty);

      expect(ui.feedback.last!.kind, 'error');
      expect(
        ui.feedback.last!.message,
        'Löschen fehlgeschlagen. Der Eintrag ist unverändert.',
      );
      expect(await ui.waterCount(), 1);

      flaky.failAfterSync = null;
      ui.feedback.last!.onRetry!();
      await ui.until(() => ui.feedback.events.last.kind == 'saved');
      expect(await ui.waterCount(), 0);
      final deletes = (await ui.receipts()).where(
        (r) => r.commandType.contains('delete'),
      );
      expect(deletes, hasLength(1), reason: 'the retry is the same command');
    });

    testWidgets('tapping an entry opens it for editing (AT23)', (tester) async {
      final ui = await NutritionUi.create(tester);
      final entry = await ui.addWater(
        250,
        ago: const Duration(hours: 1, minutes: 50),
      );
      final router = await ui.pumpRoute('/water');

      await tester.tap(find.text('08:10 Uhr'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/water/${entry.id}');
      expect(find.text('Eintrag bearbeiten'), findsOneWidget);
    });
  });

  group('same data as history and analysis (A01)', () {
    testWidgets(
      'the totals on screen are the sums the repository reads for every day '
      '(A01)',
      (tester) async {
        final ui = await NutritionUi.create(tester);
        await ui.addWater(250, ago: const Duration(hours: 1));
        await ui.addWater(500, ago: const Duration(hours: 2));
        await ui.addWater(1200, ago: const Duration(days: 1));
        await ui.pumpRoute('/water');

        final history = await tester.runAsync(
          () => ui.water.loadHistory(today: uiToday, days: 14),
        );
        final today = history!.daysNewestFirst.first;
        final yesterday = history.daysNewestFirst.last;
        expect(today.totalMl, 750);
        expect(richText('0,75 / 2,5 l'), findsOneWidget);
        await ui.reveal(find.textContaining('1,2 l'));
        expect(yesterday.totalMl, 1200);
        expect(find.text('1,2 l von 2,5 l · 1 Eintrag'), findsOneWidget);
      },
    );
  });

  group('daily goal', () {
    testWidgets(
      'a changed goal applies from tomorrow, today keeps its threshold '
      '(AT24)',
      (tester) async {
        final ui = await NutritionUi.create(tester, realProjection: true);
        await ui.addWater(1250, ago: const Duration(hours: 1));
        await ui.pumpRoute('/water');
        expect(
          find.text('2,5 l · Änderungen gelten ab morgen'),
          findsOneWidget,
        );

        await tester.tap(find.text('Tagesziel'));
        await tester.pumpAndSettle();
        expect(find.text('Tagesziel ändern'), findsOneWidget);
        expect(
          find.text(
            'Die Änderung gilt ab morgen. Heute zählt weiterhin 2,5 l.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('In 50-ml-Schritten · 250 bis 10.000 ml'),
          findsOneWidget,
        );

        await tester.tap(find.bySemanticsLabel('um 50 Milliliter erhöhen'));
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '2550',
        );
        await tester.tap(find.text('Tagesziel speichern'));
        await ui.until(() => ui.feedback.events.isNotEmpty);

        expect(
          ui.feedback.last!.message,
          'Tagesziel auf 2,55 l gesetzt. Es gilt ab morgen.',
        );
        await tester.pumpAndSettle();
        expect(find.text('Tagesziel ändern'), findsNothing);
        // Today still counts against 2,5 l.
        expect(richText('1,25 / 2,5 l'), findsOneWidget);
        expect(find.text('50 %'), findsOneWidget);
        expect(find.text('Heute 2,5 l, ab morgen 2,55 l'), findsOneWidget);
      },
    );

    testWidgets('typed targets are checked against 250 to 10000 in 50 steps', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await tester.tap(find.text('Tagesziel'));
      await tester.pumpAndSettle();

      Future<void> save(String text) async {
        await tester.enterText(find.byType(TextField), text);
        await tester.tap(find.text('Tagesziel speichern'));
        await tester.pump();
      }

      await save('2525');
      expect(
        find.text(
          'Das Tagesziel geht in 50-ml-Schritten, zum Beispiel 2.500 ml.',
        ),
        findsOneWidget,
      );
      await save('200');
      expect(
        find.text('Bitte gib ein Tagesziel zwischen 250 und 10.000 ml ein.'),
        findsOneWidget,
      );
      await save('10050');
      expect(
        find.text('Bitte gib ein Tagesziel zwischen 250 und 10.000 ml ein.'),
        findsOneWidget,
      );
      await save('');
      expect(
        find.text('Bitte gib dein Tagesziel in Millilitern ein.'),
        findsOneWidget,
      );
      expect(ui.feedback.events, isEmpty, reason: 'nothing was saved');
    });
  });
}
