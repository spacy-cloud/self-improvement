import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_swipe.dart';

// BS-93: the swipe that pages through the days, alone: which finger movements
// count, which do not, the mirrored layout, and that it leaves taps and the
// vertical scroll to the page.

Future<void> _pump(
  WidgetTester tester, {
  required void Function(String) onPage,
  bool enabled = true,
  TextDirection direction = TextDirection.ltr,
  Widget? child,
}) => tester.pumpWidget(
  Directionality(
    textDirection: direction,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: DaySwipe(
        enabled: enabled,
        onPrevious: () => onPage('previous'),
        onNext: () => onPage('next'),
        child:
            child ??
            const SizedBox(
              width: 400,
              height: 800,
              child: ColoredBox(color: Colors.white),
            ),
      ),
    ),
  ),
);

const Offset _at = Offset(200, 400);

void main() {
  group('which movements page (BS-93, Q02)', () {
    testWidgets('(BS-93) a swipe to the right goes to the previous day, one '
        'to the left to the next', (tester) async {
      final pages = <String>[];
      await _pump(tester, onPage: pages.add);
      await tester.dragFrom(_at, const Offset(120, 0));
      await tester.dragFrom(_at, const Offset(-120, 0));
      expect(pages, <String>['previous', 'next']);
    });

    testWidgets('(BS-93) a slow drag needs the distance of ${72.0} px', (
      tester,
    ) async {
      final pages = <String>[];
      await _pump(tester, onPage: pages.add);
      await tester.dragFrom(_at, Offset(daySwipeDistance - 4, 0));
      expect(pages, isEmpty);
      await tester.dragFrom(_at, Offset(daySwipeDistance + 4, 0));
      expect(pages, <String>['previous']);
    });

    testWidgets('(BS-93) a fast flick pages over a shorter distance, but not '
        'below the minimum', (tester) async {
      final pages = <String>[];
      await _pump(tester, onPage: pages.add);
      await tester.flingFrom(_at, const Offset(60, 0), 1500);
      expect(pages, <String>['previous']);
      // A flinch of a few pixels is not a page, however fast.
      await tester.flingFrom(_at, const Offset(-10, 0), 3000);
      expect(pages, <String>['previous']);
    });

    testWidgets('(BS-93) a drag that goes right and comes back counts where '
        'it ends', (tester) async {
      final pages = <String>[];
      await _pump(tester, onPage: pages.add);
      final gesture = await tester.startGesture(_at);
      await gesture.moveBy(const Offset(100, 0));
      await gesture.moveBy(const Offset(-90, 0));
      await gesture.up();
      expect(pages, isEmpty, reason: 'only 10 px are left');
    });

    testWidgets('(BS-93) a touch that is taken away before it became a '
        'drag counts for nothing', (tester) async {
      final pages = <String>[];
      await _pump(tester, onPage: pages.add);
      final gesture = await tester.startGesture(_at);
      await gesture.moveBy(const Offset(10, 0));
      await gesture.cancel();
      expect(pages, isEmpty);
      await tester.dragFrom(_at, const Offset(30, 0));
      expect(pages, isEmpty, reason: 'the 10 px of that touch are forgotten');
    });

    testWidgets('(BS-93) the swipe works over the whole area, also where '
        'nothing is drawn', (tester) async {
      final pages = <String>[];
      await _pump(tester, onPage: pages.add);
      await tester.dragFrom(const Offset(20, 580), const Offset(150, 0));
      expect(pages, <String>['previous']);
    });
  });

  group('the layout direction (BS-93)', () {
    testWidgets('(BS-93) in a right-to-left layout the directions are '
        'mirrored', (tester) async {
      final pages = <String>[];
      await _pump(tester, onPage: pages.add, direction: TextDirection.rtl);
      await tester.dragFrom(_at, const Offset(120, 0));
      await tester.dragFrom(_at, const Offset(-120, 0));
      expect(pages, <String>['next', 'previous']);
    });
  });

  group('leaving the page alone (BS-93, Q02)', () {
    testWidgets('(BS-93) disabled: no page, whatever the finger does', (
      tester,
    ) async {
      final pages = <String>[];
      await _pump(tester, onPage: pages.add, enabled: false);
      await tester.dragFrom(_at, const Offset(200, 0));
      await tester.flingFrom(_at, const Offset(-200, 0), 3000);
      expect(pages, isEmpty);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('(BS-93) a tap is a tap: a button below still gets it', (
      tester,
    ) async {
      final pages = <String>[];
      var taps = 0;
      await _pump(
        tester,
        onPage: pages.add,
        child: Center(
          child: GestureDetector(
            key: const Key('button'),
            onTap: () => taps++,
            child: const SizedBox(
              width: 100,
              height: 100,
              child: ColoredBox(color: Colors.red),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('button')));
      expect(taps, 1);
      expect(pages, isEmpty);
    });

    testWidgets('(BS-93) a vertical drag scrolls the list below and pages '
        'nothing', (tester) async {
      final pages = <String>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        onPage: pages.add,
        child: ListView(
          controller: controller,
          children: <Widget>[
            for (var i = 0; i < 40; i++)
              SizedBox(height: 80, child: Text('Zeile $i')),
          ],
        ),
      );
      await tester.dragFrom(_at, const Offset(0, -300));
      await tester.pump();
      expect(controller.offset, greaterThan(100));
      expect(pages, isEmpty);
      // A vertical drag with a small sideways drift still scrolls and pages
      // nothing: the vertical axis wins the arena first.
      await tester.dragFrom(_at, const Offset(20, -300));
      await tester.pump();
      expect(pages, isEmpty);
    });

    testWidgets('(BS-93) a horizontal drag over a list pages, and the list '
        'does not scroll sideways', (tester) async {
      final pages = <String>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        onPage: pages.add,
        child: ListView(
          controller: controller,
          children: <Widget>[
            for (var i = 0; i < 40; i++)
              SizedBox(height: 80, child: Text('Zeile $i')),
          ],
        ),
      );
      await tester.dragFrom(_at, const Offset(150, 0));
      expect(pages, <String>['previous']);
      expect(controller.offset, 0);
    });
  });
}
