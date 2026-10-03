import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart' hide HabitIcon;
import 'package:self_improvement/features/tasks/application/habit_actions_controller.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_overview.dart';
import 'package:self_improvement/features/tasks/domain/habit_validation.dart';
import 'package:self_improvement/features/tasks/presentation/action_feedback.dart';
import 'package:self_improvement/features/tasks/presentation/habit_dialogs.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_routes.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_widgets.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// The detail of one habit: series and quota, the history of the last 30 days
/// (as a grid or as a list) with the correction of past days, and the actions
/// edit, archive and delete.
class HabitDetailScreen extends ConsumerWidget {
  const HabitDetailScreen({required this.habitId, super.key});

  final String habitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(habitDetailProvider(habitId));
    return async.when(
      loading: () => AppScaffold.subpage(
        title: 'Gewohnheit',
        onBack: () => backOrHome(context),
        body: const TasksLoadingPlaceholder(),
      ),
      error: (error, stack) => AppScaffold.subpage(
        title: 'Gewohnheit',
        onBack: () => backOrHome(context),
        body: ErrorState(
          onRetry: () {
            ref
              ..invalidate(habitProvider(habitId))
              ..invalidate(habitCheckIndexProvider);
          },
        ),
      ),
      data: (detail) => detail == null
          ? AppScaffold.subpage(
              title: 'Gewohnheit',
              onBack: () => backOrHome(context),
              body: EmptyState(
                title: 'Gewohnheit nicht gefunden',
                message: 'Diese Gewohnheit gibt es nicht mehr.',
                actionLabel: 'Zu den Gewohnheiten',
                onAction: () => context.go(HabitRoutes.tab),
              ),
            )
          : _DetailBody(detail: detail),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.detail});

  final HabitDetail detail;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  bool _asList = false;

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final habit = detail.habit;
    final colors = context.tokens.colors;
    final visual = habitVisual(habit.icon);
    final canEdit = !detail.ended;
    final canArchive = !detail.ended && !detail.archivePending;
    return AppScaffold.subpage(
      title: habit.title,
      onBack: () => backOrHome(context),
      actions: <Widget>[
        if (canEdit)
          AppIconButton(
            icon: AppIcon.edit.data,
            filled: true,
            semanticLabel: 'Gewohnheit bearbeiten',
            onPressed: () => context.push(HabitRoutes.edit(habit.id)),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _StatsCard(detail: detail),
          const SizedBox(height: 14),
          _HistoryCard(
            detail: detail,
            accent: visual.accent,
            asList: _asList,
            onToggleView: () => setState(() => _asList = !_asList),
          ),
          const SizedBox(height: 14),
          AppListGroup(
            children: <Widget>[
              if (canEdit)
                EntryListTile(
                  title: 'Bearbeiten',
                  icon: AppIcon.edit.data,
                  accent: AppAccent.habits,
                  onTap: () => context.push(HabitRoutes.edit(habit.id)),
                ),
              if (canArchive)
                EntryListTile(
                  title: 'Archivieren',
                  icon: Icons.archive_outlined,
                  accent: AppAccent.habits,
                  onTap: () =>
                      unawaited(confirmAndArchiveHabit(context, habit)),
                ),
              EntryListTile(
                title: 'Löschen',
                icon: AppIcon.delete.data,
                accent: AppAccent.error,
                destructive: true,
                onTap: () => unawaited(_delete(context, habit)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              detail.ended
                  ? 'Diese Gewohnheit ist archiviert und zählt nicht mehr. '
                        'Der Verlauf bleibt erhalten.'
                  : (detail.archivePending
                        ? 'Diese Gewohnheit zählt heute noch. Ab morgen ist '
                              'sie archiviert, der Verlauf bleibt erhalten.'
                        : 'Archivierte Gewohnheiten zählen ab morgen nicht '
                              'mehr. Der Verlauf bleibt erhalten.'),
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, Habit habit) async {
    final deleted = await confirmAndDeleteHabit(context, habit);
    if (deleted && context.mounted) {
      context.go(HabitRoutes.tab);
    }
  }
}

/// Series, checked days and quota of the last 30 days.
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.detail});

  final HabitDetail detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final series = detail.series.current;
    final checked = detail.checkedDaysInHistory;
    final applicable = detail.applicableDaysInHistory;
    final stats = <Widget>[
      _Stat(
        value: '$series',
        valueColor: series > 0 ? colors.streakText : colors.textPrimary,
        label: series == 1 ? 'Tag Serie' : 'Tage Serie',
        spoken: detail.currentSeriesText,
      ),
      _Stat(
        value: '$checked / $applicable',
        valueColor: colors.textPrimary,
        label: 'Tage erfüllt',
        spoken: '$checked von $applicable Tagen erfüllt',
      ),
      _Stat(
        value: applicable == 0
            ? '–'
            : '${roundedPercent(checked / applicable)} %',
        valueColor: colors.textPrimary,
        label: 'Quote',
        spoken: applicable == 0
            ? 'Quote: noch keine Tage'
            : 'Quote: ${roundedPercent(checked / applicable)} Prozent',
      ),
    ];
    final stacked = isLargeText(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (stacked)
            Column(
              children: <Widget>[
                for (var i = 0; i < stats.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: 12),
                  stats[i],
                ],
              ],
            )
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (var i = 0; i < stats.length; i++) ...<Widget>[
                    if (i > 0)
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: colors.track,
                      ),
                    Expanded(child: stats[i]),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: <Widget>[
              Text(
                detail.longestSeriesText,
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              Text(
                detail.reminderText,
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              if (detail.archiveHint != null)
                Text(
                  detail.archiveHint!,
                  style: AppTextStyles.captionStrong.copyWith(
                    color: colors.warningText,
                  ),
                ),
              if (detail.ended)
                Text(
                  'Archiviert',
                  style: AppTextStyles.captionStrong.copyWith(
                    color: colors.warningText,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.valueColor,
    required this.label,
    required this.spoken,
  });

  final String value;
  final Color valueColor;
  final String label;
  final String spoken;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      label: spoken,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              value,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleSection.copyWith(color: valueColor),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Letzte 30 Tage": the grid (or the list) of the days with their state. A
/// tap on a day that may be changed sets or removes its check.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.detail,
    required this.accent,
    required this.asList,
    required this.onToggleView,
  });

  final HabitDetail detail;
  final AppAccent accent;
  final bool asList;
  final VoidCallback onToggleView;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final first = detail.history.first.date;
    final last = detail.history.last.date;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 2,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  'Letzte $habitHistoryDays Tage',
                  style: AppTextStyles.titleCard.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${formatDayMonth(first)} – ${formatDayMonth(last)}',
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (asList)
            _HistoryList(detail: detail, accent: accent)
          else
            _HistoryGrid(detail: detail, accent: accent),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: <Widget>[
              if (!asList) _Legend(accent: accent),
              _TextAction(
                label: asList ? 'Als Raster' : 'Als Liste',
                onTap: onToggleView,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small green text action with a 48 px tap area.
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSizes.touchMin,
          minWidth: AppSizes.touchMin,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadii.controlBorder,
            focusColor: colors.focus.withValues(alpha: 0.2),
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  label,
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

/// What the cells of the grid mean: checked, open, not active, today.
class _Legend extends StatelessWidget {
  const _Legend({required this.accent});

  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    Widget item(Widget swatch, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        swatch,
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTextStyles.captionDefault.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
    Widget swatch({
      Color? fill,
      Color? border,
      double borderWidth = 1,
      bool check = false,
    }) => SizedBox.square(
      dimension: 14,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(4),
          border: border == null
              ? null
              : Border.all(color: border, width: borderWidth),
        ),
        child: check
            ? Icon(Icons.check_rounded, size: 10, color: colors.surface)
            : null,
      ),
    );
    return ExcludeSemantics(
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: <Widget>[
          item(swatch(fill: colors.accent(accent), check: true), 'erledigt'),
          item(
            swatch(
              fill: colors.accentTint(accent),
              border: colors.borderDecorative,
            ),
            'offen',
          ),
          item(swatch(border: colors.borderDecorative), 'nicht aktiv'),
          item(swatch(border: colors.textPrimary, borderWidth: 2), 'heute'),
        ],
      ),
    );
  }
}

/// The 30 days as tiles. The number of columns follows the width so every tile
/// is at least 48 wide and 48 high: 6 columns on a normal phone (5 rows).
class _HistoryGrid extends StatelessWidget {
  const _HistoryGrid({required this.detail, required this.accent});

  final HabitDetail detail;
  final AppAccent accent;

  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = ((width + _gap) / (AppSizes.touchMin + _gap))
            .floor()
            .clamp(3, 10);
        final entries = detail.history;
        final rows = <Widget>[];
        for (var start = 0; start < entries.length; start += columns) {
          final end = (start + columns).clamp(0, entries.length);
          final cells = <Widget>[];
          for (var i = start; i < start + columns; i++) {
            if (i > start) {
              cells.add(const SizedBox(width: _gap));
            }
            cells.add(
              Expanded(
                child: i < end
                    ? _DayCell(
                        habitId: detail.habit.id,
                        entry: entries[i],
                        accent: accent,
                      )
                    : const SizedBox.shrink(),
              ),
            );
          }
          if (start > 0) {
            rows.add(const SizedBox(height: _gap));
          }
          rows.add(Row(children: cells));
        }
        return Column(children: rows);
      },
    );
  }
}

