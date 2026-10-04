import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';

/// Edits goal values and their on/off switches.
///
/// Changes take effect FROM TOMORROW (the UI says so explicitly); several
/// edits made today replace the same (type, tomorrow) version. Past and
/// today's snapshots keep their frozen thresholds. The body target weight is
/// a profile value and not edited here.
class GoalsCommands {
  GoalsCommands({required this._runner, required this._versions});

  static const String updateType = 'goals.update';

  final CommandRunner _runner;
  final GoalVersionRepository _versions;

  /// Applies [changes] (type -> new value) effective tomorrow. A null target
  /// keeps the default of the type. Unchanged values create no version.
  Future<CommandOutcome> update({
    required String commandId,
    required Map<GoalType, GoalSetting> changes,
  }) {
    return _runner.run(
      commandId: commandId,
      type: updateType,
      body: (ctx) async {
        final errors = <String, String>{};
        for (final entry in changes.entries) {
          final target = entry.value.target;
          if (target != null && !entry.key.validateTarget(target).isValid) {
            errors[entry.key.key] = 'Ungültiger Zielwert.';
          }
        }
        if (errors.isNotEmpty) {
          throw ValidationFailure(errors);
        }

        final effective = nextEffectiveDate(ctx.today);
        final existing = await _versions.all();
        var changed = false;
        for (final entry in changes.entries) {
          final type = entry.key;
          final proposed = GoalVersion(
            type: type,
            target: type.resolveTarget(entry.value.target),
            enabled: entry.value.enabled,
            effectiveFrom: effective,
          );
          final inEffect = effectiveGoalOrDefault(existing, type, effective);
          final hasRowForTomorrow = existing.any(
            (v) => v.type == type && v.effectiveFrom == effective,
          );
          if (!hasRowForTomorrow &&
              inEffect.target == proposed.target &&
              inEffect.enabled == proposed.enabled) {
            continue;
          }
          await _versions.upsert(
            proposed,
            newId: ctx.ids.newId(),
            nowUtc: ctx.nowUtc,
          );
          changed = true;
        }
        return CommandEffect(
          entityId: effective.toIso(),
          extraEvents: changed ? const [GoalsChanged()] : const [],
        );
      },
    );
  }
}
