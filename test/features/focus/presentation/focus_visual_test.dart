import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_intensity.dart';

import '../../../support/pump_app.dart';
import '../support/focus_ui_kit.dart';

/// Writes a PNG of every focus and workout screen below `build/focus_ui/` for
/// the visual comparison with the Figma frames. Only runs when the environment
/// variable FOCUS_UI_PNG is set, so the normal test run stays fast:
///
///     FOCUS_UI_PNG=1 flutter test test/features/focus/presentation/focus_visual_test.dart
void main() {
  final enabled = Platform.environment.containsKey('FOCUS_UI_PNG');
  const dir = 'build/focus_ui';

  Future<FocusUi> seeded(WidgetTester tester) async {
    // 17:00 in Berlin on Saturday 2026-10-03.
    final ui = await createFocusUi(tester, nowIso: '2026-10-03T15:00:00Z');
    ui.harness.clock.setNow(DateTime.utc(2026, 10, 3, 7, 10));
    await tester.completeFocus(
      ui,
      seconds: 1500,
      category: FocusCategory.learning,
    );
    ui.harness.clock.setNow(DateTime.utc(2026, 10, 3, 12, 30));
    await tester.completeFocus(
      ui,
      seconds: 1200,
      plannedSeconds: 1200,
      category: FocusCategory.reading,
    );
    ui.harness.clock.setNow(DateTime.utc(2026, 10, 3, 15));
    return ui;
  }

  Future<void> shots(
    WidgetTester tester,
    FocusUi ui,
    String name,
    String location,
  ) async {
    await pumpFocusApp(tester, ui, initialLocation: location);
    await tester.settleDb();
    await savePng(tester, '$dir/$name.png');
    await pumpFocusApp(
      tester,
      ui,
      initialLocation: location,
      size: const Size(320, 640),
      textScale: 2.0,
    );
    await tester.settleDb();
    await savePng(tester, '$dir/$name-320-x2.png');
  }

  testWidgets('start screen', (tester) async {
    final ui = await seeded(tester);
    await shots(tester, ui, 'start', '/focus');
  }, skip: !enabled);

  testWidgets('running, paused and awaiting', (tester) async {
    final ui = await createFocusUi(tester, nowIso: '2026-10-03T08:00:00Z');
    final id = await tester.startFocus(ui);
    ui.advance(888);
    await shots(tester, ui, 'running', '/focus/session');
    await tester.runCommand(
      () => ui.focusRepository.pause(commandId: ui.harness.ids.newId(), id: id),
    );
    ui.advance(120);
    await shots(tester, ui, 'paused', '/focus/session');
    await tester.runCommand(
      () =>
          ui.focusRepository.resume(commandId: ui.harness.ids.newId(), id: id),
    );
    ui.advance(1500);
    await restoreFocus(tester, ui);
    await shots(tester, ui, 'awaiting', '/focus/session');
  }, skip: !enabled);

  testWidgets('history and detail', (tester) async {
    final ui = await seeded(tester);
    await shots(tester, ui, 'history', '/focus/history');
    final id = await tester.completeFocus(ui, seconds: 600);
    await shots(tester, ui, 'detail', '/focus/history/$id');
  }, skip: !enabled);

  testWidgets('workouts', (tester) async {
    final ui = await createFocusUi(tester, nowIso: '2026-10-03T15:00:00Z');
    await tester.addWorkout(
      ui,
      title: 'Upper Body',
      minutes: 60,
      groups: [
        MuscleGroup.chest,
        MuscleGroup.shoulders,
        MuscleGroup.back,
        MuscleGroup.biceps,
        MuscleGroup.triceps,
      ],
      intensity: WorkoutIntensity.moderate,
      at: DateTime.utc(2026, 10, 3, 14, 30),
    );
    await tester.addWorkout(
      ui,
      title: 'Lower Body',
      minutes: 45,
      groups: [MuscleGroup.legs],
      intensity: WorkoutIntensity.high,
      at: DateTime.utc(2026, 9, 29, 16, 10),
    );
    await tester.addWorkout(
      ui,
      category: TrainingCategory.cardio,
      title: 'Laufen',
      minutes: 30,
      intensity: WorkoutIntensity.low,
      at: DateTime.utc(2026, 9, 21, 5),
    );
    await shots(tester, ui, 'workout-overview', '/workouts');
    await shots(tester, ui, 'workout-all', '/workouts/all');
    await shots(tester, ui, 'workout-new', '/workouts/new');
  }, skip: !enabled);
}
