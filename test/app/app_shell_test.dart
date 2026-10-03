import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/router/app_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/features/tasks/presentation/habits_tab_screen.dart';

import '../support/db_fixtures.dart';
import 'support/app_harness.dart';
import 'support/fake_modules.dart';

final AppTabBuilders _tabs = AppTabBuilders(
  home: (context, state) => const CounterTab('Tab-Home'),
  analysis: (context, state) => const CounterTab('Tab-Analyse'),
  habits: (context, state) => const CounterTab('Tab-Habits'),
  profile: (context, state) => const CounterTab('Tab-Profil'),
);

const List<String> _labelsInOrder = <String>[
  'Gewicht',
  'Workout',
  'Wasser',
  'Schritte',
  'Fokus',
  'Aufgabe',
  'Gewohnheit',
  'Mahlzeit',
];

Future<void> _openPlus(AppFixture app) async {
  await app.tester.tap(plusButton());
  await app.tester.pump();
  await app.settle();
}

Future<void> _closePlus(AppFixture app) async {
  await app.tester.tap(
    find.descendant(of: plusSheet(), matching: find.byIcon(AppIcon.close.data)),
  );
  await app.tester.pump();
  await app.settle();
}

Finder _entry(String id) => find.byKey(ValueKey<String>('plus-entry-$id'));

/// The labels of the menu entries, top to bottom and left to right.
List<String> _visibleEntryLabels(WidgetTester tester) {
  final found = <(String, Offset)>[];
  for (final label in <String>[..._labelsInOrder, 'Fokus fortsetzen']) {
    final finder = find.descendant(of: plusSheet(), matching: find.text(label));
    if (finder.evaluate().isNotEmpty) {
      found.add((label, tester.getTopLeft(finder.first)));
    }
  }
  found.sort((a, b) {
    final byRow = a.$2.dy.compareTo(b.$2.dy);
    return byRow != 0 ? byRow : a.$2.dx.compareTo(b.$2.dx);
  });
  return [for (final entry in found) entry.$1];
}

Future<void> _setModule(
  AppFixture app,
  ModuleId module, {
  required bool enabled,
}) => app.run(
  () => app.container
      .read(moduleManagerProvider)
      .setEnabled(
        commandId: app.harness.ids.newId(),
        module: module,
        enabled: enabled,
      ),
);

