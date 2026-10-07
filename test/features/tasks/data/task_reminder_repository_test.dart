import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/tasks/data/task_repository.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/features/tasks/domain/task_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/task_test_support.dart';

/// The reminder of a task as a stored fact (BS-111): the instant with the local
/// date and the zone frozen when it was set; set, moved and removed by the
/// commands of the task, restored exactly by their undo, and never accepted in
/// the past when it is SET.
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

  // "now" is 2026-10-03 08:00Z = 10:00 in Berlin (a Saturday, summer time).
  DateTime inHours(int hours) =>
      harness.clock.nowUtc().add(Duration(hours: hours));

  TaskDraft draft({
    String title = 'Steuererklärung',
    DateTime? reminderAt,
    LocalDate? dueDate,
  }) => TaskDraft(title: title, dueDate: dueDate, reminderAtUtc: reminderAt);

  Future<String> create([TaskDraft? d, String? commandId]) async {
    final outcome = await repository.create(
      commandId: commandId ?? harness.ids.newId(),
      draft: d ?? draft(),
    );
    return outcome.entityId!;
  }

  Future<Task> reload(String id) async => (await repository.findById(id))!;

  Future<TaskRow> rawRow(String id) => (harness.database.select(
    harness.database.tasks,
  )..where((t) => t.id.equals(id))).getSingle();

  Future<CommandOutcome> edit(
    String id, {
    DateTime? reminderAt,
    String? title,
  }) async {
    final task = await reload(id);
    return repository.update(
      commandId: harness.ids.newId(),
      id: id,
      draft: TaskDraft(
        title: title ?? task.title,
        description: task.description,
        priority: task.priority,
        dueDate: task.dueDate,
        tags: task.tags,
        reminderAtUtc: reminderAt,
      ),
      expectedRowVersion: task.rowVersion,
    );
  }

  Future<ValidationFailure> failureOf(Future<Object?> call) async {
    try {
      await call;
    } on ValidationFailure catch (error) {
      return error;
    }
    fail('expected a ValidationFailure');
  }

  group('create', () {
    test(
      'freezes the instant, the local date and the zone (BS-111, T01)',
      () async {
        // 16:30Z on 2026-10-04 is 18:30 in Berlin.
        final at = DateTime.utc(2026, 10, 4, 16, 30);
        final id = await create(draft(reminderAt: at));

        final row = await rawRow(id);
        expect(row.reminderAtUtc, at);
        expect(row.reminderAtUtc!.isUtc, isTrue);
        expect(row.reminderLocalDate, LocalDate(2026, 10, 4));
        expect(row.reminderTimezoneId, 'Europe/Berlin');
        final task = await reload(id);
        expect(
          task.reminder,
          TaskReminder(
            atUtc: at,
            localDate: LocalDate(2026, 10, 4),
            timezoneId: 'Europe/Berlin',
          ),
        );
      },
    );

    test('the local date follows the zone of the moment, not the UTC day '
        '(BS-111, AT25)', () async {
      harness.clock.setTimeZone('America/New_York');
      // 02:30Z on 2026-10-04 is 22:30 on 2026-10-03 in New York (EDT).
      final id = await create(
        draft(reminderAt: DateTime.utc(2026, 10, 4, 2, 30)),
      );
      final row = await rawRow(id);
      expect(row.reminderLocalDate, LocalDate(2026, 10, 3));
      expect(row.reminderTimezoneId, 'America/New_York');
    });

    test('without a reminder all three columns are null (BS-111)', () async {
      final id = await create();
      final row = await rawRow(id);
      expect(row.reminderAtUtc, isNull);
      expect(row.reminderLocalDate, isNull);
      expect(row.reminderTimezoneId, isNull);
      expect((await reload(id)).reminder, isNull);
    });

    test('a moment that is not in the future is refused at the field, nothing '
        'is stored (BS-111)', () async {
      for (final at in [
        harness.clock.nowUtc(),
        inHours(-1),
        DateTime.utc(2020),
      ]) {
        final failure = await failureOf(
          repository.create(
            commandId: harness.ids.newId(),
            draft: draft(reminderAt: at),
          ),
        );
        expect(failure.fieldErrors.keys, [TaskFields.reminder], reason: '$at');
        expect(
          failure.fieldErrors[TaskFields.reminder],
          'Dieser Zeitpunkt ist schon vorbei. Wähle einen späteren Zeitpunkt '
          'für die Erinnerung.',
        );
      }
      expect(await repository.watchActive().first, isEmpty);
      expect(
        await harness.database.select(harness.database.commandReceipts).get(),
        isEmpty,
      );
    });

    test('the next moment is accepted (BS-111)', () async {
      final id = await create(
        draft(
          reminderAt: harness.clock.nowUtc().add(const Duration(minutes: 1)),
        ),
      );
      expect((await reload(id)).reminder, isNotNull);
    });

    test('a retry with the same command id stores one task with one reminder '
        '(BS-111, AT12)', () async {
      final commandId = harness.ids.newId();
      final d = draft(reminderAt: inHours(5));
      final first = await create(d, commandId);
      final second = await create(d, commandId);
      expect(second, first);
      expect(await repository.watchActive().first, hasLength(1));
    });

    test(
      'a reminder is no event of a day: no day is synced for it (BS-111)',
      () async {
        await create(draft(reminderAt: inHours(5)));
        expect(projection.allDays, isEmpty);
      },
    );
  });

  group('update', () {
    test('sets a reminder on a task that had none (BS-111)', () async {
      final id = await create();
      final version = (await reload(id)).rowVersion;
      await edit(id, reminderAt: inHours(4));

      final task = await reload(id);
      expect(task.reminder!.atUtc, inHours(4));
      expect(task.reminder!.localDate, LocalDate(2026, 10, 3));
      expect(task.reminder!.timezoneId, 'Europe/Berlin');
      expect(task.rowVersion, version + 1);
    });

    test('moves it: the date and zone are frozen again with the new moment '
        '(BS-111, AT25)', () async {
      final id = await create(draft(reminderAt: inHours(4)));
      harness.clock.setTimeZone('America/New_York');
      await edit(id, reminderAt: DateTime.utc(2026, 10, 6, 3, 0));

      final reminder = (await reload(id)).reminder!;
      expect(reminder.atUtc, DateTime.utc(2026, 10, 6, 3, 0));
      expect(reminder.localDate, LocalDate(2026, 10, 5));
      expect(reminder.timezoneId, 'America/New_York');
    });

    test('removes it: all three columns are null together (BS-111)', () async {
      final id = await create(draft(reminderAt: inHours(4)));
      await edit(id, reminderAt: null);

      final row = await rawRow(id);
      expect(row.reminderAtUtc, isNull);
      expect(row.reminderLocalDate, isNull);
      expect(row.reminderTimezoneId, isNull);
    });

    test('the very same instant leaves the three columns exactly as they are, '
        'also after a trip to another zone (BS-111, AT25)', () async {
      final id = await create(draft(reminderAt: inHours(30)));
      final before = (await reload(id)).reminder!;

      harness.clock.setTimeZone('Asia/Tokyo');
      await edit(id, title: 'Anderer Titel', reminderAt: before.atUtc);

      final task = await reload(id);
      expect(task.title, 'Anderer Titel');
      expect(task.reminder, before);
      expect(task.reminder!.timezoneId, 'Europe/Berlin');
    });

    test('a reminder that has gone off does not block saving another change '
        '(BS-111)', () async {
      final id = await create(draft(reminderAt: inHours(1)));
      final before = (await reload(id)).reminder!;
      harness.clock.advance(const Duration(hours: 3));

      await edit(id, title: 'Weiter bearbeitet', reminderAt: before.atUtc);

      final task = await reload(id);
      expect(task.title, 'Weiter bearbeitet');
      expect(task.reminder, before, reason: 'the stored fact stays');
    });

    test('moving to a moment in the past is refused, the task stays '
        '(BS-111)', () async {
      final id = await create(draft(reminderAt: inHours(4)));
      final before = await reload(id);
      final failure = await failureOf(edit(id, reminderAt: inHours(-2)));

      expect(failure.fieldErrors.keys, [TaskFields.reminder]);
      final after = await reload(id);
      expect(after.reminder, before.reminder);
      expect(after.rowVersion, before.rowVersion);
    });

    test('after the old reminder has passed, a new future moment is accepted '
        '(BS-111)', () async {
      final id = await create(draft(reminderAt: inHours(1)));
      harness.clock.advance(const Duration(hours: 3));
      await edit(id, reminderAt: inHours(2));
      expect((await reload(id)).reminder!.atUtc, inHours(2));
    });

    test('an invalid title is reported before the reminder is looked at '
        '(BS-111)', () async {
      final id = await create();
      final failure = await failureOf(
        edit(id, title: '', reminderAt: inHours(-1)),
      );
      expect(failure.fieldErrors.keys, [TaskFields.title]);
    });

    test('a stale form is a conflict, a stale form with a past reminder is a '
        'validation failure first (BS-111)', () async {
      final id = await create();
      final stale = await reload(id);
      await edit(id, title: 'Zwischendurch geändert');

      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(reminderAt: inHours(3)),
          expectedRowVersion: stale.rowVersion,
        ),
        throwsA(isA<ConflictFailure>()),
      );
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(reminderAt: inHours(-3)),
          expectedRowVersion: stale.rowVersion,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('a missing task is NotFound also with a reminder (BS-111)', () async {
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: 'missing',
          draft: draft(reminderAt: inHours(3)),
          expectedRowVersion: 1,
        ),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('a reminder change syncs no day (BS-111)', () async {
      final id = await create();
      projection.syncs.clear();
      await edit(id, reminderAt: inHours(3));
      expect(projection.allDays, isEmpty);
    });
  });

  group('undo', () {
    test('of a moved reminder restores the old one with its frozen date and '
        'zone (BS-111)', () async {
      final id = await create(draft(reminderAt: inHours(30)));
      final before = (await reload(id)).reminder!;
      harness.clock.setTimeZone('America/New_York');

      final outcome = await edit(id, reminderAt: inHours(60));
      expect((await reload(id)).reminder!.timezoneId, 'America/New_York');

      await outcome.undo!.run(harness.ids.newId());
      expect((await reload(id)).reminder, before);
    });

    test('of a removed reminder brings it back exactly (BS-111)', () async {
      final id = await create(draft(reminderAt: inHours(30)));
      final before = (await reload(id)).reminder!;
      final outcome = await edit(id, reminderAt: null);
      expect((await reload(id)).reminder, isNull);

      await outcome.undo!.run(harness.ids.newId());
      expect((await reload(id)).reminder, before);
    });

    test('of a reminder that was set removes it again (BS-111)', () async {
      final id = await create();
      final outcome = await edit(id, reminderAt: inHours(30));
      await outcome.undo!.run(harness.ids.newId());
      final row = await rawRow(id);
      expect(row.reminderAtUtc, isNull);
      expect(row.reminderLocalDate, isNull);
      expect(row.reminderTimezoneId, isNull);
    });

    test('is a conflict when the task changed meanwhile and changes nothing '
        '(BS-111)', () async {
      final id = await create();
      final outcome = await edit(id, reminderAt: inHours(30));
      await edit(id, reminderAt: inHours(40));

      await expectLater(
        outcome.undo!.run(harness.ids.newId()),
        throwsA(isA<ConflictFailure>()),
      );
      expect((await reload(id)).reminder!.atUtc, inHours(40));
    });

    test(
      'of the creation removes the task with its reminder (BS-111)',
      () async {
        final outcome = await repository.create(
          commandId: harness.ids.newId(),
          draft: draft(reminderAt: inHours(30)),
        );
        await outcome.undo!.run(harness.ids.newId());
        expect(await repository.watchActive().first, isEmpty);
      },
    );
  });

  group('completing and deleting keep the reminder (BS-111)', () {
    test(
      'completion, reopening, deletion and restoring do not touch it',
      () async {
        final id = await create(draft(reminderAt: inHours(30)));
        final reminder = (await reload(id)).reminder!;

        await repository.setCompleted(
          commandId: harness.ids.newId(),
          id: id,
          completed: true,
        );
        expect((await reload(id)).reminder, reminder);
        await repository.setCompleted(
          commandId: harness.ids.newId(),
          id: id,
          completed: false,
        );
        expect((await reload(id)).reminder, reminder);

        final deleted = await repository.delete(
          commandId: harness.ids.newId(),
          id: id,
        );
        await deleted.undo!.run(harness.ids.newId());
        expect((await reload(id)).reminder, reminder);
      },
    );
  });

  group('Task.hasUpcomingReminder', () {
    final now = DateTime.utc(2026, 10, 3, 8);

    Task task({DateTime? at, bool completed = false}) => Task(
      id: 't',
      title: 'Aufgabe',
      priority: TaskPriority.normal,
      createdAtUtc: now,
      updatedAtUtc: now,
      rowVersion: 1,
      completedAtUtc: completed ? now : null,
      completedLocalDate: completed ? LocalDate(2026, 10, 3) : null,
      completionTimezoneId: completed ? 'Europe/Berlin' : null,
      completionEligibility: completed ? true : null,
      reminder: at == null
          ? null
          : TaskReminder(
              atUtc: at,
              localDate: LocalDate(2026, 10, 3),
              timezoneId: 'Europe/Berlin',
            ),
    );

    test('an open task whose reminder lies ahead has one (BS-111)', () {
      expect(
        task(at: now.add(const Duration(minutes: 1))).hasUpcomingReminder(now),
        isTrue,
      );
    });

    test('no reminder, a reminder at or before now and a completed task '
        'have none (BS-111)', () {
      expect(task().hasUpcomingReminder(now), isFalse);
      expect(task(at: now).hasUpcomingReminder(now), isFalse);
      expect(
        task(at: now.subtract(const Duration(days: 1)))
            .hasUpcomingReminder(now),
        isFalse,
      );
      expect(
        task(
          at: now.add(const Duration(days: 1)),
          completed: true,
        ).hasUpcomingReminder(now),
        isFalse,
      );
    });
  });

  group('the three columns belong together (BS-111)', () {
    test('the database refuses a partial reminder', () async {
      final id = await create();
      await expectLater(
        harness.database.customStatement(
          'UPDATE tasks SET reminder_at_utc = 1 WHERE id = ?',
          [id],
        ),
        throwsA(anything),
      );
    });
  });
}
