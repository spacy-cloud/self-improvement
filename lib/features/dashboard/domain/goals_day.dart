import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/goals/domain/goal_keys.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/focus/domain/workout_day_mark.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';
import 'package:self_improvement/features/profile/domain/goal_editor.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// How one goal of a day stands.
///
/// A rest day and a skipped day (BS-99) are states of their own, but they count
/// as reached, exactly like in the day ring: [isReached] is `true` for all of
/// them but [open].
enum GoalRowStatus {
  /// Not reached yet.
  open('Offen', 'noch offen'),

  /// Reached.
  reached('Erreicht', 'erreicht'),

  /// "Workout heute" is answered by a rest day.
  rest('Ruhetag', 'Ruhetag, zählt als erreicht'),

  /// "Workout heute" is answered by a skipped day.
  skipped('Übersprungen', 'übersprungen, zählt als erreicht');

  const GoalRowStatus(this.label, this.spoken);

  /// The word in the pill of the row.
  final String label;

  /// The same state for a screen reader.
  final String spoken;

  /// Whether the goal counts as reached.
  bool get isReached => this != open;
}

/// A habit as the list of goals needs it: id (the goal key is `habit:<id>`),
/// name and symbol.
typedef GoalHabit = ({String id, String title, HabitIcon icon});

/// One line of "Ziele heute": a daily goal with its stand, target and status,
/// or the weekly workout goal ([isWeekly]).
///
/// Every number comes from the [GoalProgress] of the day status (for the week
/// from the weekly summary); this class only words them.
@immutable
final class GoalsDayRow {
  const GoalsDayRow({
    required this.goalKey,
    required this.module,
    required this.title,
    required this.status,
    required this.detail,
    required this.spoken,
    this.type,
    this.habitId,
    this.habitIcon,
    this.fraction,
  });

  /// `GoalType.key` or `habit:<id>`.
  final String goalKey;

  /// The goal type; `null` for a habit.
  final GoalType? type;

  /// The habit id of a habit goal, otherwise `null`.
  final String? habitId;

  /// The symbol of a habit goal (`null` when the habit is not known).
  final HabitIcon? habitIcon;

  /// The module the goal belongs to.
  final ModuleId module;

  /// The name, for example "Wasser" (the title of the goal editor).
  final String title;

  final GoalRowStatus status;

  /// The second line: stand and target in the units of the app, with the
  /// percentage for measured goals ("1,5 von 2,5 l · 60 %").
  final String detail;

  /// The whole row for a screen reader (without the hint that it opens a page).
  final String spoken;

  /// The bar from 0 to 1, or `null` for no bar (a rest day and a skipped day
  /// have no measure).
  final double? fraction;

  /// Whether this is the weekly workout goal (not a daily goal, never counted
  /// in the day ring).
  bool get isWeekly => type == GoalType.workoutWeekly;

  /// Whether the goal counts as reached.
  bool get isReached => status.isReached;
}

/// What "Ziele heute" shows for one day: the numbers of the day ring, one row
/// per applicable daily goal and the weekly workout goal apart from them.
@immutable
final class GoalsDay {
  const GoalsDay({
    required this.date,
    required this.isToday,
    required this.fulfilled,
    required this.applicable,
    required this.rows,
    this.weekly,
  });

  /// A day without a daily goal: "Noch keine Tagesziele".
  const GoalsDay.none({required this.date, required this.isToday})
    : fulfilled = 0,
      applicable = 0,
      rows = const <GoalsDayRow>[],
      weekly = null;

  /// The day shown.
  final LocalDate date;

  /// Whether [date] is today. A past day is shown read-only ("Nicht heute"),
  /// without the weekly goal and without the word "heute".
  final bool isToday;

  /// Goals reached: [DayStatus.fulfilledCount], the number of the ring.
  final int fulfilled;

  /// Goals that count: [DayStatus.applicableCount], the number of the ring.
  final int applicable;

