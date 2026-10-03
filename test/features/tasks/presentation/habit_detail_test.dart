import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/task_test_support.dart';
import '../support/ui_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  final today = LocalDate(2026, 10, 3);

  /// A habit that started on 2026-09-20 and is checked on 22, 23, 24
  /// September and on 1, 2 and 3 October (series 3, 6 of 14 days).
  Future<(TasksUiEnv, String)> envWithHistory(WidgetTester tester) async {
    final env = await createTasksUiEnv(tester);
    env.moveTo(LocalDate(2026, 9, 20));
    final id = await env.addHabit(tester, 'Lesen');
    for (final date in [
      LocalDate(2026, 9, 22),
      LocalDate(2026, 9, 23),
      LocalDate(2026, 9, 24),
      LocalDate(2026, 10, 1),
      LocalDate(2026, 10, 2),
      today,
    ]) {
      env.moveTo(date);
      await env.checkHabit(tester, id, date);
    }
    env.moveTo(today);
    return (env, id);
  }

  Future<GoRouter> openDetail(
    WidgetTester tester,
    TasksUiEnv env,
    String id,
  ) async {
    final router = await pumpTasksRouter(tester, env);
    unawaited(router.push('/habits/$id'));
    await tester.pumpAndSettle();
    await pumpData(tester);
    return router;
  }

  Future<void> waitForFeedback(
    WidgetTester tester,
    TasksUiEnv env, [
    int count = 1,
  ]) async {
    await tester.pumpUntil(() => env.feedback.events.length >= count);
    await tester.pumpAndSettle();
    await pumpData(tester);
  }

  final cellPattern = RegExp(r'^(Heute, )?[A-Z][a-z]\., \d\d\.\d\d\.: ');

  testWidgets('shows the series, the checked days and the quota of the last '
      '30 days (T02)', (tester) async {
    final handle = tester.ensureSemantics();
    final (env, id) = await envWithHistory(tester);
    await openDetail(tester, env, id);

    expect(find.text('Lesen'), findsWidgets);
    expect(find.bySemanticsLabel('3 Tage in Folge'), findsOneWidget);
    expect(find.text('Tage Serie'), findsOneWidget);
    expect(find.text('6 / 14'), findsOneWidget);
    expect(find.text('Tage erfüllt'), findsOneWidget);
    expect(find.text('43 %'), findsOneWidget);
    expect(find.text('Quote'), findsOneWidget);
    expect(find.text('Längste Serie: 3 Tage'), findsOneWidget);
    expect(find.text('Keine Erinnerung'), findsOneWidget);
    expect(find.text('Letzte 30 Tage'), findsOneWidget);
    expect(find.text('4. Sep. – 3. Okt.'), findsOneWidget);
    expect(find.bySemanticsLabel(cellPattern), findsNWidgets(30));
    expect(
      find.bySemanticsLabel('Heute, Sa., 03.10.: erledigt, zum Ändern tippen'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('So., 20.09.: offen, zum Ändern tippen'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('a past day is corrected with a tap and the undo restores it '
      '(AT23, G01, G02)', (tester) async {
    final handle = tester.ensureSemantics();
    final (env, id) = await envWithHistory(tester);
    await openDetail(tester, env, id);
    final xpBefore = await tester.runAsync(env.harness.totalXp);
    final day = LocalDate(2026, 9, 25);

    await tester.tap(
      find.bySemanticsLabel('Fr., 25.09.: offen, zum Ändern tippen'),
    );
    await waitForFeedback(tester, env);

    expect(env.feedback.last!.message, 'Abgehakt');
    expect(
      await tester.runAsync(() => env.habits.findCheck(id, day)),
      isNotNull,
    );
    expect(find.text('7 / 14'), findsOneWidget);
    expect(find.text('50 %'), findsOneWidget);
    expect(await tester.runAsync(env.harness.totalXp), xpBefore! + 5);
    // 22, 23, 24 and 25 September form a series of four days now.
    expect(find.text('Längste Serie: 4 Tage'), findsOneWidget);

    await tester.runAsync(env.feedback.last!.undo!.perform);
    await pumpData(tester);
    expect(await tester.runAsync(() => env.habits.findCheck(id, day)), isNull);
    expect(find.text('6 / 14'), findsOneWidget);
    expect(await tester.runAsync(env.harness.totalXp), xpBefore);
    expect(find.text('Längste Serie: 3 Tage'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('tapping a checked day removes the check and can be undone '
      '(AT23)', (tester) async {
    final handle = tester.ensureSemantics();
    final (env, id) = await envWithHistory(tester);
    await openDetail(tester, env, id);
    final day = LocalDate(2026, 9, 23);

    await tester.tap(
      find.bySemanticsLabel('Mi., 23.09.: erledigt, zum Ändern tippen'),
    );
    await waitForFeedback(tester, env);

    expect(env.feedback.last!.message, 'Haken entfernt');
    expect(await tester.runAsync(() => env.habits.findCheck(id, day)), isNull);
    expect(find.text('5 / 14'), findsOneWidget);

    await tester.runAsync(env.feedback.last!.undo!.perform);
    await pumpData(tester);
    expect(
      await tester.runAsync(() => env.habits.findCheck(id, day)),
      isNotNull,
    );
    handle.dispose();
  });

  testWidgets('days before the start cannot be changed (T02, C08)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final (env, id) = await envWithHistory(tester);
    await openDetail(tester, env, id);

    final before = find.bySemanticsLabel('Sa., 19.09.: noch nicht begonnen');
    expect(before, findsOneWidget);
    await tester.tap(before, warnIfMissed: false);
    await tester.pump();

    expect(env.feedback.events, isEmpty);
    expect(env.habits.commandIds, isEmpty);
    handle.dispose();
  });

  testWidgets('days from the archive date on cannot be changed (AT21, C08)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final (env, id) = await envWithHistory(tester);
    await tester.runAsync(
      () => env.habits.archive(commandId: env.harness.ids.newId(), id: id),
    );
    env.habits.commandIds.clear();
    env.moveTo(today.addDays(2));
    await openDetail(tester, env, id);

    expect(find.bySemanticsLabel('So., 04.10.: archiviert'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Heute, Mo., 05.10.: archiviert'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Sa., 03.10.: erledigt, zum Ändern tippen'),
      findsOneWidget,
      reason: 'the last day of the habit can still be corrected',
    );
    await tester.tap(
      find.bySemanticsLabel('So., 04.10.: archiviert'),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(env.habits.commandIds, isEmpty);
    handle.dispose();
  });

  testWidgets('the list view shows every day in words with a checkbox '
      '(AT23)', (tester) async {
    final handle = tester.ensureSemantics();
    final (env, id) = await envWithHistory(tester);
    await openDetail(tester, env, id);

    await tester.tap(find.text('Als Liste'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Als Raster'), findsOneWidget);
    expect(find.text('Heute, Sa., 3. Okt.'), findsOneWidget);
    expect(find.text('erledigt'), findsNWidgets(6));
    expect(find.text('offen'), findsNWidgets(8));
    expect(find.text('noch nicht begonnen'), findsNWidgets(16));
    expect(find.byType(RoundCheckbox), findsNWidgets(14));

    await tester.ensureVisible(find.bySemanticsLabel('Fr., 25. Sep.'));
    await tester.tap(find.bySemanticsLabel('Fr., 25. Sep.'));
    await waitForFeedback(tester, env);
    expect(env.feedback.last!.message, 'Abgehakt');
    expect(find.text('erledigt'), findsNWidgets(7));

    await tester.ensureVisible(find.text('Als Raster'));
    await tester.tap(find.text('Als Raster'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Als Liste'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a double tap on a day checks it once (AT12, C05)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final (env, id) = await envWithHistory(tester);
    await openDetail(tester, env, id);
    final gate = Completer<void>();
    env.habits.gate = gate;
    final cell = find.bySemanticsLabel('Fr., 25.09.: offen, zum Ändern tippen');

    await tester.tap(cell);
    await tester.pump();
    await tester.tap(cell, warnIfMissed: false);
    await tester.pump();
    gate.complete();
    await waitForFeedback(tester, env);

    expect(env.habits.commandIds, hasLength(1));
    expect(env.feedback.events, hasLength(1));
    expect(find.text('7 / 14'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a failed check keeps the day; the retry reuses the command id '
      '(AT27, AT12)', (tester) async {
    final handle = tester.ensureSemantics();
    final (env, id) = await envWithHistory(tester);
    await openDetail(tester, env, id);
    env.habits.failNext = 1;

    await tester.tap(
      find.bySemanticsLabel('Fr., 25.09.: offen, zum Ändern tippen'),
    );
    await waitForFeedback(tester, env);
    final error = env.feedback.last!;
    expect(error.kind, 'error');
    expect(find.text('6 / 14'), findsOneWidget);

    error.onRetry!();
    await waitForFeedback(tester, env, 2);

    expect(env.habits.commandIds[0], env.habits.commandIds[1]);
    expect(find.text('7 / 14'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('archiving asks first, says "Ab morgen archiviert" and offers no '
      'undo (AT21, AT24)', (tester) async {
    final (env, id) = await envWithHistory(tester);
    await openDetail(tester, env, id);

    await tester.tap(find.text('Archivieren'));
    await tester.pumpAndSettle();
    expect(find.text('Gewohnheit archivieren?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect((await env.readHabit(tester, id))!.archivedFrom, isNull);
    expect(env.feedback.events, isEmpty);

    await tester.tap(find.text('Archivieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archivieren').last);
    await tester.pumpAndSettle();
    await waitForFeedback(tester, env);

    expect(env.feedback.last!.message, 'Ab morgen archiviert');
    expect(env.feedback.last!.undo, isNull);
    expect((await env.readHabit(tester, id))!.archivedFrom, today.addDays(1));
    expect(find.text('Ab morgen archiviert'), findsOneWidget);
    expect(find.text('Archivieren'), findsNothing);
    expect(find.text('Bearbeiten'), findsOneWidget);
    // Today still counts: the checks stay editable.
    expect(find.text('6 / 14'), findsOneWidget);
  });

  testWidgets('an archived habit is read only once the archive date is '
      'reached (T02)', (tester) async {
    final handle = tester.ensureSemantics();
    final (env, id) = await envWithHistory(tester);
    await tester.runAsync(
      () => env.habits.archive(commandId: env.harness.ids.newId(), id: id),
    );
    env.moveTo(today.addDays(1));
    await openDetail(tester, env, id);

    expect(find.text('Archiviert'), findsOneWidget);
    expect(find.text('Bearbeiten'), findsNothing);
    expect(find.text('Archivieren'), findsNothing);
    expect(find.bySemanticsLabel('Gewohnheit bearbeiten'), findsNothing);
    expect(find.text('Löschen'), findsOneWidget);
    expect(
      find.text(
        'Diese Gewohnheit ist archiviert und zählt nicht mehr. Der Verlauf '
        'bleibt erhalten.',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('delete asks first, returns to the habits and the undo restores '
      'the same habit (T02, C05)', (tester) async {
    final (env, id) = await envWithHistory(tester);
    final router = await openDetail(tester, env, id);

    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Gewohnheit löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(await env.readHabit(tester, id), isNotNull);

    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen').last);
    await tester.pumpAndSettle();
    await waitForFeedback(tester, env);

    expect(env.feedback.last!.message, 'Gewohnheit gelöscht');
    expect(await env.readHabit(tester, id), isNull);
    expect(locationOf(router), '/habits');
    expect(find.text('Noch keine Gewohnheit'), findsOneWidget);

    await tester.runAsync(env.feedback.last!.undo!.perform);
    await pumpData(tester);
    expect((await env.readHabit(tester, id))!.title, 'Lesen');
    expect(find.text('Lesen'), findsOneWidget);
    expect(await tester.runAsync(env.harness.totalXp), 30);
  });

  testWidgets('the edit buttons open the form of the habit', (tester) async {
    final handle = tester.ensureSemantics();
    final (env, id) = await envWithHistory(tester);
    final router = await openDetail(tester, env, id);

    await tester.tap(find.bySemanticsLabel('Gewohnheit bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.text('Gewohnheit bearbeiten'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    handle.dispose();
  });

  testWidgets('an unknown habit shows the not found state', (tester) async {
    final env = await createTasksUiEnv(tester);
    final router = await pumpTasksRouter(tester, env);
    unawaited(router.push('/habits/gibt-es-nicht'));
    await tester.pumpAndSettle();
    await pumpData(tester);

    expect(find.text('Gewohnheit nicht gefunden'), findsOneWidget);
    expect(find.text('Zu den Gewohnheiten'), findsOneWidget);
  });

  testWidgets('a habit without history yet shows empty numbers, not invented '
      'ones', (tester) async {
    final env = await createTasksUiEnv(tester);
    final id = await env.addHabit(tester, 'Neu');
    await openDetail(tester, env, id);

    expect(find.text('0 / 1'), findsOneWidget);
    expect(find.text('0 %'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Längste Serie: ', findRichText: true), findsNothing);
    expect(find.text('Noch keine Serie'), findsOneWidget);
    expect(find.byType(AppCard), findsWidgets);
  });
}
