import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/tasks/presentation/habits_tab_screen.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets(
    'AT34 a confirmation opened from a tab covers the whole screen, the '
    'navigation bar included',
    (tester) async {
      final app = await pumpFullApp(tester);
      await tester.tap(navTab('Habits'));
      await app.settle();

      final tabContext = tester.element(find.byType(HabitsTabScreen));
      unawaited(
        showConfirmationSheet(
          tabContext,
          title: 'Aufgabe löschen?',
          message: 'Diese Aufgabe wird gelöscht.',
          confirmLabel: 'Löschen',
        ),
      );
      await tester.pump();
      await app.settle();

      expect(find.text('Aufgabe löschen?'), findsOneWidget);
      final barrier = tester.getRect(find.byType(ModalBarrier).last);
      expect(
        barrier.bottom,
        tester.view.physicalSize.height / tester.view.devicePixelRatio,
        reason: 'the scrim reaches the bottom edge, below the navigation bar',
      );
      expect(barrier.top, 0);
    },
  );
}
