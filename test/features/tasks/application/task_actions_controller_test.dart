import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/tasks/application/task_actions_controller.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/task_test_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  late DataHarness harness;
  late ProviderContainer container;
  late ScriptedTaskRepository repository;

  setUp(() async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    repository = ScriptedTaskRepository(
      database: harness.database,
      runner: harness.runner,
    );
    container = harness.createContainer(
      overrides: [taskRepositoryProvider.overrideWithValue(repository)],
    );
    container.listen(taskActionsProvider, (_, _) {});
  });
  tearDown(() => harness.dispose());

  TaskActionsController actions() =>
      container.read(taskActionsProvider.notifier);

  TaskActionsState actionsState() => container.read(taskActionsProvider);

  Future<String> add([String title = 'Aufgabe']) async {
    final outcome = await repository.create(
      commandId: harness.ids.newId(),
      draft: TaskDraft(title: title),
    );
    repository.commandIds.clear();
    return outcome.entityId!;
  }

  Future<Task> reload(String id) async => (await repository.findById(id))!;

  group('completion (AT13, AT12)', () {
    test(
      'completing reports the German message and an undo, XP is awarded once',
      () async {
        final id = await add();
        final result = await actions().setCompleted(id, completed: true);
        expect(result, isA<TaskActionSucceeded>());
        final ok = result as TaskActionSucceeded;
        expect(ok.message, 'Aufgabe erledigt');
        expect(ok.undo, isNotNull);
        expect((await reload(id)).isCompleted, isTrue);
        expect(await harness.totalXp(), 10);
      },
    );

    test('reopening reports its message and takes the XP back', () async {
      final id = await add();
      await actions().setCompleted(id, completed: true);
      final result = await actions().setCompleted(id, completed: false);
      expect(
        (result as TaskActionSucceeded).message,
        'Aufgabe wieder geöffnet',
      );
      expect(result.undo, isNotNull);
      expect((await reload(id)).isOpen, isTrue);
      expect(await harness.totalXp(), 0);
    });

    test('completing a completed task is a success without undo and without a change', () async {
      final id = await add();
      await actions().setCompleted(id, completed: true);
      final before = await reload(id);
      harness.clock.advance(const Duration(hours: 1));
      final result = await actions().setCompleted(id, completed: true);
      expect(result, isA<TaskActionSucceeded>());
      expect((result as TaskActionSucceeded).undo, isNull);
      expect((await reload(id)).completedAtUtc, before.completedAtUtc);
      expect(await harness.totalXp(), 10);
    });

    test(
      'complete, reopen, complete again: one award at a time (AT13)',
      () async {
        final id = await add();
        for (var i = 0; i < 3; i++) {
          await actions().setCompleted(id, completed: true);
          expect(await harness.totalXp(), 10);
          await actions().setCompleted(id, completed: false);
          expect(await harness.totalXp(), 0);
        }
      },
    );

    test(
      'a double tap runs one command, the second tap is ignored (AT12)',
      () async {
        final id = await add();
        final first = actions().setCompleted(id, completed: true);
        final second = actions().setCompleted(id, completed: true);
        final results = await Future.wait([first, second]);
        expect(results[0], isA<TaskActionSucceeded>());
        expect(results[1], isA<TaskActionBusy>());
        expect(repository.commandIds, hasLength(1));
        expect(await harness.totalXp(), 10);
      },
    );

    test(
      'a tap in the opposite direction while running is ignored, not a toggle',
      () async {
        final id = await add();
        final first = actions().setCompleted(id, completed: true);
        final opposite = actions().setCompleted(id, completed: false);
        final results = await Future.wait([first, opposite]);
        expect(results[1], isA<TaskActionBusy>());
        expect((await reload(id)).isCompleted, isTrue);
      },
    );

    test('different tasks do not block each other', () async {
      final a = await add('A');
      final b = await add('B');
      final results = await Future.wait([
        actions().setCompleted(a, completed: true),
        actions().setCompleted(b, completed: true),
      ]);
      expect(results.whereType<TaskActionSucceeded>(), hasLength(2));
      expect(await harness.totalXp(), 20);
    });

    test(
      'busy is visible while the command runs and cleared afterwards',
      () async {
        final id = await add();
        repository.gate = Completer<void>();
        final pending = actions().setCompleted(id, completed: true);
        await pumpEventQueue();
        expect(actionsState().isBusy(id), isTrue);
        expect(actionsState().isBusy('other'), isFalse);
        repository.gate!.complete();
        await pending;
        expect(actionsState().isBusy(id), isFalse);
      },
    );

    test(
      'a failure reports the German text; the retry reuses the command id',
      () async {
        final id = await add();
        repository.failNext = 1;
        final failed = await actions().setCompleted(id, completed: true);
        expect(failed, isA<TaskActionFailed>());
        expect(
          (failed as TaskActionFailed).message,
          contains('Deine Eingaben bleiben erhalten'),
        );
        expect(failed.failure, isA<StorageFailure>());
        expect((await reload(id)).isOpen, isTrue);
        expect(actionsState().isBusy(id), isFalse);

        final retry = await actions().setCompleted(id, completed: true);
        expect(retry, isA<TaskActionSucceeded>());
        expect(repository.commandIds, hasLength(2));
        expect(repository.commandIds.first, repository.commandIds.last);
        expect(await harness.totalXp(), 10);
      },
    );

    test('a new action after a success uses a new command id', () async {
      final id = await add();
      await actions().setCompleted(id, completed: true);
      await actions().setCompleted(id, completed: false);
      expect(repository.commandIds.toSet(), hasLength(2));
    });

    test(
      'a different desired state after a failure gets a new command id',
      () async {
        final id = await add();
        repository.failNext = 1;
        await actions().setCompleted(id, completed: true);
        await actions().setCompleted(id, completed: false);
        expect(repository.commandIds.first, isNot(repository.commandIds.last));
      },
    );

    test(
      'a real database failure rolls back completion and XP (AT27)',
      () async {
        final id = await add();
        await failInsertsInto(harness, 'command_receipts');
        final failed = await actions().setCompleted(id, completed: true);
        expect(failed, isA<TaskActionFailed>());
        expect((await reload(id)).isOpen, isTrue);
        expect(await harness.totalXp(), 0);
        await restoreInserts(harness, 'command_receipts');
        final retry = await actions().setCompleted(id, completed: true);
        expect(retry, isA<TaskActionSucceeded>());
        expect(await harness.totalXp(), 10);
      },
    );

    test('a missing task is a failure with the not-found text', () async {
      final result = await actions().setCompleted('missing', completed: true);
      expect(result, isA<TaskActionFailed>());
      expect(
        (result as TaskActionFailed).message,
        'Dieser Eintrag ist nicht mehr vorhanden.',
      );
    });
  });

  group('delete and undo', () {
    test(
      'delete reports its message; undo restores the task and the XP',
      () async {
        final id = await add();
        await actions().setCompleted(id, completed: true);
        final deleted = await actions().delete(id);
        expect((deleted as TaskActionSucceeded).message, 'Aufgabe gelöscht');
        expect(await repository.findById(id), isNull);
        expect(await harness.totalXp(), 0);

        final undone = await actions().undo(deleted.undo!);
        expect((undone as TaskActionSucceeded).message, 'Rückgängig gemacht');
        expect((await reload(id)).isCompleted, isTrue);
        expect(await harness.totalXp(), 10);
      },
    );

    test('undo of a completion reopens the task', () async {
      final id = await add();
      final done = await actions().setCompleted(id, completed: true);
      await actions().undo((done as TaskActionSucceeded).undo!);
      expect((await reload(id)).isOpen, isTrue);
      expect(await harness.totalXp(), 0);
    });

    test(
      'an undo after a later change is a conflict, nothing is overwritten',
      () async {
        final id = await add();
        final done = await actions().setCompleted(id, completed: true);
        await repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: const TaskDraft(title: 'Zwischendurch'),
          expectedRowVersion: 2,
        );
        final result = await actions().undo(
          (done as TaskActionSucceeded).undo!,
        );
        expect(result, isA<TaskActionFailed>());
        expect(
          (result as TaskActionFailed).message,
          'Der Eintrag wurde inzwischen geändert.',
        );
        expect(
          (result.failure as ConflictFailure).kind,
          ConflictKind.staleVersion,
        );
        expect((await reload(id)).isCompleted, isTrue);
      },
    );

    test('a second tap on "Rückgängig" while it runs is ignored', () async {
      final id = await add();
      final done = await actions().setCompleted(id, completed: true);
      final undo = (done as TaskActionSucceeded).undo!;
      final first = actions().undo(undo);
      final second = actions().undo(undo);
      final results = await Future.wait([first, second]);
      expect(results[0], isA<TaskActionSucceeded>());
      expect(results[1], isA<TaskActionBusy>());
      expect(actionsState().undoRunning, isFalse);
    });

    test('deleting an unknown task fails with the not-found text', () async {
      final result = await actions().delete('missing');
      expect(result, isA<TaskActionFailed>());
      expect(
        (result as TaskActionFailed).message,
        'Dieser Eintrag ist nicht mehr vorhanden.',
      );
    });
  });
}
