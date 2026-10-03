import 'package:flutter/foundation.dart';
import 'package:self_improvement/features/gamification/domain/xp_rules.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The activity kind an XP award stems from. The string [key] is the stable
/// persisted `source_kind`.
enum XpSource {
  water('water'),
  weight('weight'),
  steps('steps'),
  task('task'),
  focus('focus'),
  workout('workout'),
  habit('habit');

  const XpSource(this.key);

  /// Stable persisted identifier.
  final String key;

  /// Returns the source for a persisted [key], or `null` when unknown.
  static XpSource? tryParse(String key) {
    for (final source in values) {
      if (source.key == key) {
        return source;
      }
    }
    return null;
  }
}

/// The award keys (primary key of `xp_awards`). A key identifies what is
/// rewarded, so recomputing never creates a second award for the same thing.
abstract final class XpKeys {
  /// `water:<entryId>`
  static String water(String entryId) => 'water:$entryId';

  /// `weight:<YYYY-MM-DD>`
  static String weight(LocalDate date) => 'weight:${date.toIso()}';

  /// `steps:<YYYY-MM-DD>`
  static String steps(LocalDate date) => 'steps:${date.toIso()}';

  /// `task:<taskId>`
  static String task(String taskId) => 'task:$taskId';

  /// `focus:<sessionId>`
  static String focus(String sessionId) => 'focus:$sessionId';

  /// `workout:<YYYY-MM-DD>`
  static String workout(LocalDate date) => 'workout:${date.toIso()}';

  /// `habit:<habitId>:<YYYY-MM-DD>`
  static String habit(String habitId, LocalDate date) =>
      'habit:$habitId:${date.toIso()}';
}

/// One desired row of `xp_awards`: a fixed number of points for one thing.
///
/// Total XP is the sum of all valid awards; no counter is stored anywhere.
@immutable
final class XpAward {
  const XpAward({
    required this.key,
    required this.date,
    required this.source,
    this.sourceId,
    required this.points,
    this.ruleVersion = XpRules.ruleVersion,
  }) : assert(points >= 0, 'XP points are never negative');

  /// Unique award key, see [XpKeys].
  final String key;

  /// The stored local date of the rewarded activity (not the day it was
  /// entered).
  final LocalDate date;

  final XpSource source;

  /// The record the award is attributed to: the water entry, task or focus
  /// session id, or the habit id. `null` for the per-day awards of weight,
  /// steps and workout, which are not tied to one record.
  final String? sourceId;

  final int points;

  /// The rule version that fixed [points].
  final int ruleVersion;

  @override
  bool operator ==(Object other) =>
      other is XpAward &&
      other.key == key &&
      other.date == date &&
      other.source == source &&
      other.sourceId == sourceId &&
      other.points == points &&
      other.ruleVersion == ruleVersion;

  @override
  int get hashCode =>
      Object.hash(key, date, source, sourceId, points, ruleVersion);

  @override
  String toString() =>
      'XpAward($key, $date, ${source.key}, sourceId: $sourceId, '
      'points: $points, v$ruleVersion)';
}
