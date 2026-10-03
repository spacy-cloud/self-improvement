import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// XP needed to advance one level.
const int xpPerLevel = 100;

/// The level derived from the total XP.
@immutable
final class LevelProgress {
  const LevelProgress({
    required this.level,
    required this.xpInLevel,
    this.xpForNextLevel = xpPerLevel,
  });

  /// Current level, starting at 1.
  final int level;

  /// XP collected inside the current level (0 to 99).
  final int xpInLevel;

  /// XP the current level needs to reach the next one (always 100).
  final int xpForNextLevel;

  /// Progress inside the current level in 0..1 (for a progress bar).
  double get fraction => xpInLevel / xpForNextLevel;

  @override
  bool operator ==(Object other) =>
      other is LevelProgress &&
      other.level == level &&
      other.xpInLevel == xpInLevel &&
      other.xpForNextLevel == xpForNextLevel;

  @override
  int get hashCode => Object.hash(level, xpInLevel, xpForNextLevel);

  @override
  String toString() =>
      'LevelProgress(level: $level, $xpInLevel/$xpForNextLevel)';
}

/// Level of [totalXp]: `1 + floor(totalXp / 100)`, with `totalXp % 100` XP
/// inside the level. 0 gives level 1, 99 level 1, 100 level 2, 250 level 3
/// with 50 of 100. [totalXp] is the sum of all valid awards; a negative value
/// (which cannot occur) is treated as 0.
LevelProgress levelFor(int totalXp) {
  final xp = math.max(0, totalXp);
  return LevelProgress(level: 1 + xp ~/ xpPerLevel, xpInLevel: xp % xpPerLevel);
}
