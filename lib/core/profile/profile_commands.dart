import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';

/// Edits the local profile. Body values are voluntary profile data and are
/// never turned into weight measurements; the target weight takes effect
/// immediately (unlike the daily goals).
class ProfileCommands {
  ProfileCommands({required this._database, required this._runner});

  static const String updateType = 'profile.update';

  final AppDatabase _database;
  final CommandRunner _runner;

  /// Replaces the editable profile fields with [values] (the editor sends the
  /// complete desired state). Validation errors keep the form input.
  Future<CommandOutcome> update({
    required String commandId,
    String? displayName,
    int? heightCm,
    int? ageYears,
    int? startWeightGrams,
    int? targetWeightGrams,
    Iterable<String>? motivationGoals,
  }) {
    return _runner.run(
      commandId: commandId,
      type: updateType,
      body: (ctx) async {
        final row = await _database.select(_database.profile).getSingleOrNull();
        if (row == null) {
          throw const NotFoundFailure(entity: 'profile');
        }
        final values = validateProfileValues(
          displayName: displayName,
          heightCm: heightCm,
          ageYears: ageYears,
          startWeightGrams: startWeightGrams,
          targetWeightGrams: targetWeightGrams,
          motivationGoals: motivationGoals ?? row.motivationGoals,
        );
        await (_database.update(
          _database.profile,
        )..where((p) => p.id.equals('local'))).write(
          ProfileCompanion(
            displayName: Value(values.displayName),
            heightCm: Value(values.heightCm),
            ageYears: Value(values.ageYears),
            startWeightGrams: Value(values.startWeightGrams),
            targetWeightGrams: Value(values.targetWeightGrams),
            motivationGoals: Value(values.motivationGoals),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(row.rowVersion + 1),
          ),
        );
        return const CommandEffect(entityId: 'local');
      },
    );
  }
}
