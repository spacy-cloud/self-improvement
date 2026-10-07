import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/navigation.dart' show currentPath;
import 'package:self_improvement/core/dashboard/domain/motivation.dart';
import 'package:self_improvement/core/design/design.dart' hide HabitIcon;
import 'package:self_improvement/core/goals/application/goal_providers.dart'
    show todayStatusProvider;
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/features/dashboard/domain/goals_day.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/goals_day_view.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/not_today_banner.dart';
import 'package:self_improvement/features/focus/application/workout_day_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_day_mark.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../core/design/support/ring_arcs.dart';
import '../../../support/pump_app.dart';
import '../support/dashboard_test_kit.dart';
import '../support/goals_today_kit.dart';

// BS-103 (with BS-100): the page "Ziele heute" shows every daily goal of today
// with its stand, target and status, the ring in the numbers of Home and the
// weekly workout goal apart. Rows are read from the day status; the numbers are
// the ones the ring counts.

/// A day after the profile start: no welcome, the real data.
final LocalDate _secondDay = LocalDate(2026, 10, 2);

/// The arcs the ring paints for [fulfilled] of [applicable] goals in [colors]:
/// the track, then (when something is reached) the arc in yellow or, with all
/// goals reached, the full ring in green.
List<PaintedArc> _arcs(AppColors colors, int fulfilled, int applicable) {
  final standing = GoalsStanding.of(
    fulfilled: fulfilled,
    applicable: applicable,
  );
  return <PaintedArc>[
    (color: colors.track, sweep: 2 * math.pi),
    if (standing == GoalsStanding.partial)
      (color: colors.dayRing, sweep: 2 * math.pi * fulfilled / applicable),
    if (standing == GoalsStanding.all)
      (color: colors.dayRingComplete, sweep: 2 * math.pi),
  ];
}

Future<GoRouter> _pump(
  WidgetTester tester,
  List<GoalProgress> goals, {
  List<Override> overrides = const <Override>[],
  Size size = const Size(393, 852),
  double textScale = 1.0,
  AppThemeVariant theme = AppThemeVariant.light,
}) async {
  final harness = await createHarness(tester, startedOn: _secondDay);
  return pumpGoalsToday(
    tester,
    harness,
    overrides: <Override>[todayStatusOverride(statusOf(goals)), ...overrides],
    size: size,
    textScale: textScale,
    theme: theme,
  );
}

/// The path of the page on top, also of a page that was pushed (the router's
/// own location is only the base).
String _top(GoRouter router) => currentPath(router);

