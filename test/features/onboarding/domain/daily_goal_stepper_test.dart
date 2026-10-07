import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/features/onboarding/domain/daily_goal_stepper.dart';

void main() {
  group('suggested goals', () {
    test('the six suggested goals are listed once, steppers first; "Workout heute" is not suggested (BS-99)', () {
      expect(
        onboardingGoalTypes.toSet(),
        GoalType.values.toSet()..remove(GoalType.workoutDaily),
      );
      expect(onboardingGoalTypes, hasLength(GoalType.values.length - 1));
      expect(onboardingGoalTypes, isNot(contains(GoalType.workoutDaily)));
      expect(onboardingStepperGoals, <GoalType>[
        GoalType.steps,
        GoalType.water,
        GoalType.focusMinutes,
        GoalType.workoutWeekly,
      ]);
      expect(onboardingSwitchGoals, <GoalType>[
        GoalType.taskCompletion,
        GoalType.weightEntry,
      ]);
      expect(onboardingSwitchGoals.every((type) => type.isSwitch), isTrue);
      expect(onboardingStepperGoals.any((type) => type.isSwitch), isFalse);
    });

    test('the visible starting values are the suggested defaults', () {
      expect(defaultGoalTargets(), <GoalType, int>{
        GoalType.steps: 10000,
        GoalType.water: 2500,
        GoalType.focusMinutes: 25,
        GoalType.workoutWeekly: 3,
      });
      // The on/off goals have a fixed target of 1.
      expect(GoalType.taskCompletion.defaultTarget, 1);
      expect(GoalType.weightEntry.defaultTarget, 1);
    });
  });

  group('steppedGoalTarget', () {
    test('moves by one step size from the default in both directions', () {
      expect(steppedGoalTarget(GoalType.steps, 10000, 1), 10500);
      expect(steppedGoalTarget(GoalType.steps, 10000, -1), 9500);
      expect(steppedGoalTarget(GoalType.water, 2500, 1), 2750);
      expect(steppedGoalTarget(GoalType.water, 2500, -1), 2250);
      expect(steppedGoalTarget(GoalType.focusMinutes, 25, 1), 30);
      expect(steppedGoalTarget(GoalType.focusMinutes, 25, -1), 20);
      expect(steppedGoalTarget(GoalType.workoutWeekly, 3, 1), 4);
      expect(steppedGoalTarget(GoalType.workoutWeekly, 3, -1), 2);
    });

    test('direction zero never changes the value', () {
      for (final type in onboardingStepperGoals) {
        expect(steppedGoalTarget(type, type.defaultTarget, 0), isNull);
      }
    });

    test('stops at both ends of every range (both sides of each limit)', () {
      // steps 100 to 100000
      expect(steppedGoalTarget(GoalType.steps, 100, -1), isNull);
      expect(steppedGoalTarget(GoalType.steps, 100, 1), 500);
      expect(steppedGoalTarget(GoalType.steps, 500, -1), 100);
      expect(steppedGoalTarget(GoalType.steps, 99500, 1), 100000);
      expect(steppedGoalTarget(GoalType.steps, 100000, 1), isNull);
      expect(steppedGoalTarget(GoalType.steps, 100000, -1), 99500);
      // water 250 to 10000 ml
      expect(steppedGoalTarget(GoalType.water, 250, -1), isNull);
      expect(steppedGoalTarget(GoalType.water, 250, 1), 500);
      expect(steppedGoalTarget(GoalType.water, 10000, 1), isNull);
      expect(steppedGoalTarget(GoalType.water, 10000, -1), 9750);
      // focus 5 to 180 minutes
      expect(steppedGoalTarget(GoalType.focusMinutes, 5, -1), isNull);
      expect(steppedGoalTarget(GoalType.focusMinutes, 5, 1), 10);
      expect(steppedGoalTarget(GoalType.focusMinutes, 180, 1), isNull);
      expect(steppedGoalTarget(GoalType.focusMinutes, 180, -1), 175);
      // workouts 1 to 14 per week
      expect(steppedGoalTarget(GoalType.workoutWeekly, 1, -1), isNull);
      expect(steppedGoalTarget(GoalType.workoutWeekly, 1, 1), 2);
      expect(steppedGoalTarget(GoalType.workoutWeekly, 14, 1), isNull);
      expect(steppedGoalTarget(GoalType.workoutWeekly, 14, -1), 13);
    });

    test('values off the step grid snap onto it and stay inside the range', () {
      expect(steppedGoalTarget(GoalType.steps, 120, 1), 500);
      expect(steppedGoalTarget(GoalType.steps, 120, -1), 100);
      expect(steppedGoalTarget(GoalType.steps, 650, 1), 1000);
      expect(steppedGoalTarget(GoalType.steps, 650, -1), 500);
      expect(steppedGoalTarget(GoalType.water, 2600, 1), 2750);
      expect(steppedGoalTarget(GoalType.water, 2600, -1), 2500);
      expect(steppedGoalTarget(GoalType.focusMinutes, 27, 1), 30);
      expect(steppedGoalTarget(GoalType.focusMinutes, 27, -1), 25);
    });

    test('walking the whole range only visits valid targets', () {
      for (final type in onboardingStepperGoals) {
        var value = type.minTarget;
        var count = 1;
        while (true) {
          final next = steppedGoalTarget(type, value, 1);
          if (next == null) {
            break;
          }
          expect(next, greaterThan(value), reason: '${type.key} moves up');
          expect(
            type.validateTarget(next).isValid,
            isTrue,
            reason: '${type.key} $next is a valid target',
          );
          value = next;
          count++;
        }
        expect(value, type.maxTarget, reason: '${type.key} reaches the max');
        expect(count, lessThan(250), reason: '${type.key} terminates');
        while (true) {
          final previous = steppedGoalTarget(type, value, -1);
          if (previous == null) {
            break;
          }
          expect(type.validateTarget(previous).isValid, isTrue);
          value = previous;
        }
        expect(value, type.minTarget, reason: '${type.key} returns to the min');
      }
    });

    test('every goal step size is positive', () {
      for (final type in onboardingStepperGoals) {
        expect(goalStepSize(type), greaterThan(0));
      }
    });
  });

  group('texts', () {
    test('values use German number formats', () {
      expect(goalValueText(GoalType.steps, 10000), '10.000');
      expect(goalValueText(GoalType.steps, 500), '500');
      expect(goalValueText(GoalType.water, 2500), '2,5');
      expect(goalValueText(GoalType.water, 2250), '2,25');
      expect(goalValueText(GoalType.focusMinutes, 25), '25');
      expect(goalValueText(GoalType.workoutWeekly, 3), '3');
    });

    test('units and spoken values name what the number means', () {
      expect(goalUnitText(GoalType.steps), isNull);
      expect(goalUnitText(GoalType.water), 'l');
      expect(goalUnitText(GoalType.focusMinutes), 'Min.');
      expect(goalUnitText(GoalType.workoutWeekly), '×');
      expect(goalSpokenValue(GoalType.steps, 10000), '10.000 Schritte pro Tag');
      expect(goalSpokenValue(GoalType.water, 2500), '2,5 Liter pro Tag');
      expect(
        goalSpokenValue(GoalType.focusMinutes, 25),
        '25 Minuten Fokus pro Tag',
      );
      expect(goalSpokenValue(GoalType.workoutWeekly, 1), '1 Workout pro Woche');
      expect(
        goalSpokenValue(GoalType.workoutWeekly, 3),
        '3 Workouts pro Woche',
      );
    });

    test('titles, periods and button labels exist for every goal', () {
      for (final type in onboardingGoalTypes) {
        expect(goalTitle(type), isNotEmpty);
        expect(goalPeriod(type), type.isDaily ? 'pro Tag' : 'pro Woche');
        expect(goalSwitchDescription(type), isNotEmpty);
      }
      for (final type in onboardingStepperGoals) {
        expect(goalIncreaseLabel(type), contains('erhöhen'));
        expect(goalDecreaseLabel(type), contains('verringern'));
      }
      // Every row is told apart for screen readers.
      expect(<String>{
        for (final t in onboardingStepperGoals) goalIncreaseLabel(t),
      }, hasLength(onboardingStepperGoals.length));
      expect(<String>{
        for (final t in onboardingStepperGoals) goalDecreaseLabel(t),
      }, hasLength(onboardingStepperGoals.length));
    });
  });
}
