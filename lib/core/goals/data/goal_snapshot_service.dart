import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/domain/day_snapshot.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_status_repository.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Maintains the stored daily goal snapshots.
///
/// A snapshot freezes which goals applied on a day and their thresholds, so
/// later goal or module changes never rewrite history. Whether a goal was
/// fulfilled is NEVER stored; it is derived from the facts of the day.
///
/// - Missing past days are created from the stored goal versions and the module
///   status history, in batches of at most [batchDays] days.
/// - The snapshot of TODAY follows module changes immediately (see
///   `maskTodaySnapshot`); past days never change.
/// - No snapshot exists before the profile start date or for future days.
class GoalSnapshotService {
  GoalSnapshotService({
    required this._database,
    required this._clock,
    required this._ids,
  });

  /// Maximum days handled per batch when catching up a long period.
  static const int batchDays = 365;

  final AppDatabase _database;
  final ClockService _clock;
  final IdGenerator _ids;

  /// Creates missing snapshots for [days] and re-masks today's snapshot.
  /// Idempotent; call inside the command transaction.
  Future<void> ensureForDays(Iterable<LocalDate> days) async {
    final sources = await _loadSources();
    if (sources == null) {
      return;
    }
    final today = _clock.today();
    final wanted =
        days
            .where((day) => day >= sources.profileStart && day <= today)
            .toSet()
            .toList()
          ..sort();
    if (wanted.isEmpty) {
      return;
    }
    final stored = await _storedBetween(wanted.first, wanted.last);
    final inserts = <DailyGoalSnapshotsCompanion>[];
    final updates = <(String, bool)>[];

    for (final day in wanted) {
      final existing = stored[day];
      if (existing == null) {
        final built = buildDaySnapshot(
          day: day,
          profileStart: sources.profileStart,
          versions: sources.versions,
          isModuleEnabledOn: sources.isModuleEnabledOn,
          habits: sources.habits,
        );
        if (built != null) {
          inserts.addAll(_companions(built));
        }
      } else if (day == today) {
        final masked = maskTodaySnapshot(
          today: today,
          stored: _toSnapshot(day, existing),
          versions: sources.versions,
          habits: sources.habits,
          isModuleEnabledNow: (module) =>
              sources.isModuleEnabledOn(module, today),
        );
        final byKey = {for (final row in existing) row.goalKey: row};
        for (final item in masked.items) {
          final row = byKey[item.goalKey];
          if (row == null) {
            inserts.add(_companion(day, item));
          } else if (row.applicable != item.applicable) {
            updates.add((row.id, item.applicable));
          }
        }
      }
    }

    if (inserts.isNotEmpty) {
      await _database.batch((batch) {
        batch.insertAll(
          _database.dailyGoalSnapshots,
          inserts,
          mode: InsertMode.insertOrIgnore,
        );
      });
    }
    for (final (id, applicable) in updates) {
      await (_database.update(_database.dailyGoalSnapshots)
            ..where((s) => s.id.equals(id)))
          .write(DailyGoalSnapshotsCompanion(applicable: Value(applicable)));
    }
  }

  /// Creates every missing snapshot from the profile start through [to]
  /// (clamped to today), [batchDays] days per batch/transaction.
  Future<void> ensureThrough(LocalDate to) async {
    final profileStart = await _profileStart();
    if (profileStart == null) {
      return;
    }
    final today = _clock.today();
    final end = LocalDate.earlier(to, today);
    var cursor = profileStart;
    while (cursor <= end) {
      final batchEnd = LocalDate.earlier(cursor.addDays(batchDays - 1), end);
      await _database.transaction(() async {
        await ensureForDays(cursor.rangeTo(batchEnd));
      });
      cursor = batchEnd.addDays(1);
    }
  }

  /// The stored snapshot of [day], or null.
  Future<DaySnapshot?> snapshotFor(LocalDate day) async {
    final stored = await _storedBetween(day, day);
    final rows = stored[day];
    return rows == null ? null : _toSnapshot(day, rows);
  }

  /// Stored snapshots of `[from, to]` (days without one are absent).
  Future<Map<LocalDate, DaySnapshot>> snapshotsBetween(
    LocalDate from,
    LocalDate to,
  ) async {
    final stored = await _storedBetween(from, to);
    return {
      for (final entry in stored.entries)
        entry.key: _toSnapshot(entry.key, entry.value),
    };
  }

  // ---------------------------------------------------------------- helpers

  Future<LocalDate?> _profileStart() async {
    final row = await _database.select(_database.profile).getSingleOrNull();
    return row?.startedLocalDate;
  }

  Future<_Sources?> _loadSources() async {
    final profile = await _database.select(_database.profile).getSingleOrNull();
    if (profile == null) {
      return null;
    }
    final versions = (await _database.select(_database.goalVersions).get())
        .map(GoalVersionRepository.mapRow)
        .whereType<GoalVersion>()
        .toList();
    final history = await _database.select(_database.moduleStatusHistory).get();
    final habitRows = await (_database.select(
      _database.habits,
    )..where((h) => h.deletedAtUtc.isNull())).get();
    return _Sources(
      profileStart: profile.startedLocalDate,
      versions: versions,
      history: history,
      habits: [
        for (final habit in habitRows)
          HabitSnapshotInput(
            id: habit.id,
            startedOn: habit.startedLocalDate,
            archivedFrom: habit.archivedFromDate,
          ),
      ],
    );
  }

  Future<Map<LocalDate, List<DailyGoalSnapshotRow>>> _storedBetween(
    LocalDate from,
    LocalDate to,
  ) async {
    final rows =
        await (_database.select(_database.dailyGoalSnapshots)
              ..where(
                (s) => s.localDate.isBetweenValues(from.toIso(), to.toIso()),
              )
              ..orderBy([(s) => OrderingTerm.asc(s.goalKey)]))
            .get();
    final map = <LocalDate, List<DailyGoalSnapshotRow>>{};
    for (final row in rows) {
      map.putIfAbsent(row.localDate, () => []).add(row);
    }
    return map;
  }

  DaySnapshot _toSnapshot(LocalDate day, List<DailyGoalSnapshotRow> rows) =>
      DaySnapshot(
        date: day,
        items: [
          for (final row in rows)
            if (ModuleId.tryParse(row.moduleId) case final module?)
              GoalSnapshotItem(
                goalKey: row.goalKey,
                module: module,
                target: row.targetInteger,
                applicable: row.applicable,
              ),
        ],
      );

  List<DailyGoalSnapshotsCompanion> _companions(DaySnapshot snapshot) => [
    for (final item in snapshot.items) _companion(snapshot.date, item),
  ];

  DailyGoalSnapshotsCompanion _companion(
    LocalDate day,
    GoalSnapshotItem item,
  ) => DailyGoalSnapshotsCompanion.insert(
    id: _ids.newId(),
    localDate: day,
    goalKey: item.goalKey,
    moduleId: item.module.key,
    targetInteger: Value(item.target),
    applicable: item.applicable,
  );
}

class _Sources {
  _Sources({
    required this.profileStart,
    required this.versions,
    required this.history,
    required this.habits,
  });

  final LocalDate profileStart;
  final List<GoalVersion> versions;
  final List<ModuleStatusRow> history;
  final List<HabitSnapshotInput> habits;

  bool isModuleEnabledOn(ModuleId module, LocalDate day) =>
      ModuleStatusRepository.statusesFromHistory(history, day)[module] ?? true;
}
