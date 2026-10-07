import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/dashboard/domain/motivation.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/dashboard/application/day_browser_providers.dart';
import 'package:self_improvement/features/dashboard/presentation/goals_today_screen.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../core/design/support/ring_arcs.dart';
import '../../../support/pump_app.dart';
import '../support/dashboard_test_kit.dart';
import '../support/day_browser_kit.dart';

// BS-93: the ring and the goals of the day Home shows come from the snapshot of
// THAT day and the facts of that day, so they are the numbers the day had then,
// also after the goals changed. "Ziele heute" shows the same day.

/// Text of a card value line (a `Text.rich` of value, unit and target).
Finder _rich(String text) => find.text(text, findRichText: true);

/// Two days before the host day: Thursday, 1 October.
final LocalDate _day = hostToday.addDays(-2);

/// The next morning: the clock moves a day on and Home reads it.
Future<void> _nextDay(WidgetTester tester, RealHome home) async {
  home.harness.clock.advance(const Duration(days: 1));
  home.container.read(todayProvider.notifier).refresh();
  await tester.pump(const Duration(milliseconds: 300));
  await settle(tester);
}

void main() {
  group('the day keeps the goals it had (BS-93, AT24, C04)', () {
    testWidgets('(BS-93, AT24, C04) a goal changed "ab morgen": the day before '
        'keeps its target in the ring, the card and the goals page', (
      tester,
    ) async {
      final home = await pumpRealHome(tester);
      await seedWater(tester, home, hostToday, 2600);
      // 3 litres from tomorrow on.
      await tester.runCommand(
        () => home.container
            .read(goalsCommandsProvider)
            .update(
              commandId: home.harness.ids.newId(),
              changes: <GoalType, GoalSetting>{
                GoalType.water: const GoalSetting(target: 3000),
              },
            ),
      );
      // Today still counts 2.5 litres.
      expect(_rich('2,6 / 2,5 l'), findsOneWidget);

      await _nextDay(tester, home);
      final newToday = hostToday.addDays(1);
      expect(home.container.read(todayProvider), newToday);
      expect(find.text('Sonntag, 4. Oktober'), findsOneWidget);
      // The new day counts 3 litres, and nothing was drunk yet.
      expect(_rich('0 / 3 l'), findsOneWidget);

      // Yesterday was a 2.5 litre day: reached, as it was.
      await showDay(tester, home, hostToday);
      expect(find.text('Samstag, 3. Oktober'), findsOneWidget);
      expect(_rich('2,6 / 2,5 l'), findsOneWidget);
      expect(find.text('Tagesziel erreicht · 104 %'), findsOneWidget);
      expect(_rich('2,6 / 3 l'), findsNothing);
      expect(
        find.text('An diesem Tag hast du 1 von 5 Zielen erreicht.'),
        findsOneWidget,
      );

      // "Ziele heute" of that day: the same target and the same status.
      await tester.tap(find.text('1 von 5'));
      await tester.pumpAndSettle();
      expect(find.byType(GoalsTodayScreen), findsOneWidget);
      expect(find.text('Nicht heute'), findsOneWidget);
      expect(find.text('2,6 von 2,5 l · 104 %'), findsOneWidget);
    });

    testWidgets('(BS-93, AT24, C04) a goal switched off from tomorrow still '
        'counts on the day before', (tester) async {
      final home = await pumpRealHome(tester);
      await tester.runCommand(
        () => home.container
            .read(goalsCommandsProvider)
            .update(
              commandId: home.harness.ids.newId(),
              changes: <GoalType, GoalSetting>{
                GoalType.water: const GoalSetting(enabled: false),
              },
            ),
      );
      await _nextDay(tester, home);
      // Today: four goals count.
      expect(find.text('0 von 4'), findsOneWidget);
      // Yesterday: five, the water goal was still on.
      await showDay(tester, home, hostToday);
      expect(find.text('0 von 5'), findsOneWidget);
      expect(
        find.text('An diesem Tag hast du kein Ziel erreicht.'),
        findsOneWidget,
      );
    });

    testWidgets('(BS-93, AT24) a goal switched on from tomorrow is not a goal '
        'of the days before', (tester) async {
      final home = await pumpRealHome(tester);
      await tester.runCommand(
        () => home.container
            .read(goalsCommandsProvider)
            .update(
              commandId: home.harness.ids.newId(),
              changes: <GoalType, GoalSetting>{
                GoalType.workoutDaily: const GoalSetting(),
              },
            ),
      );
      await _nextDay(tester, home);
      expect(find.text('0 von 6'), findsOneWidget);
      await showDay(tester, home, hostToday);
      expect(find.text('0 von 5'), findsOneWidget);
      await showDay(tester, home, hostToday.addDays(-3));
      expect(find.text('0 von 5'), findsOneWidget);
    });
  });

  group('the ring of the day (BS-93, C04, C06)', () {
    Future<RealHome> seedDay(WidgetTester tester) async {
      final home = await pumpRealHome(tester);
      await seedWater(tester, home, _day, 2600);
      await seedSteps(tester, home, _day, 5000);
      await seedWeight(tester, home, _day, 71500);
      await seedFocus(tester, home, _day, 20);
      await seedCompletedTask(tester, home, _day, 'Steuer machen');
      await showDay(tester, home, _day);
      return home;
    }

    testWidgets('(BS-93, C04) it counts the goals reached on that day, says '
        'so in a factual sentence and carries no title of the lists', (
      tester,
    ) async {
      await seedDay(tester);
      final semantics = tester.ensureSemantics();
      expect(find.text('3 von 5'), findsOneWidget);
      expect(find.text('Zielen'), findsOneWidget);
      expect(
        find.text('An diesem Tag hast du 3 von 5 Zielen erreicht.'),
        findsOneWidget,
      );
      expect(find.text('Du hast heute 3 von 5 Zielen erreicht.'), findsNothing);
      // The titles speak of "today": none of the nine is on a day before.
      for (final standing in GoalsStanding.values) {
        for (final text in motivationTextsOf(standing)) {
          expect(find.text(text), findsNothing, reason: text);
        }
      }
      expect(
        find.bySemanticsLabel(
          'Ziele dieses Tages, 3 von 5 erreicht, Details öffnen',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('(BS-93, C06) the ring is yellow for some goals, grey for none '
        'and green for all, as on today', (tester) async {
      final home = await seedDay(tester);
      await tester.pumpAndSettle();
      final colors = AppThemeVariant.light.colors;
      expect(paintedArcs(tester), <PaintedArc>[
        (color: colors.track, sweep: 2 * math.pi),
        (color: colors.dayRing, sweep: 2 * math.pi * 3 / 5),
      ]);
      // Nothing reached that day: only the track.
      await showDay(tester, home, hostToday.addDays(-3));
      await tester.pumpAndSettle();
      expect(paintedArcs(tester), <PaintedArc>[
        (color: colors.track, sweep: 2 * math.pi),
      ]);
    });

    testWidgets('(BS-93) the card is tappable on a past day: it opens "Ziele '
        'heute" of that day, and back shows the same day on Home', (
      tester,
    ) async {
      final home = await seedDay(tester);
      await tester.tap(find.text('3 von 5'));
      await tester.pumpAndSettle();
      expect(find.byType(GoalsTodayScreen), findsOneWidget);
      expect(find.text('Ziele heute'), findsOneWidget);
      expect(find.text('Nicht heute'), findsOneWidget);
      expect(find.text('Donnerstag, 1. Oktober'), findsOneWidget);
      expect(find.text('3 von 5 erreicht'), findsOneWidget);
      expect(find.text('Du siehst die Werte dieses Tages.'), findsOneWidget);

      home.router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(GoalsTodayScreen), findsNothing);
      expect(
        home.container.read(browsedDayProvider).date,
        _day,
        reason: 'Home stays on the day',
      );
      expect(find.text('Donnerstag, 1. Oktober'), findsOneWidget);
    });

    testWidgets('(BS-93) "Zurück zu heute" on the page puts the page and Home '
        'on today', (tester) async {
      final home = await seedDay(tester);
      await tester.tap(find.text('3 von 5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zurück zu heute'));
      await settle(tester);
      expect(find.text('Nicht heute'), findsNothing);
      expect(find.text('Samstag, 3. Oktober'), findsOneWidget);
      home.router.pop();
      await tester.pumpAndSettle();
      expect(home.container.read(selectedDayProvider), isNull);
      expect(find.text('Dein Tag im Überblick'), findsOneWidget);
    });

    testWidgets('(BS-93) a day without a goal says so and offers nothing to '
        'set', (tester) async {
      final home = await pumpRealHome(tester);
      // Every goal off from tomorrow: today has none, the day before keeps its
      // five.
      await tester.runCommand(
        () => home.container
            .read(goalsCommandsProvider)
            .update(
              commandId: home.harness.ids.newId(),
              changes: <GoalType, GoalSetting>{
                for (final type in GoalType.values.where((t) => t.isDaily))
                  type: const GoalSetting(enabled: false),
              },
            ),
      );
      await _nextDay(tester, home);
      expect(find.text('Noch keine Tagesziele'), findsOneWidget);
      expect(find.text('Ziele festlegen'), findsOneWidget);
      // The day before still had its five goals.
      await showDay(tester, home, hostToday);
      expect(find.text('0 von 5'), findsOneWidget);
      expect(find.text('Noch keine Tagesziele'), findsNothing);
    });
  });

  group('"Ziele heute" of the day (BS-93, BS-103, C04)', () {
    testWidgets('(BS-93, C04) the rows are the goals of that day with its '
        'numbers, in the words of the past', (tester) async {
      final home = await pumpRealHome(tester);
      await seedWater(tester, home, _day, 2600);
      await seedSteps(tester, home, _day, 5000);
      await seedWeight(tester, home, _day, 71500);
      await seedFocus(tester, home, _day, 20);
      await showDay(tester, home, _day);
      await tester.tap(find.text('2 von 5'));
      await tester.pumpAndSettle();

      expect(find.text('2,6 von 2,5 l · 104 %'), findsOneWidget);
      expect(find.text('5.000 von 10.000 · 50 %'), findsOneWidget);
      expect(find.text('20 von 25 Min. · 80 %'), findsOneWidget);
      expect(find.text('Gewogen'), findsOneWidget);
      expect(find.text('Keine Aufgabe erledigt'), findsOneWidget);
      // No weekly goal on a day that is not today.
      expect(find.text('Workouts diese Woche'), findsNothing);
      expect(find.text('Wochenziel · nicht im Tagesring'), findsNothing);
    });

    testWidgets('(BS-93, BS-99, C04) "Workout heute" of a past day tells how '
        'it was answered: a rest day', (tester) async {
      final home = await pumpRealHome(tester, workoutDailyGoal: true);
      await seedWorkoutMark(tester, home, _day, WorkoutDayMarkKind.rest);
      await showDay(tester, home, _day);
      await tester.tap(find.text('1 von 6'));
      await tester.pumpAndSettle();
      expect(find.text('Ruhetag'), findsWidgets);
      expect(
        find.text('Ruhetag eingetragen · keine XP, Streak bleibt'),
        findsOneWidget,
      );
    });

    testWidgets('(BS-93, BS-99, C04) a workout of a past day counts as "1 '
        'Training eingetragen"', (tester) async {
      final home = await pumpRealHome(tester, workoutDailyGoal: true);
      await seedWorkout(tester, home, _day);
      await showDay(tester, home, _day);
      await tester.tap(find.text('1 von 6'));
      await tester.pumpAndSettle();
      expect(find.text('1 Training eingetragen'), findsOneWidget);
    });

    testWidgets('(BS-93, C04) the habits of the day are rows with the names of '
        'the habits and the state of that day', (tester) async {
      final home = await pumpRealHome(
        tester,
        seed: (h) async {
          await seedHabitBeforeHome(
            h,
            'Lesen',
            startedOn: hostToday.addDays(-5),
            checked: <LocalDate>[_day],
          );
        },
      );
      await showDay(tester, home, _day);
      await tester.tap(find.text('1 von 6'));
      await tester.pumpAndSettle();
      expect(find.text('Lesen'), findsOneWidget);
      expect(find.text('Abgehakt'), findsOneWidget);
    });
  });
}
