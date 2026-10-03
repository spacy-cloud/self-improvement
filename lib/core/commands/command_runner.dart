import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/commands/command_context.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Whether a command created/changed facts or removed/reverted them.
enum EffectKind { committed, removed }

/// An inverse mutation that can be offered to the user for a short time.
///
/// Running it is a NEW command with its own id and a row version check, so it
/// never overwrites changes made after the original action.
@immutable
final class UndoAction {
  const UndoAction({required this.run});

  /// Executes the inverse command with [undoCommandId]. Throws
  /// [ConflictFailure] (`staleVersion`) if the record changed meanwhile.
  final Future<CommandOutcome> Function(String undoCommandId) run;
}

/// What a command body reports to the runner.
@immutable
final class CommandEffect {
  const CommandEffect({
    this.entityId,
    this.affectedDays = const {},
    this.undo,
    this.kind = EffectKind.committed,
    this.extraEvents = const [],
  });

  /// The record created or changed (stored in the receipt for replays).
  final String? entityId;

  /// Local dates whose projections (goal snapshots, XP) must be re-synced.
  /// For a record moved between days include the old AND the new date.
  final Set<LocalDate> affectedDays;

  /// Inverse action to offer after commit; null if none.
  final UndoAction? undo;

  final EffectKind kind;

  /// Additional events to publish after the commit.
  final List<AppEvent> extraEvents;
}

/// Result of a successfully committed or replayed command.
@immutable
final class CommandOutcome {
  const CommandOutcome({this.entityId, this.undo, this.replayed = false});

  final String? entityId;

  /// Null for replays: an already committed command offers no new undo.
  final UndoAction? undo;

  /// True if this command id had been committed before (nothing was done).
  final bool replayed;
}

/// A command body runs inside the transaction. All futures must be awaited.
typedef CommandBody = Future<CommandEffect> Function(CommandContext context);

/// Broadcasts [AppEvent]s after commits.
final class CommandEvents {
  final StreamController<AppEvent> _controller =
      StreamController<AppEvent>.broadcast();

  Stream<AppEvent> get stream => _controller.stream;

  void publish(AppEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  Future<void> dispose() => _controller.close();
}

/// Runs every mutation atomically and idempotently.
///
/// Inside ONE database transaction: check the receipt (replay -> no-op) ->
/// run the mutation -> sync projections for the affected days -> write the
/// receipt. Any error rolls everything back. UI events are published only
/// after the commit.
final class CommandRunner {
  CommandRunner({
    required this._database,
    required this._clock,
    required this._ids,
    required this._projections,
    required this._events,
    required this._gamificationEnabled,
  });

  final AppDatabase _database;
  final ClockService _clock;
  final IdGenerator _ids;
  final ProjectionSynchronizer _projections;
  final CommandEvents _events;
  final Future<bool> Function() _gamificationEnabled;

  /// Executes [body] as command [commandId] of kind [type].
  ///
  /// Retrying a failed submit MUST reuse the same [commandId]; a new user
  /// action uses a new id. Throws an [AppFailure]; unexpected errors become a
  /// [StorageFailure] (without their message, which may contain data).
  Future<CommandOutcome> run({
    required String commandId,
    required String type,
    required CommandBody body,
  }) async {
    final nowUtc = _clock.nowUtc();
    final context = CommandContext(
      clock: _clock,
      ids: _ids,
      nowUtc: nowUtc,
      gamificationEnabled: _gamificationEnabled,
    );

    final _Committed committed;
    try {
      committed = await _database.transaction(() async {
        final receipt = await (_database.select(
          _database.commandReceipts,
        )..where((r) => r.commandId.equals(commandId))).getSingleOrNull();
        if (receipt != null) {
          return _Committed.replay(
            CommandOutcome(entityId: receipt.resultEntityId, replayed: true),
          );
        }
        final xpBefore = await _projections.totalXp();
        final effect = await body(context);
        if (effect.affectedDays.isNotEmpty) {
          await _projections.syncDays(effect.affectedDays);
        }
        final xpAfter = await _projections.totalXp();
        await _database
            .into(_database.commandReceipts)
            .insert(
              CommandReceiptsCompanion.insert(
                commandId: commandId,
                commandType: type,
                resultEntityId: Value(effect.entityId),
                committedAtUtc: nowUtc,
              ),
            );
        return _Committed(
          CommandOutcome(entityId: effect.entityId, undo: effect.undo),
          effect,
          xpBefore,
          xpAfter,
          type,
        );
      });
    } on AppFailure {
      rethrow;
    } catch (error) {
      // Log only the type: messages of storage errors can contain values.
      debugPrint('command "$type" failed: ${error.runtimeType}');
      throw StorageFailure(causeType: error.runtimeType.toString());
    }

    final effect = committed.effect;
    if (effect != null) {
      _events.publish(
        effect.kind == EffectKind.removed
            ? ActivityRemoved(
                commandType: committed.type,
                entityId: effect.entityId,
                xpBefore: committed.xpBefore,
                xpAfter: committed.xpAfter,
              )
            : ActivityCommitted(
                commandType: committed.type,
                entityId: effect.entityId,
                xpBefore: committed.xpBefore,
                xpAfter: committed.xpAfter,
              ),
      );
      effect.extraEvents.forEach(_events.publish);
    }
    return committed.outcome;
  }
}

final class _Committed {
  const _Committed(
    this.outcome,
    this.effect,
    this.xpBefore,
    this.xpAfter,
    this.type,
  );

  const _Committed.replay(this.outcome)
    : effect = null,
      xpBefore = 0,
      xpAfter = 0,
      type = '';

  final CommandOutcome outcome;
  final CommandEffect? effect;
  final int xpBefore;
  final int xpAfter;
  final String type;
}
