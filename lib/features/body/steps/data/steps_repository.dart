import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/command_context.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/goal_snapshot_service.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/features/body/steps/domain/step_day.dart';
import 'package:self_improvement/features/body/steps/domain/step_source.dart';
import 'package:self_improvement/features/body/steps/domain/steps_input.dart';
import 'package:self_improvement/features/gamification/domain/steps_eligibility.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Daily step totals: one active value per local date, typed in by hand or
/// taken from the health interface (`source`).
///
/// Saving a date again REPLACES the value (never adds). A value the user
/// types in always makes the row `manual`; the comparison with the health
/// interface ([applyHealthTotals]) never touches such a row. The first time an
/// applicable step goal is reached, the XP decision is frozen on the row
/// (`decideStepsEligibility`); later corrections keep it and the award only
/// holds while the value still reaches the frozen threshold.
class StepsRepository {
  StepsRepository({
    required this._database,
    required this._runner,
    required this._snapshots,
  });

  static const String setType = 'steps.set';
  static const String deleteType = 'steps.delete';
  static const String undoSetType = 'steps.set.undo';
  static const String undoDeleteType = 'steps.delete.undo';

  /// The comparison with the health interface (one command per run).
  static const String healthSyncType = 'steps.health.sync';

  final AppDatabase _database;
  final CommandRunner _runner;
  final GoalSnapshotService _snapshots;

  // ---------------------------------------------------------------- reads

