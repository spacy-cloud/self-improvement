import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/profile/profile_repository.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_controller.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_state.dart';

import '../support/onboarding_test_env.dart';

/// Controller, wrapped repository and database of one test.
class _Fixture {
  _Fixture._(this.harness, this.container, this.repository);

  final DataHarness harness;
  final ProviderContainer container;
  final FlakyOnboardingRepository repository;

  static Future<_Fixture> create({
    int failures = 0,
    AppFailure error = const StorageFailure(causeType: 'TestFailure'),
    RecordingProjectionSynchronizer? projection,
  }) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final harness = await DataHarness.create(projections: projection);
    addTearDown(harness.dispose);
    final real = harness.createContainer().read(onboardingRepositoryProvider);
    final repository = FlakyOnboardingRepository(
      real,
      failures: failures,
      error: error,
    );
    final container = harness.createContainer(
      overrides: [onboardingRepositoryProvider.overrideWithValue(repository)],
    );
    // Keeps the auto dispose notifier alive like the mounted screen does.
    container.listen(onboardingControllerProvider, (previous, next) {});
    return _Fixture._(harness, container, repository);
  }

  OnboardingController get controller =>
      container.read(onboardingControllerProvider.notifier);

  OnboardingState get state => container.read(onboardingControllerProvider);

  Future<UserProfile> profile() async =>
      (await ProfileRepository(harness.database).get())!;

  Future<Map<GoalType, bool>> goalsEnabled() async {
    final goals = await GoalVersionRepository(harness.database).all();
    return <GoalType, bool>{for (final goal in goals) goal.type: goal.enabled};
  }

  Future<Map<GoalType, int?>> goalTargets() async {
    final goals = await GoalVersionRepository(harness.database).all();
    return <GoalType, int?>{for (final goal in goals) goal.type: goal.target};
  }

  Future<int> goalVersionCount() async =>
      (await GoalVersionRepository(harness.database).all()).length;

  /// Walks to the last step (the body texts typed so far must be valid).
  void goToLastStep() {
    while (!state.step.isLast) {
      expect(controller.next(), isTrue);
    }
  }
}

/// Throws something that is not an [AppFailure].
class _ThrowingRepository implements OnboardingRepository {
  @override
  Future<CommandOutcome> complete({
    required String commandId,
    required OnboardingDraft draft,
  }) => throw StateError('disk is on fire');
}

