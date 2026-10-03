import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/body/application/weight_form_controller.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_calculations.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/domain/weight_input.dart';
import 'package:self_improvement/features/body/domain/weight_validation.dart';
import 'package:self_improvement/features/body/presentation/weight_routes.dart';
import 'package:self_improvement/features/body/presentation/weight_widgets.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';
import 'package:self_improvement/shared/number_format.dart';

/// "Gewicht eintragen" (new) and "Eintrag bearbeiten" (with [entryId]).
class WeightFormScreen extends ConsumerWidget {
  const WeightFormScreen({this.entryId, super.key});

  /// The measurement to edit, or null for a new one.
  final String? entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = entryId;
    if (id == null) {
      return const _WeightForm(
        key: ValueKey('weight-create'),
        args: WeightFormArgs.create(),
      );
    }
    return _EditLoader(entryId: id);
  }
}

/// Loads the measurement once; later changes of its row (for example by an
/// undo elsewhere) never reset a form that is open.
class _EditLoader extends ConsumerStatefulWidget {
  const _EditLoader({required this.entryId});

  final String entryId;

  @override
  ConsumerState<_EditLoader> createState() => _EditLoaderState();
}

class _EditLoaderState extends ConsumerState<_EditLoader> {
  WeightEntry? _opened;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(weightEntryProvider(widget.entryId));
    _opened ??= async.value;
    final opened = _opened;
    if (opened != null) {
      return _WeightForm(
        key: ValueKey('weight-edit-${opened.id}'),
        args: WeightFormArgs.edit(opened),
      );
    }
    return AppScaffold.subpage(
      title: 'Eintrag bearbeiten',
      onBack: () => backOrHome(context),
      body: async.when(
        loading: () => const SizedBox(height: 120),
        error: (error, stack) => ErrorState(
          onRetry: () => ref.invalidate(weightEntryProvider(widget.entryId)),
        ),
        data: (entry) => EmptyState(
          title: 'Eintrag nicht gefunden',
          message: 'Diese Messung gibt es nicht mehr.',
          actionLabel: 'Zur Übersicht',
          onAction: () => context.go(WeightRoutes.overview),
        ),
      ),
    );
  }
}

class _WeightForm extends ConsumerStatefulWidget {
  const _WeightForm({required this.args, super.key});

  final WeightFormArgs args;

  @override
  ConsumerState<_WeightForm> createState() => _WeightFormState();
}

class _WeightFormState extends ConsumerState<_WeightForm> {
  late final TextEditingController _weight;
  late final TextEditingController _note;
  final FocusNode _weightFocus = FocusNode();
  final FocusNode _noteFocus = FocusNode();

