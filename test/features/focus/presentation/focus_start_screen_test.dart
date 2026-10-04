import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/application/focus_setup_controller.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_history.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/focus_timer.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/flaky_repositories.dart';
import '../support/focus_ui_kit.dart';

/// The start screen "Fokus" (`/focus`): setup, resume instead of a second
/// session, today's summary and the sessions of today.
void main() {
  final minus = find.byIcon(Icons.remove_rounded);
  final plus = find.byIcon(Icons.add_rounded);
  Finder chip(String label) => find.widgetWithText(AppChoiceChip, label);
  final start = find.text('Fokus starten');

  bool isSelected(WidgetTester tester, String label) =>
      tester.widget<AppChoiceChip>(chip(label)).selected;

  group('setup', () {
    testWidgets('shows 25 minutes and the five categories, nothing started', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await pumpFocusApp(tester, ui);

      expect(find.text('Fokus'), findsOneWidget, reason: 'header');
      expect(find.text('25:00'), findsOneWidget);
      expect(find.text('Minuten'), findsOneWidget);
      for (final label in [
        'Lesen',
        'Lernen',
        'Programmieren',
        'Meditation',
        'Sonstiges',
      ]) {
        expect(chip(label), findsOneWidget, reason: label);
      }
      expect(find.text('Arbeit'), findsNothing, reason: 'not in the spec');
      expect(find.byType(AppChoiceChip), findsNWidgets(5));
      expect(isSelected(tester, 'Sonstiges'), isTrue);
      expect(isSelected(tester, 'Lernen'), isFalse);
      expect(start, findsOneWidget);
      expect(await tester.focusRows(ui), isEmpty);
    });

    testWidgets('choosing a category selects exactly that one', (tester) async {
      final ui = await createFocusUi(tester);
      await pumpFocusApp(tester, ui);
      await tester.tap(chip('Programmieren'));
      await tester.pump();
      expect(isSelected(tester, 'Programmieren'), isTrue);
      expect(isSelected(tester, 'Sonstiges'), isFalse);
      await tester.tap(chip('Meditation'));
      await tester.pump();
      expect(
        [
          for (final c in FocusCategory.values)
            if (isSelected(tester, c.label)) c.label,
        ],
        ['Meditation'],
      );
    });

    testWidgets('the duration changes by five minutes (F01)', (tester) async {
      final ui = await createFocusUi(tester);
      await pumpFocusApp(tester, ui);
      await tester.tap(plus);
      await tester.pump();
      expect(find.text('30:00'), findsOneWidget);
      await tester.tap(minus);
      await tester.tap(minus);
      await tester.pump();
      expect(find.text('20:00'), findsOneWidget);
    });

    testWidgets('the lower limit is 5 minutes: 4 is not reachable', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await pumpFocusApp(tester, ui);
      for (var i = 0; i < 4; i++) {
        await tester.tap(minus);
        await tester.pump();
      }
      expect(find.text('05:00'), findsOneWidget);
      await tester.tap(minus);
      await tester.pump();
      expect(find.text('05:00'), findsOneWidget, reason: 'stays at 5');
      // Even a direct request below the limit is clamped.
      ui.container.read(focusSetupProvider.notifier).setPlannedMinutes(4);
      await tester.pump();
      expect(find.text('05:00'), findsOneWidget);

      await tester.tap(start);
      await tester.settleDb();
      final rows = await tester.focusRows(ui);
      expect(rows.single.plannedSeconds, 300);
    });

    testWidgets('the upper limit is 180 minutes: 181 is not reachable', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await pumpFocusApp(tester, ui);
      for (var i = 0; i < 31; i++) {
        await tester.tap(plus);
        await tester.pump();
      }
      expect(find.text('3:00:00'), findsOneWidget);
      expect(find.text('180 Minuten'), findsOneWidget);
      await tester.tap(plus);
      await tester.pump();
      expect(find.text('3:00:00'), findsOneWidget, reason: 'stays at 180');
      ui.container.read(focusSetupProvider.notifier).setPlannedMinutes(181);
      await tester.pump();
      expect(find.text('3:00:00'), findsOneWidget);

      await tester.tap(start);
      await tester.settleDb();
      expect((await tester.focusRows(ui)).single.plannedSeconds, 10800);
    });

    testWidgets(
      'the buttons at the limits are disabled and spoken',
      (tester) => withSemantics(tester, () async {
        final ui = await createFocusUi(tester);
        await pumpFocusApp(tester, ui);
        SemanticsNode node(String label) =>
            tester.getSemantics(find.bySemanticsLabel(label));
        expect(
          node('Dauer um 5 Minuten verringern')
              .getSemanticsData()
              .flagsCollection
              .isEnabled,
          Tristate.isTrue,
        );
        ui.container.read(focusSetupProvider.notifier).setPlannedMinutes(5);
        await tester.pump();
        final down = node('Dauer um 5 Minuten verringern').getSemanticsData();
        expect(
          down.flagsCollection.isEnabled,
          Tristate.isFalse,
          reason: 'at 5 minutes',
        );
        ui.container.read(focusSetupProvider.notifier).setPlannedMinutes(180);
        await tester.pump();
        final up = node('Dauer um 5 Minuten erhöhen').getSemanticsData();
        expect(
          up.flagsCollection.isEnabled,
          Tristate.isFalse,
          reason: 'at 180 minutes',
        );
      }),
    );
  });

  group('starting', () {
    testWidgets(
      'starts one running session with the choice and opens it (AT16, F01)',
      (tester) async {
        final ui = await createFocusUi(tester);
        final router = await pumpFocusApp(tester, ui);
        await tester.tap(chip('Lernen'));
        await tester.tap(plus);
        await tester.pump();
        await tester.tapAndSettleDb(start);

        final rows = await tester.focusRows(ui);
        expect(rows, hasLength(1));
        expect(rows.single.status, 'running');
        expect(rows.single.category, 'learning');
        expect(rows.single.plannedSeconds, 1800);
        expect(rows.single.accumulatedSeconds, 0);
        expect(
          router.state.uri.path,
          '/focus/session',
          reason: 'the running session is shown',
        );
        expect(find.text('Läuft · Lernen'), findsOneWidget);
        expect(find.text('30:00'), findsOneWidget);
      },
    );

    testWidgets(
      'going back from the running session never allows a second start '
      '(F01)',
      (tester) async {
        final ui = await createFocusUi(tester);
        final router = await pumpFocusApp(tester, ui);
        await tester.tapAndSettleDb(start);
        expect(router.state.uri.path, '/focus/session');

        router.pop();
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/focus');
        expect(find.text('Fokus starten'), findsNothing);
        expect(find.text('Sitzung fortsetzen'), findsOneWidget);
        expect(await tester.focusRows(ui), hasLength(1));
      },
    );

    testWidgets('a double tap on start creates ONE session (AT12, F01)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await pumpFocusApp(tester, ui);
      await tester.tap(start);
      await tester.tap(start);
      await tester.settleDb();
      expect(await tester.focusRows(ui), hasLength(1));
      expect(await tester.receipts(ui, 'focus.start'), hasLength(1));
    });

    testWidgets(
      'a failed start keeps the choice, retries with the same command id and creates one session (AT27, AT12)',
      (tester) async {
        late FlakyFocusRepository flaky;
        final ui = await createFocusUi(
          tester,
          overrides: [flakyFocusRepository((r) => flaky = r, startFailures: 1)],
        );
        await pumpFocusApp(tester, ui);
        await tester.tap(chip('Lesen'));
        await tester.tap(minus);
        await tester.pump();

        await tester.tapAndSettleDb(start);
        expect(
          await tester.focusRows(ui),
          isEmpty,
          reason: 'nothing committed',
        );
        expect(ui.feedback.last!.kind, 'error');
        expect(
          ui.feedback.last!.message,
          'Starten fehlgeschlagen. Deine Auswahl bleibt erhalten.',
        );
        expect(ui.feedback.last!.onRetry, isNotNull);
        expect(isSelected(tester, 'Lesen'), isTrue, reason: 'choice kept');
        expect(find.text('20:00'), findsOneWidget, reason: 'duration kept');
        expect(find.text('Fokus starten'), findsOneWidget, reason: 'retryable');

        ui.feedback.last!.onRetry!();
        await tester.settleDb();
        final rows = await tester.focusRows(ui);
        expect(rows, hasLength(1));
        expect(rows.single.category, 'reading');
        expect(rows.single.plannedSeconds, 1200);
        expect(flaky.startIds, hasLength(2));
        expect(
          flaky.startIds.first,
          flaky.startIds.last,
          reason: 'the retry reused the command id',
        );
        expect(
          (await tester.receipts(ui, 'focus.start')).single.commandId,
          flaky.startIds.first,
        );
      },
    );

    testWidgets('a rejected duration is shown at the dial, nothing starts', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await pumpFocusApp(tester, ui);
      // The UI keeps 5 to 180; the engine would still refuse anything else.
      final result = await tester.runAsync(
        () => ui.focusRepository
            .start(
              commandId: ui.ids.newId(),
              category: FocusCategory.other,
              plannedSeconds: 299,
            )
            .then<Object?>((_) => null, onError: (Object e) => e),
      );
      expect(result, isA<ValidationFailure>());
      expect(
        (result! as ValidationFailure).fieldErrors[FocusFields.planned],
        'Bitte wähle eine Dauer zwischen 5 und 180 Minuten.',
      );
      expect(await tester.focusRows(ui), isEmpty);
    });

    testWidgets('a start that finds an open session shows the resume card', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await pumpFocusApp(tester, ui);
      // A session was opened elsewhere in the meantime.
      await tester.startFocus(ui);
      expect(find.text('Fokus starten'), findsNothing);
      expect(find.text('Sitzung fortsetzen'), findsOneWidget);
    });
  });

  group('an open session', () {
    testWidgets('is resumed instead of starting a second one (AT16, F01)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await tester.startFocus(ui, category: FocusCategory.reading);
      final router = await pumpFocusApp(tester, ui);

      expect(find.text('Eine Sitzung läuft'), findsOneWidget);
      expect(find.text('Läuft · Lesen'), findsOneWidget);
      expect(find.textContaining('Lesen · Noch'), findsOneWidget);
      expect(
        find.text('Es kann immer nur eine Sitzung gleichzeitig offen sein.'),
        findsOneWidget,
      );
      expect(find.text('Fokus starten'), findsNothing);
      expect(find.byType(AppChoiceChip), findsNothing);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(await tester.focusRows(ui), hasLength(1));

      await tester.tap(find.text('Sitzung fortsetzen'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/focus/session');
      expect(await tester.focusRows(ui), hasLength(1));
    });

    testWidgets('a paused session says so', (tester) async {
      final ui = await createFocusUi(tester);
      final id = await tester.startFocus(ui);
      ui.advance(600);
      await tester.runCommand(
        () => ui.focusRepository.pause(commandId: ui.ids.newId(), id: id),
      );
      await pumpFocusApp(tester, ui);
      expect(find.text('Eine Sitzung ist pausiert'), findsOneWidget);
      expect(find.text('Pausiert · Lernen'), findsOneWidget);
      expect(find.text('Lernen · 15:00 übrig'), findsOneWidget);
      expect(find.text('Sitzung fortsetzen'), findsOneWidget);
    });

    testWidgets('a session that waits for confirmation asks for it', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      final id = await tester.startFocus(ui);
      ui.advance(1600);
      await tester.runCommand(
        () => ui.focusRepository.markAwaitingConfirmation(
          commandId: ui.ids.newId(),
          id: id,
        ),
      );
      await pumpFocusApp(tester, ui);
      expect(
        find.text('Eine Sitzung wartet auf deine Bestätigung'),
        findsOneWidget,
      );
      expect(find.text('Geschafft!'), findsOneWidget);
      expect(find.text('Sitzung bestätigen'), findsOneWidget);
      expect(find.text('Fokus starten'), findsNothing);
    });

    testWidgets(
      'the repository itself refuses a second session (one open session '
      'regardless of the screen, F01)',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.startFocus(ui);
        await pumpFocusApp(tester, ui);
        Object? error;
        await tester.runAsync(() async {
          try {
            await ui.focusRepository.start(
              commandId: ui.ids.newId(),
              category: FocusCategory.other,
              plannedSeconds: 1500,
            );
          } on ConflictFailure catch (failure) {
            error = failure;
          }
        });
        expect(error, isA<ConflictFailure>());
        expect((error! as ConflictFailure).kind, ConflictKind.openFocusSession);
        expect(await tester.focusRows(ui), hasLength(1));
      },
    );
  });

  group('today', () {
    testWidgets('without sessions: zero minutes against the goal, honest', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await pumpFocusApp(tester, ui);
      expect(find.text('Heute'), findsOneWidget);
      expect(find.textContaining('0'), findsWidgets);
      expect(find.text('Noch 25 Min. bis zu deinem Tagesziel'), findsOneWidget);
      expect(find.text('Sitzungen heute'), findsOneWidget);
      expect(
        find.text('Noch keine abgeschlossene Sitzung heute.'),
        findsOneWidget,
      );
      final bar = tester.widget<AppProgressBar>(find.byType(AppProgressBar));
      expect(bar.value, 0);
      expect(bar.semanticLabel, 'Fokuszeit heute: 0 von 25 Minuten');
    });

    testWidgets(
      'saved sessions count with their SAVED minutes and are listed (F02)',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.completeFocus(ui, seconds: 600); // 10 min Lernen
        ui.advance(60);
        await tester.completeFocus(
          ui,
          seconds: 300,
          category: FocusCategory.reading,
        );
        await pumpFocusApp(tester, ui);

        expect(find.text('15 / 25 Min.', findRichText: true), findsOneWidget);
        expect(
          find.text('Noch 10 Min. bis zu deinem Tagesziel'),
          findsOneWidget,
        );
        final bar = tester.widget<AppProgressBar>(find.byType(AppProgressBar));
        expect(bar.value, closeTo(0.6, 0.0001));
        // Newest first with the end time and the state.
        final rows = find.byType(EntryListTile);
        expect(rows, findsNWidgets(2));
        expect(
          find.descendant(of: rows.at(0), matching: find.text('Lesen')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: rows.at(0), matching: find.text('5 Min.')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: rows.at(0),
            matching: find.text('10:16 · früher beendet'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: rows.at(1), matching: find.text('10 Min.')),
          findsOneWidget,
        );
      },
    );

    testWidgets('the goal reached and exceeded is shown as reached', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await tester.completeFocus(ui, seconds: 1500);
      ui.advance(10);
      await tester.completeFocus(ui, seconds: 1200, plannedSeconds: 1200);
      await pumpFocusApp(tester, ui);
      expect(find.text('45 / 25 Min.', findRichText: true), findsOneWidget);
      expect(find.text('Tagesziel erreicht'), findsOneWidget);
      final bar = tester.widget<AppProgressBar>(find.byType(AppProgressBar));
      expect(bar.value, 1.0, reason: 'the bar stops at full');
    });

    testWidgets('without a daily goal only the minutes are shown', (
      tester,
    ) async {
      final ui = await createFocusUi(
        tester,
        overrides: [
          focusTodaySummaryProvider.overrideWithValue(
            AsyncData(
              FocusTodaySummary(
                date: LocalDate(2026, 10, 3),
                completedSeconds: 1500,
                sessionCount: 1,
              ),
            ),
          ),
        ],
      );
      await pumpFocusApp(tester, ui);
      expect(find.text('25 Min.', findRichText: true), findsOneWidget);
      expect(find.byType(AppProgressBar), findsNothing);
      expect(find.text('1 Sitzung heute'), findsOneWidget);
    });

    testWidgets('a session of yesterday does not count today (AT25)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await tester.completeFocus(ui, seconds: 600);
      ui.advance(86400); // the next day
      ui.container.read(todayProvider.notifier).refresh();
      await pumpFocusApp(tester, ui);
      expect(
        find.text('Noch keine abgeschlossene Sitzung heute.'),
        findsOneWidget,
      );
      expect(find.text('Noch 25 Min. bis zu deinem Tagesziel'), findsOneWidget);
    });

    testWidgets('a row opens the session and "Verlauf" opens the history', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      final id = await tester.completeFocus(ui, seconds: 600);
      final router = await pumpFocusApp(tester, ui);
      await tester.tap(find.byType(EntryListTile));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/focus/history/$id');
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verlauf'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/focus/history');
    });
  });

  group('states', () {
    testWidgets('loading shows a neutral text', (tester) async {
      final never = StreamController<FocusSession?>();
      addTearDown(never.close);
      final ui = await createFocusUi(
        tester,
        overrides: [focusSessionProvider.overrideWith((ref) => never.stream)],
      );
      await pumpFocusApp(tester, ui);
      expect(find.text('Wird geladen …'), findsOneWidget);
      expect(find.text('Fokus starten'), findsNothing);
    });

    testWidgets('an error offers a retry that reads again', (tester) async {
      var attempts = 0;
      final ui = await createFocusUi(
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
      await pumpFocusApp(tester, ui);
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      expect(find.text('Fokus starten'), findsNothing);
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Fokus starten'), findsOneWidget);
      expect(attempts, 2);
    });

    testWidgets('an error in today\'s sessions is shown with a retry', (
      tester,
    ) async {
      var attempts = 0;
      final ui = await createFocusUi(
        tester,
        overrides: [
          focusSessionsTodayProvider.overrideWith((ref) {
            attempts++;
            return attempts == 1
                ? Stream<List<FocusHistoryEntry>>.error(const StorageFailure())
                : Stream<List<FocusHistoryEntry>>.value(const []);
          }),
        ],
      );
      await pumpFocusApp(tester, ui);
      expect(find.text('Daten konnten nicht geladen werden'), findsWidgets);
      expect(
        find.text('Fokus starten'),
        findsOneWidget,
        reason: 'still usable',
      );
      await tester.tap(find.text('Erneut versuchen').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.text('Noch keine abgeschlossene Sitzung heute.'),
        findsOneWidget,
      );
    });
  });

  group('navigation', () {
    testWidgets('back leaves the screen, nothing is started', (tester) async {
      final ui = await createFocusUi(tester);
      final router = await pumpFocusApp(tester, ui);
      await tester.tap(find.bySemanticsLabel('Zurück'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/', reason: 'no stack: the dashboard');
      expect(await tester.focusRows(ui), isEmpty);
    });
  });
}
