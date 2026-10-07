import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/goals/domain/goal_keys.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';

void main() {
  group('GoalType catalogue', () {
    test('persisted keys are stable and unique', () {
      expect(
        {for (final type in GoalType.values) type: type.key},
        {
          GoalType.water: 'water',
          GoalType.steps: 'steps',
          GoalType.weightEntry: 'weight_entry',
          GoalType.focusMinutes: 'focus_minutes',
          GoalType.taskCompletion: 'task_completion',
          GoalType.workoutWeekly: 'workout_weekly',
          GoalType.workoutDaily: 'workout_daily',
        },
      );
      expect(
        GoalType.values.map((type) => type.key).toList(),
        SchemaKeys.goalTypes,
        reason: 'same keys, same order as the schema (BS-99)',
      );
      expect(
        GoalType.values.map((type) => type.key).toSet(),
        hasLength(GoalType.values.length),
      );
    });

    test('tryParse maps every key back and rejects everything else', () {
      for (final type in GoalType.values) {
        expect(GoalType.tryParse(type.key), type);
      }
      for (final bad in [
        '',
        'Water',
        ' water',
        'water ',
        'weightEntry',
        'workout',
        'habit:abc',
      ]) {
        expect(GoalType.tryParse(bad), isNull, reason: bad);
      }
    });

    test('every type belongs to its module', () {
      expect(GoalType.water.module, ModuleId.nutrition);
      expect(GoalType.steps.module, ModuleId.body);
      expect(GoalType.weightEntry.module, ModuleId.body);
      expect(GoalType.focusMinutes.module, ModuleId.focus);
      expect(GoalType.taskCompletion.module, ModuleId.tasks);
      expect(GoalType.workoutWeekly.module, ModuleId.focus);
      expect(GoalType.workoutDaily.module, ModuleId.focus);
    });

    test('only the weekly workout goal is not a daily goal', () {
      expect(GoalType.values.where((type) => !type.isDaily), [
        GoalType.workoutWeekly,
      ]);
      expect(GoalType.dailyTypes, [
        GoalType.water,
        GoalType.steps,
        GoalType.weightEntry,
        GoalType.focusMinutes,
        GoalType.taskCompletion,
        GoalType.workoutDaily,
      ]);
      expect(
        GoalType.dailyTypes.map((type) => type.module),
        isNot(contains(ModuleId.gamification)),
        reason: 'XP is not a daily goal',
      );
    });

    test('planning defaults', () {
      expect(GoalType.water.defaultTarget, 2500);
      expect(GoalType.steps.defaultTarget, 10000);
      expect(GoalType.weightEntry.defaultTarget, 1);
      expect(GoalType.focusMinutes.defaultTarget, 25);
      expect(GoalType.taskCompletion.defaultTarget, 1);
      expect(GoalType.workoutWeekly.defaultTarget, 3);
      expect(GoalType.workoutDaily.defaultTarget, 1);
    });

    test('(BS-99) only "Workout heute" is off without a goal version', () {
      expect(GoalType.values.where((type) => !type.defaultEnabled), [
        GoalType.workoutDaily,
      ]);
    });

    test('every default target is itself valid', () {
      for (final type in GoalType.values) {
        expect(
          type.validateTarget(type.defaultTarget),
          GoalTargetValidation.valid,
          reason: type.key,
        );
      }
    });

    test(
      'weight entry, task completion and "Workout heute" are the switches',
      () {
        expect(GoalType.values.where((type) => type.isSwitch), [
          GoalType.weightEntry,
          GoalType.taskCompletion,
          GoalType.workoutDaily,
        ]);
      },
    );

    test('resolveTarget uses the stored value, the default or the fixed 1', () {
      expect(GoalType.water.resolveTarget(3000), 3000);
      expect(GoalType.water.resolveTarget(null), 2500);
      expect(GoalType.steps.resolveTarget(null), 10000);
      expect(GoalType.focusMinutes.resolveTarget(40), 40);
      expect(GoalType.weightEntry.resolveTarget(null), 1);
      expect(GoalType.weightEntry.resolveTarget(7), 1);
      expect(GoalType.taskCompletion.resolveTarget(0), 1);
      expect(GoalType.workoutDaily.resolveTarget(null), 1);
      expect(GoalType.workoutDaily.resolveTarget(3), 1, reason: 'a switch');
    });
  });

  group('GoalType.validateTarget', () {
    void expectValidation(
      GoalType type,
      Map<int, GoalTargetValidation> expected,
    ) {
      expected.forEach((value, result) {
        expect(
          type.validateTarget(value),
          result,
          reason: '${type.key}: $value',
        );
      });
    }

    test('water: 250 to 10000 ml in steps of 50', () {
      expectValidation(GoalType.water, {
        -50: GoalTargetValidation.belowMinimum,
        0: GoalTargetValidation.belowMinimum,
        249: GoalTargetValidation.belowMinimum,
        250: GoalTargetValidation.valid,
        251: GoalTargetValidation.notOnStep,
        275: GoalTargetValidation.notOnStep,
        300: GoalTargetValidation.valid,
        2500: GoalTargetValidation.valid,
        2525: GoalTargetValidation.notOnStep,
        9950: GoalTargetValidation.valid,
        9999: GoalTargetValidation.notOnStep,
        10000: GoalTargetValidation.valid,
        10001: GoalTargetValidation.aboveMaximum,
        10050: GoalTargetValidation.aboveMaximum,
      });
    });

    test('steps: 100 to 100000', () {
      expectValidation(GoalType.steps, {
        0: GoalTargetValidation.belowMinimum,
        99: GoalTargetValidation.belowMinimum,
        100: GoalTargetValidation.valid,
        101: GoalTargetValidation.valid,
        7450: GoalTargetValidation.valid,
        99999: GoalTargetValidation.valid,
        100000: GoalTargetValidation.valid,
        100001: GoalTargetValidation.aboveMaximum,
      });
    });

    test('focus minutes: 5 to 180', () {
      expectValidation(GoalType.focusMinutes, {
        0: GoalTargetValidation.belowMinimum,
        4: GoalTargetValidation.belowMinimum,
        5: GoalTargetValidation.valid,
        6: GoalTargetValidation.valid,
        179: GoalTargetValidation.valid,
        180: GoalTargetValidation.valid,
        181: GoalTargetValidation.aboveMaximum,
      });
    });

    test('weekly workouts: 1 to 14', () {
      expectValidation(GoalType.workoutWeekly, {
        0: GoalTargetValidation.belowMinimum,
        1: GoalTargetValidation.valid,
        7: GoalTargetValidation.valid,
        14: GoalTargetValidation.valid,
        15: GoalTargetValidation.aboveMaximum,
      });
    });

    test('switch goals accept only the fixed target 1', () {
      for (final type in [
        GoalType.weightEntry,
        GoalType.taskCompletion,
        GoalType.workoutDaily,
      ]) {
        expectValidation(type, {
          -1: GoalTargetValidation.belowMinimum,
          0: GoalTargetValidation.belowMinimum,
          1: GoalTargetValidation.valid,
          2: GoalTargetValidation.aboveMaximum,
          10: GoalTargetValidation.aboveMaximum,
        });
      }
    });

    test('isValid is true only for valid', () {
      for (final result in GoalTargetValidation.values) {
        expect(result.isValid, result == GoalTargetValidation.valid);
      }
    });
  });

  group('habit goal keys', () {
    test('build and parse habit keys', () {
      const id = '0b5e0c1e-3c2c-4d57-9d0e-0d6f4d0a1b11';
      expect(habitGoalKey(id), 'habit:$id');
      expect(isHabitGoalKey('habit:$id'), isTrue);
      expect(habitIdFromKey('habit:$id'), id);
      expect(habitIdFromKey(habitGoalKey(id)), id);
    });

    test('type keys and malformed keys are not habit keys', () {
      for (final type in GoalType.values) {
        expect(isHabitGoalKey(type.key), isFalse, reason: type.key);
        expect(habitIdFromKey(type.key), isNull, reason: type.key);
      }
      for (final bad in ['', 'habit', 'habit:', 'Habit:abc', ' habit:abc']) {
        expect(isHabitGoalKey(bad), isFalse, reason: bad);
        expect(habitIdFromKey(bad), isNull, reason: bad);
      }
    });
  });
}
