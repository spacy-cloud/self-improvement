import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/profile/profile_commands.dart';
import 'package:self_improvement/core/profile/profile_repository.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';
import 'package:self_improvement/core/testing/data_harness.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late ProfileCommands commands;
  late ProfileRepository repository;

  setUp(() async {
    harness = await DataHarness.create();
    commands = ProfileCommands(
      database: harness.database,
      runner: harness.runner,
    );
    repository = ProfileRepository(harness.database);
  });
  tearDown(() => harness.dispose());

  Future<void> update({
    String? name,
    int? height,
    int? age,
    int? start,
    int? target,
    Iterable<String>? goals,
  }) => commands.update(
    commandId: harness.ids.newId(),
    displayName: name,
    heightCm: height,
    ageYears: age,
    startWeightGrams: start,
    targetWeightGrams: target,
    motivationGoals: goals,
  );

  test('stores all voluntary values and bumps the version', () async {
    await update(
      name: '  Mia Muster ',
      height: 170,
      age: 30,
      start: 74000,
      target: 68000,
      goals: ['move_more', 'move_more', 'get_fitter'],
    );
    final p = (await repository.get())!;
    expect(p.displayName, 'Mia Muster');
    expect(p.heightCm, 170);
    expect(p.ageYears, 30);
    expect(p.startWeightGrams, 74000);
    expect(p.targetWeightGrams, 68000);
    expect(p.motivationGoals, ['move_more', 'get_fitter']);
    expect(p.rowVersion, 2);
  });

  test(
    'an empty name means no name and optional values can be cleared',
    () async {
      await update(name: 'Mia', height: 170, age: 30, start: 74000);
      await update(name: '   ');
      final p = (await repository.get())!;
      expect(p.displayName, isNull);
      expect(p.effectiveName, 'Mia'.isEmpty ? '' : 'Mein Profil');
      expect(p.heightCm, isNull);
      expect(p.ageYears, isNull);
      expect(p.startWeightGrams, isNull);
    },
  );

  test('the editor without goals keeps the stored preferences', () async {
    await update(goals: ['build_habits']);
    await update(name: 'Mia');
    expect((await repository.get())!.motivationGoals, ['build_habits']);
  });

  group('boundaries', () {
    Future<void> rejects(Future<void> Function() call, String field) async {
      await expectLater(
        call(),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.fieldErrors.keys,
            'fields',
            contains(field),
          ),
        ),
      );
    }

    test('name 40 ok, 41 rejected', () async {
      await update(name: 'x' * 40);
      await rejects(() => update(name: 'x' * 41), ProfileFields.displayName);
    });

    test('height 100-250', () async {
      await update(height: 100);
      await update(height: 250);
      await rejects(() => update(height: 99), ProfileFields.heightCm);
      await rejects(() => update(height: 251), ProfileFields.heightCm);
    });

    test('age 18-120', () async {
      await update(age: 18);
      await update(age: 120);
      await rejects(() => update(age: 17), ProfileFields.ageYears);
      await rejects(() => update(age: 121), ProfileFields.ageYears);
    });

    test('weights 20,0-350,0 kg in 0,1 steps', () async {
      await update(start: 20000, target: 350000);
      await rejects(() => update(start: 19900), ProfileFields.startWeight);
      await rejects(() => update(target: 350100), ProfileFields.targetWeight);
      await rejects(() => update(target: 70050), ProfileFields.targetWeight);
    });

    test(
      'unknown preferences are rejected and a failure stores nothing',
      () async {
        await update(name: 'Mia');
        await rejects(
          () => update(name: 'Neu', goals: ['become_famous']),
          ProfileFields.motivationGoals,
        );
        expect((await repository.get())!.displayName, 'Mia');
      },
    );
  });

  test('a missing profile is not found', () async {
    await harness.database.delete(harness.database.profile).go();
    await expectLater(update(name: 'x'), throwsA(isA<NotFoundFailure>()));
  });
}
