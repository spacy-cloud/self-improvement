import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/application/today_checklist_providers.dart';
import 'package:self_improvement/features/tasks/domain/today_checklist.dart';
import 'package:self_improvement/features/tasks/presentation/checklist_row.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_routes.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The `tasks` card of the dashboard (full width), "Heute abhaken" (BS-110):
/// what is to be ticked off today, tasks and habits in one list.
///
/// Tasks and habits are two kinds and look different (square and round box,
/// a type chip, the series of a habit). Each row ticks with ONE tap, without
/// opening the record, through the same commands as the lists; the state comes
/// from the same streams as the habits tab and the task list, so a check made
/// anywhere shows up everywhere. A completed task or a checked habit stays in
/// the list for the rest of the day (struck through), so a mistake is visible
/// and can be undone with the box. The card lists at most three open tasks
/// (`dashboardTaskLimit`) and [dashboardHabitLimit] habits; the rest is one
/// line per kind that opens its list.
///
/// With [readOnly] the card shows the state and offers neither a tick nor the
/// actions that create something.
///
/// With a [day] (a day that is not today, BS-93) it is the card of that day, and
/// read-only: the tasks completed on that day and the habits of that day with
/// their state (`buildDayChecklist`). It is then called "Aufgaben und
/// Gewohnheiten", not "Heute abhaken", and a box cannot be changed here: a
/// correction for an earlier day is made in the habits tab or the task list.
class TasksDashboardCard extends ConsumerWidget {
  const TasksDashboardCard({super.key, this.readOnly = false, this.day});

  /// Shows the state only: no box can be changed, nothing can be created.
  final bool readOnly;

  /// The day shown; `null` is today.
  final LocalDate? day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = this.day;
    final readOnly = this.readOnly || day != null;
    final checklist = day == null
        ? ref.watch(todayChecklistProvider)
        : ref.watch(dayChecklistProvider(day));
    return checklist.when(
      loading: () => _CardFrame(
        title: _title(day),
        progress: null,
        allDone: false,
        children: const <Widget>[SizedBox(height: 48)],
      ),
      error: (error, stack) => ErrorState(
        onRetry: () {
          ref
            ..invalidate(tasksProvider)
            ..invalidate(habitsProvider)
            ..invalidate(habitCheckIndexProvider);
        },
      ),
      data: (data) => _CardFrame(
        title: _title(day),
        progress: data.isEmpty ? null : data.progressText,
        allDone: data.allDone,
        children: <Widget>[
          if (data.isEmpty)
            _EmptyBody(readOnly: readOnly, pastDay: day != null)
          else ...<Widget>[
            for (final entry in data.tasks)
              ChecklistRow(
                key: ValueKey<String>('checklist-task-${entry.id}'),
                entry: entry,
                today: data.today,
                readOnly: readOnly,
              ),
            if (data.moreTasks > 0)
              _MoreRow(kind: ChecklistKind.task, count: data.moreTasks),
            for (final entry in data.habits)
              ChecklistRow(
                key: ValueKey<String>('checklist-habit-${entry.id}'),
                entry: entry,
                today: data.today,
                readOnly: readOnly,
              ),
            if (data.moreHabits > 0)
              _MoreRow(kind: ChecklistKind.habit, count: data.moreHabits),
            if (data.habitPresence != HabitPresence.active && !readOnly)
              _NoHabitHint(presence: data.habitPresence),
          ],
        ],
      ),
    );
  }
}

/// The heading of the card: the live card is "Heute abhaken", the card of
/// another day names what it holds.
String _title(LocalDate? day) =>
    day == null ? 'Heute abhaken' : 'Aufgaben und Gewohnheiten';

/// The heading with the count outside the card and the card with the rows.
class _CardFrame extends StatelessWidget {
  const _CardFrame({
    required this.title,
    required this.progress,
    required this.allDone,
    required this.children,
  });

  final String title;
  final String? progress;
  final bool allDone;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 2,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: AppTextStyles.titleSection.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (progress != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (allDone) ...<Widget>[
                      ExcludeSemantics(
                        child: Icon(
                          AppIcon.check.data,
                          size: 14,
                          color: colors.primaryText,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      progress!,
                      style: AppTextStyles.captionDefault.copyWith(
                        color: allDone
                            ? colors.primaryText
                            : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppListGroup(dividerIndent: 0, children: children),
      ],
    );
  }
}

/// Neither a task nor a habit for the day.
class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.readOnly, required this.pastDay});

  final bool readOnly;

  /// The card of a day that is not today: it says what that day had.
  final bool pastDay;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            pastDay
                ? 'An diesem Tag wurde keine Aufgabe erledigt, und es gab '
                      'keine Gewohnheit.'
                : 'Für heute ist nichts offen. Neue Aufgaben und Gewohnheiten '
                      'erscheinen hier.',
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
          if (!readOnly) ...<Widget>[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: <Widget>[
                MetricCardAction(
                  label: 'Aufgabe anlegen',
                  icon: AppIcon.plus.data,
                  accent: AppAccent.habits,
                  onPressed: () => unawaited(context.push(TaskRoutes.create)),
                ),
                MetricCardAction(
                  label: 'Gewohnheit anlegen',
                  icon: AppIcon.plus.data,
                  accent: AppAccent.habits,
                  onPressed: () => unawaited(context.push(HabitRoutes.create)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The way to the first habit: shown while no habit applies today.
class _NoHabitHint extends StatelessWidget {
  const _NoHabitHint({required this.presence});

  final HabitPresence presence;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final none = presence == HabitPresence.none;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            none ? 'Noch keine Gewohnheit' : 'Keine aktive Gewohnheit',
            style: AppTextStyles.bodyStrong.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            none
                ? 'Lege eine tägliche Gewohnheit an und hake sie hier mit '
                      'einem Tipp ab.'
                : 'Alle deine Gewohnheiten sind archiviert. Lege eine neue an.',
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
          MetricCardAction(
            label: 'Gewohnheit anlegen',
            icon: AppIcon.plus.data,
            accent: AppAccent.habits,
            onPressed: () => unawaited(context.push(HabitRoutes.create)),
          ),
        ],
      ),
    );
  }
}

/// "und 2 weitere Aufgaben": what the card does not list, one line per kind,
/// opens the list of that kind.
class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.kind, required this.count});

  final ChecklistKind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final isTask = kind == ChecklistKind.task;
    final noun = switch ((isTask, count)) {
      (true, 1) => 'Aufgabe',
      (true, _) => 'Aufgaben',
      (false, 1) => 'Gewohnheit',
      (false, _) => 'Gewohnheiten',
    };
    final text = 'und $count weitere $noun';
    final target = isTask ? TaskRoutes.list : HabitRoutes.tab;
    return Semantics(
      container: true,
      button: true,
      label:
          '$count weitere $noun, öffnet die '
          '${isTask ? 'Aufgabenliste' : 'Gewohnheitenliste'}',
      onTap: () => context.go(target),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => context.go(target),
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
