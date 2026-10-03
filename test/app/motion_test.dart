import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/router/app_pages.dart';
import 'package:self_improvement/app/shell/plus_sheet.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/features/settings/presentation/settings_screen.dart';

import 'support/app_harness.dart';

/// Page changes and the plus sheet move unless motion is reduced; the app
/// setting "Reduzierte Bewegung" reaches them like the system flag (AT35, Q03).
Future<void> _setReduceMotion(AppFixture app, bool value) => app.run(
  () => app.container
      .read(settingsCommandsProvider)
      .setReduceMotion(commandId: app.harness.ids.newId(), value: value),
);

Future<void> _reduceMotion(AppFixture app) => _setReduceMotion(app, true);

/// How long the transition of the settings page lasts.
Duration _transitionOfSettings(WidgetTester tester) =>
    ModalRoute.of(tester.element(find.byType(SettingsScreen)))!
        .transitionDuration;

/// How long the transition back from the settings page lasts.
Duration _reverseTransitionOfSettings(WidgetTester tester) =>
    ModalRoute.of(tester.element(find.byType(SettingsScreen)))!
        .reverseTransitionDuration;

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

        expect(_topPage(tester), isA<AppPage<void>>());
        expect(_transitionOfSettings(tester), greaterThan(Duration.zero));
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

      expect(_topPage(tester), isA<AppPage<void>>());
      expect(_transitionOfSettings(tester), Duration.zero);
      expect(_reverseTransitionOfSettings(tester), Duration.zero);
    });

    testWidgets('are immediate when the system flag reduces motion', (
      tester,
    ) async {
      final app = await pumpFullApp(tester);
      unawaited(app.router.push<void>('/settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_topPage(tester), isA<AppPage<void>>());
      expect(_transitionOfSettings(tester), Duration.zero);
    });

    testWidgets('module routes get the same page', (tester) async {
      final app = await pumpFullApp(tester, animations: true);
      unawaited(app.router.push<void>('/weight/new'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_topPage(tester), isA<AppPage<void>>());
    });

    testWidgets(
      'follow the setting at the moment they run, in both directions',
      (tester) async {
        final app = await pumpFullApp(tester, animations: true);
        Future<Duration> pushAndLeave() async {
          unawaited(app.router.push<void>('/settings'));
          await tester.pumpAndSettle();
          final duration = _transitionOfSettings(tester);
          app.router.pop();
          await tester.pumpAndSettle();
          return duration;
        }

        expect(await pushAndLeave(), greaterThan(Duration.zero));
        await _setReduceMotion(app, true);
        await app.settle();
        expect(await pushAndLeave(), Duration.zero);
        await _setReduceMotion(app, false);
        await app.settle();
        expect(await pushAndLeave(), greaterThan(Duration.zero));
      },
    );
  });

  group('flipping the setting while pages are open', () {
    testWidgets('keeps the page and its scroll position', (tester) async {
      final app = await pumpFullApp(
        tester,
        animations: true,
        size: const Size(393, 520),
      );
      unawaited(app.router.push<void>('/settings'));
      await tester.pumpAndSettle();
      final row = find.text('Reduzierte Bewegung');
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final page = tester.element(find.byType(SettingsScreen));
      double offset() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(SettingsScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .pixels;
      final before = offset();
      expect(before, greaterThan(0), reason: 'scrolled down to the switch');

      await tester.tap(row);
      await app.settle();
      await tester.pumpAndSettle();

      expect(
        tester.element(find.byType(SettingsScreen)),
        same(page),
        reason: 'the page is updated in place, not built again',
      );
      expect(offset(), before);
    });

    testWidgets('keeps a sheet that is open above a page', (tester) async {
      final app = await pumpFullApp(tester, animations: true);
      unawaited(app.router.push<void>('/settings'));
      await tester.pumpAndSettle();
      var closed = false;
      unawaited(
        showConfirmationSheet(
          tester.element(find.byType(SettingsScreen)),
          title: 'Sheet zum Prüfen',
          message: 'Bleibt offen.',
          confirmLabel: 'Ja',
        ).then((_) => closed = true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sheet zum Prüfen'), findsOneWidget);

      // What an import or a reset does: the stored setting changes underneath.
      await _reduceMotion(app);
      await app.settle();
      await tester.pumpAndSettle();

      expect(find.text('Sheet zum Prüfen'), findsOneWidget);
      expect(closed, isFalse);
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
