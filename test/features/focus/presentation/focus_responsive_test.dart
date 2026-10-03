import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/workout_intensity.dart';
import 'package:self_improvement/features/focus/focus_module.dart';

import '../../../support/pump_app.dart';
import '../support/focus_ui_kit.dart';

/// Every focus and workout screen at the four widths of the design handoff and
/// at system text scale 1.0 and 2.0: nothing overflows, nothing is clipped,
/// the actions stay reachable (content scrolls) and the save buttons stay above
/// the keyboard (AT33).
void main() {
  String name(Size size, double scale) =>
      '${size.width.toInt()} px at text scale $scale';

  Future<void> shows(
    WidgetTester tester,
    FocusUi ui,
    String location,
    Size size,
    double scale,
    String expectedText,
  ) async {
    await pumpFocusApp(
      tester,
      ui,
      initialLocation: location,
      size: size,
      textScale: scale,
    );
    final exception = tester.takeException();
    if (exception != null) {
      fail('$location at ${name(size, scale)}: $exception');
    }
    expect(
      find.text(expectedText),
      findsWidgets,
      reason: '$location at ${name(size, scale)}',
    );
  }

  /// The widget [text] can be brought into view and lies within the screen.
  Future<void> reachable(
    WidgetTester tester,
    String text,
    Size size,
    String reason,
  ) async {
    final finder = find.text(text).first;
    await tester.ensureVisible(finder);
    await tester.pump();
    final rect = tester.getRect(finder);
    expect(rect.top, greaterThanOrEqualTo(0), reason: reason);
    expect(rect.bottom, lessThanOrEqualTo(size.height), reason: reason);
    expect(rect.left, greaterThanOrEqualTo(0), reason: reason);
    expect(rect.right, lessThanOrEqualTo(size.width), reason: reason);
  }

  for (final size in responsiveSizes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('focus screens fit ${name(size, scale)} (AT33)', (
        tester,
      ) async {
        final ui = await createFocusUi(tester, realProjection: true);
        // Some history first, so the lists and the today card have content.
        await tester.completeFocus(ui, seconds: 1500);
        ui.advance(60);
        final done = await tester.completeFocus(ui, seconds: 600);
        ui.advance(60);

        await shows(tester, ui, '/focus', size, scale, 'Fokus starten');
        await reachable(tester, 'Fokus starten', size, 'start button');
        await reachable(tester, 'Programmieren', size, 'category chip');
        await reachable(tester, 'Verlauf', size, 'history link');
        await shows(tester, ui, '/focus/history', size, scale, 'Fokus-Verlauf');
        await shows(
          tester,
          ui,
          '/focus/history/$done',
          size,
          scale,
          'Sitzung bearbeiten',
        );
        await reachable(tester, 'Sitzung löschen', size, 'delete');
        await reachable(tester, 'Änderungen speichern', size, 'save note');
        await shows(
          tester,
          ui,
          '/focus/session',
          size,
          scale,
          'Keine laufende Sitzung',
        );

        await tester.startFocus(ui);
        await shows(tester, ui, '/focus', size, scale, 'Sitzung fortsetzen');
        await reachable(tester, 'Sitzung fortsetzen', size, 'resume');
        await shows(
          tester,
          ui,
          '/focus/session',
          size,
          scale,
          'Läuft · Lernen',
        );
        await reachable(tester, 'Pausieren', size, 'pause');
        await reachable(tester, 'Beenden', size, 'end');

        // The "Beenden" sheet.
        await tester.tap(find.text('Beenden'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'end sheet');
        expect(find.text('Sitzung beenden?'), findsOneWidget);
        await reachable(tester, 'Weiter fokussieren', size, 'sheet cancel');
        await tester.tap(find.text('Weiter fokussieren'));
        await tester.pumpAndSettle();

        // Paused.
        await tester.tapAndSettleDb(find.text('Pausieren'));
        expect(tester.takeException(), isNull, reason: 'paused');
        expect(find.text('Pausiert · Lernen'), findsOneWidget);
        await reachable(tester, 'Fortsetzen', size, 'resume button');
        await tester.tapAndSettleDb(find.text('Fortsetzen'));

        // Waiting for the confirmation.
        ui.advance(1600);
        await resumeApp(tester);
        expect(tester.takeException(), isNull, reason: 'awaiting');
        expect(find.text('Geschafft!'), findsOneWidget);
        await reachable(tester, 'Sitzung speichern', size, 'save');
        await reachable(tester, 'Verwerfen', size, 'discard');
        // The confirmation sheet of "Verwerfen".
        await tester.tap(find.text('Verwerfen'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'discard sheet');
        expect(find.text('Sitzung verwerfen?'), findsOneWidget);
        await tester.tap(find.text('Abbrechen'));
        await tester.pumpAndSettle();
      });

      testWidgets('workout screens fit ${name(size, scale)} (AT33)', (
        tester,
      ) async {
        final ui = await createFocusUi(tester);
        final entry = await tester.addWorkout(
          ui,
          title: 'Ein ziemlich langer Titel für ein Training',
          minutes: 60,
          groups: MuscleGroup.values,
          intensity: WorkoutIntensity.moderate,
          note: 'Eine Notiz, die auch etwas länger sein darf.',
        );
        await tester.insertWorkouts(
          ui,
          5,
          newest: DateTime.utc(2026, 10, 2, 7),
        );

        await shows(tester, ui, '/workouts', size, scale, 'Meine Workouts');
        await reachable(
          tester,
          'Training eintragen',
          size,
          'pinned log button',
        );
        await reachable(tester, 'Wochenziel ändern', size, 'goal link');
        await shows(tester, ui, '/workouts/all', size, scale, 'Alle Trainings');
        await shows(
          tester,
          ui,
          '/workouts/new',
          size,
          scale,
          'Workout eintragen',
        );
        await reachable(tester, 'Training speichern', size, 'save');
        await reachable(tester, 'Sport', size, 'last category');
        await reachable(tester, 'Ganzkörper', size, 'last muscle group');
        await reachable(tester, 'Hart', size, 'intensity');
        await reachable(tester, 'Zeitpunkt', size, 'time row');
        // The validation errors fit as well.
        await tester.tap(find.text('Training speichern'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: 'errors');
        expect(
          find.text('Bitte wähle eine Trainingskategorie.'),
          findsOneWidget,
        );
        await shows(
          tester,
          ui,
          '/workouts/${entry.id}',
          size,
          scale,
          'Training bearbeiten',
        );
        await reachable(tester, 'Training löschen', size, 'delete');
        await reachable(tester, 'Änderungen speichern', size, 'save changes');
      });

      testWidgets('dashboard cards fit ${name(size, scale)} (AT33)', (
        tester,
      ) async {
        final ui = await createFocusUi(tester);
        await tester.addWorkout(ui, title: 'Upper Body', minutes: 60);
        final cards = const FocusModule().dashboardCards;
        Future<void> pumpCards() async {
          await pumpRouterApp(
            tester,
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => Scaffold(
                  body: SingleChildScrollView(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final card in cards)
                          Expanded(
                            child: Consumer(
                              builder: (context, ref, _) =>
                                  card.builder(context, ref),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            initialLocation: '/',
            container: ui.container,
            size: size,
            textScale: scale,
          );
          await tester.settleDb();
          expect(
            tester.takeException(),
            isNull,
            reason: 'cards at ${name(size, scale)}',
          );
        }

        // Two cards side by side is the harshest case (half width each).
        await pumpCards();
        expect(find.text('Workout'), findsOneWidget);
        await tester.startFocus(ui);
        await tester.pump();
        await pumpCards();
        expect(find.text('Fokus fortsetzen'), findsOneWidget);
      });
    }
  }

  testSemantics('tap targets and labels hold at 320 px and text scale 2.0 '
      '(AT33, AT34)', (tester) async {
    final ui = await createFocusUi(tester);
    final done = await tester.completeFocus(ui, seconds: 600);
    await tester.addWorkout(ui, title: 'Upper Body', minutes: 60);
    const size = Size(320, 640);
    for (final location in [
      '/focus',
      '/focus/history',
      '/focus/history/$done',
      '/workouts',
      '/workouts/all',
      '/workouts/new',
    ]) {
      await pumpFocusApp(
        tester,
        ui,
        initialLocation: location,
        size: size,
        textScale: 2.0,
      );
      await expectLater(
        tester,
        meetsGuideline(androidTapTargetGuideline),
        reason: location,
      );
      await expectLater(
        tester,
        meetsGuideline(labeledTapTargetGuideline),
        reason: location,
      );
    }
    await tester.startFocus(ui);
    await pumpFocusApp(
      tester,
      ui,
      initialLocation: '/focus/session',
      size: size,
      textScale: 2.0,
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  group('with the keyboard open', () {
    for (final size in [responsiveSizes.first, responsiveSizes[2]]) {
      testWidgets('the workout save button stays above the keyboard at '
          '${size.width.toInt()} px (AT33)', (tester) async {
        final ui = await createFocusUi(tester);
        const keyboard = 300.0;
        await pumpFocusApp(
          tester,
          ui,
          initialLocation: '/workouts/new',
          size: size,
          textScale: 2.0,
          viewInsets: const EdgeInsets.only(bottom: keyboard),
        );
        final duration = find.byType(TextField).at(1);
        await tester.ensureVisible(duration);
        await tester.tap(duration);
        await tester.pump();
        final save = find.text('Training speichern');
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(save);
        await tester.pump();
        final rect = tester.getRect(save);
        expect(
          rect.bottom,
          lessThanOrEqualTo(size.height - keyboard),
          reason: 'the save button is not covered by the keyboard',
        );
        expect(rect.top, greaterThanOrEqualTo(0));
        await tester.tap(save); // reachable: the tap lands on it
        await tester.pump();
        expect(
          find.text('Bitte wähle eine Trainingskategorie.'),
          findsOneWidget,
        );
      });
    }

    testWidgets('the note field of the session is reachable above the '
        'keyboard (AT33)', (tester) async {
      final ui = await createFocusUi(tester);
      final id = await tester.completeFocus(ui, seconds: 600);
      const size = Size(320, 640);
      const keyboard = 300.0;
      await pumpFocusApp(
        tester,
        ui,
        initialLocation: '/focus/history/$id',
        size: size,
        textScale: 2.0,
        viewInsets: const EdgeInsets.only(bottom: keyboard),
      );
      await tester.enterText(find.byType(TextField), 'Notiz');
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Änderungen speichern'));
      await tester.pump();
      final rect = tester.getRect(find.text('Änderungen speichern'));
      expect(rect.bottom, lessThanOrEqualTo(size.height - keyboard));
    });
  });
}
