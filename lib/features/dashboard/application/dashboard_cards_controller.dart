import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/dashboard/application/dashboard_providers.dart';
import 'package:self_improvement/features/dashboard/domain/card_configuration.dart';

/// State of the card configuration page. While a change is being saved
/// ([busy]) further changes are ignored, so two quick taps can never reorder
/// the cards twice.
@immutable
final class CardConfigurationState {
  const CardConfigurationState({this.busy = false});

  final bool busy;
}

/// Changes the visibility and the order of the dashboard cards.
///
/// Every change is one persisted command through `DashboardCardRepository`.
/// The Home screen and the configuration page read the same stored rows, so a
/// change is visible everywhere as soon as it is committed and survives an app
/// restart. All methods return the failure of an unsuccessful change (nothing
/// was changed then) and `null` on success; repeating the SAME change after a
/// failure reuses the command id, so a retry can never be applied twice.
class DashboardCardsController extends Notifier<CardConfigurationState> {
  late SubmissionTracker _tracker;

  @override
  CardConfigurationState build() {
    _tracker = SubmissionTracker(ref.read(idGeneratorProvider));
    return const CardConfigurationState();
  }

  /// Shows or hides the card [cardId].
  Future<AppFailure?> setVisible(String cardId, {required bool visible}) {
    return _run(
      fingerprint: ('visible', cardId, visible),
      action: (commandId) => ref
          .read(dashboardCardRepositoryProvider)
          .setVisible(commandId: commandId, cardId: cardId, visible: visible),
    );
  }

  /// Moves the card [cardId] one place up (`delta` -1) or down (+1) among the
  /// listed cards: the accessible alternative to dragging.
  Future<AppFailure?> moveBy(String cardId, int delta) {
    final shown = ref.read(configurableCardsProvider).value;
    if (shown == null) {
      return Future<AppFailure?>.value();
    }
    final from = shown.indexWhere((card) => card.cardId == cardId);
    return _moveShown(from, from + delta);
  }

  /// Handles a drag of the listed card at [oldIndex] to its final position
  /// [newIndex] (the semantics of `onReorderItem` of the reorderable lists:
  /// the index is already adjusted for the removed item).
  Future<AppFailure?> reorder(int oldIndex, int newIndex) {
    return _moveShown(oldIndex, newIndex);
  }

  Future<AppFailure?> _moveShown(int from, int to) {
    final shown = ref.read(configurableCardsProvider).value;
    final all = ref.read(dashboardCardsProvider).value;
    if (shown == null || all == null) {
      return Future<AppFailure?>.value();
    }
    final toIndex = fullListTargetIndex(
      all: all,
      shown: shown,
      fromShown: from,
      toShown: to,
    );
    if (toIndex == null) {
      return Future<AppFailure?>.value();
    }
    final cardId = shown[from].cardId;
    return _run(
      fingerprint: ('move', cardId, toIndex),
      action: (commandId) => ref
          .read(dashboardCardRepositoryProvider)
          .move(commandId: commandId, cardId: cardId, toIndex: toIndex),
    );
  }

  Future<AppFailure?> _run({
    required Object fingerprint,
    required Future<CommandOutcome> Function(String commandId) action,
  }) async {
    if (state.busy) {
      return null;
    }
    final commandId = _tracker.idFor(fingerprint);
    state = const CardConfigurationState(busy: true);
    try {
      await action(commandId);
      _tracker.completed();
      return null;
    } on AppFailure catch (failure) {
      return failure;
    } finally {
      if (ref.mounted) {
        state = const CardConfigurationState();
      }
    }
  }
}

/// Provider of the card configuration controller; disposed with its page.
final dashboardCardsControllerProvider =
    NotifierProvider.autoDispose<
      DashboardCardsController,
      CardConfigurationState
    >(DashboardCardsController.new);
