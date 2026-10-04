import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/body/data/weight_repository.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/domain/weight_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late RecordingProjectionSynchronizer projection;
  late WeightRepository repository;

  setUp(() async {
    projection = RecordingProjectionSynchronizer();
    harness = await DataHarness.create(projections: projection);
    repository = WeightRepository(
      database: harness.database,
      runner: harness.runner,
    );
  });
  tearDown(() => harness.dispose());

  // "now" is 2026-10-03 08:00Z = 10:00 in Berlin.
  DateTime at(int hour, [int minute = 0, int day = 3]) =>
      DateTime.utc(2026, 10, day, hour, minute);

  WeightDraft draft({
    int grams = 71500,
    DateTime? when,
    bool toilet = false,
    bool drinking = false,
    bool eating = false,
    String? note,
  }) => WeightDraft(
    weightGrams: grams,
    occurredAtUtc: when ?? at(7),
    beforeToilet: toilet,
    afterDrinking: drinking,
    afterEating: eating,
    note: note,
  );

  Future<String> create(WeightDraft d, {String? commandId}) async {
    final outcome = await repository.create(
      commandId: commandId ?? harness.ids.newId(),
      draft: d,
    );
    return outcome.entityId!;
  }

  Future<List<WeightEntry>> all() => repository.watchActive().first;

  group('create (AT06)', () {
    test(
      'stores grams, conditions, note and the frozen business date',
      () async {
        final id = await create(
          draft(toilet: true, drinking: true, note: '  nach dem Aufstehen  '),
        );
        final entry = (await repository.findById(id))!;
        expect(entry.weightGrams, 71500);
        expect(entry.occurredAtUtc, at(7));
        expect(entry.localDate, LocalDate(2026, 10, 3));
        expect(entry.timezoneId, 'Europe/Berlin');
        expect(entry.beforeToilet, isTrue);
        expect(entry.afterDrinking, isTrue);
        expect(entry.afterEating, isFalse);
        expect(entry.isFasted, isFalse, reason: 'drinking was flagged');
        expect(entry.note, 'nach dem Aufstehen', reason: 'note is trimmed');
        expect(entry.rowVersion, 1);
      },
    );

    test('all conditions start off; fasted is derived', () async {
      final id = await create(draft());
      final entry = (await repository.findById(id))!;
      expect(
        entry.beforeToilet || entry.afterDrinking || entry.afterEating,
        isFalse,
      );
      expect(entry.isFasted, isTrue);
    });

    test('a blank note is stored as no note', () async {
      final id = await create(draft(note: '   '));
      expect((await repository.findById(id))!.note, isNull);
    });

    test(
      'the business date is frozen in the zone at the time of the event',
      () async {
        // 22:30Z on 2026-10-03 is already 2026-10-04 in Berlin.
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 45));
        final id = await create(draft(when: DateTime.utc(2026, 10, 3, 22, 30)));
        expect(
          (await repository.findById(id))!.localDate,
          LocalDate(2026, 10, 4),
        );
        harness.clock.setTimeZone('America/New_York');
        expect(
          (await repository.findById(id))!.localDate,
          LocalDate(2026, 10, 4),
          reason: 'travel never moves existing records',
        );
      },
    );

    test(
      'syncs the projection for the affected day inside the command',
      () async {
        await create(draft());
        expect(projection.syncs, [
          {LocalDate(2026, 10, 3)},
        ]);
      },
    );

    test(
      'the same command id is one record, a new id a new record (AT12)',
      () async {
        final first = await repository.create(commandId: 'c1', draft: draft());
        final replay = await repository.create(commandId: 'c1', draft: draft());
        expect(replay.replayed, isTrue);
        expect(replay.entityId, first.entityId);
        expect(await all(), hasLength(1));
        await repository.create(
          commandId: 'c2',
          draft: draft(when: at(7, 30)),
        );
        expect(await all(), hasLength(2));
      },
    );

    test(
      'eligibility is frozen from the gamification state at creation (AT26)',
      () async {
        final eligibleId = await create(draft(when: at(6)));
        await harness.database
            .into(harness.database.moduleStatusHistory)
            .insert(
              ModuleStatusHistoryCompanion.insert(
                id: 'off',
                moduleId: ModuleId.gamification.key,
                effectiveAtUtc: harness.clock.nowUtc(),
                localDate: LocalDate(2026, 10, 3),
                enabled: false,
              ),
            );
        final notEligibleId = await create(draft(when: at(7)));
        expect(
          (await repository.findById(eligibleId))!.gamificationEligible,
          isTrue,
        );
        expect(
          (await repository.findById(notEligibleId))!.gamificationEligible,
          isFalse,
        );
      },
    );
  });

  group('validation (AT05 boundaries at the repository)', () {
    Future<ValidationFailure> failure(WeightDraft d) async {
      try {
        await create(d);
      } on ValidationFailure catch (error) {
        return error;
      }
      fail('expected a ValidationFailure');
    }

    test('weight must be 20,0 to 350,0 kg in 0,1 steps', () async {
      for (final bad in [19900, 350100, 71550, 71501, 0, -100]) {
        expect(
          (await failure(draft(grams: bad))).fieldErrors.keys,
          contains(WeightFields.weight),
          reason: '$bad g',
        );
      }
      await create(draft(grams: 20000, when: at(1)));
      await create(draft(grams: 350000, when: at(2)));
    });

    test('measurement time must not be in the future', () async {
      final error = await failure(draft(when: at(8, 1)));
      expect(error.fieldErrors[WeightFields.measuredAt], contains('Zukunft'));
      await create(draft(when: at(8)));
    });

    test('measurement time must not be before 2000-01-01 (Berlin)', () async {
      // 1999-12-31T22:59Z is 1999-12-31 23:59 in Berlin; 23:00Z is 2000-01-01.
      final error = await failure(
        draft(when: DateTime.utc(1999, 12, 31, 22, 59)),
      );
      expect(
        error.fieldErrors[WeightFields.measuredAt],
        contains('01.01.2000'),
      );
      await create(draft(when: DateTime.utc(1999, 12, 31, 23, 0)));
    });

    test('note is limited to 500 characters after trimming', () async {
      expect(
        (await failure(draft(note: 'x' * 501))).fieldErrors.keys,
        contains(WeightFields.note),
      );
      await create(draft(note: 'x' * 500));
    });

    test(
      'a rejected draft leaves no record, no receipt and no projection call',
      () async {
        await failure(draft(grams: 10));
        expect(await all(), isEmpty);
        expect(
          await harness.database.select(harness.database.commandReceipts).get(),
          isEmpty,
        );
        expect(projection.syncs, isEmpty);
      },
    );

    test('several errors are reported together', () async {
      final error = await failure(
        draft(grams: 10, when: at(9), note: 'x' * 501),
      );
      expect(
        error.fieldErrors.keys,
        containsAll([
          WeightFields.weight,
          WeightFields.measuredAt,
          WeightFields.note,
        ]),
      );
    });
  });

  group('same measurement time (AT07)', () {
    test('a second entry at the exact same time is refused and offers the existing one', () async {
      final firstId = await create(draft(when: at(7)));
      await expectLater(
        repository.create(
          commandId: 'dup',
          draft: draft(when: at(7), grams: 72000),
        ),
        throwsA(
          isA<ConflictFailure>()
              .having((f) => f.kind, 'kind', ConflictKind.duplicateMeasurement)
              .having((f) => f.relatedEntityId, 'related', firstId),
        ),
      );
      expect(await all(), hasLength(1));
      expect(
        await harness.database.select(harness.database.commandReceipts).get(),
        hasLength(1),
        reason: 'only the successful first command left a receipt',
      );
    });

    test('a different time on the same day is allowed', () async {
      await create(draft(when: at(7)));
      await create(draft(when: at(7, 1)));
      await create(draft(when: at(8)));
      expect(await all(), hasLength(3));
    });

    test('after deleting, the time is free again', () async {
      final id = await create(draft(when: at(7)));
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await create(draft(when: at(7), grams: 72000));
      expect(await all(), hasLength(1));
    });
  });

  group('update', () {
    test('changes values, bumps the version and keeps eligibility', () async {
      final id = await create(draft(note: 'alt'));
      final before = (await repository.findById(id))!;
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(grams: 71200, eating: true, note: 'neu'),
        expectedRowVersion: before.rowVersion,
      );
      final after = (await repository.findById(id))!;
      expect(after.weightGrams, 71200);
      expect(after.afterEating, isTrue);
      expect(after.note, 'neu');
      expect(after.rowVersion, before.rowVersion + 1);
      expect(after.gamificationEligible, before.gamificationEligible);
    });

    test('a note edit never moves the frozen date or zone', () async {
      harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 45));
      final id = await create(draft(when: DateTime.utc(2026, 10, 3, 22, 30)));
      harness.clock.setTimeZone('America/New_York');
      final before = (await repository.findById(id))!;
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: WeightDraft(
          weightGrams: before.weightGrams,
          occurredAtUtc: before.occurredAtUtc,
          note: 'nur Notiz',
        ),
        expectedRowVersion: before.rowVersion,
      );
      final after = (await repository.findById(id))!;
      expect(after.localDate, LocalDate(2026, 10, 4));
      expect(after.timezoneId, 'Europe/Berlin');
    });

    test(
      'moving the time to another day re-freezes the date and syncs both days',
      () async {
        final id = await create(draft(when: at(7)));
        projection.syncs.clear();
        final before = (await repository.findById(id))!;
        await repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(when: at(7, 0, 1)),
          expectedRowVersion: before.rowVersion,
        );
        expect(
          (await repository.findById(id))!.localDate,
          LocalDate(2026, 10, 1),
        );
        expect(projection.syncs.single, {
          LocalDate(2026, 10, 3),
          LocalDate(2026, 10, 1),
        });
      },
    );

    test('a stale form version is a conflict and changes nothing', () async {
      final id = await create(draft());
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(grams: 70000),
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
      expect((await repository.findById(id))!.weightGrams, 71500);
    });

    test('moving onto another entry\'s time is a duplicate conflict, own time is fine', () async {
      final a = await create(draft(when: at(6)));
      await create(draft(when: at(7)));
      final entryA = (await repository.findById(a))!;
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: a,
          draft: draft(when: at(7)),
          expectedRowVersion: entryA.rowVersion,
        ),
        throwsA(
          isA<ConflictFailure>().having(
            (f) => f.kind,
            'kind',
            ConflictKind.duplicateMeasurement,
          ),
        ),
      );
      await repository.update(
        commandId: harness.ids.newId(),
        id: a,
        draft: draft(when: at(6), grams: 70000),
        expectedRowVersion: entryA.rowVersion,
      );
    });

    test('a missing entry is NotFound', () async {
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: 'missing',
          draft: draft(),
          expectedRowVersion: 1,
        ),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('delete and undo', () {
    test('delete is soft and the entry disappears from active reads', () async {
      final id = await create(draft());
      final outcome = await repository.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      expect(await all(), isEmpty);
      expect(await repository.findById(id), isNull);
      final row = await (harness.database.select(
        harness.database.weightEntries,
      )..where((w) => w.id.equals(id))).getSingle();
      expect(row.deletedAtUtc, isNotNull, reason: 'soft delete keeps the row');
      expect(outcome.undo, isNotNull);
    });

    test('undoing a delete restores the SAME id with its data', () async {
      final id = await create(draft(note: 'bleibt'));
      final outcome = await repository.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      await outcome.undo!.run(harness.ids.newId());
      final restored = (await repository.findById(id))!;
      expect(restored.id, id);
      expect(restored.weightGrams, 71500);
      expect(restored.note, 'bleibt');
    });

    test(
      'undoing a delete is refused if the entry changed meanwhile',
      () async {
        final id = await create(draft());
        final outcome = await repository.delete(
          commandId: harness.ids.newId(),
          id: id,
        );
        await (harness.database.update(harness.database.weightEntries)
              ..where((w) => w.id.equals(id)))
            .write(const WeightEntriesCompanion(rowVersion: Value(50)));
        await expectLater(
          outcome.undo!.run(harness.ids.newId()),
          throwsA(
            isA<ConflictFailure>().having(
              (f) => f.kind,
              'kind',
              ConflictKind.staleVersion,
            ),
          ),
        );
        expect(await repository.findById(id), isNull);
      },
    );

    test(
      'undoing a delete is refused if the time was taken meanwhile',
      () async {
        final id = await create(draft(when: at(7)));
        final outcome = await repository.delete(
          commandId: harness.ids.newId(),
          id: id,
        );
        await create(draft(when: at(7), grams: 72000));
        await expectLater(
          outcome.undo!.run(harness.ids.newId()),
          throwsA(
            isA<ConflictFailure>().having(
              (f) => f.kind,
              'kind',
              ConflictKind.duplicateMeasurement,
            ),
          ),
        );
      },
    );

    test('undoing a create removes that entry', () async {
      final outcome = await repository.create(commandId: 'u1', draft: draft());
      await outcome.undo!.run(harness.ids.newId());
      expect(await all(), isEmpty);
    });

    test('undoing a create after an edit is refused (AT23 style)', () async {
      final created = await repository.create(commandId: 'u1', draft: draft());
      final id = created.entityId!;
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(grams: 70000),
        expectedRowVersion: 1,
      );
      await expectLater(
        created.undo!.run(harness.ids.newId()),
        throwsA(
          isA<ConflictFailure>().having(
            (f) => f.kind,
            'kind',
            ConflictKind.staleVersion,
          ),
        ),
      );
      expect((await repository.findById(id))!.weightGrams, 70000);
    });

    test('undoing an update restores the previous values', () async {
      final id = await create(draft(grams: 71500, note: 'vorher'));
      final entry = (await repository.findById(id))!;
      final outcome = await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(grams: 70000, note: 'nachher', when: at(6)),
        expectedRowVersion: entry.rowVersion,
      );
      await outcome.undo!.run(harness.ids.newId());
      final restored = (await repository.findById(id))!;
      expect(restored.weightGrams, 71500);
      expect(restored.note, 'vorher');
      expect(restored.occurredAtUtc, at(7));
    });

    test('an undo is itself idempotent and is a removal event', () async {
      final created = await repository.create(commandId: 'u1', draft: draft());
      final first = await created.undo!.run('undo-1');
      final second = await created.undo!.run('undo-1');
      expect(first.replayed, isFalse);
      expect(second.replayed, isTrue);
    });
  });

  group('atomicity (AT27)', () {
    test('a failing projection stores no weight, no receipt', () async {
      projection.failure = StateError('disk full');
      await expectLater(
        repository.create(commandId: 'fail', draft: draft()),
        throwsA(isA<StorageFailure>()),
      );
      expect(await all(), isEmpty);
      expect(
        await harness.database.select(harness.database.commandReceipts).get(),
        isEmpty,
      );
      // The retry with the SAME id succeeds once the problem is gone.
      projection.failure = null;
      await repository.create(commandId: 'fail', draft: draft());
      expect(await all(), hasLength(1));
    });
  });

  group('reads', () {
    test('watchActive is newest first and excludes deleted entries', () async {
      final a = await create(draft(when: at(6), grams: 70000));
      await create(draft(when: at(7), grams: 71000));
      final c = await create(draft(when: at(8), grams: 72000));
      await repository.delete(commandId: harness.ids.newId(), id: a);
      final list = await all();
      expect(list.map((e) => e.weightGrams), [72000, 71000]);
      expect(list.first.id, c);
    });

    test('watchById emits null after deletion', () async {
      final id = await create(draft());
      final emissions = <WeightEntry?>[];
      final subscription = repository.watchById(id).listen(emissions.add);
      await Future<void>.delayed(Duration.zero);
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(emissions.first, isNotNull);
      expect(emissions.last, isNull);
    });

    test('data persists as plain database rows (reopen equivalence)', () async {
      await create(draft(grams: 71500, toilet: true));
      final rows = await harness.database
          .select(harness.database.weightEntries)
          .get();
      expect(rows.single.weightGrams, 71500);
      expect(rows.single.beforeToilet, isTrue);
    });
  });
}