  /// The applicable daily goals in the order of the goal editor, then the
  /// habits.
  final List<GoalsDayRow> rows;

  /// The weekly workout goal, shown apart from the rows and never part of the
  /// numbers above; `null` when it is not shown.
  final GoalsDayRow? weekly;

  /// Whether at least one daily goal applies (otherwise the page shows
  /// "Noch keine Tagesziele").
  bool get hasGoals => applicable > 0;

  /// Whether every goal is reached (and at least one applies).
  bool get isComplete => applicable > 0 && fulfilled >= applicable;

  /// The date line, for example "Montag, 14. September".
  String get dateText => formatDateLong(date);

  /// The spoken text of the ring, the same as on Home.
  String get ringLabel {
    if (applicable <= 0) {
      return 'Heute sind keine Ziele aktiv';
    }
    return applicable == 1
        ? '$fulfilled von 1 Ziel erreicht'
        : '$fulfilled von $applicable Zielen erreicht';
  }

  /// The word under "x von y" in the ring.
  String get ringUnit => applicable == 1 ? 'Ziel' : 'Zielen';

  /// The headline of the summary: "2 von 5 erreicht".
  String get title {
    if (fulfilled <= 0) {
      return isToday ? 'Noch nichts erreicht' : 'Nichts erreicht';
    }
    return applicable == 1
        ? '$fulfilled von 1 Ziel erreicht'
        : '$fulfilled von $applicable erreicht';
  }

  /// The sentence under the headline.
  String get sentence {
    if (!isToday) {
      return 'Du siehst die Werte dieses Tages.';
    }
    if (fulfilled <= 0) {
      return 'Heute ist noch alles offen. Mach den ersten Schritt.';
    }
    if (isComplete) {
      return applicable == 1
          ? 'Du hast dein Tagesziel erreicht.'
          : 'Stark! Heute ist alles geschafft.';
    }
    final open = applicable - fulfilled;
    return open == 1
        ? 'Noch 1 Ziel offen. Bleib dran!'
        : 'Noch $open Ziele offen. Bleib dran!';
  }

  /// The whole summary for a screen reader.
  String get summarySpoken => '$dateText. $title. $sentence';

  /// The label above the list of the daily goals.
  String get listTitle => applicable == 1 ? 'Tagesziel' : 'Tagesziele';
}

/// The real percentage of [target] that [current] reaches, rounded half up and
/// never 100 while the target is not reached (9.950 of 10.000 shows 99, so
/// "100 %" and "erreicht" always agree). Above the target it is the real value
/// (112), like on the water and steps screens.
int goalPercent({required int current, required int target}) {
  assert(target > 0, 'a target is always positive');
  final rounded = (current * 200 + target) ~/ (2 * target);
  return current < target && rounded > 99 ? 99 : rounded;
}

double _fraction(int current, int target) =>
    target <= 0 ? 0 : (current / target).clamp(0.0, 1.0);

/// Builds the rows of "Ziele heute" from the [status] of the day, the same
/// object the day ring on Home counts.
///
/// - Only applicable goals appear, so [GoalsDay.applicable] and
///   [GoalsDay.fulfilled] are the numbers of the ring and the rows add up to
///   them. Whether a row is reached comes from the status, never from the
///   other sources below.
/// - The rows follow [goalDisplayOrder] (the order of the goal editor), then
///   the habits in the order of [habits]. One row per habit, because the ring
///   counts every habit as a goal.
/// - [workoutOutcome] says how "Workout heute" was answered on that day (rest
///   day, skipped day or workout); it only refines the words of a reached row.
/// - [week] is the weekly workout goal. It stands apart below the daily goals
///   and is not part of the numbers; it is shown for today only, and only
///   while at least one daily goal applies (without one the page shows just
///   "Noch keine Tagesziele").
GoalsDay buildGoalsDay({
  required DayStatus status,
  required LocalDate today,
  List<GoalHabit> habits = const <GoalHabit>[],
  WorkoutDayOutcome? workoutOutcome,
  WorkoutWeekSummary? week,
}) {
  final isToday = status.date == today;
  final applicable = <String, GoalProgress>{
    for (final goal in status.goals)
      if (goal.applicable) goal.goalKey: goal,
  };
  final rows = <GoalsDayRow>[
    for (final type in goalDisplayOrder)
      if (type.isDaily && applicable[type.key] != null)
        _typeRow(
          type,
          applicable[type.key]!,
          isToday: isToday,
          workoutOutcome: workoutOutcome,
        ),
    ..._habitRows(applicable.values, habits, isToday: isToday),
  ];
  return GoalsDay(
    date: status.date,
    isToday: isToday,
    fulfilled: status.fulfilledCount,
    applicable: status.applicableCount,
    rows: List<GoalsDayRow>.unmodifiable(rows),
    weekly: week != null && isToday && status.hasApplicableGoals
        ? _weeklyRow(week)
        : null,
  );
}

