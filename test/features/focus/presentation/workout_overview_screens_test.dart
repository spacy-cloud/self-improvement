import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/application/workout_ui_providers.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_intensity.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/focus_ui_kit.dart';

/// The week overview (`/workouts`) and the list of all workouts
/// (`/workouts/all`). "Today" is Saturday 2026-10-03; the week runs from
/// Monday 2026-09-28 to Sunday 2026-10-04.
void main() {
  final tile = find.byType(EntryListTile);

  /// Two workouts this week (105 minutes) and one last week.
  Future<FocusUi> seeded(WidgetTester tester) async {
    final ui = await createFocusUi(tester);
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
      at: DateTime.utc(2026, 10, 3, 7),
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
    return ui;
  }

  ProgressRing ring(WidgetTester tester) =>
      tester.widget<ProgressRing>(find.byType(ProgressRing).first);

  group('overview', () {
    testWidgets('without workouts: an empty state with the way to log one', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      final router = await pumpFocusApp(
        tester,
        ui,
        initialLocation: '/workouts',
      );
      expect(find.text('Meine Workouts'), findsOneWidget);
      expect(find.text('Noch kein Training'), findsOneWidget);
      expect(find.text('2 / 3 Trainings', findRichText: true), findsNothing);
      await tester.tap(find.text('Training eintragen'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/workouts/new');
    });

    testWidgets(
      'this week: the real count against the goal, minutes, average and what '
      'is missing (F03, A01, AT20)',
      (tester) async {
        final ui = await seeded(tester);
        await pumpFocusApp(tester, ui, initialLocation: '/workouts');

        expect(find.text('Diese Woche'), findsOneWidget);
        expect(find.text('Ziel: 3× pro Woche'), findsOneWidget);
        expect(
          find.text('2 / 3 Trainings', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('105 Min.'), findsOneWidget);
        expect(find.text('Trainingszeit'), findsOneWidget);
        expect(find.text('53 Min.'), findsOneWidget);
        expect(find.text('Ø pro Training'), findsOneWidget);
        expect(find.text('1 fehlt'), findsOneWidget);
        expect(find.text('zum Ziel'), findsOneWidget);
        expect(ring(tester).value, closeTo(2 / 3, 0.0001));
      },
    );

    testWidgets('the ring stops at 100 percent, the real count and minutes '
        'stay visible (F03, A01)', (tester) async {
      final ui = await seeded(tester);
      await tester.addWorkout(
        ui,
        minutes: 20,
        at: DateTime.utc(2026, 10, 3, 6),
      );
      await tester.addWorkout(
        ui,
        minutes: 25,
        at: DateTime.utc(2026, 10, 2, 6),
      );
      await tester.addWorkout(
        ui,
        minutes: 30,
        at: DateTime.utc(2026, 10, 1, 6),
      );
      await pumpFocusApp(tester, ui, initialLocation: '/workouts');

      expect(find.text('5 / 3 Trainings', findRichText: true), findsOneWidget);
      expect(find.text('180 Min.'), findsOneWidget);
      expect(find.text('36 Min.'), findsOneWidget);
      expect(find.text('Erreicht'), findsOneWidget);
      expect(find.text('Wochenziel'), findsOneWidget);
      expect(ring(tester).value, 1.0, reason: 'never above 100 percent');
    });

    testWidgets('the week is Monday to Sunday (F03, A01)', (tester) async {
      final ui = await createFocusUi(tester);
      // Sunday 23:30 local belongs to last week, Monday 00:30 to this one.
      await tester.addWorkout(
        ui,
        minutes: 40,
        at: DateTime.utc(2026, 9, 27, 21, 30),
      );
      await tester.addWorkout(
        ui,
        minutes: 50,
        at: DateTime.utc(2026, 9, 27, 22, 30),
      );
      await pumpFocusApp(tester, ui, initialLocation: '/workouts');
      expect(find.text('1 / 3 Trainings', findRichText: true), findsOneWidget);
      expect(find.text('50 Min.'), findsWidgets);
    });

    testWidgets('a new week starts on Monday: the count starts again, the '
        'workouts stay listed (A01)', (tester) async {
      final ui = await seeded(tester);
      await pumpFocusApp(tester, ui, initialLocation: '/workouts');
      expect(find.text('2 / 3 Trainings', findRichText: true), findsOneWidget);

      ui.harness.clock.setNow(DateTime.utc(2026, 10, 5, 8)); // Monday
      ui.container.read(todayProvider.notifier).refresh();
      await tester.settleDb();
      expect(find.text('0 / 3 Trainings', findRichText: true), findsOneWidget);
      expect(find.text('3 fehlen'), findsOneWidget);
      expect(find.text('–'), findsOneWidget, reason: 'no average without any');
      expect(ring(tester).value, 0);
      expect(find.text('Upper Body'), findsOneWidget, reason: 'still listed');
    });

    testWidgets('lists the latest workouts with their details', (tester) async {
      final ui = await seeded(tester);
      await pumpFocusApp(tester, ui, initialLocation: '/workouts');
      expect(tile, findsNWidgets(3 + 1), reason: '3 workouts, 1 goal row');
      expect(find.text('Letzte Trainings'), findsOneWidget);
      expect(find.text('Upper Body'), findsOneWidget);
      expect(find.text('Kraft · 60 Min. · Mittel'), findsOneWidget);
      expect(find.text('Heute · 09:00'), findsOneWidget);
      expect(find.text('Lower Body'), findsOneWidget);
      expect(find.text('Kraft · 45 Min. · Hart'), findsOneWidget);
      expect(find.text('Dienstag · 18:10'), findsOneWidget);
      expect(find.text('Laufen'), findsOneWidget);
      expect(find.text('Cardio · 30 Min. · Leicht'), findsOneWidget);
      expect(find.text('Mo., 21. Sep. · 07:00'), findsOneWidget);
    });

    testWidgets('shows only the newest five', (tester) async {
      final ui = await createFocusUi(tester);
      await tester.insertWorkouts(ui, 8, newest: DateTime.utc(2026, 10, 3, 7));
      await pumpFocusApp(tester, ui, initialLocation: '/workouts');
      expect(tile, findsNWidgets(workoutOverviewLatestCount + 1));
    });

    testWidgets('names the muscle groups trained last, freshest first', (
      tester,
    ) async {
      final ui = await seeded(tester);
      await pumpFocusApp(tester, ui, initialLocation: '/workouts');
      expect(find.text('Zuletzt trainiert'), findsOneWidget);
      expect(find.text('frisch'), findsOneWidget);
      expect(find.text('länger her'), findsOneWidget);
      for (final label in [
        'Brust',
        'Schultern',
        'Rücken',
        'Bizeps',
        'Trizeps',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('heute'), findsNWidgets(5));
      expect(find.text('Beine'), findsOneWidget);
      expect(find.text('vor 4 Tagen'), findsOneWidget);
      expect(find.text('Core'), findsNothing, reason: 'never trained');
    });

    testWidgets('hides the muscle card while no workout names a group', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await tester.addWorkout(ui, minutes: 30);
      await pumpFocusApp(tester, ui, initialLocation: '/workouts');
      expect(find.text('Zuletzt trainiert'), findsNothing);
      expect(find.text('Letzte Trainings'), findsOneWidget);
    });

    testWidgets('a row opens the workout; "Alle anzeigen" the whole list', (
      tester,
    ) async {
      final ui = await seeded(tester);
      final router = await pumpFocusApp(
        tester,
        ui,
        initialLocation: '/workouts',
      );
      await tester.tap(find.text('Lower Body'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, startsWith('/workouts/'));
      expect(find.text('Training bearbeiten'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Zurück'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alle anzeigen'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/workouts/all');
    });

    testWidgets('the weekly goal is changed in the goals editor, from '
        'tomorrow (F03)', (tester) async {
      final ui = await seeded(tester);
      final router = await pumpFocusApp(
        tester,
        ui,
        initialLocation: '/workouts',
      );
      await tester.ensureVisible(find.text('Wochenziel ändern'));
      expect(
        find.text(
          'Aktuell 3 Trainings pro Woche. Änderungen gelten ab morgen.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Wochenziel ändern'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/goals');
    });

    testWidgets('the weekly goal of the goal version is shown (1 to 14)', (
      tester,
    ) async {
      final ui = await createFocusUi(
        tester,
        overrides: [
          workoutWeekSummaryProvider.overrideWithValue(
            AsyncData(
              WorkoutWeekSummary(
                weekStart: LocalDate(2026, 9, 28),
                entryCount: 1,
                totalMinutes: 30,
                weeklyTarget: 14,
              ),
            ),
          ),
        ],
      );
      await tester.addWorkout(ui);
      await pumpFocusApp(tester, ui, initialLocation: '/workouts');
      expect(find.text('Ziel: 14× pro Woche'), findsOneWidget);
      expect(find.text('1 / 14 Trainings', findRichText: true), findsOneWidget);
      expect(find.text('13 fehlen'), findsOneWidget);
    });

    testWidgets('workouts do not add focus time (F03, AT20)', (tester) async {
      final ui = await seeded(tester);
      await pumpFocusApp(tester, ui, initialLocation: '/workouts');
      expect(await tester.focusRows(ui), isEmpty);
      expect(find.textContaining('Fokus'), findsNothing);
    });

    testWidgets('loading and error states', (tester) async {
      final loading = await createFocusUi(
        tester,
        overrides: [
          workoutLatestProvider.overrideWithValue(const AsyncLoading()),
        ],
      );
      await pumpFocusApp(tester, loading, initialLocation: '/workouts');
      expect(find.text('Wird geladen …'), findsOneWidget);

      var attempts = 0;
      await closeApp(tester);
      final failing = await createFocusUi(
        tester,
        overrides: [
          workoutEntriesPageProvider.overrideWith((ref, limit) {
            attempts++;
            return attempts == 1
                ? Stream<List<WorkoutEntry>>.error(StateError('x'))
                : Stream<List<WorkoutEntry>>.value(const []);
          }),
        ],
      );
      await pumpFocusApp(tester, failing, initialLocation: '/workouts');
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Noch kein Training'), findsOneWidget);
    });

    testSemantics('the week is read with the real count; every control has a '
        'label and a 48 px target (AT33, AT34)', (tester) async {
      final ui = await seeded(tester);
      await pumpFocusApp(tester, ui, initialLocation: '/workouts');
      expect(
        find.bySemanticsLabel(
          'Diese Woche 2 von 3 Trainings, 105 Minuten. 1 fehlt zum Ziel.',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Brust, zuletzt heute'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Upper Body, Kraft, 60 Minuten, Mittel, Brust, Schultern, Rücken, '
          'Bizeps, Trizeps, Heute, 09:00 Uhr. Tippen zum Bearbeiten',
        ),
        findsOneWidget,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });

  group('all workouts', () {
    testWidgets('without workouts: an empty state', (tester) async {
      final ui = await createFocusUi(tester);
      await pumpFocusApp(tester, ui, initialLocation: '/workouts/all');
      expect(find.text('Alle Trainings'), findsOneWidget);
      expect(find.text('Noch kein Training'), findsOneWidget);
    });

    testWidgets('groups by calendar week, Monday to Sunday (F03)', (
      tester,
    ) async {
      final ui = await seeded(tester);
      await tester.addWorkout(
        ui,
        minutes: 20,
        at: DateTime.utc(2026, 9, 27, 21, 30), // Sunday 23:30: last week
      );
      await tester.addWorkout(
        ui,
        minutes: 20,
        at: DateTime.utc(2026, 9, 7, 5), // two weeks earlier
      );
      await pumpFocusApp(tester, ui, initialLocation: '/workouts/all');

      expect(find.text('DIESE WOCHE'), findsOneWidget);
      expect(find.text('LETZTE WOCHE'), findsOneWidget);
      expect(find.text('7. SEP. – 13. SEP.'), findsOneWidget);
      expect(tile, findsNWidgets(5));
      // Newest first within the week; each row names the day.
      expect(find.text('Sa., 3. Okt. · Kraft · Mittel'), findsOneWidget);
      expect(find.text('Di., 29. Sep. · Kraft · Hart'), findsOneWidget);
      expect(find.text('60 Min.'), findsOneWidget);
      expect(find.text('45 Min.'), findsOneWidget);
      expect(
        find.text(
          'Tippe auf ein Training, um es zu bearbeiten oder zu löschen.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('loading shows nothing yet, no empty state', (tester) async {
      final never = StreamController<List<WorkoutEntry>>();
      addTearDown(never.close);
      final ui = await createFocusUi(
        tester,
        overrides: [
          workoutEntriesPageProvider.overrideWith((ref, limit) => never.stream),
        ],
      );
      await pumpFocusApp(tester, ui, initialLocation: '/workouts/all');
      expect(find.byType(EntryListTile), findsNothing);
      expect(find.text('Noch kein Training'), findsNothing);
    });

    testWidgets('an error offers a retry that reads again', (tester) async {
      var attempts = 0;
      final ui = await createFocusUi(
        tester,
        overrides: [
          workoutEntriesPageProvider.overrideWith((ref, limit) {
            attempts++;
            return attempts == 1
                ? Stream<List<WorkoutEntry>>.error(StateError('x'))
                : Stream<List<WorkoutEntry>>.value(const []);
          }),
        ],
      );
      await pumpFocusApp(tester, ui, initialLocation: '/workouts/all');
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Noch kein Training'), findsOneWidget);
    });

    testWidgets('a row opens the workout for editing', (tester) async {
      final ui = await seeded(tester);
      final router = await pumpFocusApp(
        tester,
        ui,
        initialLocation: '/workouts/all',
      );
      await tester.tap(find.text('Lower Body'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, startsWith('/workouts/'));
      expect(find.text('Training bearbeiten'), findsOneWidget);
    });

    testWidgets('loads older workouts on request, built lazily (AT36)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await tester.insertWorkouts(ui, 70, newest: DateTime.utc(2026, 10, 3, 7));
      await pumpFocusApp(tester, ui, initialLocation: '/workouts/all');
      final loadMore = find.text('Ältere Trainings laden');
      await tester.scrollUntilVisible(
        loadMore,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(EntryListTile).evaluate().length, lessThan(50));
      await tester.tap(loadMore);
      await tester.settleDb();
      expect(loadMore, findsNothing, reason: 'all 70 are loaded');
    });

    testWidgets('a deleted workout disappears and the week count follows '
        '(AT23, A01)', (tester) async {
      final ui = await seeded(tester);
      final rows = await tester.workoutRows(ui);
      final upper = rows.firstWhere((r) => r.title == 'Upper Body');
      await pumpFocusApp(tester, ui, initialLocation: '/workouts');
      expect(find.text('2 / 3 Trainings', findRichText: true), findsOneWidget);
      await tester.runCommand(
        () => ui.workoutRepository.delete(
          commandId: ui.ids.newId(),
          id: upper.id,
        ),
      );
      expect(find.text('1 / 3 Trainings', findRichText: true), findsOneWidget);
      expect(find.text('45 Min.'), findsWidgets);
      expect(find.text('Upper Body'), findsNothing);
    });

    testSemantics('every row has a label and a 48 px target (AT33, AT34)', (
      tester,
    ) async {
      final ui = await seeded(tester);
      await pumpFocusApp(tester, ui, initialLocation: '/workouts/all');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
