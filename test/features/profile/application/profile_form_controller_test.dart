import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/profile/application/profile_form_controller.dart';

import '../support/flaky_projection.dart';
import '../support/recording_commands.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late FlakyProjection projection;
  late RecordingProfileCommands commands;
  late ProviderContainer container;

  ProviderContainer newContainer() => harness.createContainer(
    overrides: [profileCommandsProvider.overrideWithValue(commands)],
  );

  setUp(() async {
    projection = FlakyProjection();
    harness = await DataHarness.create(projections: projection);
    await harness.seedOnboarded();
    commands = RecordingProfileCommands(
      database: harness.database,
      runner: harness.runner,
    );
    container = newContainer();
  });
  tearDown(() => harness.dispose());

  Future<UserProfile> stored() async =>
      (await container.read(profileRepositoryProvider).get())!;

  Future<ProfileFormArgs> open({bool bodyVisible = true}) async {
    final args = ProfileFormArgs(await stored(), bodyVisible: bodyVisible);
    // Keep the auto-disposed form alive like its screen does.
    final subscription = container.listen(profileFormProvider(args), (_, _) {});
    addTearDown(subscription.close);
    return args;
  }

  ProfileFormController controller(ProfileFormArgs args) =>
      container.read(profileFormProvider(args).notifier);

  ProfileFormState state(ProfileFormArgs args) =>
      container.read(profileFormProvider(args));

  Future<void> fillAll(ProfileFormArgs args) async {
    controller(args)
      ..setName('Max Mustermann')
      ..setHeight('180')
      ..setAge('22')
      ..setStartWeight('74,0')
      ..setTargetWeight('68,0');
  }

  group('a new editor', () {
    test('shows the stored values, is clean and has no errors', () async {
      final args = await open();
      final s = state(args);
      expect(s.dirty, isFalse);
      expect(s.fieldErrors, isEmpty);
      expect(s.submitting, isFalse);
      expect(s.input.name, isEmpty, reason: 'no name stored, no default text');
      expect(s.input.heightText, isEmpty);
    });

    test('opening and saving without a change writes nothing', () async {
      final args = await open();
      final before = (await stored()).rowVersion;
      final result = await controller(args).submit();
      expect(result, isA<ProfileUnchanged>());
      expect((await stored()).rowVersion, before);
      expect(commands.commandIds, isEmpty);
    });
  });

  group('saving', () {
    test('stores every value, trimmed and normalised (AT02)', () async {
      final args = await open();
      controller(args)
        ..setName('  Max Mustermann  ')
        ..setHeight('180')
        ..setAge('22')
        ..setStartWeight('74.0')
        ..setTargetWeight('68,0');
      final result = await controller(args).submit();
      expect(result, isA<ProfileSaved>());
      expect((result as ProfileSaved).message, 'Profil gespeichert');
      final profile = await stored();
      expect(profile.displayName, 'Max Mustermann');
      expect(profile.heightCm, 180);
      expect(profile.ageYears, 22);
      expect(profile.startWeightGrams, 74000);
      expect(profile.targetWeightGrams, 68000);
      expect(state(args).dirty, isFalse, reason: 'saved input is the baseline');
    });

    test('the target weight is valid immediately, not from tomorrow', () async {
      final args = await open();
      controller(args).setTargetWeight('68,0');
      await controller(args).submit();
      // Same fake day: nothing has to advance for the value to apply.
      expect((await stored()).targetWeightGrams, 68000);
    });

    test('an optional profile stays empty and can be emptied again', () async {
      final args = await open();
      await fillAll(args);
      await controller(args).submit();

      final second = await open();
      controller(second)
        ..setName('   ')
        ..setHeight('')
        ..setAge('')
        ..setStartWeight('')
        ..setTargetWeight('');
      final result = await controller(second).submit();
      expect(result, isA<ProfileSaved>());
      final profile = await stored();
      expect(profile.displayName, isNull);
      expect(profile.effectiveName, 'Mein Profil');
      expect(profile.initials, isNull);
      expect(profile.heightCm, isNull);
      expect(profile.ageYears, isNull);
      expect(profile.startWeightGrams, isNull);
      expect(profile.targetWeightGrams, isNull);
    });

    test('profile values never become weight measurements (W02)', () async {
      final args = await open();
      controller(args)
        ..setStartWeight('74,0')
        ..setTargetWeight('68,0');
      await controller(args).submit();
      final entries = await container
          .read(weightRepositoryProvider)
          .watchActive()
          .first;
      expect(entries, isEmpty);
    });

    test('the saved profile survives a restart (AT02)', () async {
      final args = await open();
      await fillAll(args);
      await controller(args).submit();

      container = newContainer(); // a new process over the same database
      final reopened = await open();
      expect(state(reopened).input.name, 'Max Mustermann');
      expect(state(reopened).input.heightText, '180');
      expect(state(reopened).input.targetWeightText, '68,0');
      expect(state(reopened).dirty, isFalse);
    });

    test('a hidden body section keeps its stored values', () async {
      final first = await open();
      await fillAll(first);
      await controller(first).submit();

      final args = await open(bodyVisible: false);
      controller(args)
        ..setName('Neuer Name')
        ..setHeight('999'); // would be invalid; the section is hidden
      final result = await controller(args).submit();
      expect(result, isA<ProfileSaved>());
      final profile = await stored();
      expect(profile.displayName, 'Neuer Name');
      expect(profile.heightCm, 180);
      expect(profile.startWeightGrams, 74000);
      expect(profile.targetWeightGrams, 68000);
    });
  });

  group('validation keeps the input', () {
    test('invalid fields write nothing and are all reported', () async {
      final args = await open();
      final before = (await stored()).rowVersion;
      controller(args)
        ..setName('Max')
        ..setHeight('99')
        ..setAge('17')
        ..setStartWeight('19,9')
        ..setTargetWeight('350,1');
      final result = await controller(args).submit();
      expect(result, isA<ProfileRejected>());
      final s = state(args);
      expect(s.fieldErrors.keys.toSet(), {
        ProfileFields.heightCm,
        ProfileFields.ageYears,
        ProfileFields.startWeight,
        ProfileFields.targetWeight,
      });
      expect(s.input.name, 'Max', reason: 'the input stays');
      expect(s.input.heightText, '99');
      expect(s.input.targetWeightText, '350,1');
      expect(s.dirty, isTrue);
      expect(s.submitting, isFalse);
      expect((await stored()).rowVersion, before);
      expect(commands.commandIds, isEmpty, reason: 'nothing was sent');
    });

    test('editing a field clears only its own error', () async {
      final args = await open();
      controller(args)
        ..setHeight('99')
        ..setAge('17');
      await controller(args).submit();
      expect(state(args).fieldErrors, hasLength(2));
      controller(args).setHeight('180');
      expect(state(args).fieldErrors.keys, [ProfileFields.ageYears]);
    });

    test('after the fix the same form saves', () async {
      final args = await open();
      controller(args).setHeight('99');
      await controller(args).submit();
      controller(args).setHeight('180');
      final result = await controller(args).submit();
      expect(result, isA<ProfileSaved>());
      expect((await stored()).heightCm, 180);
    });

    test('a name of 41 characters is rejected, 40 are saved', () async {
      final args = await open();
      controller(args).setName('n' * 41);
      expect(await controller(args).submit(), isA<ProfileRejected>());
      expect(state(args).fieldErrors.keys, [ProfileFields.displayName]);
      controller(args).setName('n' * 40);
      expect(await controller(args).submit(), isA<ProfileSaved>());
      expect((await stored()).displayName, 'n' * 40);
    });
  });

  group('cancelling', () {
    test('an edit makes the form dirty, undoing it makes it clean', () async {
      final args = await open();
      controller(args).setName('Max');
      expect(state(args).dirty, isTrue);
      controller(args).setName('');
      expect(state(args).dirty, isFalse, reason: 'nothing to discard');
    });

    test(
      'leaving a dirty form without saving leaves the profile alone',
      () async {
        final args = await open();
        final before = await stored();
        controller(args)
          ..setName('Verworfen')
          ..setHeight('190');
        // The screen drops the form when the user confirms "Verwerfen".
        container.invalidate(profileFormProvider(args));
        final after = await stored();
        expect(after.displayName, before.displayName);
        expect(after.heightCm, before.heightCm);
        expect(after.rowVersion, before.rowVersion);
        expect(state(args).dirty, isFalse);
      },
    );
  });

  group('failures and retries', () {
    test(
      'a failed commit rolls back, keeps the input; retry reuses the id',
      () async {
        final args = await open();
        final before = (await stored()).rowVersion;
        controller(args)
          ..setName('Max')
          ..setHeight('180');
        projection.failure = StateError('disk full');

        final failed = await controller(args).submit();
        expect(failed, isA<ProfileRejected>());
        expect(state(args).submitFailure, isA<StorageFailure>());
        expect(state(args).submitting, isFalse);
        expect(state(args).input.name, 'Max');
        expect(state(args).input.heightText, '180');
        expect(state(args).dirty, isTrue);
        final unchanged = await stored();
        expect(unchanged.displayName, isNull, reason: 'rolled back');
        expect(unchanged.rowVersion, before);

        projection.failure = null;
        final retried = await controller(args).submit();
        expect(retried, isA<ProfileSaved>());
        expect(state(args).submitFailure, isNull);
        expect(commands.commandIds, hasLength(2));
        expect(commands.commandIds[0], commands.commandIds[1]);
        final saved = await stored();
        expect(saved.displayName, 'Max');
        expect(saved.rowVersion, before + 1, reason: 'saved exactly once');
      },
    );

    test('changed content gets a new command id', () async {
      final args = await open();
      controller(args).setName('Max');
      projection.failure = StateError('disk full');
      await controller(args).submit();
      controller(args).setName('Maxi');
      await controller(args).submit();
      expect(commands.commandIds[0], isNot(commands.commandIds[1]));
    });

    test('a new action after a success gets a new command id', () async {
      final args = await open();
      controller(args).setName('Max');
      await controller(args).submit();
      controller(args).setName('Maxi');
      await controller(args).submit();
      expect(commands.commandIds[0], isNot(commands.commandIds[1]));
    });

    test('a second tap while saving is ignored (submit lock)', () async {
      final args = await open();
      controller(args).setName('Max');
      final first = controller(args).submit();
      final second = controller(args).submit();
      final results = await Future.wait([first, second]);
      expect(results.whereType<ProfileSaved>(), hasLength(1));
      expect(results.whereType<ProfileRejected>(), hasLength(1));
      expect(commands.commandIds, hasLength(1), reason: 'one command only');
      expect((await stored()).rowVersion, 2);
    });

    test(
      'a failure reported by the command layer keeps the input too',
      () async {
        final args = await open();
        controller(args).setName('Max');
        commands.failure = const ConflictFailure(ConflictKind.invalidState);
        final result = await controller(args).submit();
        expect(result, isA<ProfileRejected>());
        expect(state(args).submitFailure, isA<ConflictFailure>());
        expect(state(args).input.name, 'Max');
      },
    );
  });
}
