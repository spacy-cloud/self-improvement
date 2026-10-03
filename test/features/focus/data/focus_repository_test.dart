import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/focus/data/focus_repository.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/features/focus/domain/focus_timer.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late RecordingProjectionSynchronizer projection;
  late FocusRepository repository;

  setUp(() async {
    projection = RecordingProjectionSynchronizer();
    harness = await DataHarness.create(projections: projection);
    repository = FocusRepository(
      database: harness.database,
      runner: harness.runner,
    );
  });
  tearDown(() => harness.dispose());

  final startTime = DateTime.utc(2026, 10, 3, 8);

  void advance(int seconds) =>
      harness.clock.advance(Duration(seconds: seconds));

  Future<FocusSessionRow> rowOf(String id) => (harness.database.select(
    harness.database.focusSessions,
  )..where((f) => f.id.equals(id))).getSingle();

  Future<List<CommandReceiptRow>> receipts() =>
      harness.database.select(harness.database.commandReceipts).get();

  Future<String> start({
    FocusCategory category = FocusCategory.learning,
    int planned = 1500,
    String? commandId,
  }) async {
    final outcome = await repository.start(
      commandId: commandId ?? harness.ids.newId(),
      category: category,
      plannedSeconds: planned,
    );
    return outcome.entityId!;
  }

  Future<CommandOutcome> pause(String id) =>
      repository.pause(commandId: harness.ids.newId(), id: id);
  Future<CommandOutcome> resume(String id) =>
      repository.resume(commandId: harness.ids.newId(), id: id);
  Future<CommandOutcome> save(String id) =>
      repository.save(commandId: harness.ids.newId(), id: id);
  Future<CommandOutcome> discard(String id) =>
      repository.discard(commandId: harness.ids.newId(), id: id);
  Future<CommandOutcome> markAwaiting(String id) => repository
      .markAwaitingConfirmation(commandId: harness.ids.newId(), id: id);

  /// Events published after commits (flushed before reading).
  List<AppEvent> collectEvents() {
    final events = <AppEvent>[];
    final subscription = harness.events.stream.listen(events.add);
    addTearDown(subscription.cancel);
    return events;
  }

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  Matcher conflict(ConflictKind kind) =>
      throwsA(isA<ConflictFailure>().having((f) => f.kind, 'kind', kind));

  group('start', () {
    test(
      'persists a running session with plan, segment start and zone',
      () async {
        final id = await start(category: FocusCategory.programming);
        final row = await rowOf(id);
        expect(row.category, 'programming');
        expect(row.plannedSeconds, 1500);
        expect(row.accumulatedSeconds, 0);
        expect(row.status, 'running');
        expect(row.segmentStartedAtUtc, startTime);
        expect(row.startedAtUtc, startTime);
        expect(row.endedAtUtc, isNull);
        expect(row.completedLocalDate, isNull);
        expect(row.timezoneId, 'Europe/Berlin');
        expect(row.note, isNull);
        expect(
          row.gamificationEligible,
          isFalse,
          reason: 'frozen only at save',
        );
        expect(row.rowVersion, 1);
        expect(row.deletedAtUtc, isNull);
      },
    );

    test('the open session is readable right after the command (persist before display)', () async {
      final emissions = <FocusSession?>[];
      final subscription = repository.watchOpen().listen(emissions.add);
      addTearDown(subscription.cancel);
      await flush();
      expect(emissions, [isNull]);
      final id = await start();
      await flush();
      expect(emissions.last!.id, id);
      expect(emissions.last!.status, FocusStatus.running);
      expect(
        emissions.last!.segmentStartedAtUtc,
        startTime,
        reason: 'the emitted state is the persisted state',
      );
    });

    test('every category can be started', () async {
      for (final category in FocusCategory.values) {
        final id = await start(category: category);
        expect((await rowOf(id)).category, category.key);
        await discard(id);
      }
    });

    test(
      'the planned time is validated first: 5 to 180 minutes inclusive',
      () async {
        for (final bad in [299, 0, -300, 10801, 99999]) {
          await expectLater(
            repository.start(
              commandId: 'bad-$bad',
              category: FocusCategory.reading,
              plannedSeconds: bad,
            ),
            throwsA(
              isA<ValidationFailure>().having(
                (f) => f.fieldErrors[FocusFields.planned],
                'message',
                'Bitte wähle eine Dauer zwischen 5 und 180 Minuten.',
              ),
            ),
            reason: '$bad s',
          );
        }
        expect(await repository.findOpen(), isNull);
        expect(await receipts(), isEmpty, reason: 'no receipt for failures');
        final low = await start(planned: 300);
        expect((await rowOf(low)).plannedSeconds, 300);
        await discard(low);
        final high = await start(planned: 10800);
        expect((await rowOf(high)).plannedSeconds, 10800);
      },
    );

    test(
      'the same command id is one session, a new id is refused while open',
      () async {
        final first = await repository.start(
          commandId: 'once',
          category: FocusCategory.reading,
          plannedSeconds: 1500,
        );
        final replay = await repository.start(
          commandId: 'once',
          category: FocusCategory.reading,
          plannedSeconds: 1500,
        );
        expect(replay.replayed, isTrue);
        expect(replay.entityId, first.entityId);
        expect(
          await harness.database.select(harness.database.focusSessions).get(),
          hasLength(1),
        );
      },
    );

    test(
      'a start does not touch the projection (nothing earned yet)',
      () async {
        await start();
        expect(projection.syncs, isEmpty);
      },
    );
  });

  group('single open session', () {
    Future<String> inState(FocusStatus status) async {
      final id = await start();
      switch (status) {
        case FocusStatus.running:
          break;
        case FocusStatus.paused:
          advance(60);
          await pause(id);
        case FocusStatus.awaitingConfirmation:
          await markAwaiting(id);
        case FocusStatus.completed:
        case FocusStatus.discarded:
          fail('not an open state');
      }
      return id;
    }

    for (final status in [
      FocusStatus.running,
      FocusStatus.paused,
      FocusStatus.awaitingConfirmation,
    ]) {
      test('a second start is refused while one is ${status.key}', () async {
        final openId = await inState(status);
        final receiptsBefore = (await receipts()).length;
        await expectLater(
          repository.start(
            commandId: 'second',
            category: FocusCategory.reading,
            plannedSeconds: 600,
          ),
          throwsA(
            isA<ConflictFailure>()
                .having((f) => f.kind, 'kind', ConflictKind.openFocusSession)
                .having((f) => f.relatedEntityId, 'open session', openId),
          ),
        );
        expect(
          await harness.database.select(harness.database.focusSessions).get(),
          hasLength(1),
          reason: 'navigation never creates a second session',
        );
        expect((await receipts()).length, receiptsBefore);
        expect((await repository.findOpen())!.id, openId);
      });
    }

    test('after save or discard a new session can be started', () async {
      final first = await start();
      advance(30);
      await save(first);
      final second = await start();
      expect(second, isNot(first));
      await discard(second);
      final third = await start();
      expect((await repository.findOpen())!.id, third);
    });

    test(
      'the partial unique index is the backstop for a second open row',
      () async {
        await start();
        await expectLater(
          harness.database
              .into(harness.database.focusSessions)
              .insert(
                FocusSessionsCompanion.insert(
                  id: 'raw',
                  category: 'reading',
                  plannedSeconds: 600,
                  startedAtUtc: startTime,
                  timezoneId: 'Europe/Berlin',
                  status: 'paused',
                  createdAtUtc: startTime,
                  updatedAtUtc: startTime,
                ),
              ),
          throwsA(anything),
        );
      },
    );

    test(
      'a soft-deleted open row does not block (index excludes deleted)',
      () async {
        final id = await start();
        await (harness.database.update(harness.database.focusSessions)
              ..where((f) => f.id.equals(id)))
            .write(FocusSessionsCompanion(deletedAtUtc: Value(startTime)));
        expect(await repository.findOpen(), isNull);
        await start();
      },
    );
  });

  group('pause and resume (persisted segments, AT16)', () {
    test('pause stores the elapsed seconds and clears the segment', () async {
      final id = await start();
      advance(600);
      await pause(id);
      final row = await rowOf(id);
      expect(row.status, 'paused');
      expect(row.accumulatedSeconds, 600);
      expect(row.segmentStartedAtUtc, isNull);
      expect(row.rowVersion, 2);
      expect(row.updatedAtUtc, startTime.add(const Duration(seconds: 600)));
      expect(
        (await repository.findById(id))!.pausedAtUtc,
        startTime.add(const Duration(seconds: 600)),
      );
    });

    test(
      'resume keeps the accumulated time and starts a new segment now',
      () async {
        final id = await start();
        advance(600);
        await pause(id);
        advance(300);
        await resume(id);
        final row = await rowOf(id);
        expect(row.status, 'running');
        expect(row.accumulatedSeconds, 600);
        expect(
          row.segmentStartedAtUtc,
          startTime.add(const Duration(seconds: 900)),
        );
        expect(row.rowVersion, 3);
        advance(180);
        final elapsed = computeFocusElapsed(
          (await repository.findById(id))!,
          harness.clock.nowUtc(),
        );
        expect(elapsed.elapsedSeconds, 780);
        expect(elapsed.remainingSeconds, 720);
      },
    );

    test('paused time does not count: the pause length is ignored', () async {
      final id = await start();
      advance(100);
      await pause(id);
      advance(86400);
      expect((await rowOf(id)).accumulatedSeconds, 100);
      await resume(id);
      advance(50);
      await pause(id);
      expect((await rowOf(id)).accumulatedSeconds, 150);
    });

    test('pause after the plan is over gives awaiting confirmation, never more than the plan', () async {
      final id = await start(planned: 300);
      advance(5000);
      await pause(id);
      final row = await rowOf(id);
      expect(row.status, 'awaiting_confirmation');
      expect(row.accumulatedSeconds, 300);
      expect(row.segmentStartedAtUtc, isNull);
    });

    test(
      'pause and resume are no-ops when the session already is in the state',
      () async {
        final id = await start();
        advance(10);
        await pause(id);
        final version = (await rowOf(id)).rowVersion;
        final events = collectEvents();
        advance(10);
        await pause(id);
        expect((await rowOf(id)).rowVersion, version);
        expect((await rowOf(id)).accumulatedSeconds, 10);
        await resume(id);
        final resumedVersion = (await rowOf(id)).rowVersion;
        await resume(id);
        expect((await rowOf(id)).rowVersion, resumedVersion);
        await flush();
        expect(
          events.whereType<FocusStateChanged>(),
          hasLength(1),
          reason: 'only the real resume',
        );
      },
    );

    test('pause and resume of an awaiting session are refused', () async {
      final id = await start();
      await markAwaiting(id);
      await expectLater(pause(id), conflict(ConflictKind.invalidState));
      await expectLater(resume(id), conflict(ConflictKind.invalidState));
      expect((await rowOf(id)).status, 'awaiting_confirmation');
    });

    test('commands on a missing or deleted session are NotFound', () async {
      await expectLater(pause('missing'), throwsA(isA<NotFoundFailure>()));
      await expectLater(save('missing'), throwsA(isA<NotFoundFailure>()));
    });

    test('the clock set back never produces negative time', () async {
      final id = await start();
      advance(100);
      await pause(id);
      advance(10);
      await resume(id);
      harness.clock.setNow(startTime.subtract(const Duration(hours: 5)));
      await pause(id);
      final row = await rowOf(id);
      expect(
        row.accumulatedSeconds,
        100,
        reason: 'the negative segment counts as 0',
      );
      expect(row.status, 'paused');
    });

    test('pause, resume and await never use the projection', () async {
      final id = await start();
      advance(60);
      await pause(id);
      await resume(id);
      advance(10);
      await markAwaiting(id);
      expect(projection.syncs, isEmpty);
    });
  });

  group('markAwaitingConfirmation', () {
    test(
      'sets accumulated to the plan, clears the segment, completes nothing',
      () async {
        final id = await start(planned: 600);
        advance(30);
        await markAwaiting(id);
        final row = await rowOf(id);
        expect(row.status, 'awaiting_confirmation');
        expect(row.accumulatedSeconds, 600);
        expect(row.segmentStartedAtUtc, isNull);
        expect(row.endedAtUtc, isNull);
        expect(row.completedLocalDate, isNull);
        expect(row.gamificationEligible, isFalse);
      },
    );

    test(
      'is idempotent: a second call with a new id changes nothing',
      () async {
        final id = await start();
        await markAwaiting(id);
        final version = (await rowOf(id)).rowVersion;
        final events = collectEvents();
        await markAwaiting(id);
        expect((await rowOf(id)).rowVersion, version);
        await flush();
        expect(events.whereType<FocusStateChanged>(), isEmpty);
      },
    );

    test('a paused session below its plan cannot be marked', () async {
      final id = await start();
      advance(10);
      await pause(id);
      await expectLater(markAwaiting(id), conflict(ConflictKind.invalidState));
    });

    test('a completed session cannot be marked (the late foreground call is harmless)', () async {
      final id = await start();
      advance(10);
      await save(id);
      await expectLater(markAwaiting(id), conflict(ConflictKind.invalidState));
      expect((await rowOf(id)).status, 'completed');
    });
  });

  group('save (Sitzung speichern)', () {
    test(
      'running: saves the elapsed time, end and local date of the confirmation',
      () async {
        final id = await start();
        advance(1200);
        await save(id);
        final row = await rowOf(id);
        expect(row.status, 'completed');
        expect(row.accumulatedSeconds, 1200);
        expect(row.segmentStartedAtUtc, isNull);
        expect(row.endedAtUtc, startTime.add(const Duration(seconds: 1200)));
        expect(row.completedLocalDate, LocalDate(2026, 10, 3));
        expect(row.timezoneId, 'Europe/Berlin');
        expect(row.rowVersion, 2);
      },
    );

    test(
      'paused: saves the accumulated time regardless of the pause',
      () async {
        final id = await start();
        advance(400);
        await pause(id);
        advance(7200);
        await save(id);
        expect((await rowOf(id)).accumulatedSeconds, 400);
      },
    );

    test('awaiting confirmation: saves the planned time', () async {
      final id = await start(planned: 900);
      advance(99999);
      await markAwaiting(id);
      advance(500);
      await save(id);
      final row = await rowOf(id);
      expect(row.accumulatedSeconds, 900);
      expect(row.status, 'completed');
    });

    test('finishEarly is the same as save from a running session', () async {
      final id = await start();
      advance(100);
      final outcome = await repository.finishEarly(
        commandId: harness.ids.newId(),
        id: id,
      );
      expect(outcome.entityId, id);
      expect((await rowOf(id)).status, 'completed');
      expect((await rowOf(id)).accumulatedSeconds, 100);
    });

    test('running past the plan saves exactly the plan', () async {
      final id = await start(planned: 300);
      advance(100000);
      await save(id);
      expect((await rowOf(id)).accumulatedSeconds, 300);
    });

    test('the minimum is one second: 0 s is a validation error and changes nothing', () async {
      final id = await start();
      final receiptsBefore = (await receipts()).length;
      await expectLater(
        save(id),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.fieldErrors.keys,
            'fields',
            contains(FocusFields.duration),
          ),
        ),
      );
      expect((await rowOf(id)).status, 'running');
      expect(projection.syncs, isEmpty);
      expect((await receipts()).length, receiptsBefore);
      advance(1);
      await save(id);
      expect((await rowOf(id)).accumulatedSeconds, 1);
    });

    test(
      'with the clock set back and nothing accumulated it cannot be saved',
      () async {
        final id = await start();
        harness.clock.setNow(startTime.subtract(const Duration(hours: 2)));
        await expectLater(save(id), throwsA(isA<ValidationFailure>()));
      },
    );

    test(
      'saving twice (same or new command id) yields exactly one completion',
      () async {
        final id = await start();
        advance(600);
        final first = await repository.save(commandId: 'save-1', id: id);
        advance(60);
        final sameId = await repository.save(commandId: 'save-1', id: id);
        final newId = await repository.save(commandId: 'save-2', id: id);
        expect(first.replayed, isFalse);
        expect(sameId.replayed, isTrue);
        expect(newId.replayed, isFalse, reason: 'a new command, but a no-op');
        expect(newId.undo, isNull, reason: 'nothing to undo for a no-op');
        final row = await rowOf(id);
        expect(
          row.accumulatedSeconds,
          600,
          reason: 'the later save changed nothing',
        );
        expect(row.endedAtUtc, startTime.add(const Duration(seconds: 600)));
        expect(row.rowVersion, 2);
        expect(projection.syncs, [
          {LocalDate(2026, 10, 3)},
        ], reason: 'only the real save syncs the projection');
      },
    );

    test('a discarded session cannot be saved', () async {
      final id = await start();
      advance(100);
      await discard(id);
      await expectLater(save(id), conflict(ConflictKind.invalidState));
    });

    test(
      'syncs the projection for the completion day inside the command',
      () async {
        final id = await start();
        advance(100);
        await save(id);
        expect(projection.syncs, [
          {LocalDate(2026, 10, 3)},
        ]);
      },
    );
  });

  group('completion date (AT25, AT23)', () {
    test(
      'a session over midnight counts completely on the confirmation day',
      () async {
        // 23:50 Berlin on 2026-10-03.
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 21, 50));
        final id = await start(planned: 3600);
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 10));
        await save(id);
        final row = await rowOf(id);
        expect(row.completedLocalDate, LocalDate(2026, 10, 4));
        expect(row.accumulatedSeconds, 1200, reason: 'not split at midnight');
        expect(projection.syncs.single, {LocalDate(2026, 10, 4)});
      },
    );

    test(
      'the date is the local date of the confirmation, not the UTC date',
      () async {
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 21, 0));
        final id = await start();
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 30));
        await save(id);
        expect(
          (await rowOf(id)).completedLocalDate,
          LocalDate(2026, 10, 4),
          reason: '22:30Z is 00:30 on the 4th in Berlin',
        );
      },
    );

    test(
      'summer time ending: the duration is real elapsed time, the date stays',
      () async {
        // Berlin turns the clocks back on 2026-10-25 at 03:00 CEST (01:00Z).
        harness.clock.setNow(DateTime.utc(2026, 10, 25, 0, 30));
        final id = await start(planned: 7200);
        harness.clock.setNow(DateTime.utc(2026, 10, 25, 1, 30));
        await save(id);
        final row = await rowOf(id);
        expect(row.accumulatedSeconds, 3600, reason: 'one real hour');
        expect(row.completedLocalDate, LocalDate(2026, 10, 25));
      },
    );

    test(
      'summer time starting: confirmation after the gap keeps the day',
      () async {
        // Berlin skips 02:00-03:00 on 2026-03-29 (01:00Z).
        harness.clock.setNow(DateTime.utc(2026, 3, 29, 0, 30));
        final id = await start(planned: 7200);
        harness.clock.setNow(DateTime.utc(2026, 3, 29, 1, 30));
        await save(id);
        final row = await rowOf(id);
        expect(row.accumulatedSeconds, 3600);
        expect(row.completedLocalDate, LocalDate(2026, 3, 29));
      },
    );

    test(
      'the zone is frozen at the confirmation: travel afterwards moves nothing',
      () async {
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 0));
        final id = await start();
        harness.clock.setTimeZone('America/New_York');
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 30));
        await save(id);
        var row = await rowOf(id);
        expect(
          row.completedLocalDate,
          LocalDate(2026, 10, 3),
          reason: '18:30 on the 3rd in New York (Berlin would be the 4th)',
        );
        expect(row.timezoneId, 'America/New_York');
        harness.clock.setTimeZone('Asia/Tokyo');
        harness.clock.advance(const Duration(days: 2));
        row = await rowOf(id);
        expect(row.completedLocalDate, LocalDate(2026, 10, 3));
        expect(row.timezoneId, 'America/New_York');
      },
    );

    test(
      'a start in one zone and a save in another uses the zone of the save',
      () async {
        final id = await start();
        expect((await rowOf(id)).timezoneId, 'Europe/Berlin');
        harness.clock.setTimeZone('Asia/Tokyo');
        advance(60);
        await save(id);
        expect((await rowOf(id)).timezoneId, 'Asia/Tokyo');
      },
    );
  });

  group('discard', () {
    test('records no completion, no end and no eligibility', () async {
      final id = await start();
      advance(300);
      await discard(id);
      final row = await rowOf(id);
      expect(row.status, 'discarded');
      expect(row.completedLocalDate, isNull);
      expect(row.endedAtUtc, isNull);
      expect(row.segmentStartedAtUtc, isNull);
      expect(row.gamificationEligible, isFalse);
      expect(row.accumulatedSeconds, 300, reason: 'time spent stays on record');
      expect(projection.syncs, isEmpty);
    });

    test(
      'works from every open state and is a no-op the second time',
      () async {
        final running = await start();
        await discard(running);
        final paused = await start();
        advance(10);
        await pause(paused);
        await discard(paused);
        final awaiting = await start();
        await markAwaiting(awaiting);
        await discard(awaiting);
        final version = (await rowOf(awaiting)).rowVersion;
        await discard(awaiting);
        expect((await rowOf(awaiting)).rowVersion, version);
        expect(await repository.findOpen(), isNull);
      },
    );

    test('a completed session cannot be discarded', () async {
      final id = await start();
      advance(30);
      await save(id);
      await expectLater(discard(id), conflict(ConflictKind.invalidState));
    });
  });

  group('FocusStateChanged', () {
    test(
      'is published after the commit for every change of the open session',
      () async {
        final events = collectEvents();
        final id = await start();
        advance(30);
        await pause(id);
        await resume(id);
        advance(30);
        await markAwaiting(id);
        await save(id);
        final other = await start();
        await discard(other);
        await flush();
        expect(events.whereType<FocusStateChanged>(), hasLength(7));
        // The activity events of the commands come first, then the focus event.
        final committed = events.whereType<ActivityCommitted>().toList();
        expect(
          committed.map((e) => e.commandType),
          containsAll([
            FocusRepository.startType,
            FocusRepository.pauseType,
            FocusRepository.resumeType,
            FocusRepository.awaitType,
            FocusRepository.saveType,
            FocusRepository.discardType,
          ]),
        );
      },
    );

    test('failed commands publish nothing', () async {
      final events = collectEvents();
      final id = await start();
      await flush();
      events.clear();
      await expectLater(save(id), throwsA(isA<ValidationFailure>()));
      await expectLater(
        repository.start(
          commandId: 'dup',
          category: FocusCategory.reading,
          plannedSeconds: 600,
        ),
        throwsA(isA<ConflictFailure>()),
      );
      await expectLater(
        repository.start(
          commandId: 'bad',
          category: FocusCategory.reading,
          plannedSeconds: 1,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      advance(10);
      projection.failure = StateError('disk full');
      await expectLater(save(id), throwsA(isA<StorageFailure>()));
      await flush();
      expect(events, isEmpty);
    });

    test('a replay publishes nothing again', () async {
      final events = collectEvents();
      await repository.start(
        commandId: 'once',
        category: FocusCategory.reading,
        plannedSeconds: 600,
      );
      await repository.start(
        commandId: 'once',
        category: FocusCategory.reading,
        plannedSeconds: 600,
      );
      await flush();
      expect(events.whereType<FocusStateChanged>(), hasLength(1));
    });

    test('notes and deletions are not timer state changes', () async {
      final id = await start();
      advance(100);
      await save(id);
      final events = collectEvents();
      await repository.updateNote(
        commandId: harness.ids.newId(),
        id: id,
        note: 'Kapitel 1',
      );
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await flush();
      expect(events.whereType<FocusStateChanged>(), isEmpty);
    });
  });

  group('atomicity (AT27)', () {
    test('a failing projection stores no completion and no receipt', () async {
      final id = await start();
      advance(600);
      final receiptsBefore = (await receipts()).length;
      projection.failure = StateError('disk full');
      await expectLater(
        repository.save(commandId: 'save', id: id),
        throwsA(isA<StorageFailure>()),
      );
      final row = await rowOf(id);
      expect(row.status, 'running', reason: 'nothing committed');
      expect(row.completedLocalDate, isNull);
      expect(row.rowVersion, 1);
      expect((await receipts()).length, receiptsBefore);
      // The retry with the SAME id succeeds once the problem is gone.
      projection.failure = null;
      await repository.save(commandId: 'save', id: id);
      expect((await rowOf(id)).status, 'completed');
      expect((await rowOf(id)).accumulatedSeconds, 600);
    });
  });

  group('eligibility (AT26)', () {
    Future<void> setGamification(bool enabled) => harness.database
        .into(harness.database.moduleStatusHistory)
        .insert(
          ModuleStatusHistoryCompanion.insert(
            id: harness.ids.newId(),
            moduleId: ModuleId.gamification.key,
            effectiveAtUtc: harness.clock.nowUtc(),
            localDate: harness.clock.today(),
            enabled: enabled,
          ),
        );

    test('is frozen from the gamification state at the SAVE', () async {
      final a = await start();
      advance(400);
      await save(a);
      expect((await rowOf(a)).gamificationEligible, isTrue);

      await setGamification(false);
      advance(1);
      final b = await start();
      expect((await rowOf(b)).gamificationEligible, isFalse);
      advance(400);
      await save(b);
      expect((await rowOf(b)).gamificationEligible, isFalse);
      await setGamification(true);
      expect(
        (await rowOf(b)).gamificationEligible,
        isFalse,
        reason: 'never retroactive',
      );
    });

    test('started while off but saved while on counts as eligible', () async {
      await setGamification(false);
      advance(1);
      final id = await start();
      advance(1);
      await setGamification(true);
      advance(400);
      await save(id);
      expect((await rowOf(id)).gamificationEligible, isTrue);
    });

    test('started while on but saved while off is not eligible', () async {
      final id = await start();
      advance(1);
      await setGamification(false);
      advance(400);
      await save(id);
      expect((await rowOf(id)).gamificationEligible, isFalse);
    });
  });

  group('notes', () {
    Future<String> completedSession() async {
      final id = await start();
      advance(600);
      await save(id);
      return id;
    }

    Future<CommandOutcome> note(String id, String? text, {int? version}) =>
        repository.updateNote(
          commandId: harness.ids.newId(),
          id: id,
          note: text,
          expectedRowVersion: version,
        );

    test('stores a trimmed note and bumps the version', () async {
      final id = await completedSession();
      await note(id, '  Kapitel 3 gelesen  ', version: 2);
      final row = await rowOf(id);
      expect(row.note, 'Kapitel 3 gelesen');
      expect(row.rowVersion, 3);
      expect(
        row.accumulatedSeconds,
        600,
        reason: 'the duration is untouchable',
      );
    });

    test(
      'a blank note removes it; 500 characters are fine, 501 are not',
      () async {
        final id = await completedSession();
        await note(id, 'x' * 500);
        expect((await rowOf(id)).note, 'x' * 500);
        await expectLater(
          note(id, 'x' * 501),
          throwsA(
            isA<ValidationFailure>().having(
              (f) => f.fieldErrors.keys,
              'fields',
              contains(FocusFields.note),
            ),
          ),
        );
        expect((await rowOf(id)).note, 'x' * 500);
        await note(id, '   ');
        expect((await rowOf(id)).note, isNull);
      },
    );

    test('an unchanged note is a no-op without a new version', () async {
      final id = await completedSession();
      await note(id, 'gleich');
      final version = (await rowOf(id)).rowVersion;
      final outcome = await note(id, ' gleich ');
      expect((await rowOf(id)).rowVersion, version);
      expect(outcome.undo, isNull);
    });

    test('only completed sessions have a note', () async {
      final open = await start();
      await expectLater(
        note(open, 'zu früh'),
        conflict(ConflictKind.invalidState),
      );
      advance(30);
      await discard(open);
      await expectLater(
        note(open, 'verworfen'),
        conflict(ConflictKind.invalidState),
      );
      await expectLater(note('missing', 'x'), throwsA(isA<NotFoundFailure>()));
    });

    test('a stale form version is a conflict and changes nothing', () async {
      final id = await completedSession();
      await expectLater(
        note(id, 'neu', version: 99),
        conflict(ConflictKind.staleVersion),
      );
      expect((await rowOf(id)).note, isNull);
    });

    test(
      'undo restores the previous note (also none), a changed row refuses it',
      () async {
        final id = await completedSession();
        final first = await note(id, 'eins');
        final second = await note(id, 'zwei');
        await expectLater(
          first.undo!.run(harness.ids.newId()),
          conflict(ConflictKind.staleVersion),
          reason: 'the note changed after the first edit',
        );
        expect((await rowOf(id)).note, 'zwei');
        await second.undo!.run(harness.ids.newId());
        expect((await rowOf(id)).note, 'eins');
        final third = await note(id, null);
        expect((await rowOf(id)).note, isNull);
        await third.undo!.run(harness.ids.newId());
        expect((await rowOf(id)).note, 'eins');
      },
    );

    test('a note change never touches the projection', () async {
      final id = await completedSession();
      projection.syncs.clear();
      await note(id, 'x');
      expect(projection.syncs, isEmpty);
    });

    test('the same command id is one change', () async {
      final id = await completedSession();
      await repository.updateNote(commandId: 'n1', id: id, note: 'a');
      final replay = await repository.updateNote(
        commandId: 'n1',
        id: id,
        note: 'b',
      );
      expect(replay.replayed, isTrue);
      expect((await rowOf(id)).note, 'a');
    });
  });

  group('delete and undo', () {
    Future<String> completedSession({int seconds = 600}) async {
      final id = await start();
      advance(seconds);
      await save(id);
      return id;
    }

    test('soft-deletes a completed session and syncs its day', () async {
      final id = await completedSession();
      projection.syncs.clear();
      final outcome = await repository.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      expect(await repository.findById(id), isNull);
      final row = await rowOf(id);
      expect(row.deletedAtUtc, isNotNull, reason: 'the row is kept');
      expect(outcome.undo, isNotNull);
      expect(projection.syncs, [
        {LocalDate(2026, 10, 3)},
      ]);
      expect(await repository.fetchHistory(limit: 10), isEmpty);
    });

    test('an open session cannot be deleted', () async {
      Future<void> expectRefused(String id) async {
        await expectLater(
          repository.delete(commandId: harness.ids.newId(), id: id),
          conflict(ConflictKind.invalidState),
        );
        expect((await repository.findOpen())!.id, id);
      }

      final id = await start();
      await expectRefused(id);
      advance(10);
      await pause(id);
      await expectRefused(id);
      await discard(id);
      final awaiting = await start();
      await markAwaiting(awaiting);
      await expectRefused(awaiting);
      expect((await rowOf(awaiting)).deletedAtUtc, isNull);
    });

    test('a discarded session can be deleted (no projection day)', () async {
      final id = await start();
      advance(30);
      await discard(id);
      projection.syncs.clear();
      await repository.delete(commandId: harness.ids.newId(), id: id);
      expect(await repository.findById(id), isNull);
      expect(projection.syncs, isEmpty);
    });

    test('undo restores the SAME id with its data', () async {
      final id = await completedSession(seconds: 900);
      await repository.updateNote(
        commandId: harness.ids.newId(),
        id: id,
        note: 'bleibt',
      );
      final outcome = await repository.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      await outcome.undo!.run(harness.ids.newId());
      final restored = (await repository.findById(id))!;
      expect(restored.id, id);
      expect(restored.accumulatedSeconds, 900);
      expect(restored.note, 'bleibt');
      expect(restored.status, FocusStatus.completed);
      expect(restored.completedLocalDate, LocalDate(2026, 10, 3));
    });

    test('undo is refused if the row changed meanwhile', () async {
      final id = await completedSession();
      final outcome = await repository.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      await (harness.database.update(harness.database.focusSessions)
            ..where((f) => f.id.equals(id)))
          .write(const FocusSessionsCompanion(rowVersion: Value(50)));
      await expectLater(
        outcome.undo!.run(harness.ids.newId()),
        conflict(ConflictKind.staleVersion),
      );
      expect(await repository.findById(id), isNull);
    });

    test(
      'deleting a deleted session is NotFound, the undo is idempotent',
      () async {
        final id = await completedSession();
        final outcome = await repository.delete(commandId: 'd1', id: id);
        await expectLater(
          repository.delete(commandId: 'd2', id: id),
          throwsA(isA<NotFoundFailure>()),
        );
        final first = await outcome.undo!.run('undo-1');
        final second = await outcome.undo!.run('undo-1');
        expect(first.replayed, isFalse);
        expect(second.replayed, isTrue);
      },
    );

    test('the same delete command id is one deletion', () async {
      final id = await completedSession();
      await repository.delete(commandId: 'once', id: id);
      final replay = await repository.delete(commandId: 'once', id: id);
      expect(replay.replayed, isTrue);
    });
  });

  group('undo of save and discard', () {
    test(
      'undo of a save from running continues the session from now',
      () async {
        final id = await start(planned: 3600);
        advance(600);
        final saved = await save(id);
        expect(saved.undo, isNotNull);
        advance(30);
        final events = collectEvents();
        projection.syncs.clear();
        await saved.undo!.run(harness.ids.newId());
        final row = await rowOf(id);
        expect(row.status, 'running');
        expect(row.accumulatedSeconds, 600, reason: 'the time saved so far');
        expect(row.segmentStartedAtUtc, harness.clock.nowUtc());
        expect(row.endedAtUtc, isNull);
        expect(row.completedLocalDate, isNull);
        expect(row.gamificationEligible, isFalse);
        expect(row.timezoneId, 'Europe/Berlin');
        expect(projection.syncs, [
          {LocalDate(2026, 10, 3)},
        ], reason: 'the completion day is re-synced');
        await flush();
        expect(events.whereType<ActivityRemoved>(), hasLength(1));
        expect(events.whereType<FocusStateChanged>(), hasLength(1));
      },
    );

    test('undo of a save from paused reopens it paused', () async {
      final id = await start();
      advance(200);
      await pause(id);
      advance(10);
      final saved = await save(id);
      await saved.undo!.run(harness.ids.newId());
      final row = await rowOf(id);
      expect(row.status, 'paused');
      expect(row.accumulatedSeconds, 200);
      expect(row.segmentStartedAtUtc, isNull);
    });

    test('undo of a save from awaiting reopens it awaiting', () async {
      final id = await start(planned: 600);
      advance(10000);
      await markAwaiting(id);
      final saved = await save(id);
      await saved.undo!.run(harness.ids.newId());
      final row = await rowOf(id);
      expect(row.status, 'awaiting_confirmation');
      expect(row.accumulatedSeconds, 600);
    });

    test('the zone of the start comes back with the undo', () async {
      final id = await start();
      harness.clock.setTimeZone('Asia/Tokyo');
      advance(100);
      final saved = await save(id);
      expect((await rowOf(id)).timezoneId, 'Asia/Tokyo');
      await saved.undo!.run(harness.ids.newId());
      expect((await rowOf(id)).timezoneId, 'Europe/Berlin');
    });

    test(
      'undo of a discard reopens the session in its previous state',
      () async {
        final id = await start(planned: 3600);
        advance(300);
        final discarded = await discard(id);
        advance(20);
        projection.syncs.clear();
        await discarded.undo!.run(harness.ids.newId());
        final row = await rowOf(id);
        expect(row.status, 'running');
        expect(row.accumulatedSeconds, 300);
        expect(row.segmentStartedAtUtc, harness.clock.nowUtc());
        expect(projection.syncs, isEmpty, reason: 'a discard never counted');
      },
    );

    test(
      'undo is refused when another session was started meanwhile',
      () async {
        final first = await start();
        advance(100);
        final saved = await save(first);
        final second = await start();
        await expectLater(
          saved.undo!.run(harness.ids.newId()),
          throwsA(
            isA<ConflictFailure>()
                .having((f) => f.kind, 'kind', ConflictKind.openFocusSession)
                .having((f) => f.relatedEntityId, 'open', second),
          ),
        );
        expect((await rowOf(first)).status, 'completed');
      },
    );

    test('undo is refused when the note changed after the save', () async {
      final id = await start();
      advance(100);
      final saved = await save(id);
      await repository.updateNote(
        commandId: harness.ids.newId(),
        id: id,
        note: 'inzwischen',
      );
      await expectLater(
        saved.undo!.run(harness.ids.newId()),
        conflict(ConflictKind.staleVersion),
      );
      expect((await rowOf(id)).status, 'completed');
    });

    test('undo is refused after the session was deleted', () async {
      final id = await start();
      advance(100);
      final saved = await save(id);
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await expectLater(
        saved.undo!.run(harness.ids.newId()),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('an undo is itself idempotent', () async {
      final id = await start();
      advance(100);
      final saved = await save(id);
      final first = await saved.undo!.run('u1');
      final second = await saved.undo!.run('u1');
      expect(first.replayed, isFalse);
      expect(second.replayed, isTrue);
      expect((await rowOf(id)).status, 'running');
    });
  });

  group('reads', () {
    test('watchOpen follows the lifecycle: null, session, null', () async {
      final emissions = <FocusSession?>[];
      final subscription = repository.watchOpen().listen(emissions.add);
      addTearDown(subscription.cancel);
      await flush();
      final id = await start();
      await flush();
      advance(60);
      await pause(id);
      await flush();
      await save(id);
      await flush();
      expect(emissions.first, isNull);
      expect(emissions.whereType<FocusSession>().map((s) => s.status), [
        FocusStatus.running,
        FocusStatus.paused,
      ]);
      expect(emissions.last, isNull, reason: 'a completed session is not open');
    });

    test('history lists completed sessions newest first, excluding discarded, open and deleted', () async {
      final a = await start();
      advance(100);
      await save(a);
      advance(60);
      final b = await start();
      advance(200);
      await save(b);
      advance(60);
      final discarded = await start();
      advance(10);
      await discard(discarded);
      advance(60);
      final deleted = await start();
      advance(10);
      await save(deleted);
      await repository.delete(commandId: harness.ids.newId(), id: deleted);
      advance(60);
      final open = await start();
      final history = await repository.watchHistory().first;
      expect(history.map((s) => s.id), [b, a]);
      expect(history.map((s) => s.accumulatedSeconds), [200, 100]);
      expect(history.map((s) => s.id), isNot(contains(open)));
    });

    test('the history can be paged', () async {
      final ids = <String>[];
      for (var i = 0; i < 5; i++) {
        final id = await start();
        advance(10 + i);
        await save(id);
        advance(5);
        ids.add(id);
      }
      final newestFirst = ids.reversed.toList();
      expect(
        (await repository.fetchHistory(limit: 2)).map((s) => s.id),
        newestFirst.take(2),
      );
      expect(
        (await repository.fetchHistory(limit: 2, offset: 2)).map((s) => s.id),
        newestFirst.skip(2).take(2),
      );
      expect(
        (await repository.fetchHistory(limit: 2, offset: 4)).map((s) => s.id),
        newestFirst.skip(4),
      );
      expect(
        (await repository.watchHistory(limit: 3).first).map((s) => s.id),
        newestFirst.take(3),
      );
    });

    test('completed-on-date reads the confirmation day', () async {
      harness.clock.setNow(DateTime.utc(2026, 10, 3, 21, 50));
      final late = await start();
      harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 10));
      await save(late); // completed on the 4th (Berlin)
      harness.clock.setNow(DateTime.utc(2026, 10, 3, 12, 0));
      final earlier = await start();
      advance(100);
      await save(earlier); // completed on the 3rd
      expect(
        (await repository.watchCompletedOn(LocalDate(2026, 10, 3)).first).map(
          (s) => s.id,
        ),
        [earlier],
      );
      expect(
        (await repository.watchCompletedOn(LocalDate(2026, 10, 4)).first).map(
          (s) => s.id,
        ),
        [late],
      );
      expect(
        await repository.watchCompletedOn(LocalDate(2026, 10, 5)).first,
        isEmpty,
      );
    });

    test('watchById emits null after the session is deleted', () async {
      final id = await start();
      advance(100);
      await save(id);
      final emissions = <FocusSession?>[];
      final subscription = repository.watchById(id).listen(emissions.add);
      addTearDown(subscription.cancel);
      await flush();
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await flush();
      expect(emissions.first, isNotNull);
      expect(emissions.last, isNull);
    });

    test('the persisted rows map to the domain model', () async {
      final id = await start(category: FocusCategory.meditation, planned: 900);
      final session = (await repository.findById(id))!;
      expect(session.category, FocusCategory.meditation);
      expect(session.plannedSeconds, 900);
      expect(session.status, FocusStatus.running);
      expect(
        session.expectedEndUtc,
        startTime.add(const Duration(seconds: 900)),
      );
      expect(session.rowVersion, 1);
      expect(session.isOpen, isTrue);
    });
  });
}
