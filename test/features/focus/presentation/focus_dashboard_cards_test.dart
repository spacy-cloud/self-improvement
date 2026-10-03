import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/focus_module.dart';

import '../../../support/pump_app.dart';
import '../support/focus_ui_kit.dart';

/// The dashboard cards `focus` and `workout` as the shell builds them.
void main() {
  Future<GoRouter> pumpCards(
    WidgetTester tester,
    FocusUi ui, {
    Size size = const Size(393, 852),
    double textScale = 1.0,
  }) async {
    final cards = const FocusModule().dashboardCards;
    final router = await pumpRouterApp(
      tester,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final card in cards)
                    Consumer(
                      builder: (context, ref, _) => card.builder(context, ref),
                    ),
                ],
              ),
            ),
          ),
        ),
        ...ui.routes.where((r) => r is GoRoute && r.path != '/'),
      ],
      initialLocation: '/',
      container: ui.container,
      size: size,
      textScale: textScale,
    );
    await tester.settleDb();
    return router;
  }

  Finder rich(String text) => find.text(text, findRichText: true);

  ProgressRing workoutRing(WidgetTester tester) =>
      tester.widget<ProgressRing>(find.byType(ProgressRing));

  group('descriptors', () {
    test(
      'two cards with the shell ids and the default order (workout, focus)',
      () {
        final cards = const FocusModule().dashboardCards;
        expect([for (final c in cards) c.cardId], ['workout', 'focus']);
        expect([for (final c in cards) c.title], ['Workout', 'Fokus']);
        expect(cards[0].defaultRank, lessThan(cards[1].defaultRank));
        expect([for (final c in cards) c.fullWidth], [false, false]);
      },
    );
  });

  group('focus card', () {
    testWidgets('without sessions: zero minutes against the daily goal', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      final router = await pumpCards(tester, ui);
      expect(find.text('Fokus'), findsOneWidget);
      expect(rich('0 / 25 Min.'), findsOneWidget);
      expect(find.text('Noch 25 Min. bis zu deinem Tagesziel'), findsOneWidget);
      expect(find.text('Fokus fortsetzen'), findsNothing);
      await tester.tap(find.text('Fokus'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/focus');
    });

    testWidgets('saved focus time counts, workouts do not (F02, F03, AT20)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await tester.completeFocus(ui, seconds: 600);
      await tester.addWorkout(ui, minutes: 90);
      await pumpCards(tester, ui);
      expect(rich('10 / 25 Min.'), findsOneWidget);
      expect(find.text('Noch 15 Min. bis zu deinem Tagesziel'), findsOneWidget);
      expect(rich('1 / 3 Trainings'), findsOneWidget);
      expect(find.text('90 Min.'), findsOneWidget);
    });

    testWidgets(
      'a running session shows its state and the way back (F01, AT16)',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.startFocus(ui);
        final router = await pumpCards(tester, ui);

        expect(find.text('Läuft'), findsOneWidget);
        expect(find.text('Lernen · Noch 25 Min.'), findsOneWidget);
        expect(find.text('Fokus fortsetzen'), findsOneWidget);
        expect(find.textContaining('/ 25 Min.'), findsNothing);
        await tester.tap(find.text('Fokus fortsetzen'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/focus/session');
        expect(
          await tester.focusRows(ui),
          hasLength(1),
          reason: 'no second one',
        );
      },
    );

    testWidgets('the card changes once a minute, not every second', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await tester.startFocus(ui);
      await pumpCards(tester, ui);
      expect(find.text('Lernen · Noch 25 Min.'), findsOneWidget);
      await tester.tick(ui, 1);
      expect(find.text('Lernen · Noch 25 Min.'), findsOneWidget);
      await tester.tick(ui, 58);
      expect(find.text('Lernen · Noch 25 Min.'), findsOneWidget);
      await tester.tick(ui, 1);
      expect(find.text('Lernen · Noch 24 Min.'), findsOneWidget);
      await tester.tick(ui, 1380); // 23 minutes later
      expect(find.text('Lernen · Noch 1 Min.'), findsOneWidget);
      expect(
        (await tester.focusRows(ui)).single.rowVersion,
        1,
        reason: 'the card never writes',
      );
    });

    testWidgets('a paused session shows the time left', (tester) async {
      final ui = await createFocusUi(tester);
      final id = await tester.startFocus(ui);
      ui.advance(600);
      await tester.runCommand(
        () => ui.focusRepository.pause(commandId: ui.ids.newId(), id: id),
      );
      await pumpCards(tester, ui);
      expect(find.text('Pausiert'), findsOneWidget);
      expect(find.text('Lernen · 15:00 übrig'), findsOneWidget);
      expect(find.text('Fokus fortsetzen'), findsOneWidget);
    });

    testWidgets(
      'the card alone turns an ended countdown into the confirmation, exactly once (AT17, F01)',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.startFocus(ui);
        await pumpCards(tester, ui);
        await tester.tick(ui, 1500);
        await tester.settleDb();

        expect(find.text('Geschafft!'), findsOneWidget);
        expect(find.text('Lernen · Bestätigung offen'), findsOneWidget);
        expect(find.text('Sitzung bestätigen'), findsOneWidget);
        expect(
          (await tester.focusRows(ui)).single.status,
          'awaiting_confirmation',
        );
        expect(
          await tester.receipts(ui, 'focus.await_confirmation'),
          hasLength(1),
        );
      },
    );

    testWidgets(
      'a session that ran out while the app was closed is shown as waiting after the restoration (AT17)',
      (tester) async {
        var ui = await createFocusUi(tester);
        await tester.startFocus(ui, category: FocusCategory.meditation);
        ui.advance(2000);
        ui = ui.restarted();
        await pumpCards(tester, ui);
        await restoreFocus(tester, ui);
        expect(find.text('Geschafft!'), findsOneWidget);
        expect(find.text('Meditation · Bestätigung offen'), findsOneWidget);
      },
    );

    testWidgets('loading and error states', (tester) async {
      final never = StreamController<FocusSession?>();
      addTearDown(never.close);
      final loading = await createFocusUi(
        tester,
        overrides: [focusSessionProvider.overrideWith((ref) => never.stream)],
      );
      await pumpCards(tester, loading);
      expect(find.text('Fokus'), findsOneWidget);
      expect(find.text('–'), findsWidgets);

      await closeApp(tester);
      var attempts = 0;
      final failing = await createFocusUi(
        tester,
        overrides: [
          focusSessionProvider.overrideWith((ref) {
            attempts++;
            return attempts == 1
                ? Stream<FocusSession?>.error(const StorageFailure())
                : Stream<FocusSession?>.value(null);
          }),
        ],
      );
      await pumpCards(tester, failing);
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await tester.settleDb();
      expect(rich('0 / 25 Min.'), findsOneWidget);
    });

    testWidgets(
      'the card is read as one button with its state (AT34)',
      (tester) => withSemantics(tester, () async {
        final ui = await createFocusUi(tester);
        await pumpCards(tester, ui);
        expect(
          find.bySemanticsLabel(
            'Fokus, Fokuszeit heute: 0 von 25 Minuten, '
            'Noch 25 Min. bis zu deinem Tagesziel',
          ),
          findsOneWidget,
        );
        await tester.startFocus(ui);
        await tester.pump();
        expect(
          find.bySemanticsLabel('Fokus, Läuft, Lernen · Noch 25 Min.'),
          findsOneWidget,
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }),
    );
  });

  group('workout card', () {
    testWidgets('an empty week is shown honestly, with the way to log one', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      final router = await pumpCards(tester, ui);
      expect(find.text('Workout'), findsOneWidget);
      expect(rich('0 / 3 Trainings'), findsOneWidget);
      expect(find.text('Noch kein Workout diese Woche'), findsOneWidget);
      expect(find.text('0 Min.'), findsOneWidget);
      expect(find.text('diese Woche'), findsOneWidget);
      expect(workoutRing(tester).value, 0);
      await tester.tap(find.text('Training eintragen'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/workouts/new');
    });

    testWidgets(
      'this week: count, minutes, the latest workout and the ring (F03, A01, AT20)',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.addWorkout(
          ui,
          title: 'Upper Body',
          minutes: 60,
          groups: [MuscleGroup.chest],
          at: DateTime.utc(2026, 10, 3, 7),
        );
        await tester.addWorkout(
          ui,
          title: 'Lower Body',
          minutes: 45,
          at: DateTime.utc(2026, 9, 29, 16),
        );
        final router = await pumpCards(tester, ui);
        expect(rich('2 / 3 Trainings'), findsOneWidget);
        expect(find.text('105 Min.'), findsOneWidget);
        expect(find.text('Zuletzt: Upper Body'), findsOneWidget);
        expect(workoutRing(tester).value, closeTo(2 / 3, 0.0001));
        await tester.tap(find.text('Workout'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/workouts');
      },
    );

    testWidgets('the ring is capped at 100 percent, the real numbers stay '
        '(F03, A01)', (tester) async {
      final ui = await createFocusUi(tester);
      for (var i = 0; i < 5; i++) {
        await tester.addWorkout(
          ui,
          minutes: 30,
          at: DateTime.utc(2026, 10, 3 - i % 3, 6, i),
        );
      }
      await pumpCards(tester, ui);
      expect(rich('5 / 3 Trainings'), findsOneWidget);
      expect(find.text('150 Min.'), findsOneWidget);
      expect(workoutRing(tester).value, 1.0);
    });

    testWidgets('follows new workouts and the new week at once (A01)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await pumpCards(tester, ui);
      expect(rich('0 / 3 Trainings'), findsOneWidget);
      await tester.addWorkout(ui, minutes: 40);
      expect(rich('1 / 3 Trainings'), findsOneWidget);
      expect(find.text('40 Min.'), findsOneWidget);

      ui.harness.clock.setNow(DateTime.utc(2026, 10, 5, 8)); // next Monday
      ui.container.read(todayProvider.notifier).refresh();
      await tester.settleDb();
      expect(rich('0 / 3 Trainings'), findsOneWidget);
      expect(find.text('Noch kein Workout diese Woche'), findsOneWidget);
    });

    testWidgets('an error offers a retry', (tester) async {
      var attempts = 0;
      final ui = await createFocusUi(
        tester,
        overrides: [
          workoutWeekEntriesProvider.overrideWith((ref) {
            attempts++;
            return attempts == 1
                ? Stream.error(const StorageFailure())
                : Stream.value(const []);
          }),
        ],
      );
      await pumpCards(tester, ui);
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.settleDb();
      expect(rich('0 / 3 Trainings'), findsOneWidget);
    });

    testWidgets(
      'the week is read with the real count (AT34)',
      (tester) => withSemantics(tester, () async {
        final ui = await createFocusUi(tester);
        await tester.addWorkout(ui, title: 'Laufen', minutes: 30);
        await pumpCards(tester, ui);
        expect(
          find.bySemanticsLabel(
            'Workout, Diese Woche 1 von 3 Trainings, 30 Minuten. '
            '2 fehlen zum Ziel. Zuletzt: Laufen',
          ),
          findsOneWidget,
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }),
    );
  });
}
