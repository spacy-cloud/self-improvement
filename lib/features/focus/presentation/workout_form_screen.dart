import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/workout_form_controller.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_intensity.dart';
import 'package:self_improvement/features/focus/domain/workout_validation.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';
import 'package:self_improvement/features/focus/presentation/focus_widgets.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// "Workout eintragen" (new) and "Training bearbeiten" (with [entryId]).
///
/// Nothing is preselected: no category, no duration, no muscle group, no
/// intensity. What the user does not choose is not saved.
class WorkoutFormScreen extends ConsumerWidget {
  const WorkoutFormScreen({this.entryId, super.key});

  /// The workout to edit, or null for a new one.
  final String? entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = entryId;
    if (id == null) {
      return const _WorkoutForm(
        key: ValueKey('workout-create'),
        args: WorkoutFormArgs.create(),
      );
    }
    return _EditLoader(entryId: id);
  }
}

/// Loads the workout once; later changes of its row (for example by an undo
/// elsewhere) never reset a form that is open.
class _EditLoader extends ConsumerStatefulWidget {
  const _EditLoader({required this.entryId});

  final String entryId;

  @override
  ConsumerState<_EditLoader> createState() => _EditLoaderState();
}

class _EditLoaderState extends ConsumerState<_EditLoader> {
  WorkoutEntry? _opened;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(workoutEntryProvider(widget.entryId));
    _opened ??= async.value;
    final opened = _opened;
    if (opened != null) {
      return _WorkoutForm(
        key: ValueKey('workout-edit-${opened.id}'),
        args: WorkoutFormArgs.edit(opened),
      );
    }
    return AppScaffold.subpage(
      title: 'Training bearbeiten',
      onBack: () => closeOrGoHome(context),
      body: async.when(
        loading: () => const ScreenLoading(),
        error: (error, stack) => ErrorState(
          onRetry: () => ref.invalidate(workoutEntryProvider(widget.entryId)),
        ),
        data: (entry) => EmptyState(
          title: 'Training nicht gefunden',
          message: 'Dieses Training gibt es nicht mehr.',
          actionLabel: 'Zur Übersicht',
          onAction: () => context.go(WorkoutRoutes.overview),
          icon: AppIcon.workout,
          accent: AppAccent.workout,
        ),
      ),
    );
  }
}

class _WorkoutForm extends ConsumerStatefulWidget {
  const _WorkoutForm({required this.args, super.key});

  final WorkoutFormArgs args;

  @override
  ConsumerState<_WorkoutForm> createState() => _WorkoutFormState();
}

class _WorkoutFormState extends ConsumerState<_WorkoutForm> {
  late final TextEditingController _title;
  late final TextEditingController _duration;
  late final TextEditingController _note;
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _durationFocus = FocusNode();
  final FocusNode _noteFocus = FocusNode();

