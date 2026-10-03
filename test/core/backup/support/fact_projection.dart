import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/shared/local_date.dart';

/// A small stand-in for the goal domain's projection: it rebuilds the XP
/// awards of the given days from the facts in the database.
///
/// 10 points for a day with at least one active weight entry, 4 points for
/// every active water entry of at least 100 ml. It writes `xp_awards` inside
/// the caller's transaction, like the real synchronizer, so tests can prove
/// that "computed values" are recomputed after an import.
final class FactBasedProjection implements ProjectionSynchronizer {
  FactBasedProjection(this._database);

  final AppDatabase _database;

  /// Every synced set of days, in order.
  final List<Set<LocalDate>> syncs = [];

  @override
  Future<void> syncDays(Set<LocalDate> days) async {
    syncs.add(days);
    final db = _database;
    for (final day in days) {
      await (db.delete(
        db.xpAwards,
      )..where((a) => a.localDate.equalsValue(day))).go();

      final weights =
          await (db.select(db.weightEntries)
                ..where(
                  (w) => w.localDate.equalsValue(day) & w.deletedAtUtc.isNull(),
                )
                ..orderBy([(w) => OrderingTerm.asc(w.id)]))
              .get();
      if (weights.isNotEmpty) {
        await db
            .into(db.xpAwards)
            .insert(
              XpAwardsCompanion.insert(
                awardKey: 'weight:${day.toIso()}',
                localDate: day,
                sourceKind: 'weight',
                sourceId: Value(weights.first.id),
                points: 10,
                ruleVersion: 1,
              ),
            );
      }

      final water =
          await (db.select(db.waterEntries)..where(
                (w) => w.localDate.equalsValue(day) & w.deletedAtUtc.isNull(),
              ))
              .get();
      for (final entry in water.where((w) => w.amountMl >= 100)) {
        await db
            .into(db.xpAwards)
            .insert(
              XpAwardsCompanion.insert(
                awardKey: 'water:${entry.id}',
                localDate: day,
                sourceKind: 'water',
                sourceId: Value(entry.id),
                points: 4,
                ruleVersion: 1,
              ),
            );
      }
    }
  }

  @override
  Future<int> totalXp() async {
    final rows = await _database.select(_database.xpAwards).get();
    return rows.fold<int>(0, (sum, row) => sum + row.points);
  }
}

/// Reads the database from inside `syncDays` to prove WHEN it runs relative to
/// the delete and the inserts of an import.
final class ProbingProjection implements ProjectionSynchronizer {
  ProbingProjection(this._database);

  final AppDatabase _database;

  int weightsSeen = -1;
  int staleWeightsSeen = -1;
  int profilesSeen = -1;
  Set<LocalDate>? days;

  /// Id of a row that existed before the import and must be gone by now.
  String? staleWeightId;

  @override
  Future<void> syncDays(Set<LocalDate> days) async {
    this.days = days;
    final db = _database;
    weightsSeen = (await db.select(db.weightEntries).get()).length;
    staleWeightsSeen = staleWeightId == null
        ? 0
        : (await (db.select(
            db.weightEntries,
          )..where((w) => w.id.equals(staleWeightId!))).get()).length;
    profilesSeen = (await db.select(db.profile).get()).length;
  }

  @override
  Future<int> totalXp() async => 0;
}

/// Writes an XP award and then fails: proves that what a projection wrote
/// before failing is rolled back together with the rest.
final class WriteThenFailProjection implements ProjectionSynchronizer {
  WriteThenFailProjection(this._database);

  final AppDatabase _database;

  @override
  Future<void> syncDays(Set<LocalDate> days) async {
    await _database
        .into(_database.xpAwards)
        .insert(
          XpAwardsCompanion.insert(
            awardKey: 'half-done',
            localDate: days.first,
            sourceKind: 'weight',
            points: 1,
            ruleVersion: 1,
          ),
        );
    throw StateError('simulated failure after writing');
  }

  @override
  Future<int> totalXp() async => 0;
}
