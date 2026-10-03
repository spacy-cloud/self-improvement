import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/design/app_theme.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';

/// Outcome of a settings change.
sealed class SettingsResult {
  const SettingsResult();
}

/// The new value is committed. The app shell reacts through
/// `appSettingsProvider`, so the change is visible immediately.
final class SettingsSaved extends SettingsResult {
  const SettingsSaved();
}

/// The same setting is still being written; the tap is ignored.
final class SettingsBusy extends SettingsResult {
  const SettingsBusy();
}

/// Nothing was written; [failure] has the German message. The switch keeps its
/// old position because the screen shows the stored value.
final class SettingsFailed extends SettingsResult {
  const SettingsFailed(this.failure);

  final AppFailure failure;
}

/// Changes of the application settings (theme, reduced motion, haptics).
///
/// Every setting is its own command. A retry with the same value reuses the
/// command id ([SubmissionTracker]); a tap while the same setting is still
/// being written is ignored.
class SettingsActions {
  SettingsActions(this._ref);

  final Ref _ref;
  final Map<String, SubmissionTracker> _trackers = {};
  final Set<String> _running = {};

  /// Sets the theme: `system`, `light`, `dark` or `oled`.
  Future<SettingsResult> setThemeMode(AppThemeMode mode) {
    return _run(
      slot: 'theme',
      fingerprint: mode.key,
      write: (commandId) => _ref
          .read(settingsCommandsProvider)
          .setThemeMode(commandId: commandId, themeModeKey: mode.key),
    );
  }

  /// Sets the reduced motion switch (in addition to the system setting).
  Future<SettingsResult> setReduceMotion({required bool value}) {
    return _run(
      slot: 'motion',
      fingerprint: value,
      write: (commandId) => _ref
          .read(settingsCommandsProvider)
          .setReduceMotion(commandId: commandId, value: value),
    );
  }

  /// Sets the haptic feedback switch.
  Future<SettingsResult> setHaptics({required bool value}) {
    return _run(
      slot: 'haptics',
      fingerprint: value,
      write: (commandId) => _ref
          .read(settingsCommandsProvider)
          .setHaptics(commandId: commandId, value: value),
    );
  }

  Future<SettingsResult> _run({
    required String slot,
    required Object fingerprint,
    required Future<CommandOutcome> Function(String commandId) write,
  }) async {
    if (!_running.add(slot)) {
      return const SettingsBusy();
    }
    final tracker = _trackers.putIfAbsent(
      slot,
      () => SubmissionTracker(_ref.read(idGeneratorProvider)),
    );
    try {
      await write(tracker.idFor(fingerprint));
      tracker.completed();
      return const SettingsSaved();
    } on AppFailure catch (failure) {
      return SettingsFailed(failure);
    } finally {
      _running.remove(slot);
    }
  }
}

/// The settings commands of the settings screen.
final settingsActionsProvider = Provider<SettingsActions>(SettingsActions.new);
