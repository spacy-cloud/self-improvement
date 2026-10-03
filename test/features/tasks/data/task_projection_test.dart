import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/tasks/data/task_repository.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/task_test_support.dart';

/// Runs the real projection and THEN fails, like a disk error at the very end
/// of the transaction: everything the sync wrote must be rolled back.
final class _FailAfterSync implements ProjectionSynchronizer {
  _FailAfterSync(this._inner);

  final ProjectionSynchronizer _inner;
  bool failing = true;

  @override
  Future<void> syncDays(Set<LocalDate> days) async {
    await _inner.syncDays(days);
    if (failing) {
      throw StateError('disk full');
    }
  }

  @override
  Future<int> totalXp() => _inner.totalXp();
}

void main() {
  setUpAll(allowMultipleDatabases);

  late DataHarness harness;
  late TaskRepository repository;

  final today = LocalDate(2026, 10, 3);
  final yesterday = LocalDate(2026, 10, 2);

  setUp(() async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    repository = TaskRepository(
      database: harness.database,
      runner: harness.runner,
    );
  });
  tearDown(() => harness.dispose());

  Future<String> create([String title = 'Aufgabe']) async {
    final outcome = await repository.create(
      commandId: harness.ids.newId(),
      draft: TaskDraft(title: title),
    );
    return outcome.entityId!;
  }

  Future<CommandOutcome> complete(String id) => repository.setCompleted(
    commandId: harness.ids.newId(),
    id: id,
    completed: true,
  );

  Future<CommandOutcome> reopen(String id) => repository.setCompleted(
    commandId: harness.ids.newId(),
    id: id,
    completed: false,
  );

  /// Creates and completes a task, one minute after the previous call.
  Future<String> createCompleted(String title) async {
    harness.clock.advance(const Duration(minutes: 1));
    final id = await create(title);
    await complete(id);
    return id;
  }

  Future<int> xp() => harness.totalXp();

  Future<Set<String>> awardKeys() async =>
      (await awardPoints(harness)).keys.toSet();

  group('AT13: complete, reopen, complete again', () {
    test(
      'XP never piles up and exactly one award exists per completion',
      () async {
        final id = await create();
        expect(await xp(), 0, reason: 'creating earns nothing');
        for (var round = 0; round < 3; round++) {
          harness.clock.advance(const Duration(minutes: 1));
          await complete(id);
          expect(await xp(), 10, reason: 'completed in round $round');
          expect(await awardKeys(), {'task:$id'});
          harness.clock.advance(const Duration(minutes: 1));
          await reopen(id);
          expect(await xp(), 0, reason: 'reopened in round $round');
          expect(await awardKeys(), isEmpty);
        }
      },
    );

    test(
      'the award is a task award worth 10 XP on the completion day',
      () async {
        final id = await create();
        await complete(id);
        final rows = await harness.database
            .select(harness.database.xpAwards)
            .get();
        final award = rows.single;
        expect(award.awardKey, 'task:$id');
        expect(award.sourceKind, 'task');
        expect(award.sourceId, id);
        expect(award.points, 10);
        expect(award.localDate, today);
        expect(award.ruleVersion, 1);
      },
    );

    test('five tasks earn 50 XP, the sixth and seventh earn nothing', () async {
      final ids = [for (var i = 1; i <= 7; i++) await createCompleted('T$i')];
      expect(await xp(), 50);
      expect(await awardKeys(), {for (final id in ids.take(5)) 'task:$id'});
    });

    test('reopening one of the first five lets the next one move up (still 50)', () async {
      final ids = [for (var i = 1; i <= 6; i++) await createCompleted('T$i')];
      expect(await xp(), 50);
      expect(await awardKeys(), isNot(contains('task:${ids[5]}')));

      harness.clock.advance(const Duration(minutes: 1));
      await reopen(ids[0]);
      expect(await xp(), 50, reason: 'the sixth task took the free place');
      expect(await awardKeys(), {for (final id in ids.skip(1)) 'task:$id'});

      // Completing the first task again makes it the LAST completion: it is
      // the sixth of the day now and earns nothing, the total never exceeds 50.
      harness.clock.advance(const Duration(minutes: 1));
      await complete(ids[0]);
      expect(await xp(), 50);
      expect(await awardKeys(), {for (final id in ids.skip(1)) 'task:$id'});
    });

    test('the limit of five applies per stored completion day', () async {
      setLocalNow(harness, yesterday);
      final first = [
        for (var i = 1; i <= 5; i++) await createCompleted('Alt$i'),
      ];
      setLocalNow(harness, today);
      final second = [
        for (var i = 1; i <= 5; i++) await createCompleted('Neu$i'),
      ];
      expect(await xp(), 100);
      final awards = await awardPoints(harness);
      expect(awards.keys.toSet(), {
        for (final id in [...first, ...second]) 'task:$id',
      });
    });

    test(
      'a replayed command and a repeated tap do not award again (AT12)',
      () async {
        final id = await create();
        await repository.setCompleted(
          commandId: 'tap',
          id: id,
          completed: true,
        );
        await repository.setCompleted(
          commandId: 'tap',
          id: id,
          completed: true,
        );
        await complete(id); // a second tap with a new id: already completed
        await complete(id);
        expect(await xp(), 10);
        expect(await awardKeys(), {'task:$id'});
      },
    );

    test(
      'two simultaneous completions with different command ids complete once',
      () async {
        final id = await create();
        final results = await Future.wait([complete(id), complete(id)]);
        expect(
          results.where((r) => r.undo != null),
          hasLength(1),
          reason: 'only one of them changed the task',
        );
        expect((await repository.findById(id))!.rowVersion, 2);
        expect(await xp(), 10);
        expect(await awardKeys(), {'task:$id'});
      },
    );

    test(
      'a completion across local midnight is counted on its own day',
      () async {
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 21, 55)); // 23:55 Berlin
        final evening = [
          for (var i = 1; i <= 5; i++)
            await _completeAt(harness, repository, i),
        ];
        expect(await xp(), 50);
        // 00:00:30 on the next local day: the fifth-per-day limit starts anew.
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 0, 30));
        final next = await create('Nach Mitternacht');
        await complete(next);
        expect(await xp(), 60);
        final rows = await harness.database
            .select(harness.database.xpAwards)
            .get();
        expect(
          rows.singleWhere((r) => r.awardKey == 'task:$next').localDate,
          LocalDate(2026, 10, 4),
        );
        expect(
          rows.where((r) => r.localDate == today),
          hasLength(evening.length),
        );
      },
    );
  });

  group('eligibility is frozen per completion (T01, AT26)', () {
    test('completed while gamification is off: no XP, not even after switching it on', () async {
      await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
      final id = await create();
      await complete(id);
      expect((await repository.findById(id))!.completionEligibility, isFalse);
      expect(await xp(), 0);

      harness.clock.advance(const Duration(minutes: 1));
      await setModuleEnabled(harness, ModuleId.gamification, enabled: true);
      // Any later command of that day re-runs the projection.
      final other = await create('Andere');
      await complete(other);
      expect(await xp(), 10, reason: 'only the new task counts');
      expect(await awardKeys(), {'task:$other'});
    });

    test(
      'reopen and complete again with gamification on is eligible',
      () async {
        await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
        final id = await create();
        await complete(id);
        expect(await xp(), 0);

        harness.clock.advance(const Duration(minutes: 1));
        await setModuleEnabled(harness, ModuleId.gamification, enabled: true);
        harness.clock.advance(const Duration(minutes: 1));
        await reopen(id);
        harness.clock.advance(const Duration(minutes: 1));
        await complete(id);
        expect((await repository.findById(id))!.completionEligibility, isTrue);
        expect(await xp(), 10);
      },
    );

    test('earned XP survives switching gamification off, a correction still removes it', () async {
      final id = await create();
      await complete(id);
      expect(await xp(), 10);
      harness.clock.advance(const Duration(minutes: 1));
      await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
      // Another command of the day re-runs the projection: nothing changes.
      final unrelated = await create('Unbeteiligt');
      await repository.delete(commandId: harness.ids.newId(), id: unrelated);
      await complete(await create('Neue Aufgabe'));
      expect(await xp(), 10, reason: 'the new completion is not eligible');
      await reopen(id);
      expect(await xp(), 0, reason: 'corrections subtract even when off');
    });

    test(
      'an ineligible completion does not take one of the five places',
      () async {
        await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
        final ineligible = await create('Ohne XP');
        await complete(ineligible);
        harness.clock.advance(const Duration(minutes: 1));
        await setModuleEnabled(harness, ModuleId.gamification, enabled: true);
        final ids = [for (var i = 1; i <= 5; i++) await createCompleted('T$i')];
        expect(await xp(), 50);
        expect(await awardKeys(), {for (final id in ids) 'task:$id'});
      },
    );

    test('undo of a completion/reopen restores the exact flag, not the current one', () async {
      // Case 1: completed while OFF, reopened, switched ON, reopen undone.
      await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
      final off = await create('Aus');
      await complete(off);
      harness.clock.advance(const Duration(minutes: 1));
      await setModuleEnabled(harness, ModuleId.gamification, enabled: true);
      final reopenedOff = await reopen(off);
      await reopenedOff.undo!.run(harness.ids.newId());
      expect((await repository.findById(off))!.completionEligibility, isFalse);
      expect(await xp(), 0, reason: 'the restored completion is not eligible');

      // Case 2: completed while ON, switched OFF, reopened, reopen undone.
      harness.clock.advance(const Duration(minutes: 1));
      final on = await create('An');
      await complete(on);
      expect(await xp(), 10);
      harness.clock.advance(const Duration(minutes: 1));
      await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
      final reopenedOn = await reopen(on);
      expect(await xp(), 0);
      await reopenedOn.undo!.run(harness.ids.newId());
      expect((await repository.findById(on))!.completionEligibility, isTrue);
      expect(await xp(), 10, reason: 'the original flag is back');
    });

    test('undoing a completion removes its XP again', () async {
      final id = await create();
      final done = await complete(id);
      expect(await xp(), 10);
      await done.undo!.run(harness.ids.newId());
      expect(await xp(), 0);
      expect(await awardKeys(), isEmpty);
    });
  });

  group('deleting a task (T01)', () {
    test(
      'a deleted completed task takes its XP with it, undo brings it back',
      () async {
        final id = await create();
        await complete(id);
        expect(await xp(), 10);
        final deleted = await repository.delete(
          commandId: harness.ids.newId(),
          id: id,
        );
        expect(await xp(), 0);
        await deleted.undo!.run(harness.ids.newId());
        expect(await xp(), 10);
        expect(await awardKeys(), {'task:$id'});
      },
    );

    test('deleting an open task changes no XP', () async {
      final done = await create('Fertig');
      await complete(done);
      final open = await create('Offen');
      await repository.delete(commandId: harness.ids.newId(), id: open);
      expect(await xp(), 10);
    });
  });

  group(
    'AT23: correcting the past changes ring, XP and streak consistently',
    () {
      late DayStatusRepositoryHandle days;

      setUp(() => days = DayStatusRepositoryHandle(harness));

      /// Completes one task on [day] (clock at 10:00 that day).
      Future<String> completeOn(LocalDate day, String title) async {
        setLocalNow(harness, day);
        final id = await create(title);
        await complete(id);
        return id;
      }

      test(
        'reopening a task of a past day lowers that day, the XP and the streak',
        () async {
          final past = await completeOn(yesterday, 'Gestern');
          await completeOn(today, 'Heute');
          expect(await xp(), 20);
          expect((await days.status(yesterday)).fulfilledCount, 1);
          expect(await days.streak(), (current: 2, longest: 2));

          await reopen(past);
          expect(await xp(), 10);
          final status = await days.status(yesterday);
          expect(status.fulfilledCount, 0);
          expect(status.isActive, isFalse);
          expect(await days.streak(), (current: 1, longest: 1));
        },
      );

      test(
        'deleting a past completion and undoing it restores everything',
        () async {
          final past = await completeOn(yesterday, 'Gestern');
          await completeOn(today, 'Heute');
          final deleted = await repository.delete(
            commandId: harness.ids.newId(),
            id: past,
          );
          expect(await xp(), 10);
          expect(await days.streak(), (current: 1, longest: 1));
          await deleted.undo!.run(harness.ids.newId());
          expect(await xp(), 20);
          expect((await days.status(yesterday)).fulfilledCount, 1);
          expect(await days.streak(), (current: 2, longest: 2));
        },
      );

      test(
        'the correction only touches the completion day, other days stay',
        () async {
          final a = await completeOn(LocalDate(2026, 9, 29), 'A');
          await completeOn(LocalDate(2026, 9, 30), 'B');
          await completeOn(LocalDate(2026, 10, 1), 'C');
          await completeOn(yesterday, 'D');
          await completeOn(today, 'E');
          expect(await days.streak(), (current: 5, longest: 5));
          expect(await xp(), 50);

          // Reopening the OLDEST day shortens only the start of the run.
          await reopen(a);
          expect(await days.streak(), (current: 4, longest: 4));
          expect(await xp(), 40);
          // Reopening a MIDDLE day splits the run: longest drops, current too.
          final middle = (await repository.watchActive().first).firstWhere(
            (Task t) => t.title == 'C',
          );
          await reopen(middle.id);
          expect(await days.streak(), (current: 2, longest: 2));
          expect(await xp(), 30);
        },
      );

      test(
        'a day with another completed task stays active after one is reopened',
        () async {
          final first = await completeOn(yesterday, 'Eins');
          setLocalNow(harness, yesterday, const LocalTime(11, 0));
          final second = await create('Zwei');
          await complete(second);
          setLocalNow(harness, today);
          await reopen(first);
          final status = await days.status(yesterday);
          expect(status.isActive, isTrue, reason: 'one completed task remains');
          expect(await xp(), 10);
        },
      );

      test('the ring of today follows completion and reopening live', () async {
        final id = await create();
        expect((await days.status(today)).fulfilledCount, 0);
        await complete(id);
        var status = await days.status(today);
        expect(status.fulfilledCount, 1);
        expect(status.applicableCount, 5);
        expect(status.ringFraction, closeTo(0.2, 1e-9));
        await reopen(id);
        status = await days.status(today);
        expect(status.fulfilledCount, 0);
      });
    },
  );

  group('atomicity (AT27): a storage failure rolls back completion and XP', () {
    late _FailAfterSync failing;
    late TaskRepository failingRepository;

    setUp(() {
      failing = _FailAfterSync(harness.projections);
      final runner = CommandRunner(
        database: harness.database,
        clock: harness.clock,
        ids: harness.ids,
        projections: failing,
        events: harness.events,
        gamificationEnabled: () =>
            harness.moduleStatus.isEnabled(ModuleId.gamification),
      );
      failingRepository = TaskRepository(
        database: harness.database,
        runner: runner,
      );
    });

    test(
      'nothing is committed: task still open, no award, no receipt',
      () async {
        final id = await create();
        failing.failing = true;
        await expectLater(
          failingRepository.setCompleted(
            commandId: 'fail',
            id: id,
            completed: true,
          ),
          throwsA(isA<StorageFailure>()),
        );
        expect((await repository.findById(id))!.isOpen, isTrue);
        expect(await xp(), 0);
        expect(await awardKeys(), isEmpty);
        final receipts = await harness.database
            .select(harness.database.commandReceipts)
            .get();
        expect(receipts.where((r) => r.commandId == 'fail'), isEmpty);
      },
    );

    test('the retry with the SAME id succeeds once, XP exactly 10', () async {
      final id = await create();
      failing.failing = true;
      await expectLater(
        failingRepository.setCompleted(
          commandId: 'retry',
          id: id,
          completed: true,
        ),
        throwsA(isA<StorageFailure>()),
      );
      failing.failing = false;
      final outcome = await failingRepository.setCompleted(
        commandId: 'retry',
        id: id,
        completed: true,
      );
      expect(
        outcome.replayed,
        isFalse,
        reason: 'the first attempt left nothing',
      );
      expect(await xp(), 10);
      final again = await failingRepository.setCompleted(
        commandId: 'retry',
        id: id,
        completed: true,
      );
      expect(again.replayed, isTrue);
      expect(await xp(), 10);
    });

    test('a failing reopen keeps the completion and its XP', () async {
      final id = await create();
      await complete(id);
      failing.failing = true;
      await expectLater(
        failingRepository.setCompleted(
          commandId: 'fail-reopen',
          id: id,
          completed: false,
        ),
        throwsA(isA<StorageFailure>()),
      );
      expect((await repository.findById(id))!.isCompleted, isTrue);
      expect(await xp(), 10);
    });

    test('a failing delete keeps the task and its XP', () async {
      final id = await create();
      await complete(id);
      failing.failing = true;
      await expectLater(
        failingRepository.delete(commandId: 'fail-delete', id: id),
        throwsA(isA<StorageFailure>()),
      );
      expect(await repository.findById(id), isNotNull);
      expect(await xp(), 10);
    });
  });
}

/// Completes a fresh task at a fixed instant minute offset (helper of the
/// midnight test) and returns its id.
Future<String> _completeAt(
  DataHarness harness,
  TaskRepository repository,
  int index,
) async {
  harness.clock.advance(const Duration(seconds: 10));
  final created = await repository.create(
    commandId: harness.ids.newId(),
    draft: TaskDraft(title: 'Spät $index'),
  );
  await repository.setCompleted(
    commandId: harness.ids.newId(),
    id: created.entityId!,
    completed: true,
  );
  return created.entityId!;
}

/// Small read helper over the real day status repository.
final class DayStatusRepositoryHandle {
  DayStatusRepositoryHandle(this._harness);

  final DataHarness _harness;

  Future<DayStatus> status(LocalDate day) async =>
      (await _harness.dayStatusRepository().statusFor(day))!;

  Future<({int current, int longest})> streak() async {
    final summary = (await _harness
        .dayStatusRepository()
        .computeStreakSummary())!;
    return (current: summary.current, longest: summary.longest);
  }
}
