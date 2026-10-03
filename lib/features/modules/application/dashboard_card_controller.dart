import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';

/// Changes order and visibility of the dashboard cards (button alternative to
/// dragging). The state tells whether a change is running; the UI disables the
/// controls meanwhile so two changes never overlap.
class DashboardCardController extends Notifier<bool> {
  SubmissionTracker? _tracker;

  @override
  bool build() => false;

  /// Moves card [cardId] by [delta] positions (`-1` up, `1` down). Returns the
  /// failure, or `null` when committed.
  Future<AppFailure?> moveBy(String cardId, int delta) {
    return _run(
      ('move', cardId, delta),
      (commandId) => ref
          .read(dashboardCardRepositoryProvider)
          .moveBy(commandId: commandId, cardId: cardId, delta: delta),
    );
  }

  /// Shows or hides card [cardId].
  Future<AppFailure?> setVisible(String cardId, {required bool visible}) {
    return _run(
      ('visible', cardId, visible),
      (commandId) => ref
          .read(dashboardCardRepositoryProvider)
          .setVisible(commandId: commandId, cardId: cardId, visible: visible),
    );
  }

  /// Shows every card in [cardIds] again (the "no cards" state's action).
  Future<AppFailure?> showAll(Iterable<String> cardIds) async {
    for (final cardId in cardIds) {
      final failure = await setVisible(cardId, visible: true);
      if (failure != null) {
        return failure;
      }
    }
    return null;
  }

  Future<AppFailure?> _run(
    Object fingerprint,
    Future<Object?> Function(String commandId) body,
  ) async {
    if (state) {
      return null;
    }
    state = true;
    final tracker = _tracker ??= SubmissionTracker(
      ref.read(idGeneratorProvider),
    );
    try {
      await body(tracker.idFor(fingerprint));
      tracker.completed();
      return null;
    } on AppFailure catch (failure) {
      return failure;
    } on Object catch (error) {
      return StorageFailure(causeType: '${error.runtimeType}');
    } finally {
      if (ref.mounted) {
        state = false;
      }
    }
  }
}

final dashboardCardControllerProvider =
    NotifierProvider<DashboardCardController, bool>(
      DashboardCardController.new,
    );
