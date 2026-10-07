import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/presentation/workout_day_sheet.dart';

import '../../../support/pump_app.dart';
import '../support/focus_ui_kit.dart';

/// The workout area (`/workouts`) with the optional daily goal "Workout
/// heute" (BS-99): the day card above the week, the way to the sheet "Wie war
/// dein Tag?", taking a mark back, and the row that leads to the goal. "Today"
/// is Saturday 2026-10-03.
void main() {
  Future<void> pumpArea(
    WidgetTester tester,
    FocusUi ui, {
    Size size = const Size(393, 852),
    double textScale = 1.0,
  }) async {
    await pumpFocusApp(
      tester,
      ui,
      initialLocation: '/workouts',
      size: size,
      textScale: textScale,
    );
  }

  Finder inTodayCard(Finder matching) => find.descendant(
    of: find.ancestor(of: find.text('Heute'), matching: find.byType(AppCard)),
    matching: matching,
  );

  group('the goal is off (default)', () {
    testWidgets(
      '(BS-99) no day card; a row names the goal as off and leads to the goal editor',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.addWorkout(ui, title: 'Laufen');
        await pumpArea(tester, ui);

        expect(find.text('Heute'), findsNothing);
        expect(find.text('Wie war dein Tag?'), findsNothing);
        expect(find.text('Tagesziel „Workout heute“'), findsOneWidget);
        expect(
          find.text('Aus. Einschalten bei den Zielen, gilt ab morgen.'),
          findsOneWidget,
        );
        expect(find.text('Wochenziel ändern'), findsOneWidget);

        await tester.tap(find.text('Tagesziel „Workout heute“'));
        await tester.pumpAndSettle();
        expect(find.text('GOALS-STUB'), findsOneWidget);
      },
    );

    testWidgets(
      '(BS-99, AT24) switched on today the row says "Ab morgen ein", today still has no day card',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.addWorkout(ui, title: 'Laufen');
        await tester.runCommand(
          () => ui.container
              .read(goalsCommandsProvider)
              .update(
                commandId: ui.ids.newId(),
                changes: {GoalType.workoutDaily: const GoalSetting()},
              ),
        );
        await pumpArea(tester, ui);
        expect(
          find.text(
            'Ab morgen ein. Training, Ruhetag oder Überspringen zählt dann '
            'als erreicht.',
          ),
          findsOneWidget,
        );
        expect(find.text('Heute'), findsNothing);

        ui.harness.clock.advance(const Duration(days: 1));
        ui.container.read(todayProvider.notifier).refresh();
        await tester.settleDb();
        expect(
          find.text('Heute'),
          findsOneWidget,
          reason: 'tomorrow it counts',
        );
        expect(
          find.text(
            'Ein. Training, Ruhetag oder Überspringen zählt als erreicht.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('the goal is on: the day card', () {
    testWidgets(
      '(BS-99) an open day asks how it was; the sheet leads to a rest day that can be taken back',
      (tester) async {
        final ui = await createFocusUi(tester, workoutDailyGoal: true);
        await tester.addWorkout(
          ui,
          title: 'Gestern',
          at: DateTime.utc(2026, 10, 2, 8),
        );
        await pumpArea(tester, ui);

        expect(find.text('Heute'), findsOneWidget);
        expect(find.text('Ziel: Workout heute'), findsOneWidget);
        expect(find.text('Noch kein Training'), findsOneWidget);
        expect(find.text('Heute offen'), findsOneWidget);
        expect(
          find.text(
            'Ein. Training, Ruhetag oder Überspringen zählt als erreicht.',
          ),
          findsOneWidget,
        );

        await tester.tap(inTodayCard(find.text('Wie war dein Tag?')));
        await tester.pumpAndSettle();
        expect(find.byType(WorkoutDaySheet), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(WorkoutDaySheet),
            matching: find.text('Ruhetag'),
          ),
        );
        await tester.settleDb();
        await tester.pumpAndSettle();

        expect(inTodayCard(find.text('Ruhetag')), findsOneWidget);
        expect(
          find.text('Zählt als erreicht, keine XP. Die Streak bleibt.'),
          findsOneWidget,
        );
        expect(ui.feedback.last!.message, 'Ruhetag eingetragen');

        await tester.tap(inTodayCard(find.text('Rückgängig')));
        await tester.settleDb();
        expect(inTodayCard(find.text('Noch kein Training')), findsOneWidget);
        expect(ui.feedback.last!.message, 'Eintrag für heute zurückgenommen');
      },
    );

    testWidgets('(BS-99) a skipped day is shown as such, with the take back', (
      tester,
    ) async {
      final ui = await createFocusUi(tester, workoutDailyGoal: true);
      await tester.addWorkout(
        ui,
        title: 'Gestern',
        at: DateTime.utc(2026, 10, 2, 8),
      );
      await tester.markWorkoutDay(ui, WorkoutDayMarkKind.skipped);
      await pumpArea(tester, ui);
      expect(inTodayCard(find.text('Übersprungen')), findsOneWidget);
      expect(inTodayCard(find.text('Rückgängig')), findsOneWidget);
      expect(find.byIcon(workoutSkipIcon), findsOneWidget);
    });

    testWidgets(
      '(BS-99) a workout today is shown as the training of the day, without an action',
      (tester) async {
        final ui = await createFocusUi(tester, workoutDailyGoal: true);
        await tester.addWorkout(ui, title: 'Upper Body');
        await pumpArea(tester, ui);
        expect(inTodayCard(find.text('Upper Body')), findsOneWidget);
        expect(inTodayCard(find.byIcon(AppIcon.check.data)), findsOneWidget);
        expect(inTodayCard(find.byType(SecondaryButton)), findsNothing);
        expect(find.text('Wie war dein Tag?'), findsNothing);
      },
    );

    testWidgets(
      '(BS-99) without any workout the day card is still there next to the empty state: a rest day needs no workout',
      (tester) async {
        final ui = await createFocusUi(tester, workoutDailyGoal: true);
        await pumpArea(tester, ui);
        expect(find.text('Noch kein Training'), findsNWidgets(2));
        expect(find.text('Heute'), findsOneWidget);
        expect(find.text('Wie war dein Tag?'), findsOneWidget);

        await tester.tap(find.text('Wie war dein Tag?'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(WorkoutDaySheet),
            matching: find.text('Heute überspringen'),
          ),
        );
        await tester.settleDb();
        await tester.pumpAndSettle();
        expect(inTodayCard(find.text('Übersprungen')), findsOneWidget);
      },
    );

    testWidgets(
      '(BS-99) without any workout and with the goal off there is the empty state only',
      (tester) async {
        final ui = await createFocusUi(tester);
        await pumpArea(tester, ui);
        expect(find.text('Heute'), findsNothing);
        expect(find.text('Noch kein Training'), findsOneWidget);
        expect(find.text('Training eintragen'), findsOneWidget);
      },
    );

    testWidgets(
      '(BS-99) the week card keeps counting only workouts: a rest day today is not one of them',
      (tester) async {
        final ui = await createFocusUi(tester, workoutDailyGoal: true);
        await tester.addWorkout(
          ui,
          title: 'Montag',
          at: DateTime.utc(2026, 9, 28, 8),
        );
        await tester.markWorkoutDay(ui, WorkoutDayMarkKind.rest);
        await pumpArea(tester, ui);
        expect(
          find.textContaining('1 / 3 Trainings', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('2 fehlen'), findsOneWidget);
      },
    );
  });

  group('labels and layout', () {
    testWidgets(
      '(BS-99, AT34) the day card is read with its state; the buttons have labels',
      (tester) => withSemantics(tester, () async {
        final ui = await createFocusUi(tester, workoutDailyGoal: true);
        await tester.addWorkout(
          ui,
          title: 'Gestern',
          at: DateTime.utc(2026, 10, 2, 8),
        );
        await pumpArea(tester, ui);
        expect(
          find.bySemanticsLabel('Noch kein Training, Heute offen'),
          findsOneWidget,
        );
        await tester.markWorkoutDay(ui, WorkoutDayMarkKind.rest);
        await tester.pump();
        expect(
          find.bySemanticsLabel(
            'Ruhetag, Zählt als erreicht, keine XP. Die Streak bleibt., '
            'Tagesziel erreicht',
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Ruhetag rückgängig machen'),
          findsOneWidget,
        );
      }),
    );

    for (final size in responsiveSizes) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '(BS-99, AT33) the area with the day card fits ${size.width.toInt()} px at text scale $scale in every state',
          (tester) => withSemantics(tester, () async {
            final ui = await createFocusUi(tester, workoutDailyGoal: true);
            await tester.addWorkout(
              ui,
              title: 'Gestern',
              at: DateTime.utc(2026, 10, 2, 8),
            );
            await pumpArea(tester, ui, size: size, textScale: scale);

            Future<void> check(String state) async {
              await tester.pump();
              expect(
                tester.takeException(),
                isNull,
                reason: '$state: overflow',
              );
              await expectLater(
                tester,
                meetsGuideline(androidTapTargetGuideline),
              );
              await expectLater(
                tester,
                meetsGuideline(labeledTapTargetGuideline),
              );
            }

            await check('open');
            final rest = await tester.markWorkoutDay(
              ui,
              WorkoutDayMarkKind.rest,
            );
            await check('rest');
            await tester.runCommand(
              () => ui.workoutDayMarkRepository.unmark(
                commandId: ui.ids.newId(),
                id: rest.id,
              ),
            );
            await tester.addWorkout(ui, title: 'Heute trainiert');
            await check('workout');
          }),
        );
      }
    }
  });
}
