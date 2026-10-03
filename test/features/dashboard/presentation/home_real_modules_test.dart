import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/features/dashboard/presentation/home_screen.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/dashboard_test_kit.dart';

/// The dashboard with the bundled modules exactly as the app wires them (no
/// stand-in modules): the cards come from the real module contract.
Future<_Home> _pump(
  WidgetTester tester, {
  Set<String>? enabledModules,
  LocalDate? startedOn,
  Size size = const Size(393, 852),
  double scale = 1.0,
}) async {
  final harness = await createHarness(
    tester,
    startedOn: startedOn ?? LocalDate(2026, 10, 2),
    enabledModules: enabledModules,
  );
  final container = harness.createContainer(
    overrides: [
      feedbackServiceProvider.overrideWithValue(RecordingFeedbackService()),
    ],
  );
  final router = await pumpRouterApp(
    tester,
    container: container,
    size: size,
    textScale: scale,
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      for (final module in bundledModules) ...module.routes,
    ],
  );
  await settle(tester);
  return _Home(container, router);
}

final class _Home {
  const _Home(this.container, this.router);

  final ProviderContainer container;
  final GoRouter router;
}

void main() {
  testWidgets('(C03, C04) the bundled modules fill the dashboard: steps and weight from the body '
      'module, XP from the progress module', (tester) async {
    await _pump(tester);
    expect(find.text('Schritte'), findsOneWidget);
    expect(find.text('Gewicht'), findsOneWidget);
    expect(find.text('XP und Level'), findsOneWidget);
    expect(find.text('Noch keine Messung'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Default order: steps before weight before XP.
    expect(
      tester.getTopLeft(find.text('Schritte')).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.text('Gewicht')).dy),
    );
    await tester.ensureVisible(find.text('XP und Level'));
    expect(
      tester.getTopLeft(find.text('XP und Level')).dy,
      greaterThan(tester.getTopLeft(find.text('Gewicht')).dy),
    );
  });

  testWidgets('a card opens the screen of its module (C02)', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Gewicht'));
    await tester.pumpAndSettle();
    expect(find.text('Mein Gewicht'), findsOneWidget);
  });

  testWidgets(
    'the first day offers the entries the active modules really have',
    (tester) async {
      await _pump(tester, startedOn: LocalDate(2026, 10, 3));
      expect(find.text('Willkommen!'), findsOneWidget);
      expect(find.text('Gewicht eintragen'), findsOneWidget);
      await tester.tap(find.text('Ersten Eintrag hinzufügen'));
      await tester.pumpAndSettle();
      expect(find.text('Gewicht eintragen'), findsWidgets);
    },
  );

  testWidgets('with the body module off only the XP card remains (AT03)', (
    tester,
  ) async {
    final handle = await _pump(tester);
    await tester.runCommand(
      () => handle.container
          .read(moduleManagerProvider)
          .setEnabled(commandId: 'off', module: ModuleId.body, enabled: false),
    );
    await settle(tester);
    expect(find.text('Schritte'), findsNothing);
    expect(find.text('Gewicht'), findsNothing);
    expect(find.text('XP und Level'), findsOneWidget);
  });

  for (final size in responsiveSizes) {
    testWidgets(
      '(Q02) real cards fit ${size.width.toInt()} px at 200 % text without overflow',
      (tester) async {
        await _pump(tester, size: size, scale: 2.0);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Karten anpassen'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
