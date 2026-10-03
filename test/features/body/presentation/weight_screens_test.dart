import 'dart:async';

import 'dart:ui' show CheckedState;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/presentation/weight_form_screen.dart';
import 'package:self_improvement/features/body/presentation/weight_history_screen.dart';
import 'package:self_improvement/features/body/presentation/weight_overview_screen.dart';
import 'package:self_improvement/features/body/presentation/weight_routes.dart';

import '../../../support/pump_app.dart';

/// Widget tests of the weight screens against a real in-memory database
/// (clock 2026-10-03 10:00 Europe/Berlin).

class _Env {
  _Env({
    required this.harness,
    required this.container,
    required this.feedback,
    required this.projection,
  });

  final DataHarness harness;
  final ProviderContainer container;
  final RecordingFeedbackService feedback;
  final RecordingProjectionSynchronizer projection;
}

Future<_Env> _env(WidgetTester tester) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final projection = RecordingProjectionSynchronizer();
  final harness = (await tester.runAsync(
    () => DataHarness.create(projections: projection),
  ))!;
  addTearDown(() async {
    await tester.runAsync(harness.dispose);
  });
  await tester.runAsync(harness.seedOnboarded);
  final feedback = RecordingFeedbackService(ids: harness.ids);
  final container = harness.createContainer(
    overrides: [feedbackServiceProvider.overrideWithValue(feedback)],
  );
  return _Env(
    harness: harness,
    container: container,
    feedback: feedback,
    projection: projection,
  );
}

List<RouteBase> _routes() => [
  GoRoute(
    path: '/',
    builder: (context, state) =>
        const Scaffold(body: Center(child: Text('Start'))),
  ),
  GoRoute(
    path: WeightRoutes.overview,
    builder: (context, state) => const WeightOverviewScreen(),
  ),
  GoRoute(
    path: WeightRoutes.create,
    builder: (context, state) => const WeightFormScreen(),
  ),
  GoRoute(
    path: WeightRoutes.all,
    builder: (context, state) => const WeightHistoryScreen(),
  ),
  GoRoute(
    path: WeightRoutes.editPattern,
    builder: (context, state) =>
        WeightFormScreen(entryId: state.pathParameters['id']),
  ),
  GoRoute(
    path: '/profile/edit',
    builder: (context, state) =>
        const Scaffold(body: Center(child: Text('Profil bearbeiten'))),
  ),
];

Future<GoRouter> _open(
  WidgetTester tester,
  _Env env,
  String location, {
  Size size = const Size(393, 852),
  double textScale = 1.0,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) => pumpRouterApp(
  tester,
  routes: _routes(),
  initialLocation: location,
  container: env.container,
  size: size,
  textScale: textScale,
  viewInsets: viewInsets,
);

Future<String> _seed(
  WidgetTester tester,
  _Env env, {
  required int grams,
  required String atUtc,
  bool toilet = false,
  bool drinking = false,
  bool eating = false,
  String? note,
}) async {
  final outcome = await tester.runCommand(
    () => env.container
        .read(weightRepositoryProvider)
        .create(
          commandId: env.harness.ids.newId(),
          draft: WeightDraft(
            weightGrams: grams,
            occurredAtUtc: DateTime.parse(atUtc).toUtc(),
            beforeToilet: toilet,
            afterDrinking: drinking,
            afterEating: eating,
            note: note,
          ),
        ),
  );
  return outcome.entityId!;
}

Future<List<WeightEntry>> _active(WidgetTester tester, _Env env) async =>
    (await tester.runAsync(
      () => env.container.read(weightRepositoryProvider).watchActive().first,
    ))!;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.pumpAndSettle();
}

