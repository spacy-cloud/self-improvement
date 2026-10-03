import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_intensity.dart';
import 'package:self_improvement/features/focus/domain/workout_validation.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Identifies a workout form: new entry (`entry == null`) or editing [entry].
@immutable
final class WorkoutFormArgs {
  const WorkoutFormArgs.create() : entry = null;

  const WorkoutFormArgs.edit(WorkoutEntry this.entry);

  final WorkoutEntry? entry;

  @override
  bool operator ==(Object other) =>
      other is WorkoutFormArgs &&
      other.entry?.id == entry?.id &&
      other.entry?.rowVersion == entry?.rowVersion;

  @override
  int get hashCode => Object.hash(entry?.id, entry?.rowVersion);
}

/// State of the workout form. All input stays here when saving fails.
///
/// A new form starts EMPTY: no category, no duration, no muscle group, no
/// intensity are preselected (nothing from the design's example is saved
/// unless the user chooses it).
@immutable
final class WorkoutFormState {
  const WorkoutFormState({
    required this.title,
    required this.durationText,
    required this.muscleGroups,
    required this.note,
    required this.date,
    required this.time,
    required this.dirty,
    this.category,
    this.intensity,
    this.fieldErrors = const {},
    this.submitting = false,
    this.submitFailure,
  });

  /// The chosen category; null until the user picks one (required to save).
  final TrainingCategory? category;

  /// The optional custom title as typed (at most 80 characters); blank means
  /// the category name is displayed.
  final String title;

  /// The duration in minutes as typed (digits only).
  final String durationText;

  /// The selected muscle groups, deduplicated, in canonical order.
  final List<MuscleGroup> muscleGroups;

  /// The optional intensity; null when none is chosen.
  final WorkoutIntensity? intensity;

  final String note;

  /// Workout date and wall clock time in the current device zone.
  final LocalDate date;
  final LocalTime time;

  /// True once the user changed anything (drives the "Änderungen verwerfen?"
  /// dialog).
  final bool dirty;

  /// Field key -> German hint (see `WorkoutFields`).
  final Map<String, String> fieldErrors;

  /// True while a save is running; further saves are ignored.
  final bool submitting;

  /// A persistent form level failure (e.g. storage); input is kept.
  final AppFailure? submitFailure;

  /// The duration as a number, or null while the text is not a valid duration.
  int? get durationMinutes => switch (parseWorkoutMinutes(durationText)) {
    WorkoutMinutesParsed(:final minutes) => minutes,
    WorkoutMinutesInvalid() => null,
  };

  WorkoutFormState copyWith({
    TrainingCategory? Function()? category,
    String? title,
    String? durationText,
    List<MuscleGroup>? muscleGroups,
    WorkoutIntensity? Function()? intensity,
    String? note,
    LocalDate? date,
    LocalTime? time,
    bool? dirty,
    Map<String, String>? fieldErrors,
    bool? submitting,
    AppFailure? Function()? submitFailure,
  }) => WorkoutFormState(
    category: category == null ? this.category : category(),
    title: title ?? this.title,
    durationText: durationText ?? this.durationText,
    muscleGroups: muscleGroups ?? this.muscleGroups,
    intensity: intensity == null ? this.intensity : intensity(),
    note: note ?? this.note,
    date: date ?? this.date,
    time: time ?? this.time,
    dirty: dirty ?? this.dirty,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    submitting: submitting ?? this.submitting,
    submitFailure: submitFailure == null ? this.submitFailure : submitFailure(),
  );
}

/// Outcome of [WorkoutFormController.submit].
sealed class WorkoutSubmitResult {
  const WorkoutSubmitResult();
}

/// Saved. [outcome] carries the undo action for the snackbar.
final class WorkoutSaved extends WorkoutSubmitResult {
  const WorkoutSaved(this.outcome, {required this.wasEdit});

  final CommandOutcome outcome;
  final bool wasEdit;

  /// Success message after the commit.
  String get message =>
      wasEdit ? 'Training aktualisiert' : 'Training gespeichert';
}

/// Not saved; the form shows the reason and keeps all input.
final class WorkoutRejected extends WorkoutSubmitResult {
  const WorkoutRejected();
}

/// Outcome of [WorkoutFormController.deleteEntry].
sealed class WorkoutDeleteResult {
  const WorkoutDeleteResult();
}

