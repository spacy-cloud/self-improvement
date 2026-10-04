import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart' hide HabitIcon;
import 'package:self_improvement/features/tasks/application/habit_actions_controller.dart';
import 'package:self_improvement/features/tasks/application/habit_day_providers.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/domain/german_dates.dart';
import 'package:self_improvement/features/tasks/domain/habit_day.dart';
import 'package:self_improvement/features/tasks/presentation/action_feedback.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_routes.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_widgets.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The habits view of the tab: the week strip, the progress card of the shown
/// day and the habits of that day with their one-tap check. Today is shown by
/// default; a day of the strip lets the user fix a day that was forgotten.
class HabitsDayView extends ConsumerWidget {
  const HabitsDayView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(habitDayProvider);
    return day.when(
      loading: () =>
          const _Scroll(children: <Widget>[TasksLoadingPlaceholder()]),
      error: (error, stack) => _Scroll(
        children: <Widget>[
          ErrorState(
            onRetry: () {
              ref
                ..invalidate(habitsProvider)
                ..invalidate(habitCheckIndexProvider);
            },
          ),
        ],
      ),
      data: (data) => _DayContent(day: data),
    );
  }
}

class _Scroll extends StatelessWidget {
  const _Scroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.s16,
      AppSpacing.s8,
      AppSpacing.s16,
      AppSpacing.s24,
    ),
    children: children,
  );
}

class _DayContent extends ConsumerWidget {
  const _DayContent({required this.day});

  final HabitDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAnyHabit = ref.watch(habitsProvider).value?.isNotEmpty ?? false;
    return _Scroll(
      children: <Widget>[
        _WeekStrip(day: day),
        const SizedBox(height: 12),
        _DayCard(day: day),
        const SizedBox(height: 16),
        AppSectionHeader(
          title: day.isToday
              ? 'Deine Habits'
              : 'Habits am ${formatGermanWeekdayDate(day.date)}',
        ),
        const SizedBox(height: 8),
        if (day.isEmpty)
          _emptyState(context, day, hasAnyHabit: hasAnyHabit)
        else
          AppListGroup(
            children: <Widget>[
              for (final item in day.items)
                HabitRow(item: item, date: day.date),
            ],
          ),
        if (day.isToday) const _ArchivedHabits(),
      ],
    );
  }

  Widget _emptyState(
    BuildContext context,
    HabitDay day, {
    required bool hasAnyHabit,
  }) {
    if (!day.isToday) {
      return const EmptyState(
        title: 'Keine Gewohnheit an diesem Tag',
        message: 'Für diesen Tag war noch keine Gewohnheit aktiv.',
        icon: AppIcon.habit,
        accent: AppAccent.habits,
      );
    }
    if (hasAnyHabit) {
      return EmptyState(
        title: 'Keine aktive Gewohnheit',
        message:
            'Alle deine Gewohnheiten sind archiviert. Lege eine neue an, '
            'um wieder täglich zu starten.',
        icon: AppIcon.habit,
        accent: AppAccent.habits,
        actionLabel: 'Gewohnheit anlegen',
        onAction: () => context.push(HabitRoutes.create),
      );
    }
    return EmptyState(
      title: 'Noch keine Gewohnheit',
      message:
          'Lege eine tägliche Gewohnheit an und hake sie jeden Tag mit einem '
          'Tipp ab.',
      icon: AppIcon.habit,
      accent: AppAccent.habits,
      actionLabel: 'Gewohnheit anlegen',
      onAction: () => context.push(HabitRoutes.create),
    );
  }
}

/// The habits that have ended (archived and no longer applying): their history
/// stays readable, and they can still be deleted. They are never reactivated.
class _ArchivedHabits extends ConsumerWidget {
  const _ArchivedHabits();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = ref.watch(habitsOverviewProvider).value?.archived;
    if (archived == null || archived.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 16),
        const AppSectionHeader(title: 'Archiviert'),
        const SizedBox(height: 8),
        AppListGroup(
          children: <Widget>[
            for (final item in archived)
              EntryListTile.chevron(
                title: item.habit.title,
                subtitle:
                    'Archiviert seit ${formatGermanDate(item.habit.archivedFrom!)}',
                icon: habitVisual(item.habit.icon).glyph,
                accent: habitVisual(item.habit.icon).accent,
                semanticLabel:
                    '${item.habit.title}, archiviert seit '
                    '${formatGermanDate(item.habit.archivedFrom!)}, öffnet den '
                    'Verlauf',
                onTap: () => context.push(HabitRoutes.detail(item.habit.id)),
              ),
          ],
        ),
      ],
    );
  }
}

/// The last seven days with a marker for how complete each day is. Every day
/// is a button: it shows that day's habits below. The strip scrolls sideways
/// when the screen is too narrow for seven 48 px targets.
class _WeekStrip extends ConsumerWidget {
  const _WeekStrip({required this.day});

