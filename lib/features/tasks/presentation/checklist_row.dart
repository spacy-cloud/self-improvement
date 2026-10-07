import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/tasks/application/habit_actions_controller.dart';
import 'package:self_improvement/features/tasks/application/task_actions_controller.dart';
import 'package:self_improvement/features/tasks/domain/today_checklist.dart';
import 'package:self_improvement/features/tasks/presentation/action_feedback.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_routes.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_widgets.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Height of a row of the card: the 48 px box and 8 px above and below.
const double checklistRowMinHeight = 64;

/// The kind of an entry as a small chip: icon and word, never colour alone.
/// Decorative for screen readers: the spoken label of the row names the kind.
///
/// A task is green on the green tint, a habit is violet (the habits accent) on
/// the quiet surface, as in the design.
class EntryTypeChip extends StatelessWidget {
  const EntryTypeChip({required this.kind, super.key});

  final ChecklistKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final isTask = kind == ChecklistKind.task;
    final background = isTask ? colors.primaryTint : colors.surfaceMuted;
    final foreground = isTask ? colors.primaryText : colors.moduleHabits;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 3, 10, 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                isTask ? AppIcon.task.data : AppIcon.habit.data,
                size: 12,
                color: foreground,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  kind.label,
                  style: AppTextStyles.captionStrong.copyWith(
                    color: foreground,
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

/// One row of the Home card: the box, the title with its line, the kind chip.
///
/// The box is square for a task and round for a habit (the shape tells them
/// apart without colour). Tapping the box sets the DESIRED state through the
/// commands the lists use (`setTaskCompleted`, `setHabitChecked`): idempotent,
/// with a command id, a busy lock against a double tap and "Rückgängig" in the
/// snackbar. Tapping the rest of the row opens the task or the habit. With
/// [readOnly] (a day that cannot be changed) the box only shows the state.
///
/// With large text the box and the chip share the first line and the title
/// gets the full width below, so no word breaks.
class ChecklistRow extends ConsumerWidget {
  const ChecklistRow({
    required this.entry,
    required this.today,
    this.readOnly = false,
    super.key,
  });

  final ChecklistEntry entry;

  /// The day the habit checks belong to.
  final LocalDate today;

  /// Shows the state only: the box cannot be changed.
  final bool readOnly;

  bool get _isTask => entry.kind == ChecklistKind.task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = _isTask
        ? ref.watch(taskActionsProvider.select((s) => s.isBusy(entry.id)))
        : ref.watch(
            habitActionsProvider.select((s) => s.isCheckBusy(entry.id, today)),
          );
    final container = ProviderScope.containerOf(context, listen: false);
    final enabled = !readOnly && entry.editable && !busy;
    final checkbox = RoundCheckbox(
      value: entry.done,
      squared: _isTask,
      semanticLabel: entry.checkboxLabel,
      checkedStateLabel: entry.checkedStateLabel,
      uncheckedStateLabel: entry.uncheckedStateLabel,
      onChanged: enabled
          ? (value) => unawaited(_set(container, checked: value))
          : null,
    );
    final texts = _EntryTexts(entry: entry);
    final chip = EntryTypeChip(kind: entry.kind);
    void open() => unawaited(
      context.push(
        _isTask ? TaskRoutes.edit(entry.id) : HabitRoutes.detail(entry.id),
      ),
    );
    final label = entry.semanticsLabel;
    final hint = _isTask
        ? 'Öffnet die Aufgabe zum Bearbeiten'
        : 'Öffnet die Gewohnheit';

    if (isLargeText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            // The box has 10 px of room around it: its edge lines up with the
            // title below.
            padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 12, 0),
            child: Row(children: <Widget>[checkbox, const Spacer(), chip]),
          ),
          TappableBody(
            onTap: open,
            semanticLabel: label,
            semanticHint: hint,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 14, 12),
              child: texts,
            ),
          ),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 14),
          child: checkbox,
        ),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: checklistRowMinHeight),
            child: TappableBody(
              onTap: open,
              semanticLabel: label,
              semanticHint: hint,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(child: texts),
                    const SizedBox(width: 12),
                    chip,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _set(ProviderContainer container, {required bool checked}) =>
      _isTask
      ? setTaskCompleted(container, entry.id, completed: checked)
      : setHabitChecked(container, entry.id, today, checked: checked);
}

/// The title (struck through and quiet when done) and the line below it. An
/// overdue task says so in words and with an icon next to the red colour.
class _EntryTexts extends StatelessWidget {
  const _EntryTexts({required this.entry});

  final ChecklistEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final subtitle = entry.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          entry.title,
          style: AppTextStyles.bodyStrong.copyWith(
            color: entry.done ? colors.textSecondary : colors.textPrimary,
            decoration: entry.done ? TextDecoration.lineThrough : null,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: entry.overdue
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(AppIcon.error.data, size: 14, color: colors.error),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          subtitle,
                          style: AppTextStyles.captionStrong.copyWith(
                            color: colors.error,
                          ),
                        ),
                      ),
                    ],
                  )
                : Text(
                    subtitle,
                    style: AppTextStyles.captionDefault.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
          ),
      ],
    );
  }
}