/// Deleted. [outcome] carries the undo action that restores the same id.
final class WorkoutDeleted extends WorkoutDeleteResult {
  const WorkoutDeleted(this.outcome);

  final CommandOutcome outcome;

  /// Success message after the commit.
  String get message => 'Training gelöscht';
}

/// Ignored because a save or delete is already running (double tap).
final class WorkoutDeleteBusy extends WorkoutDeleteResult {
  const WorkoutDeleteBusy();
}

/// Not deleted (for example the workout vanished or the database failed).
final class WorkoutDeleteFailed extends WorkoutDeleteResult {
  const WorkoutDeleteFailed(this.failure);

  final AppFailure failure;
}

/// Controller of the new/edit workout form (same pattern as the weight form).
class WorkoutFormController extends Notifier<WorkoutFormState> {
  WorkoutFormController(this.args);

  final WorkoutFormArgs args;

  late SubmissionTracker _tracker;
  DateTime? _originalInstant;
  var _timeTouched = false;

  bool get isEdit => args.entry != null;

  @override
  WorkoutFormState build() {
    final clock = ref.read(clockProvider);
    // build() runs again after invalidation: reset all per-form bookkeeping.
    _tracker = SubmissionTracker(ref.read(idGeneratorProvider));
    _timeTouched = false;
    final entry = args.entry;
    final local = clock.toLocal(entry?.occurredAtUtc ?? clock.nowUtc());
    _originalInstant = entry?.occurredAtUtc;
    return WorkoutFormState(
      category: entry?.category,
      title: entry?.title ?? '',
      durationText: entry == null ? '' : '${entry.durationMinutes}',
      muscleGroups: MuscleGroup.normalize(entry?.muscleGroups ?? const []),
      intensity: entry?.intensity,
      note: entry?.note ?? '',
      date: local.date,
      time: local.time,
      dirty: false,
    );
  }

  void selectCategory(TrainingCategory category) => state = state.copyWith(
    category: () => category,
    dirty: true,
    fieldErrors: _without(WorkoutFields.category),
  );

  void setTitle(String value) => state = state.copyWith(
    title: value,
    dirty: true,
    fieldErrors: _without(WorkoutFields.title),
  );

  void setDurationText(String text) => state = state.copyWith(
    durationText: text,
    dirty: true,
    fieldErrors: _without(WorkoutFields.duration),
  );

  /// Plus (+1) or minus (-1) button: 5 minutes per step, within 1 to 600. From
  /// an empty field the first press shows 30 minutes.
  void stepDuration(int direction) {
    final minutes = stepWorkoutMinutes(
      currentText: state.durationText,
      direction: direction,
    );
    setDurationText('$minutes');
  }

  /// Selects or deselects one muscle group (multi-select; no duplicates).
  void toggleMuscleGroup(MuscleGroup group) {
    final selected = state.muscleGroups.toSet();
    if (!selected.add(group)) {
      selected.remove(group);
    }
    state = state.copyWith(
      muscleGroups: MuscleGroup.normalize(selected),
      dirty: true,
    );
  }

  /// Replaces the selection; duplicates are removed.
  void setMuscleGroups(Iterable<MuscleGroup> groups) => state = state.copyWith(
    muscleGroups: MuscleGroup.normalize(groups),
    dirty: true,
  );

  /// Sets the intensity; null clears it (it is optional).
  void setIntensity(WorkoutIntensity? intensity) =>
      state = state.copyWith(intensity: () => intensity, dirty: true);

  /// Tapping the active segment again clears the intensity, tapping another
  /// one selects it.
  void toggleIntensity(WorkoutIntensity intensity) =>
      setIntensity(state.intensity == intensity ? null : intensity);

  void setNote(String value) => state = state.copyWith(
    note: value,
    dirty: true,
    fieldErrors: _without(WorkoutFields.note),
  );

  void setDate(LocalDate date) {
    _timeTouched = true;
    state = state.copyWith(
      date: date,
      dirty: true,
      fieldErrors: _without(WorkoutFields.occurredAt),
    );
  }

  void setTime(LocalTime time) {
    _timeTouched = true;
    state = state.copyWith(
      time: time,
      dirty: true,
      fieldErrors: _without(WorkoutFields.occurredAt),
    );
  }