  WeightFormArgs get _args => widget.args;
  bool get _isEdit => _args.entry != null;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(weightFormProvider(_args));
    _weight = TextEditingController(text: initial.weightText);
    _note = TextEditingController(text: initial.note);
  }

  @override
  void dispose() {
    _weight.dispose();
    _note.dispose();
    _weightFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  WeightFormController get _controller =>
      ref.read(weightFormProvider(_args).notifier);

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final feedback = ref.read(feedbackServiceProvider);
    final router = GoRouter.of(context);
    final result = await _controller.submit();
    switch (result) {
      case WeightSaved():
        feedback.showSaved(result.message, undo: result.outcome.undo);
        if (router.canPop()) {
          router.pop();
        } else {
          router.go('/');
        }
      case WeightRejected():
        if (!mounted) {
          return;
        }
        final rejected = ref.read(weightFormProvider(_args));
        // The first invalid field takes the focus, so a screen reader reads
        // its label together with the hint.
        if (rejected.fieldErrors.containsKey(WeightFields.weight)) {
          _weightFocus.requestFocus();
        } else if (rejected.fieldErrors.containsKey(WeightFields.note)) {
          _noteFocus.requestFocus();
        }
        final failure = rejected.submitFailure;
        if (failure == null) {
          return;
        }
        if (failure is ConflictFailure &&
            failure.kind == ConflictKind.duplicateMeasurement) {
          return; // The form shows the offer to edit the existing entry.
        }
        if (failure is ConflictFailure) {
          feedback.showError(failure.userMessage);
        } else {
          feedback.showError(
            'Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.',
            onRetry: _submit,
          );
        }
    }
  }

  Future<void> _confirmDelete() async {
    final entry = _args.entry!;
    final feedback = ref.read(feedbackServiceProvider);
    final router = GoRouter.of(context);
    final confirmed = await showConfirmationSheet(
      context,
      title: 'Messung vom ${formatDayMonth(entry.localDate)} löschen?',
      message:
          '${formatKilograms(entry.weightGrams)} kg wird entfernt. '
          'Du kannst es direkt danach rückgängig machen.',
      confirmLabel: 'Löschen',
    );
    if (!confirmed || !mounted) {
      return;
    }
    final result = await _controller.deleteEntry();
    switch (result) {
      case WeightDeleted():
        feedback.showSaved(result.message, undo: result.outcome.undo);
        if (router.canPop()) {
          router.pop();
        } else {
          router.go(WeightRoutes.overview);
        }
      case WeightDeleteFailed(:final failure):
        feedback.showError(
          failure is StorageFailure
              ? 'Löschen fehlgeschlagen. Der Eintrag ist unverändert.'
              : failure.userMessage,
        );
      case WeightDeleteBusy():
        break;
    }
  }

  Future<void> _pickMoment() async {
    final state = ref.read(weightFormProvider(_args));
    final today = ref.read(todayProvider);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(state.date.year, state.date.month, state.date.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year, today.month, today.day),
      helpText: 'Messdatum',
    );
    if (pickedDate == null || !mounted) {
      return;
    }
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: state.time.hour, minute: state.time.minute),
      helpText: 'Messzeit',
    );
    if (!mounted) {
      return;
    }
    _controller.setDate(LocalDate.fromDateTime(pickedDate));
    if (pickedTime != null) {
      _controller.setTime(LocalTime(pickedTime.hour, pickedTime.minute));
    }
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
    final state = ref.watch(weightFormProvider(_args));
    ref.listen(weightFormProvider(_args).select((s) => s.weightText), (
      previous,
      next,
    ) {
      if (_weight.text != next) {
        _weight.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });
    final today = ref.watch(todayProvider);
    final weightError = state.fieldErrors[WeightFields.weight];
    final canSubmit =
        !state.submitting &&
        state.weightText.trim().isNotEmpty &&
        weightError == null &&
        (!_isEdit || state.dirty);

    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_askToDiscard());
        }
      },
      child: AppScaffold.subpage(
        title: _isEdit ? 'Eintrag bearbeiten' : 'Gewicht eintragen',
        onBack: () => backOrHome(context),
        primaryAction: PrimaryButton(
          label: _isEdit ? 'Änderungen speichern' : 'Eintrag speichern',
          onPressed: canSubmit ? _submit : null,
          loading: state.submitting,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ValueCard(
              state: state,
              weightController: _weight,
              focusNode: _weightFocus,
              error: weightError,
              deltaGrams: _previewDelta(state),
              onChanged: _controller.setWeightText,
              onSubmitted: (_) {
                if (canSubmit) {
                  unawaited(_submit());
                }
              },
              onStep: _controller.step,
              onAcceptSuggestion: _controller.acceptSuggestion,
            ),
            const SizedBox(height: 14),
            AppListGroup(
              children: [
                EntryListTile.chevron(
                  title: 'Messzeitpunkt',
                  subtitle:
                      '${formatRelativeDay(state.date, today)}, '
                      '${state.time.toIso()} Uhr',
                  icon: AppIcon.clock.data,
                  accent: AppAccent.water,
                  onTap: _pickMoment,
                ),
              ],
            ),
            if (state.fieldErrors[WeightFields.measuredAt] != null) ...[
              const SizedBox(height: 8),
              FieldErrorMessage(
                text: state.fieldErrors[WeightFields.measuredAt]!,
              ),
            ],
            if (state.duplicateOfId != null) ...[
              const SizedBox(height: 8),
              _DuplicateOffer(existingId: state.duplicateOfId!),
            ],
            const SizedBox(height: 14),
            const AppSectionHeader(
              title: 'Messbedingungen',
              subtitle: 'Wähle aus, was bei dieser Messung zutrifft.',
              padding: EdgeInsets.only(left: 10, top: 4),
            ),
            const SizedBox(height: 8),
            AppListGroup(
              children: [
                EntryListTile.check(
                  title: 'Vor dem Klo',
                  subtitle: 'Noch nicht auf Toilette gewesen',
                  icon: Icons.wc_rounded,
                  accent: AppAccent.habits,
                  value: state.beforeToilet,
                  onToggle: _controller.setBeforeToilet,
                ),
                EntryListTile.check(
                  title: 'Nach dem Trinken',
                  subtitle: 'Bereits etwas getrunken',
                  icon: AppIcon.water.data,
                  accent: AppAccent.water,
                  value: state.afterDrinking,
                  onToggle: _controller.setAfterDrinking,
                ),
                EntryListTile.check(
                  title: 'Nach dem Essen',
                  subtitle: 'Bereits etwas gegessen',
                  icon: AppIcon.meal.data,
                  accent: AppAccent.workout,
                  value: state.afterEating,
                  onToggle: _controller.setAfterEating,
                ),
              ],
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Notiz',
              requirementLabel: 'optional',
              controller: _note,
              focusNode: _noteFocus,
              hint: 'Zum Beispiel: nach dem Training',
              maxLength: maxNoteLength,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              errorText: state.fieldErrors[WeightFields.note],
              onChanged: _controller.setNote,
            ),
            const SizedBox(height: 14),
            const _HintCard(),
            if (_isEdit) ...[
              const SizedBox(height: 14),
              Center(
                child: SecondaryButton(
                  label: 'Eintrag löschen',
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

  /// The change against the latest earlier measurement for the typed value,
  /// or null without a valid value or an earlier measurement.
  int? _previewDelta(WeightFormState state) {
    final parsed = parseWeightKg(state.weightText);
    if (parsed is! WeightKgParsed) {
      return null;
    }
    final entries = ref.watch(weightEntriesProvider).value;
    if (entries == null || entries.isEmpty) {
      return null;
    }
    final at = ref.read(clockProvider).toUtc(state.date, state.time);
    if (at is! ZonedResolved) {
      return null;
    }
    return deltaBefore(
      [
        for (final entry in entries)
          WeightSample(
            id: entry.id,
            occurredAtUtc: entry.occurredAtUtc,
            localDate: entry.localDate,
            grams: entry.weightGrams,
          ),
      ],
      grams: parsed.grams,
      occurredAtUtc: at.utc,
      excludeId: _args.entry?.id,
    );
  }
}

/// The big value with minus and plus, the typed text field and the hints for
/// the value (suggestion, error, change against the last entry).
class _ValueCard extends StatelessWidget {
  const _ValueCard({
    required this.state,
    required this.weightController,
    required this.focusNode,
    required this.error,
    required this.deltaGrams,
    required this.onChanged,
    required this.onSubmitted,
    required this.onStep,
    required this.onAcceptSuggestion,
  });

  final WeightFormState state;
  final TextEditingController weightController;
  final FocusNode focusNode;
  final String? error;
  final int? deltaGrams;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final void Function(int direction) onStep;
  final VoidCallback onAcceptSuggestion;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final suggestion = state.suggestionGrams;
    final showSuggestion =
        suggestion != null && state.weightText.trim().isEmpty && error == null;
    return AppCard(
      borderColor: error == null ? null : colors.error,
      borderWidth: error == null ? 1 : 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcon.weight.data, size: 24, color: colors.moduleWeight),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gewicht',
                  style: AppTextStyles.titleCard.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  formatDateLong(state.date),
                  textAlign: TextAlign.end,
                  style: AppTextStyles.captionDefault.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          QuantityStepper(
            valueText: state.weightText,
            expand: true,
            onIncrease: () => onStep(1),
            onDecrease: () => onStep(-1),
            increaseLabel: 'um 0,1 Kilogramm erhöhen',
            decreaseLabel: 'um 0,1 Kilogramm verringern',
            valueWidget: _WeightValueField(
              controller: weightController,
              focusNode: focusNode,
              hint: suggestion == null ? '0,0' : formatKilograms(suggestion),
              hasError: error != null,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
          const SizedBox(height: 10),
          if (error != null)
            Align(child: FieldErrorMessage(text: error!))
          else if (showSuggestion)
            Align(
              child: SecondaryButton(
                label:
                    'Letzten Wert übernehmen (${formatKilograms(suggestion)} kg)',
                expand: false,
                onPressed: onAcceptSuggestion,
              ),
            )
          else if (deltaGrams != null)
            Align(
              child: WeightDeltaBadge(
                deltaGrams: deltaGrams!,
                since: 'seit dem letzten Eintrag',
              ),
            ),
        ],
      ),
    );
  }
}

/// The editable kilogram value in display size. Digits, comma and period only;
/// the validation happens when saving (domain parser). The text scale of this
/// one display value is capped at 130 % so that it always fits between the
/// buttons; everything else scales without limit.
class _WeightValueField extends StatelessWidget {
  const _WeightValueField({
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
    final style = AppTextStyles.displayXl.copyWith(
      color: hasError ? colors.error : colors.textPrimary,
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      // Narrow screens at large text sizes shrink the value instead of
      // overflowing the card.
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
                  label: 'Gewicht in Kilogramm',
                  textField: true,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textAlign: TextAlign.center,
                    style: style,
                    cursorColor: colors.primaryButton,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: bareInputDecoration(
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
              'kg',
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

/// Offered when a measurement with exactly this time exists: edit that one
/// instead of creating a second entry.
class _DuplicateOffer extends StatelessWidget {
  const _DuplicateOffer({required this.existingId});

  final String existingId;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      borderColor: colors.error,
      borderWidth: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldErrorMessage(
            text: 'Für diesen Messzeitpunkt gibt es schon einen Eintrag.',
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            label: 'Bestehenden Eintrag bearbeiten',
            onPressed: () =>
                context.pushReplacement(WeightRoutes.edit(existingId)),
          ),
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      child: MergeSemantics(
        child: Row(
          children: [
            Icon(AppIcon.hint.data, size: 28, color: colors.warningText),
            const SizedBox(width: 12),
            Container(width: 1, height: 32, color: colors.borderInput),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tipp für genaue Werte',
                    style: AppTextStyles.captionStrong.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Am besten morgens, nüchtern und nach dem Klo wiegen.',
                    style: AppTextStyles.captionDefault.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
