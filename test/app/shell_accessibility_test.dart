import 'dart:async';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/router/app_router.dart';
import 'package:self_improvement/app/shell/plus_sheet.dart';
import 'package:self_improvement/core/design/design.dart';

import '../support/pump_app.dart';
import 'support/app_harness.dart';
import 'support/fake_modules.dart';

final AppTabBuilders _tabs = AppTabBuilders(
  home: (context, state) => const CounterTab('Tab-Home'),
  analysis: (context, state) => const CounterTab('Tab-Analyse'),
  habits: (context, state) => const CounterTab('Tab-Habits'),
  profile: (context, state) => const CounterTab('Tab-Profil'),
);

const List<String> _ids = <String>[
  'weight',
  'workout',
  'water',
  'steps',
  'focus',
  'task',
  'habit',
  'meal',
];

Finder _entry(String id) => find.byKey(ValueKey<String>('plus-entry-$id'));

Future<void> _openPlus(AppFixture app) async {
  await app.tester.tap(plusButton());
  await app.tester.pump();
  await app.settle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final path = 'build/shell/$name.png';
  await savePng(tester, path);
  expect(File(path).existsSync(), isTrue, reason: path);
}

void main() {
  group('plus menu semantics (AT34)', () {
    testSemantics(
      'is announced as a route with its title, entries are labelled buttons',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        await _openPlus(app);
        final sheet = tester.getSemantics(find.byType(PlusSheet));
        expect(sheet.label, 'Was möchtest du eintragen?');
        expect(sheet.flagsCollection.scopesRoute, isTrue);
        expect(sheet.flagsCollection.namesRoute, isTrue);
        for (final entry in <(String, String)>[
          ('weight', 'Gewicht'),
          ('workout', 'Workout'),
          ('water', 'Wasser'),
          ('steps', 'Schritte'),
          ('focus', 'Fokus'),
          ('task', 'Aufgabe'),
          ('habit', 'Gewohnheit'),
          ('meal', 'Mahlzeit'),
        ]) {
          final node = tester.getSemantics(find.bySemanticsLabel(entry.$2));
          expect(node.label, entry.$2);
          expect(node.flagsCollection.isButton, isTrue, reason: entry.$1);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
            reason: entry.$1,
          );
          expect(_entry(entry.$1), findsOneWidget);
        }
        // Its own close button and the scrim's label.
        expect(find.bySemanticsLabel('Schließen'), findsWidgets);
      },
    );

    testSemantics('the plus button names itself and the open state', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, modules: fullFakeModules());
      expect(find.bySemanticsLabel('Eintrag hinzufügen'), findsOneWidget);
      await _openPlus(app);
      // While the menu is open the button announces that it closes.
      expect(find.bySemanticsLabel('Schließen'), findsWidgets);
    });

    testSemantics('the navigation announces the selected tab', (tester) async {
      final app = await pumpFullApp(tester, tabs: _tabs);
      final home = tester.getSemantics(
        find.descendant(
          of: find.byType(AppBottomNavBar),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == 'Home',
          ),
        ),
      );
      expect(home.flagsCollection.isSelected, Tristate.isTrue);
      await tester.tap(navTab('Analyse'));
      await app.settle();
      final analysis = tester.getSemantics(
        find.descendant(
          of: find.byType(AppBottomNavBar),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == 'Analyse',
          ),
        ),
      );
      expect(analysis.flagsCollection.isSelected, Tristate.isTrue);
    });
  });

  group('touch targets and labels (AT34, Q02)', () {
    testWidgets(
      'shell and plus menu meet the tap target and label guidelines',
      (tester) async {
        final handle = tester.ensureSemantics();
        final app = await pumpFullApp(
          tester,
          tabs: _tabs,
          modules: fullFakeModules(),
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await _openPlus(app);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      },
    );
  });

  group('large text and keyboard (AT33, Q02)', () {
    for (final size in responsiveSizes) {
      testWidgets(
        'the menu at ${size.width.toInt()} px and 200 % text has every action reachable',
        (tester) async {
          final app = await pumpFullApp(
            tester,
            size: size,
            textScale: 2.0,
            tabs: _tabs,
            modules: fullFakeModules(),
          );
          await _openPlus(app);
          expect(tester.takeException(), isNull);
          for (final id in _ids) {
            await tester.ensureVisible(_entry(id));
            await tester.pump();
            final box = tester.getSize(_entry(id));
            expect(box.height, greaterThanOrEqualTo(48), reason: id);
            expect(box.width, greaterThanOrEqualTo(48), reason: id);
          }
          await tester.ensureVisible(_entry('meal'));
          await tester.tap(_entry('meal'));
          await tester.pump();
          await app.settle();
          expect(app.location, '/nutrition/new');
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'the shell at 200 % text and 320 px has no overflow and a reachable plus button',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          size: const Size(320, 640),
          textScale: 2.0,
          tabs: _tabs,
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(plusButton()).height, greaterThan(0));
        await tester.tap(navTab('Profil'));
        await app.settle();
        expect(app.location, '/profile');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('with the keyboard open the menu stays scrollable and usable', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        size: const Size(360, 640),
        textScale: 1.5,
        viewInsets: const EdgeInsets.only(bottom: 280),
        modules: fullFakeModules(),
      );
      await _openPlus(app);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_entry('meal'));
      await tester.tap(_entry('meal'));
      await tester.pump();
      await app.settle();
      expect(app.location, '/nutrition/new');
    });
  });

  group('system bars (Q02)', () {
    testWidgets(
      'with a gesture bar the menu floats directly above the navigation',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          systemPadding: const EdgeInsets.only(top: 24, bottom: 34),
          tabs: _tabs,
          modules: fullFakeModules(),
        );
        await _openPlus(app);
        final navigationTop = tester
            .getTopLeft(find.byType(AppBottomNavBar))
            .dy;
        final sheetBottom = tester.getBottomLeft(find.byType(PlusSheet)).dy;
        expect(sheetBottom, lessThanOrEqualTo(navigationTop));
        expect(navigationTop - sheetBottom, lessThan(24));
        // The navigation bar keeps clear of the gesture bar itself.
        final navigation = tester.getRect(find.byType(AppBottomNavBar));
        expect(navigation.bottom, tester.view.physicalSize.height);
        expect(navigation.height, greaterThan(88));
      },
    );
  });

  group('visual verification (PNG in build/shell)', () {
    testWidgets('shell, plus menu and module manager in Light', (tester) async {
      final app = await pumpFullApp(
        tester,
        tabs: _tabs,
        modules: fullFakeModules(),
      );
      await _capture(tester, 'home_light');
      await _openPlus(app);
      await _capture(tester, 'plus_light');
    });

    testWidgets('plus menu at 320 px and 200 % text', (tester) async {
      final app = await pumpFullApp(
        tester,
        size: const Size(320, 640),
        textScale: 2.0,
        tabs: _tabs,
        modules: fullFakeModules(),
      );
      await _capture(tester, 'home_320_200');
      await _openPlus(app);
      await _capture(tester, 'plus_320_200');
    });

    testWidgets('plus menu with a running focus session and in Dark', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final app = await pumpFullApp(
        tester,
        tabs: _tabs,
        modules: fullFakeModules(),
      );
      await _openPlus(app);
      await _capture(tester, 'plus_dark');
    });

    testWidgets('plus menu with every module off', (tester) async {
      final app = await pumpFullApp(
        tester,
        tabs: _tabs,
        modules: fullFakeModules(),
        enabledModules: <String>{},
      );
      await _openPlus(app);
      await _capture(tester, 'plus_all_off');
    });

    testWidgets('module manager with the real modules', (tester) async {
      final app = await pumpFullApp(tester);
      unawaited(app.router.push<void>('/settings/modules'));
      await tester.pump();
      await app.settle();
      await _capture(tester, 'modules_light');
    });

    testWidgets('module manager at 320 px and 200 % text', (tester) async {
      final app = await pumpFullApp(
        tester,
        size: const Size(320, 640),
        textScale: 2.0,
      );
      unawaited(app.router.push<void>('/settings/modules'));
      await tester.pump();
      await app.settle();
      await _capture(tester, 'modules_320_200');
    });

    testWidgets('module manager with every module off', (tester) async {
      final app = await pumpFullApp(tester, enabledModules: <String>{});
      unawaited(app.router.push<void>('/settings/modules'));
      await tester.pump();
      await app.settle();
      await _capture(tester, 'modules_all_off');
    });

    testWidgets('bootstrap error and not-found screens', (tester) async {
      final app = await pumpFullApp(tester);
      unawaited(app.router.push<void>('/nowhere'));
      await tester.pump();
      await app.settle();
      await _capture(tester, 'not_found');
    });
  });
}