  /// Validates and saves. Ignored while a save is running (double tap).
  Future<WorkoutSubmitResult> submit() async {
    if (state.submitting) {
      return const WorkoutRejected();
    }
    final errors = <String, String>{};

    final category = state.category;
    if (category == null) {
      errors[WorkoutFields.category] = workoutCategoryMissingMessage;
    }

    int? minutes;
    switch (parseWorkoutMinutes(state.durationText)) {
      case WorkoutMinutesParsed(minutes: final parsed):
        minutes = parsed;
      case WorkoutMinutesInvalid(:final error):
        errors[WorkoutFields.duration] = workoutMinutesErrorMessage(error);
    }

    final clock = ref.read(clockProvider);
    DateTime? occurredAt;
    if (!_timeTouched && _originalInstant != null) {
      occurredAt = _originalInstant;
    } else if (!_timeTouched && !isEdit) {
      // Untouched new entry: "now" at the moment of saving (not form open).
      occurredAt = clock.nowUtc();
    } else {
      switch (clock.toUtc(state.date, state.time)) {
        case ZonedResolved(:final utc):
          occurredAt = utc;
        case ZonedNonexistent(:final nextValid):
          errors[WorkoutFields.occurredAt] =
              'Diese Uhrzeit gibt es wegen der Zeitumstellung nicht. '
              'Bitte wähle ${nextValid.toIso()} Uhr oder später.';
      }
    }

    if (errors.isNotEmpty ||
        category == null ||
        minutes == null ||
        occurredAt == null) {
      state = state.copyWith(fieldErrors: errors);
      return const WorkoutRejected();
    }

    final draft = WorkoutDraft(
      category: category,
      durationMinutes: minutes,
      occurredAtUtc: occurredAt,
      title: state.title,
      muscleGroups: state.muscleGroups,
      intensity: state.intensity,
      note: state.note,
    );
    final commandId = _tracker.idFor((
      args.entry?.id,
      category.key,
      state.title.trim(),
      minutes,
      [for (final group in state.muscleGroups) group.key].join(','),
      state.intensity?.key,
      occurredAt,
      state.note.trim(),
    ));

    state = state.copyWith(
      submitting: true,
      fieldErrors: const {},
      submitFailure: () => null,
    );
    final repository = ref.read(workoutRepositoryProvider);
    try {
      final entry = args.entry;
      final outcome = entry == null
          ? await repository.create(commandId: commandId, draft: draft)
          : await repository.update(
              commandId: commandId,
              id: entry.id,
              draft: draft,
              expectedRowVersion: entry.rowVersion,
            );
      _tracker.completed();
      state = state.copyWith(submitting: false, dirty: false);
      return WorkoutSaved(outcome, wasEdit: entry != null);
    } on ValidationFailure catch (failure) {
      state = state.copyWith(
        submitting: false,
        fieldErrors: failure.fieldErrors,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(submitting: false, submitFailure: () => failure);
    }
    return const WorkoutRejected();
  }

  /// Deletes the edited workout (soft delete with an undo that restores the
  /// same id). Only valid in edit mode; the UI asks for confirmation first. A
  /// retry after a failure reuses the command id.
  Future<WorkoutDeleteResult> deleteEntry() async {
    final entry = args.entry;
    if (entry == null) {
      throw StateError('Only an existing workout can be deleted');
    }
    if (state.submitting) {
      return const WorkoutDeleteBusy();
    }
    final commandId = _tracker.idFor(('delete', entry.id));
    state = state.copyWith(submitting: true, submitFailure: () => null);
    try {
      final outcome = await ref
          .read(workoutRepositoryProvider)
          .delete(commandId: commandId, id: entry.id);
      _tracker.completed();
      if (ref.mounted) {
        state = state.copyWith(submitting: false, dirty: false);
      }
      return WorkoutDeleted(outcome);
    } on AppFailure catch (failure) {
      if (ref.mounted) {
        state = state.copyWith(submitting: false, submitFailure: () => failure);
      }
      return WorkoutDeleteFailed(failure);
    }
  }

  Map<String, String> _without(String field) {
    final copy = Map<String, String>.of(state.fieldErrors)..remove(field);
    return copy;
  }
}

/// Provider of a workout form; auto-disposed with its screen.
final workoutFormProvider = NotifierProvider.autoDispose
    .family<WorkoutFormController, WorkoutFormState, WorkoutFormArgs>(
      WorkoutFormController.new,
    );
