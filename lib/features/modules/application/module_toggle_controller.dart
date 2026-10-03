import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/modules/application/module_providers.dart';

/// Result of asking to switch a module on or off.
@immutable
sealed class ModuleToggleResult {
  const ModuleToggleResult();
}

/// The new state is committed.
final class ModuleToggled extends ModuleToggleResult {
  const ModuleToggled();
}

/// The module cannot be switched off yet (an open focus session): the UI shows
/// the message and the resolution action instead. Nothing was changed.
final class ModuleToggleBlocked extends ModuleToggleResult {
  const ModuleToggleBlocked(this.module, this.check);

  final ModuleId module;
  final MustResolveFirst check;
}

/// Persisting failed; the toggle keeps its old state.
final class ModuleToggleFailed extends ModuleToggleResult {
  const ModuleToggleFailed(this.failure);

  final AppFailure failure;
}

/// A change of the same module is still running (the toggle is locked then).
final class ModuleToggleBusy extends ModuleToggleResult {
  const ModuleToggleBusy();
}

/// Switches modules on and off through `ModuleManager` and tells the UI which
/// modules are busy (their toggles are locked meanwhile).
///
/// Deactivation first asks the module (`canDeactivate`); the manager repeats
/// the open-session check inside the command, so a session that was started
/// in the meantime is still caught. Nothing is ever deleted.
class ModuleToggleController extends Notifier<Set<ModuleId>> {
  final Map<ModuleId, SubmissionTracker> _trackers =
      <ModuleId, SubmissionTracker>{};

  static const MustResolveFirst _focusLock = MustResolveFirst(
    message:
        'Es läuft noch eine Fokus-Sitzung. Speichere oder verwirf sie zuerst, '
        'damit keine Zeit verloren geht.',
    resolveLabel: 'Zur Sitzung',
  );

  @override
  Set<ModuleId> build() => const <ModuleId>{};

  /// Sets [module] to [enabled]. A retry with unchanged content reuses the
  /// command id of the failed attempt.
  Future<ModuleToggleResult> setEnabled(
    ModuleId module, {
    required bool enabled,
  }) async {
    if (state.contains(module)) {
      return const ModuleToggleBusy();
    }
    state = <ModuleId>{...state, module};
    try {
      if (!enabled) {
        final check = await _checkDeactivation(module);
        if (check != null) {
          return ModuleToggleBlocked(module, check);
        }
      }
      final tracker = _trackers.putIfAbsent(
        module,
        () => SubmissionTracker(ref.read(idGeneratorProvider)),
      );
      final commandId = tracker.idFor((module, enabled));
      await ref
          .read(moduleManagerProvider)
          .setEnabled(commandId: commandId, module: module, enabled: enabled);
      tracker.completed();
      return const ModuleToggled();
    } on ConflictFailure catch (failure) {
      return failure.kind == ConflictKind.openFocusSession
          ? ModuleToggleBlocked(module, _focusLock)
          : ModuleToggleFailed(failure);
    } on AppFailure catch (failure) {
      return ModuleToggleFailed(failure);
    } on Object catch (error) {
      return ModuleToggleFailed(
        StorageFailure(causeType: '${error.runtimeType}'),
      );
    } finally {
      if (ref.mounted) {
        state = <ModuleId>{...state}..remove(module);
      }
    }
  }

  /// Switches every module that is off back on (the all-off state's action).
  Future<List<ModuleToggleResult>> enableAll() async {
    final statuses = await ref.read(moduleStatusRepositoryProvider).statuses();
    final results = <ModuleToggleResult>[];
    for (final module in ModuleId.values) {
      if (statuses[module] ?? true) {
        continue;
      }
      results.add(await setEnabled(module, enabled: true));
    }
    return results;
  }

  Future<MustResolveFirst?> _checkDeactivation(ModuleId id) async {
    for (final module in ref.read(appModulesProvider)) {
      if (module.id == id) {
        final check = await module.canDeactivate(ref);
        return check is MustResolveFirst ? check : null;
      }
    }
    return null;
  }
}

final moduleToggleControllerProvider =
    NotifierProvider<ModuleToggleController, Set<ModuleId>>(
      ModuleToggleController.new,
    );