  /// All active step days, newest date first.
  Stream<List<StepDay>> watchAll() =>
      (_database.select(_database.stepDays)
            ..where((s) => s.deletedAtUtc.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.localDate)]))
          .watch()
          .map((rows) => rows.map(mapStepDay).toList());

  /// The active total of [date], or null ("Keine Angabe").
  Stream<StepDay?> watchDay(LocalDate date) =>
      (_database.select(_database.stepDays)..where(
            (s) => s.localDate.equalsValue(date) & s.deletedAtUtc.isNull(),
          ))
          .watchSingleOrNull()
          .map((row) => row == null ? null : mapStepDay(row));

  Future<StepDay?> findDay(LocalDate date) async {
    final row =
        await (_database.select(_database.stepDays)..where(
              (s) => s.localDate.equalsValue(date) & s.deletedAtUtc.isNull(),
            ))
            .getSingleOrNull();
    return row == null ? null : mapStepDay(row);
  }

  // ------------------------------------------------------------- commands

  /// Records [steps] as the total of [date], replacing an existing value. The
  /// day becomes `manual`, also when it came from the health interface until
  /// now: the value the user types in has priority from then on.
  Future<CommandOutcome> setSteps({
    required String commandId,
    required LocalDate date,
    required int steps,
  }) {
    return _runner.run(
      commandId: commandId,
      type: setType,
      body: (ctx) async {
        validateStepDay(steps: steps, date: date, today: ctx.today);
        final existing = await _activeRow(date);
        final decision = await _eligibility(ctx, date, steps, existing);

        if (existing == null) {
          final id = ctx.ids.newId();
          await _insertDay(
            ctx,
            id: id,
            date: date,
            steps: steps,
            source: StepSource.manual,
            decision: decision,
          );
          return CommandEffect(
            entityId: id,
            affectedDays: {date},
            undo: UndoAction(
              run: (undoId) => _softDelete(
                commandId: undoId,
                id: id,
                expectedRowVersion: 1,
                type: undoSetType,
              ),
            ),
          );
        }

        final newVersion = existing.rowVersion + 1;
        await _updateDay(
          ctx,
          existing: existing,
          steps: steps,
          source: StepSource.manual,
          decision: decision,
        );
        return CommandEffect(
          entityId: existing.id,
          affectedDays: {date},
          undo: UndoAction(
            run: (undoId) => _restoreValues(
              commandId: undoId,
              previous: existing,
              expectedRowVersion: newVersion,
            ),
          ),
        );
      },
    );
  }

  /// Compares the totals the health interface reports with the stored days.
  ///
  /// [totals] holds one entry per local day that was asked for; `null` means
  /// "no data" for that day. The conflict rule is [decideHealthDay]:
  ///
  /// - a day with a value the user typed in is never touched,
  /// - a day without a value gets the total (source `health`),
  /// - a value the interface wrote itself is updated when the total changed,
  /// - "no data" creates nothing and removes nothing.
  ///
  /// A total above the range of the app (100.000) is limited to it. The days
  /// that change run in ONE command (atomic, with the goal snapshot and XP of
  /// every changed day); the XP follow the stored value exactly like a value
  /// the user typed in, also for a day in the past. When nothing would change
  /// no command runs at all (no receipt, no event). The decision is made again
  /// inside the transaction, so a value the user types in at the same moment
  /// always wins.
  Future<HealthApplyResult> applyHealthTotals({
    required String commandId,
    required Map<LocalDate, int?> totals,
  }) async {
    final limited = {
      for (final entry in totals.entries)
        entry.key: entry.value?.clamp(minStepsPerDay, maxStepsPerDay),
    };
    final preview = await _planHealth(limited);
    if (preview.changes.isEmpty) {
      return preview.result;
    }
    var applied = preview.result;
    await _runner.run(
      commandId: commandId,
      type: healthSyncType,
      body: (ctx) async {
        final plan = await _planHealth(limited);
        applied = plan.result;
        final changedDays = <LocalDate>{};
        for (final change in plan.changes) {
          final existing = change.existing;
          final decision = await _eligibility(
            ctx,
            change.date,
            change.steps,
            existing,
          );
          if (existing == null) {
            await _insertDay(
              ctx,
              id: ctx.ids.newId(),
              date: change.date,
              steps: change.steps,
              source: StepSource.health,
              decision: decision,
            );
          } else {
            await _updateDay(
              ctx,
              existing: existing,
              steps: change.steps,
              source: StepSource.health,
              decision: decision,
            );
          }
          changedDays.add(change.date);
        }
        return CommandEffect(affectedDays: changedDays);
      },
    );
    return applied;
  }

  /// Removes the total of [date] (soft delete; the day becomes "Keine Angabe").
  Future<CommandOutcome> deleteDay({
    required String commandId,
    required LocalDate date,
  }) {
    return _runner.run(
      commandId: commandId,
      type: deleteType,
      body: (ctx) async {
        final row = await _activeRow(date);
        if (row == null) {
          throw NotFoundFailure(entity: 'step_day', id: date.toIso());
        }
        return _deleteBody(ctx.nowUtc, row, expectedRowVersion: null);
      },
    );
  }

  // -------------------------------------------------------------- helpers

  Future<CommandOutcome> _softDelete({
    required String commandId,
    required String id,
    required int expectedRowVersion,
    required String type,
  }) {
    return _runner.run(
      commandId: commandId,
      type: type,
      body: (ctx) async {
        final row =
            await (_database.select(_database.stepDays)
                  ..where((s) => s.id.equals(id) & s.deletedAtUtc.isNull()))
                .getSingleOrNull();
        if (row == null) {
          throw NotFoundFailure(entity: 'step_day', id: id);
        }
        return _deleteBody(
          ctx.nowUtc,
          row,
          expectedRowVersion: expectedRowVersion,
        );
      },
    );
  }

  Future<CommandEffect> _deleteBody(
    DateTime nowUtc,
    StepDayRow row, {
    required int? expectedRowVersion,
  }) async {
    if (expectedRowVersion != null && row.rowVersion != expectedRowVersion) {
      throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: row.id);
    }
    final newVersion = row.rowVersion + 1;
    await (_database.update(
      _database.stepDays,
    )..where((s) => s.id.equals(row.id))).write(
      StepDaysCompanion(
        deletedAtUtc: Value(nowUtc),
        updatedAtUtc: Value(nowUtc),
        rowVersion: Value(newVersion),
      ),
    );
    return CommandEffect(
      entityId: row.id,
      affectedDays: {row.localDate},
      kind: EffectKind.removed,
      undo: UndoAction(
        run: (undoId) => _restoreDeleted(
          commandId: undoId,
          id: row.id,
          expectedRowVersion: newVersion,
        ),
      ),
    );
  }

  Future<CommandOutcome> _restoreDeleted({
    required String commandId,
    required String id,
    required int expectedRowVersion,
  }) {
    return _runner.run(
      commandId: commandId,
      type: undoDeleteType,
      body: (ctx) async {
        final row = await (_database.select(
          _database.stepDays,
        )..where((s) => s.id.equals(id))).getSingleOrNull();
        if (row == null) {
          throw NotFoundFailure(entity: 'step_day', id: id);
        }
        if (row.deletedAtUtc == null || row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        if (await _activeRow(row.localDate) != null) {
          // The day was filled again meanwhile: keep that newer value.
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        await (_database.update(
          _database.stepDays,
        )..where((s) => s.id.equals(id))).write(
          StepDaysCompanion(
            deletedAtUtc: const Value(null),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(row.rowVersion + 1),
          ),
        );
        return CommandEffect(entityId: id, affectedDays: {row.localDate});
      },
    );
  }

  Future<CommandOutcome> _restoreValues({
    required String commandId,
    required StepDayRow previous,
    required int expectedRowVersion,
  }) {
    return _runner.run(
      commandId: commandId,
      type: undoSetType,
      body: (ctx) async {
        final current =
            await (_database.select(_database.stepDays)..where(
                  (s) => s.id.equals(previous.id) & s.deletedAtUtc.isNull(),
                ))
                .getSingleOrNull();
        if (current == null) {
          throw NotFoundFailure(entity: 'step_day', id: previous.id);
        }
        if (current.rowVersion != expectedRowVersion) {
          throw ConflictFailure(
            ConflictKind.staleVersion,
            relatedEntityId: previous.id,
          );
        }
        await (_database.update(
          _database.stepDays,
        )..where((s) => s.id.equals(previous.id))).write(
          StepDaysCompanion(
            steps: Value(previous.steps),
            source: Value(previous.source),
            reachedGoalEligible: Value(previous.reachedGoalEligible),
            xpGoalTargetSteps: Value(previous.xpGoalTargetSteps),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(current.rowVersion + 1),
          ),
        );
        return CommandEffect(
          entityId: previous.id,
          affectedDays: {previous.localDate},
        );
      },
    );
  }

  /// The frozen XP decision for [steps] on [date]: the threshold of that day
  /// must exist before the decision is made.
  Future<StepsEligibility> _eligibility(
    CommandContext ctx,
    LocalDate date,
    int steps,
    StepDayRow? existing,
  ) async {
    await _snapshots.ensureForDays([date]);
    final snapshot = await _snapshots.snapshotFor(date);
    return decideStepsEligibility(
      newSteps: steps,
      applicableTarget: snapshot?.applicableTargetFor(GoalType.steps.key),
      gamificationEnabled: await ctx.isGamificationEnabled(),
      existingReachedGoalEligible: existing?.reachedGoalEligible,
      existingXpGoalTargetSteps: existing?.xpGoalTargetSteps,
    );
  }

  Future<void> _insertDay(
    CommandContext ctx, {
    required String id,
    required LocalDate date,
    required int steps,
    required StepSource source,
    required StepsEligibility decision,
  }) => _database
      .into(_database.stepDays)
      .insert(
        StepDaysCompanion.insert(
          id: id,
          localDate: date,
          steps: steps,
          timezoneId: ctx.timeZoneId,
          source: Value(source.key),
          reachedGoalEligible: Value(decision.reachedGoalEligible),
          xpGoalTargetSteps: Value(decision.xpGoalTargetSteps),
          createdAtUtc: ctx.nowUtc,
          updatedAtUtc: ctx.nowUtc,
        ),
      );

  Future<void> _updateDay(
    CommandContext ctx, {
    required StepDayRow existing,
    required int steps,
    required StepSource source,
    required StepsEligibility decision,
  }) =>
      (_database.update(
        _database.stepDays,
      )..where((s) => s.id.equals(existing.id))).write(
        StepDaysCompanion(
          steps: Value(steps),
          source: Value(source.key),
          reachedGoalEligible: Value(decision.reachedGoalEligible),
          xpGoalTargetSteps: Value(decision.xpGoalTargetSteps),
          updatedAtUtc: Value(ctx.nowUtc),
          rowVersion: Value(existing.rowVersion + 1),
        ),
      );

  /// Applies [decideHealthDay] to every day of [totals] (read only).
  Future<_HealthPlan> _planHealth(Map<LocalDate, int?> totals) async {
    final changes = <_HealthChange>[];
    var result = HealthApplyResult.none;
    final days = totals.keys.toList()..sort();
    for (final date in days) {
      final existing = await _activeRow(date);
      final steps = totals[date];
      final action = decideHealthDay(
        existingSource: existing == null
            ? null
            : StepSource.tryParse(existing.source) ?? StepSource.manual,
        existingSteps: existing?.steps,
        healthSteps: steps,
      );
      result = result.plus(action);
      if (action == HealthDayAction.create ||
          action == HealthDayAction.update) {
        changes.add(_HealthChange(date, steps!, existing));
      }
    }
    return _HealthPlan(changes, result);
  }

  Future<StepDayRow?> _activeRow(LocalDate date) =>
      (_database.select(_database.stepDays)..where(
            (s) => s.localDate.equalsValue(date) & s.deletedAtUtc.isNull(),
          ))
          .getSingleOrNull();

  static StepDay mapStepDay(StepDayRow row) => StepDay(
    id: row.id,
    date: row.localDate,
    steps: row.steps,
    rowVersion: row.rowVersion,
    reachedGoalEligible: row.reachedGoalEligible,
    xpGoalTargetSteps: row.xpGoalTargetSteps,
    source: StepSource.tryParse(row.source) ?? StepSource.manual,
  );
}

/// One day the comparison creates or updates.
final class _HealthChange {
  const _HealthChange(this.date, this.steps, this.existing);

  final LocalDate date;
  final int steps;

  /// The active row that is updated; null when the day gets a new row.
  final StepDayRow? existing;
}

final class _HealthPlan {
  const _HealthPlan(this.changes, this.result);

  final List<_HealthChange> changes;
  final HealthApplyResult result;
}
