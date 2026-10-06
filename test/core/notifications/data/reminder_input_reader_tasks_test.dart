import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/data/reminder_input_reader.dart';
import 'package:self_improvement/core/notifications/domain/reminder_inputs.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';

import '../support/reminder_harness.dart';

/// What the reader hands the planner about tasks (BS-111): open, not deleted,
/// with a reminder, and nothing else.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late ReminderHarness h;
  late ReminderInputReader reader;

  setUp(() async {
    h = await ReminderHarness.create();
    reader = ReminderInputReader(
      database: h.database,
      modules: h.data.moduleStatus,
      waterGoalReachedToday: () async => false,
    );
  });
  tearDown(() => h.dispose());

  DateTime inHours(int hours) =>
      h.data.clock.nowUtc().add(Duration(hours: hours));

  Future<List<TaskReminderInput>> tasks() async => (await reader.read(
    nowUtc: h.data.clock.nowUtc(),
    timeZoneId: 'Europe/Berlin',
    permission: NotificationPermission.granted,
  )).tasks;

  test('a fresh installation has no task reminders (BS-111)', () async {
    expect(await tasks(), isEmpty);
  });

  test('an open task with a reminder is read with its id and instant '
      '(BS-111)', () async {
    final id = await h.createTask(reminderAt: inHours(3));
    final read = await tasks();
    expect(read, hasLength(1));
    expect(read.single.id, id);
    expect(read.single.reminderAtUtc, inHours(3));
    expect(read.single.reminderAtUtc.isUtc, isTrue);
  });

  test('a task without a reminder is not read (BS-111)', () async {
    await h.createTask();
    expect(await tasks(), isEmpty);
  });

  test('a completed task is not read, a reopened one is (BS-111)', () async {
    final id = await h.createTask(reminderAt: inHours(3));
    await h.completeTask(id);
    expect(await tasks(), isEmpty);
    await h.reopenTask(id);
    expect((await tasks()).single.id, id);
  });

  test('a deleted task is not read, a restored one is (BS-111)', () async {
    final id = await h.createTask(reminderAt: inHours(3));
    final deleted = await h.deleteTask(id);
    expect(await tasks(), isEmpty);
    await h.undo(deleted);
    expect((await tasks()).single.id, id);
  });

  test('a removed reminder is not read (BS-111)', () async {
    final id = await h.createTask(reminderAt: inHours(3));
    await h.setReminder(id, null);
    expect(await tasks(), isEmpty);
  });

  test('a reminder that has passed is still read: whether it lies ahead is '
      'the planner\'s decision (BS-111)', () async {
    final id = await h.createTask(reminderAt: inHours(1));
    h.data.clock.advance(const Duration(hours: 5));
    expect((await tasks()).single.id, id);
  });

  test('the tasks come in a stable order, by id (BS-111)', () async {
    final ids = <String>[
      for (var i = 0; i < 4; i++)
        await h.createTask(reminderAt: inHours(9 - i)),
    ];
    expect((await tasks()).map((t) => t.id), ids..sort());
  });
}
