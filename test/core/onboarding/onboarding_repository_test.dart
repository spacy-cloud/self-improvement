import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/profile/profile_repository.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late OnboardingRepository onboarding;

  Future<void> start({RecordingProjectionSynchronizer? projection}) async {
    harness = await DataHarness.create(
      realProjection: projection == null,
      projections: projection,
    );
    onboarding = OnboardingRepository(
      database: harness.database,
      runner: harness.runner,
      goals: GoalVersionRepository(harness.database),
    );
  }

  tearDown(() => harness.dispose());

  final today = LocalDate(2026, 10, 3);

  group('complete', () {
    test(
      'stores profile, modules, goals and cards together (AT01, AT02)',
      () async {
        await start();
        final events = <AppEvent>[];
        final subscription = harness.events.stream.listen(events.add);
        addTearDown(subscription.cancel);

        await onboarding.complete(
          commandId: 'o1',
          draft: const OnboardingDraft(
            displayName: '  Mia Muster  ',
            heightCm: 170,
            ageYears: 30,
            startWeightGrams: 72000,
            motivationGoals: ['move_more', 'build_habits', 'move_more'],
            enabledModules: {ModuleId.body, ModuleId.nutrition},
            goals: {
              GoalType.water: GoalSetting(target: 3000),
              GoalType.steps: GoalSetting(target: 8000, enabled: false),
            },
          ),
        );

        final profile = (await ProfileRepository(harness.database).get())!;
        expect(profile.onboardingCompleted, isTrue);
        expect(profile.displayName, 'Mia Muster');
        expect(profile.heightCm, 170);
        expect(profile.ageYears, 30);
        expect(profile.startWeightGrams, 72000);
        expect(profile.targetWeightGrams, isNull);
        expect(profile.motivationGoals, ['move_more', 'build_habits']);
        expect(profile.startedOn, today);

        final statuses = await harness.moduleStatus.statuses();
        expect(statuses[ModuleId.body], isTrue);
        expect(statuses[ModuleId.nutrition], isTrue);
        expect(statuses[ModuleId.focus], isFalse);
        expect(statuses[ModuleId.tasks], isFalse);
        expect(statuses[ModuleId.gamification], isFalse);
        expect(
          await harness.database
              .select(harness.database.moduleStatusHistory)
              .get(),
          hasLength(5),
        );

        final goals = await GoalVersionRepository(harness.database).all();
        expect(goals, hasLength(6));
        final byType = {for (final g in goals) g.type: g};
        expect(byType[GoalType.water]!.target, 3000);
        expect(byType[GoalType.steps]!.enabled, isFalse);
        expect(byType[GoalType.focusMinutes]!.target, 25, reason: 'default');
        expect(byType[GoalType.workoutWeekly]!.target, 3);
        expect(goals.every((g) => g.effectiveFrom == today), isTrue);

        final cards = await (harness.database.select(
          harness.database.dashboardCards,
        )..orderBy([(c) => OrderingTerm.asc(c.sortIndex)])).get();
        expect(
          cards.map((c) => c.cardId).toList(),
          SchemaKeys.defaultCardOrder,
        );
        expect(cards.every((c) => c.visible), isTrue);

        // Body values are profile data, never measurements.
        expect(
          await harness.database.select(harness.database.weightEntries).get(),
          isEmpty,
        );
        expect(await harness.totalXp(), 0);

        // Today's snapshot exists and follows the chosen modules.
        final snapshot = await harness.database
            .select(harness.database.dailyGoalSnapshots)
            .get();
        final applicable = {for (final s in snapshot) s.goalKey: s.applicable};
        expect(applicable['water'], isTrue);
        expect(applicable['steps'], isFalse, reason: 'goal switched off');
        expect(applicable['focus_minutes'], isFalse, reason: 'module off');
        expect(applicable['task_completion'], isFalse);

        await Future<void>.delayed(Duration.zero);
        expect(events.whereType<GoalsChanged>(), isNotEmpty);
      },
    );

    test(
      'skipping completes with all modules, default goals and no invented data',
      () async {
        await start();
        await onboarding.complete(
          commandId: 'skip',
          draft: const OnboardingDraft.skipped(),
        );

        final profile = (await ProfileRepository(harness.database).get())!;
        expect(profile.onboardingCompleted, isTrue);
        expect(profile.displayName, isNull);
        expect(profile.heightCm, isNull);
        expect(profile.ageYears, isNull);
        expect(profile.startWeightGrams, isNull);
        expect(profile.motivationGoals, isEmpty);

        expect(
          (await harness.moduleStatus.statuses()).values.every((e) => e),
          isTrue,
        );
        final goals = {
          for (final g in await GoalVersionRepository(harness.database).all())
            g.type: g,
        };
        expect(goals[GoalType.water]!.target, 2500);
        expect(goals[GoalType.steps]!.target, 10000);
        expect(goals[GoalType.focusMinutes]!.target, 25);
        expect(goals[GoalType.taskCompletion]!.target, 1);
        expect(goals[GoalType.weightEntry]!.target, 1);
        expect(goals[GoalType.workoutWeekly]!.target, 3);
        expect(goals.values.every((g) => g.enabled), isTrue);
        expect(
          await harness.database.select(harness.database.weightEntries).get(),
          isEmpty,
        );
      },
    );

    test('all modules may be switched off (AT04)', () async {
      await start();
      await onboarding.complete(
        commandId: 'none',
        draft: const OnboardingDraft(enabledModules: {}),
      );
      expect(
        (await harness.moduleStatus.statuses()).values.every((e) => !e),
        isTrue,
      );
      final snapshot = await harness.database
          .select(harness.database.dailyGoalSnapshots)
          .get();
      expect(snapshot.every((s) => !s.applicable), isTrue);
      final status = (await harness.dayStatusRepository().statusFor(today))!;
      expect(status.ringFraction, isNull, reason: 'no 0/0 ring');
    });

    test('no preselected preferences: an empty list stays empty', () async {
      await start();
      await onboarding.complete(commandId: 'p', draft: const OnboardingDraft());
      expect(
        (await ProfileRepository(harness.database).get())!.motivationGoals,
        isEmpty,
      );
    });
  });

  group('atomicity and validation', () {
    Future<void> expectNothingCompleted() async {
      final profile = (await ProfileRepository(harness.database).get())!;
      expect(profile.onboardingCompleted, isFalse);
      expect(profile.displayName, isNull);
      expect(
        await harness.database
            .select(harness.database.moduleStatusHistory)
            .get(),
        isEmpty,
      );
      expect(
        await harness.database.select(harness.database.goalVersions).get(),
        isEmpty,
      );
      expect(
        await harness.database.select(harness.database.dashboardCards).get(),
        isEmpty,
      );
      expect(
        await harness.database.select(harness.database.commandReceipts).get(),
        isEmpty,
      );
    }

    test(
      'invalid body data is a field error and nothing is committed',
      () async {
        await start();
        for (final draft in [
          const OnboardingDraft(displayName: 'Mia', heightCm: 99),
          const OnboardingDraft(displayName: 'Mia', ageYears: 17),
          const OnboardingDraft(displayName: 'Mia', startWeightGrams: 19900),
          OnboardingDraft(displayName: 'x' * 41),
          const OnboardingDraft(motivationGoals: ['become_famous']),
          const OnboardingDraft(
            goals: {GoalType.water: GoalSetting(target: 100)},
          ),
        ]) {
          await expectLater(
            onboarding.complete(commandId: harness.ids.newId(), draft: draft),
            throwsA(isA<ValidationFailure>()),
          );
          await expectNothingCompleted();
        }
      },
    );

    test(
      'a database failure during completion leaves onboarding open (AT27)',
      () async {
        final projection = RecordingProjectionSynchronizer()
          ..failure = StateError('disk');
        await start(projection: projection);
        await expectLater(
          onboarding.complete(
            commandId: 'f',
            draft: const OnboardingDraft(displayName: 'Mia'),
          ),
          throwsA(isA<StorageFailure>()),
        );
        await expectNothingCompleted();
        // Retry with the same id works after the problem is gone.
        projection.failure = null;
        await onboarding.complete(
          commandId: 'f',
          draft: const OnboardingDraft(displayName: 'Mia'),
        );
        expect(
          (await ProfileRepository(
            harness.database,
          ).get())!.onboardingCompleted,
          isTrue,
        );
      },
    );

    test('completing twice is a conflict and a replay is a no-op', () async {
      await start();
      await onboarding.complete(
        commandId: 'a',
        draft: const OnboardingDraft.skipped(),
      );
      final replay = await onboarding.complete(
        commandId: 'a',
        draft: const OnboardingDraft.skipped(),
      );
      expect(replay.replayed, isTrue);
      await expectLater(
        onboarding.complete(
          commandId: 'b',
          draft: const OnboardingDraft.skipped(),
        ),
        throwsA(isA<ConflictFailure>()),
      );
      expect(
        await harness.database
            .select(harness.database.moduleStatusHistory)
            .get(),
        hasLength(5),
      );
    });
  });

  group('the optional daily workout goal (BS-99)', () {
    Future<List<GoalType>> storedTypes() async => [
      for (final goal in await GoalVersionRepository(harness.database).all())
        goal.type,
    ];

    test('(BS-99) skipping writes a version for every goal but "Workout heute": it stays off', () async {
      await start();
      await onboarding.complete(
        commandId: 'skip',
        draft: const OnboardingDraft.skipped(),
      );
      final types = await storedTypes();
      expect(types, hasLength(GoalType.values.length - 1));
      expect(types, isNot(contains(GoalType.workoutDaily)));
      expect(
        types.toSet(),
        GoalType.values.toSet()..remove(GoalType.workoutDaily),
      );

      final status = (await harness.dayStatusRepository().statusFor(today))!;
      final daily = status.progressOf(GoalType.workoutDaily)!;
      expect(daily.applicable, isFalse, reason: 'off, not in "x von y"');
      expect(status.applicableCount, 5);
    });

    test(
      '(BS-99) a finished onboarding with entered goals leaves it off as well',
      () async {
        await start();
        await onboarding.complete(
          commandId: 'goals',
          draft: const OnboardingDraft(
            goals: {GoalType.workoutWeekly: GoalSetting(target: 5)},
          ),
        );
        expect(await storedTypes(), isNot(contains(GoalType.workoutDaily)));
      },
    );

    test(
      '(BS-99) an explicit choice writes the version, effective from today',
      () async {
        await start();
        await onboarding.complete(
          commandId: 'explicit',
          draft: const OnboardingDraft(
            goals: {GoalType.workoutDaily: GoalSetting()},
          ),
        );
        final goals = await GoalVersionRepository(harness.database).all();
        final daily = goals.singleWhere((g) => g.type == GoalType.workoutDaily);
        expect(daily.enabled, isTrue);
        expect(daily.target, 1);
        expect(daily.effectiveFrom, today);
        final status = (await harness.dayStatusRepository().statusFor(today))!;
        expect(status.progressOf(GoalType.workoutDaily)!.applicable, isTrue);
      },
    );

    test(
      '(BS-99) the test harness seeds it off too, unless a test asks for it',
      () async {
        await start();
        await harness.seedOnboarded();
        expect(await storedTypes(), isNot(contains(GoalType.workoutDaily)));
        await harness.dispose();

        await start();
        await harness.seedOnboarded(workoutDailyGoal: true);
        final daily = (await GoalVersionRepository(
          harness.database,
        ).all()).singleWhere((g) => g.type == GoalType.workoutDaily);
        expect(daily.enabled, isTrue);
      },
    );
  });
}