void main() {
  group('fresh state', () {
    test(
      'starts on the welcome screen with nothing selected or typed (AT01)',
      () async {
        final fixture = await _Fixture.create();
        final state = fixture.state;
        expect(state.step, OnboardingStep.welcome);
        expect(state.motivationGoals, isEmpty, reason: 'no preselection');
        expect(state.enabledModules, ModuleId.values.toSet());
        expect(state.nameText, isEmpty);
        expect(state.heightText, isEmpty);
        expect(state.ageText, isEmpty);
        expect(state.weightText, isEmpty);
        expect(state.goalTargets, <GoalType, int>{
          GoalType.steps: 10000,
          GoalType.water: 2500,
          GoalType.focusMinutes: 25,
          GoalType.workoutWeekly: 3,
        });
        expect(state.goalsOff, isEmpty);
        expect(state.fieldErrors, isEmpty);
        expect(state.submitFailure, isNull);
        expect(state.hasUserInput, isFalse);
        expect(state.busy, isFalse);
      },
    );

    test('nothing is stored before the flow is finished', () async {
      final fixture = await _Fixture.create();
      final goalsBefore = await fixture.goalVersionCount();
      fixture.controller
        ..toggleMotivationGoal('lose_weight')
        ..setNameText('Testperson')
        ..setAgeText('30');
      fixture.goToLastStep();
      expect(fixture.repository.commandIds, isEmpty);
      final profile = await fixture.profile();
      expect(profile.onboardingCompleted, isFalse);
      expect(profile.displayName, isNull);
      expect(profile.ageYears, isNull);
      expect(profile.motivationGoals, isEmpty);
      expect(await fixture.goalVersionCount(), goalsBefore);
    });
  });

  group('input', () {
    test('motivation goals toggle, unknown ids are ignored', () async {
      final fixture = await _Fixture.create();
      fixture.controller
        ..toggleMotivationGoal('lose_weight')
        ..toggleMotivationGoal('build_habits')
        ..toggleMotivationGoal('does_not_exist');
      expect(fixture.state.motivationGoals, <String>{
        'lose_weight',
        'build_habits',
      });
      fixture.controller.toggleMotivationGoal('lose_weight');
      expect(fixture.state.motivationGoals, <String>{'build_habits'});
      expect(fixture.state.hasUserInput, isTrue);
    });

    test('all modules can be dropped and picked again (C03, AT04)', () async {
      final fixture = await _Fixture.create();
      for (final module in ModuleId.values) {
        fixture.controller.setModuleEnabled(module, enabled: false);
      }
      expect(fixture.state.enabledModules, isEmpty);
      expect(fixture.state.hasUserInput, isTrue);
      // The flow can continue without any module.
      expect(fixture.controller.next(), isTrue);
      fixture.controller.setModuleEnabled(ModuleId.focus, enabled: true);
      fixture.controller.setModuleEnabled(ModuleId.focus, enabled: true);
      expect(fixture.state.enabledModules, <ModuleId>{ModuleId.focus});
      for (final module in ModuleId.values) {
        fixture.controller.setModuleEnabled(module, enabled: true);
      }
      expect(fixture.state.hasUserInput, isFalse, reason: 'back to defaults');
    });

    test('goal steppers stay inside the limits', () async {
      final fixture = await _Fixture.create();
      final controller = fixture.controller;
      controller.adjustGoalTarget(GoalType.steps, 1);
      expect(fixture.state.goalTargets[GoalType.steps], 10500);
      controller.adjustGoalTarget(GoalType.water, -1);
      expect(fixture.state.goalTargets[GoalType.water], 2250);
      controller.adjustGoalTarget(GoalType.focusMinutes, 1);
      expect(fixture.state.goalTargets[GoalType.focusMinutes], 30);
      for (var i = 0; i < 30; i++) {
        controller.adjustGoalTarget(GoalType.workoutWeekly, 1);
      }
      expect(fixture.state.goalTargets[GoalType.workoutWeekly], 14);
      for (var i = 0; i < 30; i++) {
        controller.adjustGoalTarget(GoalType.workoutWeekly, -1);
      }
      expect(fixture.state.goalTargets[GoalType.workoutWeekly], 1);
      // On/off goals have no target to adjust.
      controller.adjustGoalTarget(GoalType.weightEntry, 1);
      expect(
        fixture.state.goalTargets.containsKey(GoalType.weightEntry),
        isFalse,
      );
    });

    test('only the on/off goals can be switched', () async {
      final fixture = await _Fixture.create();
      fixture.controller
        ..setGoalEnabled(GoalType.weightEntry, enabled: false)
        ..setGoalEnabled(GoalType.steps, enabled: false);
      expect(fixture.state.goalsOff, <GoalType>{GoalType.weightEntry});
      fixture.controller.setGoalEnabled(GoalType.weightEntry, enabled: true);
      expect(fixture.state.goalsOff, isEmpty);
    });
  });

  group('navigation', () {
    test(
      'goes through the five screens and keeps every draft going back (C02)',
      () async {
        final fixture = await _Fixture.create();
        final controller = fixture.controller;
        expect(
          controller.back(),
          isFalse,
          reason: 'nothing before the welcome',
        );
        expect(controller.next(), isTrue);
        expect(fixture.state.step, OnboardingStep.goals);
        expect(fixture.state.step.number, 1);
        controller.toggleMotivationGoal('move_more');
        expect(controller.next(), isTrue);
        expect(fixture.state.step, OnboardingStep.modules);
        controller.setModuleEnabled(ModuleId.gamification, enabled: false);
        expect(controller.next(), isTrue);
        expect(fixture.state.step, OnboardingStep.body);
        controller
          ..setNameText('Testperson')
          ..setAgeText('30')
          ..setHeightText('170')
          ..setWeightText('71,5');
        expect(controller.next(), isTrue);
        expect(fixture.state.step, OnboardingStep.dailyGoals);
        expect(fixture.state.step.number, 4);
        controller.adjustGoalTarget(GoalType.steps, 1);
        expect(controller.next(), isFalse, reason: 'last step');

        // Back to the start: nothing was lost.
        while (fixture.state.step != OnboardingStep.welcome) {
          expect(controller.back(), isTrue);
        }
        final state = fixture.state;
        expect(state.motivationGoals, <String>{'move_more'});
        expect(state.enabledModules, isNot(contains(ModuleId.gamification)));
        expect(state.nameText, 'Testperson');
        expect(state.ageText, '30');
        expect(state.heightText, '170');
        expect(state.weightText, '71,5');
        expect(state.goalTargets[GoalType.steps], 10500);
        expect(state.movedBackward, isTrue);
        controller.next();
        expect(fixture.state.movedBackward, isFalse);
      },
    );

    test('the body step validates before it moves on (C05)', () async {
      final fixture = await _Fixture.create();
      final controller = fixture.controller
        ..next()
        ..next()
        ..next();
      expect(fixture.state.step, OnboardingStep.body);
      controller
        ..setAgeText('17')
        ..setHeightText('251')
        ..setWeightText('71,55');
      final before = fixture.state.focusRequest;
      expect(controller.next(), isFalse);
      expect(fixture.state.step, OnboardingStep.body);
      expect(
        fixture.state.fieldErrors.keys,
        containsAll(<String>[
          ProfileFields.ageYears,
          ProfileFields.heightCm,
          ProfileFields.startWeight,
        ]),
      );
      expect(fixture.state.focusRequest, before + 1);
      // The input stays as typed.
      expect(fixture.state.ageText, '17');
      expect(fixture.state.weightText, '71,55');

      // Editing a field clears just its own error.
      controller.setAgeText('18');
      expect(
        fixture.state.fieldErrors.keys,
        isNot(contains(ProfileFields.ageYears)),
      );
      expect(fixture.state.fieldErrors.keys, contains(ProfileFields.heightCm));
      controller
        ..setHeightText('170')
        ..setWeightText('71,5');
      expect(controller.next(), isTrue);
      expect(fixture.state.step, OnboardingStep.dailyGoals);
      expect(fixture.state.fieldErrors, isEmpty);
    });
  });

  group('completion', () {
    test(
      'finish stores everything in one command (AT01, AT02, C03, C07)',
      () async {
        final fixture = await _Fixture.create();
        final controller = fixture.controller
          ..toggleMotivationGoal('move_more')
          ..toggleMotivationGoal('lose_weight')
          ..setModuleEnabled(ModuleId.gamification, enabled: false)
          ..setModuleEnabled(ModuleId.focus, enabled: false)
          ..setNameText('  Testperson ')
          ..setAgeText('30')
          ..setHeightText('170')
          ..setWeightText('71,5')
          ..adjustGoalTarget(GoalType.steps, 1)
          ..adjustGoalTarget(GoalType.water, -1)
          ..setGoalEnabled(GoalType.taskCompletion, enabled: false);

        final result = await controller.finish();

        expect(result, isA<OnboardingCompleted>());
        expect((result as OnboardingCompleted).alreadyCompleted, isFalse);
        expect(fixture.state.completed, isTrue);
        expect(fixture.repository.commandIds, hasLength(1));

        final profile = await fixture.profile();
        expect(profile.onboardingCompleted, isTrue);
        expect(profile.displayName, 'Testperson');
        expect(profile.ageYears, 30);
        expect(profile.heightCm, 170);
        expect(profile.startWeightGrams, 71500);
        expect(profile.targetWeightGrams, isNull);
        // Stored in the display order of the options, not in tap order.
        expect(profile.motivationGoals, <String>['lose_weight', 'move_more']);

        final modules = await fixture.harness.moduleStatus.statuses();
        expect(modules[ModuleId.body], isTrue);
        expect(modules[ModuleId.nutrition], isTrue);
        expect(modules[ModuleId.tasks], isTrue);
        expect(modules[ModuleId.focus], isFalse);
        expect(modules[ModuleId.gamification], isFalse);

        final targets = await fixture.goalTargets();
        expect(targets[GoalType.steps], 10500);
        expect(targets[GoalType.water], 2250);
        expect(targets[GoalType.focusMinutes], 25);
        expect(targets[GoalType.workoutWeekly], 3);
        final enabled = await fixture.goalsEnabled();
        expect(enabled[GoalType.taskCompletion], isFalse);
        expect(enabled[GoalType.weightEntry], isTrue);
        expect(enabled[GoalType.steps], isTrue);

        // Body values are profile data, never a measurement.
        expect(
          await fixture.harness.database
              .select(fixture.harness.database.weightEntries)
              .get(),
          isEmpty,
        );
      },
    );

    test('finishing without any input stores the suggested defaults and no body data', () async {
      final fixture = await _Fixture.create();
      fixture.goToLastStep();
      final result = await fixture.controller.finish();
      expect(result, isA<OnboardingCompleted>());

      final profile = await fixture.profile();
      expect(profile.onboardingCompleted, isTrue);
      expect(profile.displayName, isNull);
      expect(profile.heightCm, isNull);
      expect(profile.ageYears, isNull);
      expect(profile.startWeightGrams, isNull);
      expect(profile.motivationGoals, isEmpty);
      final modules = await fixture.harness.moduleStatus.statuses();
      expect(modules.values.every((on) => on), isTrue);
      expect(await fixture.goalTargets(), <GoalType, int>{
        GoalType.steps: 10000,
        GoalType.water: 2500,
        GoalType.focusMinutes: 25,
        GoalType.workoutWeekly: 3,
        GoalType.taskCompletion: 1,
        GoalType.weightEntry: 1,
      });
    });

    test(
      'no module at all is stored as five disabled modules (AT04)',
      () async {
        final fixture = await _Fixture.create();
        for (final module in ModuleId.values) {
          fixture.controller.setModuleEnabled(module, enabled: false);
        }
        final result = await fixture.controller.finish();
        expect(result, isA<OnboardingCompleted>());
        final modules = await fixture.harness.moduleStatus.statuses();
        expect(modules.values.every((on) => !on), isTrue);
        expect((await fixture.profile()).onboardingCompleted, isTrue);
      },
    );

    test(
      'skip discards the input and stores the defaults (AT01, C02)',
      () async {
        final fixture = await _Fixture.create();
        fixture.controller
          ..toggleMotivationGoal('lose_weight')
          ..setModuleEnabled(ModuleId.body, enabled: false)
          ..setNameText('Testperson')
          ..setWeightText('80')
          ..adjustGoalTarget(GoalType.steps, 1);
        final result = await fixture.controller.skip();
        expect(result, isA<OnboardingCompleted>());

        final draft = fixture.repository.drafts.single;
        expect(draft.displayName, isNull);
        expect(draft.startWeightGrams, isNull);
        expect(draft.motivationGoals, isEmpty);
        expect(draft.enabledModules, ModuleId.values.toSet());
        expect(draft.goals, isEmpty, reason: 'defaults apply');
        final profile = await fixture.profile();
        expect(profile.onboardingCompleted, isTrue);
        expect(profile.displayName, isNull);
        expect(profile.startWeightGrams, isNull);
        expect(profile.motivationGoals, isEmpty);
        expect((await fixture.goalTargets())[GoalType.steps], 10000);
      },
    );

    test('a second tap while saving is ignored (double tap lock)', () async {
      final fixture = await _Fixture.create();
      fixture.goToLastStep();
      final first = fixture.controller.finish();
      final second = fixture.controller.finish();
      final skipped = fixture.controller.skip();
      expect(await second, isA<OnboardingRejected>());
      expect(await skipped, isA<OnboardingRejected>());
      expect(await first, isA<OnboardingCompleted>());
      expect(fixture.repository.commandIds, hasLength(1));
      // Everything is locked once the command committed.
      expect(await fixture.controller.finish(), isA<OnboardingRejected>());
      expect(fixture.repository.commandIds, hasLength(1));
    });

    test(
      'invalid body values on finish bring the user back to the body step',
      () async {
        final fixture = await _Fixture.create();
        fixture.goToLastStep();
        fixture.controller.setHeightText('10');
        final result = await fixture.controller.finish();
        expect(result, isA<OnboardingRejected>());
        expect(fixture.state.step, OnboardingStep.body);
        expect(
          fixture.state.fieldErrors.keys,
          contains(ProfileFields.heightCm),
        );
        expect(fixture.repository.commandIds, isEmpty);
        expect((await fixture.profile()).onboardingCompleted, isFalse);
      },
    );
  });

  group('failures (C05)', () {
    test('a database failure rolls everything back, keeps the flow open and the retry reuses the command id (AT01)', () async {
      final projection = RecordingProjectionSynchronizer()
        ..failure = StateError('disk');
      final fixture = await _Fixture.create(projection: projection);
      final goalsBefore = await fixture.goalVersionCount();
      fixture.controller
        ..toggleMotivationGoal('get_fitter')
        ..setNameText('Testperson')
        ..setModuleEnabled(ModuleId.focus, enabled: false);
      fixture.goToLastStep();

      final failed = await fixture.controller.finish();

      expect(failed, isA<OnboardingFailed>());
      expect(fixture.state.completed, isFalse);
      expect(fixture.state.submitting, isFalse);
      expect(fixture.state.submitFailure, isA<StorageFailure>());
      expect(fixture.state.failedSubmit, OnboardingSubmitKind.finish);
      expect(fixture.state.step, OnboardingStep.dailyGoals);
      expect(fixture.state.nameText, 'Testperson', reason: 'input kept');
      expect(fixture.state.motivationGoals, <String>{'get_fitter'});
      // The write inside the command was rolled back as a whole.
      final profile = await fixture.profile();
      expect(profile.onboardingCompleted, isFalse);
      expect(profile.displayName, isNull);
      expect(await fixture.goalVersionCount(), goalsBefore);

      projection.failure = null;
      final retried = await fixture.controller.retry();
      expect(retried, isA<OnboardingCompleted>());
      expect(fixture.repository.commandIds, hasLength(2));
      expect(
        fixture.repository.commandIds.first,
        fixture.repository.commandIds.last,
        reason: 'same content, same command id',
      );
      final saved = await fixture.profile();
      expect(saved.onboardingCompleted, isTrue);
      expect(saved.displayName, 'Testperson');
      expect(saved.motivationGoals, <String>['get_fitter']);
      expect(
        (await fixture.harness.moduleStatus.statuses())[ModuleId.focus],
        isFalse,
      );
      expect(fixture.state.submitFailure, isNull);
    });

    test('editing after a failure makes the old attempt obsolete and uses a new command id', () async {
      final fixture = await _Fixture.create(failures: 1);
      fixture.goToLastStep();
      await fixture.controller.finish();
      expect(fixture.state.submitFailure, isNotNull);

      fixture.controller.adjustGoalTarget(GoalType.steps, 1);
      expect(
        fixture.state.submitFailure,
        isNull,
        reason: 'an edit clears the error',
      );
      final result = await fixture.controller.finish();
      expect(result, isA<OnboardingCompleted>());
      expect(
        fixture.repository.commandIds.first,
        isNot(fixture.repository.commandIds.last),
        reason: 'changed content must not reuse the failed id',
      );
      expect((await fixture.goalTargets())[GoalType.steps], 10500);
    });

    test('a failed skip is retried as a skip', () async {
      final fixture = await _Fixture.create(failures: 1);
      fixture.controller.toggleMotivationGoal('lose_weight');
      final failed = await fixture.controller.skip();
      expect(failed, isA<OnboardingFailed>());
      expect(fixture.state.failedSubmit, OnboardingSubmitKind.skip);
      expect((await fixture.profile()).onboardingCompleted, isFalse);

      expect(await fixture.controller.retry(), isA<OnboardingCompleted>());
      expect(
        fixture.repository.commandIds.first,
        fixture.repository.commandIds.last,
      );
      final profile = await fixture.profile();
      expect(profile.onboardingCompleted, isTrue);
      expect(profile.motivationGoals, isEmpty, reason: 'skip stores no input');
    });

    test('an unexpected error counts as a storage error and never sticks the button', () async {
      final fixture = await _Fixture.create();
      final container = fixture.harness.createContainer(
        overrides: [
          onboardingRepositoryProvider.overrideWithValue(_ThrowingRepository()),
        ],
      )..listen(onboardingControllerProvider, (previous, next) {});
      final result = await container
          .read(onboardingControllerProvider.notifier)
          .skip();
      expect(result, isA<OnboardingFailed>());
      final state = container.read(onboardingControllerProvider);
      expect(state.submitting, isFalse);
      expect(state.completed, isFalse);
      expect(state.submitFailure, isA<StorageFailure>());
    });

    test(
      'a validation error of the repository goes back to the field',
      () async {
        final fixture = await _Fixture.create(
          failures: 1,
          error: const ValidationFailure(<String, String>{
            'water': 'Ungültiger Zielwert.',
          }),
        );
        fixture.goToLastStep();
        final result = await fixture.controller.finish();
        expect(result, isA<OnboardingRejected>());
        expect(fixture.state.step, OnboardingStep.dailyGoals);
        expect(fixture.state.fieldErrors['water'], 'Ungültiger Zielwert.');
        expect(fixture.state.submitting, isFalse);
        expect(fixture.state.submitFailure, isNull);
      },
    );

    test('an already onboarded profile counts as done and writes nothing again (AT02)', () async {
      final fixture = await _Fixture.create();
      fixture.controller.setNameText('Erster Start');
      fixture.goToLastStep();
      expect(await fixture.controller.finish(), isA<OnboardingCompleted>());

      // A stale onboarding screen of a second start: other controller, same
      // database.
      final other = fixture.harness.createContainer(
        overrides: [
          onboardingRepositoryProvider.overrideWithValue(fixture.repository),
        ],
      )..listen(onboardingControllerProvider, (previous, next) {});
      final controller = other.read(onboardingControllerProvider.notifier)
        ..setNameText('Zweiter Versuch');
      final result = await controller.skip();
      expect(result, isA<OnboardingCompleted>());
      expect((result as OnboardingCompleted).alreadyCompleted, isTrue);
      expect((await fixture.profile()).displayName, 'Erster Start');
    });
  });
}
