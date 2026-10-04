import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/body_module.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';

import '../../../support/pump_app.dart';

/// The `weight` dashboard card against a real in-memory database
/// (clock 2026-10-03 10:00 Europe/Berlin).
void main() {
  Future<ProviderContainer> start(WidgetTester tester) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final harness = await createTestHarness(tester);
    return harness.createContainer(
      overrides: [
        feedbackServiceProvider.overrideWithValue(
          RecordingFeedbackService(ids: harness.ids),
        ),
      ],
    );
  }

  Future<void> record(
    WidgetTester tester,
    ProviderContainer container,
    int grams,
    String atUtc,
  ) => tester.runCommand(
    () => container
        .read(weightRepositoryProvider)
        .create(
          commandId: 'w-$atUtc',
          draft: WeightDraft(
            weightGrams: grams,
            occurredAtUtc: DateTime.parse(atUtc).toUtc(),
          ),
        ),
  );

  Future<void> open(WidgetTester tester, ProviderContainer container) async {
    final card = const BodyModule().dashboardCards.firstWhere(
      (c) => c.cardId == 'weight',
    );
    await pumpRouterApp(
      tester,
      container: container,
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Consumer(
            builder: (context, ref, _) => Scaffold(
              body: SingleChildScrollView(child: card.builder(context, ref)),
            ),
          ),
        ),
        ...const BodyModule().routes,
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('without a measurement it shows no number and offers entering', (
    tester,
  ) async {
    final container = await start(tester);
    await open(tester, container);

    expect(find.text('Noch keine Messung'), findsOneWidget);
    expect(find.text('Gewicht eintragen'), findsOneWidget);
    expect(find.textContaining('kg'), findsNothing);
  });

  testWidgets('a recent measurement shows the value, the curve and the week', (
    tester,
  ) async {
    final container = await start(tester);
    await record(tester, container, 72000, '2026-09-26T06:00:00Z');
    await record(tester, container, 71500, '2026-10-03T06:00:00Z');
    await open(tester, container);

    expect(find.textContaining('71,5 kg'), findsOneWidget);
    expect(find.textContaining('in 7 Tagen'), findsOneWidget);
  });

  testWidgets(
    'a measurement older than a week shows its date, no curve (BS-61)',
    (tester) async {
      final container = await start(tester);
      await record(tester, container, 71500, '2026-09-20T06:00:00Z');
      await open(tester, container);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('71,5 kg'), findsOneWidget);
      expect(find.textContaining('Zuletzt So., 20. Sep.'), findsOneWidget);
      expect(find.textContaining('in 7 Tagen'), findsNothing);
    },
  );

  testWidgets(
    'tapping the card opens the overview, the action opens the form',
    (tester) async {
      final container = await start(tester);
      await open(tester, container);
      await tester.tap(find.text('Gewicht eintragen'));
      await tester.pumpAndSettle();

      expect(find.text('Eintrag speichern'), findsOneWidget);
    },
  );
}
