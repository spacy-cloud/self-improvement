import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task_list.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/features/tasks/presentation/task_row.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_routes.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_widgets.dart';

/// The tasks view of the tab: the status segments Offen / Erledigt / Alle, the
/// search with the priority filter, and the tasks in the defined order (high
/// priority first, then due day, then creation). Rows are built lazily.
class TasksListView extends ConsumerStatefulWidget {
  const TasksListView({super.key});

  @override
  ConsumerState<TasksListView> createState() => _TasksListViewState();
}

class _TasksListViewState extends ConsumerState<TasksListView> {
  late final TextEditingController _query = TextEditingController(
    text: ref.read(taskListControllerProvider).query,
  );
  bool _searchOpen = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  TaskListController get _controller =>
      ref.read(taskListControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    ref.listen(taskListControllerProvider.select((f) => f.query), (
      previous,
      next,
    ) {
      if (_query.text != next) {
        _query.text = next;
      }
    });
    final filter = ref.watch(taskListControllerProvider);
    final async = ref.watch(taskListProvider);
    // A narrowing search or priority keeps the panel open: a hidden filter
    // would silently shorten the list.
    final panelOpen = _searchOpen || filter.isNarrowed;
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            AppSpacing.s8,
            AppSpacing.s16,
            AppSpacing.s8,
          ),
          sliver: SliverToBoxAdapter(
            child: _Controls(
              filter: filter,
              panelOpen: panelOpen,
              queryController: _query,
              onToggleSearch: () {
                if (filter.isNarrowed) {
                  _controller.clearNarrowing();
                  setState(() => _searchOpen = false);
                } else {
                  setState(() => _searchOpen = !_searchOpen);
                }
              },
            ),
          ),
        ),
        ...async.when(
          loading: () => const <Widget>[
            SliverToBoxAdapter(child: TasksLoadingPlaceholder()),
          ],
          error: (error, stack) => <Widget>[
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.s16),
              sliver: SliverToBoxAdapter(
                child: ErrorState(onRetry: () => ref.invalidate(tasksProvider)),
              ),
            ),
          ],
          data: (view) => _dataSlivers(context, view),
        ),
      ],
    );
  }

  List<Widget> _dataSlivers(BuildContext context, TaskListView view) {
    final reason = view.emptyReason;
    if (reason != null) {
      return <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            AppSpacing.s8,
            AppSpacing.s16,
            AppSpacing.s24,
          ),
          sliver: SliverToBoxAdapter(child: _emptyState(context, reason)),
        ),
      ];
    }
    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s16,
          AppSpacing.s4,
          AppSpacing.s16,
          AppSpacing.s24,
        ),
        sliver: SliverList.builder(
          itemCount: view.items.length,
          itemBuilder: (context, index) => TaskRow(
            key: ValueKey<String>(view.items[index].task.id),
            item: view.items[index],
          ),
        ),
      ),
    ];
  }

  Widget _emptyState(BuildContext context, TaskListEmptyReason reason) {
    return switch (reason) {
      TaskListEmptyReason.noTasks => EmptyState(
        title: 'Noch keine Aufgaben',
        message: 'Lege deine erste Aufgabe an, um deinen Tag zu planen.',
        icon: AppIcon.task,
        accent: AppAccent.habits,
        actionLabel: 'Aufgabe anlegen',
        onAction: () => context.push(TaskRoutes.create),
      ),
      TaskListEmptyReason.noMatches => EmptyState(
        title: 'Keine Treffer',
        message: 'Zu deiner Suche oder dem Filter gibt es keine Aufgabe.',
        icon: AppIcon.analysis,
        accent: AppAccent.habits,
        actionLabel: 'Suche zurücksetzen',
        onAction: () {
          _controller.clearNarrowing();
          setState(() => _searchOpen = false);
        },
      ),
      TaskListEmptyReason.nothingOpen => EmptyState(
        title: 'Alles erledigt',
        message: 'Du hast keine offenen Aufgaben. Genieß den freien Kopf.',
        icon: AppIcon.check,
        accent: AppAccent.habits,
        actionLabel: 'Aufgabe anlegen',
        onAction: () => context.push(TaskRoutes.create),
      ),
      TaskListEmptyReason.nothingCompleted => const EmptyState(
        title: 'Noch nichts erledigt',
        message: 'Erledigte Aufgaben erscheinen hier.',
        icon: AppIcon.task,
        accent: AppAccent.habits,
      ),
    };
  }
}

/// The status chips with the search button and, when open, the search field
/// and the priority filter.
class _Controls extends ConsumerWidget {
  const _Controls({
    required this.filter,
    required this.panelOpen,
    required this.queryController,
    required this.onToggleSearch,
  });

  final TaskFilter filter;
  final bool panelOpen;
  final TextEditingController queryController;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(taskListControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final status in TaskStatusFilter.values)
                    AppChoiceChip(
                      label: status.label,
                      selected: filter.status == status,
                      onSelected: (_) => controller.setStatus(status),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppIconButton(
              icon: AppIcon.analysis.data,
              filled: true,
              semanticLabel: filter.isNarrowed
                  ? 'Suche und Filter zurücksetzen'
                  : (panelOpen
                        ? 'Suche und Filter ausblenden'
                        : 'Suche und Filter einblenden'),
              iconColor: panelOpen ? context.tokens.colors.primaryText : null,
              onPressed: onToggleSearch,
            ),
          ],
        ),
        if (panelOpen) ...<Widget>[
          const SizedBox(height: 12),
          AppTextField(
            label: 'Suche',
            hint: 'Titel oder Beschreibung',
            controller: queryController,
            textInputAction: TextInputAction.search,
            onChanged: controller.setQuery,
          ),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Priorität',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                AppChoiceChip(
                  label: 'Alle Prioritäten',
                  selected: filter.priority == null,
                  onSelected: (_) => controller.setPriority(null),
                ),
                for (final priority in TaskPriority.values.reversed)
                  AppChoiceChip(
                    label: priority.label,
                    semanticLabel: 'Priorität ${priority.label}',
                    selected: filter.priority == priority,
                    onSelected: (_) => controller.setPriority(priority),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
