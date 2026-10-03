import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// What the user chose in the "Beenden" sheet.
enum FocusEndChoice {
  /// Save the time so far.
  save,

  /// Throw the session away.
  discard,
}

/// Content of the sheet that opens with "Beenden" while a session runs or is
/// paused: the time so far, an optional XP hint and the three ways out. Built
/// like `ConfirmationSheet`; "Weiter fokussieren" is the safe default (initial
/// focus) and the sheet's own close action.
class FocusEndSheet extends StatelessWidget {
  const FocusEndSheet({
    required this.message,
    required this.canSave,
    required this.onSave,
    required this.onDiscard,
    required this.onContinue,
    super.key,
    this.hint,
  });

  /// The time so far in words.
  final String message;

  /// An optional second line (XP hint or explanation).
  final String? hint;

  /// Whether the session is long enough to be saved (one second).
  final bool canSave;

  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Sitzung beenden?',
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
            children: [
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
                  'Sitzung beenden?',
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
              if (hint != null) ...[
                const SizedBox(height: 8),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.captionStrong.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (canSave) ...[
                PrimaryButton(label: 'Zeit speichern', onPressed: onSave),
                const SizedBox(height: 12),
              ],
              SecondaryButton(
                label: 'Verwerfen',
                danger: true,
                onPressed: onDiscard,
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Weiter fokussieren',
                onPressed: onContinue,
                autofocus: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows [FocusEndSheet] as a modal bottom sheet and returns the choice, or
/// null when the user continues (button, barrier tap, system back).
Future<FocusEndChoice?> showFocusEndSheet(
  BuildContext context, {
  required String message,
  required bool canSave,
  String? hint,
}) {
  final colors = context.tokens.colors;
  return showModalBottomSheet<FocusEndChoice>(
    context: context,
    sheetAnimationStyle: AppMotion.surfaceStyleOf(context),
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: colors.scrim,
    barrierLabel: 'Schließen',
    constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: FocusEndSheet(
        message: message,
        hint: hint,
        canSave: canSave,
        onSave: () => Navigator.of(sheetContext).pop(FocusEndChoice.save),
        onDiscard: () => Navigator.of(sheetContext).pop(FocusEndChoice.discard),
        onContinue: () => Navigator.of(sheetContext).pop(),
      ),
    ),
  );
}
