import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  final start = LocalDate(2026, 9, 1);
  final water2500 = GoalVersion(
    type: GoalType.water,
    target: 2500,
    effectiveFrom: start,
  );
  final water3000 = GoalVersion(
    type: GoalType.water,
    target: 3000,
    effectiveFrom: LocalDate(2026, 9, 10),
  );
  final waterOff = GoalVersion(
    type: GoalType.water,
    target: 3000,
    enabled: false,
    effectiveFrom: LocalDate(2026, 9, 20),
  );

  group('resolveGoalVersion', () {
    test('returns null without any version', () {
      expect(resolveGoalVersion(const [], GoalType.water, start), isNull);
    });

    test('returns null before the first version of the type', () {
      expect(
        resolveGoalVersion(
          [water2500, water3000],
          GoalType.water,
          LocalDate(2026, 8, 31),
        ),
        isNull,
      );
    });

    test('a version applies on its effective date and after it', () {
      final versions = [water2500, water3000, waterOff];
      expect(resolveGoalVersion(versions, GoalType.water, start), water2500);
      expect(
        resolveGoalVersion(versions, GoalType.water, LocalDate(2026, 9, 9)),
        water2500,
      );
      expect(
        resolveGoalVersion(versions, GoalType.water, LocalDate(2026, 9, 10)),
        water3000,
      );
      expect(
        resolveGoalVersion(versions, GoalType.water, LocalDate(2026, 9, 19)),
        water3000,
      );
      expect(
        resolveGoalVersion(versions, GoalType.water, LocalDate(2026, 9, 20)),
        waterOff,
      );
      expect(
        resolveGoalVersion(versions, GoalType.water, LocalDate(2027, 1, 1)),
        waterOff,
      );
    });

    test('is independent of the order of the versions', () {
      final shuffled = [waterOff, water2500, water3000];
      expect(
        resolveGoalVersion(shuffled, GoalType.water, LocalDate(2026, 9, 15)),
        water3000,
      );
      expect(
        resolveGoalVersion(
          shuffled.reversed,
          GoalType.water,
          LocalDate(2026, 9, 25),
        ),
        waterOff,
      );
    });

    test('ignores versions of other goal types', () {
      final steps = GoalVersion(
        type: GoalType.steps,
        target: 8000,
        effectiveFrom: start,
      );
      expect(resolveGoalVersion([steps], GoalType.water, start), isNull);
      expect(
        resolveGoalVersion([steps, water2500], GoalType.steps, start),
        steps,
      );
    });

    test('a tie on the effective date is resolved deterministically', () {
      final first = GoalVersion(
        type: GoalType.water,
        target: 2000,
        effectiveFrom: start,
      );
      final second = GoalVersion(
        type: GoalType.water,
        target: 4000,
        effectiveFrom: start,
      );
      expect(
        resolveGoalVersion([first, second], GoalType.water, start),
        second,
      );
      expect(resolveGoalVersion([second, first], GoalType.water, start), first);
    });
  });

  group('effectiveGoalOrDefault', () {
    test('falls back to the default, enabled, when no version exists', () {
      for (final type in GoalType.values) {
        final goal = effectiveGoalOrDefault(const [], type, start);
        expect(goal.type, type);
        expect(goal.target, type.defaultTarget);
        expect(goal.enabled, isTrue);
      }
    });

    test('falls back before the first version, uses versions afterwards', () {
      final versions = [water3000];
      final before = effectiveGoalOrDefault(
        versions,
        GoalType.water,
        LocalDate(2026, 9, 9),
      );
      expect(before.target, 2500);
      expect(before.enabled, isTrue);
      final after = effectiveGoalOrDefault(
        versions,
        GoalType.water,
        LocalDate(2026, 9, 10),
      );
      expect(after, water3000);
    });

    test('a stored disabled version wins over the default', () {
      final goal = effectiveGoalOrDefault(
        [waterOff],
        GoalType.water,
        LocalDate(2026, 9, 20),
      );
      expect(goal.enabled, isFalse);
    });
  });

  group('nextEffectiveDate', () {
    test('is tomorrow, also across month, year and DST boundaries', () {
      expect(nextEffectiveDate(LocalDate(2026, 10, 3)), LocalDate(2026, 10, 4));
      expect(nextEffectiveDate(LocalDate(2026, 1, 31)), LocalDate(2026, 2, 1));
      expect(nextEffectiveDate(LocalDate(2026, 12, 31)), LocalDate(2027, 1, 1));
      expect(nextEffectiveDate(LocalDate(2028, 2, 28)), LocalDate(2028, 2, 29));
      expect(nextEffectiveDate(LocalDate(2026, 3, 28)), LocalDate(2026, 3, 29));
      expect(nextEffectiveDate(LocalDate(2026, 3, 29)), LocalDate(2026, 3, 30));
      expect(
        nextEffectiveDate(LocalDate(2026, 10, 24)),
        LocalDate(2026, 10, 25),
      );
      expect(
        nextEffectiveDate(LocalDate(2026, 10, 25)),
        LocalDate(2026, 10, 26),
      );
    });
  });

  group('applyGoalChange', () {
    final today = LocalDate(2026, 10, 3);
    final tomorrow = nextEffectiveDate(today);

    GoalVersion change(GoalType type, int target, {LocalDate? from}) =>
        GoalVersion(
          type: type,
          target: target,
          effectiveFrom: from ?? tomorrow,
        );

    test('appends a change with a new slot', () {
      final result = applyGoalChange([water2500], change(GoalType.water, 3000));
      expect(result, [water2500, change(GoalType.water, 3000)]);
    });

    test('several changes for tomorrow replace the same version', () {
      var versions = <GoalVersion>[water2500];
      versions = applyGoalChange(versions, change(GoalType.water, 3000));
      versions = applyGoalChange(versions, change(GoalType.water, 3500));
      versions = applyGoalChange(versions, change(GoalType.water, 2750));
      expect(versions, [water2500, change(GoalType.water, 2750)]);
    });

    test('other types and other dates are left alone', () {
      final steps = GoalVersion(
        type: GoalType.steps,
        target: 8000,
        effectiveFrom: tomorrow,
      );
      final stepsLater = GoalVersion(
        type: GoalType.steps,
        target: 9000,
        effectiveFrom: tomorrow.addDays(1),
      );
      final result = applyGoalChange([
        water2500,
        steps,
        stepsLater,
      ], change(GoalType.water, 3000));
      expect(result, [
        water2500,
        steps,
        stepsLater,
        change(GoalType.water, 3000),
      ]);
    });

    test('replaces in place and does not modify the input', () {
      final existing = [water2500, change(GoalType.water, 3000), water3000];
      final snapshotOfInput = List<GoalVersion>.of(existing);
      final result = applyGoalChange(existing, change(GoalType.water, 3500));
      expect(result, [water2500, change(GoalType.water, 3500), water3000]);
      expect(existing, snapshotOfInput);
    });

    test('collapses accidental duplicates of the same slot', () {
      final result = applyGoalChange([
        change(GoalType.water, 1000),
        water2500,
        change(GoalType.water, 2000),
      ], change(GoalType.water, 3000));
      expect(result, [change(GoalType.water, 3000), water2500]);
    });

    test('a goal edit changes tomorrow, never today (AT24)', () {
      var versions = <GoalVersion>[water2500];
      expect(
        effectiveGoalOrDefault(versions, GoalType.water, today).target,
        2500,
      );
      versions = applyGoalChange(versions, change(GoalType.water, 3000));
      expect(
        effectiveGoalOrDefault(versions, GoalType.water, today).target,
        2500,
        reason: 'today keeps the old threshold',
      );
      expect(
        effectiveGoalOrDefault(versions, GoalType.water, tomorrow).target,
        3000,
        reason: 'tomorrow uses the new threshold',
      );
      expect(
        effectiveGoalOrDefault(
          versions,
          GoalType.water,
          today.addDays(-5),
        ).target,
        2500,
        reason: 'past days are untouched',
      );
    });

    test('switching a goal off applies from tomorrow as well', () {
      final off = GoalVersion(
        type: GoalType.weightEntry,
        enabled: false,
        effectiveFrom: tomorrow,
      );
      final versions = applyGoalChange(const [], off);
      expect(
        effectiveGoalOrDefault(versions, GoalType.weightEntry, today).enabled,
        isTrue,
      );
      expect(
        effectiveGoalOrDefault(
          versions,
          GoalType.weightEntry,
          tomorrow,
        ).enabled,
        isFalse,
      );
    });
  });

  group('GoalVersion value semantics', () {
    test('equality covers all fields', () {
      final base = GoalVersion(
        type: GoalType.steps,
        target: 8000,
        effectiveFrom: start,
      );
      expect(
        base,
        GoalVersion(type: GoalType.steps, target: 8000, effectiveFrom: start),
      );
      expect(
        base.hashCode,
        GoalVersion(
          type: GoalType.steps,
          target: 8000,
          effectiveFrom: start,
        ).hashCode,
      );
      expect(
        base,
        isNot(
          GoalVersion(type: GoalType.steps, target: 8001, effectiveFrom: start),
        ),
      );
      expect(
        base,
        isNot(
          GoalVersion(
            type: GoalType.steps,
            target: 8000,
            enabled: false,
            effectiveFrom: start,
          ),
        ),
      );
      expect(
        base,
        isNot(
          GoalVersion(type: GoalType.water, target: 8000, effectiveFrom: start),
        ),
      );
      expect(
        base,
        isNot(
          GoalVersion(
            type: GoalType.steps,
            target: 8000,
            effectiveFrom: start.addDays(1),
          ),
        ),
      );
    });
  });
}
