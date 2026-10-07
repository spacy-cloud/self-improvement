import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/features/gamification/presentation/progress_screen.dart';
import 'package:self_improvement/features/gamification/presentation/streak_screen.dart';
import 'package:self_improvement/features/modules/presentation/modules_screen.dart';
import 'package:self_improvement/features/profile/presentation/goals_screen.dart';
import 'package:self_improvement/features/profile/presentation/profile_edit_screen.dart';
import 'package:self_improvement/features/settings/presentation/about_screen.dart';
import 'package:self_improvement/features/settings/presentation/data_screen.dart';
import 'package:self_improvement/features/settings/presentation/licenses_screen.dart';
import 'package:self_improvement/features/settings/presentation/settings_screen.dart';

import 'support/app_harness.dart';
import 'support/fake_modules.dart';

const String _uuid = '123e4567-e89b-42d3-a456-426614174000';

Future<void> _push(AppFixture app, String location) async {
  unawaited(app.router.push<void>(location));
  await app.tester.pump();
  await app.settle();
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
  group('unknown routes and malformed ids (C02)', () {
    testWidgets('an unknown route shows the not-found screen with a way back', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, modules: fullFakeModules());
      await _push(app, '/does/not/exist');
      expect(find.text('Diese Seite gibt es nicht'), findsOneWidget);
      expect(find.text('Zur Startseite'), findsOneWidget);
      // The header back button leads back to where the user came from.
      await tester.tap(find.byIcon(AppIcon.back.data));
      await app.settle();
      expect(find.text('Diese Seite gibt es nicht'), findsNothing);
      expect(find.byType(AppBottomNavBar), findsOneWidget);
    });

    testWidgets(
      '"Zur Startseite" leads to the dashboard even without history',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        app.router.go('/nowhere');
        await tester.pump();
        await app.settle();
        expect(find.text('Diese Seite gibt es nicht'), findsOneWidget);
        await tester.tap(find.text('Zur Startseite'));
        await app.settle();
        expect(app.location, '/');
        expect(find.byType(AppBottomNavBar), findsOneWidget);
      },
    );

    testWidgets('a malformed id never reaches a screen', (tester) async {
      final app = await pumpFullApp(tester, modules: fullFakeModules());
      for (final location in <String>[
        '/weight/abc',
        '/weight/123',
        '/weight/${_uuid.toUpperCase()}',
        '/habits/not-an-id',
        '/habits/$_uuid-x',
      ]) {
        await _push(app, location);
        expect(
          find.text('Diese Seite gibt es nicht'),
          findsOneWidget,
          reason: location,
        );
        expect(find.textContaining('probe:'), findsNothing, reason: location);
        await tester.tap(find.byIcon(AppIcon.back.data));
        await app.settle();
      }
    });

    testWidgets('a valid id reaches the screen with its parameter', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, modules: fullFakeModules());
      await _push(app, '/weight/$_uuid');
      expect(find.text('probe:weight-edit {id: $_uuid}'), findsOneWidget);
    });

    testWidgets('/weight/new and /weight/all are never read as ids', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, modules: fullFakeModules());
      await _push(app, '/weight/new');
      expect(find.text('probe:weight-new'), findsOneWidget);
      await tester.tap(find.byIcon(AppIcon.back.data));
      await app.settle();
      await _push(app, '/weight/all');
      expect(find.text('probe:weight-all'), findsOneWidget);
    });

    testWidgets(
      'an id that is valid but unknown shows the screen\'s own state, no crash',
      (tester) async {
        final app = await pumpFullApp(tester);
        await _push(app, '/weight/$_uuid');
        expect(tester.takeException(), isNull);
        expect(find.text('Eintrag nicht gefunden'), findsOneWidget);
      },
    );

    testWidgets('the real weight form opens on /weight/new', (tester) async {
      final app = await pumpFullApp(tester);
      await _push(app, '/weight/new');
      expect(find.text('Gewicht eintragen'), findsWidgets);
      expect(app.location, '/weight/new');
    });
  });

  group('routes of a disabled module (C03, AT03)', () {
    testWidgets('show an understandable screen with "Modul aktivieren"', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        modules: fullFakeModules(),
        enabledModules: <String>{'nutrition', 'focus', 'tasks', 'gamification'},
      );
      await _push(app, '/weight/new');
      expect(find.text('Gewicht & Körper ist ausgeschaltet'), findsOneWidget);
      expect(find.textContaining('Deine Daten bleiben'), findsOneWidget);
      expect(find.text('Modul aktivieren'), findsOneWidget);
      expect(find.text('Module verwalten'), findsOneWidget);
      expect(find.text('probe:weight-new'), findsNothing);
    });

    testWidgets('activating shows the real screen in place and says so', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        modules: fullFakeModules(),
        enabledModules: <String>{'nutrition', 'focus', 'tasks', 'gamification'},
      );
      await _push(app, '/weight/new');
      await tester.tap(find.text('Modul aktivieren'));
      await app.settle();
      expect(find.text('probe:weight-new'), findsOneWidget);
      expect(find.text('Modul aktivieren'), findsNothing);
      expect(find.text('Gewicht & Körper eingeschaltet.'), findsOneWidget);
      expect(app.location, '/weight/new');
      expect(
        (await app.harness.moduleStatus.statuses())[ModuleId.body],
        isTrue,
      );
    });

    testWidgets('"Module verwalten" opens the module manager', (tester) async {
      final app = await pumpFullApp(
        tester,
        modules: fullFakeModules(),
        enabledModules: <String>{'nutrition', 'focus', 'tasks', 'gamification'},
      );
      await _push(app, '/weight/new');
      await tester.tap(find.text('Module verwalten'));
      await app.settle();
      expect(find.byType(ModulesScreen), findsOneWidget);
    });

    testWidgets(
      'an open screen turns into the same state when its module is switched off',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        await _push(app, '/weight/new');
        expect(find.text('probe:weight-new'), findsOneWidget);
        await _setModule(app, ModuleId.body, enabled: false);
        await app.settle();
        expect(find.text('Modul aktivieren'), findsOneWidget);
        expect(find.text('probe:weight-new'), findsNothing);
        await _setModule(app, ModuleId.body, enabled: true);
        await app.settle();
        expect(find.text('probe:weight-new'), findsOneWidget);
      },
    );

    testWidgets('streak and progress belong to the gamification module', (
      tester,
    ) async {
      final app = await pumpFullApp(tester);
      await _push(app, '/streak');
      expect(find.byType(StreakScreen), findsOneWidget);
      await _setModule(app, ModuleId.gamification, enabled: false);
      await app.settle();
      expect(find.byType(StreakScreen), findsNothing);
      expect(find.text('Gamification ist ausgeschaltet'), findsOneWidget);
      await tester.tap(find.byIcon(AppIcon.back.data));
      await app.settle();
      await _push(app, '/progress');
      expect(find.text('Gamification ist ausgeschaltet'), findsOneWidget);
      await _setModule(app, ModuleId.gamification, enabled: true);
      await app.settle();
      expect(find.byType(ProgressScreen), findsOneWidget);
    });

    testWidgets('a malformed id wins over a disabled module', (tester) async {
      final app = await pumpFullApp(
        tester,
        modules: fullFakeModules(),
        enabledModules: <String>{'nutrition', 'focus', 'tasks', 'gamification'},
      );
      await _push(app, '/weight/abc');
      expect(find.text('Diese Seite gibt es nicht'), findsOneWidget);
    });
  });

  group('core routes are registered once and reach their screens (C02)', () {
    final cases = <String, Type>{
      '/profile/edit': ProfileEditScreen,
      '/goals': GoalsScreen,
      '/settings': SettingsScreen,
      '/settings/modules': ModulesScreen,
      '/settings/data': DataScreen,
      '/settings/licenses': LicensesScreen,
      '/settings/about': AboutScreen,
    };
    for (final entry in cases.entries) {
      testWidgets('${entry.key} opens ${entry.value}', (tester) async {
        final app = await pumpFullApp(tester);
        await _push(app, entry.key);
        expect(find.byType(entry.value), findsOneWidget);
        expect(find.byType(AppBottomNavBar), findsNothing);
      });
    }
  });
}
