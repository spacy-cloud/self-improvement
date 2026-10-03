import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/gamification/application/gamification_providers.dart';
import 'package:self_improvement/features/gamification/data/gamification_repository.dart';
import 'package:self_improvement/features/gamification/presentation/progress_screen.dart';
import 'package:self_improvement/features/gamification/presentation/widgets/xp_dashboard_card.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../../dashboard/support/dashboard_test_kit.dart';

Future<void> _pumpCard(
  WidgetTester tester,
  DataHarness harness, {
  List<Override> overrides = const <Override>[],
}) async {
  final container = harness.createContainer(overrides: overrides);
  await pumpRouterApp(
    tester,
    container: container,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(
          body: Padding(padding: EdgeInsets.all(16), child: XpDashboardCard()),
        ),
      ),
      GoRoute(
        path: '/progress',
        builder: (context, state) => const ProgressScreen(),
      ),
    ],
  );
  await settle(tester);
}

Future<void> _award(
  WidgetTester tester,
  DataHarness harness,
  int points,
) async {
  await tester.runAsync(
    () => harness.database
        .into(harness.database.xpAwards)
        .insert(
          XpAwardsCompanion.insert(
            awardKey: 'seed:$points',
            localDate: LocalDate(2026, 9, 21),
            sourceKind: 'water',
            points: points,
            ruleVersion: 1,
          ),
        ),
  );
  await settle(tester);
}

void main() {
  testWidgets('shows level, XP in the level, the missing XP and the total', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    await _pumpCard(tester, harness);
    expect(find.text('XP und Level'), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('0 / 100 XP'), findsOneWidget);

    await _award(tester, harness, 250);
    expect(find.text('Level 3'), findsOneWidget);
    expect(find.text('50 / 100 XP'), findsOneWidget);
    expect(
      find.text('Noch 50 XP bis Level 4 · Gesamt: 250 XP'),
      findsOneWidget,
    );
  });

  testWidgets(
    'one button with the numbers as label that opens the progress page',
    (tester) async {
      final harness = await createHarness(tester);
      await _pumpCard(tester, harness);
      await _award(tester, harness, 250);
      final semantics = tester.ensureSemantics();
      final label =
          'XP und Level: Level 3, 50 / 100 XP, Noch 50 XP bis Level 4, '
          'Gesamt: 250 XP. Öffnet den Fortschritt';
      expect(find.bySemanticsLabel(label), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.text('XP und Level'));
      await tester.pumpAndSettle();
      expect(find.text('Dein Fortschritt'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('shows a dash and no level while the numbers are not read', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    await _pumpCard(
      tester,
      harness,
      overrides: [
        gamificationSummaryProvider.overrideWith(
          (ref) => const Stream<GamificationSummary>.empty(),
        ),
      ],
    );
    expect(find.text('–'), findsOneWidget);
    expect(find.textContaining(RegExp(r'Level \d')), findsNothing);
    expect(find.textContaining('XP'), findsOneWidget);
  });

  testWidgets('a failed read shows the error state and retry loads', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    var reads = 0;
    await _pumpCard(
      tester,
      harness,
      overrides: [
        gamificationSummaryProvider.overrideWith((ref) {
          reads++;
          if (reads == 1) {
            return Stream<GamificationSummary>.error(StateError('read failed'));
          }
          return ref.watch(gamificationRepositoryProvider).watchSummary();
        }),
      ],
    );
    expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
    await tester.tap(find.text('Erneut versuchen'));
    await settle(tester);
    expect(find.text('Level 1'), findsOneWidget);
    expect(reads, 2);
  });
}