GoalsDayRow _typeRow(
  GoalType type,
  GoalProgress progress, {
  required bool isToday,
  required WorkoutDayOutcome? workoutOutcome,
}) {
  final title = goalEditorSpec(type).title;
  final reached = progress.fulfilled;
  final target = progress.target ?? type.defaultTarget;
  final current = progress.current;
  final status = reached ? GoalRowStatus.reached : GoalRowStatus.open;

  GoalsDayRow row({
    required GoalRowStatus status,
    required String detail,
    required String spoken,
    double? fraction,
  }) => GoalsDayRow(
    goalKey: type.key,
    type: type,
    module: progress.module,
    title: title,
    status: status,
    detail: detail,
    spoken: spoken,
    fraction: fraction,
  );

  // A goal with a number: "value · percent" and a bar that follows the number.
  GoalsDayRow measured(int amount, String value, String spokenValue) {
    final percent = goalPercent(current: amount, target: target);
    return row(
      status: status,
      detail: '$value · $percent %',
      spoken: '$title, $spokenValue, $percent Prozent, ${status.spoken}',
      fraction: reached ? 1 : _fraction(amount, target),
    );
  }

  // A goal that is done or not: a sentence and an empty or full bar.
  GoalsDayRow yesOrNo(String detail) => row(
    status: status,
    detail: detail,
    spoken: '$title, $detail, ${status.spoken}',
    fraction: reached ? 1 : 0,
  );

  switch (type) {
    case GoalType.water:
      final amount = current ?? 0;
      return measured(
        amount,
        '${formatLiters(amount)} von ${goalValueText(type, target)}',
        '${formatLiters(amount)} von ${formatLiters(target)} '
            '${target == 1000 ? 'Liter' : 'Litern'}',
      );
    case GoalType.steps:
      if (current == null) {
        return yesOrNo(
          isToday
              ? 'Noch keine Schritte eingetragen'
              : 'Keine Schritte eingetragen',
        );
      }
      return measured(
        current,
        '${formatThousands(current)} von ${formatThousands(target)}',
        '${formatThousands(current)} von ${formatThousands(target)} Schritten',
      );
    case GoalType.focusMinutes:
      final minutes = current ?? 0;
      return measured(
        minutes,
        '$minutes von $target Min.',
        '$minutes von $target Minuten',
      );
    case GoalType.weightEntry:
      final count = current ?? 0;
      if (!reached) {
        return yesOrNo(isToday ? 'Noch nicht gewogen' : 'Nicht gewogen');
      }
      if (count <= 1) {
        return yesOrNo(isToday ? 'Heute gewogen' : 'Gewogen');
      }
      return yesOrNo(
        isToday ? 'Heute $count-mal gewogen' : '$count-mal gewogen',
      );
    case GoalType.taskCompletion:
      final count = current ?? 0;
      if (!reached) {
        return yesOrNo(
          isToday ? 'Noch keine Aufgabe erledigt' : 'Keine Aufgabe erledigt',
        );
      }
      return yesOrNo(
        count == 1 ? '1 Aufgabe erledigt' : '$count Aufgaben erledigt',
      );
    case GoalType.workoutDaily:
      if (!reached) {
        return yesOrNo(
          isToday
              ? 'Noch kein Training eingetragen'
              : 'Kein Training eingetragen',
        );
      }
      return switch (workoutOutcome) {
        WorkoutDayOutcome.rest => row(
          status: GoalRowStatus.rest,
          detail: 'Ruhetag eingetragen · keine XP, Streak bleibt',
          spoken:
              '$title, ${GoalRowStatus.rest.spoken}, keine XP, die Streak '
              'bleibt',
        ),
        WorkoutDayOutcome.skipped => row(
          status: GoalRowStatus.skipped,
          detail: 'Training übersprungen · keine XP, Streak bleibt',
          spoken:
              '$title, ${GoalRowStatus.skipped.spoken}, keine XP, die Streak '
              'bleibt',
        ),
        WorkoutDayOutcome.trained => yesOrNo(
          (current ?? 0) <= 1
              ? '1 Training eingetragen'
              : '$current Trainings eingetragen',
        ),
        WorkoutDayOutcome.open || null => yesOrNo('Eintrag vorhanden'),
      };
    case GoalType.workoutWeekly:
      throw ArgumentError.value(type, 'type', 'not a daily goal');
  }
}

