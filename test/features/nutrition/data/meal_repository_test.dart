import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/nutrition/data/meal_repository.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/meal_summary.dart';
import 'package:self_improvement/features/nutrition/domain/meal_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/nutrition_test_kit.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late NutritionKit kit;
  late RecordingProjectionSynchronizer projection;
  late MealRepository repository;

  setUp(() async {
    projection = RecordingProjectionSynchronizer();
    kit = await NutritionKit.create(projections: projection);
    repository = kit.meals;
  });
  tearDown(() => kit.dispose());

  MealDraft draft({
    String name = 'Haferflocken',
    int? kcal,
    DateTime? when,
    String? note,
  }) => MealDraft(
    name: name,
    kcal: kcal,
    occurredAtUtc: when ?? at(6),
    note: note,
  );

  Future<String> create(MealDraft d, {String? commandId}) async {
    final outcome = await repository.create(
      commandId: commandId ?? kit.newId(),
      draft: d,
    );
    return outcome.entityId!;
  }

  Future<MealDay> day([LocalDate? date]) =>
      repository.watchDay(date ?? kitToday).first;

  Future<ValidationFailure> failure(Future<Object?> Function() action) async {
    try {
      await action();
    } on ValidationFailure catch (error) {
      return error;
    }
    fail('expected a ValidationFailure');
  }

  group('create', () {
    test(
      'stores name, calories, time, note and the frozen business date',
      () async {
        final id = await create(
          draft(
            name: '  Müsli mit Beeren ',
            kcal: 420,
            note: '  zum Frühstück ',
          ),
        );
        final meal = (await repository.findById(id))!;
        expect(meal.name, 'Müsli mit Beeren', reason: 'the name is trimmed');
        expect(meal.kcal, 420);
        expect(meal.occurredAtUtc, at(6));
        expect(meal.localDate, LocalDate(2026, 10, 3));
        expect(meal.timezoneId, 'Europe/Berlin');
        expect(meal.note, 'zum Frühstück');
        expect(meal.rowVersion, 1);
      },
    );

    test(
      'calories are optional: not given is stored as no value, not 0 (AT14)',
      () async {
        final id = await create(draft());
        final meal = (await repository.findById(id))!;
        expect(meal.kcal, isNull);
        expect(meal.hasKcal, isFalse);
        final row = (await kit.mealRows()).single;
        expect(row.kcal, isNull, reason: 'NULL in the database, not 0');
      },
    );

    test(
      'a deliberate 0 kcal is stored as 0 and differs from not given',
      () async {
        final zero = await create(draft(kcal: 0, when: at(5)));
        final missing = await create(draft(when: at(6)));
        expect((await repository.findById(zero))!.kcal, 0);
        expect((await repository.findById(zero))!.hasKcal, isTrue);
        expect((await repository.findById(missing))!.kcal, isNull);
      },
    );

    test('no calorie value is derived from the name', () async {
      final id = await create(draft(name: 'Pizza 1200 kcal'));
      expect((await repository.findById(id))!.kcal, isNull);
    });

    test('a blank note is stored as no note', () async {
      final id = await create(draft(note: '  '));
      expect((await repository.findById(id))!.note, isNull);
    });

    test(
      'the business date is frozen in the zone at the time of the event',
      () async {
        kit.harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 45));
        final id = await create(draft(when: DateTime.utc(2026, 10, 3, 22, 30)));
        expect(
          (await repository.findById(id))!.localDate,
          LocalDate(2026, 10, 4),
          reason: '00:30 in Berlin',
        );
        kit.harness.clock.setTimeZone('America/New_York');
        expect(
          (await repository.findById(id))!.localDate,
          LocalDate(2026, 10, 4),
        );
      },
    );

    test(
      'reports the affected day to the projection inside the command',
      () async {
        await create(draft());
        expect(projection.syncs, [
          {LocalDate(2026, 10, 3)},
        ]);
      },
    );

    test(
      'the same command id is one meal, a new id a new meal (AT12)',
      () async {
        final first = await repository.create(commandId: 'c1', draft: draft());
        final replay = await repository.create(commandId: 'c1', draft: draft());
        expect(replay.replayed, isTrue);
        expect(replay.entityId, first.entityId);
        expect((await day()).entriesNewestFirst, hasLength(1));
        await repository.create(commandId: 'c2', draft: draft());
        expect((await day()).entriesNewestFirst, hasLength(2));
      },
    );

    test(
      'there is no uniqueness rule: the same meal twice is two meals',
      () async {
        await create(draft(when: at(6)));
        await create(draft(when: at(6)));
        expect((await day()).entriesNewestFirst, hasLength(2));
      },
    );
  });

  group('validation (boundaries at the repository)', () {
    test(
      'name: 1 and 80 characters are saved, 0 and 81 are rejected',
      () async {
        await create(draft(name: 'x'));
        await create(draft(name: 'a' * 80));
        for (final bad in ['', '   ', 'a' * 81]) {
          final error = await failure(() => create(draft(name: bad)));
          expect(error.fieldErrors.keys, [MealFields.name], reason: '"$bad"');
        }
      },
    );

    test(
      'name: whitespace around is trimmed before the limit applies',
      () async {
        final id = await create(draft(name: ' ${'a' * 80} '));
        expect((await repository.findById(id))!.name, 'a' * 80);
        await failure(() => create(draft(name: ' ${'a' * 81} ')));
      },
    );

    test(
      'calories: 0 and 5000 are saved, 5001 and negatives are rejected',
      () async {
        await create(draft(kcal: 0, when: at(1)));
        await create(draft(kcal: 5000, when: at(2)));
        for (final bad in [5001, -1, 100000]) {
          final error = await failure(() => create(draft(kcal: bad)));
          expect(error.fieldErrors.keys, [MealFields.kcal], reason: '$bad');
        }
        expect((await day()).summary.knownKcal, 5000);
      },
    );

    test('time: not in the future, not before 2000-01-01 (Berlin)', () async {
      final future = await failure(() => create(draft(when: at(8, 1))));
      expect(future.fieldErrors[MealFields.occurredAt], contains('Zukunft'));
      await create(draft(when: at(8)));
      final early = await failure(
        () => create(draft(when: DateTime.utc(1999, 12, 31, 22, 59))),
      );
      expect(early.fieldErrors[MealFields.occurredAt], contains('01.01.2000'));
      await create(draft(when: DateTime.utc(1999, 12, 31, 23)));
    });

    test('note: 500 characters are saved, 501 are rejected', () async {
      final error = await failure(() => create(draft(note: 'x' * 501)));
      expect(error.fieldErrors.keys, [MealFields.note]);
      final id = await create(draft(note: 'x' * 500));
      expect((await repository.findById(id))!.note, 'x' * 500);
    });

    test('a rejected draft leaves no meal, no receipt and no sync', () async {
      await failure(() => create(draft(name: '')));
      expect((await day()).isEmpty, isTrue);
      expect(await kit.receipts(), isEmpty);
      expect(projection.syncs, isEmpty);
    });

    test('several errors are reported together', () async {
      final error = await failure(
        () => create(draft(name: '', kcal: 9999, when: at(9), note: 'x' * 501)),
      );
      expect(
        error.fieldErrors.keys,
        unorderedEquals([
          MealFields.name,
          MealFields.kcal,
          MealFields.occurredAt,
          MealFields.note,
        ]),
      );
    });
  });

  group('update', () {
    test('changes values, bumps the version and keeps creation data', () async {
      final id = await create(draft(kcal: 400, note: 'alt'));
      final before = (await repository.findById(id))!;
      await repository.update(
        commandId: kit.newId(),
        id: id,
        draft: draft(name: 'Porridge', kcal: 350, note: 'neu'),
        expectedRowVersion: before.rowVersion,
      );
      final after = (await repository.findById(id))!;
      expect(after.name, 'Porridge');
      expect(after.kcal, 350);
      expect(after.note, 'neu');
      expect(after.rowVersion, before.rowVersion + 1);
      expect(after.createdAtUtc, before.createdAtUtc);
    });

    test(
      'calories can be removed again (back to not given) or set to 0',
      () async {
        final id = await create(draft(kcal: 400));
        await repository.update(
          commandId: kit.newId(),
          id: id,
          draft: draft(),
          expectedRowVersion: 1,
        );
        expect((await repository.findById(id))!.kcal, isNull);
        await repository.update(
          commandId: kit.newId(),
          id: id,
          draft: draft(kcal: 0),
          expectedRowVersion: 2,
        );
        expect((await repository.findById(id))!.kcal, 0);
      },
    );

    test('a name or note edit never moves the frozen date or zone', () async {
      kit.harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 45));
      final id = await create(draft(when: DateTime.utc(2026, 10, 3, 22, 30)));
      kit.harness.clock.setTimeZone('America/New_York');
      final before = (await repository.findById(id))!;
      await repository.update(
        commandId: kit.newId(),
        id: id,
        draft: MealDraft(
          name: 'Nur umbenannt',
          occurredAtUtc: before.occurredAtUtc,
        ),
        expectedRowVersion: before.rowVersion,
      );
      final after = (await repository.findById(id))!;
      expect(after.localDate, LocalDate(2026, 10, 4));
      expect(after.timezoneId, 'Europe/Berlin');
    });

    test(
      'moving the time across midnight re-freezes the date and syncs both days',
      () async {
        kit.harness.clock.setNow(DateTime.utc(2026, 10, 3, 23));
        final id = await create(
          draft(kcal: 500, when: DateTime.utc(2026, 10, 3, 21, 30)),
        );
        await create(draft(kcal: 200, when: DateTime.utc(2026, 10, 3, 21, 0)));
        projection.syncs.clear();
        await repository.update(
          commandId: kit.newId(),
          id: id,
          draft: draft(kcal: 500, when: DateTime.utc(2026, 10, 3, 22, 30)),
          expectedRowVersion: 1,
        );
        expect(projection.syncs.single, {
          LocalDate(2026, 10, 3),
          LocalDate(2026, 10, 4),
        });
        final oct3 = await day(LocalDate(2026, 10, 3));
        final oct4 = await day(LocalDate(2026, 10, 4));
        expect(oct3.summary.mealCount, 1);
        expect(oct3.summary.knownKcal, 200);
        expect(oct4.summary.mealCount, 1);
        expect(oct4.summary.knownKcal, 500);
      },
    );

    test('a stale form version is a conflict and changes nothing', () async {
      final id = await create(draft());
      await expectLater(
        repository.update(
          commandId: kit.newId(),
          id: id,
          draft: draft(name: 'Anders'),
          expectedRowVersion: 99,
        ),
        throwsA(
          isA<ConflictFailure>().having(
            (f) => f.kind,
            'kind',
            ConflictKind.staleVersion,
          ),
        ),
      );
      expect((await repository.findById(id))!.name, 'Haferflocken');
    });

    test('an invalid edit is rejected and changes nothing', () async {
      final id = await create(draft(kcal: 300));
      final error = await failure(
        () => repository.update(
          commandId: kit.newId(),
          id: id,
          draft: draft(kcal: 5001),
          expectedRowVersion: 1,
        ),
      );
      expect(error.fieldErrors.keys, [MealFields.kcal]);
      final unchanged = (await repository.findById(id))!;
      expect(unchanged.kcal, 300);
      expect(unchanged.rowVersion, 1);
    });

    test('a missing or deleted meal is NotFound', () async {
      await expectLater(
        repository.update(
          commandId: kit.newId(),
          id: 'missing',
          draft: draft(),
          expectedRowVersion: 1,
        ),
        throwsA(isA<NotFoundFailure>()),
      );
      final id = await create(draft());
      await repository.delete(commandId: kit.newId(), id: id);
      await expectLater(
        repository.update(
          commandId: kit.newId(),
          id: id,
          draft: draft(),
          expectedRowVersion: 2,
        ),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('delete and undo', () {
    test(
      'delete is soft and the meal disappears from the day and its sum',
      () async {
        final id = await create(draft(kcal: 300));
        await create(draft(kcal: 200, when: at(5)));
        final outcome = await repository.delete(commandId: kit.newId(), id: id);
        final model = await day();
        expect(model.summary.mealCount, 1);
        expect(model.summary.knownKcal, 200);
        expect(await repository.findById(id), isNull);
        final row = await (kit.database.select(
          kit.database.mealEntries,
        )..where((m) => m.id.equals(id))).getSingle();
        expect(
          row.deletedAtUtc,
          isNotNull,
          reason: 'soft delete keeps the row',
        );
        expect(outcome.undo, isNotNull);
      },
    );

    test('undoing a delete restores the SAME id with all its data', () async {
      final id = await create(draft(kcal: 0, note: 'bleibt'));
      final outcome = await repository.delete(commandId: kit.newId(), id: id);
      await outcome.undo!.run(kit.newId());
      final restored = (await repository.findById(id))!;
      expect(restored.id, id);
      expect(restored.kcal, 0, reason: 'a deliberate 0 survives');
      expect(restored.note, 'bleibt');
    });

    test('undoing a delete is refused if the meal changed meanwhile', () async {
      final id = await create(draft());
      final outcome = await repository.delete(commandId: kit.newId(), id: id);
      await (kit.database.update(kit.database.mealEntries)
            ..where((m) => m.id.equals(id)))
          .write(const MealEntriesCompanion(rowVersion: Value(50)));
      await expectLater(
        outcome.undo!.run(kit.newId()),
        throwsA(
          isA<ConflictFailure>().having(
            (f) => f.kind,
            'kind',
            ConflictKind.staleVersion,
          ),
        ),
      );
      expect(await repository.findById(id), isNull);
    });

    test('undoing a create removes that meal', () async {
      final outcome = await repository.create(commandId: 'u1', draft: draft());
      await outcome.undo!.run(kit.newId());
      expect((await day()).isEmpty, isTrue);
    });

    test(
      'undoing a create after an edit is refused, the edit survives',
      () async {
        final created = await repository.create(
          commandId: 'u1',
          draft: draft(),
        );
        final id = created.entityId!;
        await repository.update(
          commandId: kit.newId(),
          id: id,
          draft: draft(name: 'Bearbeitet'),
          expectedRowVersion: 1,
        );
        await expectLater(
          created.undo!.run(kit.newId()),
          throwsA(
            isA<ConflictFailure>().having(
              (f) => f.kind,
              'kind',
              ConflictKind.staleVersion,
            ),
          ),
        );
        expect((await repository.findById(id))!.name, 'Bearbeitet');
      },
    );

    test(
      'undoing an update restores values, calories and the original day',
      () async {
        kit.harness.clock.setNow(DateTime.utc(2026, 10, 3, 23));
        final id = await create(
          draft(
            name: 'Vorher',
            kcal: 300,
            note: 'vorher',
            when: DateTime.utc(2026, 10, 3, 21, 30),
          ),
        );
        final outcome = await repository.update(
          commandId: kit.newId(),
          id: id,
          draft: draft(
            name: 'Nachher',
            note: 'nachher',
            when: DateTime.utc(2026, 10, 3, 22, 30),
          ),
          expectedRowVersion: 1,
        );
        expect((await repository.findById(id))!.kcal, isNull);
        projection.syncs.clear();
        await outcome.undo!.run(kit.newId());
        final restored = (await repository.findById(id))!;
        expect(restored.name, 'Vorher');
        expect(restored.kcal, 300);
        expect(restored.note, 'vorher');
        expect(restored.localDate, LocalDate(2026, 10, 3));
        expect(projection.syncs.single, {
          LocalDate(2026, 10, 3),
          LocalDate(2026, 10, 4),
        });
      },
    );

    test('an undo is itself idempotent', () async {
      final created = await repository.create(commandId: 'u1', draft: draft());
      final first = await created.undo!.run('undo-1');
      final second = await created.undo!.run('undo-1');
      expect(first.replayed, isFalse);
      expect(second.replayed, isTrue);
    });
  });

  group('atomicity (AT27)', () {
    test('a failing projection stores no meal and no receipt, a retry with the same id works', () async {
      projection.failure = StateError('disk full');
      await expectLater(
        repository.create(commandId: 'fail', draft: draft(kcal: 300)),
        throwsA(isA<StorageFailure>()),
      );
      expect(await kit.mealRows(), isEmpty);
      expect(await kit.receipts(), isEmpty);

      projection.failure = null;
      await repository.create(commandId: 'fail', draft: draft(kcal: 300));
      expect((await day()).entriesNewestFirst, hasLength(1));
      expect(await kit.receipts(), hasLength(1));
    });
  });

  group('day summary through the repository (AT14)', () {
    test('no meals: none, no calorie sum', () async {
      final model = await day();
      expect(model.isEmpty, isTrue);
      expect(model.summary.completeness, KcalCompleteness.none);
      expect(model.summary.knownKcal, isNull);
    });

    test('a meal without calories: incomplete and NO invented value', () async {
      await create(draft());
      final summary = (await day()).summary;
      expect(summary.mealCount, 1);
      expect(summary.completeness, KcalCompleteness.incomplete);
      expect(summary.knownKcal, isNull, reason: 'never a 0 kcal claim');
    });

    test('all with calories: complete; one more without: incomplete', () async {
      await create(draft(kcal: 400, when: at(5)));
      await create(draft(kcal: 600, when: at(6)));
      var summary = (await day()).summary;
      expect(summary.completeness, KcalCompleteness.complete);
      expect(summary.knownKcal, 1000);
      await create(draft(when: at(7)));
      summary = (await day()).summary;
      expect(summary.completeness, KcalCompleteness.incomplete);
      expect(summary.knownKcal, 1000, reason: 'the known part stays');
      expect(summary.mealCount, 3);
    });

    test('a deliberate 0 counts as given, missing does not', () async {
      await create(draft(kcal: 0));
      var summary = (await day()).summary;
      expect(summary.completeness, KcalCompleteness.complete);
      expect(summary.knownKcal, 0);
      await create(draft(when: at(7)));
      summary = (await day()).summary;
      expect(summary.completeness, KcalCompleteness.incomplete);
      expect(summary.knownKcal, 0);
    });

    test(
      'deleting the only meal without calories makes the day empty again',
      () async {
        final id = await create(draft());
        await repository.delete(commandId: kit.newId(), id: id);
        expect((await day()).summary.completeness, KcalCompleteness.none);
      },
    );
  });

  group('reads', () {
    test(
      'watchDay: only the stored local day, newest first, deleted excluded',
      () async {
        await create(draft(name: 'a', when: at(5)));
        await create(draft(name: 'b', when: at(7)));
        await create(draft(name: 'c', when: at(6)));
        await create(
          draft(name: 'other day', when: DateTime.utc(2026, 10, 2, 9)),
        );
        final gone = await create(draft(name: 'gone', when: at(4)));
        await repository.delete(commandId: kit.newId(), id: gone);
        final model = await day();
        expect(model.entriesNewestFirst.map((m) => m.name), ['b', 'c', 'a']);
      },
    );

    test('Berlin day boundary: 22:30Z belongs to the next local day', () async {
      kit.harness.clock.setNow(DateTime.utc(2026, 10, 4, 6));
      await create(
        draft(name: 'late', when: DateTime.utc(2026, 10, 3, 21, 59)),
      );
      await create(
        draft(name: 'midnight', when: DateTime.utc(2026, 10, 3, 22)),
      );
      await create(
        draft(name: 'after', when: DateTime.utc(2026, 10, 3, 22, 30)),
      );
      expect(
        (await day(LocalDate(2026, 10, 3))).entriesNewestFirst
            .map((m) => m.name),
        ['late'],
      );
      expect(
        (await day(LocalDate(2026, 10, 4))).entriesNewestFirst
            .map((m) => m.name),
        ['after', 'midnight'],
      );
    });

    test('watchDay re-emits after changes and not for equal data', () async {
      final models = <MealDay>[];
      final subscription = repository.watchDay(kitToday).listen(models.add);
      await pumpUntil(() => models.isNotEmpty, reason: 'initial model');
      expect(models.last.isEmpty, isTrue);
      final id = await create(draft(kcal: 300));
      await pumpUntil(() => models.last.summary.mealCount == 1, reason: 'add');
      await repository.update(
        commandId: kit.newId(),
        id: id,
        draft: draft(kcal: 350),
        expectedRowVersion: 1,
      );
      await pumpUntil(
        () => models.last.summary.knownKcal == 350,
        reason: 'edit',
      );
      await repository.delete(commandId: kit.newId(), id: id);
      await pumpUntil(() => models.last.isEmpty, reason: 'delete');
      await subscription.cancel();
    });

    test(
      'watchHistory groups the last N days, newest first, each summarised',
      () async {
        await create(draft(kcal: 400, when: DateTime.utc(2026, 9, 20, 9)));
        await create(draft(kcal: 300, when: DateTime.utc(2026, 10, 2, 9)));
        await create(draft(when: at(5)));
        await create(draft(kcal: 100, when: at(6)));
        await create(
          draft(when: DateTime.utc(2026, 9, 19, 9)),
        ); // outside 14 days
        final history = await repository
            .watchHistory(today: kitToday, days: 14)
            .first;
        expect(history.daysNewestFirst.map((d) => d.date), [
          LocalDate(2026, 10, 3),
          LocalDate(2026, 10, 2),
          LocalDate(2026, 9, 20),
        ]);
        expect(
          history.daysNewestFirst.first.summary.completeness,
          KcalCompleteness.incomplete,
        );
        expect(history.daysNewestFirst.first.summary.knownKcal, 100);
        expect(
          history.daysNewestFirst[1].summary.completeness,
          KcalCompleteness.complete,
        );
      },
    );

    test('a window shorter than one day is a programming error', () {
      expect(
        () => repository.watchHistory(today: kitToday, days: 0),
        throwsArgumentError,
      );
    });

    test(
      'findBetween returns the active meals of the period, newest first',
      () async {
        await create(draft(name: 'a', when: DateTime.utc(2026, 10, 1, 9)));
        await create(draft(name: 'b', when: DateTime.utc(2026, 10, 2, 9)));
        await create(draft(name: 'c', when: at(6)));
        final gone = await create(draft(name: 'gone', when: at(5)));
        await repository.delete(commandId: kit.newId(), id: gone);
        await create(draft(name: 'outside', when: DateTime.utc(2026, 9, 1, 9)));
        final meals = await repository.findBetween(
          LocalDate(2026, 10, 1),
          LocalDate(2026, 10, 3),
        );
        expect(meals.map((m) => m.name), ['c', 'b', 'a']);
        expect(summarizeMeals(meals).mealCount, 3);
      },
    );

    test('watchById emits null after deletion', () async {
      final id = await create(draft());
      final emissions = <MealEntry?>[];
      final subscription = repository.watchById(id).listen(emissions.add);
      await pumpUntil(() => emissions.isNotEmpty, reason: 'first emission');
      await repository.delete(commandId: kit.newId(), id: id);
      await pumpUntil(
        () => emissions.last == null,
        reason: 'null after delete',
      );
      await subscription.cancel();
      expect(emissions.first, isNotNull);
    });
  });

  group('meals earn no XP and are no goal (real projection)', () {
    late NutritionKit real;

    setUp(() async {
      real = await NutritionKit.create(realProjection: true, onboarded: true);
    });
    tearDown(() => real.dispose());

    test(
      'creating, editing and deleting meals never changes XP or the ring',
      () async {
        final meals = real.meals;
        final created = await meals.create(
          commandId: real.newId(),
          draft: draft(kcal: 400, when: at(5)),
        );
        await meals.create(
          commandId: real.newId(),
          draft: draft(when: at(6)),
        );
        await meals.update(
          commandId: real.newId(),
          id: created.entityId!,
          draft: draft(kcal: 450, when: at(5)),
          expectedRowVersion: 1,
        );
        expect(await real.harness.totalXp(), 0);
        expect(await real.awards(), isEmpty);
        final status = (await real.harness.dayStatusRepository().statusFor(
          kitToday,
        ))!;
        expect(status.fulfilledCount, 0, reason: 'meals are not a goal');
        expect(
          status.goals.map((g) => g.goalKey),
          isNot(contains('nutrition')),
          reason: 'there is no calorie or meal goal',
        );
        final deleted = await meals.delete(
          commandId: real.newId(),
          id: created.entityId!,
        );
        await deleted.undo!.run(real.newId());
        expect(await real.harness.totalXp(), 0);
      },
    );

    test('a meal does not make the day active for the streak', () async {
      await real.meals.create(commandId: real.newId(), draft: draft(kcal: 400));
      final status = (await real.harness.dayStatusRepository().statusFor(
        kitToday,
      ))!;
      expect(status.isActive, isFalse);
    });

    test('meals next to water: only the water is rewarded', () async {
      await real.meals.create(commandId: real.newId(), draft: draft(kcal: 400));
      await real.water.quickAdd(commandId: real.newId(), amountMl: 250);
      expect(await real.harness.totalXp(), 5);
      expect(await real.awardKeys('water'), hasLength(1));
    });

    test(
      'a failing projection stores no meal (AT27 with the real projection)',
      () async {
        final failing = FlakyProjection(real.harness.projections);
        final flaky = MealRepository(
          database: real.database,
          runner: buildRunner(real.harness, failing),
        );
        failing.failAfterSync = StateError('disk full');
        await expectLater(
          flaky.create(commandId: 'fail', draft: draft()),
          throwsA(isA<StorageFailure>()),
        );
        expect(await real.mealRows(), isEmpty);
        failing.failAfterSync = null;
        await flaky.create(commandId: 'fail', draft: draft());
        expect(await real.mealRows(), hasLength(1));
      },
    );
  });
}
