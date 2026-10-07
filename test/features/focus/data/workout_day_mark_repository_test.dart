import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/focus/data/workout_day_mark_repository.dart';
import 'package:self_improvement/features/focus/domain/workout_day_mark.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The commands behind "Wie war dein Tag?" (BS-99): rest days and skipped days
/// as facts of one local day, with command ids, undo and the affected day.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late RecordingProjectionSynchronizer projection;
  late WorkoutDayMarkRepository repository;
  late AppDatabase db;

  // "now" is 2026-10-03 08:00Z = 10:00 in Berlin.
  final today = LocalDate(2026, 10, 3);

  setUp(() async {
    projection = RecordingProjectionSynchronizer();
    harness = await DataHarness.create(projections: projection);
    db = harness.database;
    repository = WorkoutDayMarkRepository(database: db, runner: harness.runner);
  });
  tearDown(() => harness.dispose());

  Future<String> mark(
    WorkoutDayMarkKind kind, {
    LocalDate? date,
    String? commandId,
  }) async {
    final outcome = await repository.mark(
      commandId: commandId ?? harness.ids.newId(),
      kind: kind,
      date: date,
    );
    return outcome.entityId!;
  }

  Future<WorkoutDayMarkRow> rowOf(String id) => (db.select(
    db.workoutDayMarks,
  )..where((m) => m.id.equals(id))).getSingle();

  Future<List<WorkoutDayMarkRow>> rows() => db.select(db.workoutDayMarks).get();

  Future<List<CommandReceiptRow>> receipts() =>
      db.select(db.commandReceipts).get();

  Matcher conflict(ConflictKind kind, {String? related}) => throwsA(
    isA<ConflictFailure>()
        .having((f) => f.kind, 'kind', kind)
        .having((f) => f.relatedEntityId, 'related id', related),
  );

  group('mark', () {
    test('(BS-99, AT12) stores the kind, the local day, the zone and the audit columns', () async {
      final restId = await mark(WorkoutDayMarkKind.rest);
      final row = await rowOf(restId);
      expect(row.kind, 'rest');
      expect(row.localDate, today);
      expect(row.timezoneId, 'Europe/Berlin');
      expect(row.rowVersion, 1);
      expect(row.deletedAtUtc, isNull);
      expect(row.createdAtUtc, DateTime.utc(2026, 10, 3, 8));
      expect(row.updatedAtUtc, DateTime.utc(2026, 10, 3, 8));

      harness.clock.advance(const Duration(days: 1));
      final skippedId = await mark(WorkoutDayMarkKind.skipped);
      final skipped = await rowOf(skippedId);
      expect(skipped.kind, 'skipped');
      expect(skipped.localDate, today.addDays(1));
    });

    test('(BS-99) reads the mark back as a domain value', () async {
      final id = await mark(WorkoutDayMarkKind.skipped);
      final found = (await repository.findDay(today))!;
      expect(found.id, id);
      expect(found.date, today);
      expect(found.kind, WorkoutDayMarkKind.skipped);
      expect(found.timezoneId, 'Europe/Berlin');
      expect(found.rowVersion, 1);
      expect(await repository.findDay(today.addDays(-1)), isNull);
      expect(await repository.findDay(today.addDays(1)), isNull);
    });

    test(
      '(BS-99) reports the day to the projection (snapshot of that day)',
      () async {
        await mark(WorkoutDayMarkKind.rest);
        expect(projection.syncs, [
          {today},
        ]);
      },
    );

    test(
      '(BS-99) a day in the past can be marked, a day in the future cannot',
      () async {
        final yesterday = today.addDays(-1);
        final id = await mark(WorkoutDayMarkKind.rest, date: yesterday);
        expect((await rowOf(id)).localDate, yesterday);
        expect(projection.syncs.last, {yesterday});

        await expectLater(
          repository.mark(
            commandId: harness.ids.newId(),
            kind: WorkoutDayMarkKind.rest,
            date: today.addDays(1),
          ),
          throwsA(
            isA<ValidationFailure>().having(
              (f) => f.fieldErrors.keys,
              'fields',
              ['date'],
            ),
          ),
        );
        expect(await rows(), hasLength(1), reason: 'nothing was stored');
      },
    );

    test('(BS-99) a second mark for the same day is a conflict that names the first', () async {
      final first = await mark(WorkoutDayMarkKind.rest);
      final receiptsBefore = (await receipts()).length;

      await expectLater(
        repository.mark(
          commandId: harness.ids.newId(),
          kind: WorkoutDayMarkKind.skipped,
        ),
        conflict(ConflictKind.invalidState, related: first),
      );
      await expectLater(
        repository.mark(
          commandId: harness.ids.newId(),
          kind: WorkoutDayMarkKind.rest,
        ),
        conflict(ConflictKind.invalidState, related: first),
        reason: 'the same kind again is a conflict too',
      );

      expect(await rows(), hasLength(1));
      expect((await rowOf(first)).kind, 'rest', reason: 'the first stays');
      expect(
        (await receipts()).length,
        receiptsBefore,
        reason: 'a failed command leaves no receipt',
      );
    });

    test(
      '(BS-99, AT12) the same command id twice is one mark and no conflict',
      () async {
        await mark(WorkoutDayMarkKind.rest, commandId: 'once');
        final replay = await repository.mark(
          commandId: 'once',
          kind: WorkoutDayMarkKind.rest,
        );
        expect(replay.replayed, isTrue);
        expect(await rows(), hasLength(1));
        expect(projection.syncs, hasLength(1), reason: 'nothing ran twice');
      },
    );

    test('(BS-99, AT27) a failing projection rolls the mark back; the retry with the same id commits', () async {
      projection.failure = StateError('disk full');
      await expectLater(
        repository.mark(commandId: 'retry', kind: WorkoutDayMarkKind.rest),
        throwsA(isA<StorageFailure>()),
      );
      expect(await rows(), isEmpty);
      expect(await receipts(), isEmpty);

      projection.failure = null;
      await repository.mark(commandId: 'retry', kind: WorkoutDayMarkKind.rest);
      expect(await rows(), hasLength(1));
    });

    test(
      '(BS-99) the undo of a mark takes it back; its own undo sets it again',
      () async {
        final outcome = await repository.mark(
          commandId: harness.ids.newId(),
          kind: WorkoutDayMarkKind.rest,
        );
        final id = outcome.entityId!;
        projection.syncs.clear();

        final undone = await outcome.undo!.run(harness.ids.newId());
        expect(await repository.findDay(today), isNull);
        final row = await rowOf(id);
        expect(row.deletedAtUtc, isNotNull);
        expect(row.rowVersion, 2);
        expect(projection.syncs.single, {today});

        await undone.undo!.run(harness.ids.newId());
        expect((await repository.findDay(today))!.id, id);
        expect((await rowOf(id)).rowVersion, 3);
      },
    );

    test('(BS-99) the undo of a mark that was already taken back is a not found, not a second write', () async {
      final outcome = await repository.mark(
        commandId: harness.ids.newId(),
        kind: WorkoutDayMarkKind.rest,
      );
      await repository.unmark(
        commandId: harness.ids.newId(),
        id: outcome.entityId!,
      );
      await expectLater(
        outcome.undo!.run(harness.ids.newId()),
        throwsA(isA<NotFoundFailure>()),
      );
      expect((await rowOf(outcome.entityId!)).rowVersion, 2);
    });

    test('(BS-99) the undo of a mark that was changed meanwhile is a stale version conflict', () async {
      final outcome = await repository.mark(
        commandId: harness.ids.newId(),
        kind: WorkoutDayMarkKind.rest,
      );
      await (db.update(db.workoutDayMarks)
            ..where((m) => m.id.equals(outcome.entityId!)))
          .write(const WorkoutDayMarksCompanion(rowVersion: Value(5)));
      await expectLater(
        outcome.undo!.run(harness.ids.newId()),
        conflict(ConflictKind.staleVersion, related: outcome.entityId),
      );
      expect((await repository.findDay(today))!.id, outcome.entityId);
    });
  });

  group('unmark', () {
    test(
      '(BS-99) takes the mark back with a soft delete; the day is open again',
      () async {
        final id = await mark(WorkoutDayMarkKind.skipped);
        projection.syncs.clear();

        await repository.unmark(commandId: harness.ids.newId(), id: id);

        expect(await repository.findDay(today), isNull);
        final row = await rowOf(id);
        expect(row.deletedAtUtc, DateTime.utc(2026, 10, 3, 8));
        expect(row.rowVersion, 2);
        expect(projection.syncs.single, {today});
      },
    );

    test(
      '(BS-99) an unknown id and a mark that is already gone are not found',
      () async {
        await expectLater(
          repository.unmark(commandId: harness.ids.newId(), id: 'nope'),
          throwsA(isA<NotFoundFailure>()),
        );
        final id = await mark(WorkoutDayMarkKind.rest);
        await repository.unmark(commandId: harness.ids.newId(), id: id);
        await expectLater(
          repository.unmark(commandId: harness.ids.newId(), id: id),
          throwsA(isA<NotFoundFailure>()),
        );
      },
    );

    test(
      '(BS-99) the undo restores the SAME mark with its kind and day',
      () async {
        final id = await mark(WorkoutDayMarkKind.skipped);
        final taken = await repository.unmark(
          commandId: harness.ids.newId(),
          id: id,
        );
        projection.syncs.clear();

        await taken.undo!.run(harness.ids.newId());

        final found = (await repository.findDay(today))!;
        expect(found.id, id);
        expect(found.kind, WorkoutDayMarkKind.skipped);
        expect(found.rowVersion, 3);
        expect((await rowOf(id)).deletedAtUtc, isNull);
        expect(projection.syncs.single, {today});
      },
    );

    test('(BS-99) the undo is a conflict while the day was marked again; the newer mark stays', () async {
      final first = await mark(WorkoutDayMarkKind.rest);
      final taken = await repository.unmark(
        commandId: harness.ids.newId(),
        id: first,
      );
      final second = await mark(WorkoutDayMarkKind.skipped);

      await expectLater(
        taken.undo!.run(harness.ids.newId()),
        conflict(ConflictKind.staleVersion, related: second),
      );

      expect((await repository.findDay(today))!.id, second);
      expect(
        (await rowOf(first)).deletedAtUtc,
        isNotNull,
        reason: 'the old mark stays taken back',
      );
    });

    test('(BS-99) a day can be marked again after it was taken back (a new mark, not the old row)', () async {
      final first = await mark(WorkoutDayMarkKind.rest);
      await repository.unmark(commandId: harness.ids.newId(), id: first);
      final second = await mark(WorkoutDayMarkKind.skipped);
      expect(second, isNot(first));
      expect(
        (await repository.findDay(today))!.kind,
        WorkoutDayMarkKind.skipped,
      );
      expect(await rows(), hasLength(2), reason: 'the taken back row stays');
    });
  });

  group('time zone and day change (AT25)', () {
    test('(BS-99, AT25) the mark stays on the day it was set; the next day is open', () async {
      // 23:30 in Berlin.
      harness.clock.setNow(DateTime.utc(2026, 10, 3, 21, 30));
      final id = await mark(WorkoutDayMarkKind.rest);
      expect((await rowOf(id)).localDate, today);

      // 00:30 the next day.
      harness.clock.advance(const Duration(hours: 1));
      expect(harness.clock.today(), today.addDays(1));
      expect(await repository.findDay(harness.clock.today()), isNull);
      expect((await repository.findDay(today))!.id, id);

      // The new day takes its own mark.
      final next = await mark(WorkoutDayMarkKind.skipped);
      expect((await rowOf(next)).localDate, today.addDays(1));
      expect((await repository.findDay(today))!.kind, WorkoutDayMarkKind.rest);
    });

    test(
      '(BS-99, AT25) a later change of the zone never moves a mark',
      () async {
        final id = await mark(WorkoutDayMarkKind.rest);
        harness.clock
          ..setTimeZone('Pacific/Kiritimati') // UTC+14
          ..advance(const Duration(hours: 3));
        // 11:00Z is already 01:00 on the next day in Kiritimati.
        expect(harness.clock.today(), today.addDays(1));

        final row = await rowOf(id);
        expect(row.localDate, today);
        expect(row.timezoneId, 'Europe/Berlin', reason: 'frozen with the mark');

        final next = await mark(WorkoutDayMarkKind.skipped);
        final nextRow = await rowOf(next);
        expect(nextRow.localDate, today.addDays(1));
        expect(nextRow.timezoneId, 'Pacific/Kiritimati');
      },
    );

    test('(BS-99, AT25) travelling back onto a marked day makes a second mark a conflict', () async {
      final first = await mark(WorkoutDayMarkKind.rest);
      harness.clock.setTimeZone('America/New_York');
      expect(harness.clock.today(), today, reason: 'still 2026-10-03 there');
      await expectLater(
        repository.mark(
          commandId: harness.ids.newId(),
          kind: WorkoutDayMarkKind.rest,
        ),
        conflict(ConflictKind.invalidState, related: first),
      );
    });
  });

  group('watchDay', () {
    test(
      '(BS-99) follows the mark, the taking back and the restoring',
      () async {
        final seen = <WorkoutDayMark?>[];
        final sub = repository.watchDay(today).listen(seen.add);
        addTearDown(sub.cancel);
        Future<void> settle() =>
            Future<void>.delayed(const Duration(milliseconds: 20));

        await settle();
        expect(seen.last, isNull);

        final outcome = await repository.mark(
          commandId: harness.ids.newId(),
          kind: WorkoutDayMarkKind.rest,
        );
        await settle();
        expect(seen.last!.kind, WorkoutDayMarkKind.rest);

        final taken = await repository.unmark(
          commandId: harness.ids.newId(),
          id: outcome.entityId!,
        );
        await settle();
        expect(seen.last, isNull);

        await taken.undo!.run(harness.ids.newId());
        await settle();
        expect(seen.last!.id, outcome.entityId);
      },
    );
  });

  group('the table keeps the rule itself', () {
    WorkoutDayMarksCompanion companion(
      String id, {
      String kind = 'rest',
      LocalDate? date,
      DateTime? deletedAt,
    }) => WorkoutDayMarksCompanion.insert(
      id: id,
      localDate: date ?? today,
      kind: kind,
      timezoneId: 'Europe/Berlin',
      createdAtUtc: DateTime.utc(2026, 10, 3, 8),
      updatedAtUtc: DateTime.utc(2026, 10, 3, 8),
      deletedAtUtc: Value(deletedAt),
    );

    test(
      '(BS-99) at most one ACTIVE mark per day; a taken back one makes room',
      () async {
        await db.into(db.workoutDayMarks).insert(companion('a'));
        await expectLater(
          db.into(db.workoutDayMarks).insert(companion('b', kind: 'skipped')),
          throwsA(anything),
        );
        await db
            .into(db.workoutDayMarks)
            .insert(companion('c', date: today.addDays(1)));
        await db
            .into(db.workoutDayMarks)
            .insert(companion('d', deletedAt: DateTime.utc(2026, 10, 3, 9)));
        expect(await rows(), hasLength(3));
      },
    );

    test('(BS-99) only rest and skipped are valid kinds', () async {
      await expectLater(
        db.into(db.workoutDayMarks).insert(companion('x', kind: 'sick')),
        throwsA(anything),
      );
      expect(await rows(), isEmpty);
    });
  });

  group('mapMark', () {
    test('(BS-99) maps a stored row to the domain value', () async {
      final id = await mark(WorkoutDayMarkKind.rest);
      final mapped = WorkoutDayMarkRepository.mapMark(await rowOf(id))!;
      expect(
        mapped,
        WorkoutDayMark(
          id: id,
          date: today,
          kind: WorkoutDayMarkKind.rest,
          timezoneId: 'Europe/Berlin',
          rowVersion: 1,
        ),
      );
    });
  });
}
