import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_controller.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_navigation.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_state.dart';
import 'package:self_improvement/features/onboarding/presentation/onboarding_screen.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/goal_stepper_row.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/onboarding_top_bar.dart';

import '../../../support/pump_app.dart';
import '../support/onboarding_steps.dart';
import '../support/onboarding_test_env.dart';

void main() {
  group('first start', () {
    testWidgets(
      'shows only the welcome screen: no account, no example data (AT01, C01)',
      (tester) async {
        await pumpOnboarding(tester);

        expect(find.text('App-Name'), findsOneWidget);
        expect(
          find.text('Kleine Schritte, große Veränderungen.'),
          findsOneWidget,
        );
        expect(find.text('Los geht’s'), findsOneWidget);
        expect(find.text('Überspringen'), findsOneWidget);
        // The old design had a sign-in link; the app has no accounts.
        expect(find.textContaining('Konto'), findsNothing);
        expect(find.textContaining('anmelden'), findsNothing);
        // No numbered step and no top bar on the welcome screen.
        expect(find.byType(OnboardingTopBar), findsNothing);
        expect(find.textContaining('von 4'), findsNothing);
      },
    );

    testWidgets('walks through the five screens, four of them numbered (C02)', (
      tester,
    ) async {
      await pumpOnboarding(tester);

      await tapPrimary(tester);
      expect(find.text('Schritt 1 von 4'), findsOneWidget);
      expect(find.text('Was ist dein Ziel?'), findsOneWidget);
      expect(find.byType(OnboardingTopBar), findsOneWidget);
      await tapPrimary(tester);
      expect(find.text('Schritt 2 von 4'), findsOneWidget);
      expect(find.text('Was willst du nutzen?'), findsOneWidget);
      await tapPrimary(tester);
      expect(find.text('Schritt 3 von 4'), findsOneWidget);
      expect(find.text('Erzähl uns von dir'), findsOneWidget);
      await tapPrimary(tester);
      expect(find.text('Schritt 4 von 4'), findsOneWidget);
      expect(find.text('Deine Tagesziele'), findsOneWidget);
      expect(
        find.descendant(
          of: primaryButton,
          matching: find.text('Fertig – los geht’s'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'the goals step starts without a selection and has no sleep reference (AT01)',
      (tester) async {
        final env = await pumpOnboarding(tester);
        await goToStep(tester, OnboardingStep.goals);

        for (final title in <String>[
          'Abnehmen',
          'Fitter werden',
          'Mehr bewegen',
          'Gesünder leben',
          'Gute Gewohnheiten',
        ]) {
          expect(find.text(title), findsOneWidget);
        }
        expect(find.text('Trinken und Ernährung'), findsOneWidget);
        expect(find.textContaining('Schlaf'), findsNothing);
        expect(selectedGoalTitles(tester), isEmpty, reason: 'no preselection');
        expect(
          env.container.read(onboardingControllerProvider).motivationGoals,
          isEmpty,
        );

        await tester.tap(find.text('Mehr bewegen'));
        await tester.pump();
        await tester.tap(find.text('Abnehmen'));
        await tester.pump();
        expect(selectedGoalTitles(tester), <String>[
          'Abnehmen',
          'Mehr bewegen',
        ]);
        await tester.tap(find.text('Abnehmen'));
        await tester.pump();
        expect(selectedGoalTitles(tester), <String>['Mehr bewegen']);
      },
    );

    testWidgets(
      'the modules step starts with all five selected and allows none (AT04, C03)',
      (tester) async {
        final env = await pumpOnboarding(tester);
        await goToStep(tester, OnboardingStep.modules);

        final switches = find.byType(AppSwitch);
        expect(switches, findsNWidgets(5));
        expect(
          tester
              .widgetList<AppSwitch>(switches)
              .every((toggle) => toggle.value),
          isTrue,
        );
        expect(
          find.textContaining('Alle Bereiche sind ausgeschaltet'),
          findsNothing,
        );

        for (var i = 0; i < 5; i++) {
          await tester.tap(switches.at(i));
          await tester.pump();
        }
        expect(
          tester
              .widgetList<AppSwitch>(switches)
              .every((toggle) => !toggle.value),
          isTrue,
        );
        expect(
          env.container.read(onboardingControllerProvider).enabledModules,
          isEmpty,
        );
        expect(
          find.textContaining('Alle Bereiche sind ausgeschaltet'),
          findsOneWidget,
          reason: 'the empty choice is explained, not blocked',
        );
        // Continuing is still possible.
        await tapPrimary(tester);
        expect(find.text('Erzähl uns von dir'), findsOneWidget);
      },
    );

    testWidgets(
      'the body step is voluntary and shows no example person or computed value (AT01)',
      (tester) async {
        await pumpOnboarding(tester);
        await goToStep(tester, OnboardingStep.body);

        for (final name in <String>['name', 'age', 'height', 'weight']) {
          expect(typedIn(tester, name), isEmpty, reason: '$name starts empty');
        }
        expect(find.text('optional'), findsNWidgets(4));
        // Nothing of the design's example person, no BMI, no target weight.
        for (final example in <String>[
          '74,0',
          '68,0',
          '180',
          '22',
          'BMI',
          'Zielgewicht',
          'machbar',
          'Aktuelles Gewicht',
        ]) {
          expect(
            find.textContaining(example),
            findsNothing,
            reason: 'no "$example" on the body step',
          );
        }
        expect(find.textContaining('nicht als Messung'), findsOneWidget);
      },
    );

    testWidgets(
      'the daily goals show the suggested values; reminders are off (C07)',
      (tester) async {
        await pumpOnboarding(tester);
        await goToStep(tester, OnboardingStep.dailyGoals);

        expect(find.text('10.000'), findsOneWidget);
        expect(find.text('2,5 l'), findsOneWidget);
        expect(find.text('25 Min.'), findsOneWidget);
        expect(find.text('3 ×'), findsOneWidget);
        expect(find.text('Schritte'), findsOneWidget);
        expect(find.text('Wasser'), findsOneWidget);
        expect(find.text('Fokus'), findsOneWidget);
        expect(find.text('Workouts'), findsOneWidget);
        expect(find.text('Aufgaben'), findsOneWidget);
        expect(find.text('Gewicht'), findsOneWidget);
        expect(
          find.text('Mindestens 1 Aufgabe pro Tag erledigen'),
          findsOneWidget,
        );
        expect(find.text('1 Gewichtseintrag pro Tag'), findsOneWidget);
        // The two on/off goals start on.
        expect(
          tester
              .widgetList<AppSwitch>(find.byType(AppSwitch))
              .every((s) => s.value),
          isTrue,
        );
        // Reminders: no switch, no permission, just the honest hint.
        expect(
          find.textContaining('Erinnerungen sind ausgeschaltet'),
          findsOneWidget,
        );
        expect(find.byType(AppSwitch), findsNWidgets(2));
      },
    );

    testWidgets(
      'the goal steppers move by one step and stop at the limits (C07)',
      (tester) async {
        final env = await pumpOnboarding(tester);
        await goToStep(tester, OnboardingStep.dailyGoals);
        Map<GoalType, int> read() =>
            env.container.read(onboardingControllerProvider).goalTargets;

        await tapStepper(tester, 'Schritte', plus: true);
        expect(find.text('10.500'), findsOneWidget);
        await tapStepper(tester, 'Wasser', plus: false);
        expect(find.text('2,25 l'), findsOneWidget);
        await tapStepper(tester, 'Fokus', plus: true);
        expect(find.text('30 Min.'), findsOneWidget);
        await tapStepper(tester, 'Workouts', plus: true);
        expect(find.text('4 ×'), findsOneWidget);
        expect(read()[GoalType.steps], 10500);
        expect(read()[GoalType.water], 2250);
        expect(read()[GoalType.focusMinutes], 30);
        expect(read()[GoalType.workoutWeekly], 4);

        // Workouts: 1 to 14 per week. The button of an end is disabled.
        await tapStepper(tester, 'Workouts', plus: true, times: 20);
        expect(find.text('14 ×'), findsOneWidget);
        expect(stepperOf(tester, 'Workouts').onIncrease, isNull);
        expect(stepperOf(tester, 'Workouts').onDecrease, isNotNull);
        await tapStepper(tester, 'Workouts', plus: false, times: 20);
        expect(find.text('1 ×'), findsOneWidget);
        expect(stepperOf(tester, 'Workouts').onDecrease, isNull);
        expect(stepperOf(tester, 'Workouts').onIncrease, isNotNull);

        // Focus: 5 to 180 minutes.
        await tapStepper(tester, 'Fokus', plus: false, times: 30);
        expect(find.text('5 Min.'), findsOneWidget);
        expect(stepperOf(tester, 'Fokus').onDecrease, isNull);
        await tapStepper(tester, 'Fokus', plus: true, times: 40);
        expect(find.text('180 Min.'), findsOneWidget);
        expect(stepperOf(tester, 'Fokus').onIncrease, isNull);
      },
    );

    testWidgets('only the goals of the chosen modules are listed', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      await goToStep(tester, OnboardingStep.modules);
      // Drop "Wasser & Ernährung" and "Aufgaben & Gewohnheiten".
      await tester.tap(find.text('Wasser & Ernährung'));
      await tester.pump();
      await tester.tap(find.text('Aufgaben & Gewohnheiten'));
      await tester.pump();
      await tapPrimary(tester);
      await tapPrimary(tester);

      expect(find.text('Schritte'), findsOneWidget);
      expect(find.text('Fokus'), findsOneWidget);
      expect(find.text('Workouts'), findsOneWidget);
      expect(find.text('Gewicht'), findsOneWidget);
      expect(find.text('Wasser'), findsNothing);
      expect(find.text('Aufgaben'), findsNothing);
    });
  });

  group('completion', () {
    testWidgets(
      'saves the choices in one step and leaves for the dashboard (AT01, AT02, C03, C07)',
      (tester) async {
        final env = await pumpOnboarding(tester);
        await goToStep(tester, OnboardingStep.goals);
        await tester.tap(find.text('Mehr bewegen'));
        await tester.tap(find.text('Abnehmen'));
        await tester.pump();
        await tapPrimary(tester);
        await tester.tap(find.text('Gamification'));
        await tester.tap(find.text('Fokus & Workouts'));
        await tester.pump();
        await tapPrimary(tester);
        await typeInto(tester, 'name', '  Testperson ');
        await typeInto(tester, 'age', '30');
        await typeInto(tester, 'height', '170');
        await typeInto(tester, 'weight', '71,5');
        await tapPrimary(tester);
        await tapStepper(tester, 'Schritte', plus: true);
        await tapStepper(tester, 'Wasser', plus: false);
        await tester.tap(find.text('Gewicht'));
        await tester.pump();

        // Nothing is stored before the last button.
        expect((await env.profile(tester)).onboardingCompleted, isFalse);
        await finishAndWaitForExit(tester, env);

        expect(env.exits, <String>['/']);
        expect(env.repository.commandIds, hasLength(1));
        final profile = await env.profile(tester);
        expect(profile.onboardingCompleted, isTrue);
        expect(profile.displayName, 'Testperson');
        expect(profile.ageYears, 30);
        expect(profile.heightCm, 170);
        expect(profile.startWeightGrams, 71500);
        expect(profile.motivationGoals, <String>['lose_weight', 'move_more']);
        final modules = await env.modules(tester);
        expect(modules[ModuleId.focus], isFalse);
        expect(modules[ModuleId.gamification], isFalse);
        expect(modules[ModuleId.body], isTrue);
        expect(modules[ModuleId.nutrition], isTrue);
        expect(modules[ModuleId.tasks], isTrue);
        final goals = await env.goals(tester);
        expect(goals['steps']!.target, 10500);
        expect(goals['water']!.target, 2250);
        expect(goals['focus_minutes']!.target, 25);
        expect(goals['workout_weekly']!.target, 3);
        expect(goals['weight_entry']!.enabled, isFalse);
        expect(goals['task_completion']!.enabled, isTrue);
        // Typed body values are profile data: no measurement was created.
        expect(await env.weightEntryCount(tester), 0);
        // Reminders stay off, no permission flow was started.
        final reminders = await env.reminders(tester);
        expect(reminders.wanted, isFalse);
        expect(reminders.waterHours, isEmpty);
      },
    );

    testWidgets('finishing with empty body fields stores no body data (AT01)', (
      tester,
    ) async {
      final env = await pumpOnboarding(tester);
      await goToStep(tester, OnboardingStep.dailyGoals);
      await finishAndWaitForExit(tester, env);

      final profile = await env.profile(tester);
      expect(profile.onboardingCompleted, isTrue);
      expect(profile.displayName, isNull);
      expect(profile.heightCm, isNull);
      expect(profile.ageYears, isNull);
      expect(profile.startWeightGrams, isNull);
      expect(profile.motivationGoals, isEmpty);
      expect(await env.weightEntryCount(tester), 0);
      final goals = await env.goals(tester);
      expect(goals['water']!.target, 2500);
      expect(goals['steps']!.target, 10000);
      expect(goals['focus_minutes']!.target, 25);
      expect(goals['workout_weekly']!.target, 3);
    });

    testWidgets('no module at all can be saved and is explained (AT04, C03)', (
      tester,
    ) async {
      final env = await pumpOnboarding(tester);
      await goToStep(tester, OnboardingStep.modules);
      final switches = find.byType(AppSwitch);
      for (var i = 0; i < 5; i++) {
        await tester.tap(switches.at(i));
        await tester.pump();
      }
      await tapPrimary(tester);
      await tapPrimary(tester);
      expect(find.text('Deine Tagesziele'), findsOneWidget);
      expect(find.textContaining('Ohne ausgewählte Bereiche'), findsOneWidget);
      expect(find.byType(GoalStepperRow), findsNothing);
      expect(find.byType(AppSwitch), findsNothing);

      await finishAndWaitForExit(tester, env);
      final modules = await env.modules(tester);
      expect(modules.values.every((on) => !on), isTrue);
      expect((await env.profile(tester)).onboardingCompleted, isTrue);
    });

    testWidgets(
      'skipping on the welcome screen needs no confirmation and stores the defaults (AT01, C02)',
      (tester) async {
        final env = await pumpOnboarding(tester);
        await tapAndSettle(tester, find.text('Überspringen'));
        await tester.pumpUntil(() => env.exits.isNotEmpty);
        await tester.pumpAndSettle();

        expect(find.text('Einrichtung überspringen?'), findsNothing);
        final profile = await env.profile(tester);
        expect(profile.onboardingCompleted, isTrue);
        expect(profile.displayName, isNull);
        expect(profile.startWeightGrams, isNull);
        expect(profile.motivationGoals, isEmpty);
        expect((await env.modules(tester)).values.every((on) => on), isTrue);
        expect((await env.goals(tester)).length, GoalType.values.length);
        expect(await env.weightEntryCount(tester), 0);
      },
    );

    testWidgets(
      'skipping with input asks first and then stores the defaults, not the input (C02)',
      (tester) async {
        final env = await pumpOnboarding(tester);
        await goToStep(tester, OnboardingStep.goals);
        await tester.tap(find.text('Abnehmen'));
        await tester.pump();

        await tapAndSettle(tester, find.text('Überspringen'));
        expect(find.text('Einrichtung überspringen?'), findsOneWidget);
        // "Weiter einrichten" keeps everything and saves nothing.
        await tapAndSettle(tester, find.text('Weiter einrichten'));
        expect(find.text('Einrichtung überspringen?'), findsNothing);
        expect(find.text('Was ist dein Ziel?'), findsOneWidget);
        expect(selectedGoalTitles(tester), <String>['Abnehmen']);
        expect((await env.profile(tester)).onboardingCompleted, isFalse);

        await tapAndSettle(tester, find.text('Überspringen'));
        await tapAndSettle(
          tester,
          find.descendant(
            of: find.byType(ConfirmationSheet),
            matching: find.text('Überspringen'),
          ),
        );
        await tester.pumpUntil(() => env.exits.isNotEmpty);
        await tester.pumpAndSettle();

        final profile = await env.profile(tester);
        expect(profile.onboardingCompleted, isTrue);
        expect(profile.motivationGoals, isEmpty, reason: 'input is discarded');
      },
    );

    testWidgets('a double tap on the last button saves exactly once (C05)', (
      tester,
    ) async {
      final env = await pumpOnboarding(tester);
      await goToStep(tester, OnboardingStep.dailyGoals);
      await tester.tap(primaryButton);
      await tester.tap(primaryButton);
      await tester.pump();
      await tester.pumpUntil(() => env.exits.isNotEmpty);
      await tester.pumpAndSettle();
      expect(env.repository.commandIds, hasLength(1));
      expect(env.exits, hasLength(1));
    });
  });

  group('validation and drafts', () {
    testWidgets(
      'invalid body values stay on the step with field errors and keep the input (C05)',
      (tester) async {
        await pumpOnboarding(tester);
        await goToStep(tester, OnboardingStep.body);
        await typeInto(tester, 'age', '17');
        await typeInto(tester, 'height', '251');
        await typeInto(tester, 'weight', '71,55');

        await tapPrimary(tester);

        expect(find.text('Erzähl uns von dir'), findsOneWidget);
        expect(
          find.text('Bitte gib ein Alter zwischen 18 und 120 Jahren ein.'),
          findsOneWidget,
        );
        expect(
          find.text('Bitte gib eine Größe zwischen 100 und 250 cm ein.'),
          findsOneWidget,
        );
        expect(find.byIcon(AppIcon.error.data), findsNWidgets(3));
        expect(typedIn(tester, 'age'), '17');
        expect(typedIn(tester, 'height'), '251');
        expect(typedIn(tester, 'weight'), '71,55');
        // The focus moves to the first field with an error (age).
        expect(
          tester.widget<TextField>(bodyField('age')).focusNode!.hasFocus,
          isTrue,
        );

        // Correcting one field removes just its message.
        await typeInto(tester, 'age', '18');
        expect(find.textContaining('Alter zwischen'), findsNothing);
        expect(find.textContaining('Größe zwischen'), findsOneWidget);
        await typeInto(tester, 'height', '170');
        await typeInto(tester, 'weight', '71,5');
        await tapPrimary(tester);
        expect(find.text('Deine Tagesziele'), findsOneWidget);
      },
    );

    testWidgets(
      'every limit of the body fields is enforced on both sides (C05)',
      (tester) async {
        await pumpOnboarding(tester);
        await goToStep(tester, OnboardingStep.body);

        Future<bool> accepted(String field, String text) async {
          await typeInto(tester, field, text);
          await tapPrimary(tester);
          final moved = find.text('Deine Tagesziele').evaluate().isNotEmpty;
          if (moved) {
            await tapAndSettle(tester, backButton);
          }
          await typeInto(tester, field, '');
          return moved;
        }

        expect(await accepted('height', '99'), isFalse);
        expect(await accepted('height', '100'), isTrue);
        expect(await accepted('height', '250'), isTrue);
        expect(await accepted('height', '251'), isFalse);
        expect(await accepted('age', '17'), isFalse);
        expect(await accepted('age', '18'), isTrue);
        expect(await accepted('age', '120'), isTrue);
        expect(await accepted('age', '121'), isFalse);
        expect(await accepted('weight', '19,9'), isFalse);
        expect(await accepted('weight', '20,0'), isTrue);
        expect(await accepted('weight', '350,0'), isTrue);
        expect(await accepted('weight', '350,1'), isFalse);
        expect(await accepted('weight', '71,55'), isFalse);
      },
    );

    testWidgets(
      'drafts survive going back and forth through every step (C02)',
      (tester) async {
        await pumpOnboarding(tester);
        await goToStep(tester, OnboardingStep.goals);
        await tester.tap(find.text('Gute Gewohnheiten'));
        await tester.pump();
        await tapPrimary(tester);
        await tester.tap(find.text('Gamification'));
        await tester.pump();
        await tapPrimary(tester);
        await typeInto(tester, 'name', 'Testperson');
        await typeInto(tester, 'age', '30');
        await typeInto(tester, 'height', '170');
        await typeInto(tester, 'weight', '71,5');
        await tapPrimary(tester);
        await tapStepper(tester, 'Fokus', plus: true);
        await tester.tap(find.text('Aufgaben'));
        await tester.pump();

        // All the way back to the welcome screen ...
        for (var i = 0; i < 4; i++) {
          await tapAndSettle(tester, backButton);
        }
        expect(find.text('App-Name'), findsOneWidget);
        // ... and forward again: everything is still there.
        await tapPrimary(tester);
        expect(selectedGoalTitles(tester), <String>['Gute Gewohnheiten']);
        await tapPrimary(tester);
        final switches = tester.widgetList<AppSwitch>(find.byType(AppSwitch));
        expect(switches.map((toggle) => toggle.value).toList(), <bool>[
          true,
          true,
          true,
          true,
          false,
        ]);
        await tapPrimary(tester);
        expect(typedIn(tester, 'name'), 'Testperson');
        expect(typedIn(tester, 'age'), '30');
        expect(typedIn(tester, 'height'), '170');
        expect(typedIn(tester, 'weight'), '71,5');
        await tapPrimary(tester);
        expect(find.text('30 Min.'), findsOneWidget);
        expect(
          tester
              .widgetList<AppSwitch>(find.byType(AppSwitch))
              .map((s) => s.value),
          <bool>[false, true],
        );
      },
    );

    testWidgets(
      'leaving the flow without saving starts it fresh next time (C01)',
      (tester) async {
        final env = await pumpOnboarding(tester);
        await goToStep(tester, OnboardingStep.goals);
        await tester.tap(find.text('Abnehmen'));
        await tester.pump();
        await tapPrimary(tester);
        await tapPrimary(tester);
        await typeInto(tester, 'name', 'Testperson');

        // The process dies: the screen goes away, nothing was written.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        final profile = await env.profile(tester);
        expect(profile.onboardingCompleted, isFalse);
        expect(profile.displayName, isNull);
        expect(profile.motivationGoals, isEmpty);
        expect(env.repository.commandIds, isEmpty);

        // The next start (new providers, same database) shows the welcome
        // screen again with empty drafts.
        await pumpApp(
          tester,
          const OnboardingScreen(),
          container: env.harness.createContainer(),
        );
        expect(find.text('App-Name'), findsOneWidget);
        await goToStep(tester, OnboardingStep.goals);
        expect(selectedGoalTitles(tester), isEmpty);
        await tapPrimary(tester);
        await tapPrimary(tester);
        expect(typedIn(tester, 'name'), isEmpty);
      },
    );
  });

  group('Android back (C02)', () {
    testWidgets('goes to the previous step and keeps the drafts', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      await goToStep(tester, OnboardingStep.body);
      await typeInto(tester, 'age', '30');

      await pressSystemBack(tester);
      expect(find.text('Schritt 2 von 4'), findsOneWidget);
      await pressSystemBack(tester);
      expect(find.text('Schritt 1 von 4'), findsOneWidget);
      await pressSystemBack(tester);
      expect(find.text('App-Name'), findsOneWidget);

      await goToStep(tester, OnboardingStep.body);
      expect(typedIn(tester, 'age'), '30');
    });

    testWidgets(
      'on the first screen without input the system takes over and closes the app',
      (tester) async {
        await pumpOnboarding(tester);
        final exits = trackSystemExits(tester);

        await pressSystemBack(tester);

        expect(exits.count, 1, reason: 'Android convention on a root screen');
        expect(find.byType(ConfirmationSheet), findsNothing);
        expect(find.text('App-Name'), findsOneWidget);
      },
    );

    testWidgets(
      'on the first screen with input it asks before the input is lost',
      (tester) async {
        final env = await pumpOnboarding(tester);
        final exits = trackSystemExits(tester);
        await goToStep(tester, OnboardingStep.goals);
        await tester.tap(find.text('Abnehmen'));
        await tester.pump();
        await tapAndSettle(tester, backButton);
        expect(find.text('App-Name'), findsOneWidget);

        await pressSystemBack(tester);
        expect(find.text('Einrichtung abbrechen?'), findsOneWidget);
        expect(exits.count, 0);

        // "Weiter einrichten": stay, nothing lost.
        await tapAndSettle(tester, find.text('Weiter einrichten'));
        expect(find.text('Einrichtung abbrechen?'), findsNothing);
        expect(exits.count, 0);
        expect(
          env.container.read(onboardingControllerProvider).motivationGoals,
          <String>{'lose_weight'},
        );

        // "App schließen": the app closes, nothing was saved.
        await pressSystemBack(tester);
        await tapAndSettle(tester, find.text('App schließen'));
        expect(exits.count, 1);
        expect((await env.profile(tester)).onboardingCompleted, isFalse);
      },
    );

    testWidgets('does nothing while the completion runs', (tester) async {
      final env = await pumpOnboarding(tester);
      await goToStep(tester, OnboardingStep.dailyGoals);
      await tester.tap(primaryButton);
      await tester.pump();
      // The command is running: back must not move the flow.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Deine Tagesziele'), findsOneWidget);
      await tester.pumpUntil(() => env.exits.isNotEmpty);
      await tester.pumpAndSettle();
      expect(env.repository.commandIds, hasLength(1));
    });
  });

  group('errors (C05)', () {
    testWidgets(
      'a database error keeps the flow open with the input, an error and a retry (AT01)',
      (tester) async {
        final projection = RecordingProjectionSynchronizer()
          ..failure = StateError('disk');
        final env = await pumpOnboarding(tester, projection: projection);
        await goToStep(tester, OnboardingStep.goals);
        await tester.tap(find.text('Fitter werden'));
        await tester.pump();
        await tapPrimary(tester);
        await tapPrimary(tester);
        await typeInto(tester, 'name', 'Testperson');
        await tapPrimary(tester);
        await tapStepper(tester, 'Schritte', plus: true);

        await tester.tap(primaryButton);
        await tester.pump();
        await tester.pumpUntil(
          () => find.text('Erneut versuchen').evaluate().isNotEmpty,
          reason: 'the error with its retry appears',
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Die Einrichtung konnte nicht gespeichert werden. Deine Eingaben bleiben erhalten.',
          ),
          findsOneWidget,
        );
        // Still open, nothing committed, input visible.
        expect(env.exits, isEmpty);
        expect(find.text('Deine Tagesziele'), findsOneWidget);
        expect(find.text('10.500'), findsOneWidget);
        final unsaved = await env.profile(tester);
        expect(unsaved.onboardingCompleted, isFalse);
        expect(unsaved.displayName, isNull);
        expect(await env.goals(tester), isEmpty);
        expect(primaryButton, findsOneWidget);
        expect(
          tester.widget<PrimaryButton>(primaryButton).onPressed,
          isNotNull,
        );

        // Going back shows the typed draft, the error vanishes with the edit.
        await tapAndSettle(tester, backButton);
        expect(typedIn(tester, 'name'), 'Testperson');
        await tapPrimary(tester);
        expect(find.text('Erneut versuchen'), findsOneWidget);

        // The problem is gone: retry saves with the same command id.
        projection.failure = null;
        await tester.tap(find.text('Erneut versuchen'));
        await tester.pump();
        await tester.pumpUntil(() => env.exits.isNotEmpty);
        await tester.pumpAndSettle();
        expect(env.repository.commandIds, hasLength(2));
        expect(env.repository.commandIds.first, env.repository.commandIds.last);
        final saved = await env.profile(tester);
        expect(saved.onboardingCompleted, isTrue);
        expect(saved.displayName, 'Testperson');
        expect(saved.motivationGoals, <String>['get_fitter']);
        expect((await env.goals(tester))['steps']!.target, 10500);
      },
    );

    testWidgets('a failed skip shows the error and the retry skips again', (
      tester,
    ) async {
      final env = await pumpOnboarding(tester, failures: 1);
      await tapAndSettle(tester, find.text('Überspringen'));
      await tester.pumpUntil(
        () => find.text('Erneut versuchen').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Die Einrichtung konnte nicht gespeichert werden. Bitte versuche es erneut.',
        ),
        findsOneWidget,
      );
      expect(env.exits, isEmpty);
      expect((await env.profile(tester)).onboardingCompleted, isFalse);

      await tester.tap(find.text('Erneut versuchen'));
      await tester.pump();
      await tester.pumpUntil(() => env.exits.isNotEmpty);
      await tester.pumpAndSettle();
      expect(env.repository.commandIds.first, env.repository.commandIds.last);
      expect((await env.profile(tester)).onboardingCompleted, isTrue);
    });

    testWidgets('a field error of the repository is shown at the goal', (
      tester,
    ) async {
      final env = await pumpOnboarding(
        tester,
        failures: 1,
        error: const ValidationFailure(<String, String>{
          'water': 'Ungültiger Zielwert.',
        }),
      );
      await goToStep(tester, OnboardingStep.dailyGoals);
      await tester.tap(primaryButton);
      await tester.pump();
      await tester.pumpUntil(
        () => find.text('Ungültiger Zielwert.').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(find.text('Deine Tagesziele'), findsOneWidget);
      expect(find.byIcon(AppIcon.error.data), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsNothing);
      expect(env.exits, isEmpty);
    });
  });

  group('restart (AT02, C01)', () {
    testWidgets(
      'the saved state survives a restart and a stale screen changes nothing',
      (tester) async {
        final env = await pumpOnboarding(tester);
        await goToStep(tester, OnboardingStep.goals);
        await tester.tap(find.text('Mehr bewegen'));
        await tester.pump();
        await tapPrimary(tester);
        await tester.tap(find.text('Fokus & Workouts'));
        await tester.pump();
        await tapPrimary(tester);
        await typeInto(tester, 'name', 'Testperson');
        await tapPrimary(tester);
        await tapStepper(tester, 'Wasser', plus: true, times: 2);
        await finishAndWaitForExit(tester, env);

        // "Restart": a new container (fresh providers) over the same database.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        final restarts = <String>[];
        final container = env.harness.createContainer(
          overrides: [
            onboardingExitProvider.overrideWithValue(
              (context) => restarts.add('/'),
            ),
          ],
        );
        // Providers only run while somebody listens (like the app's guards).
        container
          ..listen(profileProvider, (previous, next) {})
          ..listen(moduleStatusesProvider, (previous, next) {});
        final profile = await tester.runAsync(
          () => container.read(profileProvider.future),
        );
        final modules = await tester.runAsync(
          () => container.read(moduleStatusesProvider.future),
        );
        expect(profile!.onboardingCompleted, isTrue);
        expect(profile.displayName, 'Testperson');
        expect(profile.motivationGoals, <String>['move_more']);
        expect(modules![ModuleId.focus], isFalse);
        expect(modules[ModuleId.body], isTrue);
        expect((await env.goals(tester))['water']!.target, 3000);

        // A stale onboarding screen (for example a late deep link) leaves
        // without overwriting the saved choices with defaults.
        await pumpApp(tester, const OnboardingScreen(), container: container);
        await tapAndSettle(tester, find.text('Überspringen'));
        await tester.pumpUntil(() => restarts.isNotEmpty);
        await tester.pumpAndSettle();
        final after = await env.profile(tester);
        expect(after.displayName, 'Testperson');
        expect(after.motivationGoals, <String>['move_more']);
        expect((await env.modules(tester))[ModuleId.focus], isFalse);
        expect((await env.goals(tester))['water']!.target, 3000);
      },
    );
  });

  group('navigation to the dashboard (C01, C02)', () {
    testWidgets(
      'finishing and skipping go to the dashboard route with go_router (AT01)',
      (tester) async {
        final env = await pumpOnboarding(tester, withRouter: true);
        expect(env.router!.state.uri.path, '/onboarding');
        await tapAndSettle(tester, find.text('Überspringen'));
        await tester.pumpUntil(
          () => find.text('Dashboard-Platzhalter').evaluate().isNotEmpty,
          reason: 'the dashboard route is shown',
        );
        await tester.pumpAndSettle();
        expect(env.router!.state.uri.path, '/');
        expect(find.text('Dashboard-Platzhalter'), findsOneWidget);
        expect(find.text('App-Name'), findsNothing);
        expect((await env.profile(tester)).onboardingCompleted, isTrue);
      },
    );

    testWidgets('the last button goes to the dashboard route too', (
      tester,
    ) async {
      final env = await pumpOnboarding(tester, withRouter: true);
      await goToStep(tester, OnboardingStep.dailyGoals);
      await tester.tap(primaryButton);
      await tester.pump();
      await tester.pumpUntil(
        () => find.text('Dashboard-Platzhalter').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(env.router!.state.uri.path, '/');
    });
  });
}
