import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/screen_env.dart';

Finder iconButton(String label) => find.byWidgetPredicate(
  (widget) => widget is AppIconButton && widget.semanticLabel == label,
);

void main() {
  group('a profile without entries', () {
    testWidgets('shows the default name and invents no value (AT02, W02)', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.profile);

      expect(find.text('Mein Profil'), findsOneWidget);
      expect(find.text('Dabei seit Oktober 2026'), findsOneWidget);
      expect(
        find.byIcon(Icons.person_outline_rounded),
        findsOneWidget,
        reason: 'the neutral profile icon instead of initials',
      );
      // No body data, no weight change, no BMI: nothing was entered.
      expect(find.text('Körperdaten'), findsNothing);
      expect(find.text('seit Start'), findsNothing);
      expect(find.textContaining('BMI'), findsNothing);
      expect(find.textContaining('kg'), findsNothing);
      // The target weight honestly says it is not set.
      expect(find.text('Zielgewicht'), findsOneWidget);
      expect(find.text('Nicht gesetzt'), findsOneWidget);
    });

    testWidgets(
      'shows the default goals of the five daily goals and workouts',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.profile);
        for (final text in [
          '2,5 l pro Tag',
          '10.000 pro Tag',
          '25 Min. pro Tag',
          '3× pro Woche',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        expect(find.text('Täglich'), findsNWidgets(2));
        expect(
          find.text('0'),
          findsNWidgets(2),
          reason: 'streak and active days',
        );
      },
    );
  });

  group('a full profile', () {
    testWidgets('shows initials, start date, stats, goals and body data', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await saveProfile(
        tester,
        env,
        name: 'Max Mustermann',
        heightCm: 180,
        ageYears: 22,
        startWeightGrams: 74000,
        targetWeightGrams: 68000,
      );
      await addWeight(tester, env, 71500);
      await openScreen(tester, env, ProfileRoutes.profile);

      expect(find.text('Max Mustermann'), findsOneWidget);
      expect(find.text('MM'), findsOneWidget);
      expect(find.text('−2,5 kg'), findsOneWidget);
      expect(find.text('seit Start'), findsOneWidget);
      expect(find.text('Körperdaten'), findsOneWidget);
      expect(find.text('180 cm'), findsOneWidget);
      expect(find.text('74,0 kg'), findsOneWidget);
      expect(find.text('22 J.'), findsOneWidget);
      expect(find.text('68,0 kg'), findsOneWidget, reason: 'target weight');
      await savePng(tester, 'build/profile_shots/profile.png');
    });

    testWidgets(
      'the weight since the start needs a start weight and a measurement',
      (tester) async {
        final env = await createScreenEnv(tester);
        await saveProfile(tester, env, startWeightGrams: 74000);
        await openScreen(tester, env, ProfileRoutes.profile);
        expect(find.text('seit Start'), findsNothing, reason: 'no measurement');

        await addWeight(tester, env, 75000);
        expect(
          find.text('+1,0 kg'),
          findsOneWidget,
          reason: 'a gain is shown too',
        );
        expect(find.text('seit Start'), findsOneWidget);
      },
    );

    testWidgets(
      'a start weight alone shows the body data but no weight change',
      (tester) async {
        final env = await createScreenEnv(tester);
        await saveProfile(tester, env, startWeightGrams: 74000);
        await openScreen(tester, env, ProfileRoutes.profile);
        expect(find.text('Körperdaten'), findsOneWidget);
        expect(find.text('74,0 kg'), findsOneWidget);
        expect(find.text('180 cm'), findsNothing);
        expect(find.text('Alter'), findsNothing);
      },
    );

    testWidgets(
      'shows the target weight as saved: loss, equal and gain (AT09)',
      (tester) async {
        final env = await createScreenEnv(tester);
        for (final target in [68000, 74000, 80000]) {
          await saveProfile(
            tester,
            env,
            startWeightGrams: 74000,
            targetWeightGrams: target,
          );
          await openScreen(tester, env, ProfileRoutes.profile);
          expect(
            find.text('${target ~/ 1000},0 kg'),
            findsWidgets,
            reason: 'target $target',
          );
          expect(find.text('Nicht gesetzt'), findsNothing);
        }
        await saveProfile(tester, env, startWeightGrams: 74000);
        await openScreen(tester, env, ProfileRoutes.profile);
        expect(
          find.text('Nicht gesetzt'),
          findsOneWidget,
          reason: 'missing target',
        );
      },
    );

    testWidgets('follows changes of the stored profile live', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.profile);
      expect(find.text('Mein Profil'), findsOneWidget);
      await saveProfile(tester, env, name: 'Mia Muster');
      expect(find.text('Mia Muster'), findsOneWidget);
      expect(find.text('MM'), findsOneWidget);
    });

    testWidgets(
      'shows a goal change that starts tomorrow, today stays (AT24)',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.profile);
        await tester.runCommand(
          () => env.container
              .read(goalsCommandsProvider)
              .update(
                commandId: 'g1',
                changes: const {GoalType.water: GoalSetting(target: 3000)},
              ),
        );
        expect(find.text('2,5 l pro Tag'), findsOneWidget, reason: 'today');
        expect(find.text('Ab morgen: 3 l pro Tag'), findsOneWidget);
      },
    );
  });

  group('modules', () {
    testWidgets(
      'gamification off hides streak, active days and the progress link',
      (tester) async {
        final env = await createScreenEnv(
          tester,
          enabledModules: {'body', 'nutrition', 'focus', 'tasks'},
        );
        await openScreen(tester, env, ProfileRoutes.profile);
        expect(find.text('Fortschritt'), findsNothing);
        expect(find.text('Tage Streak'), findsNothing);
        expect(find.text('Aktive Tage'), findsNothing);
        expect(find.text('Meine Ziele'), findsOneWidget, reason: 'goals stay');
      },
    );

    testWidgets('switched-off modules take their goals away', (tester) async {
      final env = await createScreenEnv(
        tester,
        enabledModules: {'tasks', 'gamification'},
      );
      await saveProfile(
        tester,
        env,
        startWeightGrams: 74000,
        targetWeightGrams: 68000,
      );
      await openScreen(tester, env, ProfileRoutes.profile);
      expect(find.text('Wasser'), findsNothing);
      expect(find.text('Schritte'), findsNothing);
      expect(find.text('Fokus'), findsNothing);
      expect(find.text('Workouts'), findsNothing);
      expect(find.text('Zielgewicht'), findsNothing, reason: 'body is off');
      expect(find.text('Körperdaten'), findsNothing);
      expect(find.text('Aufgabe erledigen'), findsOneWidget);
    });

    testWidgets('all modules off gives an understandable empty state', (
      tester,
    ) async {
      final env = await createScreenEnv(tester, enabledModules: <String>{});
      final router = await openScreen(tester, env, ProfileRoutes.profile);
      expect(find.text('Keine Ziele sichtbar'), findsOneWidget);
      await tester.tap(find.text('Module verwalten'));
      await settle(tester);
      expect(find.text('Seite ${SettingsRoutes.modules}'), findsOneWidget);
      expect(router.canPop(), isTrue);
    });
  });

  group('gamification switched off and on again (AT26)', () {
    testWidgets(
      'hides streak and XP, never pays out the time off, keeps old XP',
      (tester) async {
        final env = await createScreenEnv(
          tester,
          realProjection: true,
          startedOn: LocalDate(2026, 9, 1),
        );
        await openScreen(tester, env, ProfileRoutes.profile);
        expect(find.text('Level 1 · 0 XP'), findsOneWidget);

        await addWeight(tester, env, 71500, at: DateTime.utc(2026, 10, 3, 6));
        expect(find.text('Level 1 · 10 XP'), findsOneWidget);

        await tester.runCommand(
          () => env.container
              .read(moduleManagerProvider)
              .setEnabled(
                commandId: 'off',
                module: ModuleId.gamification,
                enabled: false,
              ),
        );
        expect(find.text('Fortschritt'), findsNothing);
        expect(find.text('Tage Streak'), findsNothing);
        expect(find.text('Meine Ziele'), findsOneWidget, reason: 'goals stay');

        // An activity while it is off earns nothing, not even later.
        await addWeight(tester, env, 71000, at: DateTime.utc(2026, 10, 2, 6));
        await tester.runCommand(
          () => env.container
              .read(moduleManagerProvider)
              .setEnabled(
                commandId: 'on',
                module: ModuleId.gamification,
                enabled: true,
              ),
        );
        expect(find.text('Fortschritt'), findsOneWidget);
        expect(
          find.text('Level 1 · 10 XP'),
          findsOneWidget,
          reason: 'no payout',
        );

        // A new activity after switching it on counts as usual.
        await addWeight(tester, env, 70500, at: DateTime.utc(2026, 10, 1, 6));
        expect(find.text('Level 1 · 20 XP'), findsOneWidget);
      },
    );
  });

  group('links', () {
    testWidgets('edit button opens the profile editor', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.profile);
      await tester.tap(iconButton('Profil bearbeiten'));
      await settle(tester);
      expect(find.text('Profil bearbeiten'), findsOneWidget);
      expect(find.text('Profil speichern'), findsOneWidget);
    });

    testWidgets(
      'settings button, goals link and goal rows lead to their screens',
      (tester) async {
        final env = await createScreenEnv(tester);
        final router = await openScreen(tester, env, ProfileRoutes.profile);

        await tester.tap(iconButton('Einstellungen'));
        await settle(tester);
        expect(find.text('Einstellungen'), findsOneWidget);
        router.pop();
        await settle(tester);

        await tester.tap(find.text('Bearbeiten'));
        await settle(tester);
        expect(find.text('Ziele speichern'), findsOneWidget);
        router.pop();
        await settle(tester);

        await tester.tap(find.text('Wasser'));
        await settle(tester);
        expect(find.text('Ziele speichern'), findsOneWidget);
      },
    );

    testWidgets('the streak and the progress entry are links', (tester) async {
      final env = await createScreenEnv(tester);
      final router = await openScreen(tester, env, ProfileRoutes.profile);
      await tester.tap(find.text('Tage Streak'));
      await settle(tester);
      expect(find.text('Seite ${ProfileRoutes.streak}'), findsOneWidget);
      router.pop();
      await settle(tester);
      await tester.tap(find.text('Fortschritt'));
      await settle(tester);
      expect(find.text('Seite ${ProfileRoutes.progress}'), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('a load error offers a retry that reads the data again', (
      tester,
    ) async {
      var reads = 0;
      final env = await createScreenEnv(
        tester,
        overrides: [
          profileProvider.overrideWith((ref) {
            reads++;
            if (reads == 1) {
              return Stream<UserProfile?>.error(StateError('boom'));
            }
            return ref.watch(profileRepositoryProvider).watch();
          }),
        ],
      );
      await openScreen(tester, env, ProfileRoutes.profile);
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      expect(find.text('Meine Ziele'), findsNothing);

      await tester.tap(find.text('Erneut versuchen'));
      await settle(tester);
      expect(find.text('Meine Ziele'), findsOneWidget);
      expect(find.text('Daten konnten nicht geladen werden'), findsNothing);
    });
  });

  testWidgets('every control has a spoken German label', (tester) async {
    final handle = tester.ensureSemantics();
    final env = await createScreenEnv(tester);
    await saveProfile(tester, env, name: 'Max Mustermann');
    await openScreen(tester, env, ProfileRoutes.profile);

    expect(find.bySemanticsLabel('Einstellungen'), findsOneWidget);
    expect(find.bySemanticsLabel('Profil bearbeiten'), findsOneWidget);
    expect(find.bySemanticsLabel('Ziele bearbeiten'), findsOneWidget);
    expect(
      find.bySemanticsLabel('0 Tage Streak, Details ansehen'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('0 aktive Tage'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Wasser, 2,5 l pro Tag, bearbeiten'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Zielgewicht, Nicht gesetzt, bearbeiten'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
