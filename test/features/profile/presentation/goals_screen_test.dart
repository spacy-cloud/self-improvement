import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/screen_env.dart';

Finder iconButton(String label) => find.byWidgetPredicate(
  (widget) => widget is AppIconButton && widget.semanticLabel == label,
);

/// The Semantics node with the given label (steppers, value fields).
Finder labelled(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Finder valueField(String label) =>
    find.descendant(of: labelled(label), matching: find.byType(TextField));

String textOf(WidgetTester tester, String label) =>
    tester.widget<TextField>(valueField(label)).controller!.text;

Finder get saveButton => find.widgetWithText(PrimaryButton, 'Ziele speichern');

Future<void> save(WidgetTester tester) async {
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await settle(tester);
}

Future<void> tapStep(WidgetTester tester, String label) async {
  await tester.ensureVisible(labelled(label));
  await tester.tap(labelled(label));
  await tester.pump();
}

Future<List<GoalVersion>> versionsOf(WidgetTester tester, ScreenEnv env) async {
  final all = await tester.runAsync(
    () => GoalVersionRepository(env.harness.database).all(),
  );
  return all!;
}

GoalVersion? versionFor(List<GoalVersion> all, GoalType type, LocalDate day) {
  final matches = all.where((v) => v.type == type && v.effectiveFrom == day);
  return matches.isEmpty ? null : matches.single;
}

final tomorrow = LocalDate(2026, 10, 4);

void main() {
  group('opening', () {
    testWidgets(
      'says that goals apply from tomorrow and what applies at once',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.goals);

        expect(
          find.text(
            'Änderungen an Tageszielen und am Wochenziel gelten ab morgen '
            '(So., 4. Okt.), damit dein heutiger Fortschritt fair bleibt.',
          ),
          findsOneWidget,
        );
        expect(find.text('TAGESZIELE · AB MORGEN'), findsOneWidget);
        expect(find.text('WOCHENZIEL · AB MORGEN'), findsOneWidget);
        expect(find.text('KÖRPERZIEL · GILT SOFORT'), findsOneWidget);
        expect(
          find.text('Jede aktive Gewohnheit zählt automatisch als Tagesziel.'),
          findsOneWidget,
        );
        expect(textOf(tester, 'Wasserziel in Millilitern'), '2500');
        expect(textOf(tester, 'Schrittziel pro Tag'), '10000');
        expect(textOf(tester, 'Fokusziel in Minuten'), '25');
        expect(textOf(tester, 'Workout-Wochenziel'), '3');
        expect(
          textOf(tester, 'Zielgewicht in Kilogramm, nicht gesetzt'),
          isEmpty,
        );
        expect(find.text('Gewicht erfassen'), findsOneWidget);
        expect(find.text('Aufgabe erledigen'), findsOneWidget);
        expect(
          tester.widget<PrimaryButton>(saveButton).onPressed,
          isNull,
          reason: 'nothing changed yet',
        );
        await savePng(tester, 'build/profile_shots/goals.png');
      },
    );

    testWidgets(
      'a change saved earlier today is shown with what applies today',
      (tester) async {
        final env = await createScreenEnv(tester);
        await tester.runCommand(
          () => env.container
              .read(goalsCommandsProvider)
              .update(
                commandId: 'seed',
                changes: const {GoalType.water: GoalSetting(target: 3000)},
              ),
        );
        await openScreen(tester, env, ProfileRoutes.goals);
        expect(textOf(tester, 'Wasserziel in Millilitern'), '3000');
        expect(find.text('Heute noch: 2,5 l pro Tag'), findsOneWidget);
      },
    );

    testWidgets('goals of switched-off modules are hidden with a note', (
      tester,
    ) async {
      final env = await createScreenEnv(
        tester,
        enabledModules: {'body', 'tasks', 'gamification'},
      );
      await openScreen(tester, env, ProfileRoutes.goals);
      expect(find.text('Wasser'), findsNothing);
      expect(find.text('Fokus'), findsNothing);
      expect(find.text('WOCHENZIEL · AB MORGEN'), findsNothing);
      expect(find.text('Schritte'), findsOneWidget);
      expect(
        find.text(
          'Ziele von ausgeschalteten Modulen sind ausgeblendet und bleiben gespeichert.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('without the body module there is no target weight', (
      tester,
    ) async {
      final env = await createScreenEnv(tester, enabledModules: {'tasks'});
      await openScreen(tester, env, ProfileRoutes.goals);
      expect(find.text('KÖRPERZIEL · GILT SOFORT'), findsNothing);
      expect(find.text('Zielgewicht'), findsNothing);
    });
  });

  group('goal values apply from tomorrow (C07, AT24)', () {
    testWidgets(
      'plus changes the value; saving says "ab morgen" and keeps today',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.goals);
        await tapStep(tester, 'Wasser um 250 Milliliter erhöhen');
        expect(textOf(tester, 'Wasserziel in Millilitern'), '2750');
        expect(tester.widget<PrimaryButton>(saveButton).onPressed, isNotNull);
        expect(env.feedback.events, isEmpty);

        await save(tester);

        expect(env.feedback.last!.kind, 'saved');
        expect(
          env.feedback.last!.message,
          'Ziele gespeichert. Sie gelten ab morgen.',
        );
        expect(
          find.text('Seite /'),
          findsOneWidget,
          reason: 'the editor closed',
        );
        final all = await versionsOf(tester, env);
        expect(versionFor(all, GoalType.water, tomorrow)!.target, 2750);
        expect(
          versionFor(all, GoalType.water, LocalDate(2026, 10, 3))!.target,
          2500,
          reason: "today's version is untouched",
        );

        // The profile shows today's value and the change that starts tomorrow.
        await openScreen(tester, env, ProfileRoutes.profile);
        expect(find.text('2,5 l pro Tag'), findsOneWidget);
        expect(find.text('Ab morgen: 2,75 l pro Tag'), findsOneWidget);
      },
    );

    testWidgets('a typed value is saved like a stepped one', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.goals);
      await tester.enterText(valueField('Schrittziel pro Tag'), '12000');
      await tester.enterText(valueField('Fokusziel in Minuten'), '45');
      await tester.pump();
      await save(tester);
      final all = await versionsOf(tester, env);
      expect(versionFor(all, GoalType.steps, tomorrow)!.target, 12000);
      expect(versionFor(all, GoalType.focusMinutes, tomorrow)!.target, 45);
      expect(
        versionFor(all, GoalType.water, tomorrow),
        isNull,
        reason: 'unchanged',
      );
    });

    testWidgets(
      'switching a goal off removes its value field and keeps the value',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.goals);
        final stepsSwitch = find.byWidgetPredicate(
          (w) => w is AppSwitch && w.semanticLabel == 'Schritte-Ziel',
        );
        await tester.ensureVisible(stepsSwitch);
        await tester.tap(stepsSwitch);
        await tester.pump();
        expect(valueField('Schrittziel pro Tag'), findsNothing);
        expect(
          find.text('Ausgeschaltet: zählt nicht für den Tagesring.'),
          findsOneWidget,
          reason: 'the state is told in words, not only by the switch',
        );
        await save(tester);

        final all = await versionsOf(tester, env);
        final version = versionFor(all, GoalType.steps, tomorrow)!;
        expect(version.enabled, isFalse);
        expect(version.target, 10000);

        // Reopened: off from tomorrow, today still counts; switching it on again
        // brings the old value back.
        await openScreen(tester, env, ProfileRoutes.goals);
        expect(valueField('Schrittziel pro Tag'), findsNothing);
        expect(find.text('Heute noch: 10.000 pro Tag'), findsOneWidget);
        await tester.ensureVisible(stepsSwitch);
        await tester.tap(stepsSwitch);
        await tester.pump();
        expect(textOf(tester, 'Schrittziel pro Tag'), '10000');
      },
    );

    testWidgets('weight entry and task goals are plain switches', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.goals);
      await tester.ensureVisible(find.text('Gewicht erfassen'));
      await tester.tap(find.text('Gewicht erfassen'));
      await tester.pump();
      await save(tester);
      final all = await versionsOf(tester, env);
      expect(versionFor(all, GoalType.weightEntry, tomorrow)!.enabled, isFalse);
      expect(versionFor(all, GoalType.taskCompletion, tomorrow), isNull);
    });

    testWidgets('the workout goal stays inside 1 to 14 (plus and minus stop)', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.goals);
      bool enabled(String label) =>
          tester.widget<Semantics>(labelled(label)).properties.enabled ?? true;

      await tester.enterText(valueField('Workout-Wochenziel'), '14');
      await tester.pump();
      expect(enabled('Workouts um 1 erhöhen'), isFalse);
      expect(enabled('Workouts um 1 verringern'), isTrue);

      await tester.enterText(valueField('Workout-Wochenziel'), '1');
      await tester.pump();
      expect(enabled('Workouts um 1 verringern'), isFalse);
      expect(enabled('Workouts um 1 erhöhen'), isTrue);
    });
  });

  group('validation', () {
    testWidgets(
      'an invalid value shows its hint, keeps the input, saves nothing',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.goals);
        await tester.enterText(valueField('Wasserziel in Millilitern'), '260');
        await tester.enterText(valueField('Schrittziel pro Tag'), '12000');
        await tester.pump();
        await save(tester);

        expect(
          find.text(
            'Bitte gib die Menge in 50-ml-Schritten an, zum Beispiel 2500.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Bitte prüfe die markierten Angaben.'),
          findsOneWidget,
        );
        expect(textOf(tester, 'Wasserziel in Millilitern'), '260');
        expect(textOf(tester, 'Schrittziel pro Tag'), '12000');
        expect(env.feedback.events, isEmpty);
        expect(env.goalsCommands.commandIds, isEmpty);
        expect(
          tester
              .widget<TextField>(valueField('Wasserziel in Millilitern'))
              .focusNode!
              .hasFocus,
          isTrue,
          reason: 'the first invalid field gets the focus',
        );

        await tester.enterText(valueField('Wasserziel in Millilitern'), '3000');
        await tester.pump();
        expect(find.textContaining('50-ml-Schritten'), findsNothing);
        await save(tester);
        expect(env.feedback.last!.kind, 'saved');
      },
    );

    testWidgets('each goal names its own range', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.goals);
      await tester.enterText(valueField('Schrittziel pro Tag'), '99');
      await tester.enterText(valueField('Fokusziel in Minuten'), '181');
      await tester.enterText(valueField('Workout-Wochenziel'), '15');
      await tester.pump();
      await save(tester);
      expect(
        find.text('Bitte gib eine Schrittzahl zwischen 100 und 100.000 ein.'),
        findsOneWidget,
      );
      expect(
        find.text('Bitte gib eine Dauer zwischen 5 und 180 Minuten ein.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Bitte gib eine Anzahl zwischen 1 und 14 Workouts pro Woche ein.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the target weight hint names the decimals and the range', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.goals);
      await tester.enterText(
        valueField('Zielgewicht in Kilogramm, nicht gesetzt'),
        '19,9',
      );
      await tester.pump();
      await save(tester);
      expect(
        find.text('Bitte gib ein Gewicht zwischen 20,0 und 350,0 kg ein.'),
        findsOneWidget,
      );
      expect(
        (await tester.runAsync(
          () => env.container.read(profileRepositoryProvider).get(),
        ))!.targetWeightGrams,
        isNull,
      );
    });
  });

  group('target weight (immediate)', () {
    testWidgets('is saved at once and the message says so', (tester) async {
      final env = await createScreenEnv(tester);
      await saveProfile(tester, env, startWeightGrams: 74000);
      await openScreen(tester, env, ProfileRoutes.goals);
      expect(find.text('Startgewicht 74,0 kg'), findsOneWidget);

      await tester.enterText(
        valueField('Zielgewicht in Kilogramm, nicht gesetzt'),
        '68,0',
      );
      await tester.pump();
      await save(tester);

      expect(
        env.feedback.last!.message,
        'Zielgewicht gespeichert. Es gilt sofort.',
      );
      final profile = (await tester.runAsync(
        () => env.container.read(profileRepositoryProvider).get(),
      ))!;
      expect(profile.targetWeightGrams, 68000);
      expect(profile.startWeightGrams, 74000, reason: 'other values stay');
      final all = await versionsOf(tester, env);
      expect(all.where((v) => v.effectiveFrom == tomorrow), isEmpty);
    });

    testWidgets('plus and minus step 0,1 kg from the start weight', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await saveProfile(tester, env, startWeightGrams: 74000);
      await openScreen(tester, env, ProfileRoutes.goals);
      await tapStep(tester, 'Zielgewicht um 0,1 Kilogramm verringern');
      expect(textOf(tester, 'Zielgewicht in Kilogramm'), '73,9');
    });

    testWidgets('plus and minus wait for a value when nothing is known', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.goals);
      final minus = tester.widget<Semantics>(
        labelled('Zielgewicht um 0,1 Kilogramm verringern'),
      );
      expect(minus.properties.enabled, isFalse);
    });

    testWidgets(
      'the last measurement is proposed as start weight and needs a tap',
      (tester) async {
        final env = await createScreenEnv(tester);
        await addWeight(tester, env, 71500);
        await openScreen(tester, env, ProfileRoutes.goals);
        expect(find.text('Als Startgewicht übernehmen'), findsNothing);

        await tester.enterText(
          valueField('Zielgewicht in Kilogramm, nicht gesetzt'),
          '68,0',
        );
        await tester.pump();
        expect(
          find.text(
            'Deine letzte Messung ist 71,5 kg. Möchtest du sie als Startgewicht übernehmen?',
          ),
          findsOneWidget,
        );

        await tester.ensureVisible(find.text('Als Startgewicht übernehmen'));
        await tester.tap(find.text('Als Startgewicht übernehmen'));
        await tester.pump();
        expect(
          find.text(
            'Startgewicht 71,5 kg wird mit dem Zielgewicht gespeichert.',
          ),
          findsOneWidget,
        );
        await save(tester);

        final profile = (await tester.runAsync(
          () => env.container.read(profileRepositoryProvider).get(),
        ))!;
        expect(profile.startWeightGrams, 71500);
        expect(profile.targetWeightGrams, 68000);
        final entries = (await tester.runAsync(
          () =>
              env.container.read(weightRepositoryProvider).watchActive().first,
        ))!;
        expect(
          entries,
          hasLength(1),
          reason: 'no measurement was added or changed',
        );
        expect(entries.single.weightGrams, 71500);
      },
    );

    testWidgets('goals and target weight together say when each applies', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.goals);
      await tapStep(tester, 'Wasser um 250 Milliliter erhöhen');
      await tester.enterText(
        valueField('Zielgewicht in Kilogramm, nicht gesetzt'),
        '70,5',
      );
      await tester.pump();
      await save(tester);
      expect(
        env.feedback.last!.message,
        'Ziele gespeichert. Tagesziele gelten ab morgen, das Zielgewicht sofort.',
      );
    });
  });

  group('cancelling', () {
    testWidgets('leaving without a change does not ask', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.goals);
      await tester.tap(iconButton('Zurück'));
      await settle(tester);
      expect(find.text('Änderungen verwerfen?'), findsNothing);
      expect(find.text('Seite /'), findsOneWidget);
    });

    testWidgets('leaving with a change asks, "Verwerfen" saves nothing', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.goals);
      await tapStep(tester, 'Wasser um 250 Milliliter erhöhen');
      await tester.tap(iconButton('Zurück'));
      await settle(tester);
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);

      await tester.tap(find.text('Weiter bearbeiten'));
      await settle(tester);
      expect(textOf(tester, 'Wasserziel in Millilitern'), '2750');

      await tester.binding.handlePopRoute(); // Android back asks again
      await settle(tester);
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await tester.tap(find.text('Verwerfen'));
      await settle(tester);
      expect(find.text('Seite /'), findsOneWidget);
      expect(env.goalsCommands.commandIds, isEmpty);
      final all = await versionsOf(tester, env);
      expect(versionFor(all, GoalType.water, tomorrow), isNull);
    });
  });

  group('while the editor is open', () {
    testWidgets('data that changes elsewhere never resets the typed input', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.goals);
      await tester.enterText(valueField('Wasserziel in Millilitern'), '3000');
      await tester.pump();
      await saveProfile(tester, env, name: 'Mia');
      await tester.runCommand(
        () => env.container
            .read(goalsCommandsProvider)
            .update(
              commandId: 'elsewhere',
              changes: const {GoalType.steps: GoalSetting(target: 12000)},
            ),
      );
      expect(textOf(tester, 'Wasserziel in Millilitern'), '3000');
      expect(
        textOf(tester, 'Schrittziel pro Tag'),
        '10000',
        reason: 'form stays as opened',
      );
    });
  });

  group('failures', () {
    testWidgets(
      'a failed save keeps the input; the retry saves once with the same id',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.goals);
        await tapStep(tester, 'Wasser um 250 Milliliter erhöhen');
        env.projection.failure = StateError('disk full');
        await save(tester);

        expect(env.feedback.last!.kind, 'error');
        expect(
          env.feedback.last!.message,
          'Speichern fehlgeschlagen. Deine Eingaben bleiben erhalten.',
        );
        expect(textOf(tester, 'Wasserziel in Millilitern'), '2750');
        expect(
          find.text('Ziele speichern'),
          findsOneWidget,
          reason: 'still open',
        );
        expect(
          versionFor(await versionsOf(tester, env), GoalType.water, tomorrow),
          isNull,
        );

        env.projection.failure = null;
        env.feedback.last!.onRetry!();
        await settle(tester);
        expect(env.feedback.last!.kind, 'saved');
        expect(env.goalsCommands.commandIds, hasLength(2));
        expect(
          env.goalsCommands.commandIds[0],
          env.goalsCommands.commandIds[1],
        );
        expect(
          versionFor(
            await versionsOf(tester, env),
            GoalType.water,
            tomorrow,
          )!.target,
          2750,
        );
      },
    );

    testWidgets('goals saved but the target weight failed says exactly that', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.goals);
      await tapStep(tester, 'Wasser um 250 Milliliter erhöhen');
      await tester.enterText(
        valueField('Zielgewicht in Kilogramm, nicht gesetzt'),
        '68,0',
      );
      await tester.pump();
      env.profileCommands.failure = const StorageFailure(
        causeType: 'StateError',
      );
      await save(tester);

      expect(
        env.feedback.last!.message,
        'Die Tagesziele sind gespeichert, das Zielgewicht nicht. Deine Eingaben bleiben erhalten.',
      );
      expect(textOf(tester, 'Zielgewicht in Kilogramm'), '68,0');
      expect(
        versionFor(
          await versionsOf(tester, env),
          GoalType.water,
          tomorrow,
        )!.target,
        2750,
      );

      env.profileCommands.failure = null;
      env.feedback.last!.onRetry!();
      await settle(tester);
      expect(env.feedback.last!.kind, 'saved');
      expect(
        env.goalsCommands.commandIds,
        hasLength(1),
        reason: 'goals are not sent twice',
      );
    });

    testWidgets('a double tap on save sends one command', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.goals);
      await tapStep(tester, 'Wasser um 250 Milliliter erhöhen');
      await tester.tap(saveButton);
      await tester.tap(saveButton);
      await settle(tester);
      expect(env.goalsCommands.commandIds, hasLength(1));
    });
  });

  testWidgets('every control has a spoken German label', (tester) async {
    final handle = tester.ensureSemantics();
    final env = await createScreenEnv(tester);
    await openScreen(tester, env, ProfileRoutes.goals);
    expect(find.bySemanticsLabel('Zurück'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Wasser um 250 Milliliter verringern'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Wasser um 250 Milliliter erhöhen'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Schritte um 500 erhöhen'), findsOneWidget);
    expect(find.bySemanticsLabel('Fokus um 5 Minuten erhöhen'), findsOneWidget);
    expect(find.bySemanticsLabel('Wasser-Ziel'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Gewicht erfassen, mindestens ein Eintrag pro Tag'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
