import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/dashboard_test_kit.dart';

WeightDraft _weight(DateTime at, {int grams = 71500}) =>
    WeightDraft(weightGrams: grams, occurredAtUtc: at);

/// 95 XP of an earlier day: the next award crosses the first level boundary.
Future<void> _seedXp(
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
}

void main() {
  final startedOn = LocalDate(2026, 9, 20);

  testWidgets(
    '(C04, G02) a committed activity that crosses a level boundary shows the notice',
    (tester) async {
      final harness = await createHarness(tester, startedOn: startedOn);
      await _seedXp(tester, harness, 95);
      final fixture = await pumpHome(tester, harness);
      expect(find.text('95 / 100 XP'), findsOneWidget);
      expect(find.textContaining(RegExp(r'Level \d+ erreicht')), findsNothing);

      await tester.runCommand(
        () => fixture.container
            .read(weightRepositoryProvider)
            .create(commandId: 'w1', draft: _weight(harness.clock.nowUtc())),
      );
      await settle(tester);

      expect(find.text('Level 2 erreicht'), findsOneWidget);
      expect(find.text('Du hast jetzt 105 XP gesammelt.'), findsOneWidget);
      expect(find.text('5 / 100 XP'), findsOneWidget);
    },
  );

  testWidgets('an activity inside a level shows no notice', (tester) async {
    final harness = await createHarness(tester, startedOn: startedOn);
    await _seedXp(tester, harness, 50);
    final fixture = await pumpHome(tester, harness);
    await tester.runCommand(
      () => fixture.container
          .read(weightRepositoryProvider)
          .create(commandId: 'w1', draft: _weight(harness.clock.nowUtc())),
    );
    await settle(tester);
    expect(find.text('60 / 100 XP'), findsOneWidget);
    expect(find.textContaining(RegExp(r'Level \d+ erreicht')), findsNothing);
  });

  testWidgets('a failed command shows no notice and changes nothing (AT27)', (
    tester,
  ) async {
    final harness = await createHarness(tester, startedOn: startedOn);
    await _seedXp(tester, harness, 95);
    final fixture = await pumpHome(tester, harness);
    await tester.runAsync(() async {
      await expectLater(
        fixture.container
            .read(weightRepositoryProvider)
            .create(
              commandId: 'bad',
              draft: _weight(harness.clock.nowUtc(), grams: 1000),
            ),
        throwsA(isA<ValidationFailure>()),
      );
    });
    await settle(tester);
    expect(find.text('95 / 100 XP'), findsOneWidget);
    expect(find.textContaining(RegExp(r'Level \d+ erreicht')), findsNothing);
  });

  testWidgets('the notice can be closed and does not come back by itself', (
    tester,
  ) async {
    final harness = await createHarness(tester, startedOn: startedOn);
    await _seedXp(tester, harness, 95);
    final fixture = await pumpHome(tester, harness);
    final semantics = tester.ensureSemantics();
    await tester.runCommand(
      () => fixture.container
          .read(weightRepositoryProvider)
          .create(commandId: 'w1', draft: _weight(harness.clock.nowUtc())),
    );
    await settle(tester);
    expect(find.text('Level 2 erreicht'), findsOneWidget);
    expect(find.bySemanticsLabel('Hinweis schließen'), findsOneWidget);

    await tester.tap(find.byIcon(AppIcon.close.data));
    await tester.pump();
    expect(find.text('Level 2 erreicht'), findsNothing);

    await tester.runCommand(
      () => fixture.container
          .read(weightRepositoryProvider)
          .create(
            commandId: 'w2',
            draft: _weight(DateTime.utc(2026, 10, 2, 6)),
          ),
    );
    await settle(tester);
    expect(find.text('Level 2 erreicht'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a level-up is never shown again after a restart (G02)', (
    tester,
  ) async {
    final harness = await createHarness(tester, startedOn: startedOn);
    await _seedXp(tester, harness, 95);
    final first = await pumpHome(tester, harness);
    await tester.runCommand(
      () => first.container
          .read(weightRepositoryProvider)
          .create(commandId: 'w1', draft: _weight(harness.clock.nowUtc())),
    );
    await settle(tester);
    expect(find.text('Level 2 erreicht'), findsOneWidget);

    await pumpHome(tester, harness);
    await settle(tester);
    expect(find.text('Level 2 erreicht'), findsNothing);
    expect(find.text('5 / 100 XP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
    'taking the XP back with a deletion hides the notice again (AT23)',
    (tester) async {
      final harness = await createHarness(tester, startedOn: startedOn);
      await _seedXp(tester, harness, 95);
      final fixture = await pumpHome(tester, harness);
      final weights = fixture.container.read(weightRepositoryProvider);
      final created = await tester.runCommand(
        () => weights.create(
          commandId: 'w1',
          draft: _weight(harness.clock.nowUtc()),
        ),
      );
      await settle(tester);
      expect(find.text('Level 2 erreicht'), findsOneWidget);

      await tester.runCommand(
        () => weights.delete(commandId: 'd1', id: created.entityId!),
      );
      await settle(tester);
      expect(find.text('95 / 100 XP'), findsOneWidget);
      expect(find.text('Level 2 erreicht'), findsNothing);
    },
  );

  testWidgets('the notice does not outlive the day', (tester) async {
    final harness = await createHarness(tester, startedOn: startedOn);
    await _seedXp(tester, harness, 95);
    final fixture = await pumpHome(tester, harness);
    await tester.runCommand(
      () => fixture.container
          .read(weightRepositoryProvider)
          .create(commandId: 'w1', draft: _weight(harness.clock.nowUtc())),
    );
    await settle(tester);
    expect(find.text('Level 2 erreicht'), findsOneWidget);

    harness.clock.advance(const Duration(days: 1));
    fixture.container.read(todayProvider.notifier).refresh();
    await settle(tester);
    expect(find.text('Level 2 erreicht'), findsNothing);
  });

  testWidgets('with the gamification module off no level-up is shown (AT26)', (
    tester,
  ) async {
    final harness = await createHarness(
      tester,
      startedOn: startedOn,
      enabledModules: {'body', 'nutrition', 'focus', 'tasks'},
    );
    await _seedXp(tester, harness, 150);
    final fixture = await pumpHome(tester, harness);
    harness.events.publish(
      const ActivityCommitted(
        commandType: 'weight.create',
        xpBefore: 95,
        xpAfter: 105,
      ),
    );
    await settle(tester);
    expect(find.textContaining(RegExp(r'Level \d+ erreicht')), findsNothing);
    expect(find.textContaining('XP'), findsNothing);
    expect(fixture.feedback.events, isEmpty);
  });
}
