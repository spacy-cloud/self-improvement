import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/dashboard_test_kit.dart';

void main() {
  for (final theme in AppThemeVariant.values) {
    testWidgets('(C06, AT35) dashboard, streak and progress render in '
        '${theme.name} without errors and keep readable text', (tester) async {
      final harness = await createHarness(
        tester,
        startedOn: LocalDate(2026, 9, 20),
      );
      final fixture = await pumpHome(
        tester,
        harness,
        theme: theme,
        realWeightCard: true,
      );
      await seedActiveDays(tester, fixture, [
        LocalDate(2026, 10, 2),
        LocalDate(2026, 10, 3),
      ]);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      for (final route in const ['/streak', '/progress']) {
        fixture.router.go(route);
        await tester.pumpAndSettle();
        await settle(tester);
        expect(tester.takeException(), isNull, reason: route);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
    });
  }

  testWidgets(
    'with reduced motion the ring and the bars show their value at once',
    (tester) async {
      final harness = await createHarness(
        tester,
        startedOn: LocalDate(2026, 9, 20),
      );
      final fixture = await pumpHome(tester, harness, reducedMotion: true);
      await seedActiveDays(tester, fixture, [LocalDate(2026, 10, 3)]);
      // No animation is running: everything is already at its final state.
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.text('1 von 5'), findsOneWidget);
    },
  );
}
