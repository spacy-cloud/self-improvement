import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/reactive.dart';
import 'package:self_improvement/core/goals/data/day_status_repository.dart';
import 'package:self_improvement/features/gamification/data/xp_projector.dart';
import 'package:self_improvement/features/gamification/domain/badges.dart';
import 'package:self_improvement/features/gamification/domain/level.dart';

/// XP, level and badges as shown on the progress page and the dashboard card.
@immutable
final class GamificationSummary {
  const GamificationSummary({
    required this.totalXp,
    required this.level,
    required this.badges,
  });

  /// Sum of all valid awards (never a stored counter).
  final int totalXp;

  /// Level 1 + totalXp / 100 and the progress inside the level.
  final LevelProgress level;

  /// The three badges, locked or earned (derived from current data; a badge
  /// can be locked again after data was corrected or deleted).
  final List<BadgeStatus> badges;
}

/// Derives the gamification summary from the database.
///
/// Nothing here is stored: total XP is the sum of `xp_awards`, level and badges
/// are pure functions of the facts. The projection keeps `xp_awards` equal to
/// what the facts earn, also while the gamification module is switched off.
class GamificationRepository {
  GamificationRepository({
    required this._database,
    required this._xp,
    required this._status,
  });

  final AppDatabase _database;
  final XpProjector _xp;
  final DayStatusRepository _status;

  List<ResultSetImplementation<dynamic, dynamic>> get _tables => [
    _database.xpAwards,
    _database.waterEntries,
    _database.weightEntries,
    _database.stepDays,
    _database.tasks,
    _database.focusSessions,
    _database.workoutEntries,
    _database.habitChecks,
    _database.habits,
    _database.dailyGoalSnapshots,
    _database.goalVersions,
    _database.moduleStatusHistory,
    _database.profile,
  ];

  /// Total XP, re-emitted when awards change.
  Stream<int> watchTotalXp() =>
      watchComputed(_database, [_database.xpAwards], _xp.totalXp);

  /// The summary, recomputed on every relevant change.
  Stream<GamificationSummary> watchSummary() =>
      watchComputed(_database, _tables, summary);

  Future<GamificationSummary> summary() async {
    final totalXp = await _xp.totalXp();
    final streak = await _status.computeStreakSummary();
    return GamificationSummary(
      totalXp: totalXp,
      level: levelFor(totalXp),
      badges: computeBadges(
        hasEligibleActivity: await hasEligibleActivity(),
        longestStreak: streak?.longest ?? 0,
        completedFocusSeconds: await completedFocusSeconds(),
      ),
    );
  }

  /// True if at least one active record exists whose eligibility was true when
  /// it was created or completed (an activity that was entitled to XP).
  Future<bool> hasEligibleActivity() async {
    final row = await _database
        .customSelect(
          'SELECT 1 AS hit WHERE '
          'EXISTS (SELECT 1 FROM water_entries WHERE gamification_eligible = 1 AND deleted_at_utc IS NULL) OR '
          'EXISTS (SELECT 1 FROM weight_entries WHERE gamification_eligible = 1 AND deleted_at_utc IS NULL) OR '
          'EXISTS (SELECT 1 FROM step_days WHERE reached_goal_eligible = 1 AND deleted_at_utc IS NULL) OR '
          'EXISTS (SELECT 1 FROM tasks WHERE completion_eligibility = 1 AND completed_at_utc IS NOT NULL AND deleted_at_utc IS NULL) OR '
          "EXISTS (SELECT 1 FROM focus_sessions WHERE status = 'completed' AND gamification_eligible = 1 AND deleted_at_utc IS NULL) OR "
          'EXISTS (SELECT 1 FROM workout_entries WHERE gamification_eligible = 1 AND deleted_at_utc IS NULL) OR '
          'EXISTS (SELECT 1 FROM habit_checks c JOIN habits h ON h.id = c.habit_id '
          'WHERE c.eligibility = 1 AND c.deleted_at_utc IS NULL AND h.deleted_at_utc IS NULL)',
        )
        .getSingleOrNull();
    return row != null;
  }

  /// Sum of the saved duration of all completed focus sessions, in seconds.
  Future<int> completedFocusSeconds() async {
    final row = await _database
        .customSelect(
          'SELECT COALESCE(SUM(accumulated_seconds), 0) AS total '
          "FROM focus_sessions WHERE status = 'completed' "
          'AND deleted_at_utc IS NULL',
        )
        .getSingle();
    return row.read<int>('total');
  }
}
