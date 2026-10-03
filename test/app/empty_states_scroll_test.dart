import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// The empty states of the history screens sit on a screen that does not
/// scroll as a whole (the list does). On a small screen with large text the
/// state must scroll itself, otherwise it overflows and its action is cut off
/// (AT33).
void main() {
  for (final (route, action) in <(String, String)>[
    ('/weight/all', 'Gewicht eintragen'),
    ('/focus/history', 'Fokus starten'),
    ('/workouts/all', 'Training eintragen'),
  ]) {
    for (final (size, scale) in <(Size, double)>[
      (const Size(320, 568), 2.0),
      (const Size(320, 700), 2.0),
    ]) {
      testWidgets(
        'AT33 the empty state of $route scrolls on ${size.width.toInt()}x'
        '${size.height.toInt()} at ${(scale * 100).toInt()} % text',
        (tester) async {
          final app = await pumpFullApp(tester, size: size, textScale: scale);
          app.router.go(route);
          await app.settle();
          await app.settle();

          expect(tester.takeException(), isNull, reason: 'no overflow');
          await tester.scrollUntilVisible(
            find.text(action),
            80,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text(action).hitTestable(), findsOneWidget);
        },
      );
    }
  }
}
