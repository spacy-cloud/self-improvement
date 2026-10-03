import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/tasks/application/task_form_controller.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/features/tasks/domain/task_tag_suggestions.dart';
import 'package:self_improvement/features/tasks/domain/task_tags.dart';
import 'package:self_improvement/features/tasks/domain/task_validation.dart';
import 'package:self_improvement/features/tasks/presentation/task_row.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_routes.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_widgets.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';

/// "Neue Aufgabe" (new) and "Aufgabe bearbeiten" (with [taskId]).
class TaskFormScreen extends ConsumerWidget {
  const TaskFormScreen({this.taskId, super.key});

  /// The task to edit, or null for a new one.
  final String? taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = taskId;
    if (id == null) {
      return const _TaskForm(
        key: ValueKey('task-create'),
        args: TaskFormArgs.create(),
      );
    }
    return _EditLoader(taskId: id);
  }
}

/// Loads the task once; later changes of its row (for example by an undo
/// elsewhere) never reset a form that is open.
class _EditLoader extends ConsumerStatefulWidget {
  const _EditLoader({required this.taskId});

  final String taskId;

  @override
  ConsumerState<_EditLoader> createState() => _EditLoaderState();
}

class _EditLoaderState extends ConsumerState<_EditLoader> {
  Task? _opened;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(taskProvider(widget.taskId));
    _opened ??= async.value;
    final opened = _opened;
    if (opened != null) {
      return _TaskForm(
        key: ValueKey('task-edit-${opened.id}'),
        args: TaskFormArgs.edit(opened),
      );
    }
    return AppScaffold.subpage(
      title: 'Aufgabe bearbeiten',
      onBack: () => backOrHome(context),
      body: async.when(
        loading: () => const TasksLoadingPlaceholder(),
        error: (error, stack) => ErrorState(
          onRetry: () => ref.invalidate(taskProvider(widget.taskId)),
        ),
        data: (task) => EmptyState(
          title: 'Aufgabe nicht gefunden',
          message: 'Diese Aufgabe gibt es nicht mehr.',
          actionLabel: 'Zu den Aufgaben',
          onAction: () => context.go(TaskRoutes.list),
        ),
      ),
    );
  }
}

class _TaskForm extends ConsumerStatefulWidget {
  const _TaskForm({required this.args, super.key});

  final TaskFormArgs args;

  @override
  ConsumerState<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends ConsumerState<_TaskForm> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  final TextEditingController _tag = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();

  TaskFormArgs get _args => widget.args;
  bool get _isEdit => _args.task != null;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(taskFormProvider(_args));
    _title = TextEditingController(text: initial.title);
    _description = TextEditingController(text: initial.description);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tag.dispose();
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  TaskFormController get _controller =>
      ref.read(taskFormProvider(_args).notifier);

  Future<void> _submit() async {
    if (!mounted) {
      return;
    }
    FocusScope.of(context).unfocus();
    final feedback = ref.read(feedbackServiceProvider);
    final router = GoRouter.of(context);
    final result = await _controller.submit();
    switch (result) {
      case TaskSaved():
        feedback.showSaved(result.message, undo: result.outcome.undo);
        if (router.canPop()) {
          router.pop();
        } else {
          router.go(TaskRoutes.list);
        }
      case TaskRejected():
        if (!mounted) {
          return;
        }
        final state = ref.read(taskFormProvider(_args));
        // The first invalid field takes the focus, so a screen reader reads
        // its label together with the hint.
        if (state.fieldErrors.containsKey(TaskFields.title)) {
          _titleFocus.requestFocus();
        } else if (state.fieldErrors.containsKey(TaskFields.description)) {
          _descriptionFocus.requestFocus();
        }
        final failure = state.submitFailure;
        if (failure == null) {
          return;
        }
        if (failure is ConflictFailure || failure is NotFoundFailure) {
          feedback.showError(failure.userMessage);
        } else {
          feedback.showError(
            'Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.',
            onRetry: () => unawaited(_submit()),
          );
        }
    }
  }

