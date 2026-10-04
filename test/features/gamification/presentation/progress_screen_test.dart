import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/gamification/application/gamification_providers.dart';
import 'package:self_improvement/features/gamification/data/gamification_repository.dart';
import 'package:self_improvement/features/gamification/presentation/widgets/badge_tile.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/db_fixtures.dart';
import '../../../support/pump_app.dart';
import '../../dashboard/support/dashboard_test_kit.dart';

final LocalDate _start = LocalDate(2026, 9, 20);
final LocalDate _today = LocalDate(2026, 10, 3);

Future<HomeFixture> _pump(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double scale = 1.0,
  List<Override> overrides = const <Override>[],
}) async {
  final harness = await createHarness(tester, startedOn: _start);
  return pumpHome(
    tester,
    harness,
    size: size,
    textScale: scale,
    initialLocation: '/progress',
    overrides: overrides,
  );
}

Future<void> _award(
  WidgetTester tester,
  DataHarness harness,
  String key,
  int points,
) async {
  await tester.runAsync(
    () => harness.database
        .into(harness.database.xpAwards)
        .insert(
          XpAwardsCompanion.insert(
            awardKey: key,
            localDate: LocalDate(2026, 9, 21),
            sourceKind: 'water',
            points: points,
            ruleVersion: 1,
          ),
        ),
  );
  await settle(tester);
}

Finder _badge(String title, String state) =>
    find.bySemanticsLabel(RegExp('^$title, .* $state\$'));

