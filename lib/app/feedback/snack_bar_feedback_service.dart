import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';

/// The snack bar implementation of [FeedbackService] (the interface says it
/// lives in the app shell): success with an optional "Rückgängig" (8 seconds),
/// errors with an optional retry, neutral information. A new message replaces
/// the visible one, so at most one undo is ever offered.
///
/// A message is presented one microtask later: callers show the message and
/// leave their screen in the same breath, and the bar must float above the
/// screen that is visible afterwards (see [bottomOffset]).
class SnackBarFeedbackService implements FeedbackService {
  SnackBarFeedbackService({
    required this.context,
    required this.ids,
    this.bottomOffset = _noOffset,
  });

  /// A context below the `ScaffoldMessenger` (the root navigator's).
  final BuildContext? Function() context;

  /// Ids of undo commands.
  final IdGenerator ids;

  /// How far above the bottom edge the bar floats: zero above the navigation
  /// bar, [AppSizes.pinnedActionArea] above a pinned primary action.
  final double Function() bottomOffset;

  static double _noOffset() => 0;

  void _present(void Function(BuildContext context, double offset) show) {
    scheduleMicrotask(() {
      final target = context();
      if (target != null && target.mounted) {
        show(target, bottomOffset());
      }
    });
  }

  @override
  void showSaved(String message, {UndoAction? undo}) {
    if (undo == null) {
      _present(
        (context, offset) => showSuccessSnackBar(
          context,
          message: message,
          bottomOffset: offset,
        ),
      );
      return;
    }
    final presentation = UndoPresentation(action: undo, ids: ids);
    _present(
      (context, offset) => showUndoSnackBar(
        context,
        message: message,
        bottomOffset: offset,
        onUndo: () => unawaited(_undo(presentation)),
      ),
    );
  }

  Future<void> _undo(UndoPresentation presentation) async {
    final result = await presentation.perform();
    switch (result) {
      case UndoResult.undone:
        showInfo('Rückgängig gemacht.');
      case UndoResult.conflict:
      case UndoResult.failed:
        showError(
          presentation.failureMessage ?? 'Rückgängig machen war nicht möglich.',
        );
    }
  }

  @override
  void showError(
    String message, {
    VoidCallback? onRetry,
    String retryLabel = 'Erneut',
  }) {
    _present(
      (context, offset) => showErrorSnackBar(
        context,
        message: message,
        onRetry: onRetry,
        retryLabel: retryLabel,
        bottomOffset: offset,
      ),
    );
  }

  @override
  void showInfo(String message) {
    _present(
      (context, offset) =>
          showSuccessSnackBar(context, message: message, bottomOffset: offset),
    );
  }
}
