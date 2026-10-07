import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/app/screens/module_disabled_screen.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/presentation/weight_overview_screen.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_overview_screen.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_routes.dart';
import 'package:self_improvement/features/dashboard/presentation/goals_today_screen.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_overview_card.dart';
import 'package:self_improvement/features/focus/presentation/focus_start_screen.dart';
import 'package:self_improvement/features/focus/presentation/workout_overview_screen.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/presentation/water_screen.dart';
import 'package:self_improvement/features/profile/presentation/goals_screen.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/presentation/habits_tab_screen.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../app/support/app_harness.dart';
import '../../../core/design/support/ring_arcs.dart';
import '../../../support/pump_app.dart';
import '../support/goals_today_kit.dart';

// BS-103 and BS-104 in the running app: the day card on Home opens "Ziele
// heute" over the shell, back leads to Home as it was, and the page and the
// ring always show the same numbers because they read the same status.

/// A day after the profile start: no welcome, the ring and its card.
final LocalDate _secondDay = LocalDate(2026, 10, 2);

Future<AppFixture> _pumpApp(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
  Size size = const Size(393, 852),
  double textScale = 1.0,
}) async {
  final harness = await createTestHarness(
    tester,
    onboarded: false,
    realProjection: true,
  );
  return pumpFullApp(
    tester,
    reuse: harness,
    onboarded: false,
    seed: (h) => h.seedOnboarded(startedOn: _secondDay),
    overrides: overrides,
    size: size,
    textScale: textScale,
  );
}

/// Taps the day card on Home and waits for the page.
Future<void> _openGoalsToday(AppFixture app) async {
  await app.tester.tap(find.byType(DayOverviewCard));
  await app.tester.pump();
  await app.settle();
}

Finder _backButton() => find.byIcon(AppIcon.back.data);

/// The arcs of the day ring on Home (the workout card has a ring of its own).
List<PaintedArc> _homeArcs(WidgetTester tester) => paintedArcs(
  tester,
  ring: find.descendant(
    of: find.byType(DayOverviewCard),
    matching: find.byType(ProgressRing),
  ),
);

