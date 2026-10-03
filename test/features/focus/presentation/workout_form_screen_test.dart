import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/focus/application/workout_form_controller.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_intensity.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../../../support/pump_app.dart';
import '../support/focus_ui_kit.dart';

/// The workout form (`/workouts/new`, `/workouts/:id`): nothing preselected,
/// optional fields, validation, create / edit / delete / undo.
void main() {
  final nameField = find.byType(TextField).at(0);
  final durationField = find.byType(TextField).at(1);
  final noteField = find.byType(TextField).at(2);
  final saveNew = find.text('Training speichern');
  final saveEdit = find.text('Änderungen speichern');
  final plus = find.byIcon(Icons.add_rounded);
  final minus = find.byIcon(Icons.remove_rounded);

  Finder category(String label) => find.widgetWithText(AppChoiceChip, label);
  Finder muscle(String label) => find.widgetWithText(AppFilterChip, label);
  bool chipSelected(WidgetTester tester, Finder chip) {
    final widget = tester.widget(chip);
    return widget is AppChoiceChip
        ? widget.selected
        : (widget as AppFilterChip).selected;
  }

  PeriodSelector<WorkoutIntensity?> intensity(WidgetTester tester) =>
      tester.widget<PeriodSelector<WorkoutIntensity?>>(
        find.byType(PeriodSelector<WorkoutIntensity?>),
      );

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openNew(WidgetTester tester, FocusUi ui) =>
      pumpFocusApp(tester, ui, initialLocation: '/workouts/new');

  Future<void> save(WidgetTester tester, [Finder? button]) async {
    await tester.ensureVisible(button ?? saveNew);
    await tester.tap(button ?? saveNew);
    await tester.settleDb();
  }

  group('a new form', () {
    testWidgets(
      'starts EMPTY: nothing is preselected and nothing is saved (F03, AT20)',
      (tester) async {
        final ui = await createFocusUi(tester);
        await openNew(tester, ui);

        expect(find.text('Workout eintragen'), findsOneWidget);
        for (final label in ['Kraft', 'Cardio', 'Mobility', 'Sport']) {
          expect(chipSelected(tester, category(label)), isFalse, reason: label);
        }
        expect(find.byType(AppChoiceChip), findsNWidgets(4));
        for (final group in MuscleGroup.values) {
          expect(chipSelected(tester, muscle(group.label)), isFalse);
        }
        expect(find.byType(AppFilterChip), findsNWidgets(8));
        expect(intensity(tester).selected, isNull);
        for (final label in ['Leicht', 'Mittel', 'Hart']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.widget<TextField>(nameField).controller!.text, isEmpty);
        expect(
          tester.widget<TextField>(durationField).controller!.text,
          isEmpty,
        );
        expect(tester.widget<TextField>(noteField).controller!.text, isEmpty);
        expect(find.text('Heute, 10:00 Uhr'), findsOneWidget);
        expect(await tester.workoutRows(ui), isEmpty);
        // No sets, no repetitions, no calories anywhere.
        expect(find.textContaining('Sätze'), findsNothing);
        expect(find.textContaining('Wiederholungen'), findsNothing);
        expect(find.textContaining('kcal'), findsNothing);
        expect(find.textContaining('Kalorien'), findsNothing);
      },
    );

    testWidgets('lists the categories and groups with their German names', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await openNew(tester, ui);
      for (final label in [
        'Brust',
        'Schultern',
        'Rücken',
        'Bizeps',
        'Trizeps',
        'Beine',
        'Core',
        'Ganzkörper',
      ]) {
        expect(muscle(label), findsOneWidget, reason: label);
      }
      expect(find.text('Muskelgruppen'), findsWidgets);
      expect(find.text('Intensität'), findsWidgets);
    });

    testWidgets('saving an empty form shows what is missing and keeps the '
        'input (AT27)', (tester) async {
      final ui = await createFocusUi(tester);
      await openNew(tester, ui);
      await tester.enterText(nameField, 'Mein Training');
      await tester.tap(muscle('Beine'));
      await tester.pump();
      await save(tester);

      expect(find.text('Bitte wähle eine Trainingskategorie.'), findsOneWidget);
      expect(find.text('Bitte gib die Dauer in Minuten ein.'), findsOneWidget);
      expect(await tester.workoutRows(ui), isEmpty);
      expect(find.text('Mein Training'), findsOneWidget, reason: 'input kept');
      expect(chipSelected(tester, muscle('Beine')), isTrue);
      expect(ui.feedback.events, isEmpty, reason: 'no success message');
    });

    testWidgets(
      'category and duration are enough; optional fields stay empty (F03, '
      'AT20)',
      (tester) async {
        final ui = await createFocusUi(tester);
        await openNew(tester, ui);
        await tester.tap(category('Kraft'));
        await tester.enterText(durationField, '45');
        await tester.pump();
        await save(tester);

        final rows = await tester.workoutRows(ui);
        expect(rows, hasLength(1));
        final row = rows.single;
        expect(row.trainingCategory, 'strength');
        expect(row.title, isNull);
        expect(row.durationMinutes, 45);
        expect(row.muscleGroups, isEmpty);
        expect(row.intensity, isNull);
        expect(row.note, isNull);
        expect(row.localDate, LocalDate(2026, 10, 3));
        expect(ui.feedback.last!.kind, 'saved');
        expect(ui.feedback.last!.message, 'Training gespeichert');
        expect(ui.feedback.last!.undo, isNotNull);
        expect(find.text('HOME-STUB'), findsOneWidget, reason: 'screen left');
      },
    );

    testWidgets('all optional fields are saved: title, muscle groups without '
        'duplicates, intensity, time and note (F03)', (tester) async {
      final ui = await createFocusUi(tester);
      await openNew(tester, ui);
      await tester.tap(category('Cardio'));
      await tester.enterText(nameField, '  Laufen am Fluss  ');
      await tester.enterText(durationField, '30');
      // Brust on, off, on again; Core on: no duplicates, canonical order.
      await tester.tap(muscle('Core'));
      await tester.tap(muscle('Brust'));
      await tester.tap(muscle('Brust'));
      await tester.tap(muscle('Brust'));
      await tester.tap(find.text('Hart'));
      await tester.pump();
      await tester.tap(find.text('Hart')); // again: cleared
      await tester.pump();
      expect(intensity(tester).selected, isNull);
      await tester.tap(find.text('Mittel'));
      await tester.enterText(noteField, '  Schönes Wetter  ');
      await tester.pump();
      await save(tester);

      final row = (await tester.workoutRows(ui)).single;
      expect(row.trainingCategory, 'cardio');
      expect(row.title, 'Laufen am Fluss');
      expect(row.durationMinutes, 30);
      expect(row.muscleGroups, ['chest', 'core']);
      expect(row.intensity, 'moderate');
      expect(row.note, 'Schönes Wetter');
    });

    for (final (text, valid) in [
      ('0', false),
      ('1', true),
      ('600', true),
      ('601', false),
    ]) {
      testWidgets('duration $text is ${valid ? 'saved' : 'refused'} '
          '(limits 1 and 600, F03)', (tester) async {
        final ui = await createFocusUi(tester);
        await openNew(tester, ui);
        await tester.tap(category('Sport'));
        await tester.enterText(durationField, text);
        await tester.pump();
        await save(tester);

        final rows = await tester.workoutRows(ui);
        if (valid) {
          expect(rows.single.durationMinutes, int.parse(text));
        } else {
          expect(rows, isEmpty);
          expect(
            find.text('Bitte gib eine Dauer zwischen 1 und 600 Minuten ein.'),
            findsOneWidget,
          );
          expect(find.text(text), findsOneWidget, reason: 'input kept');
        }
      });
    }

    testWidgets('only digits can be typed into the duration', (tester) async {
      final ui = await createFocusUi(tester);
      await openNew(tester, ui);
      await tester.enterText(durationField, '4,5 min');
      await tester.pump();
      expect(tester.widget<TextField>(durationField).controller!.text, '45');
    });

    testWidgets('minus and plus: first press shows 30, then five minutes, '
        'within 1 and 600', (tester) async {
      final ui = await createFocusUi(tester);
      await openNew(tester, ui);
      await tester.tap(plus);
      await tester.pump();
      String duration() =>
          tester.widget<TextField>(durationField).controller!.text;
      expect(duration(), '30');
      await tester.tap(plus);
      await tester.pump();
      expect(duration(), '35');
      await tester.tap(minus);
      await tester.tap(minus);
      await tester.pump();
      expect(duration(), '25');

      await tester.enterText(durationField, '3');
      await tester.pump();
      await tester.tap(minus);
      await tester.pump();
      expect(duration(), '1', reason: 'never below one minute');
      await tester.tap(minus);
      await tester.pump();
      expect(duration(), '1');
      await tester.enterText(durationField, '598');
      await tester.pump();
      await tester.tap(plus);
      await tester.pump();
      expect(duration(), '600');
      await tester.tap(plus);
      await tester.pump();
      expect(duration(), '600', reason: 'never above 600');
    });

    testWidgets('the title stops at 80 characters', (tester) async {
      final ui = await createFocusUi(tester);
      await openNew(tester, ui);
      await tester.enterText(nameField, 'a' * 81);
      await tester.pump();
      expect(tester.widget<TextField>(nameField).controller!.text.length, 80);
    });

    testWidgets('a time in the future is refused at the time row (F03)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await openNew(tester, ui);
      await tester.tap(category('Kraft'));
      await tester.enterText(durationField, '30');
      ui.container
          .read(workoutFormProvider(const WorkoutFormArgs.create()).notifier)
          .setTime(const LocalTime(23, 30));
      await tester.pump();
      await save(tester);
      expect(
        find.text('Der Zeitpunkt darf nicht in der Zukunft liegen.'),
        findsOneWidget,
      );
      expect(await tester.workoutRows(ui), isEmpty);
      expect(find.text('30'), findsOneWidget, reason: 'input kept');
    });

    testWidgets('a past day can be chosen with the date and time picker', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await openNew(tester, ui);
      await tester.tap(category('Kraft'));
      await tester.enterText(durationField, '30');
      await tester.pump();
      await tapVisible(tester, find.text('Zeitpunkt'));
      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // the time as proposed
      await tester.pumpAndSettle();
      expect(find.text('Gestern, 10:00 Uhr'), findsOneWidget);
      await save(tester);

      final row = (await tester.workoutRows(ui)).single;
      expect(row.localDate, LocalDate(2026, 10, 2));
    });

    testWidgets('a failed save keeps ALL input; the retry reuses the command '
        'id and saves one workout (AT27, AT12)', (tester) async {
      final projection = RecordingProjectionSynchronizer();
      final ui = await createFocusUi(tester, projection: projection);
      await openNew(tester, ui);
      await tester.tap(category('Kraft'));
      await tester.enterText(nameField, 'Upper Body');
      await tester.enterText(durationField, '60');
      await tester.tap(muscle('Brust'));
      await tester.tap(muscle('Rücken'));
      await tester.tap(find.text('Mittel'));
      await tester.enterText(noteField, 'Gut');
      await tester.pump();

      projection.failure = StateError('disk full');
      final before = ui.ids.issued.length;
      await save(tester);

      expect(
        await tester.workoutRows(ui),
        isEmpty,
        reason: 'nothing committed',
      );
      expect(ui.feedback.last!.kind, 'error');
      expect(
        ui.feedback.last!.message,
        'Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.',
      );
      expect(ui.feedback.last!.onRetry, isNotNull);
      expect(chipSelected(tester, category('Kraft')), isTrue);
      expect(chipSelected(tester, muscle('Brust')), isTrue);
      expect(chipSelected(tester, muscle('Rücken')), isTrue);
      expect(intensity(tester).selected, WorkoutIntensity.moderate);
      expect(find.text('Upper Body'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('Gut'), findsOneWidget);
      expect(saveNew, findsOneWidget, reason: 'the form stays');
      final firstId = ui.ids.issued[before];

      projection.failure = null;
      ui.feedback.last!.onRetry!();
      await tester.settleDb();
      final rows = await tester.workoutRows(ui);
      expect(rows, hasLength(1));
      expect(rows.single.title, 'Upper Body');
      final receipts = await tester.receipts(ui, 'workout.create');
      expect(receipts.single.commandId, firstId, reason: 'same command id');
    });

    testWidgets('a double tap on save creates ONE workout (AT12)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      await openNew(tester, ui);
      await tester.tap(category('Kraft'));
      await tester.enterText(durationField, '45');
      await tester.pump();
      await tester.ensureVisible(saveNew);
      await tester.tap(saveNew);
      await tester.tap(saveNew);
      await tester.settleDb();
      expect(await tester.workoutRows(ui), hasLength(1));
      expect(await tester.receipts(ui, 'workout.create'), hasLength(1));
    });

    testWidgets('leaving with input asks first; an untouched form does not '
        '(F03)', (tester) async {
      final ui = await createFocusUi(tester);
      await openNew(tester, ui);
      await tester.tap(find.bySemanticsLabel('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsNothing);

      await openNew(tester, ui);
      await tester.tap(category('Mobility'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await tester.tap(find.text('Weiter bearbeiten'));
      await tester.pumpAndSettle();
      expect(chipSelected(tester, category('Mobility')), isTrue);

      await tester.binding.handlePopRoute(); // Android back
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await tester.tap(find.text('Verwerfen'));
      await tester.pumpAndSettle();
      expect(await tester.workoutRows(ui), isEmpty);
      expect(find.text('Mobility'), findsNothing);
    });

    testWidgets('workouts never count focus time (F03, AT20)', (tester) async {
      final ui = await createFocusUi(tester);
      await openNew(tester, ui);
      await tester.tap(category('Kraft'));
      await tester.enterText(durationField, '45');
      await tester.pump();
      await save(tester);
      expect(await tester.focusRows(ui), isEmpty);
      final focusToday = await tester.runAsync(
        () => ui.focusRepository.watchCompletedOn(LocalDate(2026, 10, 3)).first,
      );
      expect(focusToday, isEmpty);
    });
  });

  group('editing', () {
    testWidgets('opens with the saved values; saving needs a change (F03)', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      final entry = await tester.addWorkout(
        ui,
        category: TrainingCategory.cardio,
        title: 'Laufen',
        minutes: 40,
        groups: [MuscleGroup.legs, MuscleGroup.core],
        intensity: WorkoutIntensity.high,
        note: 'Regen',
        at: DateTime.utc(2026, 10, 2, 16, 30),
      );
      await pumpFocusApp(tester, ui, initialLocation: '/workouts/${entry.id}');

      expect(find.text('Training bearbeiten'), findsOneWidget);
      expect(chipSelected(tester, category('Cardio')), isTrue);
      expect(chipSelected(tester, muscle('Beine')), isTrue);
      expect(chipSelected(tester, muscle('Core')), isTrue);
      expect(chipSelected(tester, muscle('Brust')), isFalse);
      expect(intensity(tester).selected, WorkoutIntensity.high);
      expect(find.text('Laufen'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
      expect(find.text('Regen'), findsOneWidget);
      expect(find.text('Gestern, 18:30 Uhr'), findsOneWidget);
      final button = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Änderungen speichern'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Training löschen'), findsOneWidget);
    });

    testWidgets('a change is saved with a message and undo; the time stays '
        'when it was not touched (AT23)', (tester) async {
      final ui = await createFocusUi(tester);
      final entry = await tester.addWorkout(
        ui,
        minutes: 40,
        at: DateTime.utc(2026, 10, 2, 16, 30),
      );
      await pumpFocusApp(tester, ui, initialLocation: '/workouts/${entry.id}');
      await tester.enterText(durationField, '50');
      await tester.pump();
      await save(tester, saveEdit);

      final row = (await tester.workoutRows(ui)).single;
      expect(row.id, entry.id);
      expect(row.durationMinutes, 50);
      expect(row.occurredAtUtc, DateTime.utc(2026, 10, 2, 16, 30));
      expect(row.localDate, LocalDate(2026, 10, 2));
      expect(ui.feedback.last!.message, 'Training aktualisiert');

      await tester.runAsync(() => ui.feedback.last!.undo!.perform());
      expect((await tester.workoutRows(ui)).single.durationMinutes, 40);
    });

    testWidgets('deleting asks first; confirm deletes with a message and an '
        'undo that restores the same id (AT23, AT20)', (tester) async {
      final ui = await createFocusUi(tester, realProjection: true);
      final entry = await tester.addWorkout(
        ui,
        title: 'Upper Body',
        minutes: 60,
      );
      expect(await tester.xpAwards(ui), hasLength(1), reason: '15 XP');
      await pumpFocusApp(tester, ui, initialLocation: '/workouts/${entry.id}');

      await tapVisible(tester, find.text('Training löschen'));
      expect(find.text('Training vom 3. Okt. löschen?'), findsOneWidget);
      expect(
        find.text(
          'Upper Body (60 Min.) wird entfernt. Du kannst es direkt danach '
          'rückgängig machen.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect((await tester.workoutRows(ui)).single.deletedAtUtc, isNull);

      await tapVisible(tester, find.text('Training löschen'));
      await tester.tapAndSettleDb(find.text('Löschen'));
      expect((await tester.workoutRows(ui)).single.deletedAtUtc, isNotNull);
      expect(await tester.xpAwards(ui), isEmpty, reason: 'the XP went with it');
      expect(ui.feedback.last!.message, 'Training gelöscht');

      await tester.runAsync(() => ui.feedback.last!.undo!.perform());
      final row = (await tester.workoutRows(ui)).single;
      expect(row.id, entry.id);
      expect(row.deletedAtUtc, isNull);
      expect(await tester.xpAwards(ui), hasLength(1));
    });

    testWidgets('a failed delete keeps the workout (AT27)', (tester) async {
      final projection = RecordingProjectionSynchronizer();
      final ui = await createFocusUi(tester, projection: projection);
      final entry = await tester.addWorkout(ui);
      await pumpFocusApp(tester, ui, initialLocation: '/workouts/${entry.id}');
      projection.failure = StateError('disk full');
      await tapVisible(tester, find.text('Training löschen'));
      await tester.tapAndSettleDb(find.text('Löschen'));
      expect((await tester.workoutRows(ui)).single.deletedAtUtc, isNull);
      expect(
        ui.feedback.last!.message,
        'Löschen fehlgeschlagen. Das Training ist unverändert.',
      );
    });

    testWidgets('an unknown workout is "not found" with a way back', (
      tester,
    ) async {
      final ui = await createFocusUi(tester);
      final router = await pumpFocusApp(
        tester,
        ui,
        initialLocation: '/workouts/unknown',
      );
      expect(find.text('Training nicht gefunden'), findsOneWidget);
      await tester.tap(find.text('Zur Übersicht'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/workouts');
    });

    testWidgets('leaving after changes asks first; discarding leaves and '
        'saves nothing', (tester) async {
      final ui = await createFocusUi(tester);
      final entry = await tester.addWorkout(ui, minutes: 40);
      final router = await pumpFocusApp(
        tester,
        ui,
        initialLocation: '/workouts/${entry.id}',
      );
      await tester.enterText(durationField, '99');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await tester.tap(find.text('Verwerfen'));
      await tester.pumpAndSettle();
      expect(
        router.state.uri.path,
        '/workouts',
        reason: 'back to the overview',
      );
      expect((await tester.workoutRows(ui)).single.durationMinutes, 40);
    });
  });

  testSemantics('every control has a label and a 48 px target (AT33, AT34)', (
    tester,
  ) async {
    final ui = await createFocusUi(tester);
    await openNew(tester, ui);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(find.bySemanticsLabel('Dauer um 5 Minuten erhöhen'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Dauer um 5 Minuten verringern'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Dauer in Minuten'), findsOneWidget);
    expect(find.bySemanticsLabel('Trainingskategorie'), findsOneWidget);
    expect(find.bySemanticsLabel('Intensität'), findsWidgets);
  });
}
