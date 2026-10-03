import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/features/tasks/domain/task_tags.dart';
import 'package:self_improvement/features/tasks/domain/task_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Identifies a task form: new task (`task == null`) or editing [task].
///
/// Two args are equal when they describe the same task in the same version, so
/// a family provider keeps one form state per open form.
@immutable
final class TaskFormArgs {
  const TaskFormArgs.create() : task = null;

  const TaskFormArgs.edit(Task this.task);

  final Task? task;

  @override
  bool operator ==(Object other) =>
      other is TaskFormArgs &&
      other.task?.id == task?.id &&
      other.task?.rowVersion == task?.rowVersion;

  @override
  int get hashCode => Object.hash(task?.id, task?.rowVersion);
}

/// State of the task form. All input stays here when saving fails.
@immutable
final class TaskFormState {
  const TaskFormState({
    required this.title,
    required this.description,
    required this.priority,
    required this.dueDate,
    required this.tags,
    this.dirty = false,
    this.fieldErrors = const {},
    this.submitting = false,
    this.submitFailure,
  });

  /// What the user typed (trimmed on save).
  final String title;
  final String description;
  final TaskPriority priority;

  /// The optional due day; null means no date.
  final LocalDate? dueDate;

  /// The tags entered so far (trimmed, deduplicated, at most five).
  final List<String> tags;

  /// True while the content differs from what the form was opened with; drives
  /// the "Änderungen verwerfen?" dialog. Typing and deleting the same text again
  /// is not dirty.
  final bool dirty;

  /// Field key -> German hint (see [TaskFields]).
  final Map<String, String> fieldErrors;

  /// True while a save is running; further saves are ignored.
  final bool submitting;

  /// A form level failure (storage, conflict, task deleted meanwhile); the
  /// input is kept.
  final AppFailure? submitFailure;

  /// Whether another tag can still be added (at most five).
  bool get canAddTag => tags.length < maxTagsPerTask;

  TaskFormState copyWith({
    String? title,
    String? description,
    TaskPriority? priority,
    LocalDate? Function()? dueDate,
    List<String>? tags,
    bool? dirty,
    Map<String, String>? fieldErrors,
    bool? submitting,
    AppFailure? Function()? submitFailure,
  }) => TaskFormState(
    title: title ?? this.title,
    description: description ?? this.description,
    priority: priority ?? this.priority,
    dueDate: dueDate == null ? this.dueDate : dueDate(),
    tags: tags ?? this.tags,
    dirty: dirty ?? this.dirty,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    submitting: submitting ?? this.submitting,
    submitFailure: submitFailure == null ? this.submitFailure : submitFailure(),
  );
}

/// Outcome of [TaskFormController.submit].
sealed class TaskSubmitResult {
  const TaskSubmitResult();
}

/// Saved. [outcome] carries the undo action for the snackbar.
final class TaskSaved extends TaskSubmitResult {
  const TaskSaved(this.outcome, {required this.wasEdit, required this.taskId});

  final CommandOutcome outcome;
  final bool wasEdit;

  /// The id of the created or edited task.
  final String taskId;

  /// Success message after the commit.
  String get message =>
      wasEdit ? 'Aufgabe aktualisiert' : 'Aufgabe gespeichert';
}

/// Not saved; the form shows the reason and keeps all input.
final class TaskRejected extends TaskSubmitResult {
  const TaskRejected();
}

/// Controller of the new/edit task form.
///
/// Field errors are typed by field (see [TaskFields]); [submit] is guarded
/// against double taps; a retry after a failure reuses the command id of the
/// failed attempt (as long as the content is unchanged).
class TaskFormController extends Notifier<TaskFormState> {
  TaskFormController(this.args);

  final TaskFormArgs args;

  late SubmissionTracker _tracker;
  late Object _initialContent;

  bool get isEdit => args.task != null;

  @override
  TaskFormState build() {
    // build() runs again after invalidation: reset all per-form bookkeeping.
    _tracker = SubmissionTracker(ref.read(idGeneratorProvider));
    final task = args.task;
    final initial = TaskFormState(
      title: task?.title ?? '',
      description: task?.description ?? '',
      priority: task?.priority ?? defaultTaskPriority,
      dueDate: task?.dueDate,
      tags: List.unmodifiable(task?.tags ?? const <String>[]),
    );
    _initialContent = _contentOf(initial);
    return initial;
  }

