import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/presentation/habits_day_view.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_list_view.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_routes.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_widgets.dart';

/// The "Habits" tab: two views, the daily habits (with the week strip and the
/// one-tap check) and the task list. [showTasks] is true when the route is
/// `/habits?tab=tasks`; the selected view is also written back to the route so
/// a repeated deep link to the same tab always lands on it.
///
/// The app shell owns the bottom navigation, this screen only fills the page.
class HabitsTabScreen extends ConsumerStatefulWidget {
  const HabitsTabScreen({this.showTasks = false, super.key});

  /// True when the route is `/habits?tab=tasks` (tasks list selected).
  final bool showTasks;

  @override
  ConsumerState<HabitsTabScreen> createState() => _HabitsTabScreenState();
}

class _HabitsTabScreenState extends ConsumerState<HabitsTabScreen> {
  late bool _showTasks = widget.showTasks;

  @override
  void didUpdateWidget(HabitsTabScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showTasks != widget.showTasks) {
      _showTasks = widget.showTasks;
    }
  }

  void _select(bool showTasks) {
    if (_showTasks == showTasks) {
      return;
    }
    setState(() => _showTasks = showTasks);
    GoRouter.maybeOf(context)
        ?.go(showTasks ? TaskRoutes.list : HabitRoutes.tab);
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(habitsOverviewProvider).value;
    final openTasks = ref.watch(taskListProvider).value?.openCount;
    final habitsBadge = overview == null
        ? null
        : '${overview.doneCount}/${overview.totalCount}';
    return AppScaffold(
      title: 'Habits',
      safeAreaBottom: false,
      scrollable: false,
      padding: EdgeInsets.zero,
      actions: <Widget>[
        AppIconButton(
          icon: AppIcon.plus.data,
          filled: true,
          iconColor: context.tokens.colors.primaryText,
          semanticLabel: _showTasks
              ? 'Aufgabe hinzufügen'
              : 'Gewohnheit hinzufügen',
          onPressed: () =>
              context.push(_showTasks ? TaskRoutes.create : HabitRoutes.create),
        ),
      ],
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s8,
              AppSpacing.s16,
              AppSpacing.s8,
            ),
            child: SegmentedChoice<bool>(
              semanticLabel: 'Ansicht',
              selected: _showTasks,
              onChanged: _select,
              options: <SegmentOption<bool>>[
                SegmentOption<bool>(
                  value: true,
                  label: 'Aufgaben',
                  badge: openTasks == null ? null : '$openTasks offen',
                ),
                SegmentOption<bool>(
                  value: false,
                  label: 'Gewohnheiten',
                  badge: habitsBadge,
                  semanticLabel: overview == null
                      ? 'Gewohnheiten'
                      : 'Gewohnheiten, ${overview.progressText}',
                ),
              ],
            ),
          ),
          Expanded(
            child: _showTasks ? const TasksListView() : const HabitsDayView(),
          ),
        ],
      ),
    );
  }
}
