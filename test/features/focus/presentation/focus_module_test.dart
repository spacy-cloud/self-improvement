import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/data/focus_repository.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/focus_module.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';

import '../../../support/pump_app.dart';
import '../support/focus_ui_kit.dart';

/// A repository whose reads fail like a broken disk.
final class _BrokenFocusRepository extends FocusRepository {
  _BrokenFocusRepository({required super.database, required super.runner});

  @override
  Future<FocusSession?> findOpen() async => throw const StorageFailure();
}

/// The module registration: routes, cards, plus menu entries and the check
/// that blocks switching the module off while a session is open.
void main() {
  const module = FocusModule();

  final canDeactivateProbe = Provider<Future<DeactivationCheck>>(
    (ref) => module.canDeactivate(ref),
  );
  final initializeProbe = Provider<Future<void>>(
    (ref) => module.initialize(ref),
  );

  Future<DeactivationCheck> check(WidgetTester tester, FocusUi ui) async =>
      (await tester.runAsync(() => ui.container.read(canDeactivateProbe)))!;

  test('describes itself', () {
    expect(module.id, ModuleId.focus);
    expect(module.title, 'Fokus & Workouts');
    expect(module.description, 'Fokus-Timer und Trainings');
    expect(module.icon, Icons.schedule_rounded);
  });

  group('routes', () {
    final paths = [
      for (final route in module.routes)
        if (route is GoRoute) route.path,
    ];

    test('are the screens of the routes table, static before parametric', () {
      expect(paths, [
        '/focus',
        '/focus/session',
        '/focus/history',
        '/focus/history/:id',
        '/workouts',
        '/workouts/new',
        '/workouts/all',
        '/workouts/:id',
      ]);
      expect(
        paths.indexOf('/workouts/new'),
        lessThan(paths.indexOf('/workouts/:id')),
      );
      expect(
        paths.indexOf('/workouts/all'),
        lessThan(paths.indexOf('/workouts/:id')),
      );
      expect(
        paths.indexOf('/focus/history'),
        lessThan(paths.indexOf('/focus/history/:id')),
      );
    });

    test('the constants match the registered paths', () {
      expect(FocusRoutes.start, '/focus');
      expect(FocusRoutes.session, '/focus/session');
      expect(FocusRoutes.history, '/focus/history');
      expect(FocusRoutes.historyDetail('a1'), '/focus/history/a1');
      expect(WorkoutRoutes.overview, '/workouts');
      expect(WorkoutRoutes.create, '/workouts/new');
      expect(WorkoutRoutes.all, '/workouts/all');
      expect(WorkoutRoutes.edit('w1'), '/workouts/w1');
      expect(focusDeactivationResolveRoute, '/focus/session');
    });

    for (final (location, expected) in [
      ('/focus', 'Fokus starten'),
      ('/focus/session', 'Keine laufende Sitzung'),
      ('/focus/history', 'Fokus-Verlauf'),
      ('/focus/history/unknown', 'Sitzung nicht gefunden'),
      ('/workouts', 'Meine Workouts'),
      ('/workouts/new', 'Workout eintragen'),
      ('/workouts/all', 'Alle Trainings'),
      ('/workouts/unknown', 'Training nicht gefunden'),
    ]) {
      testWidgets('$location opens the right screen', (tester) async {
        final ui = await createFocusUi(tester);
        await pumpFocusApp(tester, ui, initialLocation: location);
        expect(find.text(expected), findsWidgets);
        if (location == '/workouts/new' || location == '/workouts/all') {
          expect(
            find.text('Training nicht gefunden'),
            findsNothing,
            reason: 'never read as a workout id',
          );
        }
      });
    }
  });

  group('dashboard cards', () {
    test('use ids of the schema and belong to this module', () {
      for (final card in module.dashboardCards) {
        expect(SchemaKeys.dashboardCards, contains(card.cardId));
        expect(SchemaKeys.dashboardCardModule[card.cardId], ModuleId.focus.key);
      }
      // The default order of the dashboard: workout before focus.
      final order = SchemaKeys.defaultCardOrder;
      expect(order.indexOf('workout'), lessThan(order.indexOf('focus')));
    });
  });

  group('plus menu', () {
    test('Workout is position 1 and Fokus position 4 (design order)', () {
      final actions = {for (final a in module.quickActions) a.id: a};
      expect(actions.keys, ['workout', 'focus']);
      expect(actions['workout']!.label, 'Workout');
      expect(actions['workout']!.route, '/workouts/new');
      expect(actions['workout']!.plusOrder, 1);
      expect(actions['workout']!.dynamicLabel, isNull);
      expect(actions['focus']!.label, 'Fokus');
      expect(actions['focus']!.route, '/focus');
      expect(actions['focus']!.plusOrder, 4);
    });

    testWidgets('Fokus reads "Fokus fortsetzen" while a session is open', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      final focus = module.quickActions.last;
      await pumpApp(
        tester,
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Text(focus.dynamicLabel!(ref)),
          ),
        ),
        container: ui.container,
      );
      await tester.settleDb();
      expect(find.text('Fokus'), findsOneWidget);

      final id = await tester.startFocus(ui);
      expect(find.text('Fokus fortsetzen'), findsOneWidget);

      ui.advance(600);
      await tester.runCommand(
        () => ui.focusRepository.save(commandId: ui.ids.newId(), id: id),
      );
      expect(find.text('Fokus'), findsOneWidget, reason: 'the session is done');
    });
  });

  group('switching the module off (AT19, F01)', () {
    testWidgets('is allowed without an open session', (tester) async {
      final ui = await createFocusUi(tester);
      expect(await check(tester, ui), isA<CanDeactivate>());
    });

    testWidgets('is blocked while a session runs or is paused', (tester) async {
      final ui = await createFocusUi(tester);
      final id = await tester.startFocus(ui);
      var result = await check(tester, ui);
      expect(result, isA<MustResolveFirst>());
      expect(
        (result as MustResolveFirst).message,
        'Es läuft noch eine Fokus-Sitzung. Speichere oder verwirf sie, bevor '
        'du das Modul ausschaltest.',
      );
      expect(result.resolveLabel, 'Sitzung zuerst beenden');

      ui.advance(60);
      await tester.runCommand(
        () => ui.focusRepository.pause(commandId: ui.ids.newId(), id: id),
      );
      result = await check(tester, ui);
      expect(result, isA<MustResolveFirst>());
      expect(
        (result as MustResolveFirst).resolveLabel,
        'Sitzung zuerst beenden',
      );
    });

    testWidgets('is blocked while a session waits for its confirmation', (
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
      final result = await check(tester, ui);
      expect(result, isA<MustResolveFirst>());
      expect(
        (result as MustResolveFirst).message,
        contains('wartet noch auf deine Bestätigung'),
      );
      expect(result.resolveLabel, 'Sitzung zuerst bestätigen');
    });

    testWidgets(
      'the manager refuses too, nothing is deleted silently; the session is resolved on the focus screen, then the module can be switched off (AT19)',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.startFocus(ui);
        ui.advance(600);
        final manager = ui.container.read(moduleManagerProvider);

        Object? refused;
        await tester.runAsync(() async {
          try {
            await manager.setEnabled(
              commandId: ui.ids.newId(),
              module: ModuleId.focus,
              enabled: false,
            );
          } on ConflictFailure catch (failure) {
            refused = failure;
          }
        });
        expect(
          (refused! as ConflictFailure).kind,
          ConflictKind.openFocusSession,
        );
        expect(await tester.focusRows(ui), hasLength(1));
        expect((await tester.focusRows(ui)).single.status, 'running');

        // The resolution route: the user ends the session there (discard).
        await pumpFocusApp(
          tester,
          ui,
          initialLocation: focusDeactivationResolveRoute,
        );
        await tester.tap(find.text('Beenden'));
        await tester.pumpAndSettle();
        await tester.tapAndSettleDb(find.text('Verwerfen'));

        expect(await check(tester, ui), isA<CanDeactivate>());
        await tester.runAsync(
          () => manager.setEnabled(
            commandId: ui.ids.newId(),
            module: ModuleId.focus,
            enabled: false,
          ),
        );
        final statuses = await tester.runAsync(
          () => ui.container
              .read(moduleStatusRepositoryProvider)
              .watchStatuses()
              .first,
        );
        expect(statuses![ModuleId.focus], isFalse);
        // The data is still there: discarded by the user, never deleted.
        final rows = await tester.focusRows(ui);
        expect(rows, hasLength(1));
        expect(rows.single.status, 'discarded');
        expect(rows.single.deletedAtUtc, isNull);
      },
    );

    testWidgets('saving is a second way to resolve it', (tester) async {
      final ui = await createFocusUi(tester);
      await tester.startFocus(ui);
      await pumpFocusApp(
        tester,
        ui,
        initialLocation: focusDeactivationResolveRoute,
      );
      await tester.tick(ui, 600);
      await tester.tap(find.text('Beenden'));
      await tester.pumpAndSettle();
      await tester.tapAndSettleDb(find.text('Zeit speichern'));
      expect(await check(tester, ui), isA<CanDeactivate>());
      expect((await tester.focusRows(ui)).single.status, 'completed');
    });
  });

  group('initialize', () {
    testWidgets('restores a session that ran out, idempotently', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await tester.startFocus(ui);
      ui.advance(1700);

      await tester.runAsync(() => ui.container.read(initializeProbe));
      expect(
        (await tester.focusRows(ui)).single.status,
        'awaiting_confirmation',
      );
      expect(
        await tester.receipts(ui, 'focus.await_confirmation'),
        hasLength(1),
      );
      // A second call changes nothing.
      ui.container.invalidate(initializeProbe);
      await tester.runAsync(() => ui.container.read(initializeProbe));
      expect(
        await tester.receipts(ui, 'focus.await_confirmation'),
        hasLength(1),
      );
    });

    testWidgets('leaves a running session with time left untouched', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await tester.startFocus(ui);
      ui.advance(600);
      await tester.runAsync(() => ui.container.read(initializeProbe));
      final row = (await tester.focusRows(ui)).single;
      expect(row.status, 'running');
      expect(row.rowVersion, 1);
    });

    testWidgets('a storage problem does not stop the app from starting', (
      tester,
    ) async {
      final ui = await createFocusUi(
        tester,
        overrides: [
          focusRepositoryProvider.overrideWith(
            (ref) => _BrokenFocusRepository(
              database: ref.watch(appDatabaseProvider),
              runner: ref.watch(commandRunnerProvider),
            ),
          ),
        ],
      );
      await tester.runAsync(() => ui.container.read(initializeProbe));
    });
  });
}