void main() {
  group('tabs (C02)', () {
    testWidgets('four tabs and a plus action, the plus is not a fifth tab', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, tabs: _tabs);
      expect(AppBottomNavBar.destinations, hasLength(4));
      for (final label in <String>['Home', 'Analyse', 'Habits', 'Profil']) {
        expect(navTab(label), findsOneWidget);
      }
      expect(plusButton(), findsOneWidget);
      await tester.tap(plusButton());
      await tester.pump();
      await app.settle();
      expect(plusSheet(), findsOneWidget);
      expect(app.location, '/');
      expect(find.text('Tab-Home:0'), findsOneWidget);
    });

    testWidgets('every tab keeps its state while another tab is shown', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, tabs: _tabs);
      await tester.tap(find.text('plus-Tab-Home'));
      await tester.tap(find.text('plus-Tab-Home'));
      await tester.pump();
      expect(find.text('Tab-Home:2'), findsOneWidget);

      await tester.tap(navTab('Analyse'));
      await app.settle();
      expect(app.location, '/analysis');
      expect(find.text('Tab-Analyse:0'), findsOneWidget);
      await tester.tap(find.text('plus-Tab-Analyse'));
      await tester.pump();

      await tester.tap(navTab('Habits'));
      await app.settle();
      expect(find.text('Tab-Habits:0'), findsOneWidget);

      await tester.tap(navTab('Home'));
      await app.settle();
      expect(find.text('Tab-Home:2'), findsOneWidget);
      await tester.tap(navTab('Analyse'));
      await app.settle();
      expect(find.text('Tab-Analyse:1'), findsOneWidget);
    });

    testWidgets('a pushed sub page leaves the tab and its state untouched', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        tabs: _tabs,
        modules: fullFakeModules(),
      );
      await tester.tap(navTab('Profil'));
      await app.settle();
      await tester.tap(find.text('plus-Tab-Profil'));
      await tester.pump();
      unawaited(app.router.push<void>('/weight/all'));
      await tester.pump();
      await app.settle();
      expect(find.text('probe:weight-all'), findsOneWidget);
      expect(find.byType(AppBottomNavBar), findsNothing);
      await tester.tap(find.byIcon(AppIcon.back.data));
      await app.settle();
      expect(find.text('Tab-Profil:1'), findsOneWidget);
      expect(app.location, '/profile');
    });

    testWidgets('/habits?tab=tasks selects the tasks list, /habits does not', (
      tester,
    ) async {
      final app = await pumpFullApp(tester);
      app.router.go('/habits?tab=tasks');
      await tester.pump();
      await app.settle();
      expect(
        tester.widget<HabitsTabScreen>(find.byType(HabitsTabScreen)).showTasks,
        isTrue,
      );
      app.router.go('/habits');
      await tester.pump();
      await app.settle();
      expect(
        tester.widget<HabitsTabScreen>(find.byType(HabitsTabScreen)).showTasks,
        isFalse,
      );
    });

    testWidgets('tapping the selected tab again returns it to its root', (
      tester,
    ) async {
      final app = await pumpFullApp(tester);
      app.router.go('/habits?tab=tasks');
      await tester.pump();
      await app.settle();
      await tester.tap(navTab('Habits'));
      await app.settle();
      expect(
        tester.widget<HabitsTabScreen>(find.byType(HabitsTabScreen)).showTasks,
        isFalse,
      );
    });
  });

  group('plus menu (C02)', () {
    testWidgets('offers exactly the eight entries in the fixed order', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, modules: fullFakeModules());
      await _openPlus(app);
      expect(find.text('Was möchtest du eintragen?'), findsOneWidget);
      expect(_visibleEntryLabels(tester), _labelsInOrder);
      for (final id in <String>[
        'weight',
        'workout',
        'water',
        'steps',
        'focus',
        'task',
        'habit',
        'meal',
      ]) {
        expect(_entry(id), findsOneWidget);
      }
    });

    testWidgets('offers only the entries of active modules', (tester) async {
      final app = await pumpFullApp(
        tester,
        modules: fullFakeModules(),
        enabledModules: <String>{'body', 'focus', 'tasks', 'gamification'},
      );
      await _openPlus(app);
      expect(_visibleEntryLabels(tester), <String>[
        'Gewicht',
        'Workout',
        'Schritte',
        'Fokus',
        'Aufgabe',
        'Gewohnheit',
      ]);
    });

    testWidgets('follows a module switched off while it is open', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, modules: fullFakeModules());
      await _openPlus(app);
      expect(_entry('water'), findsOneWidget);
      await _setModule(app, ModuleId.nutrition, enabled: false);
      await app.settle();
      expect(_entry('water'), findsNothing);
      expect(_entry('meal'), findsNothing);
      expect(_entry('weight'), findsOneWidget);
    });

    testWidgets(
      'with every module off it offers the module choice, no dead end (AT04)',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          modules: fullFakeModules(),
          enabledModules: <String>{},
        );
        await _openPlus(app);
        expect(
          find.textContaining('Alle Module sind ausgeschaltet'),
          findsOneWidget,
        );
        expect(_entry('weight'), findsNothing);
        expect(find.text('Gewicht & Körper'), findsOneWidget);
        expect(find.text('Module verwalten'), findsOneWidget);
        // Switching a module on makes its entries appear right here.
        await tester.tap(find.text('Gewicht & Körper'));
        await tester.pump();
        await app.settle();
        expect(_entry('weight'), findsOneWidget);
        expect(_entry('steps'), findsOneWidget);
        expect(_entry('water'), findsNothing);
      },
    );

    testWidgets(
      '"Module verwalten" in the empty menu opens the module manager (AT04)',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          modules: fullFakeModules(),
          enabledModules: <String>{},
        );
        await _openPlus(app);
        await tester.tap(find.text('Module verwalten'));
        await tester.pump();
        await app.settle();
        expect(app.location, '/settings/modules');
        expect(plusSheet(), findsNothing);
      },
    );

    testWidgets(
      'a running focus session becomes "Fokus fortsetzen" and leads to it',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        await app.run(
          () => app.harness.database
              .into(app.harness.database.focusSessions)
              .insert(focusRow(status: 'paused')),
        );
        await _openPlus(app);
        expect(find.text('Fokus fortsetzen'), findsOneWidget);
        expect(find.text('Fokus'), findsNothing);
        expect(_visibleEntryLabels(tester), hasLength(8));
        await tester.tap(find.text('Fokus fortsetzen'));
        await tester.pump();
        await app.settle();
        expect(app.location, '/focus/session');
        expect(find.text('probe:focus-session'), findsOneWidget);
      },
    );

    testWidgets('without a running session Fokus starts a new one', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, modules: fullFakeModules());
      await _openPlus(app);
      await tester.tap(find.text('Fokus'));
      await tester.pump();
      await app.settle();
      expect(app.location, '/focus');
    });

    testWidgets(
      'a pick opens the target on top and leaving returns to the starting tab',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          tabs: _tabs,
          modules: fullFakeModules(),
        );
        await tester.tap(navTab('Analyse'));
        await app.settle();
        await _openPlus(app);
        await tester.tap(find.text('Wasser'));
        await tester.pump();
        await app.settle();
        expect(app.location, '/water');
        expect(find.text('probe:water'), findsOneWidget);
        expect(plusSheet(), findsNothing);
        // Cancel the flow: back to where it was started, with the tab intact.
        await tester.tap(find.byIcon(AppIcon.back.data));
        await app.settle();
        expect(app.location, '/analysis');
        expect(find.text('Tab-Analyse:0'), findsOneWidget);
      },
    );

    testWidgets('the close button closes the menu and changes nothing', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        tabs: _tabs,
        modules: fullFakeModules(),
      );
      await tester.tap(navTab('Habits'));
      await app.settle();
      await _openPlus(app);
      await _closePlus(app);
      expect(plusSheet(), findsNothing);
      expect(app.location, '/habits');
      expect(find.text('Tab-Habits:0'), findsOneWidget);
    });

    testWidgets('the scrim closes the menu', (tester) async {
      final app = await pumpFullApp(tester, modules: fullFakeModules());
      await _openPlus(app);
      await tester.tapAt(const Offset(196, 40));
      await tester.pump();
      await app.settle();
      expect(plusSheet(), findsNothing);
      expect(app.location, '/');
    });

    testWidgets('focus returns to the plus button when the menu closes', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, modules: fullFakeModules());
      final node = Focus.of(tester.element(plusButton()));
      node.requestFocus();
      await tester.pump();
      expect(node.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await app.settle();
      expect(plusSheet(), findsOneWidget);
      expect(node.hasPrimaryFocus, isFalse);
      await _closePlus(app);
      expect(plusSheet(), findsNothing);
      expect(node.hasPrimaryFocus, isTrue);
    });

    testWidgets(
      'the real weight entry opens from the plus menu with the real module',
      (tester) async {
        final app = await pumpFullApp(tester);
        await _openPlus(app);
        expect(_visibleEntryLabels(tester), <String>['Gewicht']);
        await tester.tap(find.text('Gewicht'));
        await tester.pump();
        await app.settle();
        expect(app.location, '/weight/new');
        expect(find.text('Gewicht eintragen'), findsWidgets);
      },
    );
  });
}
