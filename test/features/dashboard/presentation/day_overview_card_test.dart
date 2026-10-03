import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_overview_card.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/no_goals_card.dart';

import '../../../support/pump_app.dart';

Future<void> _pump(
  WidgetTester tester, {
  required int fulfilled,
  required int applicable,
  double scale = 1.0,
  Size size = const Size(393, 852),
}) {
  return pumpApp(
    tester,
    SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: DayOverviewCard(
        fulfilled: fulfilled,
        applicable: applicable,
        motivation: 'Bleib in deinem Tempo.',
      ),
    ),
    size: size,
    textScale: scale,
    wrapInScaffold: true,
  );
}

void main() {
  group('texts follow the numbers (C04)', () {
    testWidgets('some goals reached', (tester) async {
      await _pump(tester, fulfilled: 3, applicable: 4);
      expect(find.text('3 von 4'), findsOneWidget);
      expect(find.text('Zielen'), findsOneWidget);
      expect(find.text('Bleib in deinem Tempo.'), findsOneWidget);
      expect(
        find.text('Du hast heute 3 von 4 Zielen erreicht.'),
        findsOneWidget,
      );
    });

    testWidgets('no goal reached yet', (tester) async {
      await _pump(tester, fulfilled: 0, applicable: 4);
      expect(find.text('0 von 4'), findsOneWidget);
      expect(
        find.text('Du hast heute noch kein Ziel erreicht.'),
        findsOneWidget,
      );
    });

    testWidgets('all goals reached', (tester) async {
      await _pump(tester, fulfilled: 4, applicable: 4);
      expect(
        find.text('Du hast heute alle Tagesziele erreicht.'),
        findsOneWidget,
      );
    });

    testWidgets('a single goal uses the singular', (tester) async {
      await _pump(tester, fulfilled: 1, applicable: 1);
      expect(find.text('1 von 1'), findsOneWidget);
      expect(find.text('Ziel'), findsOneWidget);
      expect(
        find.text('Du hast heute dein Tagesziel erreicht.'),
        findsOneWidget,
      );
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('1 von 1 Ziel erreicht'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the ring has its own spoken text', (tester) async {
      await _pump(tester, fulfilled: 3, applicable: 4);
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('3 von 4 Zielen erreicht'), findsOneWidget);
      semantics.dispose();
    });

    test('a ring without an applicable goal is not allowed', () {
      expect(
        () => DayOverviewCard(fulfilled: 0, applicable: 0, motivation: 'x'),
        throwsAssertionError,
      );
    });
  });

  group('layout', () {
    testWidgets('ring and text share a row on a normal phone', (tester) async {
      await _pump(tester, fulfilled: 3, applicable: 4);
      final ring = tester.getCenter(find.text('3 von 4'));
      final text = tester.getTopLeft(find.text('Bleib in deinem Tempo.'));
      expect(text.dx, greaterThan(ring.dx));
    });

    testWidgets('at large text the text goes below the ring (AT33)', (
      tester,
    ) async {
      await _pump(
        tester,
        fulfilled: 3,
        applicable: 4,
        scale: 2.0,
        size: const Size(320, 640),
      );
      final ring = tester.getCenter(find.text('3 von 4'));
      final text = tester.getTopLeft(find.text('Bleib in deinem Tempo.'));
      expect(text.dy, greaterThan(ring.dy));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the card without goals asks to set them (never a 0 of 0 ring)', (
    tester,
  ) async {
    var opened = 0;
    await pumpApp(
      tester,
      NoGoalsCard(onSetGoals: () => opened++),
      wrapInScaffold: true,
    );
    expect(find.text('Noch keine Tagesziele'), findsOneWidget);
    expect(find.textContaining('von 0'), findsNothing);
    await tester.tap(find.text('Ziele festlegen'));
    expect(opened, 1);
  });
}
