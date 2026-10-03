import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/onboarding/domain/onboarding_options.dart';

void main() {
  test('the five motivation goals use the stored ids in design order', () {
    expect(
      OnboardingOptions.motivationGoals.map((option) => option.id).toList(),
      <String>[
        'lose_weight',
        'get_fitter',
        'move_more',
        'live_healthier',
        'build_habits',
      ],
    );
    expect(
      OnboardingOptions.motivationGoals.map((option) => option.id).toSet(),
      SchemaKeys.motivationGoals.toSet(),
    );
  });

  test('the sleep reference is gone from every text', () {
    final live = OnboardingOptions.motivationGoals.firstWhere(
      (option) => option.id == 'live_healthier',
    );
    expect(live.subtitle, 'Trinken und Ernährung');
    for (final option in OnboardingOptions.motivationGoals) {
      expect('${option.title} ${option.subtitle}', isNot(contains('Schlaf')));
    }
  });

  test('every bundled module is offered exactly once', () {
    expect(
      OnboardingOptions.modules.map((option) => option.module).toList(),
      ModuleId.values,
    );
    for (final option in OnboardingOptions.modules) {
      expect(option.title, isNotEmpty);
      expect(option.subtitle, isNotEmpty);
    }
  });
}
