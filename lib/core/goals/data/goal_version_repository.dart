import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';

/// Stored goal versions (target, enabled, effective-from date).
///
/// Changes to goal values apply FROM TOMORROW (see `nextEffectiveDate`); several
/// changes made for tomorrow replace the same (type, effective date) row.
class GoalVersionRepository {
  GoalVersionRepository(this._database);

  final AppDatabase _database;

  Future<List<GoalVersion>> all() async {
    final rows = await _database.select(_database.goalVersions).get();
    return rows.map(mapRow).whereType<GoalVersion>().toList();
  }

  Stream<List<GoalVersion>> watchAll() => _database
      .select(_database.goalVersions)
      .watch()
      .map((rows) => rows.map(mapRow).whereType<GoalVersion>().toList());

  /// Inserts or replaces the version of ([GoalVersion.type],
  /// [GoalVersion.effectiveFrom]). Call inside a command transaction.
  Future<void> upsert(
    GoalVersion version, {
    required String newId,
    required DateTime nowUtc,
  }) {
    return _database
        .into(_database.goalVersions)
        .insert(
          GoalVersionsCompanion.insert(
            id: newId,
            goalType: version.type.key,
            targetInteger: Value(version.target),
            enabled: version.enabled,
            effectiveFromDate: version.effectiveFrom,
            createdAtUtc: nowUtc,
          ),
          onConflict: DoUpdate(
            (old) => GoalVersionsCompanion(
              targetInteger: Value(version.target),
              enabled: Value(version.enabled),
              createdAtUtc: Value(nowUtc),
            ),
            target: [
              _database.goalVersions.goalType,
              _database.goalVersions.effectiveFromDate,
            ],
          ),
        );
  }

  /// Maps a row; rows with an unknown goal type (impossible by CHECK) are
  /// skipped by callers via `whereType`.
  static GoalVersion? mapRow(GoalVersionRow row) {
    final type = GoalType.tryParse(row.goalType);
    if (type == null) {
      return null;
    }
    return GoalVersion(
      type: type,
      target: row.targetInteger,
      enabled: row.enabled,
      effectiveFrom: row.effectiveFromDate,
    );
  }
}
