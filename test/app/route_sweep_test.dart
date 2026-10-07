import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/dashboard/application/day_browser_providers.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_routes.dart';
import 'package:self_improvement/features/focus/data/workout_day_mark_repository.dart';
import 'package:self_improvement/features/focus/data/workout_repository.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/pump_app.dart';
import '../support/synthetic_records.dart';
import 'support/app_harness.dart';

/// Sweep over EVERY route of the running app without an id (the core pages and
/// the routes of all bundled modules, found from the route tables themselves,
/// so a new route is covered without touching this file): the page must lay
/// out without overflow, every tap target must be at least 48 by 48 and every
/// control must have a label (AT33, AT34, Q02), on the four design widths, with
/// 200 % text, with real-looking data, and in all three themes (AT35).
///
/// The guidelines are the framework's own checks; a page that fails one fails
/// here by name, with the size and theme in the test name.
Iterable<String> _paths(List<RouteBase> routes, [String prefix = '']) sync* {
  for (final route in routes) {
    if (route is! GoRoute) {
      continue;
    }
    final full = route.path.startsWith('/')
        ? route.path
        : '${prefix == '/' ? '' : prefix}/${route.path}';
    yield full;
    yield* _paths(route.routes, full);
  }
}

final List<String> _routes = <String>{
  AppRoutes.home,
  AppRoutes.analysis,
  AppRoutes.habits,
  AppRoutes.habitsTasks,
  AppRoutes.profile,
  AppRoutes.profileEdit,
  AppRoutes.goals,
  DashboardRoutes.goalsToday,
  AppRoutes.settings,
  AppRoutes.modules,
  AppRoutes.data,
  AppRoutes.licenses,
  AppRoutes.about,
  AppRoutes.notFound,
  for (final module in bundledModules) ..._paths(module.routes),
}.where((path) => !path.contains(':')).toList()..sort();

typedef _Setup = ({String name, Size size, double scale});

const List<_Setup> _setups = <_Setup>[
  (name: '320x568 at 200 %', size: Size(320, 568), scale: 2),
  (name: '320x700 at 200 %', size: Size(320, 700), scale: 2),
  (name: '360x800 at 100 %', size: Size(360, 800), scale: 1),
  (name: '393x852 at 100 %', size: Size(393, 852), scale: 1),
  (name: '430x932 at 100 %', size: Size(430, 932), scale: 1),
];

Future<void> _check(WidgetTester tester, AppFixture app, String route) async {
  final handle = tester.ensureSemantics();
  app.router.go(route);
  await app.settle();
  await app.settle();
  expect(tester.takeException(), isNull, reason: 'no exception or overflow');
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  handle.dispose();
}

/// The pages that change with the optional daily goal "Workout heute" (BS-99):
/// home with the Workout card, the workout area with its day card, the goal
/// editor and "Ziele heute" (BS-103) with its row for the day. Each state of the
/// day is a state of the card.
const List<String> _dailyWorkoutRoutes = <String>[
  '/',
  '/workouts',
  '/goals',
  DashboardRoutes.goalsToday,
];

/// The pages that show the day Home pages to (BS-93): Home with its day
/// navigator, the note "Nicht heute" and the cards of that day, and "Ziele
/// heute" with the same day. They only look like that on a day before today.
const List<String> _pastDayRoutes = <String>['/', DashboardRoutes.goalsToday];

/// Seeds a month of synthetic data and pages Home to three days before today.
Future<AppFixture> _pumpOnPastDay(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double scale = 1.0,
}) async {
  final today = LocalDate(2026, 10, 3);
  final first = today.addDays(-29);
  final harness = await createTestHarness(
    tester,
    onboarded: false,
    realProjection: true,
  );
  final app = await pumpFullApp(
    tester,
    reuse: harness,
    size: size,
    textScale: scale,
    onboarded: false,
    seed: (h) async {
      await h.seedOnboarded(startedOn: first);
      await insertSyntheticRecords(
        h.database,
        h.ids,
        first,
        today,
        data: const SyntheticData(
          habitTitles: <String>['Lesen', 'Dehnen'],
          mealNames: <String>['Frühstück', 'Mittagessen', 'Abendessen'],
          varied: true,
        ),
      );
      await h.projections.syncDays(<LocalDate>{
        for (var d = first; !d.isAfter(today); d = d.addDays(1)) d,
      });
    },
  );
  app.container.read(selectedDayProvider.notifier).select(today.addDays(-3));
  await app.settle();
  return app;
}

