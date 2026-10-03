import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';

import '../../../support/pump_app.dart';
import '../support/screen_env.dart';

const scales = [1.0, 2.0];

/// A profile with every optional value, so the screens show their longest
/// content.
Future<ScreenEnv> fullEnv(WidgetTester tester) async {
  final env = await createScreenEnv(tester);
  await saveProfile(
    tester,
    env,
    name: 'Maximilian Alexander Mustermann-Schmidt',
    heightCm: 180,
    ageYears: 22,
    startWeightGrams: 74000,
    targetWeightGrams: 68000,
  );
  await addWeight(tester, env, 71500);
  return env;
}

void main() {
  for (final size in responsiveSizes) {
    for (final scale in scales) {
      final name = '${size.width.toInt()} px, text ${(scale * 100).toInt()} %';

      group(name, () {
        for (final entry in {
          'profile': ProfileRoutes.profile,
          'profile editor': ProfileRoutes.edit,
          'goals': ProfileRoutes.goals,
        }.entries) {
          testWidgets(
            '${entry.key} fits without overflow, tap targets 48 px and labelled (AT33)',
            (tester) async {
              final handle = tester.ensureSemantics();
              final env = await fullEnv(tester);
              await openScreen(
                tester,
                env,
                entry.value,
                size: size,
                textScale: scale,
              );
              await expectLater(
                tester,
                meetsGuideline(androidTapTargetGuideline),
              );
              await expectLater(
                tester,
                meetsGuideline(labeledTapTargetGuideline),
              );
              handle.dispose();
            },
          );
        }

        for (final entry in {
          'profile editor': (ProfileRoutes.edit, 'Profil speichern'),
          'goals': (ProfileRoutes.goals, 'Ziele speichern'),
        }.entries) {
          testWidgets(
            '${entry.key}: the save button stays above the keyboard and works (AT33)',
            (tester) async {
              final env = await fullEnv(tester);
              const keyboard = 300.0;
              await openScreen(
                tester,
                env,
                entry.value.$1,
                size: size,
                textScale: scale,
                viewInsets: const EdgeInsets.only(bottom: keyboard),
              );
              // Change something so that the button is active.
              if (entry.value.$1 == ProfileRoutes.edit) {
                await tester.enterText(find.byType(TextField).first, 'Mia');
              } else {
                await tester.enterText(find.byType(TextField).first, '3000');
              }
              await tester.pump();
              final button = find.widgetWithText(PrimaryButton, entry.value.$2);
              final rect = tester.getRect(button);
              expect(
                rect.bottom,
                lessThanOrEqualTo(size.height - keyboard + 0.5),
                reason: 'not hidden by the keyboard',
              );
              expect(tester.widget<PrimaryButton>(button).onPressed, isNotNull);
              await tester.tap(button);
              await settle(tester);
              expect(
                find.text('Seite /'),
                findsOneWidget,
                reason: 'saved and closed',
              );
            },
          );
        }
      });
    }
  }

  testWidgets('the last field can be reached with the keyboard open at 200 %', (
    tester,
  ) async {
    final env = await fullEnv(tester);
    await openScreen(
      tester,
      env,
      ProfileRoutes.edit,
      size: const Size(320, 640),
      textScale: 2.0,
      viewInsets: const EdgeInsets.only(bottom: 300),
    );
    final target = find.byType(TextField).last;
    await tester.ensureVisible(target);
    await tester.enterText(target, '67,5');
    await tester.pump();
    final rect = tester.getRect(target);
    expect(rect.bottom, lessThanOrEqualTo(640 - 300));
  });
}
