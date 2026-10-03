import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/gamification/domain/level.dart';

void main() {
  group('levelFor', () {
    test('reference values: 0, 99, 100 and 250 XP', () {
      expect(
        levelFor(0),
        const LevelProgress(level: 1, xpInLevel: 0, xpForNextLevel: 100),
      );
      expect(
        levelFor(99),
        const LevelProgress(level: 1, xpInLevel: 99, xpForNextLevel: 100),
      );
      expect(
        levelFor(100),
        const LevelProgress(level: 2, xpInLevel: 0, xpForNextLevel: 100),
      );
      expect(
        levelFor(250),
        const LevelProgress(level: 3, xpInLevel: 50, xpForNextLevel: 100),
      );
    });

    test('every level boundary', () {
      for (var level = 1; level <= 30; level++) {
        final first = (level - 1) * 100;
        expect(levelFor(first).level, level, reason: 'first XP of $level');
        expect(levelFor(first).xpInLevel, 0);
        expect(levelFor(first + 99).level, level, reason: 'last XP of $level');
        expect(levelFor(first + 99).xpInLevel, 99);
        expect(levelFor(first + 100).level, level + 1);
      }
    });

    test('level plus XP in the level always add up to the total', () {
      for (final xp in [
        0,
        1,
        17,
        99,
        100,
        101,
        199,
        200,
        250,
        999,
        1000,
        12345,
      ]) {
        final progress = levelFor(xp);
        expect((progress.level - 1) * 100 + progress.xpInLevel, xp);
        expect(progress.xpInLevel, inInclusiveRange(0, 99));
        expect(progress.xpForNextLevel, 100);
      }
    });

    test('large totals', () {
      expect(levelFor(9999), const LevelProgress(level: 100, xpInLevel: 99));
      expect(levelFor(10000), const LevelProgress(level: 101, xpInLevel: 0));
      expect(
        levelFor(1000000),
        const LevelProgress(level: 10001, xpInLevel: 0),
      );
      expect(
        levelFor(2147483647),
        const LevelProgress(level: 21474837, xpInLevel: 47),
      );
    });

    test('a negative total (which cannot occur) is treated as 0', () {
      expect(levelFor(-5), levelFor(0));
      expect(levelFor(-100).level, 1);
    });

    test('fraction is the progress inside the level', () {
      expect(levelFor(0).fraction, 0.0);
      expect(levelFor(50).fraction, 0.5);
      expect(levelFor(250).fraction, 0.5);
      expect(levelFor(99).fraction, closeTo(0.99, 1e-12));
      expect(levelFor(100).fraction, 0.0);
    });
  });
}