/// One day of the grid: its day number, a check mark when done, and a thick
/// border for today. Not colour alone: the number, the check and the spoken
/// label carry the state.
class _DayCell extends ConsumerWidget {
  const _DayCell({
    required this.habitId,
    required this.entry,
    required this.accent,
  });

  final String habitId;
  final HabitDayEntry entry;
  final AppAccent accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final busy = ref.watch(
      habitActionsProvider.select((s) => s.isCheckBusy(habitId, entry.date)),
    );
    final container = ProviderScope.containerOf(context, listen: false);
    final canTap = entry.editable && !busy;
    final fill = switch (entry.status) {
      HabitDayStatus.checked => colors.accent(accent),
      HabitDayStatus.open => colors.accentTint(accent),
      HabitDayStatus.beforeStart ||
      HabitDayStatus.archived => colors.surfaceMuted,
    };
    final numberColor = switch (entry.status) {
      HabitDayStatus.checked => colors.surface,
      HabitDayStatus.open => colors.textPrimary,
      HabitDayStatus.beforeStart ||
      HabitDayStatus.archived => colors.textTertiary,
    };
    final label =
        '${entry.isToday ? 'Heute, ' : ''}${entry.semanticsLabel}'
        '${entry.editable ? ', zum Ändern tippen' : ''}';
    void onTap() => unawaited(
      setHabitChecked(container, habitId, entry.date, checked: !entry.checked),
    );
    return Semantics(
      container: true,
      button: entry.editable,
      enabled: entry.editable,
      checked: entry.applicable ? entry.checked : null,
      label: label,
      onTap: canTap ? onTap : null,
      excludeSemantics: true,
      child: SizedBox(
        height: AppSizes.touchMin,
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: entry.isToday
                ? BorderSide(color: colors.textPrimary, width: 2)
                : BorderSide(color: colors.borderDecorative),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canTap ? onTap : null,
            focusColor: colors.focus.withValues(alpha: 0.2),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    '${entry.date.day}',
                    style: AppTextStyles.captionStrong.copyWith(
                      color: numberColor,
                      height: 1.1,
                    ),
                  ),
                  SizedBox(
                    height: 14,
                    child: entry.checked
                        ? Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: numberColor,
                          )
                        : null,
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

/// The same 30 days as a list, newest first: date, state in words, and the
/// checkbox for a day that may be changed. The text alternative of the grid.
class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.detail, required this.accent});

  final HabitDetail detail;
  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final days = detail.history.reversed.toList();
    return Column(
      children: <Widget>[
        for (var i = 0; i < days.length; i++) ...<Widget>[
          if (i > 0) Divider(height: 1, thickness: 1, color: colors.track),
          _HistoryListRow(habitId: detail.habit.id, entry: days[i]),
        ],
      ],
    );
  }
}

class _HistoryListRow extends ConsumerWidget {
  const _HistoryListRow({required this.habitId, required this.entry});

  final String habitId;
  final HabitDayEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final busy = ref.watch(
      habitActionsProvider.select((s) => s.isCheckBusy(habitId, entry.date)),
    );
    final container = ProviderScope.containerOf(context, listen: false);
    final date = formatDateShort(entry.date);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.isToday ? 'Heute, $date' : date,
                      style: AppTextStyles.bodyDefault.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      entry.status.text,
                      style: AppTextStyles.captionDefault.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (entry.applicable)
            RoundCheckbox(
              value: entry.checked,
              semanticLabel: formatDateShort(entry.date),
              checkedStateLabel: 'erledigt',
              uncheckedStateLabel: 'offen',
              onChanged: (!entry.editable || busy)
                  ? null
                  : (value) => unawaited(
                      setHabitChecked(
                        container,
                        habitId,
                        entry.date,
                        checked: value,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}
