import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/components/secondary_button.dart';
import 'package:self_improvement/core/design/tokens/app_radii.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Content of a confirmation: handle, title, explanation, the confirming
/// action and "Abbrechen".
///
/// Safe by default: "Abbrechen" takes the initial focus and is the sheet's own
/// close action. The destructive variant draws the confirming action in the
/// error colour. Use [showConfirmationSheet] to present it as a modal sheet.
class ConfirmationSheet extends StatelessWidget {
  /// Creates the sheet content.
  const ConfirmationSheet({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    super.key,
    this.cancelLabel = 'Abbrechen',
    this.destructive = true,
  });

  /// Question, for example "Eintrag löschen?".
  final String title;

  /// Consequence and undo hint.
  final String message;

  /// Label of the confirming action, for example "Löschen".
  final String confirmLabel;

  /// Label of the cancelling action.
  final String cancelLabel;

  /// Whether the confirming action is destructive (error colour).
  final bool destructive;

  /// Called when the user confirms.
  final VoidCallback onConfirm;

  /// Called when the user cancels.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadii.sheetBorder,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: AppSizes.sheetHandleWidth,
                    height: AppSizes.sheetHandleHeight,
                    decoration: BoxDecoration(
                      color: colors.borderInput,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                container: true,
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.titleSection.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyRegular.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: confirmLabel,
                danger: destructive,
                onPressed: onConfirm,
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: cancelLabel,
                onPressed: onCancel,
                autofocus: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows [ConfirmationSheet] as a modal bottom sheet and returns `true` only
/// when the user confirmed. Cancelling, the system back gesture, tapping the
/// barrier and dragging the sheet away all return `false`.
///
/// The background is inactive while the sheet is open and the focus starts on
/// "Abbrechen".
Future<bool> showConfirmationSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Abbrechen',
  bool destructive = true,
}) async {
  final colors = context.tokens.colors;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: colors.scrim,
    barrierLabel: 'Schließen',
    constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
    builder: (sheetContext) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ConfirmationSheet(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          destructive: destructive,
          onConfirm: () => Navigator.of(sheetContext).pop(true),
          onCancel: () => Navigator.of(sheetContext).pop(false),
        ),
      );
    },
  );
  return result ?? false;
}