  WorkoutFormArgs get _args => widget.args;
  bool get _isEdit => _args.entry != null;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(workoutFormProvider(_args));
    _title = TextEditingController(text: initial.title);
    _duration = TextEditingController(text: initial.durationText);
    _note = TextEditingController(text: initial.note);
  }

  @override
  void dispose() {
    _title.dispose();
    _duration.dispose();
    _note.dispose();
    _titleFocus.dispose();
    _durationFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  WorkoutFormController get _controller =>
      ref.read(workoutFormProvider(_args).notifier);

  void _leave(GoRouter router, String fallback) {
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(fallback);
    }
  }

  Future<void> _submit() async {
    if (!mounted) {
      return;
    }
    FocusScope.of(context).unfocus();
    final feedback = ref.read(feedbackServiceProvider);
    final router = GoRouter.of(context);
    final result = await _controller.submit();
    switch (result) {
      case WorkoutSaved():
        feedback.showSaved(result.message, undo: result.outcome.undo);
        if (mounted) {
          _leave(router, '/');
        }
      case WorkoutRejected():
        if (!mounted) {
          return;
        }
        final rejected = ref.read(workoutFormProvider(_args));
        // The first invalid text field takes the focus, so a screen reader
        // reads its label together with the hint. The title and the note are
        // limited by their fields, but a field counts characters and the rules
        // count code points, so they can be wrong too (the category is a
        // choice, not a text field).
        final errors = rejected.fieldErrors;
        if (errors.containsKey(WorkoutFields.title)) {
          _titleFocus.requestFocus();
        } else if (errors.containsKey(WorkoutFields.duration)) {
          _durationFocus.requestFocus();
        } else if (errors.containsKey(WorkoutFields.note)) {
          _noteFocus.requestFocus();
        }
        final failure = rejected.submitFailure;
        if (failure == null) {
          return; // The fields show what to correct.
        }
        if (failure is ConflictFailure) {
          feedback.showError(failure.userMessage);
        } else {
          feedback.showError(
            'Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.',
            onRetry: () => unawaited(_submit()),
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
      title: 'Training vom ${formatDayMonth(entry.localDate)} löschen?',
      message:
          '${entry.displayTitle} (${entry.durationMinutes} Min.) wird '
          'entfernt. Du kannst es direkt danach rückgängig machen.',
      confirmLabel: 'Löschen',
    );
    if (!confirmed || !mounted) {
      return;
    }
    final result = await _controller.deleteEntry();
    switch (result) {
      case WorkoutDeleted():
        feedback.showSaved(result.message, undo: result.outcome.undo);
        if (mounted) {
          _leave(router, WorkoutRoutes.overview);
        }
      case WorkoutDeleteFailed(:final failure):
        feedback.showError(
          failure is StorageFailure
              ? 'Löschen fehlgeschlagen. Das Training ist unverändert.'
              : failure.userMessage,
        );
      case WorkoutDeleteBusy():
        break;
    }
  }

  Future<void> _pickMoment() async {
    final state = ref.read(workoutFormProvider(_args));
    final today = ref.read(todayProvider);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(state.date.year, state.date.month, state.date.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year, today.month, today.day),
      helpText: 'Trainingsdatum',
    );
    if (pickedDate == null || !mounted) {
      return;
    }
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: state.time.hour, minute: state.time.minute),
      helpText: 'Trainingszeit',
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
      _leave(GoRouter.of(context), _isEdit ? WorkoutRoutes.overview : '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workoutFormProvider(_args));
    ref.listen(workoutFormProvider(_args).select((s) => s.durationText), (
      previous,
      next,
    ) {
      if (_duration.text != next) {
        _duration.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });
    final today = ref.watch(todayProvider);
    final canSubmit = !state.submitting && (!_isEdit || state.dirty);
    final errors = state.fieldErrors;

    final inlineAction = formActionIsInline(context);
    final saveButton = PrimaryButton(
      label: _isEdit ? 'Änderungen speichern' : 'Training speichern',
      onPressed: canSubmit ? () => unawaited(_submit()) : null,
      loading: state.submitting,
    );

    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_askToDiscard());
        }
      },
      child: AppScaffold.subpage(
        title: _isEdit ? 'Training bearbeiten' : 'Workout eintragen',
        onBack: () => closeOrGoHome(context),
        primaryAction: inlineAction ? null : saveButton,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TrainingCard(
              state: state,
              title: _title,
              titleFocus: _titleFocus,
              error: errors[WorkoutFields.title],
              categoryError: errors[WorkoutFields.category],
              onTitle: _controller.setTitle,
              onCategory: _controller.selectCategory,
            ),
            const SizedBox(height: 12),
            _MusclesCard(
              selected: state.muscleGroups,
              onToggle: _controller.toggleMuscleGroup,
            ),
            const SizedBox(height: 12),
            _DurationCard(
              state: state,
              duration: _duration,
              focusNode: _durationFocus,
              error: errors[WorkoutFields.duration],
              onChanged: _controller.setDurationText,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              onStep: _controller.stepDuration,
              onIntensity: _controller.toggleIntensity,
            ),
            const SizedBox(height: 12),
            AppListGroup(
              children: [
                EntryListTile.chevron(
                  title: 'Zeitpunkt',
                  subtitle:
                      '${formatRelativeDay(state.date, today)}, '
                      '${state.time.toIso()} Uhr',
                  icon: AppIcon.clock.data,
                  accent: AppAccent.water,
                  onTap: () => unawaited(_pickMoment()),
                ),
              ],
            ),
            if (errors[WorkoutFields.occurredAt] != null) ...[
              const SizedBox(height: 8),
              InlineMessage(text: errors[WorkoutFields.occurredAt]!),
            ],
            const SizedBox(height: 12),
            AppTextField(
              label: 'Notiz',
              requirementLabel: 'optional',
              controller: _note,
              focusNode: _noteFocus,
              hint: 'Zum Beispiel: Schulter war etwas steif',
              maxLength: maxWorkoutNoteLength,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              errorText: errors[WorkoutFields.note],
              onChanged: _controller.setNote,
            ),
            if (_isEdit) ...[
              const SizedBox(height: 14),
              Center(
                child: SecondaryButton(
                  label: 'Training löschen',
                  icon: AppIcon.delete.data,
                  danger: true,
                  expand: false,
                  onPressed: state.submitting
                      ? null
                      : () => unawaited(_confirmDelete()),
                ),
              ),
            ],
            if (inlineAction) ...[const SizedBox(height: 16), saveButton],
          ],
        ),
      ),
    );
  }
}

