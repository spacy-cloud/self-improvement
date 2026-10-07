import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/application/notification_entry_resolver.dart';

import '../support/reminder_harness.dart';

/// What a tap on a task reminder opens, against the real records and module
/// statuses (BS-111, AT29).
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late ReminderHarness h;
  late NotificationEntryResolver resolver;

  setUp(() async {
    h = await ReminderHarness.create();
    resolver = NotificationEntryResolver(
      database: h.database,
      modules: h.data.moduleStatus,
      clock: h.data.clock,
    );
  });
  tearDown(() => h.dispose());

  DateTime inHours(int hours) =>
      h.data.clock.nowUtc().add(Duration(hours: hours));

  test('an existing task opens its form (BS-111, AT29)', () async {
    final id = await h.createTask(reminderAt: inHours(2));
    expect(await resolver.resolve('/tasks/$id'), '/tasks/$id');
  });

  test('the payload of a planned task reminder resolves to its own route '
      '(BS-111, AT29)', () async {
    await h.setWanted(true);
    final id = await h.createTask(reminderAt: inHours(2));
    await h.service.reconcile();
    final row = (await h.rows()).single;
    expect(row.route, '/tasks/$id');
    expect(await resolver.resolve(row.route), '/tasks/$id');
  });

  test('a completed task still exists: its form opens (BS-111)', () async {
    final id = await h.createTask(reminderAt: inHours(2));
    await h.completeTask(id);
    expect(await resolver.resolve('/tasks/$id'), '/tasks/$id');
  });

  test('a deleted task opens the task list, a restored one its form again '
      '(BS-111, AT29)', () async {
    final id = await h.createTask(reminderAt: inHours(2));
    final deleted = await h.deleteTask(id);
    expect(await resolver.resolve('/tasks/$id'), '/habits?tab=tasks');
    await h.undo(deleted);
    expect(await resolver.resolve('/tasks/$id'), '/tasks/$id');
  });

  test(
    'a task that never existed opens the task list (BS-111, AT29)',
    () async {
      expect(
        await resolver.resolve('/tasks/${h.data.ids.newId()}'),
        '/habits?tab=tasks',
      );
    },
  );

  test('the module tasks off opens the dashboard, on again the form '
      '(BS-111, AT29)', () async {
    final id = await h.createTask(reminderAt: inHours(2));
    await h.setModule(ModuleId.tasks, enabled: false);
    expect(await resolver.resolve('/tasks/$id'), '/');
    expect(await resolver.resolve('/habits?tab=tasks'), '/');

    h.data.clock.advance(const Duration(minutes: 1));
    await h.setModule(ModuleId.tasks, enabled: true);
    expect(await resolver.resolve('/tasks/$id'), '/tasks/$id');
    expect(await resolver.resolve('/habits?tab=tasks'), '/habits?tab=tasks');
  });

  test('a habit is not found under the id of a task and the other way round '
      '(BS-111)', () async {
    final task = await h.createTask();
    final habit = await h.addHabit();
    expect(await resolver.resolve('/habits/$task'), '/habits');
    expect(await resolver.resolve('/tasks/$habit'), '/habits?tab=tasks');
    expect(await resolver.resolve('/habits/$habit'), '/habits/$habit');
  });
}
