import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/tasks/application/task_form_controller.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/features/tasks/domain/task_tags.dart';
import 'package:self_improvement/features/tasks/domain/task_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/task_test_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  late DataHarness harness;
  late ProviderContainer container;
  late ScriptedTaskRepository repository;

  setUp(() async {
    harness = await DataHarness.create();
    repository = ScriptedTaskRepository(
      database: harness.database,
      runner: harness.runner,
    );
    container = harness.createContainer(
      overrides: [taskRepositoryProvider.overrideWithValue(repository)],
    );
  });
  tearDown(() => harness.dispose());

  const create = TaskFormArgs.create();

  TaskFormController controller(TaskFormArgs args) =>
      container.read(taskFormProvider(args).notifier);

  TaskFormState formState(TaskFormArgs args) =>
      container.read(taskFormProvider(args));

  Future<List<Task>> stored() => repository.watchActive().first;

  Future<Task> seedTask({String title = 'Bestehend'}) async {
    final outcome = await repository.create(
      commandId: harness.ids.newId(),
      draft: TaskDraft(
        title: title,
        description: 'Text',
        priority: TaskPriority.high,
        dueDate: LocalDate(2026, 10, 9),
        tags: const ['a', 'b'],
      ),
    );
    repository.commandIds.clear();
    return (await repository.findById(outcome.entityId!))!;
  }

  group('new task', () {
    test('starts empty: normal priority, no date, no tags, not dirty', () {
      final s = formState(create);
      expect(s.title, isEmpty);
      expect(s.description, isEmpty);
      expect(s.priority, TaskPriority.normal);
      expect(s.dueDate, isNull);
      expect(s.tags, isEmpty);
      expect(s.dirty, isFalse);
      expect(s.submitting, isFalse);
      expect(s.fieldErrors, isEmpty);
      expect(s.submitFailure, isNull);
      expect(controller(create).isEdit, isFalse);
    });

    test(
      'an empty title is rejected with a hint and nothing is saved',
      () async {
        final result = await controller(create).submit();
        expect(result, isA<TaskRejected>());
        expect(
          formState(create).fieldErrors[TaskFields.title],
          'Bitte gib einen Titel ein.',
        );
        expect(await stored(), isEmpty);
        expect(repository.commandIds, isEmpty, reason: 'repository not called');
      },
    );

    test('title 120 is saved, title 121 is rejected', () async {
      controller(create).setTitle('a' * 121);
      expect(await controller(create).submit(), isA<TaskRejected>());
      expect(
        formState(create).fieldErrors[TaskFields.title],
        'Der Titel darf höchstens 120 Zeichen lang sein.',
      );
      expect(await stored(), isEmpty);

      controller(create).setTitle('a' * 120);
      expect(await controller(create).submit(), isA<TaskSaved>());
      expect((await stored()).single.title, 'a' * 120);
    });

    test('description 1000 is saved, 1001 is rejected', () async {
      controller(create).setTitle('x');
      controller(create).setDescription('d' * 1001);
      expect(await controller(create).submit(), isA<TaskRejected>());
      expect(
        formState(create).fieldErrors[TaskFields.description],
        'Die Beschreibung darf höchstens 1.000 Zeichen lang sein.',
      );
      controller(create).setDescription('d' * 1000);
      expect(await controller(create).submit(), isA<TaskSaved>());
    });

    test(
      'saves all fields and reports the success message with an undo',
      () async {
        controller(create).setTitle('  Steuer machen ');
        controller(create).setDescription('Belege');
        controller(create).setPriority(TaskPriority.high);
        controller(create).setDueDate(LocalDate(2026, 10, 15));
        controller(create).addTag('Finanzen');
        final result = await controller(create).submit();
        expect(result, isA<TaskSaved>());
        final saved = result as TaskSaved;
        expect(saved.message, 'Aufgabe gespeichert');
        expect(saved.wasEdit, isFalse);
        expect(saved.outcome.undo, isNotNull);
        final task = (await stored()).single;
        expect(saved.taskId, task.id);
        expect(task.title, 'Steuer machen');
        expect(task.description, 'Belege');
        expect(task.priority, TaskPriority.high);
        expect(task.dueDate, LocalDate(2026, 10, 15));
        expect(task.tags, ['Finanzen']);
      },
    );

    test('editing a field clears only its own error', () async {
      controller(create).setDescription('d' * 1001);
      await controller(create).submit();
      expect(
        formState(create).fieldErrors.keys,
        containsAll([TaskFields.title, TaskFields.description]),
      );
      controller(create).setTitle('ok');
      expect(
        formState(create).fieldErrors.containsKey(TaskFields.title),
        isFalse,
      );
      expect(
        formState(create).fieldErrors.containsKey(TaskFields.description),
        isTrue,
        reason: 'the description hint stays until the description changes',
      );
      controller(create).setDescription('kurz');
      expect(formState(create).fieldErrors, isEmpty);
    });

    test(
      'after a success a further save is a new task (new command id)',
      () async {
        controller(create).setTitle('Eins');
        await controller(create).submit();
        controller(create).setTitle('Eins');
        await controller(create).submit();
        expect(await stored(), hasLength(2));
        expect(repository.commandIds.toSet(), hasLength(2));
      },
    );
  });

  group('dirty flag (discard dialog)', () {
    test('is set by every kind of change', () {
      final changes = <void Function()>[
        () => controller(create).setTitle('x'),
        () => controller(create).setDescription('x'),
        () => controller(create).setPriority(TaskPriority.low),
        () => controller(create).setDueDate(LocalDate(2026, 10, 9)),
        () => controller(create).addTag('x'),
      ];
      for (final change in changes) {
        container.invalidate(taskFormProvider(create));
        expect(formState(create).dirty, isFalse);
        change();
        expect(formState(create).dirty, isTrue);
      }
    });

    test('typing and removing the same text is not dirty', () {
      controller(create).setTitle('abc');
      expect(formState(create).dirty, isTrue);
      controller(create).setTitle('');
      expect(formState(create).dirty, isFalse);
      controller(create).addTag('x');
      controller(create).removeTag('x');
      expect(formState(create).dirty, isFalse);
    });

    test('whitespace only is not a change', () {
      controller(create).setTitle('   ');
      controller(create).setDescription('\n ');
      expect(formState(create).dirty, isFalse);
    });

    test('a saved form is not dirty any more', () async {
      controller(create).setTitle('x');
      expect(formState(create).dirty, isTrue);
      await controller(create).submit();
      expect(formState(create).dirty, isFalse);
    });

    test('an edit form compares with the opened task', () async {
      final task = await seedTask();
      final args = TaskFormArgs.edit(task);
      expect(formState(args).dirty, isFalse);
      controller(args).setTitle('${task.title}!');
      expect(formState(args).dirty, isTrue);
      controller(args).setTitle(task.title);
      expect(formState(args).dirty, isFalse);
      controller(args).setDueDate(null);
      expect(formState(args).dirty, isTrue);
    });
  });

  group('tags', () {
    test(
      'addTag returns the result and stores the German hint on rejection',
      () {
        expect(controller(create).addTag(' Büro '), TagAddResult.added);
        expect(formState(create).tags, ['Büro']);
        expect(formState(create).fieldErrors, isEmpty);

        expect(controller(create).addTag('büro'), TagAddResult.duplicate);
        expect(
          formState(create).fieldErrors[TaskFields.tags],
          'Dieses Tag gibt es schon.',
        );
        expect(formState(create).tags, ['Büro'], reason: 'first spelling kept');

        expect(controller(create).addTag('  '), TagAddResult.empty);
        expect(
          formState(create).fieldErrors[TaskFields.tags],
          'Bitte gib ein Tag ein.',
        );
        expect(controller(create).addTag('t' * 21), TagAddResult.tooLong);
        expect(
          formState(create).fieldErrors[TaskFields.tags],
          'Ein Tag darf höchstens 20 Zeichen lang sein.',
        );
      },
    );

    test('a successful add clears the tag hint', () {
      controller(create).addTag('');
      expect(formState(create).fieldErrors, isNotEmpty);
      controller(create).addTag('ok');
      expect(formState(create).fieldErrors, isEmpty);
    });

    test(
      'at most five tags: the sixth is refused, a removal frees a place',
      () {
        for (final tag in ['a', 'b', 'c', 'd', 'e']) {
          expect(controller(create).addTag(tag), TagAddResult.added);
        }
        expect(formState(create).canAddTag, isFalse);
        expect(controller(create).addTag('f'), TagAddResult.limitReached);
        expect(
          formState(create).fieldErrors[TaskFields.tags],
          'Du kannst höchstens 5 Tags vergeben.',
        );
        expect(formState(create).tags, hasLength(5));

        controller(create).removeTag('C');
        expect(formState(create).tags, ['a', 'b', 'd', 'e']);
        expect(formState(create).canAddTag, isTrue);
        expect(controller(create).addTag('f'), TagAddResult.added);
        expect(formState(create).fieldErrors, isEmpty);
      },
    );

    test(
      'five tags are saved, a tag of exactly 20 characters is fine',
      () async {
        controller(create).setTitle('x');
        controller(create).addTag('t' * 20);
        for (final tag in ['b', 'c', 'd', 'e']) {
          controller(create).addTag(tag);
        }
        expect(await controller(create).submit(), isA<TaskSaved>());
        expect((await stored()).single.tags, hasLength(5));
      },
    );
  });

  group('edit', () {
    test('is prefilled from the task and saves a changed task', () async {
      final task = await seedTask(title: 'Alt');
      final args = TaskFormArgs.edit(task);
      final s = formState(args);
      expect(s.title, 'Alt');
      expect(s.description, 'Text');
      expect(s.priority, TaskPriority.high);
      expect(s.dueDate, LocalDate(2026, 10, 9));
      expect(s.tags, ['a', 'b']);
      expect(controller(args).isEdit, isTrue);

      controller(args).setTitle('Neu');
      final result = await controller(args).submit();
      expect(result, isA<TaskSaved>());
      final saved = result as TaskSaved;
      expect(saved.message, 'Aufgabe aktualisiert');
      expect(saved.wasEdit, isTrue);
      expect(saved.taskId, task.id);
      final after = (await repository.findById(task.id))!;
      expect(after.title, 'Neu');
      expect(after.rowVersion, task.rowVersion + 1);
    });

    test('editing never touches the completion', () async {
      final seeded = await seedTask();
      await repository.setCompleted(
        commandId: harness.ids.newId(),
        id: seeded.id,
        completed: true,
      );
      final task = (await repository.findById(seeded.id))!;
      final args = TaskFormArgs.edit(task);
      controller(args).setTitle('Umbenannt');
      expect(await controller(args).submit(), isA<TaskSaved>());
      final after = (await repository.findById(task.id))!;
      expect(after.isCompleted, isTrue);
      expect(after.completedAtUtc, task.completedAtUtc);
      expect(after.completionEligibility, task.completionEligibility);
    });

    test('a stale version is a conflict: nothing saved, input kept', () async {
      final task = await seedTask();
      final args = TaskFormArgs.edit(task);
      await repository.update(
        commandId: harness.ids.newId(),
        id: task.id,
        draft: const TaskDraft(title: 'Zwischendurch'),
        expectedRowVersion: task.rowVersion,
      );
      controller(args).setTitle('Meine Änderung');
      expect(await controller(args).submit(), isA<TaskRejected>());
      final s = formState(args);
      expect(s.submitFailure, isA<ConflictFailure>());
      expect(
        s.submitFailure!.userMessage,
        'Der Eintrag wurde inzwischen geändert.',
      );
      expect(s.title, 'Meine Änderung');
      expect(s.submitting, isFalse);
      expect((await repository.findById(task.id))!.title, 'Zwischendurch');
    });

    test('a task deleted meanwhile is reported, the input stays', () async {
      final task = await seedTask();
      final args = TaskFormArgs.edit(task);
      await repository.delete(commandId: harness.ids.newId(), id: task.id);
      controller(args).setTitle('Neu');
      expect(await controller(args).submit(), isA<TaskRejected>());
      expect(formState(args).submitFailure, isA<NotFoundFailure>());
      expect(formState(args).title, 'Neu');
    });

    test('form args are equal for the same task version only', () async {
      final task = await seedTask();
      expect(TaskFormArgs.edit(task), TaskFormArgs.edit(task));
      expect(const TaskFormArgs.create(), const TaskFormArgs.create());
      await repository.update(
        commandId: harness.ids.newId(),
        id: task.id,
        draft: const TaskDraft(title: 'x'),
        expectedRowVersion: task.rowVersion,
      );
      final newer = (await repository.findById(task.id))!;
      expect(TaskFormArgs.edit(newer), isNot(TaskFormArgs.edit(task)));
      expect(TaskFormArgs.edit(task), isNot(const TaskFormArgs.create()));
    });
  });

  group('submit safety (AT12, AT27)', () {
    test('a double tap saves exactly one task', () async {
      controller(create).setTitle('Einmal');
      final first = controller(create).submit();
      final second = controller(create).submit();
      final results = await Future.wait([first, second]);
      expect(results.whereType<TaskSaved>(), hasLength(1));
      expect(results.whereType<TaskRejected>(), hasLength(1));
      expect(await stored(), hasLength(1));
      expect(repository.commandIds, hasLength(1));
    });

    test('submitting is visible while the save runs', () async {
      // A listener keeps the auto-disposed form alive across event loop turns
      // (a mounted screen does this in the app).
      container.listen(taskFormProvider(create), (_, _) {});
      controller(create).setTitle('x');
      repository.gate = Completer<void>();
      final pending = controller(create).submit();
      await Future<void>.delayed(Duration.zero);
      expect(formState(create).submitting, isTrue);
      repository.gate!.complete();
      await pending;
      expect(formState(create).submitting, isFalse);
    });

    test(
      'a storage failure keeps the input, the retry reuses the command id',
      () async {
        controller(create).setTitle('Bleibt');
        controller(create).setDescription('Auch');
        controller(create).addTag('tag');
        repository.failNext = 1;
        final failed = await controller(create).submit();
        expect(failed, isA<TaskRejected>());
        final s = formState(create);
        expect(s.submitFailure, isA<StorageFailure>());
        expect(s.submitting, isFalse);
        expect(s.title, 'Bleibt');
        expect(s.description, 'Auch');
        expect(s.tags, ['tag']);
        expect(await stored(), isEmpty);

        final saved = await controller(create).submit();
        expect(saved, isA<TaskSaved>());
        expect(formState(create).submitFailure, isNull);
        expect(await stored(), hasLength(1));
        expect(repository.commandIds, hasLength(2));
        expect(
          repository.commandIds.first,
          repository.commandIds.last,
          reason: 'the retry reuses the id of the failed attempt',
        );
      },
    );

    test('changed content after a failure gets a NEW command id', () async {
      controller(create).setTitle('Erst');
      repository.failNext = 1;
      await controller(create).submit();
      controller(create).setTitle('Dann anders');
      await controller(create).submit();
      expect(repository.commandIds, hasLength(2));
      expect(repository.commandIds.first, isNot(repository.commandIds.last));
      expect((await stored()).single.title, 'Dann anders');
    });

    test(
      'a real database failure rolls back; the retry succeeds (AT27)',
      () async {
        controller(create).setTitle('Echt');
        await failInsertsInto(harness, 'tasks');
        expect(await controller(create).submit(), isA<TaskRejected>());
        expect(formState(create).submitFailure, isA<StorageFailure>());
        expect(
          formState(create).submitFailure!.userMessage,
          contains('Deine Eingaben bleiben erhalten'),
        );
        expect(await stored(), isEmpty);
        expect(
          await harness.database.select(harness.database.commandReceipts).get(),
          isEmpty,
        );
        await restoreInserts(harness, 'tasks');
        expect(await controller(create).submit(), isA<TaskSaved>());
        expect(await stored(), hasLength(1));
      },
    );
  });
}
