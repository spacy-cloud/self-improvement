import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/presentation/weight_routes.dart';
import 'package:self_improvement/features/body/presentation/weight_widgets.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_controller.dart';
import 'package:self_improvement/features/body/steps/application/steps_form_controller.dart';
import 'package:self_improvement/features/body/steps/domain/step_day.dart';
import 'package:self_improvement/features/body/steps/presentation/health_steps_labels.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_labels.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_routes.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// "Schritte eintragen": the total of one day. Saving REPLACES a total that
/// already exists for that day (it is never added), and the form says so.
class StepsFormScreen extends ConsumerStatefulWidget {
  const StepsFormScreen({this.date, super.key});

  /// The date to open for (null: today).
  final LocalDate? date;

  @override
  ConsumerState<StepsFormScreen> createState() => _StepsFormScreenState();
}

class _StepsFormScreenState extends ConsumerState<StepsFormScreen> {
  late final TextEditingController _steps;
  final FocusNode _stepsFocus = FocusNode();

  StepsFormArgs get _args => StepsFormArgs(date: widget.date);

  StepsFormController get _controller =>
      ref.read(stepsFormProvider(_args).notifier);

  @override
  void initState() {
    super.initState();
    _steps = TextEditingController(
      text: ref.read(stepsFormProvider(_args)).stepsText,
    );
  }

  @override
  void dispose() {
    _steps.dispose();
    _stepsFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final feedback = ref.read(feedbackServiceProvider);
    final router = GoRouter.of(context);
    final result = await _controller.submit();
    switch (result) {
      case StepsSaved():
        feedback.showSaved(result.message, undo: result.outcome.undo);
        if (router.canPop()) {
          router.pop();
        } else {
          router.go('/');
        }
      case StepsRejected():
        if (!mounted) {
          return;
        }
        final rejected = ref.read(stepsFormProvider(_args));
        // The invalid field takes the focus, so a screen reader reads its
        // label together with the hint.
        if (rejected.fieldErrors.containsKey(StepsFields.steps)) {
          _stepsFocus.requestFocus();
        }
        final failure = rejected.submitFailure;
        if (failure != null) {
          feedback.showError(
            'Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.',
            onRetry: _submit,
          );
        }
    }
  }

  Future<void> _confirmDelete() async {
    final state = ref.read(stepsFormProvider(_args));
    final today = ref.read(todayProvider);
    final feedback = ref.read(feedbackServiceProvider);
    final router = GoRouter.of(context);
    final confirmed = await showConfirmationSheet(
      context,
      title: 'Tageswert löschen?',
      message:
          '${stepsText(state.existingSteps ?? 0)} Schritte für '
          '${stepsDateInSentence(state.date, today)} werden entfernt. Du '
          'kannst es direkt danach rückgängig machen.'
          '${ref.read(healthStepsStatusProvider).enabled ? healthDeleteRefillText : ''}',
      confirmLabel: 'Löschen',
    );
    if (!confirmed || !mounted) {
      return;
    }
    final result = await _controller.deleteExisting();
    switch (result) {
      case StepsDeleted():
        feedback.showSaved(result.message, undo: result.outcome.undo);
        if (router.canPop()) {
          router.pop();
        } else {
          router.go(StepsRoutes.overview);
        }
      case StepsDeleteFailed():
        feedback.showError(
          'Löschen fehlgeschlagen. Der Tageswert ist unverändert.',
        );
      case StepsDeleteBusy():
        break;
    }
  }

  Future<void> _pickDate() async {
    final state = ref.read(stepsFormProvider(_args));
    final today = ref.read(todayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(state.date.year, state.date.month, state.date.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year, today.month, today.day),
      helpText: 'Datum der Schritte',
    );
    if (picked == null || !mounted) {
      return;
    }
    _controller.setDate(LocalDate.fromDateTime(picked));
  }

