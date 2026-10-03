import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/nutrition/data/water_repository.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/nutrition_test_kit.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late NutritionKit kit;
  late RecordingProjectionSynchronizer projection;
  late WaterRepository repository;

  setUp(() async {
    projection = RecordingProjectionSynchronizer();
    kit = await NutritionKit.create(projections: projection);
    repository = kit.water;
  });
  tearDown(() => kit.dispose());

  WaterDraft draft({int ml = 250, DateTime? when, String? note}) =>
      WaterDraft(amountMl: ml, occurredAtUtc: when ?? at(7), note: note);

  Future<String> create(WaterDraft d, {String? commandId}) async {
    final outcome = await repository.create(
      commandId: commandId ?? kit.newId(),
      draft: d,
    );
    return outcome.entityId!;
  }

  /// All active entries of the harness day, newest first.
  Future<List<WaterEntry>> today() async =>
      (await repository.loadToday(kitToday)).entriesNewestFirst;

  Future<ValidationFailure> failure(Future<Object?> Function() action) async {
    try {
      await action();
    } on ValidationFailure catch (error) {
      return error;
    }
    fail('expected a ValidationFailure');
  }

  group('quick add (250 / 500 ml)', () {
    test(
      'creates a real entry NOW in one command, with the frozen day',
      () async {
        final outcome = await repository.quickAdd(
          commandId: 'tap-1',
          amountMl: 250,
        );
        final entry = (await repository.findById(outcome.entityId!))!;
        expect(entry.amountMl, 250);
        expect(entry.occurredAtUtc, at(8), reason: 'the clock now');
        expect(entry.localDate, LocalDate(2026, 10, 3));
        expect(entry.timezoneId, 'Europe/Berlin');
        expect(entry.note, isNull);
        expect(entry.rowVersion, 1);
        expect(entry.gamificationEligible, isTrue);
        expect(outcome.undo, isNotNull, reason: 'the snackbar needs the undo');
        expect(outcome.replayed, isFalse);
      },
    );

    test(
      'is exactly ONE command: one receipt and one projection sync',
      () async {
        await repository.quickAdd(commandId: 'tap-1', amountMl: 500);
        final receipts = await kit.receipts();
        expect(receipts, hasLength(1));
        expect(receipts.single.commandId, 'tap-1');
        expect(receipts.single.commandType, WaterRepository.quickAddType);
        expect(projection.syncs, [
          {LocalDate(2026, 10, 3)},
        ]);
      },
    );

    test('250 and 500 ml are two entries that add up (AT10 amounts)', () async {
      await repository.quickAdd(commandId: 'a', amountMl: 250);
      kit.harness.clock.advance(const Duration(minutes: 1));
      await repository.quickAdd(commandId: 'b', amountMl: 500);
      final model = await repository.loadToday(kitToday);
      expect(model.totalMl, 750);
      expect(model.entriesNewestFirst.map((e) => e.amountMl), [500, 250]);
    });

    test(
      'two quick taps are two entries, even in the same instant (AT12)',
      () async {
        await repository.quickAdd(commandId: 'tap-1', amountMl: 250);
        await repository.quickAdd(commandId: 'tap-2', amountMl: 250);
        expect(await today(), hasLength(2));
        expect((await repository.loadToday(kitToday)).totalMl, 500);
      },
    );

    test(
      'the SAME command id is one entry, the replay does nothing (AT12)',
      () async {
        final first = await repository.quickAdd(
          commandId: 'tap-1',
          amountMl: 250,
        );
        final replay = await repository.quickAdd(
          commandId: 'tap-1',
          amountMl: 250,
        );
        expect(replay.replayed, isTrue);
        expect(replay.entityId, first.entityId);
        expect(replay.undo, isNull);
        expect(await today(), hasLength(1));
        expect(await kit.receipts(), hasLength(1));
        expect(projection.syncs, hasLength(1), reason: 'no second sync');
      },
    );

    test(
      'a replay ignores a different amount: the first tap decided',
      () async {
        await repository.quickAdd(commandId: 'tap-1', amountMl: 250);
        await repository.quickAdd(commandId: 'tap-1', amountMl: 500);
        final entries = await today();
        expect(entries.single.amountMl, 250);
      },
    );

    test(
      'amounts 49 and 2001 are rejected, 50 and 2000 are accepted',
      () async {
        for (final bad in [49, 2001, 0, -250]) {
          final error = await failure(
            () => repository.quickAdd(commandId: 'bad-$bad', amountMl: bad),
          );
          expect(error.fieldErrors.keys, [WaterFields.amount], reason: '$bad');
        }
        expect(await today(), isEmpty);
        expect(await kit.receipts(), isEmpty);
        expect(projection.syncs, isEmpty);

        await repository.quickAdd(commandId: 'min', amountMl: 50);
        await repository.quickAdd(commandId: 'max', amountMl: 2000);
        expect((await repository.loadToday(kitToday)).totalMl, 2050);
      },
    );

    test(
      'the business date is frozen in the zone at the time of the tap',
      () async {
        // 22:30Z on 2026-10-03 is already 2026-10-04 in Berlin.
        kit.harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 30));
        final outcome = await repository.quickAdd(
          commandId: 't',
          amountMl: 250,
        );
        final entry = (await repository.findById(outcome.entityId!))!;
        expect(entry.localDate, LocalDate(2026, 10, 4));
        kit.harness.clock.setTimeZone('America/New_York');
        expect(
          (await repository.findById(outcome.entityId!))!.localDate,
          LocalDate(2026, 10, 4),
          reason: 'travel never moves existing entries',
        );
      },
    );
  });

  group('create (custom amount)', () {
    test(
      'stores amount, time, trimmed note and the frozen business date',
      () async {
        final id = await create(draft(ml: 300, note: '  nach dem Sport  '));
        final entry = (await repository.findById(id))!;
        expect(entry.amountMl, 300);
        expect(entry.occurredAtUtc, at(7));
        expect(entry.localDate, LocalDate(2026, 10, 3));
        expect(entry.timezoneId, 'Europe/Berlin');
        expect(entry.note, 'nach dem Sport');
        expect(entry.rowVersion, 1);
      },
    );

    test('a blank note is stored as no note', () async {
      final id = await create(draft(note: '   '));
      expect((await repository.findById(id))!.note, isNull);
    });

    test('back-dated entries keep their own day', () async {
      final id = await create(draft(when: DateTime.utc(2026, 9, 20, 5, 30)));
      final entry = (await repository.findById(id))!;
      expect(entry.localDate, LocalDate(2026, 9, 20));
      expect(entry.occurredAtUtc, DateTime.utc(2026, 9, 20, 5, 30));
    });

    test('Berlin day boundary: 22:30Z belongs to the NEXT local day', () async {
      kit.harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 45));
      final before = await create(
        draft(when: DateTime.utc(2026, 10, 3, 21, 59)),
      );
      final after = await create(draft(when: DateTime.utc(2026, 10, 3, 22, 0)));
      final later = await create(
        draft(when: DateTime.utc(2026, 10, 3, 22, 30)),
      );
      expect(
        (await repository.findById(before))!.localDate,
        LocalDate(2026, 10, 3),
        reason: '23:59 in Berlin',
      );
      expect(
        (await repository.findById(after))!.localDate,
        LocalDate(2026, 10, 4),
        reason: '00:00 in Berlin',
      );
      expect(
        (await repository.findById(later))!.localDate,
        LocalDate(2026, 10, 4),
        reason: '00:30 in Berlin',
      );
    });

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
      'the same command id is one entry, a new id a new entry (AT12)',
      () async {
        final first = await repository.create(commandId: 'c1', draft: draft());
        final replay = await repository.create(commandId: 'c1', draft: draft());
        expect(replay.replayed, isTrue);
        expect(replay.entityId, first.entityId);
        expect(await today(), hasLength(1));
        await repository.create(commandId: 'c2', draft: draft());
        expect(await today(), hasLength(2));
      },
    );

    test(
      'there is no uniqueness rule: two drinks at one instant are two entries',
      () async {
        await create(draft(when: at(7)));
        await create(draft(when: at(7)));
        expect(await today(), hasLength(2));
      },
    );

    test(
      'eligibility is frozen from the gamification state at creation',
      () async {
        final eligible = await create(draft(when: at(6)));
        await kit.database
            .into(kit.database.moduleStatusHistory)
            .insert(
              ModuleStatusHistoryCompanion.insert(
                id: 'off',
                moduleId: ModuleId.gamification.key,
                effectiveAtUtc: kit.harness.clock.nowUtc(),
                localDate: LocalDate(2026, 10, 3),
                enabled: false,
              ),
            );
        final notEligible = await create(draft(when: at(7)));
        final viaQuickAdd = (await repository.quickAdd(
          commandId: 'q',
          amountMl: 250,
        )).entityId!;
        expect(
          (await repository.findById(eligible))!.gamificationEligible,
          isTrue,
        );
        expect(
          (await repository.findById(notEligible))!.gamificationEligible,
          isFalse,
        );
        expect(
          (await repository.findById(viaQuickAdd))!.gamificationEligible,
          isFalse,
        );
      },
    );
  });

  group('validation (boundaries at the repository)', () {
    test('amount: 49 and 2001 are rejected, 50 and 2000 are saved', () async {
      for (final bad in [49, 2001, 0, -1]) {
        final error = await failure(() => create(draft(ml: bad)));
        expect(error.fieldErrors.keys, contains(WaterFields.amount));
      }
      await create(draft(ml: 50, when: at(1)));
      await create(draft(ml: 2000, when: at(2)));
      expect((await repository.loadToday(kitToday)).totalMl, 2050);
    });

    test('time: not in the future, now is fine', () async {
      final error = await failure(() => create(draft(when: at(8, 1))));
      expect(error.fieldErrors[WaterFields.occurredAt], contains('Zukunft'));
      await create(draft(when: at(8)));
    });

    test('time: not before 2000-01-01 (Berlin)', () async {
      final error = await failure(
        () => create(draft(when: DateTime.utc(1999, 12, 31, 22, 59))),
      );
      expect(error.fieldErrors[WaterFields.occurredAt], contains('01.01.2000'));
      await create(draft(when: DateTime.utc(1999, 12, 31, 23)));
    });

    test('note: 500 characters are saved, 501 are rejected', () async {
      final error = await failure(() => create(draft(note: 'x' * 501)));
      expect(error.fieldErrors.keys, contains(WaterFields.note));
      final id = await create(draft(note: 'x' * 500));
      expect((await repository.findById(id))!.note, 'x' * 500);
    });

    test('a rejected draft leaves no entry, no receipt and no sync', () async {
      await failure(() => create(draft(ml: 10)));
      expect(await today(), isEmpty);
      expect(await kit.receipts(), isEmpty);
      expect(projection.syncs, isEmpty);
    });

    test('several errors are reported together', () async {
      final error = await failure(
        () => create(draft(ml: 10, when: at(9), note: 'x' * 501)),
      );
      expect(
        error.fieldErrors.keys,
        unorderedEquals([
          WaterFields.amount,
          WaterFields.occurredAt,
          WaterFields.note,
        ]),
      );
    });
  });

  group('update', () {
    test('changes values, bumps the version and keeps eligibility', () async {
      final id = await create(draft(note: 'alt'));
      final before = (await repository.findById(id))!;
      await repository.update(
        commandId: kit.newId(),
        id: id,
        draft: draft(ml: 400, when: at(7), note: 'neu'),
        expectedRowVersion: before.rowVersion,
      );
      final after = (await repository.findById(id))!;
      expect(after.amountMl, 400);
      expect(after.note, 'neu');
      expect(after.rowVersion, before.rowVersion + 1);
      expect(after.gamificationEligible, before.gamificationEligible);
      expect(after.createdAtUtc, before.createdAtUtc);
    });

    test(
      'an amount or note edit never moves the frozen date or zone',
      () async {
        kit.harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 45));
        final id = await create(draft(when: DateTime.utc(2026, 10, 3, 22, 30)));
        kit.harness.clock.setTimeZone('America/New_York');
        final before = (await repository.findById(id))!;
        await repository.update(
          commandId: kit.newId(),
          id: id,
          draft: WaterDraft(
            amountMl: 300,
            occurredAtUtc: before.occurredAtUtc,
            note: 'nur Menge',
          ),
          expectedRowVersion: before.rowVersion,
        );
        final after = (await repository.findById(id))!;
        expect(after.localDate, LocalDate(2026, 10, 4));
        expect(after.timezoneId, 'Europe/Berlin');
      },
    );

    test(
      'moving the time across midnight re-freezes the date and syncs both days',
      () async {
        // 21:30Z is 23:30 in Berlin on the 3rd; 22:30Z is 00:30 on the 4th.
        kit.harness.clock.setNow(DateTime.utc(2026, 10, 3, 23));
        final id = await create(
          draft(ml: 300, when: DateTime.utc(2026, 10, 3, 21, 30)),
        );
        await create(draft(ml: 200, when: DateTime.utc(2026, 10, 3, 21, 0)));
        projection.syncs.clear();
        final before = (await repository.findById(id))!;
        await repository.update(
          commandId: kit.newId(),
          id: id,
          draft: draft(ml: 300, when: DateTime.utc(2026, 10, 3, 22, 30)),
          expectedRowVersion: before.rowVersion,
        );
        expect(
          (await repository.findById(id))!.localDate,
          LocalDate(2026, 10, 4),
        );
        expect(projection.syncs.single, {
          LocalDate(2026, 10, 3),
          LocalDate(2026, 10, 4),
        });
        final oct3 = await repository.loadToday(LocalDate(2026, 10, 3));
        final oct4 = await repository.loadToday(LocalDate(2026, 10, 4));
        expect(oct3.totalMl, 200, reason: 'the day total lost the moved entry');
        expect(oct4.totalMl, 300, reason: 'the day total gained it');
      },
    );

    test('a stale form version is a conflict and changes nothing', () async {
      final id = await create(draft());
      await expectLater(
        repository.update(
          commandId: kit.newId(),
          id: id,
          draft: draft(ml: 999),
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
      expect((await repository.findById(id))!.amountMl, 250);
    });

    test('an invalid edit is rejected and changes nothing', () async {
      final id = await create(draft());
      final error = await failure(
        () => repository.update(
          commandId: kit.newId(),
          id: id,
          draft: draft(ml: 2001),
          expectedRowVersion: 1,
        ),
      );
      expect(error.fieldErrors.keys, [WaterFields.amount]);
      final unchanged = (await repository.findById(id))!;
      expect(unchanged.amountMl, 250);
      expect(unchanged.rowVersion, 1);
    });

    test('a missing or deleted entry is NotFound', () async {
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
      'delete is soft and the entry disappears from the day total',
      () async {
        final id = await create(draft(ml: 300));
        await create(draft(ml: 200, when: at(6)));
        final outcome = await repository.delete(commandId: kit.newId(), id: id);
        expect((await repository.loadToday(kitToday)).totalMl, 200);
        expect(await repository.findById(id), isNull);
        final row = await (kit.database.select(
          kit.database.waterEntries,
        )..where((w) => w.id.equals(id))).getSingle();
        expect(
          row.deletedAtUtc,
          isNotNull,
          reason: 'soft delete keeps the row',
        );
        expect(outcome.undo, isNotNull);
        expect(projection.syncs.last, {LocalDate(2026, 10, 3)});
      },
    );

    test(
      'deleting twice with the same id is a replay, with a new id NotFound',
      () async {
        final id = await create(draft());
        await repository.delete(commandId: 'd1', id: id);
        final replay = await repository.delete(commandId: 'd1', id: id);
        expect(replay.replayed, isTrue);
        await expectLater(
          repository.delete(commandId: 'd2', id: id),
          throwsA(isA<NotFoundFailure>()),
        );
      },
    );

    test('undoing a delete restores the SAME id with its data', () async {
      final id = await create(draft(ml: 300, note: 'bleibt'));
      final outcome = await repository.delete(commandId: kit.newId(), id: id);
      await outcome.undo!.run(kit.newId());
      final restored = (await repository.findById(id))!;
      expect(restored.id, id);
      expect(restored.amountMl, 300);
      expect(restored.note, 'bleibt');
      expect((await repository.loadToday(kitToday)).totalMl, 300);
    });

    test(
      'undoing a delete is refused if the entry changed meanwhile',
      () async {
        final id = await create(draft());
        final outcome = await repository.delete(commandId: kit.newId(), id: id);
        await (kit.database.update(kit.database.waterEntries)
              ..where((w) => w.id.equals(id)))
            .write(const WaterEntriesCompanion(rowVersion: Value(50)));
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
      },
    );

    test('undoing a create removes that entry', () async {
      final outcome = await repository.create(commandId: 'u1', draft: draft());
      await outcome.undo!.run(kit.newId());
      expect(await today(), isEmpty);
    });

    test('undoing a quick add removes that entry', () async {
      final outcome = await repository.quickAdd(commandId: 'q1', amountMl: 250);
      await outcome.undo!.run(kit.newId());
      expect(await today(), isEmpty);
      expect((await repository.loadToday(kitToday)).totalMl, 0);
    });

    test(
      'undoing a create after an edit is refused: the edit is not overwritten',
      () async {
        final created = await repository.create(
          commandId: 'u1',
          draft: draft(),
        );
        final id = created.entityId!;
        await repository.update(
          commandId: kit.newId(),
          id: id,
          draft: draft(ml: 400),
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
        expect((await repository.findById(id))!.amountMl, 400);
      },
    );

    test('undoing a create after the entry was deleted is NotFound', () async {
      final created = await repository.create(commandId: 'u1', draft: draft());
      await repository.delete(commandId: kit.newId(), id: created.entityId!);
      await expectLater(
        created.undo!.run(kit.newId()),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test(
      'undoing an update restores amount, note and the original day',
      () async {
        kit.harness.clock.setNow(DateTime.utc(2026, 10, 3, 23));
        final id = await create(
          draft(
            ml: 300,
            note: 'vorher',
            when: DateTime.utc(2026, 10, 3, 21, 30),
          ),
        );
        final entry = (await repository.findById(id))!;
        projection.syncs.clear();
        final outcome = await repository.update(
          commandId: kit.newId(),
          id: id,
          draft: draft(
            ml: 700,
            note: 'nachher',
            when: DateTime.utc(2026, 10, 3, 22, 30),
          ),
          expectedRowVersion: entry.rowVersion,
        );
        expect(
          (await repository.findById(id))!.localDate,
          LocalDate(2026, 10, 4),
        );
        projection.syncs.clear();
        await outcome.undo!.run(kit.newId());
        final restored = (await repository.findById(id))!;
        expect(restored.amountMl, 300);
        expect(restored.note, 'vorher');
        expect(restored.occurredAtUtc, DateTime.utc(2026, 10, 3, 21, 30));
        expect(restored.localDate, LocalDate(2026, 10, 3));
        expect(projection.syncs.single, {
          LocalDate(2026, 10, 3),
          LocalDate(2026, 10, 4),
        }, reason: 'both days are re-synced when an undo moves the entry back');
      },
    );

    test('an undo is itself idempotent', () async {
      final created = await repository.create(commandId: 'u1', draft: draft());
      final first = await created.undo!.run('undo-1');
      final second = await created.undo!.run('undo-1');
      expect(first.replayed, isFalse);
      expect(second.replayed, isTrue);
    });

    test('deleting and undoing alternately keeps the version moving', () async {
      final id = await create(draft());
      final deleted = await repository.delete(commandId: kit.newId(), id: id);
      await deleted.undo!.run(kit.newId());
      expect((await repository.findById(id))!.rowVersion, 3);
    });
  });

  group('atomicity (AT27)', () {
    test('a failing projection stores no entry and no receipt, a retry with the same id works', () async {
      projection.failure = StateError('disk full');
      await expectLater(
        repository.quickAdd(commandId: 'fail', amountMl: 250),
        throwsA(isA<StorageFailure>()),
      );
      expect(await kit.waterRows(), isEmpty);
      expect(await kit.receipts(), isEmpty);

      projection.failure = null;
      await repository.quickAdd(commandId: 'fail', amountMl: 250);
      expect(await today(), hasLength(1));
      expect(await kit.receipts(), hasLength(1));
    });

    test(
      'a failing create and a failing delete leave the data as it was',
      () async {
        final id = await create(draft());
        projection.failure = StateError('disk full');
        await expectLater(
          repository.create(commandId: 'x', draft: draft(ml: 400)),
          throwsA(isA<StorageFailure>()),
        );
        await expectLater(
          repository.delete(commandId: 'y', id: id),
          throwsA(isA<StorageFailure>()),
        );
        projection.failure = null;
        final entries = await today();
        expect(entries, hasLength(1));
        expect(entries.single.rowVersion, 1);
      },
    );
  });

  group('reads', () {
    test('watchById emits null after deletion', () async {
      final id = await create(draft());
      final emissions = <WaterEntry?>[];
      final subscription = repository.watchById(id).listen(emissions.add);
      await pumpUntil(() => emissions.isNotEmpty, reason: 'first emission');
      await repository.delete(commandId: kit.newId(), id: id);
      await pumpUntil(
        () => emissions.last == null,
        reason: 'null after delete',
      );
      await subscription.cancel();
      expect(emissions.first, isNotNull);
      expect(emissions.last, isNull);
    });

    test('data persists as plain database rows', () async {
      await create(draft(ml: 300, note: 'n'));
      final rows = await kit.waterRows();
      expect(rows.single.amountMl, 300);
      expect(rows.single.note, 'n');
      expect(rows.single.deletedAtUtc, isNull);
    });
  });
}
