import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/router/app_pages.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/features/settings/presentation/about_screen.dart';
import 'package:self_improvement/features/settings/presentation/licenses_screen.dart';

import 'support/app_harness.dart';

/// The page "Über die App" in the running app: it opens from the "Version" row
/// of the settings, is a sub page without navigation bar, and its page change
/// follows the motion setting like the other core pages (BS-118, AT35).
Future<void> _setReduceMotion(AppFixture app, bool value) => app.run(
  () => app.container
      .read(settingsCommandsProvider)
      .setReduceMotion(commandId: app.harness.ids.newId(), value: value),
);

Page<Object?> _topPage(WidgetTester tester) {
  final navigator = tester.widget<Navigator>(find.byType(Navigator).first);
  return navigator.pages.last;
}

/// How long the transition of the page of [screen] lasts.
Duration _transitionOf(WidgetTester tester, Type screen) =>
    ModalRoute.of(tester.element(find.byType(screen)))!.transitionDuration;

void main() {
  testWidgets(
    'the Version row of the settings opens the page, system back returns '
    '(BS-118)',
    (tester) async {
      final app = await pumpFullApp(tester);
      unawaited(app.router.push<void>(AppRoutes.settings));
      await app.settle();

      final row = find.text('Version');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await app.settle();

      expect(app.location, AppRoutes.about);
      expect(find.byType(AboutScreen), findsOneWidget);
      expect(find.byType(AppBottomNavBar), findsNothing, reason: 'sub page');

      expect(await app.systemBack(), isTrue, reason: 'the app handled back');
      expect(app.location, AppRoutes.settings);
      expect(find.byType(AboutScreen), findsNothing);
    },
  );

  testWidgets(
    'the page slides in with the Material transition while motion is allowed '
    '(BS-118, AT35)',
    (tester) async {
      final app = await pumpFullApp(tester, animations: true);
      unawaited(app.router.push<void>(AppRoutes.about));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_topPage(tester), isA<AppPage<void>>());
      expect(_transitionOf(tester, AboutScreen), greaterThan(Duration.zero));
      expect(
        tester.binding.transientCallbackCount,
        greaterThan(0),
        reason: 'the transition is still running 50 ms in',
      );
      await tester.pumpAndSettle();
      expect(find.byType(AboutScreen), findsOneWidget);
    },
  );

  testWidgets(
    'the page changes at once when the app setting reduces motion, like the '
    'licence page (BS-118, AT35)',
    (tester) async {
      final app = await pumpFullApp(tester, animations: true);
      await _setReduceMotion(app, true);
      await app.settle();

      final pages = <String, Type>{
        AppRoutes.licenses: LicensesScreen,
        AppRoutes.about: AboutScreen,
      };
      for (final entry in pages.entries) {
        unawaited(app.router.push<void>(entry.key));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(_topPage(tester), isA<AppPage<void>>(), reason: entry.key);
        expect(
          _transitionOf(tester, entry.value),
          Duration.zero,
          reason: entry.key,
        );
        app.router.pop();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('the page changes at once when the system flag reduces motion', (
    tester,
  ) async {
    final app = await pumpFullApp(tester);
    unawaited(app.router.push<void>(AppRoutes.about));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_transitionOf(tester, AboutScreen), Duration.zero);
  });
}