  final HabitDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Die letzten sieben Tage',
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final entry in day.week)
                    _DayButton(
                      entry: entry,
                      selected: entry.date == day.date,
                      onTap: () => ref
                          .read(selectedHabitDayProvider.notifier)
                          .select(entry.isToday ? null : entry.date),
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

class _DayButton extends StatelessWidget {
  const _DayButton({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final HabitWeekDay entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final foreground = selected ? colors.onPrimary : colors.textPrimary;
    final marker = switch (entry.completion) {
      HabitDayCompletion.complete => _Marker.filled,
      HabitDayCompletion.partial => _Marker.ring,
      HabitDayCompletion.none || HabitDayCompletion.noHabits => _Marker.none,
    };
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: entry.semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSizes.touchMin,
          minHeight: AppSizes.touchMin,
        ),
        child: Material(
          color: selected ? colors.primaryButton : Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: entry.isToday && !selected
                ? BorderSide(color: colors.primaryButton, width: 1.5)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: onTap,
            focusColor: colors.focus.withValues(alpha: 0.2),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    weekdayTwoLetters(entry.date),
                    style: AppTextStyles.captionDefault.copyWith(
                      color: selected ? colors.onPrimary : colors.textSecondary,
                    ),
                  ),
                  Text(
                    '${entry.date.day}',
                    style: AppTextStyles.titleCard.copyWith(color: foreground),
                  ),
                  const SizedBox(height: 4),
                  _MarkerDot(
                    marker: marker,
                    color: selected
                        ? colors.onPrimary
                        : (marker == _Marker.ring
                              ? colors.warningText
                              : colors.primaryButton),
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

enum _Marker { none, filled, ring }

class _MarkerDot extends StatelessWidget {
  const _MarkerDot({required this.marker, required this.color});

  final _Marker marker;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 8,
      child: marker == _Marker.none
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: marker == _Marker.filled ? color : null,
                border: marker == _Marker.ring
                    ? Border.all(color: color, width: 1.5)
                    : null,
              ),
            ),
    );
  }
}

/// "Heute" with the progress of the shown day.
class _DayCard extends ConsumerWidget {
  const _DayCard({required this.day});

  final HabitDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final label = day.isToday
        ? 'Heute'
        : formatRelativeDay(day.date, day.today);
    final pill = day.isToday ? _encouragement(day) : null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: <Widget>[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          label,
                          style: AppTextStyles.bodyDefault.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              TextSpan(
                                text: '${day.doneCount} von ${day.totalCount} ',
                                style: AppTextStyles.titleScreen.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                              TextSpan(
                                text: 'erledigt',
                                style: AppTextStyles.bodyDefault.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (pill != null)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.primaryTint,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            pill,
                            style: AppTextStyles.captionStrong.copyWith(
                              color: colors.primaryText,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                AppProgressBar(value: day.progress),
              ],
            ),
          ),
          if (!day.isToday) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'Du siehst einen vergangenen Tag. Hier kannst du Haken '
              'nachtragen oder entfernen.',
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Zurück zu heute',
              onPressed: () =>
                  ref.read(selectedHabitDayProvider.notifier).select(null),
            ),
          ],
        ],
      ),
    );
  }

  /// A short state word, only for today: all done, or exactly one missing.
  String? _encouragement(HabitDay day) {
    if (day.totalCount == 0) {
      return null;
    }
    if (day.doneCount == day.totalCount) {
      return 'Alles geschafft!';
    }
    if (day.totalCount > 1 && day.doneCount == day.totalCount - 1) {
      return 'Fast geschafft!';
    }
    return null;
  }
}

/// One habit of the shown day: the symbol, the title with the series, and the
/// round checkbox. Tapping the body opens the detail; the checkbox sets the
/// day's check (a desired state, with undo). With large text the checkbox sits
/// in its own line above the title, so the title keeps the full width.
class HabitRow extends ConsumerWidget {
  const HabitRow({required this.item, required this.date, super.key});

  final HabitDayItem item;
  final LocalDate date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habit = item.habit;
    final busy = ref.watch(
      habitActionsProvider.select((s) => s.isCheckBusy(habit.id, date)),
    );
    final container = ProviderScope.containerOf(context, listen: false);
    final stacked = isLargeText(context);
    final checkbox = RoundCheckbox(
      value: item.checked,
      semanticLabel: habit.title,
      checkedStateLabel: 'erledigt',
      uncheckedStateLabel: 'offen',
      onChanged: (!item.editable || busy)
          ? null
          : (value) => unawaited(
              setHabitChecked(container, habit.id, date, checked: value),
            ),
    );
    final body = TappableBody(
      onTap: () => context.push(HabitRoutes.detail(habit.id)),
      semanticLabel: item.semanticsLabel,
      semanticHint: 'Öffnet die Gewohnheit',
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, stacked ? 4 : 8, stacked ? 14 : 4, 8),
        child: _HabitTexts(item: item),
      ),
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 6, top: 4),
              child: checkbox,
            ),
          ),
          body,
        ],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(child: body),
        checkbox,
        const SizedBox(width: 6),
      ],
    );
  }
}

/// Symbol tile, title and the line with the frequency, the series and the
/// archive hint.
class _HabitTexts extends StatelessWidget {
  const _HabitTexts({required this.item});

  final HabitDayItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final habit = item.habit;
    final visual = habitVisual(habit.icon);
    final series = item.series;
    final seriesText = item.seriesText;
    final running = series != null && series.current > 0;
    return Row(
      children: <Widget>[
        AppIconTile(
          icon: visual.glyph,
          accent: visual.accent,
          size: 44,
          iconSize: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                habit.title,
                style: AppTextStyles.titleCard.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    'Täglich',
                    style: AppTextStyles.captionDefault.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  if (seriesText != null && running)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          AppIcon.streak.data,
                          size: 14,
                          color: colors.streakText,
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            seriesText,
                            style: AppTextStyles.captionStrong.copyWith(
                              color: colors.streakText,
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (seriesText != null)
                    Text(
                      seriesText,
                      style: AppTextStyles.captionDefault.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  if (item.archiveHint != null)
                    Text(
                      item.archiveHint!,
                      style: AppTextStyles.captionStrong.copyWith(
                        color: colors.warningText,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
