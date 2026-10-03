import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/reactive.dart';
import 'package:self_improvement/core/goals/data/day_facts_source.dart';
import 'package:self_improvement/core/goals/data/goal_snapshot_service.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Read models derived from snapshots plus facts: the day status (ring) and the
/// streak. Nothing here is stored; every value is recomputed from the database.
class DayStatusRepository {
  DayStatusRepository({
    required this._database,
    required this._clock,
    required this._snapshots,
    required this._facts,
  });

  final AppDatabase _database;
  final ClockService _clock;
  final GoalSnapshotService _snapshots;
  final DayFactsSource _facts;

  /// The tables a day status depends on.
  List<ResultSetImplementation<dynamic, dynamic>> get _tables => [
    ..._facts.tables,
    _database.dailyGoalSnapshots,
    _database.goalVersions,
    _database.moduleStatusHistory,
    _database.profile,
  ];

  /// The status of [day]; null for days before the profile start or in the
  /// future (no snapshot exists there).
  Future<DayStatus?> statusFor(LocalDate day) async {
    await _snapshots.ensureForDays([day]);
    final snapshot = await _snapshots.snapshotFor(day);
    if (snapshot == null) {
      return null;
    }
    return computeDayStatus(snapshot, await _facts.factsFor(day));
  }

  /// Statuses for every day of `[from, to]` that has a snapshot. Missing
  /// snapshots from the profile start up to [to] are caught up first.
  Future<Map<LocalDate, DayStatus>> statusesBetween(
    LocalDate from,
    LocalDate to,
  ) async {
    await _snapshots.ensureThrough(to);
    final snapshots = await _snapshots.snapshotsBetween(from, to);
    if (snapshots.isEmpty) {
      return const {};
    }
    final facts = await _facts.factsBetween(from, to);
    return {
      for (final entry in snapshots.entries)
        entry.key: computeDayStatus(
          entry.value,
          facts[entry.key] ?? DayFactsSource.emptyFacts(entry.key),
        ),
    };
  }

  /// Re-emits the status of [day] whenever a relevant table changes.
  Stream<DayStatus?> watchDay(LocalDate day) =>
      watchComputed(_database, _tables, () => statusFor(day));

  /// Re-emits statuses of `[from, to]` whenever a relevant table changes.
  Stream<Map<LocalDate, DayStatus>> watchBetween(
    LocalDate from,
    LocalDate to,
  ) => watchComputed(_database, _tables, () => statusesBetween(from, to));

  /// The global streak summary, recomputed on every relevant change.
  Stream<StreakSummary?> watchStreak() =>
      watchComputed(_database, _tables, computeStreakSummary);

  /// The streak summary now, or null before the profile exists.
  Future<StreakSummary?> computeStreakSummary() async {
    final profile = await _database.select(_database.profile).getSingleOrNull();
    if (profile == null) {
      return null;
    }
    final today = _clock.today();
    final start = profile.startedLocalDate;
    if (today < start) {
      return null;
    }
    final statuses = await statusesBetween(start, today);
    return computeStreak(
      today: today,
      profileStart: start,
      isActiveDay: (day) => statuses[day]?.isActive ?? false,
    );
  }
}