/// Name (optional) and the category. No category is preselected; saving
/// without one is refused with a message at the chips.
class _TrainingCard extends StatelessWidget {
  const _TrainingCard({
    required this.state,
    required this.title,
    required this.titleFocus,
    required this.error,
    required this.categoryError,
    required this.onTitle,
    required this.onCategory,
  });

  final WorkoutFormState state;
  final TextEditingController title;
  final FocusNode titleFocus;
  final String? error;
  final String? categoryError;
  final ValueChanged<String> onTitle;
  final ValueChanged<TrainingCategory> onCategory;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      borderColor: categoryError == null ? null : colors.error,
      borderWidth: categoryError == null ? 1 : 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeading(
            icon: AppIcon.workout.data,
            title: 'Training',
            accent: AppAccent.workout,
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Name',
            requirementLabel: 'optional',
            controller: title,
            focusNode: titleFocus,
            hint: 'Zum Beispiel: Upper Body',
            helperText: 'Ohne Namen wird die Kategorie angezeigt.',
            maxLength: maxWorkoutTitleLength,
            textCapitalization: TextCapitalization.sentences,
            errorText: error,
            onChanged: onTitle,
          ),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Trainingskategorie',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in TrainingCategory.values)
                  AppChoiceChip(
                    label: category.label,
                    selected: state.category == category,
                    onSelected: (_) => onCategory(category),
                  ),
              ],
            ),
          ),
          if (categoryError != null) ...[
            const SizedBox(height: 8),
            InlineMessage(text: categoryError!),
          ],
        ],
      ),
    );
  }
}

/// The optional muscle groups (multi-select, no duplicates).
class _MusclesCard extends StatelessWidget {
  const _MusclesCard({required this.selected, required this.onToggle});

  final List<MuscleGroup> selected;
  final ValueChanged<MuscleGroup> onToggle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TitleWithHint(
            title: 'Muskelgruppen',
            hint: 'optional, Mehrfachauswahl',
          ),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Muskelgruppen',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final group in MuscleGroup.values)
                  AppFilterChip(
                    label: group.label,
                    selected: selected.contains(group),
                    onSelected: (_) => onToggle(group),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Duration with minus and plus (5 minutes per step, typed digits allowed) and
/// the optional intensity.
class _DurationCard extends StatelessWidget {
  const _DurationCard({
    required this.state,
    required this.duration,
    required this.focusNode,
    required this.error,
    required this.onChanged,
    required this.onSubmitted,
    required this.onStep,
    required this.onIntensity,
  });

  final WorkoutFormState state;
  final TextEditingController duration;
  final FocusNode focusNode;
  final String? error;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final void Function(int direction) onStep;
  final ValueChanged<WorkoutIntensity> onIntensity;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      borderColor: error == null ? null : colors.error,
      borderWidth: error == null ? 1 : 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Dauer',
                  style: AppTextStyles.titleCard.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              QuantityStepper(
                valueText: state.durationText,
                onIncrease: () => onStep(1),
                onDecrease: () => onStep(-1),
                increaseLabel: 'Dauer um 5 Minuten erhöhen',
                decreaseLabel: 'Dauer um 5 Minuten verringern',
                valueWidget: _DurationField(
                  controller: duration,
                  focusNode: focusNode,
                  hasError: error != null,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            InlineMessage(text: error!),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: colors.track),
          const SizedBox(height: 12),
          const TitleWithHint(title: 'Intensität', hint: 'optional'),
          const SizedBox(height: 8),
          PeriodSelector<WorkoutIntensity?>(
            options: [
              for (final intensity in WorkoutIntensity.values)
                PeriodOption<WorkoutIntensity?>(
                  value: intensity,
                  label: intensity.label,
                ),
            ],
            selected: state.intensity,
            semanticLabel: 'Intensität',
            onChanged: (value) {
              if (value != null) {
                onIntensity(value);
              }
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Zum Entfernen die Auswahl erneut antippen.',
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The editable duration in display size. Digits only; the validation happens
/// when saving (domain parser). The text scale of this one display value is
/// capped at 130 % so that it always fits between the buttons; everything else
/// scales without limit.
class _DurationField extends StatelessWidget {
  const _DurationField({
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final style = AppTextStyles.titleScreen.copyWith(
      color: hasError ? colors.error : colors.textPrimary,
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48),
              child: Semantics(
                label: 'Dauer in Minuten',
                textField: true,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textAlign: TextAlign.center,
                  style: style,
                  cursorColor: colors.primaryButton,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    // With the padding the field is at least 48 px high.
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                    hintText: '–',
                    hintStyle: style.copyWith(color: colors.textTertiary),
                  ),
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  onTapOutside: dismissKeyboardOnTapOutside,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Min.',
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
