import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/tasks/application/task_actions_controller.dart';
import 'package:self_improvement/features/tasks/domain/german_dates.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_list.dart';
import 'package:self_improvement/features/tasks/presentation/action_feedback.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_routes.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_widgets.dart';

/// Asks for confirmation and deletes [task] with undo. Shared by the list menu
/// and the edit screen. Returns whether the task was deleted.
Future<bool> confirmAndDeleteTask(BuildContext context, Task task) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final confirmed = await showConfirmationSheet(
    context,
    title: 'Aufgabe löschen?',
    message:
        '„${task.title}“ wird entfernt. Du kannst es direkt danach '
        'rückgängig machen.',
    confirmLabel: 'Löschen',
  );
  if (!confirmed) {
    return false;
  }
  return deleteTaskWithFeedback(container, task.id);
}

enum _TaskMenuAction { edit, toggleCompleted, delete }

/// One task of the list: the round checkbox (completion as a desired state),
/// the body with priority, due text and tags, and the more-actions menu.
///
/// The menu offers every action of a swipe (complete or reopen, edit, delete),
/// so nothing depends on a gesture. An overdue task is marked by the word
/// "Überfällig" and a red outline. With large text the controls sit in their
/// own line above the title, so the title keeps the full width.
class TaskRow extends ConsumerWidget {
  const TaskRow({required this.item, super.key});

  final TaskListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final task = item.task;
    final busy = ref.watch(
      taskActionsProvider.select((state) => state.isBusy(task.id)),
    );
    final container = ProviderScope.containerOf(context, listen: false);
    final overdue = item.overdue;
    final spokenTags = task.tags.isEmpty
        ? ''
        : ', Tags: ${task.tags.join(', ')}';

    final checkbox = RoundCheckbox(
      value: task.isCompleted,
      semanticLabel: task.title,
      checkedStateLabel: 'erledigt',
      uncheckedStateLabel: 'offen',
      onChanged: busy
          ? null
          : (value) => unawaited(
              setTaskCompleted(container, task.id, completed: value),
            ),
    );
    final menu = PopupMenuButton<_TaskMenuAction>(
      tooltip: 'Weitere Aktionen: ${task.title}',
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(AppSizes.touchMin),
      ),
      icon: Icon(Icons.more_vert_rounded, color: colors.textSecondary),
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      popUpAnimationStyle: AppMotion.surfaceStyleOf(context),
      onSelected: (action) => _onAction(context, container, action),
      itemBuilder: (context) => <PopupMenuEntry<_TaskMenuAction>>[
        _entry(_TaskMenuAction.edit, 'Bearbeiten', colors.textPrimary),
        _entry(
          _TaskMenuAction.toggleCompleted,
          task.isCompleted ? 'Wieder öffnen' : 'Als erledigt markieren',
          colors.textPrimary,
        ),
        _entry(_TaskMenuAction.delete, 'Löschen', colors.error),
      ],
    );
    final stacked = isLargeText(context);
    final body = TappableBody(
      onTap: () => context.push(TaskRoutes.edit(task.id)),
      semanticLabel: '${item.semanticsLabel}$spokenTags',
      semanticHint: 'Öffnet die Aufgabe zum Bearbeiten',
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          stacked ? 14 : 4,
          10,
          stacked ? 14 : 4,
          10,
        ),
        child: _TaskTexts(item: item),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: AppCard(
        padding: EdgeInsets.zero,
        borderColor: overdue ? colors.error : null,
        borderWidth: overdue ? 1.5 : 1,
        child: ColoredBox(
          color: overdue ? colors.errorTint : Colors.transparent,
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const SizedBox(width: 6),
                        checkbox,
                        const Spacer(),
                        menu,
                      ],
                    ),
                    body,
                  ],
                )
              : Row(
                  children: <Widget>[
                    const SizedBox(width: 6),
                    checkbox,
                    Expanded(child: body),
                    menu,
                  ],
                ),
        ),
      ),
    );
  }

  PopupMenuItem<_TaskMenuAction> _entry(
    _TaskMenuAction action,
    String label,
    Color color,
  ) => PopupMenuItem<_TaskMenuAction>(
    value: action,
    child: Text(label, style: AppTextStyles.bodyDefault.copyWith(color: color)),
  );

  void _onAction(
    BuildContext context,
    ProviderContainer container,
    _TaskMenuAction action,
  ) {
    final task = item.task;
    switch (action) {
      case _TaskMenuAction.edit:
        unawaited(context.push(TaskRoutes.edit(task.id)));
      case _TaskMenuAction.toggleCompleted:
        unawaited(
          setTaskCompleted(container, task.id, completed: !task.isCompleted),
        );
      case _TaskMenuAction.delete:
        unawaited(confirmAndDeleteTask(context, task));
    }
  }
}

/// Title and the meta line (priority, due text, completion day, tags).
class _TaskTexts extends StatelessWidget {
  const _TaskTexts({required this.item});

  final TaskListItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final task = item.task;
    final overdue = item.overdue;
    final dueText = item.dueText;
    final completedOn = task.completedLocalDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          task.title,
          style: AppTextStyles.titleCard.copyWith(
            color: task.isCompleted ? colors.textSecondary : colors.textPrimary,
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            PriorityPill(priority: task.priority),
            if (dueText != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (overdue) ...<Widget>[
                    Icon(AppIcon.error.data, size: 14, color: colors.error),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      dueText,
                      style: overdue
                          ? AppTextStyles.captionStrong.copyWith(
                              color: colors.error,
                            )
                          : AppTextStyles.captionDefault.copyWith(
                              color: colors.textSecondary,
                            ),
                    ),
                  ),
                ],
              ),
            if (task.isCompleted && completedOn != null)
              Text(
                'Erledigt am ${formatGermanDate(completedOn)}',
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            for (final tag in task.tags)
              Text(
                '#$tag',
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