/// Runs [body] on [_pumpOnPastDay] and takes the app down again when [body]
/// throws: a failed expectation with the app running would otherwise hang the
/// test run in its tear down instead of failing the test.
Future<void> _onPastDay(
  WidgetTester tester, {
  required Future<void> Function(AppFixture app) body,
  Size size = const Size(393, 852),
  double scale = 1.0,
}) async {
  final app = await _pumpOnPastDay(tester, size: size, scale: scale);
  try {
    await body(app);
  } finally {
    await tester.pumpWidget(const SizedBox());
    await app.settle();
  }
}

/// Switches "Workout heute" on and puts the day into [state]: `open`, `rest`,
/// `skipped` or `workout` (a rest day and a skipped day need no workout; the
/// workout of yesterday makes the area show its week and its list).
Future<void> _seedDailyWorkout(DataHarness harness, String state) async {
  await harness.seedOnboarded(
    startedOn: LocalDate(2026, 9, 1),
    workoutDailyGoal: true,
  );
  final marks = WorkoutDayMarkRepository(
    database: harness.database,
    runner: harness.runner,
  );
  final workouts = WorkoutRepository(
    database: harness.database,
    runner: harness.runner,
  );
  WorkoutDraft draft(DateTime at) => WorkoutDraft(
    category: TrainingCategory.strength,
    durationMinutes: 45,
    occurredAtUtc: at,
    title: 'Oberkörper',
  );
  await workouts.create(
    commandId: harness.ids.newId(),
    draft: draft(DateTime.utc(2026, 10, 2, 8)),
  );
  switch (state) {
    case 'rest':
      await marks.mark(
        commandId: harness.ids.newId(),
        kind: WorkoutDayMarkKind.rest,
      );
    case 'skipped':
      await marks.mark(
        commandId: harness.ids.newId(),
        kind: WorkoutDayMarkKind.skipped,
      );
    case 'workout':
      await workouts.create(
        commandId: harness.ids.newId(),
        draft: draft(harness.clock.nowUtc()),
      );
  }
}