Future<void> _enterWeight(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

PrimaryButton _primaryButton(WidgetTester tester, String label) =>
    tester.widget<PrimaryButton>(find.widgetWithText(PrimaryButton, label));

CheckedState _checkedOf(WidgetTester tester, String title) {
  final tile = find
      .ancestor(of: find.text(title), matching: find.byType(EntryListTile))
      .first;
  return tester.getSemantics(tile).flagsCollection.isChecked;
}

Future<void> _setProfile(
  WidgetTester tester,
  _Env env, {
  int? start,
  int? target,
  int? heightCm,
  int? ageYears,
}) async {
  await tester.runCommand(
    () => env.container
        .read(profileCommandsProvider)
        .update(
          commandId: env.harness.ids.newId(),
          startWeightGrams: start,
          targetWeightGrams: target,
          heightCm: heightCm,
          ageYears: ageYears,
        ),
  );
}

String _minus(String text) => text.replaceAll('-', '−');

void main() {
  group('create form', () {
    for (final typed in ['71,5', '71.5']) {
      testWidgets('saves "$typed" as 71,5 kg and reports it (AT05)', (
        tester,
      ) async {
        final env = await _env(tester);
        await _open(tester, env, WeightRoutes.create);

        await _enterWeight(tester, typed);
        await tester.tap(find.text('Eintrag speichern'));
        await _settle(tester);

        final entries = await _active(tester, env);
        expect(entries, hasLength(1));
        expect(entries.single.weightGrams, 71500);
        expect(env.feedback.last?.kind, 'saved');
        expect(env.feedback.last?.message, 'Gewicht gespeichert');
        expect(env.feedback.last?.undo, isNotNull);
        expect(find.text('Start'), findsOneWidget, reason: 'left the form');
      });
    }

    for (final (typed, message) in [
      ('19,9', 'Bitte gib ein Gewicht zwischen 20,0 und 350,0 kg ein.'),
      ('350,1', 'Bitte gib ein Gewicht zwischen 20,0 und 350,0 kg ein.'),
      (
        '71,55',
        'Bitte gib höchstens eine Nachkommastelle an, zum Beispiel 71,5.',
      ),
    ]) {
      testWidgets('rejects "$typed" next to the field, keeps it (AT05)', (
        tester,
      ) async {
        final env = await _env(tester);
        await _open(tester, env, WeightRoutes.create);

        await _enterWeight(tester, typed);
        await tester.tap(find.text('Eintrag speichern'));
        await _settle(tester);

        expect(find.text(message), findsOneWidget);
        expect(find.widgetWithText(TextField, typed), findsOneWidget);
        expect(await _active(tester, env), isEmpty);
        expect(
          env.feedback.events,
          isEmpty,
          reason: 'the hint stays at the field',
        );

        await _enterWeight(tester, '71,5');
        expect(find.text(message), findsNothing, reason: 'typing clears it');
      });
    }

    testWidgets('empty input and text without digits cannot be saved (AT05)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _open(tester, env, WeightRoutes.create);
      expect(_primaryButton(tester, 'Eintrag speichern').onPressed, isNull);

      await _enterWeight(tester, 'NaN');

      expect(
        find.text('NaN'),
        findsNothing,
        reason: 'letters are filtered out of the field',
      );
      expect(_primaryButton(tester, 'Eintrag speichern').onPressed, isNull);
      expect(await _active(tester, env), isEmpty);
    });

    testWidgets('minus and plus change the value by 0,1 kg', (tester) async {
      final env = await _env(tester);
      await _open(tester, env, WeightRoutes.create);
      await _enterWeight(tester, '71,5');

      await tester.tap(find.bySemanticsLabel('um 0,1 Kilogramm erhöhen'));
      await tester.pump();
      expect(find.widgetWithText(TextField, '71,6'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('um 0,1 Kilogramm verringern'));
      await tester.tap(find.bySemanticsLabel('um 0,1 Kilogramm verringern'));
      await tester.pump();
      expect(find.widgetWithText(TextField, '71,4'), findsOneWidget);
    });

    testWidgets('offers the last value and the change to it', (tester) async {
      final env = await _env(tester);
      await _seed(tester, env, grams: 71800, atUtc: '2026-10-02T06:00:00Z');
      await _open(tester, env, WeightRoutes.create);
      await _settle(tester);

      expect(find.text('Letzten Wert übernehmen (71,8 kg)'), findsOneWidget);
      await _enterWeight(tester, '71,5');
      await _settle(tester);

      expect(find.textContaining(_minus('-0,3 kg')), findsWidgets);
      expect(find.textContaining('seit dem letzten Eintrag'), findsOneWidget);
    });

    testWidgets(
      'saves the conditions, edits them and shows them after a restart (AT06)',
      (tester) async {
        final env = await _env(tester);
        await _open(tester, env, WeightRoutes.create);
        await _enterWeight(tester, '71,5');
        await tester.tap(find.text('Vor dem Klo'));
        await tester.tap(find.text('Nach dem Trinken'));
        await tester.tap(find.text('Nach dem Essen'));
        await tester.pump();
        await tester.tap(find.text('Eintrag speichern'));
        await _settle(tester);

        final saved = (await _active(tester, env)).single;
        expect(saved.beforeToilet, isTrue);
        expect(saved.afterDrinking, isTrue);
        expect(saved.afterEating, isTrue);

        // "Restart": a second container over the same database.
        final restarted = env.harness.createContainer(
          overrides: [feedbackServiceProvider.overrideWithValue(env.feedback)],
        );
        await pumpRouterApp(
          tester,
          routes: _routes(),
          initialLocation: WeightRoutes.edit(saved.id),
          container: restarted,
        );
        await _settle(tester);
        expect(_checkedOf(tester, 'Vor dem Klo'), CheckedState.isTrue);
        expect(_checkedOf(tester, 'Nach dem Essen'), CheckedState.isTrue);

        await tester.tap(find.text('Nach dem Essen'));
        await tester.pump();
        expect(_checkedOf(tester, 'Nach dem Essen'), CheckedState.isFalse);
        await tester.tap(find.text('Änderungen speichern'));
        await _settle(tester);

        final edited = (await _active(tester, env)).single;
        expect(edited.afterEating, isFalse);
        expect(edited.beforeToilet, isTrue);
        expect(env.feedback.last?.message, 'Gewicht aktualisiert');
      },
    );

    testWidgets(
      'the same measuring time offers the existing entry, no second one (AT07)',
      (tester) async {
        final env = await _env(tester);
        await _seed(tester, env, grams: 71800, atUtc: '2026-10-03T08:00:00Z');
        await _open(tester, env, WeightRoutes.create);

        await _enterWeight(tester, '72,0');
        await tester.tap(find.text('Eintrag speichern'));
        await _settle(tester);

        expect(
          find.text('Für diesen Messzeitpunkt gibt es schon einen Eintrag.'),
          findsOneWidget,
        );
        expect(await _active(tester, env), hasLength(1));
        expect(env.feedback.events, isEmpty);

        await tester.tap(find.text('Bestehenden Eintrag bearbeiten'));
        await _settle(tester);
        expect(find.text('Eintrag bearbeiten'), findsWidgets);
        expect(find.widgetWithText(TextField, '71,8'), findsOneWidget);
      },
    );

    testWidgets('another time on the same day is allowed (AT07)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _seed(tester, env, grams: 71800, atUtc: '2026-10-03T06:00:00Z');
      await _open(tester, env, WeightRoutes.create);

      await _enterWeight(tester, '72,0');
      await tester.tap(find.text('Eintrag speichern'));
      await _settle(tester);

      final entries = await _active(tester, env);
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.localDate).toSet(), hasLength(1));
    });

    testWidgets(
      'a failed save keeps the input and the retry stores exactly one entry (AT27)',
      (tester) async {
        final env = await _env(tester);
        env.projection.failure = StateError('disk full');
        await _open(tester, env, WeightRoutes.create);
        await _enterWeight(tester, '71,5');

        await tester.tap(find.text('Eintrag speichern'));
        await _settle(tester);

        expect(await _active(tester, env), isEmpty);
        expect(find.widgetWithText(TextField, '71,5'), findsOneWidget);
        expect(env.feedback.last?.kind, 'error');
        expect(
          env.feedback.last?.message,
          'Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.',
        );
        final retry = env.feedback.last?.onRetry;
        expect(retry, isNotNull);

        env.projection.failure = null;
        await tester.runAsync(() async {
          retry!();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await _settle(tester);

        final entries = await _active(tester, env);
        expect(entries, hasLength(1));
        expect(entries.single.weightGrams, 71500);
        expect(env.feedback.last?.kind, 'saved');
      },
    );

    testWidgets('leaving with unsaved input asks to discard (C05)', (
      tester,
    ) async {
      final env = await _env(tester);
      final router = await _open(tester, env, '/');
      unawaited(router.push(WeightRoutes.create));
      await _settle(tester);
      await _enterWeight(tester, '71,5');

      await tester.tap(find.bySemanticsLabel('Zurück'));
      await _settle(tester);
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);

      await tester.tap(find.text('Weiter bearbeiten'));
      await _settle(tester);
      expect(find.widgetWithText(TextField, '71,5'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Zurück'));
      await _settle(tester);
      await tester.tap(find.text('Verwerfen'));
      await _settle(tester);
      expect(find.text('Start'), findsOneWidget);
      expect(await _active(tester, env), isEmpty);
    });

    testWidgets('a clean form leaves without asking', (tester) async {
      final env = await _env(tester);
      final router = await _open(tester, env, '/');
      unawaited(router.push(WeightRoutes.create));
      await _settle(tester);

      await tester.tap(find.bySemanticsLabel('Zurück'));
      await _settle(tester);

      expect(find.text('Änderungen verwerfen?'), findsNothing);
      expect(find.text('Start'), findsOneWidget);
    });
  });

  group('edit form', () {
    testWidgets('deletes after confirmation and undo restores it (C05)', (
      tester,
    ) async {
      final env = await _env(tester);
      final id = await _seed(
        tester,
        env,
        grams: 71500,
        atUtc: '2026-10-03T06:00:00Z',
        toilet: true,
      );
      await _open(tester, env, WeightRoutes.edit(id));
      await _settle(tester);

      await tester.ensureVisible(find.text('Eintrag löschen'));
      await tester.tap(find.text('Eintrag löschen'));
      await _settle(tester);
      expect(find.textContaining('löschen?'), findsOneWidget);
      expect(find.textContaining('71,5 kg wird entfernt'), findsOneWidget);

      await tester.tap(find.text('Löschen'));
      await _settle(tester);

      expect(await _active(tester, env), isEmpty);
      expect(env.feedback.last?.message, 'Messung gelöscht');
      final undo = env.feedback.last?.undo;
      expect(undo, isNotNull);

      final result = await tester.runAsync(() => undo!.perform());
      expect(result, UndoResult.undone);
      final restored = await _active(tester, env);
      expect(restored, hasLength(1));
      expect(restored.single.weightGrams, 71500);
      expect(restored.single.beforeToilet, isTrue);
    });

    testWidgets('cancelling the confirmation deletes nothing', (tester) async {
      final env = await _env(tester);
      final id = await _seed(
        tester,
        env,
        grams: 71500,
        atUtc: '2026-10-03T06:00:00Z',
      );
      await _open(tester, env, WeightRoutes.edit(id));
      await _settle(tester);

      await tester.ensureVisible(find.text('Eintrag löschen'));
      await tester.tap(find.text('Eintrag löschen'));
      await _settle(tester);
      await tester.tap(find.text('Abbrechen'));
      await _settle(tester);

      expect(await _active(tester, env), hasLength(1));
      expect(env.feedback.events, isEmpty);
    });

    testWidgets('a missing entry shows a way back instead of crashing', (
      tester,
    ) async {
      final env = await _env(tester);
      await _open(tester, env, WeightRoutes.edit('does-not-exist'));
      await _settle(tester);

      expect(find.text('Eintrag nicht gefunden'), findsOneWidget);
      await tester.tap(find.text('Zur Übersicht'));
      await _settle(tester);
      expect(find.text('Mein Gewicht'), findsOneWidget);
    });

    testWidgets('saving stays disabled until something changed', (
      tester,
    ) async {
      final env = await _env(tester);
      final id = await _seed(
        tester,
        env,
        grams: 71500,
        atUtc: '2026-10-03T06:00:00Z',
      );
      await _open(tester, env, WeightRoutes.edit(id));
      await _settle(tester);
      expect(_primaryButton(tester, 'Änderungen speichern').onPressed, isNull);

      await _enterWeight(tester, '71,6');
      expect(
        _primaryButton(tester, 'Änderungen speichern').onPressed,
        isNotNull,
      );
    });
  });

  group('overview', () {
    testWidgets('no measurement shows the honest empty state (AT08)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _open(tester, env, WeightRoutes.overview);
      await _settle(tester);

      expect(find.text('Noch keine Messung'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);

      await tester.tap(find.text('Gewicht eintragen'));
      await _settle(tester);
      expect(find.text('Eintrag speichern'), findsOneWidget);
    });

    testWidgets('one measurement shows the marker and no comparison (AT08)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _seed(tester, env, grams: 71500, atUtc: '2026-10-03T06:00:00Z');
      await _open(tester, env, WeightRoutes.overview);
      await _settle(tester);

      expect(find.textContaining('Eine Messung am'), findsOneWidget);
      expect(find.text('Noch kein Wochenvergleich'), findsOneWidget);
      expect(find.text('71,5 kg'), findsWidgets);
      expect(find.text('Zielgewicht festlegen'), findsOneWidget);
    });

    testWidgets('several measurements show deltas and the real course (AT08)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _seed(tester, env, grams: 72000, atUtc: '2026-09-25T06:00:00Z');
      await _seed(tester, env, grams: 71800, atUtc: '2026-10-02T06:00:00Z');
      await _seed(
        tester,
        env,
        grams: 71500,
        atUtc: '2026-10-03T06:00:00Z',
        toilet: true,
      );
      await _open(tester, env, WeightRoutes.overview);
      await _settle(tester);

      // Current value, week comparison and the reference delta of the row.
      expect(find.text('71,5 kg'), findsWidgets);
      expect(find.textContaining('seit letzter Woche'), findsOneWidget);
      expect(find.text(_minus('↓ -0,3 kg')), findsOneWidget);
      expect(
        find.textContaining('08:00 · nüchtern · Vor dem Klo'),
        findsOneWidget,
      );
      expect(find.text('Letzte Einträge'), findsOneWidget);

      // The text alternative of the chart and its table view.
      expect(find.textContaining('2 Messtage in 7 Tagen'), findsOneWidget);
      await tester.tap(find.text('30 T'));
      await _settle(tester);
      expect(find.textContaining('3 Messtage in 30 Tagen'), findsOneWidget);
      await tester.tap(find.text('3 M'));
      await _settle(tester);
      expect(find.textContaining('3 Messtage in 90 Tagen'), findsOneWidget);

      await tester.ensureVisible(find.text('Als Tabelle anzeigen'));
      await tester.tap(find.text('Als Tabelle anzeigen'));
      await _settle(tester);
      expect(find.textContaining('72,0 kg'), findsWidgets);
    });

    testWidgets('tapping an entry opens its edit form', (tester) async {
      final env = await _env(tester);
      await _seed(tester, env, grams: 71500, atUtc: '2026-10-03T06:00:00Z');
      await _open(tester, env, WeightRoutes.overview);
      await _settle(tester);

      await tester.tap(find.text('08:00 · nüchtern'));
      await _settle(tester);

      expect(find.text('Änderungen speichern'), findsOneWidget);
      expect(find.widgetWithText(TextField, '71,5'), findsOneWidget);
    });

    testWidgets('losing weight: progress, remaining and goal texts (AT09)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _setProfile(tester, env, start: 75000, target: 70000);
      await _seed(tester, env, grams: 71500, atUtc: '2026-10-03T06:00:00Z');
      await _open(tester, env, WeightRoutes.overview);
      await _settle(tester);

      expect(find.text('Start 75,0 kg'), findsOneWidget);
      expect(find.text('Noch 1,5 kg'), findsOneWidget);
      expect(find.text('Ziel 70,0 kg'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Fortschritt zum Zielgewicht: 70 Prozent'),
        findsOneWidget,
      );
    });

    testWidgets('gaining weight: progress counts upwards (AT09)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _setProfile(tester, env, start: 60000, target: 65000);
      await _seed(tester, env, grams: 62000, atUtc: '2026-10-03T06:00:00Z');
      await _open(tester, env, WeightRoutes.overview);
      await _settle(tester);

      expect(find.text('Noch 3,0 kg'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Fortschritt zum Zielgewicht: 40 Prozent'),
        findsOneWidget,
      );
    });

    testWidgets('goal reached and goal equal to start (AT09)', (tester) async {
      final env = await _env(tester);
      await _setProfile(tester, env, start: 75000, target: 70000);
      await _seed(tester, env, grams: 69800, atUtc: '2026-10-03T06:00:00Z');
      await _open(tester, env, WeightRoutes.overview);
      await _settle(tester);
      expect(find.text('Ziel erreicht'), findsOneWidget);
      expect(find.bySemanticsLabel('Zielgewicht erreicht'), findsOneWidget);

      await _setProfile(tester, env, start: 70000, target: 70000);
      await _settle(tester);
      expect(find.text('Noch 0,2 kg'), findsOneWidget);
    });

    testWidgets(
      'a missing goal offers to set it, no invented progress (AT09)',
      (tester) async {
        final env = await _env(tester);
        await _seed(tester, env, grams: 71500, atUtc: '2026-10-03T06:00:00Z');
        await _open(tester, env, WeightRoutes.overview);
        await _settle(tester);

        expect(find.text('Zielgewicht festlegen'), findsOneWidget);
        expect(find.textContaining('Ziel '), findsNothing);
        await tester.tap(find.text('Zielgewicht festlegen'));
        await _settle(tester);
        expect(find.text('Profil bearbeiten'), findsOneWidget);
      },
    );

    testWidgets(
      'BMI only appears with height and age, as a neutral value (W02)',
      (tester) async {
        final env = await _env(tester);
        await _seed(tester, env, grams: 71500, atUtc: '2026-10-03T06:00:00Z');
        await _open(tester, env, WeightRoutes.overview);
        await _settle(tester);
        await tester.ensureVisible(find.text('BMI anzeigen'));
        expect(find.text('BMI anzeigen'), findsOneWidget);
        expect(find.text('Rechnerischer BMI'), findsNothing);

        await _setProfile(tester, env, heightCm: 180, ageYears: 30);
        await _settle(tester);
        await tester.ensureVisible(find.text('Rechnerischer BMI'));
        expect(find.text('Rechnerischer BMI'), findsOneWidget);
        expect(find.text('22,1'), findsOneWidget);
        expect(find.textContaining('ohne Bewertung'), findsOneWidget);
      },
    );

    testWidgets('a start weight marks the first entry (W02)', (tester) async {
      final env = await _env(tester);
      await _setProfile(tester, env, start: 72000, target: 70000);
      await _seed(tester, env, grams: 72000, atUtc: '2026-09-25T06:00:00Z');
      await _seed(tester, env, grams: 71500, atUtc: '2026-10-03T06:00:00Z');
      await _open(tester, env, WeightRoutes.overview);
      await _settle(tester);

      expect(find.textContaining('Startgewicht'), findsOneWidget);
    });
  });

  group('history', () {
    testWidgets('groups by month and builds rows lazily (AT08)', (
      tester,
    ) async {
      final env = await _env(tester);
      for (var day = 0; day < 70; day++) {
        final at = DateTime.utc(2026, 10, 3, 6).subtract(Duration(days: day));
        await _seed(
          tester,
          env,
          grams: 70000 + day * 100,
          atUtc: at.toIso8601String(),
        );
      }
      await _open(tester, env, WeightRoutes.all);
      await _settle(tester);

      expect(
        find.textContaining(RegExp('oktober 2026', caseSensitive: false)),
        findsOneWidget,
      );
      expect(find.byType(EntryListTile).evaluate().length, lessThan(30));

      await tester.dragUntilVisible(
        find.textContaining('Tippe auf einen Eintrag'),
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      expect(
        find.textContaining(RegExp('juli 2026', caseSensitive: false)),
        findsOneWidget,
      );
    });

    testWidgets('empty history shows the empty state with its action', (
      tester,
    ) async {
      final env = await _env(tester);
      await _open(tester, env, WeightRoutes.all);
      await _settle(tester);

      expect(find.text('Noch keine Messung'), findsOneWidget);
      await tester.tap(find.text('Gewicht eintragen'));
      await _settle(tester);
      expect(find.text('Eintrag speichern'), findsOneWidget);
    });
  });

  group('responsive layout and accessibility', () {
    for (final size in responsiveSizes) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'form, overview and history fit ${size.width.toInt()} px at '
          '${(scale * 100).toInt()} % text (AT33)',
          (tester) async {
            final env = await _env(tester);
            await _setProfile(
              tester,
              env,
              start: 75000,
              target: 70000,
              heightCm: 180,
              ageYears: 30,
            );
            for (var day = 0; day < 8; day++) {
              await _seed(
                tester,
                env,
                grams: 72000 - day * 100,
                atUtc: DateTime.utc(
                  2026,
                  9,
                  26,
                  6,
                ).add(Duration(days: day)).toIso8601String(),
                toilet: day.isEven,
                drinking: day % 3 == 0,
                eating: day % 4 == 0,
              );
            }
            for (final location in [
              WeightRoutes.overview,
              WeightRoutes.create,
              WeightRoutes.all,
            ]) {
              await _open(tester, env, location, size: size, textScale: scale);
              await _settle(tester);
              expect(
                tester.takeException(),
                isNull,
                reason: '$location overflowed',
              );
            }
            // The form with an error and the duplicate offer is the tallest.
            await _open(
              tester,
              env,
              WeightRoutes.create,
              size: size,
              textScale: scale,
            );
            await _enterWeight(tester, '19,9');
            await _settle(tester);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('the save button stays reachable above the keyboard (AT33)', (
      tester,
    ) async {
      final env = await _env(tester);
      const size = Size(360, 640);
      const keyboard = 300.0;
      await _open(
        tester,
        env,
        WeightRoutes.create,
        size: size,
        textScale: 2.0,
        viewInsets: const EdgeInsets.only(bottom: keyboard),
      );
      await _enterWeight(tester, '71,5');
      await _settle(tester);

      final button = find.text('Eintrag speichern');
      await tester.ensureVisible(button);
      await tester.pump();
      final rect = tester.getRect(button);
      expect(rect.bottom, lessThanOrEqualTo(size.height - keyboard));

      await tester.tap(button);
      await _settle(tester);
      expect(await _active(tester, env), hasLength(1));
    });

    testWidgets('tap targets and labels meet the guidelines (AT34)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await _env(tester);
      for (var day = 0; day < 3; day++) {
        await _seed(
          tester,
          env,
          grams: 72000 - day * 100,
          atUtc: DateTime.utc(
            2026,
            9,
            28,
            6,
          ).add(Duration(days: day)).toIso8601String(),
        );
      }
      for (final location in [WeightRoutes.overview, WeightRoutes.create]) {
        await _open(tester, env, location);
        await _settle(tester);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }
      handle.dispose();
    });

    testWidgets(
      'the chart is described by text and the delta by words (AT34)',
      (tester) async {
        final handle = tester.ensureSemantics();
        final env = await _env(tester);
        await _seed(tester, env, grams: 71800, atUtc: '2026-10-02T06:00:00Z');
        await _seed(tester, env, grams: 71500, atUtc: '2026-10-03T06:00:00Z');
        await _open(tester, env, WeightRoutes.overview);
        await _settle(tester);

        expect(
          find.bySemanticsLabel(RegExp('Aktuelles Gewicht 71,5 Kilogramm')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp('minus 0,3 Kilogramm')),
          findsWidgets,
        );
        expect(find.textContaining('2 Messtage in 7 Tagen'), findsOneWidget);
        handle.dispose();
      },
    );
  });
}
