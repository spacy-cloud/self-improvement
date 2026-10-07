import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/tasks/application/task_form_controller.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_validation.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/task_test_support.dart';

/// The reminder in the task form (BS-111): choosing, changing and removing it,
/// the refusal of a moment in the past or one that does not exist, what makes
/// the form dirty, and saving it with the task.
void main() {
  setUpAll(allowMultipleDatabases);

  late DataHarness harness;
  late ProviderContainer container;
  late ScriptedTaskRepository repository;

  Future<void> start({String nowIso = '2026-10-03T08:00:00Z'}) async {
    harness = await DataHarness.create(nowIso: nowIso);
    repository = ScriptedTaskRepository(
      database: harness.database,
      runner: harness.runner,
    );
    container = harness.createContainer(
      overrides: [taskRepositoryProvider.overrideWithValue(repository)],
    );
  }

  // "now" is 2026-10-03 10:00 in Berlin.
  setUp(start);
  tearDown(() => harness.dispose());

  const create = TaskFormArgs.create();

  TaskFormController controller(TaskFormArgs args) =>
      container.read(taskFormProvider(args).notifier);

  TaskFormState formState(TaskFormArgs args) =>
      container.read(taskFormProvider(args));

  DateTime inHours(int hours) =>
      harness.clock.nowUtc().add(Duration(hours: hours));

  Future<Task> seedTask({DateTime? reminderAt}) async {
    final outcome = await repository.create(
      commandId: harness.ids.newId(),
      draft: TaskDraft(title: 'Bestehend', reminderAtUtc: reminderAt),
    );
    repository.commandIds.clear();
    return (await repository.findById(outcome.entityId!))!;
  }

  const pastHint =
      'Dieser Zeitpunkt ist schon vorbei. Wähle einen späteren Zeitpunkt für '
      'die Erinnerung.';

  group('choosing a reminder', () {
    test('a new form has none and is not dirty (BS-111)', () {
      expect(formState(create).reminderAtUtc, isNull);
      expect(formState(create).dirty, isFalse);
    });

    test('a moment ahead is set, makes the form dirty and clears an old hint '
        '(BS-111)', () {
      controller(create).setReminder(inHours(-1)); // refused: leaves a hint
      expect(formState(create).fieldErrors[TaskFields.reminder], pastHint);

      controller(create).setReminder(inHours(5));
      expect(formState(create).reminderAtUtc, inHours(5));
      expect(formState(create).dirty, isTrue);
      expect(formState(create).fieldErrors, isEmpty);
    });

    test('a moment in the past is refused with the hint and changes nothing '
        '(BS-111)', () {
      controller(create).setReminder(inHours(-3));
      expect(formState(create).reminderAtUtc, isNull);
      expect(formState(create).dirty, isFalse);
      expect(formState(create).fieldErrors[TaskFields.reminder], pastHint);

      controller(create).setReminder(inHours(5));
      controller(create).setReminder(harness.clock.nowUtc());
      expect(formState(create).reminderAtUtc, inHours(5), reason: 'kept');
      expect(formState(create).fieldErrors[TaskFields.reminder], pastHint);
    });

    test('the next minute is accepted (BS-111)', () {
      controller(create)
          .setReminder(harness.clock.nowUtc().add(const Duration(minutes: 1)));
      expect(formState(create).reminderAtUtc, isNotNull);
      expect(formState(create).fieldErrors, isEmpty);
    });

    test('clearReminder removes it and is not dirty on a form that never had '
        'one (BS-111)', () {
      controller(create).setReminder(inHours(5));
      controller(create).clearReminder();
      expect(formState(create).reminderAtUtc, isNull);
      expect(formState(create).dirty, isFalse);
    });

    test('removing a reminder clears its hint (BS-111)', () {
      controller(create).setReminder(inHours(-1));
      expect(formState(create).fieldErrors, isNotEmpty);
      controller(create).clearReminder();
      expect(formState(create).fieldErrors, isEmpty);
    });
  });

  group('a date and a time of the device zone', () {
    test('become the instant of the zone (BS-111, AT25)', () {
      controller(create)
          .setReminderLocal(LocalDate(2026, 10, 4), const LocalTime(18, 30));
      // 18:30 CEST is 16:30Z.
      expect(
        formState(create).reminderAtUtc,
        DateTime.utc(2026, 10, 4, 16, 30),
      );
    });

    test('follow another zone when the device is in one (BS-111, AT25)', () {
      harness.clock.setTimeZone('America/New_York');
      controller(create)
          .setReminderLocal(LocalDate(2026, 10, 4), const LocalTime(18, 30));
      // 18:30 EDT is 22:30Z.
      expect(
        formState(create).reminderAtUtc,
        DateTime.utc(2026, 10, 4, 22, 30),
      );
    });

    test('today at a time that has passed is refused like any past moment '
        '(BS-111)', () {
      controller(create)
          .setReminderLocal(LocalDate(2026, 10, 3), const LocalTime(9, 59));
      expect(formState(create).reminderAtUtc, isNull);
      expect(formState(create).fieldErrors[TaskFields.reminder], pastHint);
      controller(create)
          .setReminderLocal(LocalDate(2026, 10, 3), const LocalTime(10, 1));
      expect(formState(create).reminderAtUtc, DateTime.utc(2026, 10, 3, 8, 1));
    });

    test('a time that does not exist on the day the clocks go forward is '
        'refused and names the first valid time (BS-111, AT25)', () async {
      await harness.dispose();
      await start(nowIso: '2026-03-28T10:00:00Z');
      // 2026-03-29: 02:00 CET jumps to 03:00 CEST.
      controller(create)
          .setReminderLocal(LocalDate(2026, 3, 29), const LocalTime(2, 30));
      expect(formState(create).reminderAtUtc, isNull);
      expect(
        formState(create).fieldErrors[TaskFields.reminder],
        'Diese Uhrzeit gibt es wegen der Zeitumstellung nicht. Bitte wähle '
        '03:00 Uhr oder später.',
      );
      // The first minute after the gap is fine: 03:00 CEST is 01:00Z.
      controller(create)
          .setReminderLocal(LocalDate(2026, 3, 29), const LocalTime(3, 0));
      expect(formState(create).reminderAtUtc, DateTime.utc(2026, 3, 29, 1));
      expect(formState(create).fieldErrors, isEmpty);
    });

    test('a time that exists twice when the clocks go back means its first '
        'occurrence (BS-111, AT25)', () async {
      await harness.dispose();
      await start(nowIso: '2026-10-24T10:00:00Z');
      controller(create)
          .setReminderLocal(LocalDate(2026, 10, 25), const LocalTime(2, 30));
      // 02:30 CEST (the earlier offset) is 00:30Z; 02:30 CET would be 01:30Z.
      expect(
        formState(create).reminderAtUtc,
        DateTime.utc(2026, 10, 25, 0, 30),
      );
    });
  });

  group('saving a new task with a reminder', () {
    test('stores the reminder with the frozen date and zone and reports '
        'success (BS-111, T01)', () async {
      controller(create).setTitle('Steuer machen');
      controller(create)
          .setReminderLocal(LocalDate(2026, 10, 4), const LocalTime(18, 0));
      final result = await controller(create).submit();
      expect(result, isA<TaskSaved>());

      final task = (await repository.watchActive().first).single;
      expect(task.reminder!.atUtc, DateTime.utc(2026, 10, 4, 16));
      expect(task.reminder!.localDate, LocalDate(2026, 10, 4));
      expect(task.reminder!.timezoneId, 'Europe/Berlin');
    });

    test('without a reminder it saves none (BS-111)', () async {
      controller(create).setTitle('Einkaufen');
      expect(await controller(create).submit(), isA<TaskSaved>());
      expect((await repository.watchActive().first).single.reminder, isNull);
    });

    test('a reminder that passed while the form was open is refused at the '
        'field, nothing is saved (BS-111)', () async {
      controller(create).setTitle('Steuer machen');
      controller(create)
          .setReminderLocal(LocalDate(2026, 10, 3), const LocalTime(10, 30));
      expect(formState(create).reminderAtUtc, isNotNull);

      harness.clock.advance(const Duration(minutes: 31)); // 11:01
      final result = await controller(create).submit();

      expect(result, isA<TaskRejected>());
      expect(formState(create).fieldErrors[TaskFields.reminder], pastHint);
      expect(formState(create).reminderAtUtc, isNotNull, reason: 'input kept');
      expect(repository.commandIds, isEmpty, reason: 'no command was run');
      expect(await repository.watchActive().first, isEmpty);
    });

    test('an invalid title and a past reminder are both reported at once '
        '(BS-111)', () async {
      controller(create).setReminder(inHours(2));
      harness.clock.advance(const Duration(hours: 3));
      final result = await controller(create).submit();
      expect(result, isA<TaskRejected>());
      expect(
        formState(create).fieldErrors.keys,
        containsAll([TaskFields.title, TaskFields.reminder]),
      );
    });

    test('after a failed save the reminder stays and a retry with the same '
        'content reuses the command id (BS-111, AT12, AT27)', () async {
      controller(create).setTitle('Steuer machen');
      controller(create).setReminder(inHours(6));
      repository.failNext = 1;

      expect(await controller(create).submit(), isA<TaskRejected>());
      expect(formState(create).reminderAtUtc, inHours(6));
      expect(formState(create).submitFailure, isNotNull);

      expect(await controller(create).submit(), isA<TaskSaved>());
      expect(repository.commandIds, hasLength(2));
      expect(repository.commandIds.first, repository.commandIds.last);
      expect(await repository.watchActive().first, hasLength(1));
    });

    test('another reminder after a failed save is another command '
        '(BS-111, AT12)', () async {
      controller(create).setTitle('Steuer machen');
      controller(create).setReminder(inHours(6));
      repository.failNext = 1;
      await controller(create).submit();

      controller(create).setReminder(inHours(7));
      await controller(create).submit();
      expect(repository.commandIds.first, isNot(repository.commandIds.last));
    });
  });

  group('editing the reminder of a task', () {
    test('opens with the stored reminder, not dirty (BS-111)', () async {
      final task = await seedTask(reminderAt: inHours(30));
      final args = TaskFormArgs.edit(task);
      expect(formState(args).reminderAtUtc, inHours(30));
      expect(formState(args).dirty, isFalse);
    });

    test('choosing another moment makes it dirty, choosing the same one '
        'again does not (BS-111)', () async {
      final task = await seedTask(reminderAt: inHours(30));
      final args = TaskFormArgs.edit(task);

      controller(args).setReminder(inHours(40));
      expect(formState(args).dirty, isTrue);
      controller(args).setReminder(inHours(30));
      expect(formState(args).dirty, isFalse);
    });

    test('removing it saves a task without a reminder (BS-111)', () async {
      final task = await seedTask(reminderAt: inHours(30));
      final args = TaskFormArgs.edit(task);
      controller(args).clearReminder();
      expect(formState(args).dirty, isTrue);

      expect(await controller(args).submit(), isA<TaskSaved>());
      expect((await repository.findById(task.id))!.reminder, isNull);
    });

    test('changing it moves the stored reminder (BS-111)', () async {
      final task = await seedTask(reminderAt: inHours(30));
      final args = TaskFormArgs.edit(task);
      controller(args).setReminder(inHours(50));
      expect(await controller(args).submit(), isA<TaskSaved>());
      expect(
        (await repository.findById(task.id))!.reminder!.atUtc,
        inHours(50),
      );
    });

    test('setting one on a task that had none saves it (BS-111)', () async {
      final task = await seedTask();
      final args = TaskFormArgs.edit(task);
      controller(args).setReminder(inHours(4));
      expect(await controller(args).submit(), isA<TaskSaved>());
      expect((await repository.findById(task.id))!.reminder, isNotNull);
    });

    test(
      'a reminder that has gone off stays and does not block another '
      'change; picking the same past moment is not refused (BS-111)',
      () async {
        final task = await seedTask(reminderAt: inHours(1));
        final args = TaskFormArgs.edit(task);
        harness.clock.advance(const Duration(hours: 4));

        controller(args).setTitle('Neuer Titel');
        controller(args).setReminder(task.reminder!.atUtc);
        expect(formState(args).fieldErrors, isEmpty);

        expect(await controller(args).submit(), isA<TaskSaved>());
        final saved = (await repository.findById(task.id))!;
        expect(saved.title, 'Neuer Titel');
        expect(saved.reminder, task.reminder);
      },
    );

    test('moving an expired reminder to another past moment is refused '
        '(BS-111)', () async {
      final task = await seedTask(reminderAt: inHours(1));
      final args = TaskFormArgs.edit(task);
      harness.clock.advance(const Duration(hours: 4));
      controller(args).setReminder(inHours(-2));
      expect(formState(args).fieldErrors[TaskFields.reminder], pastHint);
      expect(formState(args).reminderAtUtc, task.reminder!.atUtc);
    });

    test('the task changed meanwhile is a conflict, the input including the '
        'reminder is kept (BS-111, AT27)', () async {
      final task = await seedTask(reminderAt: inHours(30));
      final args = TaskFormArgs.edit(task);
      controller(args).setReminder(inHours(50));
      await repository.update(
        commandId: harness.ids.newId(),
        id: task.id,
        draft: TaskDraft(title: 'Woanders geändert'),
        expectedRowVersion: task.rowVersion,
      );

      expect(await controller(args).submit(), isA<TaskRejected>());
      expect(formState(args).submitFailure, isNotNull);
      expect(formState(args).reminderAtUtc, inHours(50));
    });
  });
}
