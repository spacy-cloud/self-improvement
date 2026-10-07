import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/dashboard_test_kit.dart';
import '../support/day_browser_kit.dart';

// BS-93: the cards of Home show the day that is shown. Every card of the
// bundled modules, for today and for a day before it, over the real database:
// the numbers are the ones of that day (with the goals that counted then), a
// day without records says so and never reads as zero, and nothing on a card of
// another day records something (a tap would put it on today).

/// Text of a card value line (a `Text.rich` of value, unit and target).
Finder _rich(String text) => find.text(text, findRichText: true);

/// The day two days before the host day: Thursday, 1 October.
final LocalDate _day = hostToday.addDays(-2);

/// The day before the host day: Friday, 2 October.
final LocalDate _yesterday = hostToday.addDays(-1);

void main() {
  group('water (BS-93, N01, C04)', () {
    testWidgets('(BS-93, C04) the day shows what was drunk against the target '
        'of that day, and no quick add', (tester) async {
      final home = await pumpRealHome(tester, seed: (h) async {});
      await seedWater(tester, home, _day, 1500);
      await seedWater(tester, home, hostToday, 250);
      final semantics = tester.ensureSemantics();

      // Today is the live card with its quick adds.
      expect(
        find.bySemanticsLabel('250 Milliliter Wasser hinzufügen'),
        findsOneWidget,
      );
      expect(_rich('0,25 / 2,5 l'), findsOneWidget);

      await showDay(tester, home, _day);
      expect(_rich('1,5 / 2,5 l'), findsOneWidget);
      expect(find.text('60 % erreicht'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Wasser an diesem Tag: 1,5 l von 2,5 l, 60 Prozent erreicht.',
        ),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel('250 Milliliter Wasser hinzufügen'),
        findsNothing,
      );
      expect(find.text('250 ml'), findsNothing);
      semantics.dispose();
    });

    testWidgets('(BS-93) a day above the target reads the real percentage '
        'and says the goal was reached', (tester) async {
      final home = await pumpRealHome(tester);
      await seedWater(tester, home, _day, 2600);
      await showDay(tester, home, _day);
      expect(_rich('2,6 / 2,5 l'), findsOneWidget);
      expect(find.text('Tagesziel erreicht · 104 %'), findsOneWidget);
    });

    testWidgets('(BS-93) a day without an entry says "Nichts eingetragen" and '
        'shows no zero', (tester) async {
      final home = await pumpRealHome(tester);
      await showDay(tester, home, _day);
      expect(find.text('Nichts eingetragen'), findsOneWidget);
      expect(_rich('– / 2,5 l'), findsOneWidget);
      expect(_rich('0 / 2,5 l'), findsNothing);
    });

    testWidgets('(BS-93) the card opens the water screen', (tester) async {
      final home = await pumpRealHome(tester);
      await showDay(tester, home, _day);
      await tester.tap(find.text('Wasser'));
      await tester.pumpAndSettle();
      expect(find.text('Wasser eintragen'), findsOneWidget);
    });
  });

  group('steps (BS-93, W03, C04)', () {
    testWidgets('(BS-93, C04) the day shows its total against its target, '
        'without the action to enter one', (tester) async {
      final home = await pumpRealHome(tester);
      await seedSteps(tester, home, _day, 7450);
      await seedSteps(tester, home, hostToday, 1200);
      final semantics = tester.ensureSemantics();

      expect(find.text('Schritte aktualisieren'), findsOneWidget);
      expect(_rich('1.200 / 10.000'), findsOneWidget);

      await showDay(tester, home, _day);
      expect(_rich('7.450 / 10.000'), findsOneWidget);
      expect(find.text('75 % erreicht'), findsOneWidget);
      expect(find.text('Schritte aktualisieren'), findsNothing);
      expect(find.text('Schritte eintragen'), findsNothing);
      expect(
        find.bySemanticsLabel('Schritte, 7.450 / 10.000, 75 % erreicht'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('(BS-93) a reached day says so; a recorded zero is a value', (
      tester,
    ) async {
      final home = await pumpRealHome(tester);
      await seedSteps(tester, home, _day, 10240);
      await seedSteps(tester, home, _yesterday, 0);
      await showDay(tester, home, _day);
      expect(_rich('10.240 / 10.000'), findsOneWidget);
      expect(find.text('Ziel erreicht'), findsOneWidget);
      await showDay(tester, home, _yesterday);
      expect(_rich('0 / 10.000'), findsOneWidget);
      expect(find.text('0 % erreicht'), findsOneWidget);
    });

    testWidgets('(BS-93) a day without a total says "Keine Schritte '
        'eingetragen" and no number', (tester) async {
      final home = await pumpRealHome(tester);
      await showDay(tester, home, _day);
      expect(find.text('Keine Schritte eingetragen'), findsOneWidget);
      expect(_rich('0 / 10.000'), findsNothing);
    });
  });

  group('weight (BS-93, W01, C04)', () {
    testWidgets('(BS-93, C04) the card is the weight at the end of the day: a '
        'measurement of a later day is not part of it', (tester) async {
      final home = await pumpRealHome(tester);
      await seedWeight(tester, home, _day, 71500);
      await seedWeight(tester, home, hostToday, 72300);

      await showDay(tester, home, _day);
      expect(_rich('71,5 kg'), findsOneWidget);
      expect(_rich('72,3 kg'), findsNothing);
      expect(find.text('Gewicht eintragen'), findsNothing);

      await showDay(tester, home, hostToday);
      expect(_rich('72,3 kg'), findsOneWidget);
    });

    testWidgets('(BS-93) before the first measurement the card says so and '
        'offers no entry', (tester) async {
      final home = await pumpRealHome(tester);
      await seedWeight(tester, home, _yesterday, 71500);
      await showDay(tester, home, _day);
      expect(find.text('Keine Messung bis zu diesem Tag'), findsOneWidget);
      expect(find.text('Gewicht eintragen'), findsNothing);
      expect(_rich('71,5 kg'), findsNothing);
    });

    testWidgets('(BS-93) a measurement older than the curve is dated, the '
        'honest way', (tester) async {
      final home = await pumpRealHome(tester);
      await seedWeight(tester, home, LocalDate(2026, 9, 15), 70900);
      await showDay(tester, home, _day);
      expect(_rich('70,9 kg'), findsOneWidget);
      expect(find.text('Zuletzt Di., 15. Sep.'), findsOneWidget);
    });
  });

  group('workout (BS-93, F03, C04)', () {
    testWidgets('(BS-93, C04) the day shows its workout with the muscle '
        'groups, and no way to record one', (tester) async {
      final home = await pumpRealHome(tester);
      await seedWorkout(
        tester,
        home,
        _day,
        groups: <MuscleGroup>[MuscleGroup.chest, MuscleGroup.shoulders],
      );
      final semantics = tester.ensureSemantics();

      // Today still asks.
      expect(find.text('Training eintragen'), findsOneWidget);

      await showDay(tester, home, _day);
      expect(find.text('Oberkörper'), findsOneWidget);
      expect(find.text('Brust, Schultern'), findsOneWidget);
      expect(find.text('Training eintragen'), findsNothing);
      expect(find.text('Wie war dein Tag?'), findsNothing);
      expect(
        find.bySemanticsLabel('Workout, Oberkörper, Brust, Schultern'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('(BS-93) two workouts on the day say how many there were', (
      tester,
    ) async {
      final home = await pumpRealHome(tester);
      await seedWorkout(tester, home, _day, title: 'Morgens', hour: 6);
      await seedWorkout(tester, home, _day, title: 'Abends', hour: 17);
      await showDay(tester, home, _day);
      expect(find.text('Abends'), findsOneWidget);
      expect(find.text('2 Trainings an diesem Tag'), findsOneWidget);
    });

    testWidgets('(BS-93, BS-99) a rest day and a skipped day of the past are '
        'shown, and cannot be set or taken back from here', (tester) async {
      final home = await pumpRealHome(tester, workoutDailyGoal: true);
      await seedWorkoutMark(tester, home, _day, WorkoutDayMarkKind.rest);
      await seedWorkoutMark(
        tester,
        home,
        _yesterday,
        WorkoutDayMarkKind.skipped,
      );
      await showDay(tester, home, _day);
      expect(find.text('Ruhetag'), findsOneWidget);
      expect(
        find.text('Zählt als erreicht, keine XP. Die Streak bleibt.'),
        findsOneWidget,
      );
      expect(find.text('Rückgängig'), findsNothing);
      await showDay(tester, home, _yesterday);
      expect(find.text('Übersprungen'), findsOneWidget);
      expect(find.text('Rückgängig'), findsNothing);
      expect(find.text('Wie war dein Tag?'), findsNothing);
    });

    testWidgets('(BS-93) a day without a workout says so and shows no zero', (
      tester,
    ) async {
      final home = await pumpRealHome(tester);
      await showDay(tester, home, _day);
      expect(find.text('Kein Training eingetragen'), findsOneWidget);
    });
  });

  group('focus (BS-93, F01, C04)', () {
    testWidgets('(BS-93, C04) the day shows the saved focus time against the '
        'goal of that day', (tester) async {
      final home = await pumpRealHome(tester);
      await seedFocus(tester, home, _day, 20);
      await showDay(tester, home, _day);
      expect(_rich('20 / 25 Min.'), findsOneWidget);
      expect(find.text('Es fehlten 5 Min. bis zum Tagesziel'), findsOneWidget);

      await seedFocus(tester, home, _yesterday, 25);
      await showDay(tester, home, _yesterday);
      expect(_rich('25 / 25 Min.'), findsOneWidget);
      expect(find.text('Tagesziel erreicht'), findsOneWidget);
    });

    testWidgets('(BS-93) a day without a session says so and shows no zero', (
      tester,
    ) async {
      final home = await pumpRealHome(tester);
      await showDay(tester, home, _day);
      expect(find.text('Keine Sitzung an diesem Tag'), findsOneWidget);
      expect(_rich('– / 25 Min.'), findsOneWidget);
    });
  });

  group('meals (BS-93, N02, C04)', () {
    testWidgets('(BS-93, C04) the day shows the meals and only the known '
        'calories', (tester) async {
      final home = await pumpRealHome(tester);
      await seedMeal(tester, home, _day, 'Frühstück', kcal: 400, hour: 7);
      await seedMeal(tester, home, _day, 'Mittagessen', hour: 11);
      final semantics = tester.ensureSemantics();
      await showDay(tester, home, _day);
      expect(_rich('2 Mahlzeiten'), findsOneWidget);
      expect(
        find.text('400 kcal bekannt · Kalorien unvollständig'),
        findsOneWidget,
      );
      expect(find.text('Mahlzeit eintragen'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('^Ernährung an diesem Tag: ')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('(BS-93) a day without a meal says so', (tester) async {
      final home = await pumpRealHome(tester);
      await showDay(tester, home, _day);
      expect(find.text('Keine Mahlzeit eingetragen'), findsOneWidget);
      expect(find.text('Mahlzeit eintragen'), findsNothing);
    });
  });

  group('tasks and habits (BS-93, T01, T02, C04)', () {
    testWidgets('(BS-93, C04) the day shows the tasks completed on it and its '
        'habits with their state, and nothing can be ticked', (tester) async {
      final home = await pumpRealHome(tester);
      await seedCompletedTask(tester, home, _day, 'Steuer machen');
      final habit = await seedHabit(
        tester,
        home,
        'Lesen',
        startedOn: hostToday.addDays(-5),
        checked: <LocalDate>[_day],
      );
      final semantics = tester.ensureSemantics();

      await showDay(tester, home, _day);
      expect(find.text('Aufgaben und Gewohnheiten'), findsOneWidget);
      expect(find.text('Heute abhaken'), findsNothing);
      expect(find.text('2 von 2 erledigt'), findsOneWidget);
      expect(find.text('Steuer machen'), findsOneWidget);
      expect(find.text('Erledigt um 10:00'), findsOneWidget);
      expect(find.text('Lesen'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Gewohnheit Lesen, an diesem Tag erledigt'),
        findsWidgets,
      );

      // A day on which the habit was not checked.
      await showDay(tester, home, _yesterday);
      expect(find.text('0 von 1 erledigt'), findsOneWidget);
      expect(find.text('Steuer machen'), findsNothing);
      expect(
        find.bySemanticsLabel('Gewohnheit Lesen, an diesem Tag offen'),
        findsWidgets,
      );

      // The box is a display here: a tap records nothing.
      final checks = await tester.runAsync(
        () => home.harness.database
            .customSelect(
              'SELECT COUNT(*) AS n FROM habit_checks WHERE habit_id = ?1',
              variables: [Variable<String>(habit)],
            )
            .getSingle(),
      );
      await tester.tap(
        find.bySemanticsLabel('Gewohnheit Lesen, an diesem Tag offen').first,
      );
      await settle(tester);
      final after = await tester.runAsync(
        () => home.harness.database
            .customSelect(
              'SELECT COUNT(*) AS n FROM habit_checks WHERE habit_id = ?1',
              variables: [Variable<String>(habit)],
            )
            .getSingle(),
      );
      expect(after!.read<int>('n'), checks!.read<int>('n'));
      semantics.dispose();
    });

    testWidgets('(BS-93) a day without a completed task and a habit says what '
        'it had, and offers nothing to create', (tester) async {
      final home = await pumpRealHome(tester);
      await showDay(tester, home, _day);
      expect(
        find.text(
          'An diesem Tag wurde keine Aufgabe erledigt, und es gab '
          'keine Gewohnheit.',
        ),
        findsOneWidget,
      );
      expect(find.text('Aufgabe anlegen'), findsNothing);
      expect(find.text('Gewohnheit anlegen'), findsNothing);
    });

    testWidgets('(BS-93) today keeps its card "Heute abhaken"', (tester) async {
      await pumpRealHome(tester);
      expect(find.text('Heute abhaken'), findsOneWidget);
      expect(find.text('Aufgaben und Gewohnheiten'), findsNothing);
    });
  });

  group('XP and level (BS-93, G02, C04)', () {
    testWidgets('(BS-93, C04) the card is the level at the end of the day: '
        'what later days earned is not part of it', (tester) async {
      final home = await pumpRealHome(tester);
      for (var i = 0; i < 3; i++) {
        await seedWater(tester, home, _day, 300);
      }
      for (var i = 0; i < 2; i++) {
        await seedWater(tester, home, _yesterday, 300);
      }
      final semantics = tester.ensureSemantics();

      await showDay(tester, home, _day);
      expect(find.text('Level 1'), findsOneWidget);
      expect(find.text('15 / 100 XP'), findsOneWidget);
      expect(find.text('Stand am Ende dieses Tages'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('^XP und Level: .*Stand am Ende dieses')),
        findsOneWidget,
      );

      await showDay(tester, home, _yesterday);
      expect(find.text('25 / 100 XP'), findsOneWidget);

      await showDay(tester, home, hostToday);
      expect(find.text('25 / 100 XP'), findsOneWidget);
      expect(find.text('Stand am Ende dieses Tages'), findsNothing);
      semantics.dispose();
    });
  });

  group('a card the module has no day for (BS-93)', () {
    testWidgets('(BS-93) the bundled cards all have one', (tester) async {
      final home = await pumpRealHome(tester);
      await showDay(tester, home, _day);
      for (final title in <String>[
        'Schritte',
        'Wasser',
        'Gewicht',
        'Workout',
        'Fokus',
        'Aufgaben und Gewohnheiten',
        'Ernährung',
        'XP und Level',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });
  });
}
