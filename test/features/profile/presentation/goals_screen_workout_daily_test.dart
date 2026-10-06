import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../core/design/support/contrast.dart';
import '../../../support/pump_app.dart';
import '../support/screen_env.dart';

/// The optional daily goal "Workout heute" in the goal editor and on the
/// profile page (BS-99, Figma `4117:249` off and `4117:361` on): a switch
/// between "Gewicht erfassen" and "Aufgabe erledigen", off until it is switched
/// on, valid from tomorrow like every goal.
void main() {
  final tomorrow = LocalDate(2026, 10, 4);

  const habitNote = 'Jede aktive Gewohnheit zählt automatisch als Tagesziel.';
  const dailyNote =
      'Ruhetag und Überspringen erfüllen das Workout-Ziel, geben aber keine '
      'XP. Die Streak bleibt.';

  final saveButton = find.widgetWithText(PrimaryButton, 'Ziele speichern');

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await settle(tester);
  }

  Future<List<GoalVersion>> versionsOf(
    WidgetTester tester,
    ScreenEnv env,
  ) async {
    final all = await tester.runAsync(
      () => GoalVersionRepository(env.harness.database).all(),
    );
    return all!;
  }

  GoalVersion? dailyVersion(List<GoalVersion> all, LocalDate day) {
    final matches = all.where(
      (v) => v.type == GoalType.workoutDaily && v.effectiveFrom == day,
    );
    return matches.isEmpty ? null : matches.single;
  }

  AppSwitch dailySwitch(WidgetTester tester) => tester.widget<AppSwitch>(
    find.byWidgetPredicate(
      (w) => w is AppSwitch && w.semanticLabel == 'Workout heute',
    ),
  );

  Future<void> toggleDaily(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Workout heute'));
    await tester.tap(find.text('Workout heute'));
    await tester.pump();
  }

  group('opening', () {
    testWidgets(
      '(BS-99) sits between "Gewicht erfassen" and "Aufgabe erledigen" with its caption, switched off',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.goals);

        expect(find.text('Workout heute'), findsOneWidget);
        expect(
          find.text('Training, Ruhetag oder übersprungen zählt'),
          findsOneWidget,
        );
        expect(dailySwitch(tester).value, isFalse, reason: 'off by default');

        final weight = tester.getTopLeft(find.text('Gewicht erfassen')).dy;
        final daily = tester.getTopLeft(find.text('Workout heute')).dy;
        final task = tester.getTopLeft(find.text('Aufgabe erledigen')).dy;
        expect(weight, lessThan(daily));
        expect(daily, lessThan(task));

        // The weekly goal stays where it was, separate from the daily goals.
        expect(find.text('WOCHENZIEL · AB MORGEN'), findsOneWidget);
        expect(find.text('Workouts'), findsOneWidget);
        expect(
          tester.widget<PrimaryButton>(saveButton).onPressed,
          isNull,
          reason: 'nothing changed yet',
        );
      },
    );

    testWidgets('(BS-99) while it is off only the note about habits is shown', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.goals);
      expect(find.text(habitNote), findsOneWidget);
      expect(find.textContaining('Ruhetag und Überspringen'), findsNothing);
    });

    testWidgets(
      '(BS-99) a goal that is on shows the note about rest days and skipped days',
      (tester) async {
        final env = await createScreenEnv(tester, workoutDailyGoal: true);
        await openScreen(tester, env, ProfileRoutes.goals);
        expect(dailySwitch(tester).value, isTrue);
        expect(find.text('$habitNote $dailyNote'), findsOneWidget);
      },
    );

    testWidgets(
      '(BS-99) with the focus module off the row and its note are hidden, the goal stays stored',
      (tester) async {
        final env = await createScreenEnv(
          tester,
          enabledModules: {'body', 'nutrition', 'tasks', 'gamification'},
          workoutDailyGoal: true,
        );
        await openScreen(tester, env, ProfileRoutes.goals);
        expect(find.text('Workout heute'), findsNothing);
        expect(find.textContaining('Ruhetag und Überspringen'), findsNothing);
        expect(find.text(habitNote), findsOneWidget);
        expect(
          find.text(
            'Ziele von ausgeschalteten Modulen sind ausgeblendet und bleiben '
            'gespeichert.',
          ),
          findsOneWidget,
        );
        final all = await versionsOf(tester, env);
        expect(
          dailyVersion(all, LocalDate(2026, 10, 3)),
          isNotNull,
          reason: 'still stored',
        );
      },
    );
  });

  group('switching it', () {
    testWidgets(
      '(BS-99, AT24) on shows the note and saves a version for tomorrow; today keeps its snapshot',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.goals);

        await toggleDaily(tester);
        expect(dailySwitch(tester).value, isTrue);
        expect(find.text('$habitNote $dailyNote'), findsOneWidget);
        expect(tester.widget<PrimaryButton>(saveButton).onPressed, isNotNull);

        await save(tester);
        final all = await versionsOf(tester, env);
        final version = dailyVersion(all, tomorrow)!;
        expect(version.enabled, isTrue);
        expect(version.target, 1);
        expect(
          all.where((v) => v.type == GoalType.workoutDaily),
          hasLength(1),
          reason: 'only the version for tomorrow',
        );
        expect(
          env.feedback.last!.message,
          'Ziele gespeichert. Sie gelten ab morgen.',
        );
        expect(env.goalsCommands.commandIds, hasLength(1));
      },
    );

    testWidgets('(BS-99) on and off again is no change: nothing to save', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.goals);
      await toggleDaily(tester);
      await toggleDaily(tester);
      expect(dailySwitch(tester).value, isFalse);
      expect(tester.widget<PrimaryButton>(saveButton).onPressed, isNull);
      expect(find.textContaining('Ruhetag und Überspringen'), findsNothing);
    });

    testWidgets(
      '(BS-99, AT24) off saves a version for tomorrow; reopening says what still applies today',
      (tester) async {
        final env = await createScreenEnv(tester, workoutDailyGoal: true);
        await openScreen(tester, env, ProfileRoutes.goals);
        await toggleDaily(tester);
        expect(find.textContaining('Ruhetag und Überspringen'), findsNothing);
        await save(tester);

        final all = await versionsOf(tester, env);
        expect(dailyVersion(all, tomorrow)!.enabled, isFalse);
        expect(
          dailyVersion(all, LocalDate(2026, 10, 3))!.enabled,
          isTrue,
          reason: 'today is not rewritten',
        );

        await openScreen(tester, env, ProfileRoutes.goals);
        expect(dailySwitch(tester).value, isFalse);
        expect(
          find.text(
            'Training, Ruhetag oder übersprungen zählt · Heute noch: Täglich',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '(BS-99) a failed save keeps the switch and the note, the retry reuses the command',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.goals);
        await toggleDaily(tester);
        env.projection.failure = StateError('disk full');
        await save(tester);
        expect(dailySwitch(tester).value, isTrue);
        expect(find.text('$habitNote $dailyNote'), findsOneWidget);
        expect(env.feedback.last!.kind, 'error');
        expect(
          env.feedback.last!.message,
          'Speichern fehlgeschlagen. Deine Eingaben bleiben erhalten.',
        );
        expect(dailyVersion(await versionsOf(tester, env), tomorrow), isNull);

        env.projection.failure = null;
        env.feedback.last!.onRetry!();
        await settle(tester);
        expect(env.feedback.last!.kind, 'saved');
        expect(env.goalsCommands.commandIds, hasLength(2));
        expect(
          env.goalsCommands.commandIds.first,
          env.goalsCommands.commandIds.last,
          reason: 'the same content, the same command id',
        );
        final all = await versionsOf(tester, env);
        expect(dailyVersion(all, tomorrow)!.enabled, isTrue);
      },
    );
  });

  group('profile page', () {
    testWidgets(
      '(BS-99) "Meine Ziele" names the goal: Aus by default, Täglich once it is on, "Ab morgen" while a change waits',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.profile);
        await tester.ensureVisible(find.text('Workout heute'));
        expect(find.text('Workout heute'), findsOneWidget);
        expect(find.text('Aus'), findsWidgets);

        // Switched on from tomorrow: today still Aus, the change is named.
        await tester.runCommand(
          () => env.container
              .read(goalVersionRepositoryProvider)
              .upsert(
                GoalVersion(
                  type: GoalType.workoutDaily,
                  effectiveFrom: tomorrow,
                ),
                newId: 'daily-tomorrow',
                nowUtc: env.harness.clock.nowUtc(),
              ),
        );
        await settle(tester);
        expect(find.text('Ab morgen: Täglich'), findsOneWidget);
      },
    );

    testWidgets('(BS-99) a goal that is on reads Täglich', (tester) async {
      final env = await createScreenEnv(tester, workoutDailyGoal: true);
      await openScreen(tester, env, ProfileRoutes.profile);
      await tester.ensureVisible(find.text('Workout heute'));
      expect(find.text('Täglich'), findsWidgets);
    });
  });

  group('labels and layout (AT33, AT34)', () {
    testWidgets(
      '(BS-99, AT34) the row is one switch with its caption as label',
      (tester) async {
        final handle = tester.ensureSemantics();
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.goals);
        expect(
          find.bySemanticsLabel(
            'Workout heute, Training, Ruhetag oder übersprungen zählt',
          ),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    for (final size in responsiveSizes) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '(BS-99, AT33) the editor with the goal on fits ${size.width.toInt()} px at text scale $scale; the row keeps 56 px and a label',
          (tester) async {
            final handle = tester.ensureSemantics();
            final env = await createScreenEnv(tester, workoutDailyGoal: true);
            await openScreen(
              tester,
              env,
              ProfileRoutes.goals,
              size: size,
              textScale: scale,
            );
            expect(tester.takeException(), isNull, reason: 'no overflow');
            // Measured before anything is scrolled, like the other editor
            // tests: a half hidden row would fail the guideline for the wrong
            // reason.
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );

            final row = find.ancestor(
              of: find.text('Workout heute'),
              matching: find.byType(EntryListTile),
            );
            await tester.ensureVisible(row);
            await tester.pump();
            final rect = tester.getRect(row);
            expect(rect.height, greaterThanOrEqualTo(56));
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
            handle.dispose();
          },
        );
      }
    }

    for (final theme in AppThemeVariant.values) {
      testWidgets(
        '(BS-99, AT35) the row renders in ${theme.name}: texts and the switch in the colours of the tokens',
        (tester) async {
          final env = await createScreenEnv(tester, workoutDailyGoal: true);
          await openScreen(tester, env, ProfileRoutes.goals, theme: theme);
          expect(tester.takeException(), isNull);
          final colors = tester
              .element(find.text('Workout heute'))
              .tokens
              .colors;
          final title = tester.widget<Text>(find.text('Workout heute'));
          final caption = tester.widget<Text>(
            find.text('Training, Ruhetag oder übersprungen zählt'),
          );
          expect(title.style!.color, colors.textPrimary);
          expect(caption.style!.color, colors.textSecondary);
          for (final color in [title.style!.color!, caption.style!.color!]) {
            expect(
              contrastRatio(color, colors.surface),
              greaterThanOrEqualTo(4.5),
              reason: '${theme.name}: text on the card',
            );
          }
          expect(dailySwitch(tester).value, isTrue);
        },
      );
    }
  });
}
