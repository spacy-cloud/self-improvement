import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/workout_day_providers.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/focus_module.dart';
import 'package:self_improvement/features/focus/presentation/workout_day_sheet.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/focus_ui_kit.dart';

/// The Workout card of the dashboard with the optional daily goal "Workout
/// heute" (BS-99, Figma `4123:316`): the four states of the day, the sheet "Wie
/// war dein Tag?", taking a mark back, and the week as before while the goal is
/// off.
void main() {
  Finder rich(String text) => find.text(text, findRichText: true);

  Future<GoRouter> pumpCards(
    WidgetTester tester,
    FocusUi ui, {
    Size size = const Size(393, 852),
    double textScale = 1.0,
    AppThemeVariant theme = AppThemeVariant.light,
  }) async {
    final cards = const FocusModule().dashboardCards;
    final router = await pumpRouterApp(
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
      size: size,
      textScale: textScale,
      theme: theme,
    );
    await tester.settleDb();
    return router;
  }

  /// Taps "Wie war dein Tag?" on the card and answers in the sheet.
  Future<void> answer(WidgetTester tester, String text) async {
    await tester.tap(find.text('Wie war dein Tag?'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutDaySheet), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(WorkoutDaySheet),
        matching: find.text(text),
      ),
    );
    await tester.settleDb();
    await tester.pumpAndSettle();
  }

  Future<List<WorkoutDayMarkRow>> markRows(
    WidgetTester tester,
    FocusUi ui,
  ) async => (await tester.runAsync(
    () => ui.database.select(ui.database.workoutDayMarks).get(),
  ))!;

  group('the goal is off (default): the week as before', () {
    testWidgets(
      '(BS-99, AT20) the card shows the weekly count, the ring and "Training eintragen"; no question about the day',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.addWorkout(ui, title: 'Laufen', minutes: 30);
        await pumpCards(tester, ui);

        expect(rich('1 / 3 Trainings'), findsOneWidget);
        expect(find.text('Zuletzt: Laufen'), findsOneWidget);
        expect(find.text('Training eintragen'), findsOneWidget);
        expect(find.byType(ProgressRing), findsOneWidget);
        expect(find.text('Wie war dein Tag?'), findsNothing);
        expect(find.text('Noch kein Training'), findsNothing);
        expect(find.text('Heute offen'), findsNothing);
      },
    );

    testWidgets(
      '(BS-99) a rest day set elsewhere changes nothing on the card while the goal is off',
      (tester) async {
        final ui = await createFocusUi(tester);
        await tester.markWorkoutDay(ui, WorkoutDayMarkKind.rest);
        await pumpCards(tester, ui);
        expect(rich('0 / 3 Trainings'), findsOneWidget);
        expect(rich('Ruhetag'), findsNothing);
      },
    );

    testWidgets(
      '(BS-99, AT24) switched on today the goal starts tomorrow: today stays the week, the next day asks',
      (tester) async {
        final ui = await createFocusUi(tester);
        await pumpCards(tester, ui);
        expect(rich('0 / 3 Trainings'), findsOneWidget);

        await tester.runCommand(
          () => ui.container
              .read(goalsCommandsProvider)
              .update(
                commandId: ui.ids.newId(),
                changes: {GoalType.workoutDaily: const GoalSetting()},
              ),
        );
        expect(rich('0 / 3 Trainings'), findsOneWidget, reason: 'still today');
        expect(find.text('Wie war dein Tag?'), findsNothing);

        ui.harness.clock.advance(const Duration(days: 1));
        ui.container.read(todayProvider.notifier).refresh();
        await tester.settleDb();
        expect(rich('Noch kein Training'), findsOneWidget);
        expect(find.text('Wie war dein Tag?'), findsOneWidget);
        expect(find.textContaining('Trainings'), findsNothing);
      },
    );
  });

  group('the goal is on: open day', () {
    testWidgets(
      '(BS-99) shows that nothing is logged, that the day is open, and asks how it was',
      (tester) async {
        final ui = await createFocusUi(tester, workoutDailyGoal: true);
        await pumpCards(tester, ui);

        expect(find.text('Workout'), findsOneWidget);
        expect(rich('Noch kein Training'), findsOneWidget);
        expect(find.text('Heute offen'), findsOneWidget);
        expect(find.text('Wie war dein Tag?'), findsOneWidget);
        expect(find.byType(ProgressRing), findsNothing, reason: 'not the week');
        expect(find.textContaining('/ 3'), findsNothing);
      },
    );

    testWidgets('(BS-99) a tap on the body still opens the workout area', (
      tester,
    ) async {
      final ui = await createFocusUi(tester, workoutDailyGoal: true);
      final router = await pumpCards(tester, ui);
      await tester.tap(find.text('Workout'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/workouts');
    });

    testWidgets(
      '(BS-99) the question opens the sheet; "Training eintragen" leads to the form and marks nothing',
      (tester) async {
        final ui = await createFocusUi(tester, workoutDailyGoal: true);
        final router = await pumpCards(tester, ui);
        await answer(tester, 'Training eintragen');
        expect(router.state.uri.path, '/workouts/new');
        expect(await markRows(tester, ui), isEmpty);
        expect(ui.feedback.events, isEmpty);
      },
    );

    testWidgets(
      '(BS-99, AT12) "Ruhetag" marks today: the card shows it at once, the message offers "Rückgängig", no XP',
      (tester) async {
        final ui = await createFocusUi(
          tester,
          workoutDailyGoal: true,
          realProjection: true,
        );
        await pumpCards(tester, ui);
        await answer(tester, 'Ruhetag');

        expect(rich('Ruhetag'), findsOneWidget);
        expect(
          find.text('Zählt als erreicht, keine XP. Die Streak bleibt.'),
          findsOneWidget,
        );
        expect(find.text('Rückgängig'), findsOneWidget);
        expect(find.text('Wie war dein Tag?'), findsNothing);
        expect(find.byIcon(workoutRestIcon), findsOneWidget);

        final rows = await markRows(tester, ui);
        expect(rows.single.kind, 'rest');
        expect(rows.single.localDate, LocalDate(2026, 10, 3));
        expect(ui.feedback.last!.kind, 'saved');
        expect(ui.feedback.last!.message, 'Ruhetag eingetragen');
        expect(ui.feedback.last!.undo, isNotNull);
        expect(await tester.xpAwards(ui), isEmpty, reason: 'no XP');
      },
    );

    testWidgets(
      '(BS-99) "Heute überspringen" marks today as skipped with the same rules',
      (tester) async {
        final ui = await createFocusUi(
          tester,
          workoutDailyGoal: true,
          realProjection: true,
        );
        await pumpCards(tester, ui);
        await answer(tester, 'Heute überspringen');

        expect(rich('Übersprungen'), findsOneWidget);
        expect(
          find.text('Zählt als erreicht, keine XP. Die Streak bleibt.'),
          findsOneWidget,
        );
        expect(find.byIcon(workoutSkipIcon), findsOneWidget);
        expect((await markRows(tester, ui)).single.kind, 'skipped');
        expect(ui.feedback.last!.message, 'Heute übersprungen');
        expect(await tester.xpAwards(ui), isEmpty);
      },
    );

    testWidgets(
      '(BS-99) the "Rückgängig" of the message takes the mark away: the day is open again',
      (tester) async {
        final ui = await createFocusUi(tester, workoutDailyGoal: true);
        await pumpCards(tester, ui);
        await answer(tester, 'Ruhetag');
        expect(rich('Ruhetag'), findsOneWidget);

        final result = await tester.runAsync(
          () => ui.feedback.last!.undo!.perform(),
        );
        expect(result, UndoResult.undone);
        await tester.settleDb();
        expect(rich('Noch kein Training'), findsOneWidget);
        expect(find.text('Wie war dein Tag?'), findsOneWidget);
        expect(
          (await markRows(tester, ui)).single.deletedAtUtc,
          isNotNull,
          reason: 'soft deleted, not erased',
        );
      },
    );

    testWidgets(
      '(BS-99) the card\'s own "Rückgängig" takes the mark back, tells so and can itself be undone',
      (tester) async {
        final ui = await createFocusUi(tester, workoutDailyGoal: true);
        await pumpCards(tester, ui);
        await answer(tester, 'Heute überspringen');
        expect(rich('Übersprungen'), findsOneWidget);

        await tester.tap(find.text('Rückgängig'));
        await tester.settleDb();
        expect(rich('Noch kein Training'), findsOneWidget);
        expect(find.text('Rückgängig'), findsNothing);
        expect(ui.feedback.last!.kind, 'saved');
        expect(ui.feedback.last!.message, 'Eintrag für heute zurückgenommen');

        // Taking it back was a mistake: the message's "Rückgängig" restores it.
        final restored = await tester.runAsync(
          () => ui.feedback.last!.undo!.perform(),
        );
        expect(restored, UndoResult.undone);
        await tester.settleDb();
        expect(rich('Übersprungen'), findsOneWidget);
      },
    );

    testWidgets(
      '(BS-99, AT12) a double tap on the card\'s "Rückgängig" runs one command',
      (tester) async {
        final ui = await createFocusUi(tester, workoutDailyGoal: true);
        await pumpCards(tester, ui);
        await answer(tester, 'Ruhetag');

        final action = find.text('Rückgängig');
        await tester.tap(action);
        await tester.tap(action);
        await tester.settleDb();
        expect(
          await tester.receipts(ui, 'workout_day.unmark'),
          hasLength(1),
          reason: 'the second tap met the running command',
        );
        expect(rich('Noch kein Training'), findsOneWidget);
        expect(
          ui.feedback.events.where((e) => e.kind == 'error'),
          isEmpty,
          reason: 'the second tap did not run into "not found"',
        );
        expect(
          ui.feedback.events.where(
            (e) => e.message == 'Eintrag für heute zurückgenommen',
          ),
          hasLength(1),
        );
      },
    );

    testWidgets(
      '(BS-99) an entry that exists already is a conflict with its own message, nothing changes',
      (tester) async {
        final ui = await createFocusUi(tester, workoutDailyGoal: true);
        await pumpCards(tester, ui);

        // The sheet is open while the day gets its mark from elsewhere.
        await tester.tap(find.text('Wie war dein Tag?'));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => ui.workoutDayMarkRepository.mark(
            commandId: 'elsewhere',
            kind: WorkoutDayMarkKind.rest,
          ),
        );
        await tester.tap(find.text('Heute überspringen'));
        await tester.settleDb();
        await tester.pumpAndSettle();

        expect(ui.feedback.last!.kind, 'error');
        expect(
          ui.feedback.last!.message,
          'Für heute gibt es schon einen Eintrag.',
        );
        final rows = await markRows(tester, ui);
        expect(rows.single.kind, 'rest', reason: 'the first entry stays');
        expect(rich('Ruhetag'), findsOneWidget);
      },
    );

    testWidgets('(BS-99, AT27) a storage failure is told as nothing changed', (
      tester,
    ) async {
      final ui = await createFocusUi(tester, workoutDailyGoal: true);
      await pumpCards(tester, ui);
      // A trigger makes every insert into the marks fail.
      await tester.runAsync(
        () => ui.database.customStatement(
          'CREATE TRIGGER no_marks BEFORE INSERT ON workout_day_marks '
          "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
        ),
      );
      await answer(tester, 'Ruhetag');
      expect(ui.feedback.last!.kind, 'error');
      expect(
        ui.feedback.last!.message,
        'Speichern fehlgeschlagen. Es wurde nichts geändert.',
      );
      expect(await markRows(tester, ui), isEmpty);
      expect(rich('Noch kein Training'), findsOneWidget);
    });
  });

  group('the goal is on: a workout', () {
    for (final weeklyTarget in [3, 5]) {
      testWidgets(
        '(BS-99, AT20) weekly goal $weeklyTarget: one workout reaches the day, the card shows it, the weekly numbers stay away',
        (tester) async {
          final ui = await createFocusUi(tester, workoutDailyGoal: true);
          await tester.runAsync(
            () => GoalVersionRepository(ui.database).upsert(
              GoalVersion(
                type: GoalType.workoutWeekly,
                target: weeklyTarget,
                effectiveFrom: LocalDate(2026, 9, 1),
              ),
              newId: 'weekly',
              nowUtc: ui.harness.clock.nowUtc(),
            ),
          );
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
          await pumpCards(tester, ui);

          expect(rich('Upper Body'), findsOneWidget);
          expect(
            find.text('Brust, Schultern, Rücken, Bizeps, Trizeps'),
            findsOneWidget,
          );
          expect(find.byIcon(AppIcon.check.data), findsOneWidget);
          expect(find.text('Training eintragen'), findsOneWidget);
          expect(find.text('Wie war dein Tag?'), findsNothing);
          expect(find.text('Noch kein Training'), findsNothing);
          expect(
            find.textContaining('/ $weeklyTarget'),
            findsNothing,
            reason: 'the week is not what this card is about now',
          );
          expect(find.byType(ProgressRing), findsNothing);
        },
      );
    }

    testWidgets('(BS-99) the action opens the form for another workout', (
      tester,
    ) async {
      final ui = await createFocusUi(tester, workoutDailyGoal: true);
      await tester.addWorkout(ui, title: 'Laufen');
      final router = await pumpCards(tester, ui);
      await tester.tap(find.text('Training eintragen'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/workouts/new');
    });

    testWidgets(
      '(BS-99) a second workout shows the count and the latest title',
      (tester) async {
        final ui = await createFocusUi(tester, workoutDailyGoal: true);
        await tester.addWorkout(ui, title: 'Morgens');
        ui.advance(3600);
        await tester.addWorkout(ui, title: 'Abends');
        await pumpCards(tester, ui);
        expect(rich('Abends'), findsOneWidget);
        expect(find.text('2 Trainings heute'), findsOneWidget);
      },
    );

    testWidgets(
      '(BS-99) a workout wins over a rest day; without the workout the rest day counts again',
      (tester) async {
        final ui = await createFocusUi(tester, workoutDailyGoal: true);
        await tester.markWorkoutDay(ui, WorkoutDayMarkKind.rest);
        final entry = await tester.addWorkout(ui, title: 'Doch trainiert');
        await pumpCards(tester, ui);
        expect(rich('Doch trainiert'), findsOneWidget);
        expect(rich('Ruhetag'), findsNothing);
        expect(find.text('Rückgängig'), findsNothing);

        await tester.runCommand(
          () => ui.workoutRepository.delete(
            commandId: ui.ids.newId(),
            id: entry.id,
          ),
        );
        expect(rich('Ruhetag'), findsOneWidget);
        expect(find.text('Rückgängig'), findsOneWidget);
      },
    );
  });

  group('the day changes (AT25)', () {
    testWidgets(
      '(BS-99, AT25) after midnight the day is open again; yesterday\'s mark stays stored',
      (tester) async {
        // 23:30 in Berlin.
        final ui = await createFocusUi(
          tester,
          nowIso: '2026-10-03T21:30:00Z',
          workoutDailyGoal: true,
        );
        await tester.markWorkoutDay(ui, WorkoutDayMarkKind.rest);
        await pumpCards(tester, ui);
        expect(rich('Ruhetag'), findsOneWidget);

        ui.harness.clock.advance(const Duration(hours: 1));
        ui.container.read(todayProvider.notifier).refresh();
        await tester.settleDb();
        expect(rich('Noch kein Training'), findsOneWidget);
        expect(find.text('Wie war dein Tag?'), findsOneWidget);
        expect(rich('Ruhetag'), findsNothing);
        expect(
          (await markRows(tester, ui)).single.localDate,
          LocalDate(2026, 10, 3),
        );

        // The new day takes its own answer.
        await answer(tester, 'Heute überspringen');
        expect(rich('Übersprungen'), findsOneWidget);
        expect(await markRows(tester, ui), hasLength(2));
      },
    );
  });

  group('states of the card', () {
    testWidgets('(BS-99) loading and error', (tester) async {
      var attempts = 0;
      final ui = await createFocusUi(
        tester,
        workoutDailyGoal: true,
        overrides: [
          workoutDayMarkTodayProvider.overrideWith((ref) {
            attempts++;
            return attempts == 1
                ? Stream.error(const StorageFailure())
                : Stream.value(null);
          }),
        ],
      );
      await pumpCards(tester, ui);
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pump();
      await tester.settleDb();
      expect(rich('Noch kein Training'), findsOneWidget);
    });

    testWidgets('(BS-99) while the day state loads the card says so quietly', (
      tester,
    ) async {
      final ui = await createFocusUi(
        tester,
        workoutDailyGoal: true,
        overrides: [
          workoutTodayEntriesProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
      );
      await pumpCards(tester, ui);
      expect(find.text('Workout'), findsOneWidget);
      expect(rich('–'), findsOneWidget);
      expect(find.text('Wie war dein Tag?'), findsNothing);
    });
  });

  group('labels and semantics (AT34)', () {
    testWidgets(
      '(BS-99, AT34) every state is read as one button with its state; the action is its own button',
      (tester) => withSemantics(tester, () async {
        final ui = await createFocusUi(tester, workoutDailyGoal: true);
        await pumpCards(tester, ui);

        expect(
          find.bySemanticsLabel('Workout, Noch kein Training, Heute offen'),
          findsOneWidget,
        );
        final question = tester.getSemantics(
          find.bySemanticsLabel('Wie war dein Tag?'),
        );
        expect(question.flagsCollection.isButton, isTrue);

        await answer(tester, 'Ruhetag');
        expect(
          find.bySemanticsLabel(
            'Workout, Ruhetag, Zählt als erreicht, keine XP. Die Streak '
            'bleibt., Tagesziel erreicht',
          ),
          findsOneWidget,
        );
        final takeBack = tester.getSemantics(
          find.bySemanticsLabel('Ruhetag rückgängig machen'),
        );
        expect(takeBack.flagsCollection.isButton, isTrue);

        await tester.tap(find.text('Rückgängig'));
        await tester.settleDb();
        await answer(tester, 'Heute überspringen');
        expect(
          find.bySemanticsLabel('Überspringen rückgängig machen'),
          findsOneWidget,
        );

        await tester.tap(find.text('Rückgängig'));
        await tester.settleDb();
        await tester.addWorkout(ui, title: 'Upper Body');
        await tester.pump();
        expect(
          find.bySemanticsLabel(
            'Workout, Upper Body, Kraft · 45 Min., Tagesziel erreicht',
          ),
          findsOneWidget,
        );
      }),
    );
  });

  group('layout (AT33) and themes (AT35)', () {
    /// The four states one after the other, on one database.
    Future<void> eachState(
      WidgetTester tester,
      FocusUi ui,
      Future<void> Function(String state) check,
    ) async {
      await check('open');
      final rest = await tester.markWorkoutDay(ui, WorkoutDayMarkKind.rest);
      await check('rest');
      await tester.runCommand(
        () => ui.workoutDayMarkRepository.unmark(
          commandId: ui.ids.newId(),
          id: rest.id,
        ),
      );
      final skipped = await tester.markWorkoutDay(
        ui,
        WorkoutDayMarkKind.skipped,
      );
      await check('skipped');
      await tester.runCommand(
        () => ui.workoutDayMarkRepository.unmark(
          commandId: ui.ids.newId(),
          id: skipped.id,
        ),
      );
      await tester.addWorkout(
        ui,
        title: 'Oberkörper mit sehr langem Namen',
        groups: [MuscleGroup.chest, MuscleGroup.shoulders, MuscleGroup.back],
      );
      await check('workout');
    }

    for (final size in responsiveSizes) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '(BS-99, AT33) all four states fit ${size.width.toInt()} px at text scale $scale; the action keeps 48 x 48 and a label',
          (tester) => withSemantics(tester, () async {
            final ui = await createFocusUi(tester, workoutDailyGoal: true);
            await pumpCards(tester, ui, size: size, textScale: scale);
            await eachState(tester, ui, (state) async {
              await tester.pump();
              expect(
                tester.takeException(),
                isNull,
                reason: '$state: no overflow',
              );
              final action = find.byType(MetricCardAction);
              expect(action, findsOneWidget, reason: state);
              await tester.ensureVisible(action);
              await tester.pump();
              final rect = tester.getRect(action);
              expect(rect.height, greaterThanOrEqualTo(48), reason: state);
              expect(rect.width, greaterThanOrEqualTo(48), reason: state);
              expect(rect.left, greaterThanOrEqualTo(0), reason: state);
              expect(rect.right, lessThanOrEqualTo(size.width), reason: state);
              await expectLater(
                tester,
                meetsGuideline(androidTapTargetGuideline),
              );
              await expectLater(
                tester,
                meetsGuideline(labeledTapTargetGuideline),
              );
            });
          }),
        );
      }
    }

    for (final theme in AppThemeVariant.values) {
      testWidgets(
        '(BS-99, AT35) all four states render in ${theme.name} with readable text',
        (tester) => withSemantics(tester, () async {
          final ui = await createFocusUi(tester, workoutDailyGoal: true);
          await pumpCards(tester, ui, theme: theme);
          await eachState(tester, ui, (state) async {
            await tester.pump();
            expect(tester.takeException(), isNull, reason: state);
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          });
        }),
      );
    }
  });
}
