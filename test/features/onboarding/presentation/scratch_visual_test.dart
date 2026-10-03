import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/pump_app.dart';
import '../support/onboarding_test_env.dart';

void main() {
  for (final (w, h, scale) in <(double, double, double)>[
    (393, 852, 1.0),
    (320, 640, 2.0),
  ]) {
    testWidgets('scratch visual $w x $h @ $scale', (tester) async {
      await pumpOnboarding(tester, size: Size(w, h), textScale: scale);
      final tag = '${w.toInt()}_${scale.toInt()}';
      await savePng(tester, 'build/onboarding/01_welcome_$tag.png');
      await tester.tap(find.text('Los geht’s'));
      await tester.pumpAndSettle();
      await savePng(tester, 'build/onboarding/02_goals_$tag.png');
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      await savePng(tester, 'build/onboarding/03_modules_$tag.png');
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      await savePng(tester, 'build/onboarding/04_body_$tag.png');
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      await savePng(tester, 'build/onboarding/05_daily_$tag.png');
    });
  }
}
