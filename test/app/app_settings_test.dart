import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/command_providers.dart';

import 'support/app_harness.dart';

Future<void> _setTheme(AppFixture app, String key) => app.run(
  () => app.container
      .read(settingsCommandsProvider)
      .setThemeMode(commandId: app.harness.ids.newId(), themeModeKey: key),
);

void main() {
  group('theme from the settings (C06)', () {
    testWidgets('Light, Dark and OLED are applied when chosen', (tester) async {
      final app = await pumpFullApp(tester);
      Color background() =>
          Theme.of(tester.element(find.byType(AppBottomNavBar)))
              .scaffoldBackgroundColor;

      await _setTheme(app, 'light');
      await app.settle();
      expect(background(), AppTokens.light.colors.background);

      await _setTheme(app, 'dark');
      await app.settle();
      expect(background(), AppTokens.dark.colors.background);

      await _setTheme(app, 'oled');
      await app.settle();
      expect(background(), AppTokens.oled.colors.background);
      expect(background(), const Color(0xFF000000));
    });

    testWidgets('System follows the platform brightness and never picks OLED', (
      tester,
    ) async {
      final app = await pumpFullApp(tester);
      Color background() =>
          Theme.of(tester.element(find.byType(AppBottomNavBar)))
              .scaffoldBackgroundColor;
      await _setTheme(app, 'system');
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await app.settle();
      expect(background(), AppTokens.dark.colors.background);
      expect(background(), isNot(AppTokens.oled.colors.background));
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await app.settle();
      expect(background(), AppTokens.light.colors.background);
    });
  });

  group('reduced motion (Q03)', () {
    testWidgets('the app setting reaches every screen', (tester) async {
      final app = await pumpFullApp(tester, animations: true);
      final before = tester.element(find.byType(AppBottomNavBar));
      expect(AppMotion.of(before).reduced, isFalse);
      await app.run(
        () => app.container
            .read(settingsCommandsProvider)
            .setReduceMotion(commandId: app.harness.ids.newId(), value: true),
      );
      await app.settle();
      final after = tester.element(find.byType(AppBottomNavBar));
      expect(AppMotion.of(after).reduced, isTrue);
      expect(AppMotion.of(after).fast, Duration.zero);
    });

    testWidgets('the system flag is honoured without the app setting', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpFullApp(tester);
      final context = tester.element(find.byType(AppBottomNavBar));
      expect(AppMotion.of(context).reduced, isTrue);
    });
  });

  group('locale', () {
    testWidgets('the app speaks German', (tester) async {
      await pumpFullApp(tester);
      final context = tester.element(find.byType(AppBottomNavBar));
      expect(Localizations.localeOf(context).languageCode, 'de');
      expect(MaterialLocalizations.of(context).backButtonTooltip, 'Zurück');
    });
  });
}
