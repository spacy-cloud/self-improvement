import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';

/// Outcome of a delete request of a water entry or a meal.
sealed class EntryDeleteResult {
  const EntryDeleteResult();
}

/// Deleted. [outcome] carries the undo that restores the same id.
final class EntryDeleted extends EntryDeleteResult {
  const EntryDeleted(this.outcome);

  final CommandOutcome outcome;
}

/// Ignored: this entry is already being deleted (double tap).
final class EntryDeleteBusy extends EntryDeleteResult {
  const EntryDeleteBusy();
}

/// Not deleted (the database failed or the entry vanished); nothing changed.
final class EntryDeleteFailed extends EntryDeleteResult {
  const EntryDeleteFailed(this.failure);

  final AppFailure failure;
}

/// Deletes water entries and meals from lists and edit screens.
///
/// The user already confirmed. One command id is kept per entry until the
/// delete committed, so repeating a failed delete is the same command and can
/// never delete twice. While an entry is being deleted its id is in the
/// state, so the screens can disable that row's buttons and a double tap is
/// ignored.
class NutritionDeleteController extends Notifier<Set<String>> {
  final Map<String, String> _commandIds = {};

  @override
  Set<String> build() {
    _commandIds.clear();
    return const {};
  }

  /// Soft-deletes the water entry [id].
  Future<EntryDeleteResult> deleteWater(String id) => _run(
    id,
    (commandId) =>
        ref.read(waterRepositoryProvider).delete(commandId: commandId, id: id),
  );

  /// Soft-deletes the meal [id].
  Future<EntryDeleteResult> deleteMeal(String id) => _run(
    id,
    (commandId) =>
        ref.read(mealRepositoryProvider).delete(commandId: commandId, id: id),
  );

  Future<EntryDeleteResult> _run(
    String id,
    Future<CommandOutcome> Function(String commandId) run,
  ) async {
    if (state.contains(id)) {
      return const EntryDeleteBusy();
    }
    final commandId = _commandIds.putIfAbsent(
      id,
      () => ref.read(idGeneratorProvider).newId(),
    );
    state = {...state, id};
    try {
      final outcome = await run(commandId);
      _commandIds.remove(id);
      return EntryDeleted(outcome);
    } on AppFailure catch (failure) {
      return EntryDeleteFailed(failure);
    } finally {
      if (ref.mounted) {
        state = {...state}..remove(id);
      }
    }
  }
}

/// The delete controller. Lives with the app container.
final nutritionDeleteProvider =
    NotifierProvider<NutritionDeleteController, Set<String>>(
      NutritionDeleteController.new,
    );