  Future<void> _delete() async {
    final task = _args.task!;
    final deleted = await confirmAndDeleteTask(context, task);
    if (deleted && mounted) {
      leaveTo(context, fallback: TaskRoutes.list);
    }
  }

  Future<void> _pickDueDate() async {
    final state = ref.read(taskFormProvider(_args));
    final today = ref.read(todayProvider);
    final initial = state.dueDate ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Fälligkeitsdatum',
    );
    if (picked == null || !mounted) {
      return;
    }
    _controller.setDueDate(LocalDate.fromDateTime(picked));
  }

  void _addTag([String? text]) {
    final result = _controller.addTag(text ?? _tag.text);
    if (result == TagAddResult.added && text == null) {
      _tag.clear();
    }
  }

  Future<void> _askToDiscard() async {
    final discard = await showConfirmationSheet(
      context,
      title: 'Änderungen verwerfen?',
      message: 'Deine Eingaben in diesem Formular gehen verloren.',
      confirmLabel: 'Verwerfen',
      cancelLabel: 'Weiter bearbeiten',
    );
    if (discard && mounted) {
      leaveTo(context, fallback: TaskRoutes.list);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taskFormProvider(_args));
    final today = ref.watch(todayProvider);
    final suggestions = suggestTags(
      ref.watch(tasksProvider).value ?? const <Task>[],
      state.tags,
    );
    final canSubmit = !state.submitting && (!_isEdit || state.dirty);

    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_askToDiscard());
        }
      },
      child: AppScaffold.subpage(
        title: _isEdit ? 'Aufgabe bearbeiten' : 'Neue Aufgabe',
        onBack: () => backOrHome(context),
        primaryAction: PrimaryButton(
          label: _isEdit ? 'Änderungen speichern' : 'Aufgabe speichern',
          onPressed: canSubmit ? () => unawaited(_submit()) : null,
          loading: state.submitting,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppTextField(
              label: 'Titel',
              requirementLabel: 'Pflichtfeld',
              controller: _title,
              focusNode: _titleFocus,
              hint: 'Zum Beispiel: Präsentation vorbereiten',
              maxLength: maxTaskTitleLength,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              errorText: state.fieldErrors[TaskFields.title],
              onChanged: _controller.setTitle,
            ),
            const SizedBox(height: 16),
            const FieldLabel(label: 'Priorität'),
            const SizedBox(height: 6),
            SegmentedChoice<TaskPriority>(
              semanticLabel: 'Priorität',
              selected: state.priority,
              onChanged: _controller.setPriority,
              options: <SegmentOption<TaskPriority>>[
                for (final priority in TaskPriority.values)
                  SegmentOption<TaskPriority>(
                    value: priority,
                    label: priority.label,
                    semanticLabel: 'Priorität ${priority.label}',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const FieldLabel(label: 'Fällig am', requirement: 'optional'),
            const SizedBox(height: 8),
            _DueDateChips(
              dueDate: state.dueDate,
              today: today,
              onChanged: _controller.setDueDate,
            ),
            const SizedBox(height: 8),
            _DateField(
              dueDate: state.dueDate,
              today: today,
              onTap: () => unawaited(_pickDueDate()),
            ),
            if (state.fieldErrors[TaskFields.dueDate] != null) ...<Widget>[
              const SizedBox(height: 8),
              FieldMessage(text: state.fieldErrors[TaskFields.dueDate]!),
            ],
            const SizedBox(height: 16),
            const FieldLabel(label: 'Tags', requirement: 'optional'),
            const SizedBox(height: 8),
            if (state.tags.isNotEmpty) ...<Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final tag in state.tags)
                    _TagChip(
                      tag: tag,
                      onRemove: () => _controller.removeTag(tag),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            AppTextField(
              label: 'Tag hinzufügen',
              controller: _tag,
              hint: 'Zum Beispiel: Schule',
              helperText:
                  'Bis zu $maxTagsPerTask Tags mit höchstens '
                  '$maxTagLength Zeichen.',
              textInputAction: TextInputAction.done,
              errorText: state.fieldErrors[TaskFields.tags],
              onChanged: (_) => _controller.clearTagError(),
              onSubmitted: (_) => _addTag(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SecondaryButton(
                label: 'Hinzufügen',
                icon: AppIcon.plus.data,
                expand: false,
                onPressed: _addTag,
              ),
            ),
            if (suggestions.isNotEmpty && state.canAddTag) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final tag in suggestions)
                    AppFilterChip(
                      label: '#$tag',
                      semanticLabel: 'Tag $tag hinzufügen',
                      selected: false,
                      onSelected: (_) => _addTag(tag),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            AppTextField(
              label: 'Beschreibung',
              requirementLabel: 'optional',
              controller: _description,
              focusNode: _descriptionFocus,
              hint: 'Zum Beispiel: Folien und Handout fertig machen',
              maxLength: maxTaskDescriptionLength,
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              errorText: state.fieldErrors[TaskFields.description],
              onChanged: _controller.setDescription,
            ),
            if (_isEdit) ...<Widget>[
              const SizedBox(height: 24),
              Center(
                child: SecondaryButton(
                  label: 'Aufgabe löschen',
                  icon: AppIcon.delete.data,
                  danger: true,
                  expand: false,
                  onPressed: state.submitting
                      ? null
                      : () => unawaited(_delete()),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Heute", "Morgen" and "Kein Datum" as quick choices of the due day.
class _DueDateChips extends StatelessWidget {
  const _DueDateChips({
    required this.dueDate,
    required this.today,
    required this.onChanged,
  });

  final LocalDate? dueDate;
  final LocalDate today;
  final ValueChanged<LocalDate?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Fällig am',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          AppChoiceChip(
            label: 'Heute',
            selected: dueDate == today,
            onSelected: (_) => onChanged(today),
          ),
          AppChoiceChip(
            label: 'Morgen',
            selected: dueDate == today.addDays(1),
            onSelected: (_) => onChanged(today.addDays(1)),
          ),
          AppChoiceChip(
            label: 'Kein Datum',
            selected: dueDate == null,
            onSelected: (_) => onChanged(null),
          ),
        ],
      ),
    );
  }
}

/// The chosen due day as a field that opens the date picker.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.dueDate,
    required this.today,
    required this.onTap,
  });

  final LocalDate? dueDate;
  final LocalDate today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final date = dueDate;
    final text = date == null
        ? 'Kein Datum gewählt'
        : (date.year == today.year
              ? formatDateLong(date)
              : '${formatDateLong(date)} ${date.year}');
    return Semantics(
      container: true,
      button: true,
      label: 'Fälligkeitsdatum wählen, $text',
      onTap: onTap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Material(
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.controlBorder,
            side: BorderSide(color: colors.borderInput, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            focusColor: colors.focus.withValues(alpha: 0.2),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      text,
                      style: AppTextStyles.bodyDefault.copyWith(
                        color: date == null
                            ? colors.textSecondary
                            : colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tag of the task; tapping it removes the tag.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag, required this.onRemove});

  final String tag;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      button: true,
      label: 'Tag $tag entfernen',
      onTap: onRemove,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSizes.touchMin,
          minWidth: AppSizes.touchMin,
        ),
        child: Material(
          color: colors.primaryTint,
          shape: StadiumBorder(
            side: BorderSide(color: colors.primaryButton, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onRemove,
            focusColor: colors.focus.withValues(alpha: 0.2),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      '#$tag',
                      style: AppTextStyles.bodyStrong.copyWith(
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(AppIcon.close.data, size: 16, color: colors.primaryText),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
