import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';

import '../../../support/pump_app.dart';
import '../support/screen_env.dart';

void main() {
  for (final entry in {
    'profile': ProfileRoutes.profile,
    'profile_edit': ProfileRoutes.edit,
    'goals': ProfileRoutes.goals,
    'settings': SettingsRoutes.settings,
    'licenses': SettingsRoutes.licenses,
  }.entries) {
    testWidgets('render ${entry.key}', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await createScreenEnv(tester);
      await saveProfile(
        tester,
        env,
        name: 'Max Mustermann',
        heightCm: 180,
        ageYears: 22,
        startWeightGrams: 74000,
        targetWeightGrams: 68000,
      );
      await addWeight(tester, env, 71500);
      await openScreen(tester, env, entry.value);
      await savePng(tester, 'build/profile_shots/${entry.key}.png');
      handle.dispose();
    });
  }
}