void main() {
  test('the sweep finds the core and the module routes', () {
    expect(_routes, containsAll(<String>['/', '/weight/new', '/water']));
    expect(_routes.length, greaterThan(25));
  });

  test('the sweep list has every route of the route table that has no id (BS-98, R1-05, AT33)', () {
    final table = <String>{
      for (final path in allRoutePaths(buildAppRoutes(modules: bundledModules)))
        if (!path.contains(':') && path != AppRoutes.onboarding) path,
    };
    expect(
      table.difference(_routes.toSet()),
      isEmpty,
      reason:
          'a page of the app is missing from the sweep: the core pages are '
          'listed by hand in _routes, add it there (the onboarding needs a '
          'not yet onboarded app and has its own tests)',
    );
  });

  for (final setup in _setups) {
    for (final route in _routes) {
      testWidgets('AT33 $route lays out and is operable at ${setup.name}', (
        tester,
      ) async {
        final app = await pumpFullApp(
          tester,
          size: setup.size,
          textScale: setup.scale,
        );
        await _check(tester, app, route);
      });
    }
  }

  // The same pages with a month of data, where lists and charts have content.
  for (final setup in <_Setup>[_setups.first, _setups[3]]) {
    for (final route in _routes) {
      testWidgets(
        'AT33 $route with data lays out and is operable at ${setup.name}',
        (tester) async {
          final today = LocalDate(2026, 10, 3);
          final first = today.addDays(-29);
          final harness = await createTestHarness(
            tester,
            onboarded: false,
            realProjection: true,
          );
          final app = await pumpFullApp(
            tester,
            reuse: harness,
            size: setup.size,
            textScale: setup.scale,
            onboarded: false,
            seed: (h) async {
              await h.seedOnboarded(startedOn: first);
              await insertSyntheticRecords(
                h.database,
                h.ids,
                first,
                today,
                data: const SyntheticData(
                  habitTitles: <String>['Lesen', 'Dehnen'],
                  mealNames: <String>['Frühstück', 'Mittagessen', 'Abendessen'],
                  varied: true,
                ),
              );
              await h.projections.syncDays(<LocalDate>{
                for (var d = first; !d.isAfter(today); d = d.addDays(1)) d,
              });
            },
          );
          await _check(tester, app, route);
        },
      );
    }
  }

  for (final mode in <String>['dark', 'oled']) {
    for (final route in _routes) {
      testWidgets('AT35 $route lays out and is operable in the $mode theme', (
        tester,
      ) async {
        final app = await pumpFullApp(tester);
        await app.run(
          () => app.container
              .read(settingsCommandsProvider)
              .setThemeMode(
                commandId: app.harness.ids.newId(),
                themeModeKey: mode,
              ),
        );
        await app.settle();
        await _check(tester, app, route);
      });
    }
  }

  // BS-99: the three pages that change with "Workout heute", with the goal on
  // and the day in each of its four states.
  for (final setup in <_Setup>[_setups.first, _setups[3]]) {
    for (final state in <String>['open', 'rest', 'skipped', 'workout']) {
      for (final route in _dailyWorkoutRoutes) {
        testWidgets(
          'AT33 $route with "Workout heute" on and the day $state lays out '
          'and is operable at ${setup.name}',
          (tester) async {
            final harness = await createTestHarness(
              tester,
              onboarded: false,
              realProjection: true,
            );
            final app = await pumpFullApp(
              tester,
              reuse: harness,
              size: setup.size,
              textScale: setup.scale,
              onboarded: false,
              seed: (h) => _seedDailyWorkout(h, state),
            );
            await _check(tester, app, route);
          },
        );
      }
    }
  }

  for (final mode in <String>['dark', 'oled']) {
    for (final route in _dailyWorkoutRoutes) {
      testWidgets(
        'AT35 $route with "Workout heute" on and a rest day lays out and is '
        'operable in the $mode theme',
        (tester) async {
          final harness = await createTestHarness(
            tester,
            onboarded: false,
            realProjection: true,
          );
          final app = await pumpFullApp(
            tester,
            reuse: harness,
            onboarded: false,
            seed: (h) => _seedDailyWorkout(h, 'rest'),
          );
          await app.run(
            () => app.container
                .read(settingsCommandsProvider)
                .setThemeMode(
                  commandId: app.harness.ids.newId(),
                  themeModeKey: mode,
                ),
          );
          await app.settle();
          await _check(tester, app, route);
        },
      );
    }
  }

  // BS-93: the pages that show another day than today, with a month of data.
  for (final setup in <_Setup>[_setups.first, _setups[3]]) {
    for (final route in _pastDayRoutes) {
      testWidgets(
        '(BS-93, AT33) $route on a day before today lays out and is operable '
        'at ${setup.name}',
        (tester) async {
          await _onPastDay(
            tester,
            size: setup.size,
            scale: setup.scale,
            body: (app) => _check(tester, app, route),
          );
        },
      );
    }
  }

  for (final mode in <String>['dark', 'oled']) {
    for (final route in _pastDayRoutes) {
      testWidgets(
        '(BS-93, AT35) $route on a day before today lays out and is operable '
        'in the $mode theme',
        (tester) async {
          await _onPastDay(
            tester,
            body: (app) async {
              await app.run(
                () => app.container
                    .read(settingsCommandsProvider)
                    .setThemeMode(
                      commandId: app.harness.ids.newId(),
                      themeModeKey: mode,
                    ),
              );
              await app.settle();
              await _check(tester, app, route);
            },
          );
        },
      );
    }
  }
}