void main() {
  testWidgets(
    '(AT01) a fresh installation honestly shows level 1, 0 XP and three locked '
    'badges',
    (tester) async {
      await _pump(tester);
      final semantics = tester.ensureSemantics();
      expect(find.text('Dein Fortschritt'), findsOneWidget);
      expect(find.text('Level 1'), findsOneWidget);
      expect(find.text('0 / 100 XP'), findsOneWidget);
      expect(find.text('Noch 100 XP bis Level 2'), findsOneWidget);
      expect(find.text('Gesamt: 0 XP'), findsOneWidget);
      expect(find.text('0 von 3'), findsOneWidget);
      expect(find.text('Gesperrt'), findsNWidgets(3));
      expect(find.text('Erreicht'), findsNothing);
      for (final title in const [
        'Erster Schritt',
        'Eine Woche dran',
        'Fokus gesammelt',
      ]) {
        expect(find.text(title), findsOneWidget);
        expect(_badge(title, 'Gesperrt'), findsOneWidget, reason: title);
      }
      expect(
        find.bySemanticsLabel(
          'Level 1, 0 / 100 XP, Noch 100 XP bis Level 2, Gesamt: 0 XP',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('level and bar follow the awards at 99, 100 and 250 XP (G02)', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    await _award(tester, fixture.harness, 'a', 99);
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('99 / 100 XP'), findsOneWidget);
    expect(find.text('Noch 1 XP bis Level 2'), findsOneWidget);

    await _award(tester, fixture.harness, 'b', 1);
    expect(find.text('Level 2'), findsOneWidget);
    expect(find.text('0 / 100 XP'), findsOneWidget);

    await _award(tester, fixture.harness, 'c', 150);
    expect(find.text('Level 3'), findsOneWidget);
    expect(find.text('50 / 100 XP'), findsOneWidget);
    expect(find.text('Gesamt: 250 XP'), findsOneWidget);
    // The level tile shows the level as well.
    expect(find.text('LVL'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets(
    '(G02, AT23) badges unlock from the data and lock again when the data is deleted',
    (tester) async {
      final fixture = await _pump(tester);
      final semantics = tester.ensureSemantics();
      final harness = fixture.harness;

      // Seven days in a row: first step and one week.
      await seedActiveDays(
        tester,
        fixture,
        LocalDate(2026, 9, 27).rangeTo(_today).toList(),
      );
      expect(_badge('Erster Schritt', 'Erreicht'), findsOneWidget);
      expect(_badge('Eine Woche dran', 'Erreicht'), findsOneWidget);
      expect(_badge('Fokus gesammelt', 'Gesperrt'), findsOneWidget);
      expect(find.text('2 von 3'), findsOneWidget);
      expect(find.text('Erreicht'), findsNWidgets(2));

      // One hour of completed focus time.
      await tester.runAsync(
        () => harness.database
            .into(harness.database.focusSessions)
            .insert(
              focusRow(
                id: 'focus-1',
                status: 'completed',
                planned: 3600,
                accumulated: 3600,
                completedDate: Value(_today),
              ),
            ),
      );
      await settle(tester);
      expect(_badge('Fokus gesammelt', 'Erreicht'), findsOneWidget);
      expect(find.text('3 von 3'), findsOneWidget);

      // The week is wrong: one day gets deleted, the badge locks again.
      final weights = fixture.container.read(weightRepositoryProvider);
      final entries = await tester.runAsync(() => weights.watchActive().first);
      final middle = entries!.firstWhere(
        (entry) => entry.localDate == LocalDate(2026, 9, 30),
      );
      await tester.runCommand(
        () => weights.delete(commandId: 'fix', id: middle.id),
      );
      await settle(tester);
      expect(_badge('Eine Woche dran', 'Gesperrt'), findsOneWidget);
      expect(_badge('Erster Schritt', 'Erreicht'), findsOneWidget);
      expect(find.text('2 von 3'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('the streak entry shows the streak and opens its page (C02)', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    await seedActiveDays(tester, fixture, [
      LocalDate(2026, 10, 2),
      LocalDate(2026, 10, 3),
    ]);
    expect(find.text('Streak: 2 Tage in Folge'), findsOneWidget);
    await tester.tap(find.text('Streak: 2 Tage in Folge'));
    await tester.pumpAndSettle();
    expect(find.text('Deine Streak'), findsOneWidget);
    await tester.tap(find.byIcon(AppIcon.back.data));
    await tester.pumpAndSettle();
    expect(find.text('Dein Fortschritt'), findsOneWidget);
  });

  testWidgets('a failed read shows the error state and retry loads (AT27)', (
    tester,
  ) async {
    var reads = 0;
    await _pump(
      tester,
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
    expect(find.text('Level 1'), findsNothing);
    await tester.tap(find.text('Erneut versuchen'));
    await settle(tester);
    expect(find.text('Level 1'), findsOneWidget);
    expect(reads, 2);
  });

  testWidgets('says how XP work without inventing numbers', (tester) async {
    await _pump(tester);
    expect(find.text('So sammelst du XP'), findsOneWidget);
    expect(
      find.textContaining('Alle 100 XP steigst du ein Level auf.'),
      findsOneWidget,
    );
  });

  testWidgets('at large text the badges stack in one column (AT33)', (
    tester,
  ) async {
    await _pump(tester, scale: 2.0);
    final tiles = find.byType(BadgeTile);
    final first = tester.getTopLeft(tiles.at(0));
    final second = tester.getTopLeft(tiles.at(1));
    expect(second.dy, greaterThan(first.dy));
    expect(second.dx, first.dx);
  });

  testWidgets('three badges share a row on a normal phone', (tester) async {
    await _pump(tester);
    final tiles = find.byType(BadgeTile);
    final first = tester.getTopLeft(tiles.at(0));
    final third = tester.getTopLeft(tiles.at(2));
    expect(third.dy, first.dy);
    expect(third.dx, greaterThan(first.dx));
  });

  for (final size in responsiveSizes) {
    for (final scale in const <double>[1.0, 2.0]) {
      testWidgets(
        '(Q02, AT33) fits ${size.width.toInt()} px at text scale $scale with reachable '
        'content and tap targets',
        (tester) async {
          final fixture = await _pump(tester, size: size, scale: scale);
          await seedActiveDays(tester, fixture, [
            LocalDate(2026, 10, 2),
            LocalDate(2026, 10, 3),
          ]);
          final semantics = tester.ensureSemantics();
          expect(tester.takeException(), isNull);
          for (final target in [
            find.text('Badges'),
            find.text('Fokus gesammelt'),
            find.text('So sammelst du XP'),
          ]) {
            await tester.ensureVisible(target);
            await tester.pump();
            final rect = tester.getRect(target);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width + 0.5));
            expect(rect.bottom, lessThanOrEqualTo(size.height + 0.5));
          }
          tester.view.physicalSize = Size(size.width, 9000);
          await tester.pump();
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantics.dispose();
        },
      );
    }
  }
}
