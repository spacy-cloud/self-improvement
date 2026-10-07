import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/focus_module.dart';

import '../../../support/pump_app.dart';
import '../support/focus_ui_kit.dart';

/// Writes a PNG of the Workout card in its four states, of the sheet "Wie war
/// dein Tag?" and of the workout area below `build/workout_day/` for the visual
/// comparison with the Figma frames `4123:316`, `4117:473` (Hell), `4117:770`
/// (Dunkel) and `4117:1067` (OLED). Only runs when the environment variable
/// WORKOUT_DAY_PNG is set, so the normal test run stays fast:
///
///     WORKOUT_DAY_PNG=1 flutter test test/features/focus/presentation/workout_day_visual_test.dart
void main() {
  if (!Platform.environment.containsKey('WORKOUT_DAY_PNG')) {
    return;
  }
  const dir = 'build/workout_day';

  Future<void> pumpCards(
    WidgetTester tester,
    FocusUi ui, {
    AppThemeVariant theme = AppThemeVariant.light,
    double textScale = 1.0,
    Size size = const Size(393, 852),
  }) async {
    final cards = const FocusModule().dashboardCards;
    await pumpRouterApp(
      tester,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: AdaptiveGrid(
                minCellWidth: 158,
                children: [
                  for (final card in cards)
                    Consumer(
                      builder: (context, ref, _) => card.builder(context, ref),
                    ),
                ],
              ),
            ),
          ),
        ),
        ...ui.routes.where((r) => r is GoRoute && r.path != '/'),
      ],
      initialLocation: '/',
      container: ui.container,
      theme: theme,
      textScale: textScale,
      size: size,
    );
    await tester.settleDb();
  }

  Future<void> cardShots(WidgetTester tester, FocusUi ui, String name) async {
    await pumpCards(tester, ui);
    await savePng(tester, '$dir/card-$name.png');
    await pumpCards(tester, ui, size: const Size(320, 640), textScale: 2.0);
    await savePng(tester, '$dir/card-$name-320-x2.png');
    await pumpCards(tester, ui, theme: AppThemeVariant.dark);
    await savePng(tester, '$dir/card-$name-dark.png');
    await pumpCards(tester, ui, theme: AppThemeVariant.oled);
    await savePng(tester, '$dir/card-$name-oled.png');
  }

  testWidgets('card: open', (tester) async {
    final ui = await createFocusUi(tester, workoutDailyGoal: true);
    await cardShots(tester, ui, 'open');
  });

  testWidgets('card: workout', (tester) async {
    final ui = await createFocusUi(tester, workoutDailyGoal: true);
    await tester.addWorkout(
      ui,
      title: 'Upper Body',
      groups: [
        MuscleGroup.chest,
        MuscleGroup.shoulders,
        MuscleGroup.back,
        MuscleGroup.biceps,
        MuscleGroup.triceps,
      ],
    );
    await cardShots(tester, ui, 'trained');
  });

  testWidgets('card: rest day', (tester) async {
    final ui = await createFocusUi(tester, workoutDailyGoal: true);
    await tester.markWorkoutDay(ui, WorkoutDayMarkKind.rest);
    await cardShots(tester, ui, 'rest');
  });

  testWidgets('card: skipped day', (tester) async {
    final ui = await createFocusUi(tester, workoutDailyGoal: true);
    await tester.markWorkoutDay(ui, WorkoutDayMarkKind.skipped);
    await cardShots(tester, ui, 'skipped');
  });

  testWidgets('card: the week, goal off', (tester) async {
    final ui = await createFocusUi(tester);
    await tester.addWorkout(ui, title: 'Upper Body');
    await cardShots(tester, ui, 'week');
  });

  testWidgets('the sheet', (tester) async {
    final ui = await createFocusUi(tester, workoutDailyGoal: true);
    for (final (name, theme, size, scale) in [
      ('light', AppThemeVariant.light, const Size(393, 852), 1.0),
      ('dark', AppThemeVariant.dark, const Size(393, 852), 1.0),
      ('oled', AppThemeVariant.oled, const Size(393, 852), 1.0),
      ('320-x2', AppThemeVariant.light, const Size(320, 640), 2.0),
    ]) {
      await pumpCards(tester, ui, theme: theme, size: size, textScale: scale);
      await tester.tap(find.text('Wie war dein Tag?'));
      await tester.settleDb();
      await savePng(tester, '$dir/sheet-$name.png');
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.settleDb();
    }
  });

  testWidgets('the workout area', (tester) async {
    final ui = await createFocusUi(tester, workoutDailyGoal: true);
    await tester.addWorkout(ui, title: 'Upper Body');
    await pumpFocusApp(tester, ui, initialLocation: '/workouts');
    await savePng(tester, '$dir/area-trained.png');
  });
}
