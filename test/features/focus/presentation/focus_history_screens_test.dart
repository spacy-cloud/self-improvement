import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_history.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/flaky_repositories.dart';
import '../support/focus_ui_kit.dart';

/// The focus history (`/focus/history`) and the session detail with note,
/// delete and undo (`/focus/history/:id`), following the weight pattern.
void main() {
  final noteField = find.byType(TextField);
  final saveChanges = find.text('Änderungen speichern');

  group('history', () {
    testWidgets('without sessions: an empty state with the way to start', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      final router = await pumpFocusApp(
        tester,
        ui,
        initialLocation: '/focus/history',
      );
      expect(find.text('Fokus-Verlauf'), findsOneWidget);
      expect(find.text('Noch keine Sitzung'), findsOneWidget);
      await tester.tap(find.text('Fokus starten'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/focus');
    });

    testWidgets(
      'groups the sessions by their confirmation day, newest first (F02)',
      (tester) async {
        final ui = await createFocusUi(tester);
        ui.harness.clock.setNow(DateTime.utc(2026, 10, 1, 8));
        await tester.completeFocus(ui, seconds: 600);
        ui.harness.clock.setNow(DateTime.utc(2026, 10, 2, 14));
        await tester.completeFocus(
          ui,
          seconds: 1500,
          category: FocusCategory.programming,
        );
        ui.harness.clock.setNow(DateTime.utc(2026, 10, 3, 8));
        await tester.completeFocus(
          ui,
          seconds: 1200,
          plannedSeconds: 1200,
          category: FocusCategory.reading,
        );
        await tester.completeFocus(
          ui,
          seconds: 300,
          category: FocusCategory.meditation,
        );
        await pumpFocusApp(tester, ui, initialLocation: '/focus/history');

        final headers = [
          for (final text in tester.widgetList<Text>(find.byType(Text)))
            if (text.data == text.data?.toUpperCase() &&
                (text.data ?? '').length > 4 &&
                !(text.data ?? '').contains(' '))
              text.data,
        ];
        expect(headers, ['HEUTE', 'GESTERN', 'DONNERSTAG']);
        final rows = find.byType(EntryListTile);
        expect(rows, findsNWidgets(4));
        // Today: the newest first (Meditation after Lesen).
        expect(
          find.descendant(of: rows.at(0), matching: find.text('Meditation')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: rows.at(0),
            matching: find.text('10:25 · früher beendet'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: rows.at(1), matching: find.text('Lesen')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: rows.at(1), matching: find.text('20 Min.')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: rows.at(1),
            matching: find.text('10:20 · abgeschlossen'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: rows.at(2), matching: find.text('Programmieren')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: rows.at(3), matching: find.text('Lernen')),
          findsOneWidget,
        );
        expect(
          find.text(
            'Tippe auf einen Eintrag, um ihn zu bearbeiten oder zu löschen.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('open and discarded sessions are no history (F01)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await tester.completeFocus(ui, seconds: 600);
      final discarded = await tester.startFocus(ui);
      ui.advance(120);
      await tester.runCommand(
        () => ui.focusRepository.discard(
          commandId: ui.ids.newId(),
          id: discarded,
        ),
      );
      await tester.startFocus(ui);
      await pumpFocusApp(tester, ui, initialLocation: '/focus/history');
      expect(find.byType(EntryListTile), findsOneWidget);
      expect(find.text('10 Min.'), findsOneWidget);
    });

    testWidgets(
      'an older session stays on the day of its confirmation, also after a time zone change (AT25)',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.completeFocus(ui, seconds: 600); // 08:10Z = 10:10 Berlin
        ui.harness.clock.setTimeZone('Asia/Tokyo'); // the phone travels
        ui.container.read(todayProvider.notifier).refresh();
        await pumpFocusApp(tester, ui, initialLocation: '/focus/history');
        expect(
          find.text('10:10 · früher beendet'),
          findsOneWidget,
          reason: 'the frozen zone, not 17:10 of Tokyo',
        );
        expect(find.text('17:10 · früher beendet'), findsNothing);
        expect(find.text('Heute'), findsNothing, reason: 'no row title');
        expect(find.text('HEUTE'), findsOneWidget);
      },
    );

    testWidgets('loads older sessions on request, built lazily (AT36)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await tester.insertCompletedSessions(
        ui,
        60,
        newestEnd: DateTime.utc(2026, 10, 3, 7),
      );
      await pumpFocusApp(tester, ui, initialLocation: '/focus/history');
      final loadMore = find.text('Ältere Sitzungen laden');
      await tester.scrollUntilVisible(
        loadMore,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(loadMore, findsOneWidget);
      expect(find.byType(EntryListTile).evaluate().length, lessThan(40));

      await tester.tap(loadMore);
      await tester.settleDb();
      expect(loadMore, findsNothing, reason: 'everything is loaded');
      // 60 sessions in total: the oldest is reachable.
      final entries = await tester.runAsync(
        () => ui.focusRepository.fetchHistory(limit: 200),
      );
      expect(entries, hasLength(60));
    });

    testWidgets('a row opens the session; back returns to the list', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      final id = await tester.completeFocus(ui, seconds: 600);
      final router = await pumpFocusApp(
        tester,
        ui,
        initialLocation: '/focus/history',
      );
      await tester.tap(find.byType(EntryListTile));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/focus/history/$id');
      expect(find.text('Sitzung bearbeiten'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Zurück'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/focus/history');
    });

    testWidgets('loading shows nothing yet, no empty state', (tester) async {
      final never = StreamController<List<FocusHistoryEntry>>();
      addTearDown(never.close);
      final ui = await createFocusUi(
        tester,
        overrides: [
          focusHistoryPageProvider.overrideWith((ref, limit) => never.stream),
        ],
      );
      await pumpFocusApp(tester, ui, initialLocation: '/focus/history');
      expect(find.byType(EntryListTile), findsNothing);
      expect(find.text('Noch keine Sitzung'), findsNothing);
      expect(find.text('Daten konnten nicht geladen werden'), findsNothing);
    });

    testWidgets('an error offers a retry that reads again', (tester) async {
      var attempts = 0;
      final ui = await createFocusUi(
        tester,
        overrides: [
          focusHistoryPageProvider.overrideWith((ref, limit) {
            attempts++;
            return attempts == 1
                ? Stream<List<FocusHistoryEntry>>.error(const StorageFailure())
                : Stream<List<FocusHistoryEntry>>.value(const []);
          }),
        ],
      );
      await pumpFocusApp(tester, ui, initialLocation: '/focus/history');
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Noch keine Sitzung'), findsOneWidget);
    });
  });

  group('detail', () {
    Future<(FocusUi, String)> openDetail(
      WidgetTester tester, {
      bool realProjection = false,
      int seconds = 600,
      FocusCategory category = FocusCategory.learning,
    }) async {
      final ui = await createFocusUi(tester, realProjection: realProjection);
      final id = await tester.completeFocus(
        ui,
        seconds: seconds,
        category: category,
      );
      await pumpFocusApp(tester, ui, initialLocation: '/focus/history/$id');
      return (ui, id);
    }

    testWidgets('shows the facts of the session', (tester) async {
      await openDetail(tester);
      expect(find.text('Sitzung bearbeiten'), findsOneWidget);
      expect(find.text('Lernen'), findsOneWidget);
      expect(find.text('früher beendet'), findsOneWidget);
      expect(find.text('Gespeicherte Zeit'), findsOneWidget);
      expect(find.text('10 Min.'), findsOneWidget);
      expect(find.text('Geplant'), findsOneWidget);
      expect(find.text('25 Min.'), findsOneWidget);
      expect(find.text('Bestätigt'), findsOneWidget);
      expect(find.text('Heute, 10:10 Uhr'), findsOneWidget);
      expect(find.text('Notiz'), findsOneWidget);
      expect(find.text('Sitzung löschen'), findsOneWidget);
      // Nothing to save before something changed.
      final button = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Änderungen speichern'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('saving the note: committed, message with undo, back to the '
        'history (F02)', (tester) async {
      final ui = await createFocusUi(tester);
      final id = await tester.completeFocus(ui, seconds: 600);
      final router = await pumpFocusApp(
        tester,
        ui,
        initialLocation: '/focus/history',
      );
      await tester.tap(find.byType(EntryListTile));
      await tester.pumpAndSettle();

      await tester.enterText(noteField, '  Kapitel 3 gelesen  ');
      await tester.pump();
      await tester.tapAndSettleDb(saveChanges);

      final row = (await tester.focusRows(ui)).single;
      expect(row.id, id);
      expect(row.note, 'Kapitel 3 gelesen', reason: 'trimmed');
      expect(row.accumulatedSeconds, 600, reason: 'time is not editable');
      expect(ui.feedback.last!.kind, 'saved');
      expect(ui.feedback.last!.message, 'Notiz gespeichert');
      expect(router.state.uri.path, '/focus/history');

      await tester.runAsync(() => ui.feedback.last!.undo!.perform());
      expect((await tester.focusRows(ui)).single.note, isNull);
    });

    testWidgets('a note of 500 characters is saved, a 501st cannot be typed', (
      tester,
    ) async {
      final (ui, _) = await openDetail(tester);
      await tester.enterText(noteField, 'x' * 501);
      await tester.pump();
      expect(tester.widget<TextField>(noteField).controller!.text.length, 500);
      await tester.tapAndSettleDb(saveChanges);
      expect((await tester.focusRows(ui)).single.note, 'x' * 500);
    });

    testWidgets(
      'a note the field accepts but the rules reject takes the focus',
      (tester) async {
        final (ui, _) = await openDetail(tester);
        // 101 characters for the field, but 505 code points for the rule of 500.
        await tester.enterText(
          noteField,
          '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}' * 101,
        );
        await tester.pump();
        await tester.tapAndSettleDb(saveChanges);

        expect(
          find.text('Die Notiz darf höchstens 500 Zeichen lang sein.'),
          findsOneWidget,
        );
        expect(tester.widget<TextField>(noteField).focusNode!.hasFocus, isTrue);
        expect((await tester.focusRows(ui)).single.note, isNull);
      },
    );

    testWidgets('an unchanged or blank note keeps the button disabled; '
        'clearing removes the note', (tester) async {
      final ui = await createFocusUi(tester);
      final id = await tester.completeFocus(ui, seconds: 600);
      await tester.runCommand(
        () => ui.focusRepository.updateNote(
          commandId: ui.ids.newId(),
          id: id,
          note: 'Alt',
        ),
      );
      await pumpFocusApp(tester, ui, initialLocation: '/focus/history/$id');
      expect(find.text('Alt'), findsOneWidget);
      PrimaryButton button() => tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Änderungen speichern'),
      );
      expect(button().onPressed, isNull);
      await tester.enterText(noteField, 'Alt   ');
      await tester.pump();
      expect(button().onPressed, isNull, reason: 'only whitespace changed');
      await tester.enterText(noteField, '');
      await tester.pump();
      expect(button().onPressed, isNotNull);
      await tester.tapAndSettleDb(saveChanges);
      expect((await tester.focusRows(ui)).single.note, isNull);
    });

    testWidgets(
      'a failed save keeps the text and retries with the same command id (AT27, AT12)',
      (tester) async {
        late FlakyFocusRepository flaky;
        final ui = await createFocusUi(
          tester,
          overrides: [flakyFocusRepository((r) => flaky = r, noteFailures: 1)],
        );
        final id = await tester.completeFocus(ui, seconds: 600);
        await pumpFocusApp(tester, ui, initialLocation: '/focus/history/$id');
        await tester.enterText(noteField, 'Wichtig');
        await tester.pump();
        await tester.tapAndSettleDb(saveChanges);

        expect((await tester.focusRows(ui)).single.note, isNull);
        expect(
          ui.feedback.last!.message,
          'Speichern fehlgeschlagen. Deine Notiz bleibt erhalten.',
        );
        expect(find.text('Wichtig'), findsOneWidget, reason: 'input kept');
        ui.feedback.last!.onRetry!();
        await tester.settleDb();
        expect((await tester.focusRows(ui)).single.note, 'Wichtig');
        expect(flaky.noteIds, hasLength(2));
        expect(flaky.noteIds.first, flaky.noteIds.last);
      },
    );

    testWidgets(
      'a change made elsewhere meanwhile is a conflict: nothing is overwritten, the input stays (AT27)',
      (tester) async {
        final ui = await createFocusUi(tester);
        final id = await tester.completeFocus(ui, seconds: 600);
        await pumpFocusApp(tester, ui, initialLocation: '/focus/history/$id');
        await tester.runCommand(
          () => ui.focusRepository.updateNote(
            commandId: ui.ids.newId(),
            id: id,
            note: 'Von woanders',
          ),
        );
        await tester.enterText(noteField, 'Meine Version');
        await tester.pump();
        await tester.tapAndSettleDb(saveChanges);

        expect((await tester.focusRows(ui)).single.note, 'Von woanders');
        expect(
          ui.feedback.last!.message,
          'Die Sitzung wurde inzwischen geändert. Bitte öffne sie erneut.',
        );
        expect(find.text('Meine Version'), findsOneWidget);
      },
    );

    testWidgets('leaving with unsaved text asks first; "Weiter bearbeiten" '
        'keeps it, "Verwerfen" leaves', (tester) async {
      final ui = await createFocusUi(tester);
      final id = await tester.completeFocus(ui, seconds: 600);
      final router = await pumpFocusApp(
        tester,
        ui,
        initialLocation: '/focus/history/$id',
      );
      await tester.enterText(noteField, 'Noch nicht gespeichert');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await tester.tap(find.text('Weiter bearbeiten'));
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsNothing);
      expect(find.text('Noch nicht gespeichert'), findsOneWidget);

      await tester.binding.handlePopRoute(); // Android back
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await tester.tap(find.text('Verwerfen'));
      await tester.pumpAndSettle();
      expect(
        router.state.uri.path,
        '/focus/history',
        reason: 'left the screen: nothing below it, so the history',
      );
      expect((await tester.focusRows(ui)).single.note, isNull);
    });

    testWidgets('leaving without changes does not ask', (tester) async {
      final (ui, id) = await openDetail(tester);
      await tester.tap(find.bySemanticsLabel('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsNothing);
      expect(await tester.focusRows(ui), hasLength(1));
      expect(id, isNotEmpty);
    });

    testWidgets('deleting asks first; cancel keeps the session (AT23)', (
      tester,
    ) async {
      final (ui, _) = await openDetail(tester, realProjection: true);
      await tester.tap(find.text('Sitzung löschen'));
      await tester.pumpAndSettle();
      expect(find.text('Sitzung vom 3. Okt. löschen?'), findsOneWidget);
      expect(
        find.text(
          '10 Min. Lernen wird entfernt. Du kannst es direkt danach '
          'rückgängig machen.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect((await tester.focusRows(ui)).single.deletedAtUtc, isNull);
    });

    testWidgets(
      'deleting removes the time and its XP; the undo brings back the same session (AT23, G01)',
      (tester) async {
        final ui = await createFocusUi(tester, realProjection: true);
        final id = await tester.completeFocus(ui, seconds: 1500);
        expect(await tester.xpAwards(ui), hasLength(1));
        await pumpFocusApp(tester, ui, initialLocation: '/focus/history/$id');

        await tester.tap(find.text('Sitzung löschen'));
        await tester.pumpAndSettle();
        await tester.tapAndSettleDb(find.text('Löschen'));

        expect((await tester.focusRows(ui)).single.deletedAtUtc, isNotNull);
        expect(await tester.xpAwards(ui), isEmpty, reason: 'its XP is gone');
        expect(ui.feedback.last!.message, 'Sitzung gelöscht');
        expect(ui.feedback.last!.undo, isNotNull);
        final today = await tester.runAsync(
          () =>
              ui.focusRepository.watchCompletedOn(LocalDate(2026, 10, 3)).first,
        );
        expect(today, isEmpty, reason: 'the focus time of the day shrank');

        await tester.runAsync(() => ui.feedback.last!.undo!.perform());
        final row = (await tester.focusRows(ui)).single;
        expect(row.id, id);
        expect(row.deletedAtUtc, isNull);
        expect(await tester.xpAwards(ui), hasLength(1), reason: 'XP is back');
      },
    );

    testWidgets('a failed delete keeps the session (AT27)', (tester) async {
      final projection = RecordingProjectionSynchronizer();
      final ui = await createFocusUi(tester, projection: projection);
      final id = await tester.completeFocus(ui, seconds: 600);
      await pumpFocusApp(tester, ui, initialLocation: '/focus/history/$id');
      projection.failure = StateError('disk full');
      await tester.tap(find.text('Sitzung löschen'));
      await tester.pumpAndSettle();
      await tester.tapAndSettleDb(find.text('Löschen'));
      expect((await tester.focusRows(ui)).single.deletedAtUtc, isNull);
      expect(
        ui.feedback.last!.message,
        'Löschen fehlgeschlagen. Die Sitzung ist unverändert.',
      );
      expect(find.text('Sitzung bearbeiten'), findsOneWidget);
    });

    testWidgets('an unknown session is "not found" with a way back', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      final router = await pumpFocusApp(
        tester,
        ui,
        initialLocation: '/focus/history/unknown',
      );
      expect(find.text('Sitzung nicht gefunden'), findsOneWidget);
      await tester.tap(find.text('Zum Verlauf'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/focus/history');
    });

    testWidgets('an open session cannot be edited here', (tester) async {
      final ui = await createFocusUi(tester);
      final id = await tester.startFocus(ui);
      final router = await pumpFocusApp(
        tester,
        ui,
        initialLocation: '/focus/history/$id',
      );
      expect(find.text('Sitzung noch nicht abgeschlossen'), findsOneWidget);
      expect(find.text('Sitzung löschen'), findsNothing);
      await tester.tap(find.text('Zur Sitzung'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/focus/session');
    });
  });

  group('accessibility', () {
    testWidgets(
      'history and detail have labels and 48 px targets (AT33, '
      'AT34)',
      (tester) => withSemantics(tester, () async {
        final ui = await createFocusUi(tester);
        final id = await tester.completeFocus(ui, seconds: 600);
        await pumpFocusApp(tester, ui, initialLocation: '/focus/history');
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(
          find.bySemanticsLabel(
            'Lernen, 10:10 Uhr, früher beendet, 10 Minuten. '
            'Tippen zum Bearbeiten',
          ),
          findsOneWidget,
        );
        await closeApp(tester);
        await pumpFocusApp(tester, ui, initialLocation: '/focus/history/$id');
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }),
    );
  });
}
