import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/goals/data/goal_snapshot_service.dart';
import 'package:self_improvement/features/gamification/data/xp_projector.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The real projection hook of the command runner.
///
/// Runs inside the command transaction for every affected local date: first the
/// goal snapshots (so today's snapshot follows module changes and missing past
/// days are frozen from their versions), then the XP awards of that day. A
/// failure rolls back the fact mutation too.
class ProjectionSynchronizerImpl implements ProjectionSynchronizer {
  ProjectionSynchronizerImpl({
    required this._database,
    required this._snapshots,
    required this._xp,
  });

  final AppDatabase _database;
  final GoalSnapshotService _snapshots;
  final XpProjector _xp;

  @override
  Future<void> syncDays(Set<LocalDate> days) async {
    if (days.isEmpty) {
      return;
    }
    final profile = await _database.select(_database.profile).getSingleOrNull();
    if (profile == null) {
      return;
    }
    await _snapshots.ensureForDays(days);
    final sorted = days.toList()..sort();
    for (final day in sorted) {
      await _xp.syncDay(day, profileStart: profile.startedLocalDate);
    }
  }

  @override
  Future<int> totalXp() => _xp.totalXp();
}
