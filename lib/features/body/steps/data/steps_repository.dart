import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/goal_snapshot_service.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/features/body/steps/domain/step_day.dart';
import 'package:self_improvement/features/gamification/domain/steps_eligibility.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Manual daily step totals: one active value per local date.
///
/// Saving a date again REPLACES the value (never adds). The first time an
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

  /// Records [steps] as the total of [date], replacing an existing value.
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

        // The threshold of that day must exist before the decision is made.
        await _snapshots.ensureForDays([date]);
        final snapshot = await _snapshots.snapshotFor(date);
        final decision = decideStepsEligibility(
          newSteps: steps,
          applicableTarget: snapshot?.applicableTargetFor(GoalType.steps.key),
          gamificationEnabled: await ctx.isGamificationEnabled(),
          existingReachedGoalEligible: existing?.reachedGoalEligible,
          existingXpGoalTargetSteps: existing?.xpGoalTargetSteps,
        );

        if (existing == null) {
          final id = ctx.ids.newId();
          await _database
              .into(_database.stepDays)
              .insert(
                StepDaysCompanion.insert(
                  id: id,
                  localDate: date,
                  steps: steps,
                  timezoneId: ctx.timeZoneId,
                  reachedGoalEligible: Value(decision.reachedGoalEligible),
                  xpGoalTargetSteps: Value(decision.xpGoalTargetSteps),
                  createdAtUtc: ctx.nowUtc,
                  updatedAtUtc: ctx.nowUtc,
                ),
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
        await (_database.update(
          _database.stepDays,
        )..where((s) => s.id.equals(existing.id))).write(
          StepDaysCompanion(
            steps: Value(steps),
            reachedGoalEligible: Value(decision.reachedGoalEligible),
            xpGoalTargetSteps: Value(decision.xpGoalTargetSteps),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(newVersion),
          ),
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
  );
}
