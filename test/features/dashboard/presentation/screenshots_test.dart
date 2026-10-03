import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/dashboard_test_kit.dart';

/// Where the pictures for the visual comparison with the Figma frames go (the
/// `build` folder is not part of the repository).
const String _dir = 'build/dashboard_shots';

/// Seven days with a gap and an older run: streak 4, longest 5, 10 active days.
final List<LocalDate> _days = <LocalDate>[
  ...LocalDate(2026, 9, 20).rangeTo(LocalDate(2026, 9, 24)),
  LocalDate(2026, 9, 27),
  ...LocalDate(2026, 9, 30).rangeTo(LocalDate(2026, 10, 3)),
];

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 600));
  await savePng(tester, '$_dir/$name.png');
  final file = File('$_dir/$name.png');
  expect(file.existsSync(), isTrue, reason: name);
  expect(file.lengthSync(), greaterThan(2000), reason: name);
}

void main() {
  // Visual comparison harness (Q03): renders the screens of this work package
  // at the size of the Figma frames (393 x 852, Light and Dark). The pictures
  // are compared with the nodes 2013:2, 4045:2, 4004:2 and 4042:2 by eye; the
  // deviations are listed in docs/screens/dashboard-gamification.md.
  testWidgets('first day (Figma 4045:2, Q03)', (
    tester,
  ) async {
    final harness = await createHarness(tester, displayName: 'Max');
    await pumpHome(tester, harness);
    await _shot(tester, 'home_first_day');
  });

  testWidgets('all modules off (Q03)', (tester) async {
    final harness = await createHarness(tester, enabledModules: <String>{});
    await pumpHome(tester, harness);
    await _shot(tester, 'home_all_modules_off');
  });

  for (final theme in [AppThemeVariant.light, AppThemeVariant.dark]) {
    testWidgets(
      'dashboard with data, streak, progress and card configuration in '
      '${theme.name} (Figma 2013:2, 4004:2, 4042:2, Q03)',
      (tester) async {
        final harness = await createHarness(
          tester,
          startedOn: LocalDate(2026, 9, 20),
          displayName: 'Max',
        );
        final fixture = await pumpHome(
          tester,
          harness,
          theme: theme,
          realWeightCard: true,
        );
        await seedActiveDays(tester, fixture, _days);
        await _shot(tester, '${theme.name}_home');

        fixture.router.go('/streak');
        await tester.pumpAndSettle();
        await _shot(tester, '${theme.name}_streak');

        fixture.router.go('/progress');
        await tester.pumpAndSettle();
        await _shot(tester, '${theme.name}_progress');

        fixture.router.go('/');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Karten anpassen'));
        await tester.pump();
        await tester.tap(find.text('Karten anpassen'));
        await tester.pumpAndSettle();
        await _shot(tester, '${theme.name}_cards');
      },
    );
  }

  testWidgets('200 % text on the narrowest screen (Q03, AT33)', (tester) async {
    final harness = await createHarness(
      tester,
      startedOn: LocalDate(2026, 9, 20),
    );
    final fixture = await pumpHome(
      tester,
      harness,
      size: const Size(320, 640),
      textScale: 2.0,
      realWeightCard: true,
    );
    await seedActiveDays(tester, fixture, _days);
    await _shot(tester, 'large_home');
    fixture.router.go('/streak');
    await tester.pumpAndSettle();
    await _shot(tester, 'large_streak');
  });
}
