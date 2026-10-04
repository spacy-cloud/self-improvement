import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/features/tasks/domain/habit_validation.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Identifies a habit form: new habit (`habit == null`) or editing [habit].
///
/// Two args are equal when they describe the same habit in the same version.
@immutable
final class HabitFormArgs {
  const HabitFormArgs.create() : habit = null;

  const HabitFormArgs.edit(Habit this.habit);

  final Habit? habit;

  @override
  bool operator ==(Object other) =>
      other is HabitFormArgs &&
      other.habit?.id == habit?.id &&
      other.habit?.rowVersion == habit?.rowVersion;

  @override
  int get hashCode => Object.hash(habit?.id, habit?.rowVersion);
}

/// State of the habit form. All input stays here when saving fails.
///
/// V1 habits are daily: there is deliberately no weekday or time-of-day
/// selection.
@immutable
final class HabitFormState {
  const HabitFormState({
    required this.title,
    required this.icon,
    required this.reminderEnabled,
    required this.reminderTime,
    this.dirty = false,
    this.fieldErrors = const {},
    this.submitting = false,
    this.submitFailure,
  });

  /// What the user typed (trimmed on save).
  final String title;

  /// The chosen symbol (default [defaultHabitIcon]). The accent colour is
  /// derived from the design tokens by the UI and is not part of the form.
  final HabitIcon icon;

  /// Whether a daily reminder is set. Off by default.
  final bool reminderEnabled;

  /// The reminder time. Shown and editable while [reminderEnabled]; kept when
  /// the toggle is switched off so switching it on again offers the same time.
  final LocalTime reminderTime;

  /// True while the content differs from what the form was opened with; drives
  /// the "Änderungen verwerfen?" dialog.
  final bool dirty;

  /// Field key -> German hint (see [HabitFields]).
  final Map<String, String> fieldErrors;

  /// True while a save is running; further saves are ignored.
  final bool submitting;

  /// A form level failure (storage, conflict, habit deleted meanwhile); the
  /// input is kept.
  final AppFailure? submitFailure;

  HabitFormState copyWith({
    String? title,
    HabitIcon? icon,
    bool? reminderEnabled,
    LocalTime? reminderTime,
    bool? dirty,
    Map<String, String>? fieldErrors,
    bool? submitting,
    AppFailure? Function()? submitFailure,
  }) => HabitFormState(
    title: title ?? this.title,
    icon: icon ?? this.icon,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    reminderTime: reminderTime ?? this.reminderTime,
    dirty: dirty ?? this.dirty,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    submitting: submitting ?? this.submitting,
    submitFailure: submitFailure == null ? this.submitFailure : submitFailure(),
  );
}

/// Outcome of [HabitFormController.submit].
sealed class HabitSubmitResult {
  const HabitSubmitResult();
}

/// Saved. [outcome] carries the undo action for the snackbar.
final class HabitSaved extends HabitSubmitResult {
  const HabitSaved(
    this.outcome, {
    required this.wasEdit,
    required this.habitId,
  });

  final CommandOutcome outcome;
  final bool wasEdit;

  /// The id of the created or edited habit.
  final String habitId;

  /// Success message after the commit.
  String get message =>
      wasEdit ? 'Gewohnheit aktualisiert' : 'Gewohnheit gespeichert';
}

/// Not saved; the form shows the reason and keeps all input.
final class HabitRejected extends HabitSubmitResult {
  const HabitRejected();
}

/// Controller of the new/edit habit form (title, icon choice, reminder).
///
/// Same pattern as the weight and task forms: typed field errors, a submit
/// guard against double taps, the command id of a failed attempt is reused by
/// the retry, and a dirty flag for the discard dialog.
class HabitFormController extends Notifier<HabitFormState> {
  HabitFormController(this.args);

  final HabitFormArgs args;

  late SubmissionTracker _tracker;
  late Object _initialContent;

  bool get isEdit => args.habit != null;

  @override
  HabitFormState build() {
    // build() runs again after invalidation: reset all per-form bookkeeping.
    _tracker = SubmissionTracker(ref.read(idGeneratorProvider));
    final habit = args.habit;
    final initial = HabitFormState(
      title: habit?.title ?? '',
      icon: habit?.icon ?? defaultHabitIcon,
      reminderEnabled: habit?.reminderTime != null,
      reminderTime: habit?.reminderTime ?? defaultHabitReminderTime,
    );
    _initialContent = _contentOf(initial);
    return initial;
  }

  void setTitle(String value) => _change(
    state.copyWith(title: value, fieldErrors: _without(HabitFields.title)),
  );

  /// Chooses the symbol from the six offered ones.
  void setIcon(HabitIcon value) => _change(
    state.copyWith(icon: value, fieldErrors: _without(HabitFields.icon)),
  );

  /// Switches the daily reminder on or off. Switching it on offers the current
  /// time (initially [defaultHabitReminderTime]).
  void setReminderEnabled(bool value) =>
      _change(state.copyWith(reminderEnabled: value));

  /// Sets the reminder time. Choosing a time switches the reminder on.
  void setReminderTime(LocalTime value) =>
      _change(state.copyWith(reminderTime: value, reminderEnabled: true));

  /// Validates and saves. Ignored while a save is running (double tap).
  Future<HabitSubmitResult> submit() async {
    if (state.submitting) {
      return const HabitRejected();
    }
    final draft = HabitDraft(
      title: state.title,
      iconKey: state.icon.key,
      reminderTime: state.reminderEnabled ? state.reminderTime : null,
    );
    try {
      validateHabitDraft(draft);
    } on ValidationFailure catch (failure) {
      state = state.copyWith(
        fieldErrors: failure.fieldErrors,
        submitFailure: () => null,
      );
      return const HabitRejected();
    }

    final habit = args.habit;
    final commandId = _tracker.idFor((habit?.id, _contentOf(state)));
    state = state.copyWith(
      submitting: true,
      fieldErrors: const {},
      submitFailure: () => null,
    );
    final repository = ref.read(habitRepositoryProvider);
    try {
      final outcome = habit == null
          ? await repository.create(commandId: commandId, draft: draft)
          : await repository.update(
              commandId: commandId,
              id: habit.id,
              draft: draft,
              expectedRowVersion: habit.rowVersion,
            );
      _tracker.completed();
      final saved = HabitSaved(
        outcome,
        wasEdit: habit != null,
        habitId: outcome.entityId ?? habit?.id ?? '',
      );
      if (ref.mounted) {
        _initialContent = _contentOf(state);
        state = state.copyWith(submitting: false, dirty: false);
      }
      return saved;
    } on ValidationFailure catch (failure) {
      if (ref.mounted) {
        state = state.copyWith(
          submitting: false,
          fieldErrors: failure.fieldErrors,
        );
      }
    } on AppFailure catch (failure) {
      if (ref.mounted) {
        state = state.copyWith(submitting: false, submitFailure: () => failure);
      }
    }
    return const HabitRejected();
  }

  void _change(HabitFormState next) =>
      state = next.copyWith(dirty: _contentOf(next) != _initialContent);

  /// The user-visible content; a switched-off reminder ignores its time.
  static Object _contentOf(HabitFormState s) =>
      (s.title.trim(), s.icon, s.reminderEnabled ? s.reminderTime : null);

  Map<String, String> _without(String field) =>
      Map<String, String>.of(state.fieldErrors)..remove(field);
}

/// Provider of a habit form; auto-disposed with its screen.
final habitFormProvider = NotifierProvider.autoDispose
    .family<HabitFormController, HabitFormState, HabitFormArgs>(
      HabitFormController.new,
    );
