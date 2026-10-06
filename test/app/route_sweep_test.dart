import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
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

void main() {
  test('the sweep finds the core and the module routes', () {
    expect(_routes, containsAll(<String>['/', '/weight/new', '/water']));
    expect(_routes.length, greaterThan(25));
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
}
