import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/dashboard_test_kit.dart';

/// Every widget of [titles] can be scrolled to and lies completely inside the
/// screen afterwards: nothing is clipped away or unreachable.
Future<void> _expectReachable(
  WidgetTester tester,
  Size size,
  Iterable<Finder> targets,
) async {
  for (final target in targets) {
    expect(target, findsWidgets, reason: '$target is missing');
    await tester.ensureVisible(target.first);
    await tester.pump();
    final rect = tester.getRect(target.first);
    expect(rect.left, greaterThanOrEqualTo(-0.5), reason: '$target left');
    expect(
      rect.right,
      lessThanOrEqualTo(size.width + 0.5),
      reason: '$target right',
    );
    expect(rect.top, greaterThanOrEqualTo(-0.5), reason: '$target top');
    expect(
      rect.bottom,
      lessThanOrEqualTo(size.height + 0.5),
      reason: '$target bottom',
    );
  }
}

/// Runs the Android tap target and label guidelines on the whole page: the
/// view is made tall enough that no scrolled-away or half visible part
/// distorts the measured sizes (the sizes do not depend on the view height).
Future<void> _expectAccessibleTargets(WidgetTester tester, Size size) async {
  tester.view.physicalSize = Size(size.width, 9000);
  await tester.pump();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}

void main() {
  for (final size in responsiveSizes) {
    for (final scale in const <double>[1.0, 2.0]) {
      testWidgets(
        '(C04, Q02, AT33) the dashboard fits ${size.width.toInt()} px at text scale $scale: '
        'no overflow, actions reachable, tap targets',
        (tester) async {
          final harness = await createHarness(
            tester,
            startedOn: LocalDate(2026, 9, 20),
          );
          await tester.runAsync(
            () => harness.database
                .into(harness.database.xpAwards)
                .insert(
                  XpAwardsCompanion.insert(
                    awardKey: 'seed',
                    localDate: LocalDate(2026, 9, 21),
                    sourceKind: 'water',
                    points: 95,
                    ruleVersion: 1,
                  ),
                ),
          );
          final fixture = await pumpHome(
            tester,
            harness,
            size: size,
            textScale: scale,
            realWeightCard: true,
          );
          final semantics = tester.ensureSemantics();
          // A saved weight: ring progress, streak 1, a level-up notice.
          await tester.runCommand(
            () => fixture.container
                .read(weightRepositoryProvider)
                .create(
                  commandId: 'w1',
                  draft: WeightDraft(
                    weightGrams: 71500,
                    occurredAtUtc: harness.clock.nowUtc(),
                  ),
                ),
          );
          await settle(tester);

          expect(tester.takeException(), isNull);
          expect(find.text('Level 2 erreicht'), findsOneWidget);
          await _expectReachable(tester, size, [
            find.bySemanticsLabel('Streak: 1 Tag in Folge, öffnen'),
            find.bySemanticsLabel('Hinweis schließen'),
            find.text('Dein Tag im Überblick'),
            find.text('+250 ml'),
            find.text('Aufgaben'),
            find.text('XP und Level'),
            find.text('Karten anpassen'),
          ]);

          await _expectAccessibleTargets(tester, size);
          semantics.dispose();
        },
      );
    }
  }

  for (final (width, scale) in const <(double, double)>[
    (320.0, 2.0),
    (360.0, 1.0),
    (430.0, 1.0),
  ]) {
    testWidgets(
      'the first day fits $width px at text scale $scale (AT01, AT33)',
      (tester) async {
        final harness = await createHarness(tester, displayName: 'Maximilian');
        final size = Size(width, 800);
        await pumpHome(tester, harness, size: size, textScale: scale);
        final semantics = tester.ensureSemantics();
        expect(tester.takeException(), isNull);
        await _expectReachable(tester, size, [
          find.text('Willkommen, Maximilian!'),
          find.text('Ersten Eintrag hinzufügen'),
          find.text('Gewicht eintragen'),
          find.text('Wasser eintragen'),
          find.text('Erstes Habit anlegen'),
        ]);
        await _expectAccessibleTargets(tester, size);
        semantics.dispose();
      },
    );

    testWidgets(
      'all modules off fits $width px at text scale $scale (AT04, AT33)',
      (tester) async {
        final harness = await createHarness(tester, enabledModules: <String>{});
        final size = Size(width, 800);
        await pumpHome(tester, harness, size: size, textScale: scale);
        final semantics = tester.ensureSemantics();
        expect(tester.takeException(), isNull);
        await _expectReachable(tester, size, [
          find.text('Alle Module sind ausgeschaltet'),
          find.text('Module auswählen'),
        ]);
        await _expectAccessibleTargets(tester, size);
        semantics.dispose();
      },
    );
  }

  testWidgets('(AT10, AT33) the water quick action stays reachable and one tap away at 200 % text '
      'on the narrowest screen', (tester) async {
    final harness = await createHarness(
      tester,
      startedOn: LocalDate(2026, 10, 2),
    );
    const size = Size(320, 640);
    final fixture = await pumpHome(tester, harness, size: size, textScale: 2.0);
    await tester.ensureVisible(find.text('+250 ml'));
    await tester.pump();
    final rect = tester.getRect(find.text('+250 ml'));
    expect(rect.bottom, lessThanOrEqualTo(size.height));
    await tester.tap(find.text('+250 ml'));
    await tester.pump();
    // Only the quick action fired, not the card behind it.
    expect(fixture.log.entries, ['quick:water']);
  });

  testWidgets('a wide screen keeps the content at most 720 px wide', (
    tester,
  ) async {
    final harness = await createHarness(
      tester,
      startedOn: LocalDate(2026, 10, 2),
    );
    await pumpHome(tester, harness, size: const Size(1000, 800));
    final heading = tester.getTopLeft(find.text('Dein Tag im Überblick'));
    expect(heading.dx, greaterThanOrEqualTo((1000 - 720) / 2));
    await tester.ensureVisible(find.text('Karten anpassen'));
    final button = tester.getRect(
      find.ancestor(
        of: find.text('Karten anpassen'),
        matching: find.byType(SecondaryButton),
      ),
    );
    expect(button.width, lessThanOrEqualTo(720));
    expect(button.right, lessThanOrEqualTo((1000 + 720) / 2));
  });
}
