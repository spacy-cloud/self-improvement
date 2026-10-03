import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_status_repository.dart';

/// Activates and deactivates modules.
///
/// Deactivation only hides screens and actions; no business data is ever
/// deleted. The status is an append-only history so past days keep their
/// state (see `ModuleStatusRepository`). A change of today also masks today's
/// goal snapshot through the projection hook.
class ModuleManager {
  ModuleManager({
    required this._database,
    required this._runner,
    required this._status,
  });

  static const String setEnabledType = 'module.set_enabled';

  final AppDatabase _database;
  final CommandRunner _runner;
  final ModuleStatusRepository _status;

  /// Whether a running, paused or unconfirmed focus session exists.
  Future<bool> hasOpenFocusSession() async {
    final open =
        await (_database.select(_database.focusSessions)..where(
              (f) =>
                  f.status.isIn(SchemaKeys.focusOpenStatuses) &
                  f.deletedAtUtc.isNull(),
            ))
            .get();
    return open.isNotEmpty;
  }

  /// Sets [module] to [enabled]. Idempotent: setting the current state is a
  /// no-op. Deactivating `focus` while a session is open is refused with a
  /// [ConflictFailure] (`openFocusSession`): the user must save or discard the
  /// session first.
  Future<CommandOutcome> setEnabled({
    required String commandId,
    required ModuleId module,
    required bool enabled,
  }) {
    return _runner.run(
      commandId: commandId,
      type: setEnabledType,
      body: (ctx) async {
        if (await _status.isEnabled(module) == enabled) {
          return const CommandEffect();
        }
        if (!enabled &&
            module == ModuleId.focus &&
            await hasOpenFocusSession()) {
          throw const ConflictFailure(ConflictKind.openFocusSession);
        }
        // Keep the history strictly ordered even if the device clock went back.
        final latest =
            await (_database.select(_database.moduleStatusHistory)
                  ..where((r) => r.moduleId.equals(module.key))
                  ..orderBy([(r) => OrderingTerm.desc(r.effectiveAtUtc)])
                  ..limit(1))
                .getSingleOrNull();
        final effectiveAt =
            latest != null && !latest.effectiveAtUtc.isBefore(ctx.nowUtc)
            ? latest.effectiveAtUtc.add(const Duration(milliseconds: 1))
            : ctx.nowUtc;
        await _database
            .into(_database.moduleStatusHistory)
            .insert(
              ModuleStatusHistoryCompanion.insert(
                id: ctx.ids.newId(),
                moduleId: module.key,
                effectiveAtUtc: effectiveAt,
                localDate: ctx.today,
                enabled: enabled,
              ),
            );
        return CommandEffect(
          entityId: module.key,
          affectedDays: {ctx.today},
          extraEvents: [ModulesChanged(module, enabled: enabled)],
        );
      },
    );
  }
}