List<GoalsDayRow> _habitRows(
  Iterable<GoalProgress> goals,
  List<GoalHabit> habits, {
  required bool isToday,
}) {
  final position = <String, int>{
    for (var i = 0; i < habits.length; i++) habits[i].id: i,
  };
  int positionOf(GoalProgress goal) =>
      position[habitIdFromKey(goal.goalKey)] ?? habits.length;
  final ofHabits =
      <GoalProgress>[
        for (final goal in goals)
          if (isHabitGoalKey(goal.goalKey)) goal,
      ]..sort((a, b) {
        final byPosition = positionOf(a).compareTo(positionOf(b));
        return byPosition != 0 ? byPosition : a.goalKey.compareTo(b.goalKey);
      });
  return <GoalsDayRow>[
    for (final goal in ofHabits)
      _habitRow(
        goal,
        positionOf(goal) < habits.length ? habits[positionOf(goal)] : null,
        isToday: isToday,
      ),
  ];
}

GoalsDayRow _habitRow(
  GoalProgress goal,
  GoalHabit? habit, {
  required bool isToday,
}) {
  final title = habit?.title ?? 'Gewohnheit';
  final status = goal.fulfilled ? GoalRowStatus.reached : GoalRowStatus.open;
  final detail = goal.fulfilled
      ? (isToday ? 'Heute abgehakt' : 'Abgehakt')
      : (isToday ? 'Noch nicht abgehakt' : 'Nicht abgehakt');
  return GoalsDayRow(
    goalKey: goal.goalKey,
    habitId: habitIdFromKey(goal.goalKey),
    habitIcon: habit?.icon,
    module: goal.module,
    title: title,
    status: status,
    detail: detail,
    spoken: '$title, $detail, ${status.spoken}',
    fraction: goal.fulfilled ? 1 : 0,
  );
}

GoalsDayRow _weeklyRow(WorkoutWeekSummary week) {
  const type = GoalType.workoutWeekly;
  final count = week.entryCount;
  final target = week.weeklyTarget;
  final percent = goalPercent(current: count, target: target);
  final status = week.targetReached
      ? GoalRowStatus.reached
      : GoalRowStatus.open;
  return GoalsDayRow(
    goalKey: type.key,
    type: type,
    module: type.module,
    title: 'Workouts diese Woche',
    status: status,
    detail: '$count von $target · $percent %',
    spoken:
        'Workouts diese Woche, $count von $target Trainings, $percent '
        'Prozent, ${status.spoken}',
    fraction: week.ringFraction,
  );
}
