import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/gamification/domain/steps_eligibility.dart';
import 'package:self_improvement/features/gamification/domain/xp_calculator.dart';
import 'package:self_improvement/features/gamification/domain/xp_facts.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  StepsEligibility decide({
    required int steps,
    int? target = 10000,
    bool gamification = true,
    bool? existingEligible,
    int? existingTarget,
  }) => decideStepsEligibility(
    newSteps: steps,
    applicableTarget: target,
    gamificationEnabled: gamification,
    existingReachedGoalEligible: existingEligible,
    existingXpGoalTargetSteps: existingTarget,
  );

  group('first reach of an applicable goal', () {
    test('freezes the threshold and the gamification status', () {
      final result = decide(steps: 10000);
      expect(result.reachedGoalEligible, isTrue);
      expect(result.xpGoalTargetSteps, 10000);
    });

    test('the threshold itself is enough, one step less is not', () {
      expect(decide(steps: 9999), StepsEligibility.undecided);
      expect(decide(steps: 10000).reachedGoalEligible, isNotNull);
      expect(decide(steps: 10001).xpGoalTargetSteps, 10000);
    });

    test('the frozen target is the applicable one, not the default', () {
      final result = decide(steps: 6200, target: 6000);
      expect(result.xpGoalTargetSteps, 6000);
      expect(result.reachedGoalEligible, isTrue);
    });

    test('reached while gamification is off: decided as not eligible', () {
      final result = decide(steps: 12000, gamification: false);
      expect(result.reachedGoalEligible, isFalse);
      expect(result.xpGoalTargetSteps, 10000);
    });
  });

  group('no claim without a reached goal', () {
    test('early input below the threshold decides nothing', () {
      for (final steps in [0, 1, 5000, 9999]) {
        final result = decide(steps: steps);
        expect(result.reachedGoalEligible, isNull, reason: '$steps');
        expect(result.xpGoalTargetSteps, isNull, reason: '$steps');
      }
    });

    test(
      'without an applicable goal nothing is decided, however many steps',
      () {
        final result = decide(steps: 50000, target: null);
        expect(result, StepsEligibility.undecided);
      },
    );

    test('a below-threshold save keeps the day open for a later reach', () {
      final early = decide(steps: 4000);
      final later = decide(
        steps: 10500,
        existingEligible: early.reachedGoalEligible,
        existingTarget: early.xpGoalTargetSteps,
      );
      expect(later.reachedGoalEligible, isTrue);
      expect(later.xpGoalTargetSteps, 10000);
    });
  });

  group('an existing decision is never revised', () {
    test('a granted decision survives a correction below the threshold', () {
      final result = decide(
        steps: 3000,
        existingEligible: true,
        existingTarget: 10000,
      );
      expect(result.reachedGoalEligible, isTrue);
      expect(result.xpGoalTargetSteps, 10000);
    });

    test('the frozen threshold survives a changed goal', () {
      final result = decide(
        steps: 9000,
        target: 12000,
        existingEligible: true,
        existingTarget: 8000,
      );
      expect(result.xpGoalTargetSteps, 8000);
      expect(result.reachedGoalEligible, isTrue);
    });

    test('survives the goal no longer being applicable', () {
      final result = decide(
        steps: 11000,
        target: null,
        existingEligible: true,
        existingTarget: 10000,
      );
      expect(result.reachedGoalEligible, isTrue);
      expect(result.xpGoalTargetSteps, 10000);
    });

    test('reached while gamification was off is never awarded later', () {
      final off = decide(steps: 12000, gamification: false);
      expect(off.reachedGoalEligible, isFalse);
      // Gamification is switched on again and the value is saved once more.
      final again = decide(
        steps: 12500,
        gamification: true,
        existingEligible: off.reachedGoalEligible,
        existingTarget: off.xpGoalTargetSteps,
      );
      expect(again.reachedGoalEligible, isFalse);
      expect(again.xpGoalTargetSteps, 10000);
    });

    test(
      'a decision made with gamification on is kept when it is switched off',
      () {
        final result = decide(
          steps: 12000,
          gamification: false,
          existingEligible: true,
          existingTarget: 10000,
        );
        expect(result.reachedGoalEligible, isTrue);
      },
    );
  });

  group('together with the awards of the day', () {
    final day = LocalDate(2026, 10, 3);
    final profileStart = LocalDate(2026, 9, 1);

    int stepsXp(int steps, StepsEligibility decision) {
      final awards = computeDayAwards(
        XpDayFacts(
          date: day,
          steps: StepsXpFact(
            steps: steps,
            reachedGoalEligible: decision.reachedGoalEligible,
            xpGoalTargetSteps: decision.xpGoalTargetSteps,
          ),
        ),
        profileStart: profileStart,
      );
      return awards.fold(0, (sum, award) => sum + award.points);
    }

    test('a day of saves: early input, reach, correction down and up', () {
      var decision = StepsEligibility.undecided;
      StepsEligibility save(int steps) => decision = decide(
        steps: steps,
        existingEligible: decision.reachedGoalEligible,
        existingTarget: decision.xpGoalTargetSteps,
      );

      expect(stepsXp(5000, save(5000)), 0, reason: 'early input: no claim');
      expect(stepsXp(10000, save(10000)), 10, reason: 'goal reached');
      expect(
        stepsXp(8000, save(8000)),
        0,
        reason: 'below the frozen threshold',
      );
      expect(stepsXp(10500, save(10500)), 10, reason: 'back above it');
      expect(decision.xpGoalTargetSteps, 10000);
    });

    test('a goal reached with gamification off never pays out', () {
      var decision = StepsEligibility.undecided;
      StepsEligibility save(int steps, {required bool gamification}) =>
          decision = decide(
            steps: steps,
            gamification: gamification,
            existingEligible: decision.reachedGoalEligible,
            existingTarget: decision.xpGoalTargetSteps,
          );

      expect(stepsXp(11000, save(11000, gamification: false)), 0);
      expect(stepsXp(12000, save(12000, gamification: true)), 0);
    });

    test('the frozen threshold wins over a goal that changed later', () {
      final frozen = decide(steps: 8000, target: 8000);
      // Tomorrow's goal is 12000, but this day was frozen at 8000.
      expect(stepsXp(9000, frozen), 10);
      expect(stepsXp(7999, frozen), 0);
    });
  });
}
