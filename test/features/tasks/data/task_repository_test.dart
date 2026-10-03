import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/tasks/data/task_repository.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/features/tasks/domain/task_validation.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/task_test_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  late DataHarness harness;
  late RecordingProjectionSynchronizer projection;
  late TaskRepository repository;

  setUp(() async {
    projection = RecordingProjectionSynchronizer();
    harness = await DataHarness.create(projections: projection);
    repository = TaskRepository(
      database: harness.database,
      runner: harness.runner,
    );
  });
  tearDown(() => harness.dispose());

  // "now" is 2026-10-03 08:00Z = 10:00 in Berlin (a Saturday).
  final today = LocalDate(2026, 10, 3);

  TaskDraft draft({
    String title = 'Steuererklärung',
    String? description,
    TaskPriority priority = TaskPriority.normal,
    LocalDate? dueDate,
    List<String> tags = const [],
  }) => TaskDraft(
    title: title,
    description: description,
    priority: priority,
    dueDate: dueDate,
    tags: tags,
  );

  Future<String> create([TaskDraft? d, String? commandId]) async {
    final outcome = await repository.create(
      commandId: commandId ?? harness.ids.newId(),
      draft: d ?? draft(),
    );
    return outcome.entityId!;
  }

  Future<List<Task>> all() => repository.watchActive().first;

  Future<TaskRow> rawRow(String id) => (harness.database.select(
    harness.database.tasks,
  )..where((t) => t.id.equals(id))).getSingle();

  Future<Task> reload(String id) async => (await repository.findById(id))!;

  Future<List<CommandReceiptRow>> receipts() =>
      harness.database.select(harness.database.commandReceipts).get();

  Future<void> complete(String id, {String? commandId}) async {
    await repository.setCompleted(
      commandId: commandId ?? harness.ids.newId(),
      id: id,
      completed: true,
    );
  }

  Future<void> reopen(String id) async {
    await repository.setCompleted(
      commandId: harness.ids.newId(),
      id: id,
      completed: false,
    );
  }

  Matcher conflict(ConflictKind kind) =>
      throwsA(isA<ConflictFailure>().having((f) => f.kind, 'kind', kind));

  group('create (T01)', () {
    test('stores the normalised content as an OPEN task', () async {
      final id = await create(
        draft(
          title: '  Steuer machen  ',
          description: '  Belege sammeln ',
          priority: TaskPriority.high,
          dueDate: LocalDate(2026, 10, 15),
          tags: ['Finanzen', 'finanzen', ' Büro '],
        ),
      );
      final task = await reload(id);
      expect(task.title, 'Steuer machen');
      expect(task.description, 'Belege sammeln');
      expect(task.priority, TaskPriority.high);
      expect(task.dueDate, LocalDate(2026, 10, 15));
      expect(task.tags, ['Finanzen', 'Büro']);
      expect(task.isOpen, isTrue);
      expect(task.completedAtUtc, isNull);
      expect(task.completedLocalDate, isNull);
      expect(task.completionTimezoneId, isNull);
      expect(task.completionEligibility, isNull);
      expect(task.rowVersion, 1);
      expect(task.createdAtUtc, harness.clock.nowUtc());
    });

    test(
      'defaults: normal priority, no date, no tags, no description',
      () async {
        final task = await reload(await create(draft(title: 'Minimal')));
        expect(task.priority, TaskPriority.normal);
        expect(task.dueDate, isNull);
        expect(task.tags, isEmpty);
        expect(task.description, isNull);
      },
    );

    test('tags are persisted as a JSON array', () async {
      final id = await create(draft(tags: ['a', 'b']));
      final raw = await harness.database
          .customSelect(
            'SELECT tags_json AS t FROM tasks WHERE id = ?1',
            variables: [Variable(id)],
          )
          .getSingle();
      expect(raw.read<String>('t'), '["a","b"]');
    });

    test('an open task needs no projection sync', () async {
      await create();
      expect(projection.syncs, isEmpty);
    });

    test(
      'the same command id is one task, a new id a new task (AT12)',
      () async {
        final first = await repository.create(commandId: 'c1', draft: draft());
        final replay = await repository.create(commandId: 'c1', draft: draft());
        expect(replay.replayed, isTrue);
        expect(replay.entityId, first.entityId);
        expect(replay.undo, isNull, reason: 'a replay offers no new undo');
        expect(await all(), hasLength(1));
        await repository.create(commandId: 'c2', draft: draft());
        expect(await all(), hasLength(2));
      },
    );

    test('the outcome carries the undo and the new id', () async {
      final outcome = await repository.create(commandId: 'c1', draft: draft());
      expect(outcome.entityId, isNotNull);
      expect(outcome.undo, isNotNull);
      expect(outcome.replayed, isFalse);
    });
  });

  group('validation at the repository (T01 boundaries)', () {
    Future<ValidationFailure> failure(TaskDraft d) async {
      try {
        await create(d);
      } on ValidationFailure catch (error) {
        return error;
      }
      fail('expected a ValidationFailure');
    }

    test('title 120 is stored, 121 is rejected', () async {
      await create(draft(title: 'a' * 120));
      expect(
        (await failure(draft(title: 'a' * 121))).fieldErrors.keys,
        contains(TaskFields.title),
      );
    });

    test('description 1000 is stored, 1001 is rejected', () async {
      await create(draft(description: 'd' * 1000));
      expect(
        (await failure(draft(description: 'd' * 1001))).fieldErrors.keys,
        contains(TaskFields.description),
      );
    });

    test(
      'five tags are stored, six rejected; tag 20 stored, 21 rejected',
      () async {
        await create(draft(tags: ['a', 'b', 'c', 'd', 'e']));
        await create(draft(tags: ['t' * 20]));
        expect(
          (await failure(draft(tags: ['a', 'b', 'c', 'd', 'e', 'f'])))
              .fieldErrors
              .keys,
          contains(TaskFields.tags),
        );
        expect(
          (await failure(draft(tags: ['t' * 21]))).fieldErrors.keys,
          contains(TaskFields.tags),
        );
      },
    );

    test(
      'a title of 120 astral characters passes the database check too',
      () async {
        final id = await create(draft(title: astralChar * 120));
        expect((await reload(id)).title, astralChar * 120);
      },
    );

    test(
      'a rejected draft leaves no task, no receipt, no projection call',
      () async {
        await failure(draft(title: ' '));
        expect(await all(), isEmpty);
        expect(await receipts(), isEmpty);
        expect(projection.syncs, isEmpty);
      },
    );
  });

  group('update (edit changes content only)', () {
    test('changes title, description, priority, due date and tags', () async {
      final id = await create(draft(title: 'alt', tags: ['x']));
      final before = await reload(id);
      harness.clock.advance(const Duration(minutes: 5));
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(
          title: 'neu',
          description: 'mehr',
          priority: TaskPriority.low,
          dueDate: LocalDate(2026, 11, 1),
          tags: ['y', 'z'],
        ),
        expectedRowVersion: before.rowVersion,
      );
      final after = await reload(id);
      expect(after.title, 'neu');
      expect(after.description, 'mehr');
      expect(after.priority, TaskPriority.low);
      expect(after.dueDate, LocalDate(2026, 11, 1));
      expect(after.tags, ['y', 'z']);
      expect(after.rowVersion, before.rowVersion + 1);
      expect(after.updatedAtUtc.isAfter(before.updatedAtUtc), isTrue);
      expect(after.createdAtUtc, before.createdAtUtc);
    });

    test('the due date and the description can be cleared', () async {
      final id = await create(
        draft(description: 'text', dueDate: LocalDate(2026, 10, 9)),
      );
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(),
        expectedRowVersion: 1,
      );
      final after = await reload(id);
      expect(after.description, isNull);
      expect(after.dueDate, isNull);
    });

    test('never changes the completion, its flag or its day', () async {
      final id = await create();
      await complete(id);
      final completed = await reload(id);
      harness.clock.advance(const Duration(days: 2));
      projection.syncs.clear();
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(title: 'umbenannt', priority: TaskPriority.high),
        expectedRowVersion: completed.rowVersion,
      );
      final after = await reload(id);
      expect(after.title, 'umbenannt');
      expect(after.isCompleted, isTrue);
      expect(after.completedAtUtc, completed.completedAtUtc);
      expect(after.completedLocalDate, completed.completedLocalDate);
      expect(after.completionTimezoneId, completed.completionTimezoneId);
      expect(after.completionEligibility, completed.completionEligibility);
      expect(projection.syncs, isEmpty, reason: 'no fact day is affected');
    });

    test('a stale form version is a conflict and changes nothing', () async {
      final id = await create(draft(title: 'bleibt'));
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(title: 'neu'),
          expectedRowVersion: 99,
        ),
        conflict(ConflictKind.staleVersion),
      );
      expect((await reload(id)).title, 'bleibt');
    });

    test(
      'an edit after a completion makes the old form version stale',
      () async {
        final id = await create();
        final formVersion = (await reload(id)).rowVersion;
        await complete(id);
        await expectLater(
          repository.update(
            commandId: harness.ids.newId(),
            id: id,
            draft: draft(title: 'x'),
            expectedRowVersion: formVersion,
          ),
          conflict(ConflictKind.staleVersion),
        );
      },
    );

    test('an invalid edit changes nothing', () async {
      final id = await create(draft(title: 'bleibt'));
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(title: ''),
          expectedRowVersion: 1,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect((await reload(id)).title, 'bleibt');
      expect((await reload(id)).rowVersion, 1);
    });

    test('a missing or deleted task is NotFound', () async {
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: 'missing',
          draft: draft(),
          expectedRowVersion: 1,
        ),
        throwsA(isA<NotFoundFailure>()),
      );
      final id = await create();
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(),
          expectedRowVersion: 2,
        ),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('completion is a desired state (T01, AT12, AT13)', () {
    test(
      'completing freezes time, local date, zone and the eligibility flag',
      () async {
        final id = await create();
        await complete(id);
        final task = await reload(id);
        expect(task.isCompleted, isTrue);
        expect(task.completedAtUtc, DateTime.utc(2026, 10, 3, 8));
        expect(task.completedLocalDate, today);
        expect(task.completionTimezoneId, 'Europe/Berlin');
        expect(task.completionEligibility, isTrue);
        expect(task.rowVersion, 2);
        expect(projection.syncs.single, {today});
      },
    );

    test('eligibility is false when gamification is off right now', () async {
      await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
      final id = await create();
      await complete(id);
      expect((await reload(id)).completionEligibility, isFalse);
    });

    test('the same command id again is a replay and changes nothing', () async {
      final id = await create();
      final first = await repository.setCompleted(
        commandId: 'tap',
        id: id,
        completed: true,
      );
      final completedAt = (await reload(id)).completedAtUtc;
      harness.clock.advance(const Duration(minutes: 30));
      projection.syncs.clear();
      final replay = await repository.setCompleted(
        commandId: 'tap',
        id: id,
        completed: true,
      );
      expect(first.replayed, isFalse);
      expect(replay.replayed, isTrue);
      expect(replay.entityId, id);
      expect(replay.undo, isNull);
      final task = await reload(id);
      expect(task.completedAtUtc, completedAt);
      expect(task.rowVersion, 2);
      expect(projection.syncs, isEmpty);
    });

    test('a NEW command id for an already completed task keeps the existing completion (AT12)', () async {
      final id = await create();
      await complete(id);
      final before = await reload(id);
      harness.clock.advance(const Duration(hours: 3));
      projection.syncs.clear();
      final outcome = await repository.setCompleted(
        commandId: harness.ids.newId(),
        id: id,
        completed: true,
      );
      expect(outcome.replayed, isFalse);
      expect(outcome.undo, isNull, reason: 'nothing changed, nothing to undo');
      final after = await reload(id);
      expect(after.completedAtUtc, before.completedAtUtc);
      expect(after.completionEligibility, before.completionEligibility);
      expect(after.rowVersion, before.rowVersion, reason: 'no new version');
      expect(projection.syncs, isEmpty);
    });

    test('reopening an open task is a no-op without undo', () async {
      final id = await create();
      final outcome = await repository.setCompleted(
        commandId: harness.ids.newId(),
        id: id,
        completed: false,
      );
      expect(outcome.undo, isNull);
      expect((await reload(id)).rowVersion, 1);
    });

    test(
      'reopening clears every completion field including the flag',
      () async {
        final id = await create();
        await complete(id);
        await reopen(id);
        final raw = await rawRow(id);
        expect(raw.completedAtUtc, isNull);
        expect(raw.completedLocalDate, isNull);
        expect(raw.timezoneId, isNull);
        expect(raw.completionEligibility, isNull);
        expect(raw.rowVersion, 3);
      },
    );

    test('reopening syncs the old completion day AND today', () async {
      final id = await create();
      setLocalNow(harness, LocalDate(2026, 10, 1));
      await complete(id);
      setLocalNow(harness, today);
      projection.syncs.clear();
      await reopen(id);
      expect(projection.syncs.single, {LocalDate(2026, 10, 1), today});
    });

    test(
      'a later deliberate completion is NEW: new time and a new flag',
      () async {
        final id = await create();
        await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
        await complete(id);
        final first = await reload(id);
        expect(first.completionEligibility, isFalse);

        await reopen(id);
        harness.clock.advance(const Duration(minutes: 10));
        await setModuleEnabled(harness, ModuleId.gamification, enabled: true);
        harness.clock.advance(const Duration(minutes: 1));
        await complete(id);
        final second = await reload(id);
        expect(second.completionEligibility, isTrue, reason: 'flag is new');
        expect(second.completedAtUtc!.isAfter(first.completedAtUtc!), isTrue);
      },
    );

    test('desired state works in both directions repeatedly', () async {
      final id = await create();
      for (var i = 0; i < 3; i++) {
        await complete(id);
        expect((await reload(id)).isCompleted, isTrue);
        await reopen(id);
        expect((await reload(id)).isOpen, isTrue);
      }
      expect((await reload(id)).rowVersion, 7);
    });

    test('a deleted or unknown task cannot be completed', () async {
      await expectLater(
        repository.setCompleted(
          commandId: harness.ids.newId(),
          id: 'missing',
          completed: true,
        ),
        throwsA(isA<NotFoundFailure>()),
      );
      final id = await create();
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await expectLater(
        repository.setCompleted(
          commandId: harness.ids.newId(),
          id: id,
          completed: true,
        ),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test(
      'completing publishes a commit event, reopening a removal event',
      () async {
        final events = <AppEvent>[];
        final subscription = harness.events.stream.listen(events.add);
        final id = await create();
        await complete(id);
        await reopen(id);
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();
        expect(
          events.whereType<ActivityCommitted>().map((e) => e.commandType),
          contains(TaskRepository.completeType),
        );
        expect(events.whereType<ActivityRemoved>().map((e) => e.commandType), [
          TaskRepository.reopenType,
        ]);
      },
    );
  });

  group('undo of a completion restores the exact previous state (T01)', () {
    test('undoing a completion reopens the task', () async {
      final id = await create();
      final outcome = await repository.setCompleted(
        commandId: harness.ids.newId(),
        id: id,
        completed: true,
      );
      projection.syncs.clear();
      await outcome.undo!.run(harness.ids.newId());
      final task = await reload(id);
      expect(task.isOpen, isTrue);
      expect(task.completionEligibility, isNull);
      expect(projection.syncs.single, {today});
    });

    test('undoing a reopen restores the earlier completion incl. time, zone and flag', () async {
      await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
      final id = await create();
      setLocalNow(harness, LocalDate(2026, 10, 1), const LocalTime(9, 15));
      await complete(id);
      final original = await reload(id);
      expect(original.completionEligibility, isFalse);

      setLocalNow(harness, today);
      // Gamification is switched on before the reopen; the restored completion
      // must still carry its ORIGINAL flag.
      harness.clock.advance(const Duration(minutes: 1));
      await setModuleEnabled(harness, ModuleId.gamification, enabled: true);
      final reopened = await repository.setCompleted(
        commandId: harness.ids.newId(),
        id: id,
        completed: false,
      );
      projection.syncs.clear();
      await reopened.undo!.run(harness.ids.newId());

      final restored = await reload(id);
      expect(restored.completedAtUtc, original.completedAtUtc);
      expect(restored.completedLocalDate, LocalDate(2026, 10, 1));
      expect(restored.completionTimezoneId, original.completionTimezoneId);
      expect(restored.completionEligibility, isFalse);
      expect(projection.syncs.single, {LocalDate(2026, 10, 1), today});
    });

    test(
      'an eligible completion stays eligible after reopen and undo',
      () async {
        final id = await create();
        await complete(id);
        await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
        final reopened = await repository.setCompleted(
          commandId: harness.ids.newId(),
          id: id,
          completed: false,
        );
        await reopened.undo!.run(harness.ids.newId());
        expect((await reload(id)).completionEligibility, isTrue);
      },
    );

    test('the undo is refused when the task was changed meanwhile', () async {
      final id = await create();
      final outcome = await repository.setCompleted(
        commandId: harness.ids.newId(),
        id: id,
        completed: true,
      );
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(title: 'zwischendurch geändert'),
        expectedRowVersion: 2,
      );
      await expectLater(
        outcome.undo!.run(harness.ids.newId()),
        conflict(ConflictKind.staleVersion),
      );
      expect((await reload(id)).isCompleted, isTrue, reason: 'nothing undone');
    });

    test('the undo is refused after a later completion change', () async {
      final id = await create();
      final completed = await repository.setCompleted(
        commandId: harness.ids.newId(),
        id: id,
        completed: true,
      );
      await reopen(id);
      await expectLater(
        completed.undo!.run(harness.ids.newId()),
        conflict(ConflictKind.staleVersion),
      );
    });

    test('the undo is itself idempotent and offers no further undo', () async {
      final id = await create();
      final outcome = await repository.setCompleted(
        commandId: harness.ids.newId(),
        id: id,
        completed: true,
      );
      final first = await outcome.undo!.run('undo-1');
      final second = await outcome.undo!.run('undo-1');
      expect(first.replayed, isFalse);
      expect(first.undo, isNull);
      expect(second.replayed, isTrue);
      expect((await reload(id)).rowVersion, 3);
    });

    test('undoing the completion of a deleted task is NotFound', () async {
      final id = await create();
      final outcome = await repository.setCompleted(
        commandId: harness.ids.newId(),
        id: id,
        completed: true,
      );
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await expectLater(
        outcome.undo!.run(harness.ids.newId()),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('frozen business date and zone (AT25)', () {
    Future<LocalDate> completedDateAt(DateTime utc) async {
      harness.clock.setNow(utc);
      final id = await create(draft(title: 'T ${utc.toIso8601String()}'));
      await complete(id);
      return (await reload(id)).completedLocalDate!;
    }

    test('completions around local midnight land on the right day', () async {
      expect(
        await completedDateAt(DateTime.utc(2026, 10, 3, 21, 59, 30)),
        LocalDate(2026, 10, 3),
        reason: '23:59:30 in Berlin',
      );
      expect(
        await completedDateAt(DateTime.utc(2026, 10, 3, 22, 0, 30)),
        LocalDate(2026, 10, 4),
        reason: '00:00:30 in Berlin',
      );
    });

    test('around the spring DST change 2026-03-29 (23-hour day)', () async {
      final expected = {
        DateTime.utc(2026, 3, 28, 22, 59): LocalDate(2026, 3, 28),
        DateTime.utc(2026, 3, 28, 23, 0): LocalDate(2026, 3, 29),
        DateTime.utc(2026, 3, 29, 0, 59): LocalDate(2026, 3, 29),
        DateTime.utc(2026, 3, 29, 1, 0): LocalDate(2026, 3, 29),
        DateTime.utc(2026, 3, 29, 21, 59): LocalDate(2026, 3, 29),
        DateTime.utc(2026, 3, 29, 22, 0): LocalDate(2026, 3, 30),
      };
      for (final entry in expected.entries) {
        expect(
          await completedDateAt(entry.key),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    test('around the autumn DST change 2026-10-25 (25-hour day)', () async {
      final expected = {
        DateTime.utc(2026, 10, 24, 21, 59): LocalDate(2026, 10, 24),
        DateTime.utc(2026, 10, 24, 22, 0): LocalDate(2026, 10, 25),
        DateTime.utc(2026, 10, 25, 0, 30): LocalDate(2026, 10, 25),
        DateTime.utc(2026, 10, 25, 1, 30): LocalDate(2026, 10, 25),
        DateTime.utc(2026, 10, 25, 22, 59): LocalDate(2026, 10, 25),
        DateTime.utc(2026, 10, 25, 23, 0): LocalDate(2026, 10, 26),
      };
      for (final entry in expected.entries) {
        expect(
          await completedDateAt(entry.key),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    test('a later zone change never moves an existing completion', () async {
      harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 30));
      final id = await create();
      await complete(id);
      expect((await reload(id)).completedLocalDate, LocalDate(2026, 10, 4));
      harness.clock.setTimeZone('America/New_York');
      final task = await reload(id);
      expect(task.completedLocalDate, LocalDate(2026, 10, 4));
      expect(task.completionTimezoneId, 'Europe/Berlin');
    });

    test(
      'a completion in another zone freezes that zone and its date',
      () async {
        harness.clock.setTimeZone('America/New_York');
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 2, 30));
        final id = await create();
        await complete(id);
        final task = await reload(id);
        expect(task.completedLocalDate, LocalDate(2026, 10, 2));
        expect(task.completionTimezoneId, 'America/New_York');
      },
    );
  });

  group('delete and undo', () {
    test('delete is soft, hides the task and offers undo', () async {
      final id = await create();
      final outcome = await repository.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      expect(await all(), isEmpty);
      expect(await repository.findById(id), isNull);
      final raw = await rawRow(id);
      expect(raw.deletedAtUtc, isNotNull, reason: 'the row is kept');
      expect(outcome.undo, isNotNull);
    });

    test('deleting an open task affects no projection day', () async {
      final id = await create();
      await repository.delete(commandId: harness.ids.newId(), id: id);
      expect(projection.syncs, isEmpty);
    });

    test('deleting a completed task syncs its completion day', () async {
      final id = await create();
      setLocalNow(harness, LocalDate(2026, 10, 1));
      await complete(id);
      setLocalNow(harness, today);
      projection.syncs.clear();
      final outcome = await repository.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      expect(projection.syncs.single, {LocalDate(2026, 10, 1)});
      projection.syncs.clear();
      await outcome.undo!.run(harness.ids.newId());
      expect(projection.syncs.single, {LocalDate(2026, 10, 1)});
      expect((await reload(id)).isCompleted, isTrue);
    });

    test('undoing a delete restores the SAME id with all data', () async {
      final id = await create(
        draft(
          description: 'bleibt',
          priority: TaskPriority.high,
          dueDate: LocalDate(2026, 10, 9),
          tags: ['a'],
        ),
      );
      final outcome = await repository.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      await outcome.undo!.run(harness.ids.newId());
      final restored = await reload(id);
      expect(restored.title, 'Steuererklärung');
      expect(restored.description, 'bleibt');
      expect(restored.priority, TaskPriority.high);
      expect(restored.dueDate, LocalDate(2026, 10, 9));
      expect(restored.tags, ['a']);
    });

    test('undoing a delete is refused if the row changed meanwhile', () async {
      final id = await create();
      final outcome = await repository.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      await (harness.database.update(harness.database.tasks)
            ..where((t) => t.id.equals(id)))
          .write(const TasksCompanion(rowVersion: Value(50)));
      await expectLater(
        outcome.undo!.run(harness.ids.newId()),
        conflict(ConflictKind.staleVersion),
      );
      expect(await repository.findById(id), isNull);
    });

    test('undoing a create removes that task', () async {
      final outcome = await repository.create(commandId: 'u1', draft: draft());
      await outcome.undo!.run(harness.ids.newId());
      expect(await all(), isEmpty);
    });

    test('undoing a create after an edit is refused', () async {
      final created = await repository.create(commandId: 'u1', draft: draft());
      final id = created.entityId!;
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(title: 'geändert'),
        expectedRowVersion: 1,
      );
      await expectLater(
        created.undo!.run(harness.ids.newId()),
        conflict(ConflictKind.staleVersion),
      );
      expect((await reload(id)).title, 'geändert');
    });

    test('undoing an update restores the previous content', () async {
      final id = await create(
        draft(
          title: 'vorher',
          description: 'alt',
          priority: TaskPriority.low,
          dueDate: LocalDate(2026, 10, 9),
          tags: ['alt'],
        ),
      );
      final outcome = await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(title: 'nachher', priority: TaskPriority.high),
        expectedRowVersion: 1,
      );
      await outcome.undo!.run(harness.ids.newId());
      final restored = await reload(id);
      expect(restored.title, 'vorher');
      expect(restored.description, 'alt');
      expect(restored.priority, TaskPriority.low);
      expect(restored.dueDate, LocalDate(2026, 10, 9));
      expect(restored.tags, ['alt']);
    });

    test('undoing an update is refused after another change', () async {
      final id = await create();
      final outcome = await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(title: 'a'),
        expectedRowVersion: 1,
      );
      await complete(id);
      await expectLater(
        outcome.undo!.run(harness.ids.newId()),
        conflict(ConflictKind.staleVersion),
      );
    });

    test('deleting an already deleted task is NotFound', () async {
      final id = await create();
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await expectLater(
        repository.delete(commandId: harness.ids.newId(), id: id),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('atomicity (AT27)', () {
    test('a failing projection stores no completion and no receipt', () async {
      final id = await create();
      projection.failure = StateError('disk full');
      await expectLater(
        repository.setCompleted(commandId: 'fail', id: id, completed: true),
        throwsA(isA<StorageFailure>()),
      );
      expect((await reload(id)).isOpen, isTrue);
      expect((await receipts()).where((r) => r.commandId == 'fail'), isEmpty);
      // The retry with the SAME id succeeds once the problem is gone.
      projection.failure = null;
      await repository.setCompleted(commandId: 'fail', id: id, completed: true);
      expect((await reload(id)).isCompleted, isTrue);
    });

    test(
      'an open task has no projection effect, so no sync can fail it',
      () async {
        projection.failure = StateError('disk full');
        final id = await create();
        expect(await repository.findById(id), isNotNull);
        expect(projection.syncs, isEmpty);
      },
    );
  });

  group('reads', () {
    test(
      'watchActive lists open and completed tasks, not deleted ones',
      () async {
        final a = await create(draft(title: 'a'));
        final b = await create(draft(title: 'b'));
        final c = await create(draft(title: 'c'));
        await complete(b);
        await repository.delete(commandId: harness.ids.newId(), id: c);
        final list = await all();
        expect(list.map((t) => t.id), [a, b]);
        expect(list.map((t) => t.isCompleted), [false, true]);
      },
    );

    test('watchById emits null after deletion', () async {
      final id = await create();
      final emissions = <Task?>[];
      final subscription = repository.watchById(id).listen(emissions.add);
      await Future<void>.delayed(Duration.zero);
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(emissions.first, isNotNull);
      expect(emissions.last, isNull);
    });

    test('watchById of an unknown id emits null (not-found screen)', () async {
      expect(await repository.watchById('missing').first, isNull);
    });

    test(
      'data is persisted as plain database rows (reopen equivalence)',
      () async {
        final id = await create(draft(tags: ['x']));
        await complete(id);
        final raw = await rawRow(id);
        expect(raw.title, 'Steuererklärung');
        expect(raw.tagsJson, ['x']);
        expect(raw.completedAtUtc, isNotNull);
        expect(raw.completionEligibility, isTrue);
      },
    );
  });
}
