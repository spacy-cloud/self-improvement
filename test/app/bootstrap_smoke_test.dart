import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/bootstrap/app_services.dart';
import 'package:self_improvement/app/bootstrap/bootstrap_screens.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/onboarding/presentation/onboarding_screen.dart';

import '../support/pump_app.dart';
import 'support/app_harness.dart';

AppServices _services(DataHarness harness) => AppServices(
  database: harness.database,
  clock: harness.clock,
  zoneSource: const FixedZoneSource(),
  dispose: () async {},
);

void main() {
  group('start', () {
    testWidgets(
      'an onboarded start opens the dashboard with the navigation bar',
      (tester) async {
        final app = await pumpFullApp(tester);
        expect(find.byType(AppBottomNavBar), findsOneWidget);
        expect(app.location, '/');
        expect(find.byType(BootstrapLoadingScreen), findsNothing);
      },
    );

    testWidgets('a fresh install shows the onboarding and no tab (AT01)', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, onboarded: false);
      expect(app.location, '/onboarding');
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(AppBottomNavBar), findsNothing);
    });

    testWidgets('completing the onboarding leads to the dashboard (AT01)', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, onboarded: false);
      await app.run(app.harness.seedOnboarded);
      await app.settle();
      expect(app.location, '/');
      expect(find.byType(AppBottomNavBar), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets(
      'during the onboarding no other location can be opened (AT01)',
      (tester) async {
        final app = await pumpFullApp(tester, onboarded: false);
        app.router.go('/weight/new');
        await tester.pump();
        await app.settle();
        expect(app.location, '/onboarding');
        app.router.go('/settings/modules');
        await app.settle();
        expect(app.location, '/onboarding');
      },
    );

    testWidgets('while the database opens only a neutral loading state shows', (
      tester,
    ) async {
      final gate = Completer<void>();
      final app = await pumpFullApp(
        tester,
        waitForReady: false,
        starter: (harness) async {
          await gate.future;
          return _services(harness);
        },
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(BootstrapLoadingScreen), findsOneWidget);
      // No splash: neither the app name nor a logo, and no progress indicator
      // before a moment has passed.
      expect(find.text(AppConfig.appName), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.complete();
      await app.settle();
      await tester.pumpUntil(
        () => find.byType(AppBottomNavBar).evaluate().isNotEmpty,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('bootstrap error', () {
    testWidgets(
      'a database that cannot be opened shows the error with a retry',
      (tester) async {
        await pumpFullApp(
          tester,
          waitForReady: false,
          starter: (harness) async =>
              throw const MigrationFailure(causeType: 'StateError'),
        );
        await tester.pumpUntil(
          () => find.byType(BootstrapErrorScreen).evaluate().isNotEmpty,
        );
        expect(
          find.text('Daten konnten nicht geöffnet werden'),
          findsOneWidget,
        );
        expect(find.textContaining('Es wurde nichts gelöscht'), findsOneWidget);
        expect(find.text('Fehlercode: migration'), findsOneWidget);
        expect(find.text('Erneut versuchen'), findsOneWidget);
        expect(find.byType(AppBottomNavBar), findsNothing);
        expect(find.byType(BootstrapLoadingScreen), findsNothing);
      },
    );

    testWidgets('the retry starts again and the app opens once it works', (
      tester,
    ) async {
      var calls = 0;
      await pumpFullApp(
        tester,
        waitForReady: false,
        starter: (harness) async {
          calls++;
          if (calls == 1) {
            throw const MigrationFailure(causeType: 'StateError');
          }
          return _services(harness);
        },
      );
      await tester.pumpUntil(
        () => find.byType(BootstrapErrorScreen).evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpUntil(
        () => find.byType(AppBottomNavBar).evaluate().isNotEmpty,
        reason: 'the app did not open after the retry',
      );
      expect(calls, 2);
      expect(find.byType(BootstrapErrorScreen), findsNothing);
    });

    testWidgets('an error of any kind is shown, not swallowed', (tester) async {
      await pumpFullApp(
        tester,
        waitForReady: false,
        starter: (harness) async => throw StateError('boom'),
      );
      await tester.pumpUntil(
        () => find.byType(BootstrapErrorScreen).evaluate().isNotEmpty,
      );
      expect(find.text('Fehlercode: StateError'), findsOneWidget);
      // The technical message is not shown to the user.
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets(
      'the retry stays reachable at 200 % text on a narrow screen (AT33)',
      (tester) async {
        await pumpFullApp(
          tester,
          waitForReady: false,
          size: const Size(320, 640),
          textScale: 2.0,
          starter: (harness) async =>
              throw const MigrationFailure(causeType: 'StateError'),
        );
        await tester.pumpUntil(
          () => find.byType(BootstrapErrorScreen).evaluate().isNotEmpty,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Erneut versuchen'));
        expect(find.text('Erneut versuchen'), findsOneWidget);
        final size = tester.getSize(
          find
              .ancestor(
                of: find.text('Erneut versuchen'),
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(size.height, greaterThanOrEqualTo(48));
      },
    );
  });
}
