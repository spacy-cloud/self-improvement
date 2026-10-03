import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/features/reminders/presentation/reminders_section.dart';
import 'package:self_improvement/features/settings/application/license_providers.dart';
import 'package:self_improvement/features/settings/application/settings_providers.dart';

import '../../../support/pump_app.dart';
import '../../profile/support/screen_env.dart';

Finder switchOf(String label) => find.byWidgetPredicate(
  (widget) => widget is AppSwitch && widget.semanticLabel == label,
);

bool isOn(WidgetTester tester, String label) =>
    tester.widget<AppSwitch>(switchOf(label)).value;

Future<void> tapRow(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await settle(tester);
}

Future<void> restart(WidgetTester tester, ScreenEnv env) async {
  // The process is killed (the widget tree is gone) and started again.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  env.newContainer();
}

void main() {
  group('content', () {
    testWidgets('has the groups of the design and only working controls', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, SettingsRoutes.settings);

      for (final heading in [
        'PROFIL',
        'DARSTELLUNG',
        'MODULE',
        'DATEN',
        'ÜBER DIE APP',
      ]) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
      for (final row in [
        'Design',
        'Reduzierte Bewegung',
        'Haptisches Feedback',
        'Module verwalten',
        'Daten & Sicherung',
        'Version',
        'Lizenzen',
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      expect(find.text('1.0.0'), findsOneWidget);
      expect(find.text('Nur lokal'), findsOneWidget);

      // Seven rows and two switches: nothing without a function, no account
      // or cloud switch, no export/import/reset shortcuts.
      expect(find.byType(EntryListTile), findsNWidgets(7));
      expect(find.byType(AppSwitch), findsNWidgets(2));
      expect(find.byType(Switch), findsNothing);
      expect(find.text('Konto löschen'), findsNothing);
      expect(find.text('Alle Daten zurücksetzen'), findsNothing);
      await savePng(tester, 'build/profile_shots/settings.png');
    });

    testWidgets('embeds the reminders block exactly once (AT28)', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, SettingsRoutes.settings);
      expect(find.byType(RemindersSection), findsOneWidget);
      // The rest of the page works whatever the reminders block shows.
      await tapRow(tester, 'Reduzierte Bewegung');
      expect(isOn(tester, 'Reduzierte Bewegung'), isTrue);
    });

    testWidgets('shows the profile entry with the name or the default', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, SettingsRoutes.settings);
      expect(find.text('Mein Profil'), findsOneWidget);
      await saveProfile(tester, env, name: 'Max Mustermann');
      expect(find.text('Max Mustermann'), findsOneWidget);
      expect(find.text('MM'), findsOneWidget);
      expect(find.text('Name und Körperdaten'), findsOneWidget);
    });

    testWidgets('counts the active modules', (tester) async {
      final env = await createScreenEnv(
        tester,
        enabledModules: {'body', 'tasks'},
      );
      await openScreen(tester, env, SettingsRoutes.settings);
      expect(find.text('2 von 5'), findsOneWidget);
    });

    testWidgets(
      'without the body module the profile entry only names the name',
      (tester) async {
        final env = await createScreenEnv(tester, enabledModules: {'tasks'});
        await openScreen(tester, env, SettingsRoutes.settings);
        expect(find.text('Name und Körperdaten'), findsNothing);
        expect(find.text('Name'), findsOneWidget);
      },
    );

    testWidgets('mentions a system request for reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, SettingsRoutes.settings);
      expect(
        find.text('Animationen abschalten. Das System fordert sie bereits an.'),
        findsOneWidget,
      );
    });
  });

  group('theme (C06, AT35)', () {
    testWidgets('the sheet offers four choices and marks the current one', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, SettingsRoutes.settings);
      expect(find.text('System'), findsOneWidget, reason: 'value of the row');
      await tapRow(tester, 'Design');

      expect(find.text('Design wählen'), findsOneWidget);
      for (final mode in ['System', 'Hell', 'Dunkel', 'OLED']) {
        expect(find.text(mode), findsWidgets, reason: mode);
      }
      expect(find.text('Schließen'), findsOneWidget);
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(
          'System, Folgt deinem Gerät: Hell oder Dunkel, ausgewählt',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('OLED, Reines Schwarz als Hintergrund'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('choosing OLED saves it, shows it and reaches the app theme', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, SettingsRoutes.settings);
      await tapRow(tester, 'Design');
      await tester.tap(find.text('OLED'));
      await settle(tester);

      expect(
        find.text('Design wählen'),
        findsNothing,
        reason: 'the sheet closed',
      );
      expect(find.text('OLED'), findsOneWidget, reason: 'value of the row');
      expect(env.container.read(appThemeModeProvider), AppThemeMode.oled);
      final settings = (await tester.runAsync(
        () => env.container.read(appSettingsRepositoryProvider).get(),
      ))!;
      expect(settings.themeModeKey, 'oled');
    });

    testWidgets(
      'closing the sheet or choosing the current theme changes nothing',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, SettingsRoutes.settings);

        await tapRow(tester, 'Design');
        await tester.tap(find.text('Schließen'));
        await settle(tester);
        expect(find.text('Design wählen'), findsNothing);

        await tapRow(tester, 'Design');
        await tester.binding.handlePopRoute(); // Android back
        await settle(tester);
        expect(find.text('Design wählen'), findsNothing);
        expect(
          find.text('Einstellungen'),
          findsOneWidget,
          reason: 'page stays',
        );

        await tapRow(tester, 'Design');
        await tester.tap(find.text('System').last);
        await settle(tester);
        expect(env.settingsCommands.commandIds, isEmpty);
      },
    );

    testWidgets('the choice survives a restart (AT02)', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, SettingsRoutes.settings);
      await tapRow(tester, 'Design');
      await tester.tap(find.text('Dunkel'));
      await settle(tester);

      await restart(tester, env);
      await openScreen(tester, env, SettingsRoutes.settings);
      expect(find.text('Dunkel'), findsOneWidget);
      expect(env.container.read(appThemeModeProvider), AppThemeMode.dark);
    });

    for (final variant in AppThemeVariant.values) {
      testWidgets('renders in the ${variant.name} theme with its tokens', (
        tester,
      ) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, SettingsRoutes.settings, theme: variant);
        final tokens = AppTokens.forVariant(variant);
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
        expect(scaffold.backgroundColor, tokens.colors.background);
        expect(find.text('Einstellungen'), findsOneWidget);
        await savePng(
          tester,
          'build/profile_shots/settings_${variant.name}.png',
        );
      });
    }
  });

  group('switches', () {
    testWidgets('reduced motion is saved and survives a restart (AT02)', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, SettingsRoutes.settings);
      expect(isOn(tester, 'Reduzierte Bewegung'), isFalse);
      await tapRow(tester, 'Reduzierte Bewegung');
      expect(isOn(tester, 'Reduzierte Bewegung'), isTrue);
      expect(env.container.read(reduceMotionProvider), isTrue);

      await restart(tester, env);
      await openScreen(tester, env, SettingsRoutes.settings);
      expect(isOn(tester, 'Reduzierte Bewegung'), isTrue);
    });

    testWidgets(
      'haptic feedback starts on, can be switched off and stays off',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, SettingsRoutes.settings);
        expect(isOn(tester, 'Haptisches Feedback'), isTrue);
        await tapRow(tester, 'Haptisches Feedback');
        expect(isOn(tester, 'Haptisches Feedback'), isFalse);
        expect(env.container.read(hapticsEnabledProvider), isFalse);

        await restart(tester, env);
        await openScreen(tester, env, SettingsRoutes.settings);
        expect(isOn(tester, 'Haptisches Feedback'), isFalse);
      },
    );

    testWidgets(
      'a failed write keeps the switch where it was and offers a retry',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, SettingsRoutes.settings);
        env.projection.failure = StateError('disk full');
        await tapRow(tester, 'Reduzierte Bewegung');

        expect(isOn(tester, 'Reduzierte Bewegung'), isFalse);
        expect(env.feedback.last!.kind, 'error');
        expect(
          env.feedback.last!.message,
          'Die Einstellung konnte nicht gespeichert werden. Der bisherige Wert bleibt aktiv.',
        );
        env.projection.failure = null;
        env.feedback.last!.onRetry!();
        await settle(tester);
        expect(isOn(tester, 'Reduzierte Bewegung'), isTrue);
        expect(env.settingsCommands.commandIds, hasLength(2));
        expect(
          env.settingsCommands.commandIds[0],
          env.settingsCommands.commandIds[1],
        );
      },
    );

    testWidgets('a double tap writes once', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, SettingsRoutes.settings);
      await tester.ensureVisible(find.text('Reduzierte Bewegung'));
      await tester.tap(find.text('Reduzierte Bewegung'));
      await tester.tap(find.text('Reduzierte Bewegung'));
      await settle(tester);
      expect(env.settingsCommands.commandIds, hasLength(1));
      expect(isOn(tester, 'Reduzierte Bewegung'), isTrue);
    });
  });

  group('links', () {
    testWidgets('the profile entry opens the editor', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, SettingsRoutes.settings);
      await tester.tap(find.text('Mein Profil'));
      await settle(tester);
      expect(find.text('Profil speichern'), findsOneWidget);
    });

    testWidgets('modules and data lead to their screens', (tester) async {
      final env = await createScreenEnv(tester);
      final router = await openScreen(tester, env, SettingsRoutes.settings);
      await tapRow(tester, 'Module verwalten');
      expect(find.text('Seite ${SettingsRoutes.modules}'), findsOneWidget);
      router.pop();
      await settle(tester);
      await tapRow(tester, 'Daten & Sicherung');
      expect(find.text('Seite ${SettingsRoutes.data}'), findsOneWidget);
    });

    testWidgets('licences open the licence page and back returns', (
      tester,
    ) async {
      final env = await createScreenEnv(
        tester,
        overrides: [
          licenseSourceProvider.overrideWithValue(
            () => Stream.fromIterable([
              LicenseEntryWithLineBreaks(['Inter'], 'SIL OPEN FONT LICENSE'),
            ]),
          ),
        ],
      );
      await openScreen(tester, env, SettingsRoutes.settings);
      await tapRow(tester, 'Lizenzen');
      expect(find.text('Inter (Schrift)'), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is AppIconButton && w.semanticLabel == 'Zurück',
        ),
      );
      await settle(tester);
      expect(find.text('Einstellungen'), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('a load error offers a retry', (tester) async {
      var reads = 0;
      final env = await createScreenEnv(
        tester,
        overrides: [
          appSettingsProvider.overrideWith((ref) {
            reads++;
            if (reads == 1) {
              return Stream.error(StateError('boom'));
            }
            return ref.watch(appSettingsRepositoryProvider).watch();
          }),
        ],
      );
      await openScreen(tester, env, SettingsRoutes.settings);
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await settle(tester);
      expect(find.text('Design'), findsOneWidget);
    });
  });

  testWidgets('every row has a spoken German label with its state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final env = await createScreenEnv(tester);
    await openScreen(tester, env, SettingsRoutes.settings);
    expect(find.bySemanticsLabel('Zurück'), findsOneWidget);
    expect(find.bySemanticsLabel('Design, System, ändern'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Reduzierte Bewegung, Animationen abschalten'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Haptisches Feedback, Vibration beim Abhaken'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Haptisches Feedback, Vibration beim Abhaken'),
      ),
      matchesSemantics(
        label: 'Haptisches Feedback, Vibration beim Abhaken',
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}
