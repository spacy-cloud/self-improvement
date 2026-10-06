import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/body/body_module.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/body/steps/domain/step_day.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_dashboard_card.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_routes.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';

/// Widget tests of the steps screens and card against a real in-memory
/// database (clock 2026-10-03 10:00 Europe/Berlin, daily goal 10.000 steps).

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
  // The profile started earlier, so past days carry a goal too.
  await tester.runAsync(
    () => harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1)),
  );
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
    builder: (context, state) => const Scaffold(
      body: SingleChildScrollView(child: StepsDashboardCard()),
    ),
  ),
  ...const BodyModule().routes,
];

Future<GoRouter> _open(
  WidgetTester tester,
  _Env env,
  String location, {
  Size size = const Size(393, 852),
  double textScale = 1.0,
}) => pumpRouterApp(
  tester,
  routes: _routes(),
  initialLocation: location,
  container: env.container,
  size: size,
  textScale: textScale,
);

final LocalDate _today = LocalDate(2026, 10, 3);

Future<void> _record(
  WidgetTester tester,
  _Env env,
  LocalDate date,
  int steps,
) async {
  await tester.runCommand(
    () => env.container
        .read(stepsRepositoryProvider)
        .setSteps(commandId: env.harness.ids.newId(), date: date, steps: steps),
  );
}

Future<StepDay?> _day(WidgetTester tester, _Env env, LocalDate date) => tester
    .runAsync(() => env.container.read(stepsRepositoryProvider).findDay(date))
    .then((value) => value);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

PrimaryButton _primary(WidgetTester tester, String label) =>
    tester.widget<PrimaryButton>(find.widgetWithText(PrimaryButton, label));

