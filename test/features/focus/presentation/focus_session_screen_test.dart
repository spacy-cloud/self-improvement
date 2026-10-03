import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/focus/application/focus_countdown.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/flaky_repositories.dart';
import '../support/focus_ui_kit.dart';

/// Labels of every live region on the screen (what a screen reader would
/// announce when it changes).
List<String> liveRegionLabels(WidgetTester tester) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.flagsCollection.isLiveRegion) {
      labels.add(data.label);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return labels;
}

/// The running, paused and awaiting-confirmation screens (`/focus/session`).
void main() {
  final save = find.text('Sitzung speichern');
  final pause = find.text('Pausieren');
  final resume = find.text('Fortsetzen');
  final end = find.text('Beenden');

  Future<GoRouter> openSession(WidgetTester tester, FocusUi ui) =>
      pumpFocusApp(tester, ui, initialLocation: '/focus/session');

  group('running', () {
    testWidgets(
      'shows the remaining time and follows the monotonic ticks, with no database write (AT16, F01)',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.startFocus(ui);
        final versionBefore = (await tester.focusRows(ui)).single.rowVersion;
        final commandsBefore = (await tester.receipts(
          ui,
          'focus.start',
        )).length;
        await openSession(tester, ui);

        expect(find.text('Läuft · Lernen'), findsOneWidget);
        expect(find.text('25:00'), findsOneWidget);
        expect(find.text('verbleibend von 25:00'), findsOneWidget);
        expect(
          find.text('Der Timer läuft weiter, auch wenn du die App schließt.'),
          findsOneWidget,
        );
        expect(pause, findsOneWidget);
        expect(end, findsOneWidget);

        await tester.tick(ui, 5);
        expect(find.text('24:55'), findsOneWidget);
        await tester.tick(ui, 55);
        expect(find.text('24:00'), findsOneWidget);
        await tester.tick(ui, 600);
        expect(find.text('14:00'), findsOneWidget);
        for (var i = 0; i < 100; i++) {
          await tester.tick(ui, 1);
        }
        expect(find.text('12:20'), findsOneWidget);

        final row = (await tester.focusRows(ui)).single;
        expect(row.rowVersion, versionBefore, reason: 'no per-second writes');
        expect(row.status, 'running');
        expect(row.accumulatedSeconds, 0);
        expect(
          (await tester.receipts(ui, 'focus.start')).length,
          commandsBefore,
        );
        expect(await tester.receipts(ui, 'focus.pause'), isEmpty);
      },
    );

    testWidgets('a three hour session counts down as H:MM:SS', (tester) async {
      final ui = await createFocusUi(tester);
      await tester.startFocus(ui, plannedSeconds: 10800);
      await openSession(tester, ui);
      expect(find.text('3:00:00'), findsOneWidget);
      expect(find.text('verbleibend von 3:00:00'), findsOneWidget);
      await tester.tick(ui, 1);
      expect(find.text('2:59:59'), findsOneWidget);
      await tester.tick(ui, 10798);
      expect(find.text('00:01'), findsOneWidget);
    });

    testWidgets('the ring shows the elapsed share', (tester) async {
      final ui = await createFocusUi(tester);
      await tester.startFocus(ui);
      await openSession(tester, ui);
      await tester.tick(ui, 375);
      final ring = tester.widget<ProgressRing>(find.byType(ProgressRing));
      expect(ring.value, closeTo(0.25, 0.0001));
    });
  });

  group('pause and resume', () {
    testWidgets(
      'pause freezes the display and persists the time so far (AT16, F01)',
      (tester) async {
        final ui = await createFocusUi(tester);
        final id = await tester.startFocus(ui);
        await openSession(tester, ui);
        await tester.tick(ui, 888);
        expect(find.text('10:12'), findsOneWidget);

        await tester.tapAndSettleDb(pause);

        final row = (await tester.focusRows(ui)).single;
        expect(row.id, id);
        expect(row.status, 'paused');
        expect(row.accumulatedSeconds, 888);
        expect(row.segmentStartedAtUtc, isNull);
        expect(find.text('Pausiert · Lernen'), findsOneWidget);
        expect(find.text('10:12'), findsOneWidget);
        expect(find.text('gerade pausiert'), findsOneWidget);
        expect(
          find.text('Pausierte Zeit zählt nicht zur Fokuszeit.'),
          findsOneWidget,
        );
        expect(resume, findsOneWidget);
        expect(end, findsOneWidget);
        expect(pause, findsNothing);
        // Foreground time that passes while paused changes nothing.
        ui.advance(300);
        await tester.pump(const Duration(seconds: 15));
        expect(find.text('10:12'), findsOneWidget);
      },
    );

    testWidgets('the pause text follows the clock in minutes', (tester) async {
      final ui = await createFocusUi(tester);
      await tester.startFocus(ui);
      await openSession(tester, ui);
      await tester.tick(ui, 100);
      await tester.tapAndSettleDb(pause);
      expect(find.text('gerade pausiert'), findsOneWidget);
      ui.advance(125);
      await tester.pump(const Duration(seconds: 15));
      expect(find.text('pausiert seit 2 Min.'), findsOneWidget);
      ui.advance(3600);
      await tester.pump(const Duration(seconds: 15));
      expect(find.text('pausiert seit 1 Std. 2 Min.'), findsOneWidget);
    });

    testWidgets(
      'resume continues from the persisted time; the pause does not count (AT16, F01)',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.startFocus(ui);
        await openSession(tester, ui);
        await tester.tick(ui, 888);
        await tester.tapAndSettleDb(pause);
        ui.advance(300); // a five minute pause
        await tester.pump(const Duration(seconds: 15));

        await tester.tapAndSettleDb(resume);

        var row = (await tester.focusRows(ui)).single;
        expect(row.status, 'running');
        expect(row.accumulatedSeconds, 888);
        expect(row.segmentStartedAtUtc, isNotNull);
        expect(find.text('Läuft · Lernen'), findsOneWidget);
        expect(find.text('10:12'), findsOneWidget);
        await tester.tick(ui, 12);
        expect(find.text('10:00'), findsOneWidget);
        expect(row.rowVersion, 3, reason: 'start, pause, resume');
        row = (await tester.focusRows(ui)).single;
        expect(row.accumulatedSeconds, 888, reason: 'ticks are not persisted');
      },
    );

    testWidgets(
      'a failed pause leaves the session running and can be retried (AT27, AT12)',
      (tester) async {
        late FlakyFocusRepository flaky;
        final ui = await createFocusUi(
          tester,
          overrides: [flakyFocusRepository((r) => flaky = r, pauseFailures: 1)],
        );
        await tester.startFocus(ui);
        await openSession(tester, ui);
        await tester.tick(ui, 100);

        await tester.tapAndSettleDb(pause);
        expect((await tester.focusRows(ui)).single.status, 'running');
        expect(find.text('Läuft · Lernen'), findsOneWidget);
        expect(
          ui.feedback.last!.message,
          'Pausieren fehlgeschlagen. Die Sitzung läuft weiter.',
        );

        ui.feedback.last!.onRetry!();
        await tester.settleDb();
        expect((await tester.focusRows(ui)).single.status, 'paused');
        expect(flaky.pauseIds, hasLength(2));
        expect(flaky.pauseIds.first, flaky.pauseIds.last);
      },
    );
  });

  group('awaiting confirmation', () {
    testWidgets(
      'zero turns the display into the confirmation, exactly once, with no XP and no completed time yet (AT17, F01, G01)',
      (tester) async {
        final ui = await createFocusUi(tester, realProjection: true);
        await tester.startFocus(ui);
        await openSession(tester, ui);
        await tester.tick(ui, 1499);
        expect(find.text('00:01'), findsOneWidget);
        await tester.tick(ui, 1);
        await tester.settleDb();

        expect(find.text('Geschafft!'), findsOneWidget);
        expect(find.text('25:00'), findsOneWidget);
        expect(find.text('Lernen abgeschlossen'), findsOneWidget);
        expect(save, findsOneWidget);
        expect(find.text('Verwerfen'), findsOneWidget);
        expect(pause, findsNothing);
        final row = (await tester.focusRows(ui)).single;
        expect(row.status, 'awaiting_confirmation');
        expect(row.endedAtUtc, isNull, reason: 'no completion time yet');
        expect(row.completedLocalDate, isNull);
        expect(
          await tester.xpAwards(ui),
          isEmpty,
          reason: 'no XP before saving',
        );
        expect(
          await tester.receipts(ui, 'focus.await_confirmation'),
          hasLength(1),
        );
        // Further ticks do not write again.
        ui.ticker.emitSeconds(1600);
        await tester.settleDb();
        expect(
          await tester.receipts(ui, 'focus.await_confirmation'),
          hasLength(1),
        );
      },
    );

    testWidgets(
      'a session that ran out while the app was closed asks for confirmation after the restart: no XP, no completed time (AT17, F01, G01)',
      (tester) async {
        var ui = await createFocusUi(tester, realProjection: true);
        await tester.startFocus(ui);
        ui.advance(1700); // the process is dead for 28 minutes

        ui = ui.restarted();
        await openSession(tester, ui);
        await restoreFocus(tester, ui); // what the shell does on bootstrap

        expect(find.text('Geschafft!'), findsOneWidget);
        expect(find.text('25:00'), findsOneWidget);
        expect(find.text('+10 XP beim Speichern'), findsOneWidget);
        expect(
          find.text(
            'Speichern zählt 25 Min. zu deinem Tagesziel (0 → 25 von 25 Min.).',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Die Zeit zählt erst, wenn du die Sitzung speicherst.'),
          findsOneWidget,
        );
        final row = (await tester.focusRows(ui)).single;
        expect(row.status, 'awaiting_confirmation');
        expect(row.endedAtUtc, isNull);
        expect(row.completedLocalDate, isNull);
        expect(row.accumulatedSeconds, 1500, reason: 'limited to the plan');
        expect(await tester.xpAwards(ui), isEmpty);
      },
    );

    testWidgets(
      'saving twice gives ONE completion and one XP award (AT17, AT12, G01)',
      (tester) async {
        final ui = await createFocusUi(tester, realProjection: true);
        await tester.startFocus(ui);
        ui.advance(1600);
        await openSession(tester, ui);
        await restoreFocus(tester, ui);

        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.tap(save);
        await tester.settleDb();

        final rows = await tester.focusRows(ui);
        expect(rows, hasLength(1));
        expect(rows.single.status, 'completed');
        expect(rows.single.accumulatedSeconds, 1500);
        expect(rows.single.endedAtUtc, isNotNull);
        expect(rows.single.completedLocalDate, LocalDate(2026, 10, 3));
        expect(rows.single.gamificationEligible, isTrue);
        expect(await tester.receipts(ui, 'focus.save'), hasLength(1));
        final awards = await tester.xpAwards(ui);
        expect(awards, hasLength(1));
        expect(awards.single.sourceKind, 'focus');
        expect(awards.single.points, 10);
        expect(
          ui.feedback.events.where((e) => e.kind == 'saved'),
          hasLength(1),
        );
        expect(ui.feedback.last!.message, 'Sitzung gespeichert');
        expect(ui.feedback.last!.undo, isNotNull);
        expect(find.text('HOME-STUB'), findsOneWidget, reason: 'screen left');
      },
    );

    testWidgets('the undo of a save reopens the session without XP', (
      tester,
    ) async {
      final ui = await createFocusUi(tester, realProjection: true);
      await tester.startFocus(ui);
      ui.advance(1600);
      await openSession(tester, ui);
      await restoreFocus(tester, ui);
      await tester.tapAndSettleDb(save);
      expect(await tester.xpAwards(ui), hasLength(1));

      final result = await tester.runAsync(
        () => ui.feedback.last!.undo!.perform(),
      );
      await tester.settleDb();
      expect(result, UndoResult.undone);
      expect(
        (await tester.focusRows(ui)).single.status,
        'awaiting_confirmation',
      );
      expect(await tester.xpAwards(ui), isEmpty);
    });

    testWidgets(
      '"Verwerfen" asks first: cancel keeps it, confirm discards (AT18)',
      (tester) async {
        final ui = await createFocusUi(tester, realProjection: true);
        await tester.startFocus(ui);
        ui.advance(1600);
        await openSession(tester, ui);
        await restoreFocus(tester, ui);

        await tester.tap(find.text('Verwerfen'));
        await tester.pumpAndSettle();
        expect(find.text('Sitzung verwerfen?'), findsOneWidget);
        await tester.tap(find.text('Abbrechen'));
        await tester.pumpAndSettle();
        expect(find.text('Sitzung verwerfen?'), findsNothing);
        expect(
          (await tester.focusRows(ui)).single.status,
          'awaiting_confirmation',
        );

        await tester.tap(find.text('Verwerfen'));
        await tester.pumpAndSettle();
        await tester.tapAndSettleDb(find.text('Verwerfen').last);
        final row = (await tester.focusRows(ui)).single;
        expect(row.status, 'discarded');
        expect(row.completedLocalDate, isNull, reason: 'no completed time');
        expect(await tester.xpAwards(ui), isEmpty);
        expect(ui.feedback.last!.message, 'Sitzung verworfen');
        expect(ui.feedback.last!.undo, isNotNull);
      },
    );

    testWidgets(
      'a failed save keeps the session, retries with the same command id and saves once (AT27, AT12)',
      (tester) async {
        final projection = RecordingProjectionSynchronizer();
        final ui = await createFocusUi(tester, projection: projection);
        await tester.startFocus(ui);
        ui.advance(1600);
        await openSession(tester, ui);
        await restoreFocus(tester, ui);
        expect(find.text('Geschafft!'), findsOneWidget);

        projection.failure = StateError('disk full');
        final before = ui.ids.issued.length;
        await tester.tapAndSettleDb(save);

        expect(
          (await tester.focusRows(ui)).single.status,
          'awaiting_confirmation',
        );
        expect(ui.feedback.last!.kind, 'error');
        expect(
          ui.feedback.last!.message,
          'Speichern fehlgeschlagen. Deine Sitzung bleibt erhalten.',
        );
        expect(
          find.text('Geschafft!'),
          findsOneWidget,
          reason: 'screen unchanged',
        );
        expect(save, findsOneWidget, reason: 'retry possible');
        expect(await tester.receipts(ui, 'focus.save'), isEmpty);
        final firstId = ui.ids.issued[before];

        projection.failure = null;
        ui.feedback.last!.onRetry!();
        await tester.settleDb();
        final rows = await tester.focusRows(ui);
        expect(rows.single.status, 'completed');
        final receipts = await tester.receipts(ui, 'focus.save');
        expect(receipts, hasLength(1));
        expect(receipts.single.commandId, firstId, reason: 'same command id');
      },
    );

    testWidgets(
      'midnight: a session confirmed after midnight counts on the confirmation day and is not split (AT25, F01)',
      (tester) async {
        // 23:50 in Berlin on 2026-10-03; the 25 minutes end at 00:15 on the 4th.
        final ui = await createFocusUi(
          tester,
          nowIso: '2026-10-03T21:50:00Z',
          realProjection: true,
        );
        await tester.startFocus(ui);
        await openSession(tester, ui);
        await tester.tick(ui, 1500);
        await tester.settleDb();
        ui.container.read(todayProvider.notifier).refresh(); // the day changed
        await tester.settleDb();
        expect(find.text('Geschafft!'), findsOneWidget);
        expect(
          find.text(
            'Speichern zählt 25 Min. zu deinem Tagesziel (0 → 25 von 25 Min.).',
          ),
          findsOneWidget,
          reason: 'the new day is the one that counts',
        );

        await tester.tapAndSettleDb(save);
        final row = (await tester.focusRows(ui)).single;
        expect(row.status, 'completed');
        expect(row.completedLocalDate, LocalDate(2026, 10, 4));
        expect(row.accumulatedSeconds, 1500, reason: 'not split at midnight');
        final awards = await tester.xpAwards(ui);
        expect(awards.single.localDate, LocalDate(2026, 10, 4));
        final onTheThird = await tester.runAsync(
          () => ui.focusRepository.fetchHistory(limit: 10),
        );
        expect(onTheThird!.single.completedLocalDate, LocalDate(2026, 10, 4));
      },
    );
  });

  group('ending early', () {
    Future<void> endWithSeconds(
      WidgetTester tester,
      FocusUi ui,
      int seconds,
    ) async {
      await tester.startFocus(ui);
      await openSession(tester, ui);
      if (seconds > 0) {
        await tester.tick(ui, seconds);
      }
      await tester.tap(end);
      await tester.pumpAndSettle();
    }

    testWidgets(
      'under five minutes: the time is saved, no XP (299 seconds; AT18, G01)',
      (tester) async {
        final ui = await createFocusUi(tester, realProjection: true);
        await endWithSeconds(tester, ui, 299);
        expect(find.text('Sitzung beenden?'), findsOneWidget);
        expect(find.textContaining('Bisher 04:59 von 25:00.'), findsOneWidget);
        expect(
          find.text(
            'Unter 5 Minuten: Die Zeit wird gespeichert, es gibt keine XP.',
          ),
          findsOneWidget,
        );
        await tester.tapAndSettleDb(find.text('Zeit speichern'));

        final row = (await tester.focusRows(ui)).single;
        expect(row.status, 'completed');
        expect(row.accumulatedSeconds, 299, reason: 'the time is there');
        expect(await tester.xpAwards(ui), isEmpty, reason: 'but no XP');
        expect(ui.feedback.last!.message, 'Sitzung gespeichert');
      },
    );

    testWidgets('exactly five minutes earns the XP (300 seconds; AT18, G01)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester, realProjection: true);
      await endWithSeconds(tester, ui, 300);
      expect(find.text('+10 XP beim Speichern'), findsOneWidget);
      await tester.tapAndSettleDb(find.text('Zeit speichern'));
      final row = (await tester.focusRows(ui)).single;
      expect(row.accumulatedSeconds, 300);
      final awards = await tester.xpAwards(ui);
      expect(awards, hasLength(1));
      expect(awards.single.points, 10);
    });

    testWidgets('one second is the shortest session that can be saved (F01)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester, realProjection: true);
      await endWithSeconds(tester, ui, 1);
      expect(find.text('Zeit speichern'), findsOneWidget);
      await tester.tapAndSettleDb(find.text('Zeit speichern'));
      expect((await tester.focusRows(ui)).single.accumulatedSeconds, 1);
    });

    testWidgets('below one second saving is not offered, discarding is (F01)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await endWithSeconds(tester, ui, 0);
      expect(find.text('Zeit speichern'), findsNothing);
      expect(find.textContaining('zu kurz zum Speichern'), findsOneWidget);
      expect(find.text('Verwerfen'), findsOneWidget);
      expect(find.text('Weiter fokussieren'), findsOneWidget);
    });

    testWidgets(
      'discarding leaves no completed time and no XP, the undo reopens the session (AT18, G01)',
      (tester) async {
        final ui = await createFocusUi(tester, realProjection: true);
        await endWithSeconds(tester, ui, 900);
        await tester.tapAndSettleDb(find.text('Verwerfen'));

        final row = (await tester.focusRows(ui)).single;
        expect(row.status, 'discarded');
        expect(row.completedLocalDate, isNull);
        expect(row.endedAtUtc, isNull);
        expect(await tester.xpAwards(ui), isEmpty);
        expect(ui.feedback.last!.message, 'Sitzung verworfen');
        expect(find.text('HOME-STUB'), findsOneWidget);
        final today = await tester.runAsync(
          () =>
              ui.focusRepository.watchCompletedOn(LocalDate(2026, 10, 3)).first,
        );
        expect(today, isEmpty, reason: 'a discarded session is no focus time');

        await tester.runAsync(() => ui.feedback.last!.undo!.perform());
        final open = await tester.runAsync(() => ui.focusRepository.findOpen());
        expect(open, isNotNull, reason: 'the undo opens it again');
      },
    );

    testWidgets('"Weiter fokussieren" changes nothing', (tester) async {
      final ui = await createFocusUi(tester);
      await endWithSeconds(tester, ui, 600);
      await tester.tap(find.text('Weiter fokussieren'));
      await tester.pumpAndSettle();
      expect(find.text('Sitzung beenden?'), findsNothing);
      final row = (await tester.focusRows(ui)).single;
      expect(row.status, 'running');
      expect(row.rowVersion, 1);
      expect(find.text('Läuft · Lernen'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
    });

    testWidgets('the system back button closes the sheet', (tester) async {
      final ui = await createFocusUi(tester);
      await endWithSeconds(tester, ui, 600);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Sitzung beenden?'), findsNothing);
      expect((await tester.focusRows(ui)).single.status, 'running');
    });

    testWidgets('a paused session can be ended the same way (AT16)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester, realProjection: true);
      await tester.startFocus(ui);
      await openSession(tester, ui);
      await tester.tick(ui, 600);
      await tester.tapAndSettleDb(pause);
      await tester.tap(end);
      await tester.pumpAndSettle();
      expect(find.textContaining('Bisher 10:00 von 25:00.'), findsOneWidget);
      await tester.tapAndSettleDb(find.text('Zeit speichern'));
      expect((await tester.focusRows(ui)).single.accumulatedSeconds, 600);
    });
  });

  group('clock, restart and resume', () {
    testWidgets('the display ignores a wall clock jump forward (F01, AT25)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await tester.startFocus(ui);
      await openSession(tester, ui);
      await tester.tick(ui, 10);
      expect(find.text('24:50'), findsOneWidget);

      ui.advance(3600); // the user sets the clock one hour ahead
      await tester.tick(ui, 5);
      expect(
        find.text('24:45'),
        findsOneWidget,
        reason: 'monotonic time rules',
      );
      expect(find.text('Läuft · Lernen'), findsOneWidget);
      expect(find.textContaining('Uhr des Geräts'), findsNothing);
    });

    testWidgets(
      'daylight saving time ends during a session: 25 real minutes are counted and the end shows the new wall clock (AT25, F01)',
      (tester) async {
        // 02:50 CEST on 2026-10-25; at 03:00 the clocks go back to 02:00.
        final ui = await createFocusUi(tester, nowIso: '2026-10-25T00:50:00Z');
        await tester.startFocus(ui);
        await openSession(tester, ui);
        await tester.tick(ui, 600); // 03:00 CEST = 02:00 CET
        expect(find.text('15:00'), findsOneWidget);
        await tester.tick(ui, 900);
        await tester.settleDb();

        expect(find.text('Geschafft!'), findsOneWidget);
        await tester.tapAndSettleDb(save);
        final row = (await tester.focusRows(ui)).single;
        expect(row.accumulatedSeconds, 1500);
        expect(row.completedLocalDate, LocalDate(2026, 10, 25));
        // 01:15 UTC is 02:15 CET: the wall clock went back, the time did not.
        await pumpFocusApp(tester, ui, initialLocation: '/focus/history');
        expect(find.text('02:15 · abgeschlossen'), findsOneWidget);
      },
    );

    testWidgets(
      'a clock set back shows the hint and the display keeps counting (F01, AT25)',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.startFocus(ui);
        await openSession(tester, ui);
        await tester.tick(ui, 10);
        expect(find.textContaining('Uhr des Geräts'), findsNothing);

        ui.advance(-7200); // two hours back
        await tester.tick(ui, 1);
        expect(find.text('24:49'), findsOneWidget);
        expect(
          find.text(
            'Die Uhr des Geräts wurde zurückgestellt. Bitte prüfe die '
            'Sitzungsdauer.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('a segment that starts in the future counts as zero with the '
        'hint (F01)', (tester) async {
      final ui = await createFocusUi(tester);
      await tester.startFocus(ui);
      ui.advance(-3600);
      await openSession(tester, ui);
      expect(find.text('25:00'), findsOneWidget);
      expect(find.textContaining('Uhr des Geräts'), findsOneWidget);
    });

    testWidgets(
      'a restart restores the remaining time from the persisted segments (AT16, F01)',
      (tester) async {
        var ui = await createFocusUi(tester);
        await tester.startFocus(ui);
        ui.advance(600);
        final version = (await tester.focusRows(ui)).single.rowVersion;

        ui = ui.restarted();
        await openSession(tester, ui);
        await restoreFocus(tester, ui);

        expect(find.text('Läuft · Lernen'), findsOneWidget);
        expect(find.text('15:00'), findsOneWidget);
        expect(find.text('verbleibend von 25:00'), findsOneWidget);
        expect(
          (await tester.focusRows(ui)).single.rowVersion,
          version,
          reason: 'restoring a running session writes nothing',
        );
        await tester.tick(ui, 30);
        expect(find.text('14:30'), findsOneWidget);
      },
    );

    testWidgets('a paused session survives a restart unchanged (AT16)', (
      tester,
    ) async {
      var ui = await createFocusUi(tester);
      await tester.startFocus(ui);
      await openSession(tester, ui);
      await tester.tick(ui, 600);
      await tester.tapAndSettleDb(pause);
      await closeApp(tester);
      ui.advance(5400); // the app stays closed for 90 minutes

      ui = ui.restarted();
      await openSession(tester, ui);
      await restoreFocus(tester, ui);
      expect(find.text('Pausiert · Lernen'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('pausiert seit 1 Std. 30 Min.'), findsOneWidget);
    });

    testWidgets(
      'after the app was in the background the display is re-based (AT16, F01)',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.startFocus(ui);
        await openSession(tester, ui);
        await tester.tick(ui, 60);
        expect(find.text('24:00'), findsOneWidget);

        ui.advance(300); // the device slept, the monotonic clock stood still
        await resumeApp(tester);
        expect(find.text('19:00'), findsOneWidget);
        await tester.tick(ui, 10);
        expect(find.text('18:50'), findsOneWidget);
      },
    );

    testWidgets(
      'a session that ran out in the background asks for confirmation on resume (AT17)',
      (tester) async {
        final ui = await createFocusUi(tester, realProjection: true);
        await tester.startFocus(ui);
        await openSession(tester, ui);
        await tester.tick(ui, 60);

        ui.advance(1700);
        await resumeApp(tester);
        expect(find.text('Geschafft!'), findsOneWidget);
        expect(
          (await tester.focusRows(ui)).single.status,
          'awaiting_confirmation',
        );
        expect(await tester.xpAwards(ui), isEmpty);
      },
    );
  });

  group('states', () {
    testWidgets('without an open session the screen offers to start one', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      final router = await openSession(tester, ui);
      expect(find.text('Keine laufende Sitzung'), findsOneWidget);
      expect(pause, findsNothing);
      expect(save, findsNothing);
      await tester.tap(find.text('Fokus starten'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/focus');
      expect(find.byType(ProgressRing), findsOneWidget);
    });

    testWidgets('loading shows a neutral text', (tester) async {
      final never = StreamController<FocusCountdown?>();
      addTearDown(never.close);
      final ui = await createFocusUi(
        tester,
        overrides: [focusCountdownProvider.overrideWith((ref) => never.stream)],
      );
      await openSession(tester, ui);
      expect(find.text('Wird geladen …'), findsOneWidget);
      expect(pause, findsNothing);
    });

    testWidgets('an error offers a retry that reads again', (tester) async {
      var attempts = 0;
      final ui = await createFocusUi(
        tester,
        overrides: [
          focusCountdownProvider.overrideWith((ref) {
            attempts++;
            return attempts == 1
                ? Stream<FocusCountdown?>.error(const StorageFailure())
                : Stream<FocusCountdown?>.value(null);
          }),
        ],
      );
      await openSession(tester, ui);
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Keine laufende Sitzung'), findsOneWidget);
    });

    testWidgets('the screen does not flash "no session" while it closes', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await tester.startFocus(ui);
      ui.advance(1600);
      await openSession(tester, ui);
      await restoreFocus(tester, ui);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Keine laufende Sitzung'), findsNothing);
      await tester.settleDb();
      expect(find.text('Keine laufende Sitzung'), findsNothing);
      expect(find.text('HOME-STUB'), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets(
      'the countdown is not announced every second, state changes are (F01, AT34)',
      (tester) => withSemantics(tester, () async {
        final ui = await createFocusUi(tester);
        await tester.startFocus(ui);
        await openSession(tester, ui);

        final before = liveRegionLabels(tester);
        expect(before, ['Läuft · Lernen'], reason: 'only the state is live');
        expect(
          find.bySemanticsLabel(
            'Fokus läuft, Lernen. Noch 25 Minuten von 25 Minuten.',
          ),
          findsOneWidget,
        );
        for (var i = 0; i < 120; i++) {
          await tester.tick(ui, 1);
        }
        expect(
          liveRegionLabels(tester),
          before,
          reason: 'two minutes of ticks announce nothing new',
        );
        // The ring text itself follows the time and is read when focused.
        expect(
          find.bySemanticsLabel(
            'Fokus läuft, Lernen. Noch 23 Minuten von 25 Minuten.',
          ),
          findsOneWidget,
        );

        await tester.tapAndSettleDb(pause);
        expect(liveRegionLabels(tester), ['Pausiert · Lernen']);
      }),
    );

    testWidgets(
      'every action has a label and a 48 px target in every state (AT33)',
      (tester) => withSemantics(tester, () async {
        final ui = await createFocusUi(tester);
        await tester.startFocus(ui);
        await openSession(tester, ui);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(find.bySemanticsLabel('Sitzung beenden'), findsOneWidget);
        expect(find.bySemanticsLabel('Zurück'), findsOneWidget);

        await tester.tapAndSettleDb(pause);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        await tester.tapAndSettleDb(resume);
        ui.advance(1600);
        await resumeApp(tester);
        expect(find.text('Geschafft!'), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }),
    );
  });
}
