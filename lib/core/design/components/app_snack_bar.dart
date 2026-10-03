import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/tokens/app_radii.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_spacing.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Variants of the snack bar (Figma: Undo, Success, Error).
enum AppSnackBarType {
  /// A change that can be undone (action "Rückgängig").
  undo,

  /// Plain confirmation without action.
  success,

  /// Error with a retry action; the input stays untouched.
  error,
}

/// How long snack bars stay visible.
abstract final class AppSnackBarDurations {
  /// Undo window: 8 seconds (the Figma note says 5 s; the task rule wins).
  static const Duration undo = Duration(seconds: 8);

  /// Success messages.
  static const Duration success = Duration(seconds: 4);
}

/// Visual of a snack bar: message plus optional action, 56 high or more,
/// radius 14. Dark surface for undo and success, dark red for errors (the same
/// in all themes).
///
/// Use [showUndoSnackBar], [showSuccessSnackBar] and [showErrorSnackBar] to
/// show it; they wrap it in a Material snack bar that announces the message as
/// a live region to screen readers.
class UndoSnackBar extends StatelessWidget {
  /// Creates a snack bar visual of [type].
  const UndoSnackBar({
    required this.type,
    required this.message,
    super.key,
    this.actionLabel,
    this.onAction,
  });

  /// Undo variant with the action "Rückgängig".
  const UndoSnackBar.undo({
    required this.message,
    required this.onAction,
    super.key,
    this.actionLabel = 'Rückgängig',
  }) : type = AppSnackBarType.undo;

  /// Success variant without action.
  const UndoSnackBar.success({required this.message, super.key})
    : type = AppSnackBarType.success,
      actionLabel = null,
      onAction = null;

  /// Error variant; shows "Erneut" when [onAction] is set.
  const UndoSnackBar.error({
    required this.message,
    super.key,
    this.onAction,
    this.actionLabel = 'Erneut',
  }) : type = AppSnackBarType.error;

  /// Variant.
  final AppSnackBarType type;

  /// Message text (wraps on large text).
  final String message;

  /// Action text.
  final String? actionLabel;

  /// Action callback; without it no action is shown.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final isError = type == AppSnackBarType.error;
    final hasAction = onAction != null && actionLabel != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppSizes.snackBarMinHeight,
        maxWidth: AppSizes.contentMaxWidth,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isError ? colors.snackBarErrorSurface : colors.snackBarSurface,
          borderRadius: AppRadii.controlBorder,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.s16,
            6,
            hasAction ? AppSpacing.s8 : AppSpacing.s16,
            6,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    message,
                    style: AppTextStyles.bodyDefault.copyWith(
                      color: colors.onSnackBar,
                    ),
                  ),
                ),
              ),
              if (hasAction) ...<Widget>[
                const SizedBox(width: AppSpacing.s8),
                Semantics(
                  container: true,
                  button: true,
                  label: actionLabel,
                  onTap: onAction,
                  excludeSemantics: true,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSizes.touchMin,
                      minWidth: AppSizes.touchMin,
                    ),
                    child: InkSurface(
                      onTap: onAction,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadii.controlBorder,
                      ),
                      child: Center(
                        widthFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            actionLabel!,
                            style: AppTextStyles.bodyStrong.copyWith(
                              color: isError
                                  ? colors.snackBarErrorAction
                                  : colors.snackBarAction,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _show(
  BuildContext context, {
  required UndoSnackBar Function(VoidCallback close) builder,
  required Duration duration,
  required bool persist,
  required double bottomOffset,
}) {
  final messenger = ScaffoldMessenger.of(context);
  void close() =>
      messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.action);
  return (messenger..removeCurrentSnackBar()).showSnackBar(
    SnackBar(
      content: builder(close),
      duration: duration,
      persist: persist,
      padding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        0,
        AppSpacing.s16,
        AppSpacing.s16 + bottomOffset,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.controlBorder),
    ),
  );
}

/// Shows the undo snack bar: [message] plus the action [actionLabel], visible
/// for [duration] (8 seconds by default). Tapping the action hides the bar and
/// calls [onUndo]. Replaces a snack bar that is still visible.
///
/// The bar floats 16 px above the bottom of the scaffold. [bottomOffset] lifts
/// it further, for example by `AppSizes.pinnedActionArea` above a pinned
/// primary action (the Figma frame places it 18 px above the button).
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showUndoSnackBar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
  String actionLabel = 'Rückgängig',
  Duration duration = AppSnackBarDurations.undo,
  double bottomOffset = 0,
}) {
  return _show(
    context,
    duration: duration,
    persist: false,
    bottomOffset: bottomOffset,
    builder: (close) => UndoSnackBar.undo(
      message: message,
      actionLabel: actionLabel,
      onAction: () {
        close();
        onUndo();
      },
    ),
  );
}

/// Shows a success message without action for [duration] (4 seconds); see
/// [showUndoSnackBar] for [bottomOffset].
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSuccessSnackBar(
  BuildContext context, {
  required String message,
  Duration duration = AppSnackBarDurations.success,
  double bottomOffset = 0,
}) {
  return _show(
    context,
    duration: duration,
    persist: false,
    bottomOffset: bottomOffset,
    builder: (_) => UndoSnackBar.success(message: message),
  );
}

/// Shows an error message. With [onRetry] the bar offers "Erneut" and stays
/// until the user retries or dismisses it (an error must not vanish on its
/// own); without it the bar disappears after [duration]. See
/// [showUndoSnackBar] for [bottomOffset].
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showErrorSnackBar(
  BuildContext context, {
  required String message,
  VoidCallback? onRetry,
  String retryLabel = 'Erneut',
  Duration duration = const Duration(seconds: 6),
  double bottomOffset = 0,
}) {
  return _show(
    context,
    duration: duration,
    persist: onRetry != null,
    bottomOffset: bottomOffset,
    builder: (close) => UndoSnackBar.error(
      message: message,
      actionLabel: retryLabel,
      onAction: onRetry == null
          ? null
          : () {
              close();
              onRetry();
            },
    ),
  );
}