  void setTitle(String value) => _change(
    state.copyWith(title: value, fieldErrors: _without(TaskFields.title)),
  );

  void setDescription(String value) => _change(
    state.copyWith(
      description: value,
      fieldErrors: _without(TaskFields.description),
    ),
  );

  void setPriority(TaskPriority value) =>
      _change(state.copyWith(priority: value));

  /// Sets the due day; null removes it (no date).
  void setDueDate(LocalDate? value) => _change(
    state.copyWith(
      dueDate: () => value,
      fieldErrors: _without(TaskFields.dueDate),
    ),
  );

  /// Adds a tag from the tag input. Returns what happened; on a rejection the
  /// German hint is also stored under [TaskFields.tags] and the tags stay as
  /// they were. The input field should be cleared only for
  /// [TagAddResult.added].
  TagAddResult addTag(String raw) {
    final addition = addTagToList(state.tags, raw);
    if (addition.result == TagAddResult.added) {
      _change(
        state.copyWith(
          tags: addition.tags,
          fieldErrors: _without(TaskFields.tags),
        ),
      );
    } else {
      state = state.copyWith(
        fieldErrors: {
          ...state.fieldErrors,
          TaskFields.tags: addition.result.message!,
        },
      );
    }
    return addition.result;
  }

  /// Clears the hint of a rejected tag, for example when the user types the
  /// next tag. The tags themselves stay as they are.
  void clearTagError() {
    if (state.fieldErrors.containsKey(TaskFields.tags)) {
      state = state.copyWith(fieldErrors: _without(TaskFields.tags));
    }
  }

  /// Removes a tag (case-insensitive match).
  void removeTag(String tag) => _change(
    state.copyWith(
      tags: removeTagFromList(state.tags, tag),
      fieldErrors: _without(TaskFields.tags),
    ),
  );

  /// Validates and saves. Ignored while a save is running (double tap).
  Future<TaskSubmitResult> submit() async {
    if (state.submitting) {
      return const TaskRejected();
    }
    final draft = TaskDraft(
      title: state.title,
      description: state.description,
      priority: state.priority,
      dueDate: state.dueDate,
      tags: state.tags,
    );
    try {
      validateTaskDraft(draft);
    } on ValidationFailure catch (failure) {
      state = state.copyWith(
        fieldErrors: failure.fieldErrors,
        submitFailure: () => null,
      );
      return const TaskRejected();
    }

    final task = args.task;
    final commandId = _tracker.idFor((task?.id, _contentOf(state)));
    state = state.copyWith(
      submitting: true,
      fieldErrors: const {},
      submitFailure: () => null,
    );
    final repository = ref.read(taskRepositoryProvider);
    try {
      final outcome = task == null
          ? await repository.create(commandId: commandId, draft: draft)
          : await repository.update(
              commandId: commandId,
              id: task.id,
              draft: draft,
              expectedRowVersion: task.rowVersion,
            );
      _tracker.completed();
      final saved = TaskSaved(
        outcome,
        wasEdit: task != null,
        taskId: outcome.entityId ?? task?.id ?? '',
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
    return const TaskRejected();
  }

  void _change(TaskFormState next) =>
      state = next.copyWith(dirty: _contentOf(next) != _initialContent);

  /// The user-visible content, normalised so that whitespace-only edits are
  /// not "changes".
  static Object _contentOf(TaskFormState s) => (
    s.title.trim(),
    s.description.trim(),
    s.priority,
    s.dueDate,
    s.tags.join('\u0000'),
  );

  Map<String, String> _without(String field) =>
      Map<String, String>.of(state.fieldErrors)..remove(field);
}

/// Provider of a task form; auto-disposed with its screen.
final taskFormProvider = NotifierProvider.autoDispose
    .family<TaskFormController, TaskFormState, TaskFormArgs>(
      TaskFormController.new,
    );
