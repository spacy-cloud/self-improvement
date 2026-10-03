import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/tasks/application/task_actions_controller.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task_list.dart';
import 'package:self_improvement/features/tasks/presentation/action_feedback.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_routes.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_widgets.dart';

/// The `tasks` card of the dashboard (full width): up to three open tasks that
/// apply today, each with its own checkbox, so a task is completed with ONE
/// tap, without opening it. Overdue tasks say so in words. Future tasks only
/// show up in the list ("Alle").
class TasksDashboardCard extends ConsumerWidget {
  const TasksDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(dashboardTasksProvider);
    return tasks.when(
      loading: () => const _CardFrame(
        subtitle: null,
        children: <Widget>[SizedBox(height: 48)],
      ),
      error: (error, stack) =>
          ErrorState(onRetry: () => ref.invalidate(tasksProvider)),
      data: (data) => _CardFrame(
        subtitle: data.applicableOpenCount == 0
            ? 'Heute nichts offen'
            : (data.applicableOpenCount == 1
                  ? '1 Aufgabe für heute'
                  : '${data.applicableOpenCount} Aufgaben für heute'),
        quickAction: data.items.isEmpty
            ? MetricCardAction(
                label: 'Aufgabe anlegen',
                icon: AppIcon.plus.data,
                accent: AppAccent.habits,
                onPressed: () => context.push(TaskRoutes.create),
              )
            : null,
        children: <Widget>[
          if (data.items.isEmpty)
            const _EmptyBody()
          else ...<Widget>[
            for (final item in data.items) _CardTaskRow(item: item),
            if (data.moreCount > 0) _MoreRow(count: data.moreCount),
          ],
        ],
      ),
    );
  }
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({
    required this.subtitle,
    required this.children,
    this.quickAction,
  });

  final String? subtitle;
  final List<Widget> children;
  final Widget? quickAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            container: true,
            button: true,
            label: subtitle == null ? 'Aufgaben' : 'Aufgaben, $subtitle',
            hint: 'Öffnet die Aufgabenliste',
            onTap: () => context.go(TaskRoutes.list),
            excludeSemantics: true,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => context.go(TaskRoutes.list),
                focusColor: colors.focus.withValues(alpha: 0.2),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSizes.touchMin,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
                    child: Row(
                      children: <Widget>[
                        AppIconTile(
                          icon: AppIcon.task.data,
                          accent: AppAccent.habits,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Aufgaben',
                                style: AppTextStyles.titleCard.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle!,
                                  style: AppTextStyles.captionDefault.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          AppIcon.chevronRight.data,
                          size: 20,
                          color: colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ...children,
          if (quickAction != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: quickAction,
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        'Für heute ist nichts offen. Neue Aufgaben erscheinen hier.',
        style: AppTextStyles.bodyRegular.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final text = count == 1 ? 'und 1 weitere' : 'und $count weitere';
    return Semantics(
      container: true,
      button: true,
      label: '$text Aufgaben, öffnet die Aufgabenliste',
      onTap: () => context.go(TaskRoutes.list),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => context.go(TaskRoutes.list),
            focusColor: colors.focus.withValues(alpha: 0.2),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  text,
                  style: AppTextStyles.bodyStrong.copyWith(
                    color: colors.primaryText,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One task of the card: its checkbox and the title with the due text.
class _CardTaskRow extends ConsumerWidget {
  const _CardTaskRow({required this.item});

  final TaskListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final task = item.task;
    final busy = ref.watch(
      taskActionsProvider.select((state) => state.isBusy(task.id)),
    );
    final container = ProviderScope.containerOf(context, listen: false);
    final dueText = item.dueText;
    final overdue = item.overdue;
    final stacked = isLargeText(context);
    final checkbox = RoundCheckbox(
      value: false,
      semanticLabel: task.title,
      checkedStateLabel: 'erledigt',
      uncheckedStateLabel: 'offen',
      onChanged: busy
          ? null
          : (value) => unawaited(
              setTaskCompleted(container, task.id, completed: value),
            ),
    );
    final body = TappableBody(
      onTap: () => context.push(TaskRoutes.edit(task.id)),
      semanticLabel: item.semanticsLabel,
      semanticHint: 'Öffnet die Aufgabe zum Bearbeiten',
      child: Padding(
        padding: EdgeInsets.fromLTRB(stacked ? 16 : 4, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              task.title,
              style: AppTextStyles.bodyStrong.copyWith(
                color: colors.textPrimary,
              ),
            ),
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
          ],
        ),
      ),
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 10),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: checkbox,
            ),
          ),
          body,
        ],
      );
    }
    return Row(
      children: <Widget>[
        const SizedBox(width: 10),
        checkbox,
        Expanded(child: body),
      ],
    );
  }
}
