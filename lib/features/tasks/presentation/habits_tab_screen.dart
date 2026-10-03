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
            child: _ViewSwitch(
              showTasks: _showTasks,
              tasksBadge: openTasks == null ? null : '$openTasks offen',
              habitsBadge: habitsBadge,
              habitsSemanticLabel: overview == null
                  ? 'Gewohnheiten'
                  : 'Gewohnheiten, ${overview.progressText}',
              onChanged: _select,
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

/// The two views of the tab as a segmented control. Next to each other like
/// the design system's `PeriodSelector`; with large text the two segments are
/// stacked, so neither label breaks inside a word.
class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({
    required this.showTasks,
    required this.tasksBadge,
    required this.habitsBadge,
    required this.habitsSemanticLabel,
    required this.onChanged,
  });

  final bool showTasks;
  final String? tasksBadge;
  final String? habitsBadge;
  final String habitsSemanticLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final tasks = _Segment(
      label: 'Aufgaben',
      badge: tasksBadge,
      semanticLabel: tasksBadge == null ? 'Aufgaben' : 'Aufgaben, $tasksBadge',
      selected: showTasks,
      onTap: () => onChanged(true),
    );
    final habits = _Segment(
      label: 'Gewohnheiten',
      badge: habitsBadge,
      semanticLabel: habitsSemanticLabel,
      selected: !showTasks,
      onTap: () => onChanged(false),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Ansicht',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.track,
          borderRadius: BorderRadius.circular(AppRadii.segmentOuter),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: isLargeText(context)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[tasks, const SizedBox(height: 4), habits],
                )
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: tasks),
                      const SizedBox(width: 4),
                      Expanded(child: habits),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.badge,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? badge;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    const radius = BorderRadius.all(Radius.circular(AppRadii.segmentInner));
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: motion.fast,
        constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
        decoration: BoxDecoration(
          color: selected ? colors.surface : Colors.transparent,
          borderRadius: radius,
          boxShadow: selected ? AppShadows.segment : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            focusColor: colors.focus.withValues(alpha: 0.2),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 12,
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: <Widget>[
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style:
                          (selected
                                  ? AppTextStyles.bodyStrong
                                  : AppTextStyles.bodyDefault)
                              .copyWith(
                                color: selected
                                    ? colors.textPrimary
                                    : colors.textSecondary,
                              ),
                    ),
                    if (badge != null)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: selected
                              ? colors.primaryTint
                              : colors.surfaceMuted,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          child: Text(
                            badge!,
                            style: AppTextStyles.captionStrong.copyWith(
                              color: selected
                                  ? colors.primaryText
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
