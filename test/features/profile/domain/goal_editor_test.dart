import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/profile/domain/goal_editor.dart';
import 'package:self_improvement/shared/local_date.dart';

bool valid(GoalType type, String text) =>
    parseGoalText(type, text) is GoalTextValid;

String? message(GoalType type, String text) {
  final result = parseGoalText(type, text);
  return result is GoalTextInvalid ? result.message : null;
}

void main() {
  group('typed values (both sides of every limit)', () {
    test('water: 250 to 10.000 ml in steps of 50', () {
      expect(valid(GoalType.water, '250'), isTrue);
      expect(valid(GoalType.water, '2500'), isTrue);
      expect(valid(GoalType.water, '10000'), isTrue);
      expect(valid(GoalType.water, '200'), isFalse);
      expect(valid(GoalType.water, '249'), isFalse);
      expect(valid(GoalType.water, '10050'), isFalse);
      expect(message(GoalType.water, '260'), contains('50-ml-Schritten'));
      expect(
        message(GoalType.water, '100'),
        contains('zwischen 250 und 10.000'),
      );
    });

    test('steps: 100 to 100.000', () {
      expect(valid(GoalType.steps, '100'), isTrue);
      expect(valid(GoalType.steps, '100000'), isTrue);
      expect(valid(GoalType.steps, '99'), isFalse);
      expect(valid(GoalType.steps, '100001'), isFalse);
      expect(
        message(GoalType.steps, '50'),
        contains('zwischen 100 und 100.000'),
      );
    });

    test('focus: 5 to 180 minutes', () {
      expect(valid(GoalType.focusMinutes, '5'), isTrue);
      expect(valid(GoalType.focusMinutes, '180'), isTrue);
      expect(valid(GoalType.focusMinutes, '4'), isFalse);
      expect(valid(GoalType.focusMinutes, '181'), isFalse);
      expect(
        message(GoalType.focusMinutes, '0'),
        contains('5 und 180 Minuten'),
      );
    });

    test('workouts per week: 1 to 14', () {
      expect(valid(GoalType.workoutWeekly, '1'), isTrue);
      expect(valid(GoalType.workoutWeekly, '14'), isTrue);
      expect(valid(GoalType.workoutWeekly, '0'), isFalse);
      expect(valid(GoalType.workoutWeekly, '15'), isFalse);
    });

    test('empty, decimal, negative and absurd texts are rejected', () {
      for (final bad in ['', ' ', '2,5', '2.5', '-5', 'abc', '9' * 40]) {
        expect(valid(GoalType.water, bad), isFalse, reason: '"$bad"');
      }
      expect(message(GoalType.water, ''), 'Bitte gib einen Wert ein.');
      expect(message(GoalType.water, 'abc'), 'Bitte gib eine ganze Zahl ein.');
    });

    test('leading zeros and blanks are fine', () {
      expect(valid(GoalType.steps, ' 0150 '), isTrue);
    });
  });

  group('plus and minus', () {
    int? step(GoalType type, String text, int direction, {int fallback = 0}) =>
        stepGoalTarget(
          type: type,
          text: text,
          fallback: fallback,
          direction: direction,
        );

    test('move by the step of the goal', () {
      expect(step(GoalType.water, '2500', 1), 2750);
      expect(step(GoalType.water, '2500', -1), 2250);
      expect(step(GoalType.steps, '10000', 1), 10500);
      expect(step(GoalType.focusMinutes, '25', 1), 30);
      expect(step(GoalType.workoutWeekly, '3', -1), 2);
    });

    test('are clamped to the range and stay on the grid', () {
      expect(step(GoalType.water, '10000', 1), 10000);
      expect(step(GoalType.water, '250', -1), 250);
      expect(step(GoalType.workoutWeekly, '14', 1), 14);
      expect(step(GoalType.workoutWeekly, '1', -1), 1);
      expect(step(GoalType.focusMinutes, '178', 1), 180);
      // 2510 is not a water value: stepping starts from the saved value.
      expect(step(GoalType.water, '2510', 1, fallback: 2500), 2750);
    });

    test('start from the saved value while the typed text is unusable', () {
      expect(step(GoalType.water, '', 1, fallback: 2500), 2750);
      expect(step(GoalType.water, 'abc', -1, fallback: 2500), 2250);
    });

    test('switch goals have no stepping', () {
      expect(step(GoalType.weightEntry, '', 1), isNull);
      expect(step(GoalType.taskCompletion, '', -1), isNull);
    });
  });

  group('texts', () {
    test('summary lines', () {
      expect(goalSummaryText(GoalType.water, target: 2500), '2,5 l pro Tag');
      expect(goalSummaryText(GoalType.water, target: 1250), '1,25 l pro Tag');
      expect(goalSummaryText(GoalType.steps, target: 10000), '10.000 pro Tag');
      expect(
        goalSummaryText(GoalType.focusMinutes, target: 25),
        '25 Min. pro Tag',
      );
      expect(
        goalSummaryText(GoalType.workoutWeekly, target: 3),
        '3× pro Woche',
      );
      expect(goalSummaryText(GoalType.weightEntry, target: 1), 'Täglich');
      expect(
        goalSummaryText(GoalType.steps, target: 10000, enabled: false),
        'Aus',
      );
    });

    test('every goal type has a spec with a unit that fits the layout', () {
      for (final type in GoalType.values) {
        final spec = goalEditorSpec(type);
        expect(spec.type, type);
        expect(spec.title, isNotEmpty);
        expect(spec.inputLabel, isNotEmpty);
        expect(spec.isSwitch, type.isSwitch);
        expect(spec.stepAmount == 0, type.isSwitch);
        expect(spec.unit.length, lessThanOrEqualTo(4));
      }
    });
  });

  group('today versus from tomorrow', () {
    final today = LocalDate(2026, 10, 3);
    final tomorrow = LocalDate(2026, 10, 4);
    final base = [
      for (final type in GoalType.values)
        GoalVersion(
          type: type,
          target: type.defaultTarget,
          effectiveFrom: LocalDate(2026, 9, 1),
        ),
    ];
    final allOn = <ModuleId, bool>{
      for (final module in ModuleId.values) module: true,
    };

    test('without a change both days show the same values', () {
      final model = buildGoalEditorModel(
        versions: base,
        today: today,
        modules: allOn,
      );
      expect(model.tomorrow, tomorrow);
      expect(model.rows.map((row) => row.type), goalDisplayOrder);
      for (final row in model.rows) {
        expect(row.hasPendingChange, isFalse);
        expect(row.today, row.tomorrow);
      }
      expect(model.rowOf(GoalType.water).today, (target: 2500, enabled: true));
    });

    test('a saved change shows tomorrow, today keeps the old value', () {
      final model = buildGoalEditorModel(
        versions: [
          ...base,
          GoalVersion(
            type: GoalType.water,
            target: 3000,
            effectiveFrom: tomorrow,
          ),
          GoalVersion(
            type: GoalType.steps,
            target: 10000,
            enabled: false,
            effectiveFrom: tomorrow,
          ),
        ],
        today: today,
        modules: allOn,
      );
      final water = model.rowOf(GoalType.water);
      expect(water.today.target, 2500);
      expect(water.tomorrow.target, 3000);
      expect(water.hasPendingChange, isTrue);
      final steps = model.rowOf(GoalType.steps);
      expect(steps.today.enabled, isTrue);
      expect(steps.tomorrow.enabled, isFalse);
      expect(model.rowOf(GoalType.focusMinutes).hasPendingChange, isFalse);
    });

    test('the next day the pending change applies to today', () {
      final versions = [
        ...base,
        GoalVersion(
          type: GoalType.water,
          target: 3000,
          effectiveFrom: tomorrow,
        ),
      ];
      final model = buildGoalEditorModel(
        versions: versions,
        today: tomorrow,
        modules: allOn,
      );
      expect(model.rowOf(GoalType.water).today.target, 3000);
      expect(model.rowOf(GoalType.water).hasPendingChange, isFalse);
    });

    test('a goal without any stored version falls back to its default', () {
      final model = buildGoalEditorModel(
        versions: const [],
        today: today,
        modules: allOn,
      );
      expect(model.rowOf(GoalType.focusMinutes).today.target, 25);
      expect(model.rowOf(GoalType.workoutWeekly).tomorrow.target, 3);
    });

    test('goals of switched-off modules are hidden but kept', () {
      final model = buildGoalEditorModel(
        versions: base,
        today: today,
        modules: {...allOn, ModuleId.nutrition: false, ModuleId.focus: false},
      );
      expect(model.visibleRows.map((row) => row.type), [
        GoalType.steps,
        GoalType.weightEntry,
        GoalType.taskCompletion,
      ]);
      expect(model.hiddenRows.map((row) => row.type), [
        GoalType.water,
        GoalType.focusMinutes,
        GoalType.workoutDaily,
        GoalType.workoutWeekly,
      ]);
      expect(model.rowOf(GoalType.water).tomorrow.target, 2500);
    });

    test('models with the same content are equal', () {
      GoalEditorModel build() =>
          buildGoalEditorModel(versions: base, today: today, modules: allOn);
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
    });
  });

  group('"Workout heute" in the editor (BS-99)', () {
    final today = LocalDate(2026, 10, 3);
    final allOn = <ModuleId, bool>{
      for (final module in ModuleId.values) module: true,
    };
    GoalEditorRow rowOf(
      List<GoalVersion> versions, {
      Map<ModuleId, bool>? modules,
    }) => buildGoalEditorModel(
      versions: versions,
      today: today,
      modules: modules ?? allOn,
    ).rowOf(GoalType.workoutDaily);

    test('(BS-99) sits between "Gewicht erfassen" and "Aufgabe erledigen"', () {
      final index = goalDisplayOrder.indexOf(GoalType.workoutDaily);
      expect(goalDisplayOrder[index - 1], GoalType.weightEntry);
      expect(goalDisplayOrder[index + 1], GoalType.taskCompletion);
      expect(goalDisplayOrder.toSet(), GoalType.values.toSet());
      expect(goalDisplayOrder, hasLength(GoalType.values.length));
    });

    test(
      '(BS-99) is a switch without a value, with the texts of the design',
      () {
        final spec = goalEditorSpec(GoalType.workoutDaily);
        expect(spec.title, 'Workout heute');
        expect(spec.caption, 'Training, Ruhetag oder übersprungen zählt');
        expect(spec.inputLabel, 'Workout heute');
        expect(spec.isSwitch, isTrue);
        expect(spec.stepAmount, 0);
        expect(spec.unit, isEmpty);
        expect(goalValueText(GoalType.workoutDaily, 1), isEmpty);
        expect(
          stepGoalTarget(
            type: GoalType.workoutDaily,
            text: '',
            fallback: 1,
            direction: 1,
          ),
          isNull,
          reason: 'no plus and minus',
        );
      },
    );

    test(
      '(BS-99) the summary says Täglich while it is on and Aus while it is off',
      () {
        expect(goalSummaryText(GoalType.workoutDaily, target: 1), 'Täglich');
        expect(
          goalSummaryText(GoalType.workoutDaily, target: 1, enabled: false),
          'Aus',
        );
      },
    );

    test('(BS-99) only the target 1 is valid', () {
      expect(valid(GoalType.workoutDaily, '1'), isTrue);
      expect(valid(GoalType.workoutDaily, '0'), isFalse);
      expect(valid(GoalType.workoutDaily, '2'), isFalse);
      expect(message(GoalType.workoutDaily, '2'), 'Ungültiger Zielwert.');
    });

    test('(BS-99) without a goal version it is off today and tomorrow, the other goals are on', () {
      final row = rowOf(const []);
      expect(row.today, (target: 1, enabled: false));
      expect(row.tomorrow, (target: 1, enabled: false));
      expect(row.hasPendingChange, isFalse);
      final model = buildGoalEditorModel(
        versions: const [],
        today: today,
        modules: allOn,
      );
      expect([
        for (final other in model.rows)
          if (other.type != GoalType.workoutDaily) other.today.enabled,
      ], everyElement(isTrue));
    });

    test(
      '(BS-99, AT24) a version from tomorrow shows today off and tomorrow on',
      () {
        final row = rowOf([
          GoalVersion(
            type: GoalType.workoutDaily,
            effectiveFrom: today.addDays(1),
          ),
        ]);
        expect(row.today.enabled, isFalse);
        expect(row.tomorrow.enabled, isTrue);
        expect(row.hasPendingChange, isTrue);
      },
    );

    test('(BS-99) with the focus module off the row is hidden and the goal stays stored', () {
      final row = rowOf(
        [GoalVersion(type: GoalType.workoutDaily, effectiveFrom: today)],
        modules: {...allOn, ModuleId.focus: false},
      );
      expect(row.visible, isFalse);
      expect(row.today.enabled, isTrue, reason: 'kept, only hidden');
    });
  });
}
