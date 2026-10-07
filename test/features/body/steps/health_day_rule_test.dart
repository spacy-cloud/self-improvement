import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/features/body/steps/domain/step_source.dart';

/// The conflict rule of the comparison with the health interface (D-032):
/// a value typed in by hand wins, the interface fills only days without a
/// value and updates only its own values, "no data" changes nothing.
void main() {
  group('decideHealthDay: every combination (BS-97)', () {
    // existing source, existing steps, health total, expected action.
    final table = <(StepSource?, int?, int?, HealthDayAction, String)>[
      // A day without a value.
      (null, null, null, HealthDayAction.noData, 'no value, no data'),
      (null, null, 0, HealthDayAction.create, 'no value, a reported 0'),
      (null, null, 7450, HealthDayAction.create, 'no value, a total'),
      // A value typed in by hand: it always wins.
      (
        StepSource.manual,
        5000,
        null,
        HealthDayAction.keepManual,
        'manual, no data',
      ),
      (
        StepSource.manual,
        5000,
        5000,
        HealthDayAction.keepManual,
        'manual, same total',
      ),
      (
        StepSource.manual,
        5000,
        9000,
        HealthDayAction.keepManual,
        'manual, higher total',
      ),
      (
        StepSource.manual,
        5000,
        100,
        HealthDayAction.keepManual,
        'manual, lower total',
      ),
      (
        StepSource.manual,
        5000,
        0,
        HealthDayAction.keepManual,
        'manual, reported 0',
      ),
      (
        StepSource.manual,
        0,
        9000,
        HealthDayAction.keepManual,
        'manual 0 is a value too',
      ),
      // A value the interface wrote itself.
      (
        StepSource.health,
        5000,
        null,
        HealthDayAction.noData,
        'health, no data keeps the value',
      ),
      (
        StepSource.health,
        5000,
        5000,
        HealthDayAction.unchanged,
        'health, same total',
      ),
      (
        StepSource.health,
        5000,
        9000,
        HealthDayAction.update,
        'health, higher total',
      ),
      (
        StepSource.health,
        5000,
        100,
        HealthDayAction.update,
        'health, lower total',
      ),
      (
        StepSource.health,
        5000,
        0,
        HealthDayAction.update,
        'health, reported 0',
      ),
      (
        StepSource.health,
        0,
        0,
        HealthDayAction.unchanged,
        'health 0, same total',
      ),
    ];
    for (final (source, steps, health, expected, name) in table) {
      test('$name: $expected', () {
        expect(
          decideHealthDay(
            existingSource: source,
            existingSteps: steps,
            healthSteps: health,
          ),
          expected,
        );
      });
    }
  });

  test('a value typed in is never overwritten, whatever Health reports '
      '(BS-97)', () {
    for (final health in <int?>[null, 0, 1, 5000, 100000]) {
      for (final steps in <int>[0, 1, 5000, 100000]) {
        expect(
          decideHealthDay(
            existingSource: StepSource.manual,
            existingSteps: steps,
            healthSteps: health,
          ),
          HealthDayAction.keepManual,
          reason: 'steps $steps, health $health',
        );
      }
    }
  });

  test('only a create or an update changes a day (BS-97)', () {
    for (final action in HealthDayAction.values) {
      final changes =
          action == HealthDayAction.create || action == HealthDayAction.update;
      final result = HealthApplyResult.none.plus(action);
      expect(result.changed, changes ? 1 : 0, reason: action.name);
      expect(result.total, 1, reason: action.name);
    }
  });

  test('the sources are the two keys of the schema (BS-97)', () {
    expect(
      StepSource.values.map((source) => source.key).toList(),
      SchemaKeys.stepSources,
    );
    expect(StepSource.tryParse('manual'), StepSource.manual);
    expect(StepSource.tryParse('health'), StepSource.health);
    expect(StepSource.tryParse('watch'), isNull);
    expect(StepSource.tryParse(null), isNull);
  });

  test('HealthApplyResult adds up and compares by value (BS-97)', () {
    final result = HealthApplyResult.none
        .plus(HealthDayAction.create)
        .plus(HealthDayAction.create)
        .plus(HealthDayAction.update)
        .plus(HealthDayAction.unchanged)
        .plus(HealthDayAction.keepManual)
        .plus(HealthDayAction.noData);
    expect(result.created, 2);
    expect(result.updated, 1);
    expect(result.unchanged, 1);
    expect(result.keptManual, 1);
    expect(result.noData, 1);
    expect(result.changed, 3);
    expect(result.total, 6);
    expect(
      result,
      const HealthApplyResult(
        created: 2,
        updated: 1,
        unchanged: 1,
        keptManual: 1,
        noData: 1,
      ),
    );
    expect(result.hashCode, isNot(HealthApplyResult.none.hashCode));
  });
}
