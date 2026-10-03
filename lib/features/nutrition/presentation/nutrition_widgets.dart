import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Short neutral loading text (no spinner that could loop without need).
class NutritionLoading extends StatelessWidget {
  const NutritionLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          'Wird geladen …',
          style: AppTextStyles.bodyRegular.copyWith(
            color: context.tokens.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Error message directly at a field or form: icon and text on the error tint,
/// never colour alone. Announced when it appears.
class NutritionFieldError extends StatelessWidget {
  const NutritionFieldError({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorTint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(AppIcon.error.data, size: 14, color: colors.error),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: AppTextStyles.captionStrong.copyWith(
                    color: colors.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A whole number in display size with its unit, editable by typing (digits
/// only; the validation happens when saving through the domain parser). It sits
/// between the minus and plus buttons of a `QuantityStepper`. The text scale of
/// this one display value is capped at 130 % and the value shrinks to fit, so
/// it never overflows; everything else scales without limit.
class NumberDisplayField extends StatelessWidget {
  const NumberDisplayField({
    required this.controller,
    required this.focusNode,
    required this.semanticLabel,
    required this.unit,
    required this.hint,
    required this.hasError,
    required this.onChanged,
    required this.onSubmitted,
    this.maxDigits = 5,
    this.fieldKey,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Spoken label of the field, for example "Menge in Millilitern".
  final String semanticLabel;

  /// Unit after the number, for example "ml".
  final String unit;

  /// Placeholder while the field is empty.
  final String hint;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final int maxDigits;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final style = AppTextStyles.displayXl.copyWith(
      color: hasError ? colors.error : colors.textPrimary,
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            IntrinsicWidth(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 84),
                child: Semantics(
                  label: semanticLabel,
                  textField: true,
                  child: TextField(
                    key: fieldKey,
                    controller: controller,
                    focusNode: focusNode,
                    textAlign: TextAlign.center,
                    style: style,
                    cursorColor: colors.primaryButton,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(maxDigits),
                    ],
                    decoration: InputDecoration(
                      isCollapsed: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      hintText: hint,
                      hintStyle: style.copyWith(color: colors.textTertiary),
                    ),
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              unit,
              style: AppTextStyles.titleSection.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Announces a field error to screen readers when it appears (a live region
/// without visual size). The error itself is drawn by the field; screen readers
/// read it together with the field as well.
class FieldErrorAnnouncer extends StatelessWidget {
  const FieldErrorAnnouncer({required this.text, super.key});

  /// The error text, or null while the field is fine.
  final String? text;

  @override
  Widget build(BuildContext context) {
    final message = text;
    if (message == null || message.isEmpty) {
      return const SizedBox.shrink();
    }
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: const SizedBox.shrink(),
    );
  }
}

/// A save failed for a reason that is not a field (storage, entry gone): the
/// message sits inside the form so it is visible while a sheet covers the
/// snack bar; the input is kept and "Erneut versuchen" repeats the same
/// command.
class SubmitFailureNotice extends StatelessWidget {
  const SubmitFailureNotice({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NutritionFieldError(text: message),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Erneut versuchen',
            icon: AppIcon.retry.data,
            expand: false,
            onPressed: onRetry,
          ),
        ],
      ],
    );
  }
}

/// A floating form sheet (the style of the confirmation sheet): handle and title
/// with its own close button stay on top, the content scrolls and keeps clear
/// of the keyboard, the optional [action] stays pinned below so it is always
/// reachable.
class FormSheetFrame extends StatelessWidget {
  const FormSheetFrame({
    required this.title,
    required this.onClose,
    required this.child,
    this.action,
    super.key,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;

  /// The primary action (for example the save button), pinned below the
  /// scrolling content.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: title,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: AppRadii.sheetBorder,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Column(
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
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              container: true,
                              header: true,
                              child: Text(
                                title,
                                style: AppTextStyles.titleSection.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AppIconButton(
                            icon: AppIcon.close.data,
                            filled: true,
                            semanticLabel: 'Schließen',
                            onPressed: onClose,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: child,
                  ),
                ),
                if (action != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: action,
                  )
                else
                  const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [builder] as a modal form sheet. Dragging the sheet away is off: the
/// visible close button (and Android back) ask before input is discarded.
Future<T?> showFormSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final colors = context.tokens.colors;
  return showModalBottomSheet<T>(
    context: context,
    sheetAnimationStyle: AppMotion.surfaceStyleOf(context),
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: colors.scrim,
    barrierLabel: 'Schließen',
    constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
    builder: builder,
  );
}

/// Asks "Änderungen verwerfen?" and returns whether the user chose to discard.
Future<bool> confirmDiscard(BuildContext context) => showConfirmationSheet(
  context,
  title: 'Änderungen verwerfen?',
  message: 'Deine Eingaben sind noch nicht gespeichert.',
  confirmLabel: 'Verwerfen',
  cancelLabel: 'Weiter bearbeiten',
);

/// A date and a time picked by the user.
typedef PickedMoment = ({LocalDate date, LocalTime time});

/// Lets the user pick a date (not after [today]) and then a time, like the
/// weight form. Returns null when the date picker was cancelled; a cancelled
/// time picker keeps [time].
Future<PickedMoment?> pickMoment(
  BuildContext context, {
  required LocalDate date,
  required LocalTime time,
  required LocalDate today,
  required String dateHelp,
  required String timeHelp,
}) async {
  final pickedDate = await showDatePicker(
    context: context,
    initialDate: DateTime(date.year, date.month, date.day),
    firstDate: DateTime(2000),
    lastDate: DateTime(today.year, today.month, today.day),
    helpText: dateHelp,
  );
  if (pickedDate == null || !context.mounted) {
    return null;
  }
  final pickedTime = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: time.hour, minute: time.minute),
    helpText: timeHelp,
  );
  return (
    date: LocalDate.fromDateTime(pickedDate),
    time: pickedTime == null
        ? time
        : LocalTime(pickedTime.hour, pickedTime.minute),
  );
}

/// Wall clock time of a stored entry in the zone it was recorded in (`16:40`);
/// the frozen zone keeps old entries stable after a trip.
String entryTime(ClockService clock, DateTime occurredAtUtc, String zoneId) =>
    clock.toLocal(occurredAtUtc, timeZoneId: zoneId).time.toIso();