  Future<void> _askToDiscard() async {
    final discard = await showConfirmationSheet(
      context,
      title: 'Änderungen verwerfen?',
      message: 'Deine Eingaben sind noch nicht gespeichert.',
      confirmLabel: 'Verwerfen',
      cancelLabel: 'Weiter bearbeiten',
    );
    if (discard && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stepsFormProvider(_args));
    ref.listen(stepsFormProvider(_args).select((s) => s.stepsText), (
      previous,
      next,
    ) {
      if (_steps.text != next) {
        _steps.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });
    final today = ref.watch(todayProvider);
    // Keeps the state of the Health comparison alive, so the delete
    // confirmation knows whether Health would fill the day again.
    ref.watch(healthStepsStatusProvider.select((status) => status.enabled));
    final stepsError = state.fieldErrors[StepsFields.steps];
    final dateError = state.fieldErrors[StepsFields.date];
    final canSubmit = !state.submitting && state.stepsText.trim().isNotEmpty;

    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_askToDiscard());
        }
      },
      child: AppScaffold.subpage(
        title: 'Schritte eintragen',
        onBack: () => backOrHome(context),
        primaryAction: PrimaryButton(
          label: state.replacesExisting
              ? 'Tageswert ersetzen'
              : 'Schritte speichern',
          onPressed: canSubmit ? _submit : null,
          loading: state.submitting,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'Datum',
                style: AppTextStyles.bodyStrong.copyWith(
                  color: context.tokens.colors.textPrimary,
                ),
              ),
            ),
            _DateSelector(
              date: state.date,
              today: today,
              onPrevious: () => _controller.setDate(state.date.addDays(-1)),
              onNext: state.date.isBefore(today)
                  ? () => _controller.setDate(state.date.addDays(1))
                  : null,
              onPick: _pickDate,
            ),
            if (dateError != null) ...[
              const SizedBox(height: 8),
              FieldErrorMessage(text: dateError),
            ],
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                children: [
                  Text(
                    'Schritte gesamt',
                    style: AppTextStyles.bodyStrong.copyWith(
                      color: context.tokens.colors.textPrimary,
                    ),
                  ),
                  Text(
                    '0 – 100.000',
                    style: AppTextStyles.captionDefault.copyWith(
                      color: context.tokens.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            _StepsField(
              controller: _steps,
              focusNode: _stepsFocus,
              hint: state.existingSteps == null
                  ? '0'
                  : stepsText(state.existingSteps!),
              hasError: stepsError != null,
              onChanged: _controller.setStepsText,
              onSubmitted: (_) {
                if (canSubmit) {
                  unawaited(_submit());
                }
              },
            ),
            if (stepsError != null) ...[
              const SizedBox(height: 8),
              FieldErrorMessage(text: stepsError),
            ],
            if (state.replacesExisting) ...[
              const SizedBox(height: 12),
              _ReplaceNotice(
                existing: state.existingSteps!,
                date: state.date,
                today: today,
                fromHealth: state.replacesHealth,
              ),
            ],
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Tipp: Trag abends die Gesamtzahl aus deinem Schrittzähler '
                'oder deiner Uhr ein.',
                style: AppTextStyles.bodyRegular.copyWith(
                  color: context.tokens.colors.textSecondary,
                ),
              ),
            ),
            if (state.replacesExisting) ...[
              const SizedBox(height: 16),
              Center(
                child: SecondaryButton(
                  label: 'Tageswert löschen',
                  icon: AppIcon.delete.data,
                  danger: true,
                  expand: false,
                  onPressed: state.submitting ? null : _confirmDelete,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The date with a day back and a day forward button; tapping the date opens
/// the date picker. The future is not reachable.
class _DateSelector extends StatelessWidget {
  const _DateSelector({
    required this.date,
    required this.today,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });

  final LocalDate date;
  final LocalDate today;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final heading = stepsDateHeading(date, today);
    return AppCard(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          AppIconButton(
            icon: AppIcon.back.data,
            semanticLabel: 'Einen Tag zurück',
            filled: true,
            onPressed: onPrevious,
          ),
          Expanded(
            child: Semantics(
              container: true,
              button: true,
              label: 'Datum: $heading. Tippen zum Ändern',
              onTap: onPick,
              excludeSemantics: true,
              child: InkWell(
                onTap: onPick,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Text(
                        heading,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyStrong.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AppIconButton(
            icon: AppIcon.chevronRight.data,
            semanticLabel: 'Einen Tag weiter',
            filled: true,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

/// The typed total in display size, grouped with dots while typing.
class _StepsField extends StatelessWidget {
  const _StepsField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.hasError,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final style = AppTextStyles.displayL.copyWith(
      color: hasError ? colors.error : colors.textPrimary,
    );
    return AppCard(
      borderColor: hasError ? colors.error : colors.borderInput,
      borderWidth: 2,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Semantics(
          label: 'Schritte gesamt',
          textField: true,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            style: style,
            cursorColor: colors.primaryButton,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [_ThousandsInputFormatter()],
            decoration: bareInputDecoration(
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              hintText: hint,
              hintStyle: style.copyWith(color: colors.textTertiary),
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            onTapOutside: dismissKeyboardOnTapOutside,
          ),
        ),
      ),
    );
  }
}

/// Keeps digits only (at most six) and groups them with dots: `8120` becomes
/// `8.120`.
class _ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue();
    }
    final limited = digits.length > 6 ? digits.substring(0, 6) : digits;
    final text = formatThousands(int.parse(limited));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Tells before saving that the total of that day is replaced, not added.
class _ReplaceNotice extends StatelessWidget {
  const _ReplaceNotice({
    required this.existing,
    required this.date,
    required this.today,
    required this.fromHealth,
  });

  final int existing;
  final LocalDate date;
  final LocalDate today;

  /// The stored value came from Health: saving makes the day a value typed in
  /// and Health leaves it alone from then on.
  final bool fromHealth;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final title = fromHealth
        ? healthDayNoticeTitle(
            existing: stepsText(existing),
            when: stepsDateInSentence(date, today),
          )
        : 'Für ${stepsDateInSentence(date, today)} sind schon '
              '${stepsText(existing)} eingetragen';
    final body = fromHealth
        ? healthDayNoticeText
        : 'Beim Speichern wird der Tageswert ersetzt, nicht addiert.';
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $body',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.warningTint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.warningText.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcon.error.data, size: 20, color: colors.warningText),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.captionStrong.copyWith(
                        color: colors.warningText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: AppTextStyles.captionDefault.copyWith(
                        color: colors.warningText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
