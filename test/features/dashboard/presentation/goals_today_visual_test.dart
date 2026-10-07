import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/features/dashboard/domain/goals_day.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/goals_day_view.dart';
import 'package:self_improvement/features/focus/application/workout_day_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/workout_day_mark.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/dashboard_test_kit.dart';
import '../support/goals_today_kit.dart';

/// Writes a PNG of "Ziele heute" in its states and of the day card on Home to
/// `build/goals_today/` for the visual comparison with the Figma frames
/// `4112:60` (Hell), `4113:160` (Dunkel), `4113:270` (OLED), `4112:186`,
/// `4112:304`, `4112:444`, `4112:509`, `4114:501` (200 %), `4114:327`,
/// `4114:186`, `4115:249` and `4115:407` (gedrückt). Only runs when the
/// environment variable GOALS_TODAY_PNG is set, so the normal test run stays
/// fast:
///
///     GOALS_TODAY_PNG=1 flutter test test/features/dashboard/presentation/goals_today_visual_test.dart
void main() {
  if (!Platform.environment.containsKey('GOALS_TODAY_PNG')) {
    return;
  }
  const dir = 'build/goals_today';
  final secondDay = LocalDate(2026, 10, 2);

  Future<void> shot(
    WidgetTester tester,
    String name,
    List<GoalProgress> goals, {
    AppThemeVariant theme = AppThemeVariant.light,
    double textScale = 1.0,
    Size size = const Size(393, 852),
    List<Override> overrides = const <Override>[],
  }) async {
    final harness = await createHarness(tester, startedOn: secondDay);
    await pumpGoalsToday(
      tester,
      harness,
      overrides: <Override>[todayStatusOverride(statusOf(goals)), ...overrides],
      theme: theme,
      textScale: textScale,
      size: size,
    );
    await tester.pumpAndSettle();
    await savePng(tester, '$dir/$name.png');
  }

  for (final theme in AppThemeVariant.values) {
    testWidgets('some reached, ${theme.name}', (tester) async {
      await shot(
        tester,
        'some-${theme.name}',
        goalStates['some']!,
        theme: theme,
        overrides: <Override>[
          workoutWeekSummaryProvider.overrideWithValue(
            AsyncData<WorkoutWeekSummary>(
              WorkoutWeekSummary(
                weekStart: LocalDate(2026, 9, 28),
                entryCount: 0,
                totalMinutes: 0,
                weeklyTarget: 3,
              ),
            ),
          ),
        ],
      );
    });
  }

  for (final name in <String>['nothing', 'all', 'one']) {
    testWidgets(name, (tester) async {
      await shot(tester, name, goalStates[name]!);
    });
  }

  testWidgets('no goal', (tester) async {
    await shot(tester, 'none', const <GoalProgress>[]);
  });

  testWidgets('some reached at 200 % on 320 px', (tester) async {
    await shot(
      tester,
      'some-x2',
      goalStates['some']!,
      textScale: 2.0,
      size: const Size(320, 640),
    );
  });

  testWidgets('some reached at 200 % on 393 px', (tester) async {
    await shot(
      tester,
      'some-x2-393',
      goalStates['some']!,
      textScale: 2.0,
      size: const Size(393, 1700),
    );
  });

  testWidgets('with a rest day and the weekly goal', (tester) async {
    await shot(
      tester,
      'workout-week',
      <GoalProgress>[
        ...goalStates['some']!,
        goalOf(GoalType.workoutDaily, current: 1, reached: true),
        habitGoalOf('h', checked: true),
      ],
      size: const Size(393, 1100),
      overrides: <Override>[
        workoutDayStateProvider.overrideWithValue(
          AsyncData<WorkoutDayState>(
            WorkoutDayState(
              date: goalsTestDay,
              workouts: const [],
              mark: WorkoutDayMark(
                id: 'm',
                date: goalsTestDay,
                kind: WorkoutDayMarkKind.rest,
                timezoneId: 'Europe/Berlin',
                rowVersion: 1,
              ),
            ),
          ),
        ),
        workoutWeekSummaryProvider.overrideWithValue(
          AsyncData<WorkoutWeekSummary>(
            WorkoutWeekSummary(
              weekStart: LocalDate(2026, 9, 28),
              entryCount: 2,
              totalMinutes: 90,
              weeklyTarget: 3,
            ),
          ),
        ),
      ],
    );
  });

  testWidgets('a past day', (tester) async {
    final day = buildGoalsDay(
      status: statusOf(goalStates['some']!, date: LocalDate(2026, 9, 12)),
      today: goalsTestDay,
    );
    await pumpApp(
      tester,
      AppScaffold.subpage(
        title: 'Ziele heute',
        body: GoalsDayView(day: day, onSetGoals: () {}, onBackToToday: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await savePng(tester, '$dir/past.png');
  });

  for (final theme in AppThemeVariant.values) {
    testWidgets('home card, ${theme.name}', (tester) async {
      final harness = await createHarness(tester, startedOn: secondDay);
      await pumpHome(
        tester,
        harness,
        theme: theme,
        overrides: <Override>[
          todayStatusOverride(statusOf(goalStates['some']!)),
        ],
      );
      await tester.pumpAndSettle();
      await savePng(tester, '$dir/home-${theme.name}.png');
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Dein Tag im Überblick')) +
            const Offset(0, 90),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await savePng(tester, '$dir/home-pressed-${theme.name}.png');
      await gesture.cancel();
    });
  }
}