void main() {
  group('the card opens the page and back leads to Home (BS-104, C02)', () {
    testWidgets('a tap opens "Ziele heute" over the shell, with the numbers '
        'of the ring', (tester) async {
      final app = await _pumpApp(tester);
      expect(app.location, AppRoutes.home);
      expect(find.text('0 von 5'), findsOneWidget);
      final home = _homeArcs(tester);

      await _openGoalsToday(app);

      expect(app.location, DashboardRoutes.goalsToday);
      expect(find.byType(GoalsTodayScreen), findsOneWidget);
      expect(find.text('Ziele heute'), findsOneWidget);
      expect(find.byType(AppBottomNavBar), findsNothing);
      expect(find.text('0 von 5'), findsOneWidget);
      expect(find.text('Noch nichts erreicht'), findsOneWidget);
      // The same ring: Home and the page paint the same arcs.
      expect(paintedArcs(tester), home);
    });

    testWidgets('the back button of the page leads to Home, the ring is '
        'still there', (tester) async {
      final app = await _pumpApp(tester);
      await _openGoalsToday(app);
      await tester.tap(_backButton());
      await app.settle();
      expect(app.location, AppRoutes.home);
      expect(find.byType(GoalsTodayScreen), findsNothing);
      expect(find.byType(DayOverviewCard), findsOneWidget);
      expect(find.byType(AppBottomNavBar), findsOneWidget);
    });

    testWidgets('the system back button leads to Home, it does not close the '
        'app', (tester) async {
      final app = await _pumpApp(tester);
      await _openGoalsToday(app);
      expect(await app.systemBack(), isTrue, reason: 'the app handled it');
      expect(app.location, AppRoutes.home);
      expect(app.exitRequests, 0);
      expect(find.byType(DayOverviewCard), findsOneWidget);
    });

    testWidgets('Home keeps its scroll position', (tester) async {
      final app = await _pumpApp(tester);
      final scrollable = find
          .descendant(
            of: find.byType(Scaffold).first,
            matching: find.byType(Scrollable),
          )
          .first;
      double offset() =>
          tester.state<ScrollableState>(scrollable).position.pixels;
      await tester.drag(scrollable, const Offset(0, -60));
      await tester.pump();
      final before = offset();
      expect(before, greaterThan(0));

      await tester.tap(find.byType(DayOverviewCard), warnIfMissed: false);
      await tester.pump();
      await app.settle();
      expect(app.location, DashboardRoutes.goalsToday);
      await tester.tap(_backButton());
      await app.settle();

      expect(app.location, AppRoutes.home);
      expect(offset(), before);
    });

    testWidgets('a page opened from outside (a link) has Home below it after '
        'back', (tester) async {
      final app = await _pumpApp(tester);
      unawaited(app.router.push<void>(DashboardRoutes.goalsToday));
      await tester.pump();
      await app.settle();
      expect(find.byType(GoalsTodayScreen), findsOneWidget);
      await tester.tap(_backButton());
      await app.settle();
      expect(app.location, AppRoutes.home);
    });

    testWidgets('a page reached with go (nothing below it) leads to Home, '
        'never to a dead end', (tester) async {
      final app = await _pumpApp(tester);
      app.router.go(DashboardRoutes.goalsToday);
      await app.settle();
      expect(find.byType(GoalsTodayScreen), findsOneWidget);
      await tester.tap(_backButton());
      await app.settle();
      expect(app.location, AppRoutes.home);
      expect(find.byType(DayOverviewCard), findsOneWidget);
    });

    testWidgets('(AT33) at 320 px and 200 % the card is still one tap away '
        'from the page', (tester) async {
      final app = await _pumpApp(
        tester,
        size: const Size(320, 640),
        textScale: 2.0,
      );
      await tester.ensureVisible(find.byType(DayOverviewCard));
      await _openGoalsToday(app);
      expect(app.location, DashboardRoutes.goalsToday);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without a daily goal Home shows "Noch keine Tagesziele" '
        'and no card that opens the page', (tester) async {
      final app = await _pumpApp(
        tester,
        overrides: <Override>[todayStatusOverride(statusOf(const []))],
      );
      expect(find.text('Noch keine Tagesziele'), findsOneWidget);
      expect(find.byType(DayOverviewCard), findsNothing);
      await tester.tap(find.text('Ziele festlegen'));
      await app.settle();
      expect(app.location, AppRoutes.goals);
      expect(find.byType(GoalsScreen), findsOneWidget);
    });
  });

  group('the page and the ring show the same numbers (BS-103, C04)', () {
    for (final entry in goalStates.entries) {
      testWidgets('${entry.key}: Home and "Ziele heute" say the same x of y '
          'and paint the same ring', (tester) async {
        final status = statusOf(entry.value);
        final app = await _pumpApp(
          tester,
          overrides: <Override>[todayStatusOverride(status)],
        );
        final text = '${status.fulfilledCount} von ${status.applicableCount}';
        expect(find.text(text), findsOneWidget);
        final home = _homeArcs(tester);
        await _openGoalsToday(app);
        expect(find.text(text), findsOneWidget);
        expect(paintedArcs(tester), home);
        await tester.tap(_backButton());
        await app.settle();
        expect(find.text(text), findsOneWidget);
        expect(_homeArcs(tester), home);
      });
    }

    testWidgets('(AT23) a saved weight changes the ring and the page at '
        'once, and the page lists the real data', (tester) async {
      final app = await _pumpApp(tester);
      await _openGoalsToday(app);
      expect(find.text('0 von 5'), findsOneWidget);
      expect(find.text('Noch nicht gewogen'), findsOneWidget);

      await app.run(
        () => app.container
            .read(weightRepositoryProvider)
            .create(
              commandId: 'w1',
              draft: WeightDraft(
                weightGrams: 71500,
                occurredAtUtc: app.harness.clock.nowUtc(),
              ),
            ),
      );
      await app.settle();

      expect(find.text('1 von 5'), findsOneWidget);
      expect(find.text('Heute gewogen'), findsOneWidget);
      expect(find.text('Noch 4 Ziele offen. Bleib dran!'), findsOneWidget);
      await tester.tap(_backButton());
      await app.settle();
      expect(find.text('1 von 5'), findsOneWidget);
      expect(
        find.text('Du hast heute 1 von 5 Zielen erreicht.'),
        findsOneWidget,
      );
    });

    testWidgets('(C03) a module that is switched off takes its goals from '
        'the ring and from the page', (tester) async {
      final app = await _pumpApp(tester);
      await _openGoalsToday(app);
      expect(find.text('Wasser'), findsOneWidget);
      expect(find.text('0 von 5'), findsOneWidget);

      await app.run(
        () => app.container
            .read(moduleManagerProvider)
            .setEnabled(
              commandId: app.harness.ids.newId(),
              module: ModuleId.nutrition,
              enabled: false,
            ),
      );
      await app.settle();
      expect(find.text('Wasser'), findsNothing);
      expect(find.text('0 von 4'), findsOneWidget);

      await tester.tap(_backButton());
      await app.settle();
      expect(find.text('0 von 4'), findsOneWidget);
    });
  });

  group('a row opens the real module, the page is current on the way back '
      '(BS-105)', () {
    testWidgets('(C02, AT23) "Wasser" opens the water page; a glass saved '
        'there shows on the page after back', (tester) async {
      final app = await _pumpApp(tester);
      await _openGoalsToday(app);
      expect(find.text('0 von 2,5 l · 0 %'), findsOneWidget);

      await tester.tap(find.text('Wasser'));
      await app.settle();
      expect(app.location, '/water');
      expect(find.byType(WaterScreen), findsOneWidget);

      await app.run(
        () => app.container
            .read(waterRepositoryProvider)
            .create(
              commandId: 'glass',
              draft: WaterDraft(
                amountMl: 250,
                occurredAtUtc: app.harness.clock.nowUtc(),
              ),
            ),
      );
      await app.settle();
      await tester.tap(_backButton());
      await app.settle();

      expect(app.location, DashboardRoutes.goalsToday);
      expect(find.byType(GoalsTodayScreen), findsOneWidget);
      expect(find.text('0,25 von 2,5 l · 10 %'), findsOneWidget);
      expect(find.text('0 von 2,5 l · 0 %'), findsNothing);
    });

    for (final (title, path, screen) in <(String, String, Type)>[
      ('Schritte', '/steps', StepsOverviewScreen),
      ('Gewicht erfassen', '/weight', WeightOverviewScreen),
      ('Fokus', '/focus', FocusStartScreen),
      ('Workouts diese Woche', '/workouts', WorkoutOverviewScreen),
    ]) {
      testWidgets('(C02) "$title" opens $path, back shows the page', (
        tester,
      ) async {
        final app = await _pumpApp(tester);
        await _openGoalsToday(app);
        await tester.ensureVisible(find.text(title));
        await tester.pump();
        await tester.tap(find.text(title));
        await app.settle();
        expect(app.location, path);
        expect(find.byType(screen), findsOneWidget);
        await tester.tap(_backButton());
        await app.settle();
        expect(app.location, DashboardRoutes.goalsToday);
        expect(find.text('0 von 5'), findsOneWidget);
      });
    }

    testWidgets('(C02) "Aufgabe erledigen" opens the task list: the tab '
        'Habits, and back leads to Home', (tester) async {
      final app = await _pumpApp(tester);
      await _openGoalsToday(app);
      await tester.ensureVisible(find.text('Aufgabe erledigen'));
      await tester.pump();
      await tester.tap(find.text('Aufgabe erledigen'));
      await app.settle();
      expect(app.location, AppRoutes.habits);
      expect(app.fullLocation, AppRoutes.habitsTasks);
      expect(find.byType(HabitsTabScreen), findsOneWidget);
      expect(find.byType(AppBottomNavBar), findsOneWidget);
      expect(await app.systemBack(), isTrue);
      expect(app.location, AppRoutes.home);
    });

    testWidgets('(C02) a habit is a goal of the day and opens the habit '
        'list', (tester) async {
      final app = await _pumpApp(tester);
      await app.run(
        () => app.container
            .read(habitRepositoryProvider)
            .create(
              commandId: 'habit',
              draft: const HabitDraft(title: 'Lesen'),
            ),
      );
      await app.settle();
      await _openGoalsToday(app);
      // The ring counted the habit: one more goal.
      expect(find.text('0 von 6'), findsOneWidget);
      expect(find.text('Lesen'), findsOneWidget);
      expect(find.text('Noch nicht abgehakt'), findsOneWidget);
      await tester.ensureVisible(find.text('Lesen'));
      await tester.pump();
      await tester.tap(find.text('Lesen'));
      await app.settle();
      expect(app.location, AppRoutes.habits);
      expect(find.byType(HabitsTabScreen), findsOneWidget);
    });

    testWidgets('(C02) "Ziele bearbeiten" opens the real goal editor, back '
        'shows the page', (tester) async {
      final app = await _pumpApp(tester);
      await _openGoalsToday(app);
      await tester.ensureVisible(find.text('Ziele bearbeiten'));
      await tester.pump();
      await tester.tap(find.text('Ziele bearbeiten'));
      await app.settle();
      expect(app.location, AppRoutes.goals);
      expect(find.byType(GoalsScreen), findsOneWidget);
      await tester.tap(_backButton());
      await app.settle();
      expect(app.location, DashboardRoutes.goalsToday);
      expect(find.text('0 von 5'), findsOneWidget);
    });

    testWidgets('(C03) a module that is switched off while its page is open: '
        'the page says so, and the page below has lost the goal', (
      tester,
    ) async {
      final app = await _pumpApp(tester);
      await _openGoalsToday(app);
      await tester.tap(find.text('Wasser'));
      await app.settle();
      expect(find.byType(WaterScreen), findsOneWidget);

      await app.run(
        () => app.container
            .read(moduleManagerProvider)
            .setEnabled(
              commandId: app.harness.ids.newId(),
              module: ModuleId.nutrition,
              enabled: false,
            ),
      );
      await app.settle();
      expect(find.byType(ModuleDisabledScreen), findsOneWidget);
      expect(find.byType(WaterScreen), findsNothing);

      await tester.tap(_backButton());
      await app.settle();
      expect(app.location, DashboardRoutes.goalsToday);
      expect(find.text('Wasser'), findsNothing);
      expect(find.text('0 von 4'), findsOneWidget);
    });
  });
}
