import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/goals/data/goals_commands.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/profile/profile_commands.dart';
import 'package:self_improvement/core/settings/settings_commands.dart';

/// Records the command ids a form sends and can be told to fail, so tests can
/// check "a retry with the same content reuses the command id".
mixin CommandRecording {
  /// Every command id in the order it was sent.
  final List<String> commandIds = [];

  /// When set, the next commands throw it before anything is written.
  Object? failure;

  void record(String commandId) {
    commandIds.add(commandId);
    final error = failure;
    if (error != null) {
      throw error;
    }
  }
}

class RecordingProfileCommands extends ProfileCommands with CommandRecording {
  RecordingProfileCommands({required super.database, required super.runner});

  @override
  Future<CommandOutcome> update({
    required String commandId,
    String? displayName,
    int? heightCm,
    int? ageYears,
    int? startWeightGrams,
    int? targetWeightGrams,
    Iterable<String>? motivationGoals,
  }) async {
    record(commandId);
    return super.update(
      commandId: commandId,
      displayName: displayName,
      heightCm: heightCm,
      ageYears: ageYears,
      startWeightGrams: startWeightGrams,
      targetWeightGrams: targetWeightGrams,
      motivationGoals: motivationGoals,
    );
  }
}

class RecordingGoalsCommands extends GoalsCommands with CommandRecording {
  RecordingGoalsCommands({required super.runner, required super.versions});

  @override
  Future<CommandOutcome> update({
    required String commandId,
    required Map<GoalType, GoalSetting> changes,
  }) async {
    record(commandId);
    return super.update(commandId: commandId, changes: changes);
  }
}

class RecordingSettingsCommands extends SettingsCommands with CommandRecording {
  RecordingSettingsCommands({required super.database, required super.runner});

  @override
  Future<CommandOutcome> setThemeMode({
    required String commandId,
    required String themeModeKey,
  }) async {
    record(commandId);
    return super.setThemeMode(commandId: commandId, themeModeKey: themeModeKey);
  }

  @override
  Future<CommandOutcome> setReduceMotion({
    required String commandId,
    required bool value,
  }) async {
    record(commandId);
    return super.setReduceMotion(commandId: commandId, value: value);
  }

  @override
  Future<CommandOutcome> setHaptics({
    required String commandId,
    required bool value,
  }) async {
    record(commandId);
    return super.setHaptics(commandId: commandId, value: value);
  }
}
