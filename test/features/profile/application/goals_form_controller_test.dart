import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/profile/application/goals_form_controller.dart';
import 'package:self_improvement/features/profile/domain/goal_editor.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/flaky_projection.dart';
import '../support/recording_commands.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late FlakyProjection projection;
  late RecordingGoalsCommands goalCommands;
  late RecordingProfileCommands profileCommands;
  late ProviderContainer container;
  late GoalVersionRepository versions;

  final allOn = <ModuleId, bool>{
    for (final module in ModuleId.values) module: true,
  };
  final today = LocalDate(2026, 10, 3);
  final tomorrow = LocalDate(2026, 10, 4);

  Future<void> start({bool realProjection = false}) async {
    projection = FlakyProjection();
    harness = realProjection
        ? await DataHarness.create(realProjection: true)
        : await DataHarness.create(projections: projection);
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    versions = GoalVersionRepository(harness.database);
    goalCommands = RecordingGoalsCommands(
      runner: harness.runner,
      versions: versions,
    );
    profileCommands = RecordingProfileCommands(
      database: harness.database,
      runner: harness.runner,
    );
    container = harness.createContainer(
      overrides: [
        goalsCommandsProvider.overrideWithValue(goalCommands),
        profileCommandsProvider.overrideWithValue(profileCommands),
      ],
    );
  }

  setUp(start);
  tearDown(() => harness.dispose());

  Future<UserProfile> stored() async =>
      (await container.read(profileRepositoryProvider).get())!;

  Future<GoalEditorModel> buildModel({Map<ModuleId, bool>? modules}) async =>
      buildGoalEditorModel(
        versions: await versions.all(),
        today: harness.clock.today(),
        modules: modules ?? allOn,
      );

  Future<GoalsFormArgs> open({
    Map<ModuleId, bool>? modules,
    int? latest,
  }) async {
    final profile = await stored();
    final bodyVisible = (modules ?? allOn)[ModuleId.body] ?? true;
    final args = GoalsFormArgs(
      model: await buildModel(modules: modules),
      bodyVisible: bodyVisible,
      targetWeightGrams: profile.targetWeightGrams,
      startWeightGrams: profile.startWeightGrams,
      latestWeightGrams: latest,
    );
    final subscription = container.listen(goalsFormProvider(args), (_, _) {});
    addTearDown(subscription.close);
    return args;
  }

  GoalsFormController controller(GoalsFormArgs args) =>
      container.read(goalsFormProvider(args).notifier);

  GoalsFormState state(GoalsFormArgs args) =>
      container.read(goalsFormProvider(args));

  Future<GoalVersion?> versionOn(GoalType type, LocalDate day) async {
    final all = await versions.all();
    final matches = all.where((v) => v.type == type && v.effectiveFrom == day);
    return matches.isEmpty ? null : matches.single;
  }

  group('a new editor', () {
    test('starts from what applies tomorrow and is clean', () async {
      await goalCommands.update(
        commandId: 'seed',
        changes: const {GoalType.water: GoalSetting(target: 3000)},
      );
      goalCommands.commandIds.clear();
      final args = await open();
      expect(state(args).drafts[GoalType.water]!.text, '3000');
      expect(state(args).drafts[GoalType.steps]!.text, '10000');
      expect(state(args).dirty, isFalse);
      expect(state(args).targetWeightText, isEmpty);
    });

    test('saving without a change writes nothing', () async {
      final args = await open();
      final before = (await versions.all()).length;
      expect(await controller(args).submit(), isA<GoalsUnchanged>());
      expect((await versions.all()).length, before);
      expect(goalCommands.commandIds, isEmpty);
      expect(profileCommands.commandIds, isEmpty);
    });
  });

  group('goal changes apply from tomorrow (C07, AT24)', () {
    test(
      'a new water goal is stored for tomorrow, today keeps the old',
      () async {
        final args = await open();
        controller(args).setText(GoalType.water, '3000');
        expect(state(args).dirty, isTrue);
        final result = await controller(args).submit();
        expect(result, isA<GoalsSaved>());
        final saved = result as GoalsSaved;
        expect(saved.goalsSaved, isTrue);
        expect(saved.targetSaved, isFalse);
        expect(saved.message, 'Ziele gespeichert. Sie gelten ab morgen.');

        expect((await versionOn(GoalType.water, tomorrow))!.target, 3000);
        expect(await versionOn(GoalType.water, today), isNull);
        final model = await buildModel();
        expect(model.rowOf(GoalType.water).today.target, 2500);
        expect(model.rowOf(GoalType.water).tomorrow.target, 3000);
        expect(model.rowOf(GoalType.water).hasPendingChange, isTrue);
        expect(state(args).dirty, isFalse);
      },
    );

    test('the next day the new value is the goal of today', () async {
      final args = await open();
      controller(args).setText(GoalType.water, '3000');
      await controller(args).submit();
      harness.clock.advance(const Duration(days: 1));
      final model = await buildModel();
      expect(model.today, tomorrow);
      expect(model.rowOf(GoalType.water).today.target, 3000);
      expect(model.rowOf(GoalType.water).hasPendingChange, isFalse);
    });

    test('several saves on one day replace the version of tomorrow', () async {
      final args = await open();
      controller(args).setText(GoalType.water, '3000');
      await controller(args).submit();
      controller(args).setText(GoalType.water, '3500');
      await controller(args).submit();
      final all = await versions.all();
      final forTomorrow = all.where(
        (v) => v.type == GoalType.water && v.effectiveFrom == tomorrow,
      );
      expect(forTomorrow.single.target, 3500);
    });

    test(
      'a goal can be switched off and keeps its value (from tomorrow)',
      () async {
        final args = await open();
        controller(args).setEnabled(GoalType.steps, enabled: false);
        expect(await controller(args).submit(), isA<GoalsSaved>());
        final version = (await versionOn(GoalType.steps, tomorrow))!;
        expect(version.enabled, isFalse);
        expect(version.target, 10000);
        final model = await buildModel();
        expect(model.rowOf(GoalType.steps).today.enabled, isTrue);
        expect(model.rowOf(GoalType.steps).tomorrow.enabled, isFalse);
      },
    );

    test(
      'a switched-off goal with an unusable text keeps its last value',
      () async {
        final args = await open();
        controller(args)
          ..setText(GoalType.focusMinutes, '')
          ..setEnabled(GoalType.focusMinutes, enabled: false);
        expect(await controller(args).submit(), isA<GoalsSaved>());
        final version = (await versionOn(GoalType.focusMinutes, tomorrow))!;
        expect(version.enabled, isFalse);
        expect(version.target, 25);
        expect(state(args).drafts[GoalType.focusMinutes]!.text, '25');
      },
    );

    test('the switch goals only have the switch', () async {
      final args = await open();
      controller(args)
        ..setEnabled(GoalType.weightEntry, enabled: false)
        ..setEnabled(GoalType.taskCompletion, enabled: false);
      expect(await controller(args).submit(), isA<GoalsSaved>());
      final weight = (await versionOn(GoalType.weightEntry, tomorrow))!;
      expect(weight.enabled, isFalse);
      expect(weight.target, 1);
      expect(
        (await versionOn(GoalType.taskCompletion, tomorrow))!.enabled,
        isFalse,
      );
    });

    test('only changed goals create a version', () async {
      final args = await open();
      final before = (await versions.all()).length;
      controller(args).setText(GoalType.focusMinutes, '30');
      await controller(args).submit();
      expect((await versions.all()).length, before + 1);
    });

    test(
      'goals of switched-off modules are neither validated nor sent',
      () async {
        final modules = {...allOn, ModuleId.nutrition: false};
        final args = await open(modules: modules);
        controller(args)
          ..setText(GoalType.water, '260') // invalid, but hidden
          ..setText(GoalType.steps, '12000');
        final result = await controller(args).submit();
        expect(result, isA<GoalsSaved>());
        expect(await versionOn(GoalType.water, tomorrow), isNull);
        expect((await versionOn(GoalType.steps, tomorrow))!.target, 12000);
      },
    );
  });

  group('with real day snapshots', () {
    test(
      'today keeps its threshold, tomorrow gets the new one (AT24)',
      () async {
        await harness.dispose();
        await start(realProjection: true);
        final args = await open();
        // Today's snapshot exists with the old threshold before the edit.
        final status = harness.dayStatusRepository();
        int? waterTarget(DayStatus day) =>
            day.goals.singleWhere((g) => g.goalKey == 'water').target;
        expect(waterTarget((await status.statusFor(today))!), 2500);

        controller(args).setText(GoalType.water, '3000');
        expect(await controller(args).submit(), isA<GoalsSaved>());

        expect(waterTarget((await status.statusFor(today))!), 2500);
        harness.clock.advance(const Duration(days: 1));
        expect(waterTarget((await status.statusFor(tomorrow))!), 3000);
      },
    );
  });

  group('validation keeps the input (both sides of every limit)', () {
    Future<bool> accepted(GoalType type, String text) async {
      final args = await open();
      controller(args).setText(type, text);
      final result = await controller(args).submit();
      if (result is GoalsRejected) {
        expect(state(args).fieldErrors.keys, [type.key], reason: '$type $text');
        expect(state(args).drafts[type]!.text, text, reason: 'input stays');
        expect(state(args).dirty, isTrue);
        return false;
      }
      return result is GoalsSaved;
    }

    test('water 250 to 10.000 ml in 50 ml steps', () async {
      for (final ok in ['250', '2750', '10000']) {
        expect(await accepted(GoalType.water, ok), isTrue, reason: ok);
      }
      for (final bad in ['0', '249', '260', '10050', 'abc', '']) {
        expect(await accepted(GoalType.water, bad), isFalse, reason: bad);
      }
    });

    test('steps 100 to 100.000', () async {
      for (final ok in ['100', '100000']) {
        expect(await accepted(GoalType.steps, ok), isTrue, reason: ok);
      }
      for (final bad in ['99', '100001']) {
        expect(await accepted(GoalType.steps, bad), isFalse, reason: bad);
      }
    });

    test('focus 5 to 180 minutes', () async {
      for (final ok in ['5', '180']) {
        expect(await accepted(GoalType.focusMinutes, ok), isTrue, reason: ok);
      }
      for (final bad in ['4', '181']) {
        expect(
          await accepted(GoalType.focusMinutes, bad),
          isFalse,
          reason: bad,
        );
      }
    });

    test('workouts per week 1 to 14', () async {
      for (final ok in ['1', '14']) {
        expect(await accepted(GoalType.workoutWeekly, ok), isTrue, reason: ok);
      }
      for (final bad in ['0', '15']) {
        expect(
          await accepted(GoalType.workoutWeekly, bad),
          isFalse,
          reason: bad,
        );
      }
    });

    test('one invalid value blocks everything, nothing is written', () async {
      final args = await open();
      final before = (await versions.all()).length;
      controller(args)
        ..setText(GoalType.steps, '12000')
        ..setText(GoalType.water, '260')
        ..setTargetWeightText('70,0');
      expect(await controller(args).submit(), isA<GoalsRejected>());
      expect((await versions.all()).length, before);
      expect((await stored()).targetWeightGrams, isNull);
      expect(state(args).drafts[GoalType.steps]!.text, '12000');
    });

    test('editing a field clears only its own error', () async {
      final args = await open();
      controller(args)
        ..setText(GoalType.water, '260')
        ..setText(GoalType.steps, '5');
      await controller(args).submit();
      expect(state(args).fieldErrors.keys.toSet(), {'water', 'steps'});
      controller(args).setText(GoalType.water, '2500');
      expect(state(args).fieldErrors.keys, ['steps']);
    });
  });

  group('plus and minus', () {
    test('move by the step and stay inside the range', () async {
      final args = await open();
      controller(args).step(GoalType.water, 1);
      expect(state(args).drafts[GoalType.water]!.text, '2750');
      controller(args).step(GoalType.workoutWeekly, -1);
      expect(state(args).drafts[GoalType.workoutWeekly]!.text, '2');
      controller(args).setText(GoalType.workoutWeekly, '14');
      controller(args).step(GoalType.workoutWeekly, 1);
      expect(state(args).drafts[GoalType.workoutWeekly]!.text, '14');
      expect(state(args).dirty, isTrue);
    });

    test('an unusable text steps from the saved value', () async {
      final args = await open();
      controller(args).setText(GoalType.focusMinutes, 'abc');
      controller(args).step(GoalType.focusMinutes, 1);
      expect(state(args).drafts[GoalType.focusMinutes]!.text, '30');
    });
  });

  group('target weight (immediate)', () {
    test('is stored at once and creates no goal version', () async {
      final args = await open();
      final before = (await versions.all()).length;
      controller(args).setTargetWeightText('68,0');
      final result = await controller(args).submit() as GoalsSaved;
      expect(result.goalsSaved, isFalse);
      expect(result.targetSaved, isTrue);
      expect(result.message, 'Zielgewicht gespeichert. Es gilt sofort.');
      expect((await stored()).targetWeightGrams, 68000);
      expect((await versions.all()).length, before);
      expect(state(args).targetWeightText, '68,0');
      expect(state(args).dirty, isFalse);
    });

    test('goals and target weight in one save say when each applies', () async {
      final args = await open();
      controller(args)
        ..setText(GoalType.water, '3000')
        ..setTargetWeightText('70.5');
      final result = await controller(args).submit() as GoalsSaved;
      expect(result.message, contains('ab morgen'));
      expect(result.message, contains('Zielgewicht sofort'));
      expect((await stored()).targetWeightGrams, 70500);
      expect((await versionOn(GoalType.water, tomorrow))!.target, 3000);
    });

    test('the other profile values stay as they are', () async {
      await container
          .read(profileCommandsProvider)
          .update(
            commandId: 'seed',
            displayName: 'Max',
            heightCm: 180,
            ageYears: 22,
            startWeightGrams: 74000,
          );
      final args = await open();
      controller(args).setTargetWeightText('68,0');
      await controller(args).submit();
      final profile = await stored();
      expect(profile.displayName, 'Max');
      expect(profile.heightCm, 180);
      expect(profile.ageYears, 22);
      expect(profile.startWeightGrams, 74000);
      expect(profile.targetWeightGrams, 68000);
    });

    test('an empty field removes the target', () async {
      await container
          .read(profileCommandsProvider)
          .update(commandId: 'seed', targetWeightGrams: 68000);
      final args = await open();
      expect(state(args).targetWeightText, '68,0');
      controller(args).setTargetWeightText('');
      expect(await controller(args).submit(), isA<GoalsSaved>());
      expect((await stored()).targetWeightGrams, isNull);
    });

    test('rejects 19,9, 350,1 and 71,55 and keeps the text', () async {
      final args = await open();
      for (final bad in ['19,9', '350,1', '71,55', 'abc']) {
        controller(args).setTargetWeightText(bad);
        expect(await controller(args).submit(), isA<GoalsRejected>());
        expect(state(args).fieldErrors.keys, [
          ProfileFields.targetWeight,
        ], reason: bad);
        expect(state(args).targetWeightText, bad);
      }
      expect((await stored()).targetWeightGrams, isNull);
    });

    test(
      'accepts both limits and a target equal to the start (AT09)',
      () async {
        for (final ok in ['20,0', '350,0']) {
          final args = await open();
          controller(args).setTargetWeightText(ok);
          expect(
            await controller(args).submit(),
            isA<GoalsSaved>(),
            reason: ok,
          );
        }
        await container
            .read(profileCommandsProvider)
            .update(commandId: 'start', startWeightGrams: 74000);
        final args = await open();
        controller(args).setTargetWeightText('74,0');
        await controller(args).submit();
        final profile = await stored();
        expect(profile.targetWeightGrams, profile.startWeightGrams);
      },
    );

    test(
      'plus and minus step 0,1 kg from the typed value, start or last weight',
      () async {
        final args = await open(latest: 71500);
        controller(args).stepTargetWeight(1);
        expect(
          state(args).targetWeightText,
          '71,6',
          reason: 'last measurement',
        );
        controller(args).stepTargetWeight(-1);
        controller(args).stepTargetWeight(-1);
        expect(state(args).targetWeightText, '71,4');

        final none = await open();
        controller(none).stepTargetWeight(1);
        expect(
          state(none).targetWeightText,
          isEmpty,
          reason: 'nothing to start from',
        );
      },
    );
  });

  group('start weight proposal (W02)', () {
    Future<void> measure(int grams) async {
      await container
          .read(weightRepositoryProvider)
          .create(
            commandId: harness.ids.newId(),
            draft: WeightDraft(
              weightGrams: grams,
              occurredAtUtc: harness.clock.nowUtc(),
            ),
          );
    }

    test(
      'setting a target proposes the latest measurement, nothing is applied',
      () async {
        await measure(71500);
        final args = await open(latest: 71500);
        expect(state(args).proposal, isNull);
        controller(args).setTargetWeightText('68,0');
        expect(state(args).proposal!.grams, 71500);
        expect(state(args).acceptedStartGrams, isNull);

        await controller(args).submit();
        final profile = await stored();
        expect(profile.targetWeightGrams, 68000);
        expect(profile.startWeightGrams, isNull, reason: 'not confirmed');
      },
    );

    test('after the confirmation the start weight is saved, the measurement is not touched', () async {
      await measure(71500);
      final args = await open(latest: 71500);
      controller(args).setTargetWeightText('68,0');
      controller(args).acceptStartWeightProposal();
      expect(state(args).acceptedStartGrams, 71500);
      expect(state(args).dirty, isTrue);

      expect(await controller(args).submit(), isA<GoalsSaved>());
      final profile = await stored();
      expect(profile.startWeightGrams, 71500);
      expect(profile.targetWeightGrams, 68000);
      final entries = await container
          .read(weightRepositoryProvider)
          .watchActive()
          .first;
      expect(
        entries,
        hasLength(1),
        reason: 'profile data is not a measurement',
      );
      expect(entries.single.weightGrams, 71500);
    });

    test('no proposal without a measurement, with a start weight, or without a target', () async {
      final none = await open();
      controller(none).setTargetWeightText('68,0');
      expect(state(none).proposal, isNull);

      await container
          .read(profileCommandsProvider)
          .update(commandId: 'start', startWeightGrams: 74000);
      final withStart = await open(latest: 71500);
      controller(withStart).setTargetWeightText('68,0');
      expect(state(withStart).proposal, isNull);
    });

    test(
      'a confirmed proposal is dropped when the target is cleared again',
      () async {
        final args = await open(latest: 71500);
        controller(args).setTargetWeightText('68,0');
        controller(args).acceptStartWeightProposal();
        controller(args).setTargetWeightText('');
        expect(state(args).proposal, isNull);
        expect(state(args).acceptedStartGrams, isNull);
        expect(state(args).dirty, isFalse);
      },
    );
  });

  group('failures and retries', () {
    test('a failed save keeps the input; the retry reuses both ids', () async {
      final args = await open();
      controller(args)
        ..setText(GoalType.water, '3000')
        ..setTargetWeightText('68,0');
      projection.failure = StateError('disk full');

      expect(await controller(args).submit(), isA<GoalsRejected>());
      expect(state(args).submitFailure, isA<StorageFailure>());
      expect(state(args).submitting, isFalse);
      expect(state(args).drafts[GoalType.water]!.text, '3000');
      expect(state(args).targetWeightText, '68,0');
      expect(await versionOn(GoalType.water, tomorrow), isNull);

      projection.failure = null;
      final result = await controller(args).submit() as GoalsSaved;
      expect(result.goalsSaved && result.targetSaved, isTrue);
      expect(goalCommands.commandIds, hasLength(2));
      expect(goalCommands.commandIds[0], goalCommands.commandIds[1]);
      expect((await stored()).targetWeightGrams, 68000);
    });

    test(
      'goals saved but target weight failed: the goals count as saved',
      () async {
        final args = await open();
        controller(args)
          ..setText(GoalType.water, '3000')
          ..setTargetWeightText('68,0');
        profileCommands.failure = const StorageFailure(causeType: 'StateError');

        final result = await controller(args).submit();
        expect(result, isA<GoalsRejected>());
        expect((result as GoalsRejected).goalsSaved, isTrue);
        expect((await versionOn(GoalType.water, tomorrow))!.target, 3000);
        expect(state(args).targetWeightText, '68,0');
        expect(state(args).dirty, isTrue, reason: 'the target is still open');

        profileCommands.failure = null;
        final retry = await controller(args).submit() as GoalsSaved;
        expect(retry.goalsSaved, isFalse, reason: 'goals are not sent again');
        expect(retry.targetSaved, isTrue);
        expect(goalCommands.commandIds, hasLength(1));
        expect((await stored()).targetWeightGrams, 68000);
        expect(state(args).dirty, isFalse);
      },
    );

    test('a second tap while saving is ignored (submit lock)', () async {
      final args = await open();
      controller(args).setText(GoalType.water, '3000');
      final results = await Future.wait([
        controller(args).submit(),
        controller(args).submit(),
      ]);
      expect(results.whereType<GoalsSaved>(), hasLength(1));
      expect(results.whereType<GoalsRejected>(), hasLength(1));
      expect(goalCommands.commandIds, hasLength(1));
    });
  });
}
