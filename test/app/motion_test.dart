import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/shell/plus_sheet.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/features/settings/presentation/settings_screen.dart';

import 'support/app_harness.dart';

/// Page changes and the plus sheet move unless motion is reduced; the app
/// setting "Reduzierte Bewegung" reaches them like the system flag (AT35, Q03).
Future<void> _reduceMotion(AppFixture app) => app.run(
  () => app.container
      .read(settingsCommandsProvider)
      .setReduceMotion(commandId: app.harness.ids.newId(), value: true),
);

/// How long the transition of the settings page lasts.
Duration _transitionOfSettings(WidgetTester tester) =>
    ModalRoute.of(tester.element(find.byType(SettingsScreen)))!
        .transitionDuration;

Page<Object?> _topPage(WidgetTester tester) {
  final navigator = tester.widget<Navigator>(find.byType(Navigator).first);
  return navigator.pages.last;
}

void main() {
  group('page changes', () {
    testWidgets(
      'slide in with the Material transition when motion is allowed',
      (tester) async {
        final app = await pumpFullApp(tester, animations: true);
        unawaited(app.router.push<void>('/settings'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(_topPage(tester), isA<MaterialPage<void>>());
        expect(
          tester.binding.transientCallbackCount,
          greaterThan(0),
          reason: 'the transition is still running 50 ms in',
        );
        await tester.pumpAndSettle();
        expect(find.text('Einstellungen'), findsWidgets);
      },
    );

    testWidgets('are immediate when the app setting reduces motion', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, animations: true);
      await _reduceMotion(app);
      await app.settle();
      unawaited(app.router.push<void>('/settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_topPage(tester), isA<NoTransitionPage<void>>());
      expect(_transitionOfSettings(tester), Duration.zero);
    });

    testWidgets('are immediate when the system flag reduces motion', (
      tester,
    ) async {
      final app = await pumpFullApp(tester);
      unawaited(app.router.push<void>('/settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_topPage(tester), isA<NoTransitionPage<void>>());
      expect(_transitionOfSettings(tester), Duration.zero);
    });

    testWidgets('module routes get the same page', (tester) async {
      final app = await pumpFullApp(tester, animations: true);
      unawaited(app.router.push<void>('/weight/new'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_topPage(tester), isA<MaterialPage<void>>());
    });
  });

  group('the plus sheet', () {
    Future<double> sheetTopAfterOneFrame(AppFixture app) async {
      await app.tester.tap(plusButton());
      await app.tester.pump();
      await app.tester.pump(const Duration(milliseconds: 16));
      return app.tester.getTopLeft(find.byType(PlusSheet)).dy;
    }

    testWidgets('slides up when motion is allowed', (tester) async {
      final app = await pumpFullApp(tester, animations: true);
      final early = await sheetTopAfterOneFrame(app);
      await tester.pumpAndSettle();
      final settled = tester.getTopLeft(find.byType(PlusSheet)).dy;
      expect(early, greaterThan(settled), reason: 'still on its way up');
    });

    testWidgets('appears in place when the app setting reduces motion', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, animations: true);
      await _reduceMotion(app);
      await app.settle();
      final early = await sheetTopAfterOneFrame(app);
      await tester.pumpAndSettle();
      final settled = tester.getTopLeft(find.byType(PlusSheet)).dy;
      expect(early, settled, reason: 'no slide');
    });
  });
}