/// The location with its query, after a `go` (a tab).
String _uri(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

Habit _habit(String id, String title, HabitIcon icon) => Habit(
  id: id,
  title: title,
  icon: icon,
  startedOn: _secondDay,
  createdAtUtc: DateTime.utc(2026, 10, 2),
  updatedAtUtc: DateTime.utc(2026, 10, 2),
  rowVersion: 1,
);

WorkoutWeekSummary _week(int count, {int target = 3}) => WorkoutWeekSummary(
  weekStart: LocalDate(2026, 10, 3).startOfWeek,
  entryCount: count,
  totalMinutes: count * 45,
  weeklyTarget: target,
);

WorkoutEntry _workout(String id) => WorkoutEntry(
  id: id,
  category: TrainingCategory.strength,
  durationMinutes: 45,
  occurredAtUtc: DateTime.utc(2026, 10, 3, 6),
  localDate: LocalDate(2026, 10, 3),
  timezoneId: 'Europe/Berlin',
  rowVersion: 1,
  gamificationEligible: true,
);

/// How "Workout heute" was answered on the day: [workouts] and/or a [mark].
Override _workoutDay({
  List<WorkoutEntry> workouts = const <WorkoutEntry>[],
  WorkoutDayMarkKind? mark,
}) => workoutDayStateProvider.overrideWithValue(
  AsyncData<WorkoutDayState>(
    WorkoutDayState(
      date: goalsTestDay,
      workouts: workouts,
      mark: mark == null
          ? null
          : WorkoutDayMark(
              id: 'mark',
              date: goalsTestDay,
              kind: mark,
              timezoneId: 'Europe/Berlin',
              rowVersion: 1,
            ),
    ),
  ),
);

Override _weekOf(int count, {int target = 3}) =>
    workoutWeekSummaryProvider.overrideWithValue(
      AsyncData<WorkoutWeekSummary>(_week(count, target: target)),
    );

/// [text] inside the list of the daily goals: the first list group of the page
/// (the weekly goal has a list of its own below it, with its own status).
Finder _daily(String text) => find.descendant(
  of: find.byType(AppListGroup).first,
  matching: find.text(text),
);

/// The longest page there is: the five goals, the daily workout goal answered
/// by a rest day, two habits and the weekly goal.
final List<GoalProgress> _fullDay = <GoalProgress>[
  ...goalStates['some']!,
  goalOf(GoalType.workoutDaily, current: 1, reached: true),
  habitGoalOf('a', checked: true),
  habitGoalOf('b'),
];

List<Override> _fullDayOverrides() => <Override>[
  _workoutDay(mark: WorkoutDayMarkKind.rest),
  _weekOf(2),
  habitsProvider.overrideWith(
    (ref) => Stream<List<Habit>>.value(<Habit>[
      _habit('a', 'Lesen', HabitIcon.book),
      _habit('b', 'Dehnen', HabitIcon.flame),
    ]),
  ),
];

/// Runs the Android tap target and label guidelines on the whole page: the
/// view is made tall enough that no scrolled-away part distorts the measured
/// sizes.
Future<void> _expectAccessibleTargets(WidgetTester tester, Size size) async {
  tester.view.physicalSize = Size(size.width, 9000);
  await tester.pump();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}

void main() {
  group('the states of the page (BS-103)', () {
    testWidgets('(C04, AT34) nothing reached: grey ring, five open goals', (
      tester,
    ) async {
      await _pump(tester, goalStates['nothing']!);
      expect(find.text('Ziele heute'), findsOneWidget);
      expect(find.text('Samstag, 3. Oktober'), findsOneWidget);
      expect(find.text('0 von 5'), findsOneWidget);
      expect(find.text('Zielen'), findsOneWidget);
      expect(find.text('Noch nichts erreicht'), findsOneWidget);
      expect(
        find.text('Heute ist noch alles offen. Mach den ersten Schritt.'),
        findsOneWidget,
      );
      expect(find.text('TAGESZIELE'), findsOneWidget);
      expect(find.text('0,5 von 2,5 l · 20 %'), findsOneWidget);
      expect(find.text('1.250 von 10.000 · 13 %'), findsOneWidget);
      expect(find.text('0 von 60 Min. · 0 %'), findsOneWidget);
      expect(find.text('Noch nicht gewogen'), findsOneWidget);
      expect(find.text('Noch keine Aufgabe erledigt'), findsOneWidget);
      expect(_daily('Offen'), findsNWidgets(5));
      expect(_daily('Erreicht'), findsNothing);
      expect(paintedArcs(tester), _arcs(AppColors.light, 0, 5));
    });

    testWidgets('(C04, AT34) some reached: 2 of 5, yellow arc, 3 open', (
      tester,
    ) async {
      await _pump(tester, goalStates['some']!);
      expect(find.text('2 von 5'), findsOneWidget);
      expect(find.text('2 von 5 erreicht'), findsOneWidget);
      expect(find.text('Noch 3 Ziele offen. Bleib dran!'), findsOneWidget);
      expect(find.text('1,5 von 2,5 l · 60 %'), findsOneWidget);
      expect(find.text('7.450 von 10.000 · 75 %'), findsOneWidget);
      expect(find.text('45 von 60 Min. · 75 %'), findsOneWidget);
      expect(find.text('Heute gewogen'), findsOneWidget);
      expect(find.text('2 Aufgaben erledigt'), findsOneWidget);
      expect(_daily('Offen'), findsNWidgets(3));
      expect(_daily('Erreicht'), findsNWidgets(2));
      expect(paintedArcs(tester), _arcs(AppColors.light, 2, 5));
      expect(paintedArcs(tester).last.color, AppColors.light.dayRing);
    });

    testWidgets('(C04, AT34) all reached: full green ring, trophy, no open '
        'goal', (tester) async {
      await _pump(tester, goalStates['all']!);
      expect(find.text('5 von 5'), findsOneWidget);
      expect(find.text('5 von 5 erreicht'), findsOneWidget);
      expect(find.text('Stark! Heute ist alles geschafft.'), findsOneWidget);
      expect(find.byIcon(AppIcon.trophy.data), findsOneWidget);
      expect(find.text('10.240 von 10.000 · 102 %'), findsOneWidget);
      expect(_daily('Erreicht'), findsNWidgets(5));
      expect(_daily('Offen'), findsNothing);
      expect(paintedArcs(tester), _arcs(AppColors.light, 5, 5));
      expect(paintedArcs(tester).last.color, AppColors.light.dayRingComplete);
    });

    testWidgets('(C04, AT34) a single goal: singular words, one row', (
      tester,
    ) async {
      await _pump(tester, goalStates['one']!);
      expect(find.text('1 von 1'), findsOneWidget);
      expect(find.text('Ziel'), findsOneWidget);
      expect(find.text('1 von 1 Ziel erreicht'), findsOneWidget);
      expect(find.text('Du hast dein Tagesziel erreicht.'), findsOneWidget);
      expect(find.text('TAGESZIEL'), findsOneWidget);
      expect(find.text('TAGESZIELE'), findsNothing);
      expect(find.text('2,5 von 2,5 l · 100 %'), findsOneWidget);
      expect(find.text('Wasser'), findsOneWidget);
      expect(_daily('Erreicht'), findsOneWidget);
      expect(paintedArcs(tester), _arcs(AppColors.light, 1, 1));
    });

    testWidgets('(C04) without a daily goal: "Noch keine Tagesziele" and the '
        'way to the goals, no ring', (tester) async {
      await _pump(tester, const <GoalProgress>[]);
      expect(find.text('Noch keine Tagesziele'), findsOneWidget);
      expect(find.byType(ProgressRing), findsNothing);
      expect(find.textContaining('0 von 0'), findsNothing);
      expect(find.text('TAGESZIELE'), findsNothing);
      expect(find.text('Ziele festlegen'), findsOneWidget);
      // The weekly goal stands below the daily ones: without them it is not
      // shown either.
      expect(find.text('Workouts diese Woche'), findsNothing);
    });

    testWidgets('(C04) before the profile start there is no status: the same '
        'empty state, never a ring', (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      await pumpGoalsToday(
        tester,
        harness,
        overrides: <Override>[
          todayStatusProvider.overrideWith(
            (ref) => Stream<DayStatus?>.value(null),
          ),
        ],
      );
      expect(find.text('Noch keine Tagesziele'), findsOneWidget);
      expect(find.byType(ProgressRing), findsNothing);
      expect(find.text('Workouts diese Woche'), findsNothing);
    });

    testWidgets('(C04) "Ziele festlegen" opens the goal editor and back '
        'returns to the page', (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      final router = await pumpGoalsToday(
        tester,
        harness,
        overrides: <Override>[
          todayStatusOverride(statusOf(const <GoalProgress>[])),
        ],
      );
      await tester.tap(find.text('Ziele festlegen'));
      await settle(tester);
      expect(find.text('Seite /goals'), findsOneWidget);
      router.pop();
      await settle(tester);
      expect(find.text('Noch keine Tagesziele'), findsOneWidget);
    });

    testWidgets('(C04) goals that do not apply are not listed and not '
        'counted', (tester) async {
      await _pump(tester, <GoalProgress>[
        goalOf(GoalType.water, current: 2500, reached: true),
        goalOf(GoalType.steps, applicable: false),
        goalOf(GoalType.workoutDaily, applicable: false),
      ]);
      expect(find.text('1 von 1'), findsOneWidget);
      expect(find.text('Schritte'), findsNothing);
      expect(find.text('Workout heute'), findsNothing);
    });

    testWidgets('(C04) no step record is not a recorded 0', (tester) async {
      await _pump(tester, <GoalProgress>[
        goalOf(GoalType.steps, current: null),
      ]);
      expect(find.text('Noch keine Schritte eingetragen'), findsOneWidget);
      expect(find.textContaining('von 10.000'), findsNothing);
    });

    testWidgets('(C04) a reached goal above its target shows the real '
        'percentage, an almost reached one never reads 100 %', (tester) async {
      await _pump(tester, <GoalProgress>[
        goalOf(GoalType.water, current: 2800, reached: true),
        goalOf(GoalType.steps, current: 9950),
      ]);
      expect(find.text('2,8 von 2,5 l · 112 %'), findsOneWidget);
      expect(find.text('9.950 von 10.000 · 99 %'), findsOneWidget);
      expect(find.textContaining('100 %'), findsNothing);
    });
  });

  group('workout, habits and the weekly goal (BS-103, BS-99)', () {
    for (final (kind, status, detail) in <(WorkoutDayMarkKind, String, String)>[
      (
        WorkoutDayMarkKind.rest,
        'Ruhetag',
        'Ruhetag eingetragen · keine XP, Streak bleibt',
      ),
      (
        WorkoutDayMarkKind.skipped,
        'Übersprungen',
        'Training übersprungen · keine XP, Streak bleibt',
      ),
    ]) {
      testWidgets(
        '(C04, AT34) a ${kind.key} day is its own state and counts as reached',
        (tester) async {
          await _pump(
            tester,
            <GoalProgress>[
              goalOf(GoalType.water),
              goalOf(GoalType.workoutDaily, current: 1, reached: true),
            ],
            overrides: <Override>[
              _workoutDay(mark: kind),
              _weekOf(0),
            ],
          );
          expect(find.text('Workout heute'), findsOneWidget);
          expect(find.text(status), findsOneWidget);
          expect(find.text(detail), findsOneWidget);
          // Counted like a reached goal: 1 of 2.
          expect(find.text('1 von 2'), findsOneWidget);
          expect(_daily('Offen'), findsOneWidget);
          expect(_daily('Erreicht'), findsNothing);
        },
      );
    }

    testWidgets('(C04, AT34) a workout reaches the goal and is counted', (
      tester,
    ) async {
      await _pump(
        tester,
        <GoalProgress>[
          goalOf(GoalType.workoutDaily, current: 2, reached: true),
        ],
        overrides: <Override>[
          _workoutDay(workouts: <WorkoutEntry>[_workout('a'), _workout('b')]),
          _weekOf(2),
        ],
      );
      expect(find.text('2 Trainings eingetragen'), findsOneWidget);
      expect(_daily('Erreicht'), findsOneWidget);
      expect(find.text('1 von 1'), findsOneWidget);
    });

    testWidgets('(C04, AT34) no workout yet: the goal is open', (tester) async {
      await _pump(
        tester,
        <GoalProgress>[goalOf(GoalType.workoutDaily)],
        overrides: <Override>[_workoutDay(), _weekOf(0)],
      );
      expect(find.text('Noch kein Training eingetragen'), findsOneWidget);
      expect(_daily('Offen'), findsOneWidget);
      expect(find.text('0 von 1'), findsOneWidget);
    });

    testWidgets('(C04) the weekly goal stands apart and counts for nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        goalStates['some']!,
        overrides: <Override>[_weekOf(2)],
      );
      expect(find.text('WOCHENZIEL · NICHT IM TAGESRING'), findsOneWidget);
      expect(find.text('Workouts diese Woche'), findsOneWidget);
      expect(find.text('2 von 3 · 67 %'), findsOneWidget);
      // The ring is still 2 of 5: the week adds no goal and no reached one.
      expect(find.text('2 von 5'), findsOneWidget);
      expect(paintedArcs(tester), _arcs(AppColors.light, 2, 5));
      // Below the daily list.
      final daily = tester.getTopLeft(find.text('Aufgabe erledigen')).dy;
      final weekly = tester.getTopLeft(find.text('Workouts diese Woche')).dy;
      expect(weekly, greaterThan(daily));
    });

    testWidgets('(C04) the weekly goal is reached with the real count', (
      tester,
    ) async {
      await _pump(
        tester,
        goalStates['some']!,
        overrides: <Override>[_weekOf(4)],
      );
      expect(find.text('4 von 3 · 133 %'), findsOneWidget);
      // The week is reached, the ring still counts two reached goals.
      expect(
        find.descendant(
          of: find.byType(AppListGroup).last,
          matching: find.text('Erreicht'),
        ),
        findsOneWidget,
      );
      expect(_daily('Erreicht'), findsNWidgets(2));
      expect(find.text('2 von 5'), findsOneWidget);
    });

    testWidgets('(C04) without the focus module there is no weekly goal', (
      tester,
    ) async {
      final harness = await createHarness(
        tester,
        startedOn: _secondDay,
        enabledModules: <String>{'nutrition'},
      );
      await pumpGoalsToday(
        tester,
        harness,
        overrides: <Override>[
          todayStatusOverride(
            statusOf(<GoalProgress>[goalOf(GoalType.water, current: 100)]),
          ),
        ],
      );
      expect(find.text('Wasser'), findsOneWidget);
      expect(find.text('Workouts diese Woche'), findsNothing);
      expect(find.text('WOCHENZIEL · NICHT IM TAGESRING'), findsNothing);
    });

    testWidgets('(C04) the habits are goals of the day, one row each, with '
        'their names', (tester) async {
      await _pump(
        tester,
        <GoalProgress>[
          goalOf(GoalType.taskCompletion),
          habitGoalOf('a', checked: true),
          habitGoalOf('b'),
        ],
        overrides: <Override>[
          habitsProvider.overrideWith(
            (ref) => Stream<List<Habit>>.value(<Habit>[
              _habit('a', 'Lesen', HabitIcon.book),
              _habit('b', 'Dehnen', HabitIcon.flame),
            ]),
          ),
        ],
      );
      expect(find.text('1 von 3'), findsOneWidget);
      expect(find.text('Lesen'), findsOneWidget);
      expect(find.text('Dehnen'), findsOneWidget);
      expect(find.text('Heute abgehakt'), findsOneWidget);
      expect(find.text('Noch nicht abgehakt'), findsOneWidget);
      // After the task goal, in the order of the habit list.
      final task = tester.getTopLeft(find.text('Aufgabe erledigen')).dy;
      final first = tester.getTopLeft(find.text('Lesen')).dy;
      final second = tester.getTopLeft(find.text('Dehnen')).dy;
      expect(task, lessThan(first));
      expect(first, lessThan(second));
    });
  });

  group('the numbers are the numbers of the ring (BS-103, C04)', () {
    for (final entry in goalStates.entries) {
      testWidgets('${entry.key}: the head and the rows add up to the status', (
        tester,
      ) async {
        final status = statusOf(entry.value);
        await _pump(tester, entry.value);
        final fulfilled = status.fulfilledCount;
        final applicable = status.applicableCount;
        expect(find.text('$fulfilled von $applicable'), findsOneWidget);
        expect(
          _daily('Erreicht').evaluate().length,
          fulfilled,
          reason: 'one "Erreicht" per reached goal',
        );
        expect(
          _daily('Offen').evaluate().length,
          applicable - fulfilled,
          reason: 'one "Offen" per open goal',
        );
        expect(
          paintedArcs(tester),
          _arcs(AppColors.light, fulfilled, applicable),
        );
      });
    }
  });

  group('the rows open their module, "Ziele bearbeiten" the editor (BS-105)', () {
    // A page that is pushed over the page: back returns to it.
    for (final (title, path) in const <(String, String)>[
      ('Wasser', '/water'),
      ('Schritte', '/steps'),
      ('Fokus', '/focus'),
      ('Gewicht erfassen', '/weight'),
    ]) {
      testWidgets(
        '(C02) a tap on "$title" opens $path, and back shows the page again',
        (tester) async {
          final router = await _pump(tester, goalStates['some']!);
          await tester.tap(find.text(title));
          await settle(tester);
          expect(find.text('Seite $path'), findsOneWidget);
          expect(_top(router), path);
          router.pop();
          await settle(tester);
          expect(find.text('2 von 5'), findsOneWidget);
          expect(find.text(title), findsOneWidget);
        },
      );
    }

    testWidgets('(C02) "Aufgabe erledigen" opens the task list, a tab', (
      tester,
    ) async {
      final router = await _pump(tester, goalStates['some']!);
      await tester.tap(find.text('Aufgabe erledigen'));
      await settle(tester);
      expect(find.text('Seite /habits'), findsOneWidget);
      expect(_uri(router), '/habits?tab=tasks');
    });

    testWidgets('(C02) a habit opens the habit list, a tab', (tester) async {
      final router = await _pump(
        tester,
        <GoalProgress>[habitGoalOf('a')],
        overrides: <Override>[
          habitsProvider.overrideWith(
            (ref) => Stream<List<Habit>>.value(<Habit>[
              _habit('a', 'Lesen', HabitIcon.book),
            ]),
          ),
        ],
      );
      await tester.tap(find.text('Lesen'));
      await settle(tester);
      expect(find.text('Seite /habits'), findsOneWidget);
      expect(_uri(router), '/habits');
    });

    testWidgets('(C02) "Workout heute" and the weekly goal open the workout '
        'area', (tester) async {
      final overrides = <Override>[
        _workoutDay(mark: WorkoutDayMarkKind.rest),
        _weekOf(2),
      ];
      final goals = <GoalProgress>[
        goalOf(GoalType.water),
        goalOf(GoalType.workoutDaily, current: 1, reached: true),
      ];
      var router = await _pump(tester, goals, overrides: overrides);
      await tester.tap(find.text('Workout heute'));
      await settle(tester);
      expect(find.text('Seite /workouts'), findsOneWidget);
      router.pop();
      await settle(tester);

      router = await _pump(tester, goals, overrides: overrides);
      await tester.tap(find.text('Workouts diese Woche'));
      await settle(tester);
      expect(find.text('Seite /workouts'), findsOneWidget);
      expect(_top(router), '/workouts');
    });

    testWidgets('(C02) "Ziele bearbeiten" opens the goal editor, back shows '
        'the page as it was', (tester) async {
      final router = await _pump(
        tester,
        goalStates['some']!,
        overrides: <Override>[_weekOf(2)],
      );
      await tester.ensureVisible(find.text('Ziele bearbeiten'));
      await tester.pump();
      await tester.tap(find.text('Ziele bearbeiten'));
      await settle(tester);
      expect(find.text('Seite /goals'), findsOneWidget);
      expect(_top(router), '/goals');
      router.pop();
      await settle(tester);
      expect(find.text('2 von 5'), findsOneWidget);
      expect(find.text('Workouts diese Woche'), findsOneWidget);
    });

    testWidgets('"Ziele bearbeiten" is the last thing on the page, after the '
        'weekly goal', (tester) async {
      await _pump(
        tester,
        goalStates['some']!,
        overrides: <Override>[_weekOf(2)],
      );
      final weekly = tester.getTopLeft(find.text('Workouts diese Woche')).dy;
      final action = tester.getTopLeft(find.text('Ziele bearbeiten')).dy;
      expect(action, greaterThan(weekly));
    });

    testWidgets('without a daily goal there is "Ziele festlegen", not '
        '"Ziele bearbeiten"', (tester) async {
      await _pump(tester, const <GoalProgress>[]);
      expect(find.text('Ziele bearbeiten'), findsNothing);
      expect(find.text('Ziele festlegen'), findsOneWidget);
    });

    testWidgets('(AT34) every row is a button: its label ends with "öffnen", '
        'the tap area is at least 48 high', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, goalStates['some']!);
      for (final label in <String>[
        'Wasser, 1,5 von 2,5 Litern, 60 Prozent, noch offen, öffnen',
        'Schritte, 7.450 von 10.000 Schritten, 75 Prozent, noch offen, öffnen',
        'Fokus, 45 von 60 Minuten, 75 Prozent, noch offen, öffnen',
        'Gewicht erfassen, Heute gewogen, erreicht, öffnen',
        'Aufgabe erledigen, 2 Aufgaben erledigt, erreicht, öffnen',
      ]) {
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        expect(
          node,
          matchesSemantics(label: label, isButton: true, hasTapAction: true),
          reason: label,
        );
        expect(node.rect.height, greaterThanOrEqualTo(48), reason: label);
        expect(node.rect.width, greaterThanOrEqualTo(48), reason: label);
      }
      handle.dispose();
    });

    testWidgets('(AT34) "Ziele bearbeiten" is a button of at least 48 x 48', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, goalStates['some']!);
      await tester.ensureVisible(find.text('Ziele bearbeiten'));
      await tester.pump();
      final node = tester.getSemantics(
        find.bySemanticsLabel('Ziele bearbeiten'),
      );
      expect(
        node,
        matchesSemantics(
          label: 'Ziele bearbeiten',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(node.rect.height, greaterThanOrEqualTo(48));
      handle.dispose();
    });

    testWidgets('(AT33) a row shows a chevron, and gives it up when it '
        'stacks at large text', (tester) async {
      await _pump(tester, goalStates['some']!);
      // One per goal of the day, and one for the weekly goal.
      expect(find.byIcon(AppIcon.chevronRight.data), findsNWidgets(6));
      await _pump(tester, goalStates['some']!, textScale: 2.0);
      expect(find.byIcon(AppIcon.chevronRight.data), findsNothing);
    });

    testWidgets('a view without callbacks only shows: no button, no '
        'chevron, no editor action', (tester) async {
      final day = buildGoalsDay(
        status: statusOf(goalStates['some']!),
        today: goalsTestDay,
      );
      await pumpApp(
        tester,
        AppScaffold.subpage(
          title: 'Ziele heute',
          body: GoalsDayView(day: day, onSetGoals: () {}),
        ),
      );
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();
      expect(find.byIcon(AppIcon.chevronRight.data), findsNothing);
      expect(find.text('Ziele bearbeiten'), findsNothing);
      final node = tester.getSemantics(
        find.bySemanticsLabel(
          'Wasser, 1,5 von 2,5 Litern, 60 Prozent, noch offen',
        ),
      );
      expect(node, matchesSemantics(label: node.label));
      handle.dispose();
    });
  });

  group('what a screen reader hears (BS-103, AT34)', () {
    testWidgets('the summary is one element and so is every row', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, goalStates['some']!);
      expect(
        find.bySemanticsLabel(
          'Samstag, 3. Oktober. 2 von 5 erreicht. Noch 3 Ziele offen. '
          'Bleib dran!',
        ),
        findsOneWidget,
      );
      // The ring is a picture of the same numbers: it is not read again.
      expect(find.bySemanticsLabel('2 von 5 Zielen erreicht'), findsNothing);
      for (final label in <String>[
        'Wasser, 1,5 von 2,5 Litern, 60 Prozent, noch offen, öffnen',
        'Schritte, 7.450 von 10.000 Schritten, 75 Prozent, noch offen, öffnen',
        'Fokus, 45 von 60 Minuten, 75 Prozent, noch offen, öffnen',
        'Gewicht erfassen, Heute gewogen, erreicht, öffnen',
        'Aufgabe erledigen, 2 Aufgaben erledigt, erreicht, öffnen',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      // The bars and pills inside a row are not read on their own.
      expect(find.bySemanticsLabel('Offen'), findsNothing);
      expect(find.bySemanticsLabel('Erreicht'), findsNothing);
      handle.dispose();
    });

    testWidgets('a rest day is read as a rest day that counts as reached', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        <GoalProgress>[
          goalOf(GoalType.workoutDaily, current: 1, reached: true),
        ],
        overrides: <Override>[
          _workoutDay(mark: WorkoutDayMarkKind.rest),
          _weekOf(0),
        ],
      );
      expect(
        find.bySemanticsLabel(
          'Workout heute, Ruhetag, zählt als erreicht, keine XP, die Streak '
          'bleibt, öffnen',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the headings of the lists are headings', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        goalStates['some']!,
        overrides: <Override>[_weekOf(2)],
      );
      for (final heading in <String>[
        'TAGESZIELE',
        'WOCHENZIEL · NICHT IM TAGESRING',
      ]) {
        expect(
          tester.getSemantics(find.text(heading)),
          matchesSemantics(label: heading, isHeader: true),
        );
      }
      handle.dispose();
    });
  });

  group('layout at four widths and large text (BS-103, AT33, Q02)', () {
    for (final size in responsiveSizes) {
      for (final scale in const <double>[1.0, 2.0]) {
        testWidgets(
          'the whole page fits ${size.width.toInt()} px at text scale '
          '$scale: no overflow, tap targets, labels',
          (tester) async {
            await _pump(
              tester,
              _fullDay,
              overrides: _fullDayOverrides(),
              size: size,
              textScale: scale,
            );
            final handle = tester.ensureSemantics();
            expect(tester.takeException(), isNull);
            // Every part of the page can be scrolled to and lies inside the
            // width of the screen.
            for (final text in <String>[
              'Ziele heute',
              'Wasser',
              'Lesen',
              'Dehnen',
              'Workout heute',
              'Workouts diese Woche',
            ]) {
              final finder = find.text(text);
              await tester.ensureVisible(finder.first);
              await tester.pump();
              final rect = tester.getRect(finder.first);
              expect(rect.left, greaterThanOrEqualTo(-0.5), reason: text);
              expect(
                rect.right,
                lessThanOrEqualTo(size.width + 0.5),
                reason: text,
              );
            }
            await _expectAccessibleTargets(tester, size);
            handle.dispose();
          },
        );
      }
    }

    testWidgets('at 200 % the rows stack: the status below the name', (
      tester,
    ) async {
      await _pump(tester, goalStates['some']!, textScale: 2.0);
      final name = tester.getRect(find.text('Wasser'));
      final pill = tester.getRect(_daily('Offen').first);
      expect(pill.top, greaterThan(name.bottom - 1));
      expect(pill.left, lessThan(name.left + 5));
    });

    testWidgets('at 100 % the status stands right of the name', (tester) async {
      await _pump(tester, goalStates['some']!);
      final name = tester.getRect(find.text('Wasser'));
      final pill = tester.getRect(_daily('Offen').first);
      expect(pill.left, greaterThan(name.right));
      expect((pill.center.dy - name.center.dy).abs(), lessThan(8));
    });

    testWidgets('the ring grows with the text but stays inside its card', (
      tester,
    ) async {
      await _pump(
        tester,
        goalStates['some']!,
        textScale: 2.0,
        size: const Size(320, 640),
      );
      final ring = tester.getRect(find.byType(ProgressRing));
      final card = tester.getRect(find.byType(AppCard).first);
      expect(ring.left, greaterThanOrEqualTo(card.left));
      expect(ring.right, lessThanOrEqualTo(card.right));
      expect(ring.width, greaterThan(96));
    });
  });

  group('the three themes (BS-103, AT35, C06)', () {
    for (final theme in AppThemeVariant.values) {
      for (final (name, fulfilled, applicable) in const <(String, int, int)>[
        ('nothing', 0, 5),
        ('some', 2, 5),
        ('all', 5, 5),
      ]) {
        testWidgets(
          '${theme.name}: $name reached paints the ring from the tokens and '
          'keeps readable text',
          (tester) async {
            await _pump(tester, goalStates[name]!, theme: theme);
            expect(
              paintedArcs(tester),
              _arcs(theme.colors, fulfilled, applicable),
            );
            final handle = tester.ensureSemantics();
            expect(tester.takeException(), isNull);
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            handle.dispose();
          },
        );
      }

      testWidgets('${theme.name}: the pills, the banner and the weekly goal '
          'keep readable text', (tester) async {
        await _pump(
          tester,
          _fullDay,
          overrides: _fullDayOverrides(),
          theme: theme,
          size: const Size(393, 1800),
        );
        final handle = tester.ensureSemantics();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });

  group('loading and error (BS-103, Q01)', () {
    testWidgets('while the status is read only a neutral line appears, and '
        'only after a moment', (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      await pumpGoalsToday(
        tester,
        harness,
        overrides: <Override>[
          todayStatusProvider.overrideWith(
            (ref) => const Stream<DayStatus?>.empty(),
          ),
        ],
      );
      expect(find.text('Daten werden geladen …'), findsNothing);
      expect(find.byType(GoalsDayView), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Daten werden geladen …'), findsOneWidget);
      expect(find.text('Ziele heute'), findsOneWidget);
    });

    testWidgets('a failed read shows the error state and the retry brings '
        'the page back', (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      var reads = 0;
      await pumpGoalsToday(
        tester,
        harness,
        overrides: <Override>[
          todayStatusProvider.overrideWith((ref) {
            reads++;
            return reads == 1
                ? Stream<DayStatus?>.error(StateError('no read'))
                : Stream<DayStatus?>.value(statusOf(goalStates['some']!));
          }),
        ],
      );
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsOneWidget);
      expect(find.text('Wasser'), findsNothing);
      await tester.tap(find.text('Erneut versuchen'));
      await settle(tester);
      expect(find.byType(ErrorState), findsNothing);
      expect(find.text('2 von 5'), findsOneWidget);
    });
  });

  group('a day that is not today (BS-103, BS-93 prepared)', () {
    testWidgets('(C04) a status of another day, as BS-93 will put it into the '
        'dashboard view, is shown as that day', (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      await pumpGoalsToday(
        tester,
        harness,
        overrides: <Override>[
          todayStatusOverride(
            statusOf(goalStates['some']!, date: LocalDate(2026, 10, 1)),
          ),
        ],
      );
      expect(find.text('Nicht heute'), findsOneWidget);
      expect(find.text('1. Oktober · nur ansehen'), findsOneWidget);
      expect(find.text('Donnerstag, 1. Oktober'), findsOneWidget);
      expect(find.text('2 von 5 erreicht'), findsOneWidget);
      expect(find.text('Du siehst die Werte dieses Tages.'), findsOneWidget);
      // The words of the past, no weekly goal, and no way back yet: the page
      // that pages through the days wires it.
      expect(find.text('Gewogen'), findsOneWidget);
      expect(find.text('Workouts diese Woche'), findsNothing);
      expect(find.text('Zurück zu heute'), findsNothing);
      // The rows still lead to their modules.
      expect(find.byIcon(AppIcon.chevronRight.data), findsNWidgets(5));
    });

    Future<void> pumpPast(
      WidgetTester tester, {
      VoidCallback? onBack,
      double textScale = 1.0,
      Size size = const Size(393, 852),
    }) async {
      final day = buildGoalsDay(
        status: statusOf(goalStates['some']!, date: LocalDate(2026, 9, 12)),
        today: goalsTestDay,
        week: _week(2),
      );
      await pumpApp(
        tester,
        AppScaffold.subpage(
          title: 'Ziele heute',
          body: GoalsDayView(
            day: day,
            onSetGoals: () {},
            onBackToToday: onBack,
          ),
        ),
        textScale: textScale,
        size: size,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the note says it, the texts speak of the day and the way '
        'back works', (tester) async {
      var back = 0;
      await pumpPast(tester, onBack: () => back++);
      expect(find.byType(NotTodayBanner), findsOneWidget);
      expect(find.text('Nicht heute'), findsOneWidget);
      expect(find.text('12. September · nur ansehen'), findsOneWidget);
      expect(find.text('Samstag, 12. September'), findsOneWidget);
      expect(find.text('2 von 5 erreicht'), findsOneWidget);
      expect(find.text('Du siehst die Werte dieses Tages.'), findsOneWidget);
      // The numbers of that day, the same rows, no weekly goal.
      expect(find.text('1,5 von 2,5 l · 60 %'), findsOneWidget);
      expect(find.text('Workouts diese Woche'), findsNothing);
      expect(find.text('Gewogen'), findsOneWidget);
      await tester.tap(find.text('Zurück zu heute'));
      await tester.pump();
      expect(back, 1);
    });

    testWidgets('without a way back the note has no action', (tester) async {
      await pumpPast(tester);
      expect(find.text('Nicht heute'), findsOneWidget);
      expect(find.text('Zurück zu heute'), findsNothing);
    });

    testWidgets('the way back is a button of at least 48 x 48', (tester) async {
      await pumpPast(tester, onBack: () {});
      final handle = tester.ensureSemantics();
      final node = tester.getSemantics(
        find.bySemanticsLabel('Zurück zu heute'),
      );
      expect(node.rect.width, greaterThanOrEqualTo(48));
      expect(node.rect.height, greaterThanOrEqualTo(48));
      expect(
        node,
        matchesSemantics(
          label: 'Zurück zu heute',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('at 320 px and 200 % the note stacks and nothing overflows', (
      tester,
    ) async {
      await pumpPast(
        tester,
        onBack: () {},
        textScale: 2.0,
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
      final note = tester.getRect(find.text('Nicht heute'));
      final action = tester.getRect(find.text('Zurück zu heute'));
      expect(action.top, greaterThan(note.bottom - 1));
    });
  });
}
