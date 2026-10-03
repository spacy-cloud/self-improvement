import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/features/gamification/domain/xp_award.dart';
import 'package:self_improvement/features/gamification/domain/xp_calculator.dart';
import 'package:self_improvement/features/gamification/domain/xp_facts.dart';
import 'package:self_improvement/features/gamification/domain/xp_reconciliation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Keeps the `xp_awards` projection equal to what the facts of a day earn.
///
/// For a day it loads ALL active facts of that stored local date, computes the
/// desired awards with the pure `computeDayAwards` and reconciles the stored
/// rows (insert missing, update changed, delete no longer valid). Nothing is
/// accumulated: running it again changes nothing, so a retry or rebuild can
/// never create points. Total XP is the sum of the rows.
class XpProjector {
  XpProjector(this._database);

  final AppDatabase _database;

  /// Reconciles the awards of [day]. Call inside the command transaction.
  Future<void> syncDay(LocalDate day, {required LocalDate profileStart}) async {
    final facts = await loadFacts(day);
    final desired = computeDayAwards(facts, profileStart: profileStart);
    final stored = await (_database.select(
      _database.xpAwards,
    )..where((a) => a.localDate.equalsValue(day))).get();
    final diff = reconcileAwards(
      existing: stored.map(_toAward).whereType<XpAward>(),
      desired: desired,
    );
    if (diff.isEmpty) {
      return;
    }
    for (final key in diff.toDeleteKeys) {
      await (_database.delete(
        _database.xpAwards,
      )..where((a) => a.awardKey.equals(key))).go();
    }
    for (final award in diff.toUpsert) {
      await _database
          .into(_database.xpAwards)
          .insertOnConflictUpdate(
            XpAwardsCompanion.insert(
              awardKey: award.key,
              localDate: award.date,
              sourceKind: award.source.key,
              sourceId: Value(award.sourceId),
              points: award.points,
              ruleVersion: award.ruleVersion,
            ),
          );
    }
  }

  /// Total XP: the sum of all valid awards (never a stored counter).
  Future<int> totalXp() async {
    final sum = _database.xpAwards.points.sum();
    final row = await (_database.selectOnly(
      _database.xpAwards,
    )..addColumns([sum])).getSingle();
    return row.read(sum) ?? 0;
  }

  /// All active facts of [day] that can earn XP.
  Future<XpDayFacts> loadFacts(LocalDate day) async {
    final water =
        await (_database.select(_database.waterEntries)..where(
              (w) => w.localDate.equalsValue(day) & w.deletedAtUtc.isNull(),
            ))
            .get();
    final weights =
        await (_database.select(_database.weightEntries)..where(
              (w) => w.localDate.equalsValue(day) & w.deletedAtUtc.isNull(),
            ))
            .get();
    final steps =
        await (_database.select(_database.stepDays)..where(
              (s) => s.localDate.equalsValue(day) & s.deletedAtUtc.isNull(),
            ))
            .getSingleOrNull();
    final tasks =
        await (_database.select(_database.tasks)..where(
              (t) =>
                  t.completedLocalDate.equalsValue(day) &
                  t.completedAtUtc.isNotNull() &
                  t.deletedAtUtc.isNull(),
            ))
            .get();
    final focus =
        await (_database.select(_database.focusSessions)..where(
              (f) =>
                  f.completedLocalDate.equalsValue(day) &
                  f.status.equals('completed') &
                  f.deletedAtUtc.isNull(),
            ))
            .get();
    final workouts =
        await (_database.select(_database.workoutEntries)..where(
              (w) => w.localDate.equalsValue(day) & w.deletedAtUtc.isNull(),
            ))
            .get();
    final checks = await _database
        .customSelect(
          'SELECT c.id, c.habit_id, c.checked_at_utc, c.created_at_utc, '
          'c.eligibility FROM habit_checks c '
          'JOIN habits h ON h.id = c.habit_id '
          'WHERE c.local_date = ?1 AND c.deleted_at_utc IS NULL '
          'AND h.deleted_at_utc IS NULL',
          variables: [Variable(day.toIso())],
        )
        .get();

    DateTime utc(int millis) =>
        DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

    return XpDayFacts(
      date: day,
      water: [
        for (final row in water)
          WaterXpFact(
            id: row.id,
            occurredAtUtc: row.occurredAtUtc,
            createdAtUtc: row.createdAtUtc,
            eligible: row.gamificationEligible,
            amountMl: row.amountMl,
          ),
      ],
      weights: [
        for (final row in weights)
          WeightXpFact(
            id: row.id,
            occurredAtUtc: row.occurredAtUtc,
            createdAtUtc: row.createdAtUtc,
            eligible: row.gamificationEligible,
          ),
      ],
      steps: steps == null
          ? null
          : StepsXpFact(
              steps: steps.steps,
              reachedGoalEligible: steps.reachedGoalEligible,
              xpGoalTargetSteps: steps.xpGoalTargetSteps,
            ),
      tasks: [
        for (final row in tasks)
          TaskXpFact(
            id: row.id,
            occurredAtUtc: row.completedAtUtc!,
            createdAtUtc: row.createdAtUtc,
            eligible: row.completionEligibility ?? false,
          ),
      ],
      focusSessions: [
        for (final row in focus)
          FocusXpFact(
            id: row.id,
            occurredAtUtc: row.endedAtUtc ?? row.createdAtUtc,
            createdAtUtc: row.createdAtUtc,
            eligible: row.gamificationEligible,
            accumulatedSeconds: row.accumulatedSeconds,
          ),
      ],
      workouts: [
        for (final row in workouts)
          WorkoutXpFact(
            id: row.id,
            occurredAtUtc: row.occurredAtUtc,
            createdAtUtc: row.createdAtUtc,
            eligible: row.gamificationEligible,
          ),
      ],
      habitChecks: [
        for (final row in checks)
          HabitCheckXpFact(
            id: row.read<String>('id'),
            occurredAtUtc: utc(row.read<int>('checked_at_utc')),
            createdAtUtc: utc(row.read<int>('created_at_utc')),
            eligible: row.read<bool>('eligibility'),
            habitId: row.read<String>('habit_id'),
          ),
      ],
    );
  }

  static XpAward? _toAward(XpAwardRow row) {
    final source = XpSource.tryParse(row.sourceKind);
    if (source == null) {
      return null;
    }
    return XpAward(
      key: row.awardKey,
      date: row.localDate,
      source: source,
      sourceId: row.sourceId,
      points: row.points,
      ruleVersion: row.ruleVersion,
    );
  }
}