void main() {
  group('form', () {
    testWidgets('saves the typed total, groups it while typing (AT15)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _open(tester, env, StepsRoutes.create);

      await _type(tester, '7450');
      expect(find.widgetWithText(TextField, '7.450'), findsOneWidget);
      await tester.tap(find.text('Schritte speichern'));
      await _settle(tester);

      expect((await _day(tester, env, _today))?.steps, 7450);
      expect(env.feedback.last?.kind, 'saved');
      expect(env.feedback.last?.message, 'Schritte gespeichert');
      expect(env.feedback.last?.undo, isNotNull);
      expect(find.textContaining('7.450'), findsOneWidget);
      expect(find.text('75 % erreicht'), findsOneWidget);
    });

    testWidgets('a new value replaces the day, it never adds (AT15)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 7450);
      await _open(tester, env, StepsRoutes.create);
      await _settle(tester);

      expect(
        find.text('Für heute sind schon 7.450 eingetragen'),
        findsOneWidget,
      );
      expect(
        find.text('Beim Speichern wird der Tageswert ersetzt, nicht addiert.'),
        findsOneWidget,
      );
      await _type(tester, '8000');
      await tester.tap(find.text('Tageswert ersetzen'));
      await _settle(tester);

      expect((await _day(tester, env, _today))?.steps, 8000);
      expect(env.feedback.last?.message, 'Schritte aktualisiert');

      final undo = env.feedback.last?.undo;
      final result = await tester.runAsync(() => undo!.perform());
      expect(result, UndoResult.undone);
      expect((await _day(tester, env, _today))?.steps, 7450);
    });

    testWidgets('zero is a recorded value, empty is not savable (AT15)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _open(tester, env, StepsRoutes.create);
      expect(_primary(tester, 'Schritte speichern').onPressed, isNull);

      await _type(tester, '0');
      await tester.tap(find.text('Schritte speichern'));
      await _settle(tester);

      final day = await _day(tester, env, _today);
      expect(day, isNotNull);
      expect(day?.steps, 0);
    });

    testWidgets('letters are ignored and the maximum is enforced (AT15)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _open(tester, env, StepsRoutes.create);

      await _type(tester, 'abc');
      expect(_primary(tester, 'Schritte speichern').onPressed, isNull);

      await _type(tester, '100001');
      await tester.tap(find.text('Schritte speichern'));
      await _settle(tester);
      expect(
        find.text('Bitte gib höchstens 100.000 Schritte ein.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byType(TextField).first)
            .focusNode!
            .hasFocus,
        isTrue,
        reason: 'the invalid field takes the focus (Q02)',
      );
      expect(await _day(tester, env, _today), isNull);

      await _type(tester, '100000');
      await tester.tap(find.text('Schritte speichern'));
      await _settle(tester);
      expect((await _day(tester, env, _today))?.steps, 100000);
    });

    testWidgets('the day can be moved back, never into the future (AT24)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _open(tester, env, StepsRoutes.create);
      expect(find.text('Heute, 3. Oktober'), findsOneWidget);

      final next = find.bySemanticsLabel('Einen Tag weiter');
      expect(
        tester.getSemantics(next).flagsCollection.isEnabled,
        isNot(isTrue),
      );

      await tester.tap(find.bySemanticsLabel('Einen Tag zurück'));
      await tester.pump();
      expect(find.text('Gestern, 2. Oktober'), findsOneWidget);

      await _type(tester, '9000');
      await tester.tap(find.text('Schritte speichern'));
      await _settle(tester);

      final yesterday = _today.addDays(-1);
      expect((await _day(tester, env, yesterday))?.steps, 9000);
      expect(await _day(tester, env, _today), isNull);
    });

    testWidgets('a link with a date opens that day for correction (AT24)', (
      tester,
    ) async {
      final env = await _env(tester);
      final date = LocalDate(2026, 9, 28);
      await _record(tester, env, date, 5000);
      await _open(tester, env, StepsRoutes.createFor(date));
      await _settle(tester);

      expect(find.text('Montag, 28. September'), findsOneWidget);
      expect(
        find.text('Für Mo., 28. Sep. sind schon 5.000 eingetragen'),
        findsOneWidget,
      );
    });

    testWidgets('deleting asks first and can be undone (AT26)', (tester) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 7450);
      await _open(tester, env, StepsRoutes.create);
      await _settle(tester);

      await tester.ensureVisible(find.text('Tageswert löschen'));
      await tester.tap(find.text('Tageswert löschen'));
      await _settle(tester);
      expect(find.text('Tageswert löschen?'), findsOneWidget);
      await tester.tap(find.text('Löschen'));
      await _settle(tester);

      expect(await _day(tester, env, _today), isNull);
      expect(env.feedback.last?.message, 'Tageswert gelöscht');
      await tester.runAsync(() => env.feedback.last!.undo!.perform());
      expect((await _day(tester, env, _today))?.steps, 7450);
    });

    testWidgets('a failed save keeps the input, the retry saves once (AT27)', (
      tester,
    ) async {
      final env = await _env(tester);
      env.projection.failure = StateError('disk full');
      await _open(tester, env, StepsRoutes.create);
      await _type(tester, '7450');

      await tester.tap(find.text('Schritte speichern'));
      await _settle(tester);

      expect(await _day(tester, env, _today), isNull);
      expect(find.widgetWithText(TextField, '7.450'), findsOneWidget);
      expect(env.feedback.last?.kind, 'error');
      final retry = env.feedback.last?.onRetry;
      expect(retry, isNotNull);

      env.projection.failure = null;
      await tester.runAsync(() async {
        retry!();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await _settle(tester);

      expect((await _day(tester, env, _today))?.steps, 7450);
      expect(env.feedback.last?.kind, 'saved');
    });

    testWidgets('leaving with unsaved input asks to discard', (tester) async {
      final env = await _env(tester);
      final router = await _open(tester, env, '/');
      unawaited(router.push(StepsRoutes.create));
      await _settle(tester);
      await _type(tester, '5000');

      await tester.tap(find.bySemanticsLabel('Zurück'));
      await _settle(tester);
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await tester.tap(find.text('Verwerfen'));
      await _settle(tester);

      expect(find.text('Schritte eintragen'), findsOneWidget);
      expect(await _day(tester, env, _today), isNull);
    });
  });

  group('overview', () {
    testWidgets(
      'without data it shows no numbers and the way to enter (AT15)',
      (tester) async {
        final env = await _env(tester);
        await _open(tester, env, StepsRoutes.overview);
        await _settle(tester);

        expect(find.text('Meine Schritte'), findsOneWidget);
        expect(find.text('Heute noch nicht eingetragen'), findsOneWidget);
        expect(
          find.text('In den letzten 7 Tagen sind keine Schritte erfasst.'),
          findsOneWidget,
        );
        expect(find.text('Quelle: Manuell'), findsOneWidget);
        expect(find.text('Kein Tagesziel'), findsNothing);
        await tester.tap(find.text('Schritte eintragen'));
        await _settle(tester);
        expect(find.text('Schritte speichern'), findsOneWidget);
      },
    );

    testWidgets('shows today against the goal, the figures and the days', (
      tester,
    ) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 7450);
      await _record(tester, env, _today.addDays(-1), 12800);
      await _record(tester, env, _today.addDays(-3), 8000);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);

      expect(find.textContaining('7.450'), findsWidgets);
      expect(find.text('Noch 2.550'), findsOneWidget);
      expect(find.text('75 % vom Tagesziel'), findsOneWidget);
      expect(find.text('Quelle: Manuell'), findsOneWidget);
      expect(find.text('9.417'), findsOneWidget, reason: 'average of 3 days');
      expect(find.text('12.800'), findsWidgets);
      expect(find.text('Bester Tag (Fr)'), findsOneWidget);
      expect(find.text('1 / 7'), findsOneWidget);
      expect(find.text('Ziel erreicht'), findsWidgets);
      expect(find.textContaining('3 von 7 Tagen erfasst'), findsOneWidget);
      expect(find.text('Eingetragene Tage'), findsOneWidget);
    });

    testWidgets('the period changes the window and the table lists gaps', (
      tester,
    ) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 7450);
      await _record(tester, env, _today.addDays(-20), 6000);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);
      expect(find.textContaining('1 von 7 Tagen erfasst'), findsOneWidget);

      await tester.tap(find.text('30 T'));
      await _settle(tester);
      expect(find.textContaining('2 von 30 Tagen erfasst'), findsOneWidget);

      await tester.ensureVisible(find.text('Als Tabelle anzeigen'));
      await tester.tap(find.text('Als Tabelle anzeigen'));
      await _settle(tester);
      expect(find.textContaining('Nicht erfasst'), findsWidgets);
    });

    testWidgets('tapping a day opens it for correction (AT24)', (tester) async {
      final env = await _env(tester);
      await _record(tester, env, _today.addDays(-2), 5000);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);

      await tester.ensureVisible(find.text('5.000').last);
      await tester.tap(find.text('5.000').last);
      await _settle(tester);

      expect(
        find.text('Für Do., 1. Okt. sind schon 5.000 eingetragen'),
        findsOneWidget,
      );
    });
  });

  group('dashboard card', () {
    testWidgets('before an entry it offers entering, with one tap (AT26)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _open(tester, env, '/');
      await _settle(tester);

      expect(find.text('Schritte'), findsOneWidget);
      expect(find.text('Heute noch nicht eingetragen'), findsOneWidget);
      await tester.tap(find.text('Schritte eintragen'));
      await _settle(tester);
      expect(find.text('Schritte speichern'), findsOneWidget);
    });

    testWidgets('shows the total, the percentage and opens the overview', (
      tester,
    ) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 7450);
      await _open(tester, env, '/');
      await _settle(tester);

      expect(find.textContaining('7.450'), findsOneWidget);
      expect(find.text('75 % erreicht'), findsOneWidget);
      await tester.tap(find.text('Schritte'));
      await _settle(tester);
      expect(find.text('Meine Schritte'), findsOneWidget);
    });

    testWidgets('reaching the goal is stated, the bar stays at 100 %', (
      tester,
    ) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 12000);
      await _open(tester, env, '/');
      await _settle(tester);

      expect(find.text('Ziel erreicht'), findsOneWidget);
      expect(find.textContaining('12.000'), findsOneWidget);
    });

    testWidgets('a correction updates the card at once (AT26)', (tester) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 2000);
      await _open(tester, env, '/');
      await _settle(tester);
      expect(find.text('20 % erreicht'), findsOneWidget);

      await _record(tester, env, _today, 5000);
      await _settle(tester);
      expect(find.text('50 % erreicht'), findsOneWidget);
    });

    testWidgets(
      '(BS-108, AT26) the action stays after the first entry of the day and '
      'then updates the total',
      (tester) async {
        final env = await _env(tester);
        await _open(tester, env, '/');
        await _settle(tester);
        expect(find.text('Schritte eintragen'), findsOneWidget);
        expect(find.text('Schritte aktualisieren'), findsNothing);

        await _record(tester, env, _today, 7450);
        await _settle(tester);

        // The card follows the entry at once: figures, and the way to enter
        // turns into the way to update. The action is not gone.
        expect(find.text('75 % erreicht'), findsOneWidget);
        expect(find.text('Schritte aktualisieren'), findsOneWidget);
        expect(find.text('Schritte eintragen'), findsNothing);
        expect(find.byType(MetricCardAction), findsOneWidget);
      },
    );

    testWidgets(
      '(BS-108, AT15) the update action opens the form for today with the '
      'hint about the existing total',
      (tester) async {
        final env = await _env(tester);
        await _record(tester, env, _today, 7450);
        final router = await _open(tester, env, '/');
        await _settle(tester);

        await tester.tap(find.text('Schritte aktualisieren'));
        await _settle(tester);

        // Today's form: the plain create route, no date of an earlier day.
        expect(router.state.uri.toString(), StepsRoutes.create);
        expect(find.text('Heute, 3. Oktober'), findsOneWidget);
        expect(
          find.text('Für heute sind schon 7.450 eingetragen'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Beim Speichern wird der Tageswert ersetzt, nicht addiert.',
          ),
          findsOneWidget,
        );
        expect(find.text('Tageswert ersetzen'), findsOneWidget);
      },
    );

    testWidgets(
      '(BS-108, AT15, AT26) saving from the card replaces the total and the '
      'card follows at once, it keeps the action',
      (tester) async {
        final env = await _env(tester);
        await _record(tester, env, _today, 7450);
        await _open(tester, env, '/');
        await _settle(tester);

        await tester.tap(find.text('Schritte aktualisieren'));
        await _settle(tester);
        await _type(tester, '8000');
        await tester.tap(find.text('Tageswert ersetzen'));
        await _settle(tester);

        expect(
          (await _day(tester, env, _today))?.steps,
          8000,
          reason: 'the total is replaced, never added (15.450)',
        );
        expect(env.feedback.last?.message, 'Schritte aktualisiert');
        // Back on the card with the new figures and the action still there.
        expect(find.text('Heute, 3. Oktober'), findsNothing);
        expect(find.textContaining('8.000'), findsOneWidget);
        expect(find.text('80 % erreicht'), findsOneWidget);
        expect(find.text('Schritte aktualisieren'), findsOneWidget);

        // A second update works the same way: the action never disappears.
        await tester.tap(find.text('Schritte aktualisieren'));
        await _settle(tester);
        expect(
          find.text('Für heute sind schon 8.000 eingetragen'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '(BS-108, AT15) a recorded 0 is an entry: the card offers the update, '
      'not the entry',
      (tester) async {
        final env = await _env(tester);
        await _record(tester, env, _today, 0);
        await _open(tester, env, '/');
        await _settle(tester);

        expect(find.text('Heute noch nicht eingetragen'), findsNothing);
        expect(find.text('0 % erreicht'), findsOneWidget);
        expect(find.text('Schritte aktualisieren'), findsOneWidget);
        expect(find.text('Schritte eintragen'), findsNothing);
      },
    );

    testWidgets(
      '(BS-108, AT26) after deleting the total the card offers entering '
      'again',
      (tester) async {
        final env = await _env(tester);
        await _record(tester, env, _today, 7450);
        await _open(tester, env, '/');
        await _settle(tester);
        expect(find.text('Schritte aktualisieren'), findsOneWidget);

        await tester.tap(find.text('Schritte aktualisieren'));
        await _settle(tester);
        await tester.ensureVisible(find.text('Tageswert löschen'));
        await tester.tap(find.text('Tageswert löschen'));
        await _settle(tester);
        await tester.tap(find.text('Löschen'));
        await _settle(tester);

        expect(await _day(tester, env, _today), isNull);
        expect(find.text('Heute noch nicht eingetragen'), findsOneWidget);
        expect(find.text('Schritte eintragen'), findsOneWidget);
        expect(find.text('Schritte aktualisieren'), findsNothing);
      },
    );
  });

  group('module', () {
    test('routes keep static paths before parameters, ids are valid', () {
      const module = BodyModule();
      final paths = [
        for (final r in module.routes.whereType<GoRoute>()) r.path,
      ];

      expect(
        paths.indexOf('/weight/new'),
        lessThan(paths.indexOf('/weight/:id')),
      );
      expect(
        paths.indexOf('/weight/all'),
        lessThan(paths.indexOf('/weight/:id')),
      );
      expect(paths, containsAll(['/weight', '/steps', '/steps/new']));
      expect(
        [for (final c in module.dashboardCards) c.cardId],
        ['steps', 'weight'],
      );
      expect(
        [for (final a in module.quickActions) (a.id, a.plusOrder, a.route)],
        [('weight', 0, '/weight/new'), ('steps', 3, '/steps/new')],
      );
    });
  });

  group('responsive layout and accessibility', () {
    for (final size in responsiveSizes) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('overview, form and card fit ${size.width.toInt()} px at '
            '${(scale * 100).toInt()} % text (AT33)', (tester) async {
          final env = await _env(tester);
          for (var day = 0; day < 6; day++) {
            await _record(
              tester,
              env,
              _today.addDays(-day),
              day.isEven ? 100000 - day * 1000 : 3000 + day * 700,
            );
          }
          for (final location in [
            StepsRoutes.overview,
            StepsRoutes.create,
            '/',
          ]) {
            await _open(tester, env, location, size: size, textScale: scale);
            await _settle(tester);
            expect(
              tester.takeException(),
              isNull,
              reason: '$location overflowed',
            );
          }
          await _open(
            tester,
            env,
            StepsRoutes.create,
            size: size,
            textScale: scale,
          );
          await _type(tester, '100001');
          await tester.tap(find.byType(PrimaryButton));
          await _settle(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('tap targets and labels meet the guidelines (AT34)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await _env(tester);
      await _record(tester, env, _today, 7450);
      for (final location in [StepsRoutes.overview, StepsRoutes.create, '/']) {
        await _open(tester, env, location);
        await _settle(tester);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }
      handle.dispose();
    });

    for (final size in responsiveSizes) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '(BS-108, AT33, AT34) the update action keeps its label, button '
          'semantics and 48 x 48 tap area at ${size.width.toInt()} px and '
          '${(scale * 100).toInt()} % text',
          (tester) async {
            final handle = tester.ensureSemantics();
            try {
              final env = await _env(tester);
              await _record(tester, env, _today, 7450);
              await _open(tester, env, '/', size: size, textScale: scale);
              await _settle(tester);

              final action = find.bySemanticsLabel('Schritte aktualisieren');
              expect(action, findsOneWidget);
              final node = tester.getSemantics(action);
              expect(node.flagsCollection.isButton, isTrue);
              expect(
                node.getSemanticsData().hasAction(SemanticsAction.tap),
                isTrue,
              );
              final area = tester.getSize(find.byType(MetricCardAction));
              expect(area.width, greaterThanOrEqualTo(48));
              expect(area.height, greaterThanOrEqualTo(48));
              await expectLater(
                tester,
                meetsGuideline(androidTapTargetGuideline),
              );
              await expectLater(
                tester,
                meetsGuideline(labeledTapTargetGuideline),
              );
              expect(tester.takeException(), isNull);
            } finally {
              handle.dispose();
            }
          },
        );
      }
    }

    testWidgets('the chart is described in words, the bar by percent (AT34)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await _env(tester);
      await _record(tester, env, _today, 7450);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);

      expect(
        find.bySemanticsLabel('Heute 7.450 Schritte / 10.000'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Fortschritt zum Tagesziel: 75 Prozent'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Quelle: Manuell'), findsOneWidget);
      expect(find.textContaining('1 von 7 Tagen erfasst'), findsOneWidget);
      handle.dispose();
    });
  });
}
