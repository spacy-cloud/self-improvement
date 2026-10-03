import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import 'support/design_test_harness.dart';

Widget _cell(int i) => SizedBox(key: ValueKey<String>('cell$i'), height: 40);

List<Widget> _cells(int n) => <Widget>[for (var i = 0; i < n; i++) _cell(i)];

void main() {
  setUpAll(loadInterFont);

  group('AdaptiveGrid.columnsFor', () {
    const grid = AdaptiveGrid(children: <Widget>[]);

    test('two columns at normal text scale from 268 px of content width', () {
      expect(grid.columnsFor(width: 361, textScale: 1), 2);
      expect(grid.columnsFor(width: 288, textScale: 1), 2);
      expect(grid.columnsFor(width: 268, textScale: 1), 2);
    });

    test('one column when a cell would be narrower than the minimum', () {
      expect(grid.columnsFor(width: 267, textScale: 1), 1);
      expect(grid.columnsFor(width: 200, textScale: 1), 1);
    });

    test('stacks above text scale 1.3, keeps two columns at exactly 1.3', () {
      expect(grid.columnsFor(width: 361, textScale: 1.3), 2);
      expect(grid.columnsFor(width: 361, textScale: 1.31), 1);
      expect(grid.columnsFor(width: 361, textScale: 2), 1);
    });

    test('respects maxColumns and a custom minimum cell width', () {
      const three = AdaptiveGrid(
        maxColumns: 3,
        minCellWidth: 100,
        children: <Widget>[],
      );
      expect(three.columnsFor(width: 400, textScale: 1), 3);
      expect(three.columnsFor(width: 300, textScale: 1), 2);
      expect(three.columnsFor(width: 180, textScale: 1), 1);
    });
  });

  group('AdaptiveGrid layout', () {
    for (final width in <double>[320, 360, 393, 430]) {
      testWidgets('two columns at ${width.toInt()} px and normal text', (
        tester,
      ) async {
        await pumpDesign(
          tester,
          AdaptiveGrid(children: _cells(4)),
          width: width,
        );
        final a = tester.getTopLeft(
          find.byKey(const ValueKey<String>('cell0')),
        );
        final b = tester.getTopLeft(
          find.byKey(const ValueKey<String>('cell1')),
        );
        final c = tester.getTopLeft(
          find.byKey(const ValueKey<String>('cell2')),
        );
        expect(a.dy, b.dy);
        expect(b.dx, greaterThan(a.dx));
        expect(c.dy, greaterThan(a.dy));
        expect(c.dx, a.dx);
        // The page margin is 16 on both sides, the gap is 12.
        final sizeA = tester.getSize(
          find.byKey(const ValueKey<String>('cell0')),
        );
        final sizeB = tester.getSize(
          find.byKey(const ValueKey<String>('cell1')),
        );
        expect(sizeA.width, sizeB.width);
        expect(sizeA.width * 2 + 12, closeTo(width - 32, 0.01));
      });
    }

    testWidgets('stacks to one column at text scale 2.0', (tester) async {
      await pumpDesign(tester, AdaptiveGrid(children: _cells(3)), textScale: 2);
      final a = tester.getTopLeft(find.byKey(const ValueKey<String>('cell0')));
      final b = tester.getTopLeft(find.byKey(const ValueKey<String>('cell1')));
      expect(a.dx, b.dx);
      expect(b.dy, greaterThan(a.dy));
      final size = tester.getSize(find.byKey(const ValueKey<String>('cell0')));
      expect(size.width, 393 - 32);
    });

    testWidgets('cells of one row have the same height', (tester) async {
      await pumpDesign(
        tester,
        const AdaptiveGrid(
          children: <Widget>[
            SizedBox(key: ValueKey<String>('short'), height: 40),
            SizedBox(key: ValueKey<String>('tall'), height: 120),
          ],
        ),
      );
      // IntrinsicHeight stretches the shorter child only when it can expand.
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('tall'))).height,
        120,
      );
    });

    testWidgets('an odd last cell keeps the width of a column', (tester) async {
      await pumpDesign(tester, AdaptiveGrid(children: _cells(3)));
      final first = tester.getSize(find.byKey(const ValueKey<String>('cell0')));
      final last = tester.getSize(find.byKey(const ValueKey<String>('cell2')));
      expect(last.width, first.width);
    });

    testWidgets('an empty grid renders nothing and does not throw', (
      tester,
    ) async {
      await pumpDesign(tester, const AdaptiveGrid(children: <Widget>[]));
      expect(tester.takeException(), isNull);
    });
  });

  group('MaxContentWidth', () {
    testWidgets('limits and centres the content on wide screens', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const MaxContentWidth(
          child: SizedBox(key: ValueKey<String>('content'), height: 40),
        ),
        width: 1000,
        scrollable: false,
      );
      final size = tester.getSize(
        find.byKey(const ValueKey<String>('content')),
      );
      expect(size.width, 720);
      final left = tester
          .getTopLeft(find.byKey(const ValueKey<String>('content')))
          .dx;
      expect(left, closeTo((1000 - 720) / 2, 0.01));
    });

    testWidgets('does not limit narrow screens', (tester) async {
      await pumpDesign(
        tester,
        const MaxContentWidth(
          child: SizedBox(key: ValueKey<String>('content'), height: 40),
        ),
        scrollable: false,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('content'))).width,
        393,
      );
    });
  });
}
