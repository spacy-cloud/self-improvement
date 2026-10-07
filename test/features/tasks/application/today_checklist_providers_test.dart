import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/tasks/application/habit_day_providers.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/application/today_checklist_providers.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/features/tasks/domain/today_checklist.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/task_test_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  // "now" is 2026-10-03 10:00 in Berlin (a Saturday).
  final today = LocalDate(2026, 10, 3);
  final yesterday = LocalDate(2026, 10, 2);

  late DataHarness harness;
  late ProviderContainer container;

  void start({List<Override> overrides = const []}) {
    container = harness.createContainer(overrides: overrides);
    container.listen(todayChecklistProvider, (_, _) {});
    container.listen(habitTodayProvider, (_, _) {});
    container.listen(habitDayProvider, (_, _) {});
  }

  setUp(() async {
    harness = await DataHarness.create();
  });
  tearDown(() => harness.dispose());

  Future<void> settle() async {
    await pumpEventQueue();
    await container.read(tasksProvider.future);
    await container.read(habitsProvider.future);
    await container.read(habitCheckIndexProvider.future);
  }

  Future<TodayChecklist> checklist() async {
    await settle();
    return container.read(todayChecklistProvider).requireValue;
  }

  Future<String> addHabit(String title) async {
    harness.clock.advance(const Duration(seconds: 1));
    final outcome = await container
        .read(habitRepositoryProvider)
        .create(
          commandId: harness.ids.newId(),
          draft: HabitDraft(title: title),
        );
    return outcome.entityId!;
  }

  /// A habit that started on 2026-09-28, so earlier days can be checked.
  Future<String> addEarlyHabit(String title) async {
    setLocalNow(harness, LocalDate(2026, 9, 28));
    final id = await addHabit(title);
    setLocalNow(harness, today);
    return id;
  }

  Future<void> check(String id, LocalDate date, {bool checked = true}) =>
      container
          .read(habitRepositoryProvider)
          .setChecked(
            commandId: harness.ids.newId(),
            habitId: id,
            date: date,
            checked: checked,
          );

  Future<String> addTask(String title, {LocalDate? dueDate}) async {
    harness.clock.advance(const Duration(seconds: 1));
    final outcome = await container
        .read(taskRepositoryProvider)
        .create(
          commandId: harness.ids.newId(),
          draft: TaskDraft(title: title, dueDate: dueDate),
        );
    return outcome.entityId!;
  }

  Future<void> complete(String id, {bool completed = true}) => container
      .read(taskRepositoryProvider)
      .setCompleted(
        commandId: harness.ids.newId(),
        id: id,
        completed: completed,
      );

  void nextDay() {
    harness.clock.advance(const Duration(days: 1));
    container.read(todayProvider.notifier).refresh();
  }

  group('the card list (BS-110)', () {
    test('is loading until the streams have delivered, then data', () async {
      start();
      expect(container.read(todayChecklistProvider).isLoading, isTrue);

      final list = await checklist();
      expect(list.isEmpty, isTrue);
      expect(list.habitPresence, HabitPresence.none);
      expect(list.today, today);
    });

    test(
      'follows a new habit, a check and the removal of the check (T02)',
      () async {
        start();
        await settle();

        final id = await addHabit('Lesen');
        var list = await checklist();
        expect(list.habits.single.title, 'Lesen');
        expect(list.habits.single.done, isFalse);
        expect(list.progressText, '0 von 1 erledigt');

        await check(id, today);
        list = await checklist();
        expect(list.habits.single.done, isTrue);
        expect(list.progressText, '1 von 1 erledigt');
        expect(list.allDone, isTrue);

        await check(id, today, checked: false);
        list = await checklist();
        expect(list.habits.single.done, isFalse);
        expect(list.allDone, isFalse);
      },
    );

    test('follows a task: open, completed, reopened (T01)', () async {
      start();
      await settle();
      final id = await addTask('Steuer machen');
      expect((await checklist()).tasks.single.done, isFalse);

      await complete(id);
      var list = await checklist();
      expect(list.tasks.single.done, isTrue);
      expect(list.tasks.single.subtitle, 'Erledigt um 10:00');
      expect(list.progressText, '1 von 1 erledigt');

      await complete(id, completed: false);
      list = await checklist();
      expect(list.tasks.single.done, isFalse);
      expect(list.progressText, '0 von 1 erledigt');
    });

    test(
      'puts a task and a habit in one list and counts them together',
      () async {
        start();
        await settle();
        final task = await addTask('Steuer machen', dueDate: today);
        final habit = await addHabit('Lesen');
        await addHabit('Dehnen');
        await complete(task);
        await check(habit, today);

        final list = await checklist();

        expect(list.entries.map((e) => (e.kind, e.title, e.done)), [
          (ChecklistKind.task, 'Steuer machen', true),
          (ChecklistKind.habit, 'Lesen', true),
          (ChecklistKind.habit, 'Dehnen', false),
        ]);
        expect(list.progressText, '2 von 3 erledigt');
      },
    );

    test('the day change gives the new day: habits open again, done tasks gone (AT25)', () async {
      start();
      await settle();
      final task = await addTask('Heute fertig');
      final habit = await addHabit('Lesen');
      await complete(task);
      await check(habit, today);
      expect((await checklist()).doneCount, 2);

      nextDay();
      final list = await checklist();

      expect(list.today, today.addDays(1));
      expect(list.tasks, isEmpty, reason: 'completed yesterday');
      expect(list.habits.single.done, isFalse);
      expect(list.doneCount, 0);
      expect(list.totalCount, 1);
    });

    test('a failing stream is a failing card, not a half list', () async {
      start(
        overrides: [
          habitsProvider.overrideWith(
            (ref) => Stream.error(StateError('disk')),
          ),
        ],
      );
      await pumpEventQueue();

      expect(container.read(todayChecklistProvider).hasError, isTrue);
    });

    test('a completion is told in the zone it happened in, an unknown zone gives no time', () async {
      Task completedIn(String id, String zone) => Task(
        id: id,
        title: 'Aufgabe $id',
        priority: TaskPriority.normal,
        createdAtUtc: DateTime.utc(2026, 10, 1),
        updatedAtUtc: DateTime.utc(2026, 10, 3),
        rowVersion: 2,
        completedAtUtc: DateTime.utc(2026, 10, 3, 12, 15),
        completedLocalDate: today,
        completionTimezoneId: zone,
        completionEligibility: true,
      );
      start(
        overrides: [
          tasksProvider.overrideWith(
            (ref) => Stream.value([
              completedIn('ny', 'America/New_York'),
              completedIn('berlin', 'Europe/Berlin'),
              completedIn('mars', 'Mars/Olympus'),
            ]),
          ),
        ],
      );

      final list = await checklist();
      final subtitles = {for (final e in list.tasks) e.id: e.subtitle};

      // 12:15 UTC on 2026-10-03: 08:15 in New York (UTC-4), 14:15 in Berlin.
      expect(subtitles['ny'], 'Erledigt um 08:15');
      expect(subtitles['berlin'], 'Erledigt um 14:15');
      expect(subtitles['mars'], 'Erledigt');
    });
  });

  group('one model with the habits tab (BS-110, C04)', () {
    test(
      'with nothing selected the list of the tab IS the list of today',
      () async {
        start();
        await settle();
        final lesen = await addEarlyHabit('Lesen');
        await addEarlyHabit('Dehnen');
        await check(lesen, today);
        await check(lesen, yesterday);
        await settle();

        final tab = container.read(habitDayProvider).requireValue;
        final card = container.read(habitTodayProvider).requireValue;

        expect(card.date, tab.date);
        expect(
          card.items.map((i) => i.habit.id),
          tab.items.map((i) => i.habit.id),
        );
        expect(
          card.items.map((i) => i.checked),
          tab.items.map((i) => i.checked),
        );
        expect(
          card.items.map((i) => i.seriesText),
          tab.items.map((i) => i.seriesText),
        );
        expect(card.doneCount, tab.doneCount);
        expect(card.progressText, tab.progressText);
      },
    );

    test('the list of the tab follows the selected day, the list of today does not', () async {
      start();
      await settle();
      final lesen = await addEarlyHabit('Lesen');
      await check(lesen, yesterday);
      container.read(selectedHabitDayProvider.notifier).select(yesterday);
      await settle();

      final tab = container.read(habitDayProvider).requireValue;
      final card = container.read(habitTodayProvider).requireValue;

      expect(tab.date, yesterday);
      expect(tab.items.single.checked, isTrue);
      expect(card.date, today);
      expect(card.isToday, isTrue);
      expect(card.items.single.checked, isFalse);
      expect(
        (await checklist()).habits.single.done,
        isFalse,
        reason: 'the card list is built from the list of today',
      );
    });

    test(
      'a check made through the commands reaches both lists from one stream',
      () async {
        start();
        await settle();
        final lesen = await addHabit('Lesen');
        await settle();

        await check(lesen, today);
        await settle();

        expect(
          container.read(habitDayProvider).requireValue.items.single.checked,
          isTrue,
        );
        expect(
          container.read(habitTodayProvider).requireValue.items.single.checked,
          isTrue,
        );
        expect((await checklist()).habits.single.done, isTrue);
      },
    );
  });
}
