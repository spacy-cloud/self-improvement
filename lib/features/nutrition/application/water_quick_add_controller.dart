import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';

/// State of the quick add: only the latest unresolved failure.
@immutable
final class WaterQuickAddState {
  const WaterQuickAddState({this.failure, this.retryAmountMl});

  /// The failure of the latest quick add, null while everything works. A
  /// later successful add (or [WaterQuickAddController.dismissFailure])
  /// clears it.
  final AppFailure? failure;

  /// The amount [WaterQuickAddController.retry] would add again; set only for
  /// failures where a retry can succeed (storage failures).
  final int? retryAmountMl;

  bool get canRetry => retryAmountMl != null;
}

/// One-tap water entries (250 / 500 ml) for the dashboard card and the water
/// screen.
///
/// Every [add] is ONE command with a NEW command id: two quick taps are two
/// entries, also when they run at the same time. Taps are never dropped or
/// debounced. After a storage failure nothing is stored (no amount, no XP) and
/// [retry] repeats the failed tap with the SAME id, so a retry can never
/// create a second entry for one tap.
class WaterQuickAddController extends Notifier<WaterQuickAddState> {
  ({String commandId, int amountMl})? _failed;

  @override
  WaterQuickAddState build() {
    _failed = null;
    return const WaterQuickAddState();
  }

  /// Adds [amountMl] (50 to 2000; the buttons use `waterQuickAmountsMl`) at
  /// the current time. The returned outcome carries the undo for the snackbar.
  ///
  /// Throws the [AppFailure] of the failed command: [StorageFailure] (nothing
  /// was saved, [retry] is possible) or [ValidationFailure] for an amount
  /// outside 50 to 2000 ml. The failure is also published in the state.
  Future<CommandOutcome> add(int amountMl) =>
      _run(ref.read(idGeneratorProvider).newId(), amountMl);

  /// Repeats the failed quick add with its original command id. Returns null
  /// when there is nothing to retry. Throws like [add].
  Future<CommandOutcome?> retry() async {
    final failed = _failed;
    if (failed == null) {
      return null;
    }
    return _run(failed.commandId, failed.amountMl);
  }

  /// Forgets the failure (the user dismissed the message).
  void dismissFailure() {
    _failed = null;
    state = const WaterQuickAddState();
  }

  Future<CommandOutcome> _run(String commandId, int amountMl) async {
    final repository = ref.read(waterRepositoryProvider);
    try {
      final outcome = await repository.quickAdd(
        commandId: commandId,
        amountMl: amountMl,
      );
      _failed = null;
      if (state.failure != null) {
        state = const WaterQuickAddState();
      }
      return outcome;
    } on AppFailure catch (failure) {
      if (failure is StorageFailure) {
        _failed = (commandId: commandId, amountMl: amountMl);
        state = WaterQuickAddState(failure: failure, retryAmountMl: amountMl);
      } else {
        _failed = null;
        state = WaterQuickAddState(failure: failure);
      }
      rethrow;
    }
  }
}

/// The quick add controller. Lives with the app container so a failure stays
/// visible across the dashboard and the water screen.
final waterQuickAddProvider =
    NotifierProvider<WaterQuickAddController, WaterQuickAddState>(
      WaterQuickAddController.new,
    );
