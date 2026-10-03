import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/data/habit_repository.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_overview.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/task_test_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  late DataHarness harness;
  late ProviderContainer container;
  late HabitRepository repository;

  // "now" is 2026-10-03 10:00 in Berlin (a Saturday).
  final today = LocalDate(2026, 10, 3);

  setUp(() async {
    harness = await DataHarness.create();
    container = harness.createContainer();
    repository = container.read(habitRepositoryProvider);
    container.listen(habitsOverviewProvider, (_, _) {});
  });
  tearDown(() => harness.dispose());

  Future<void> settle() async {
    await pumpEventQueue();
    await container.read(habitsProvider.future);
    await container.read(habitCheckIndexProvider.future);
  }

  Future<HabitsOverview> overview() async {
    await settle();
    return container.read(habitsOverviewProvider).requireValue;
  }

  Future<String> add([String title = 'Lesen']) async {
    harness.clock.advance(const Duration(seconds: 1));
    final outcome = await repository.create(
      commandId: harness.ids.newId(),
      draft: HabitDraft(title: title),
    );
    return outcome.entityId!;
  }

  Future<void> check(String id, LocalDate date, {bool checked = true}) async {
    await repository.setChecked(
      commandId: harness.ids.newId(),
      habitId: id,
      date: date,
      checked: checked,
    );
  }

  void nextDay() {
    harness.clock.advance(const Duration(days: 1));
    container.read(todayProvider.notifier).refresh();
  }

  group('today overview (T02)', () {
    test('without habits the list is empty', () async {
      final result = await overview();
      expect(result.isEmpty, isTrue);
      expect(result.archived, isEmpty);
      expect(result.progressText, '0 von 0 erledigt');
      expect(result.today, today);
    });

    test(
      'a new habit shows up open and updates reactively when checked',
      () async {
        final id = await add('Lesen');
        var result = await overview();
        expect(result.items.single.habit.title, 'Lesen');
        expect(result.items.single.checkedToday, isFalse);
        expect(result.items.single.statusText, 'Offen');
        expect(result.progressText, '0 von 1 erledigt');

        await check(id, today);
        result = await overview();
        expect(result.items.single.checkedToday, isTrue);
        expect(result.items.single.statusText, 'Erledigt');
        expect(
          result.items.single.series,
          const HabitSeries(current: 1, longest: 1),
        );
        expect(result.progressText, '1 von 1 erledigt');

        await check(id, today, checked: false);
        result = await overview();
        expect(result.items.single.checkedToday, isFalse);
        expect(result.items.single.series.current, 0);
      },
    );

    test('lists several habits oldest first with their own state', () async {
      final a = await add('A');
      await add('B');
      await add('C');
      await check(a, today);
      final result = await overview();
      expect(result.items.map((i) => i.habit.title), ['A', 'B', 'C']);
      expect(result.items.map((i) => i.checkedToday), [true, false, false]);
      expect(result.doneCount, 1);
    });

    test('icon and reminder of the habit are part of the item', () async {
      await repository.create(
        commandId: harness.ids.newId(),
        draft: const HabitDraft(title: 'Mond', iconKey: 'moon'),
      );
      final item = (await overview()).items.single;
      expect(item.habit.icon.key, 'moon');
      expect(item.habit.reminderTime, isNull);
    });

    test(
      'a new day recomputes: today is open again, the series survives',
      () async {
        final id = await add();
        await check(id, today);
        expect((await overview()).items.single.checkedToday, isTrue);

        nextDay();
        var result = await overview();
        expect(result.today, LocalDate(2026, 10, 4));
        expect(
          result.items.single.checkedToday,
          isFalse,
          reason: 'a new open day',
        );
        expect(
          result.items.single.series.current,
          1,
          reason: 'runs until the day ends',
        );

        nextDay();
        result = await overview();
        expect(
          result.items.single.series.current,
          0,
          reason: 'a missed day broke it',
        );
        expect(result.items.single.series.longest, 1);
      },
    );

    test('archived from tomorrow: hint today, moved to the archive list the next day', () async {
      final id = await add();
      await repository.archive(commandId: harness.ids.newId(), id: id);
      var result = await overview();
      expect(result.items.single.archivePending, isTrue);
      expect(result.items.single.archiveHint, 'Ab morgen archiviert');
      expect(result.archived, isEmpty);

      nextDay();
      result = await overview();
      expect(result.items, isEmpty);
      expect(result.archived.single.habit.id, id);
    });

    test(
      'a deleted habit leaves the list and its checks stop counting',
      () async {
        final a = await add('A');
        final b = await add('B');
        await check(a, today);
        await check(b, today);
        expect((await overview()).doneCount, 2);
        await repository.delete(commandId: harness.ids.newId(), id: a);
        final result = await overview();
        expect(result.items.single.habit.id, b);
        expect(result.doneCount, 1);
      },
    );
  });

  group('habit by id', () {
    test('emits the habit and updates after an edit', () async {
      final id = await add('Alt');
      final values = <Habit?>[];
      container.listen(
        habitProvider(id),
        (_, next) => values.add(next.value),
        fireImmediately: true,
      );
      await pumpEventQueue();
      expect(values.last?.title, 'Alt');
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: const HabitDraft(title: 'Neu', iconKey: 'heart'),
        expectedRowVersion: 1,
      );
      await pumpEventQueue();
      expect(values.last?.title, 'Neu');
      expect(values.last?.icon.key, 'heart');
    });

    test('an unknown id emits null (not-found screen)', () async {
      container.listen(habitProvider('missing'), (_, _) {});
      expect(await container.read(habitProvider('missing').future), isNull);
    });

    test('a deleted habit becomes null', () async {
      final id = await add();
      container.listen(habitProvider(id), (_, _) {});
      expect(await container.read(habitProvider(id).future), isNotNull);
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await pumpEventQueue();
      expect(container.read(habitProvider(id)).value, isNull);
    });

    test('an archived habit is still readable by id', () async {
      final id = await add();
      await repository.archive(commandId: harness.ids.newId(), id: id);
      container.listen(habitProvider(id), (_, _) {});
      final habit = await container.read(habitProvider(id).future);
      expect(habit!.archivedFrom, LocalDate(2026, 10, 4));
    });
  });

  group('habit detail with the 30 day history', () {
    Future<HabitDetail?> detail(String id) async {
      container.listen(habitDetailProvider(id), (_, _) {});
      await settle();
      await container.read(habitProvider(id).future);
      await pumpEventQueue();
      return container.read(habitDetailProvider(id)).requireValue;
    }

    test('shows 30 days with accessible texts and the series', () async {
      final id = await add();
      await check(id, today);
      final result = (await detail(id))!;
      expect(result.history, hasLength(30));
      expect(result.history.last.date, today);
      expect(result.history.last.semanticsLabel, 'Sa., 03.10.: erledigt');
      expect(result.history.first.status, HabitDayStatus.beforeStart);
      expect(result.checkedToday, isTrue);
      expect(result.series.current, 1);
      expect(result.historySummaryText, '1 von 1 Tagen erledigt');
    });

    test('updates after a retroactive check and after unchecking', () async {
      final id = await add();
      await check(id, today);
      await detail(id);
      // A habit created today has no earlier day: create an older one instead.
      final back = harness.clock.nowUtc();
      setLocalNow(harness, LocalDate(2026, 9, 20));
      final older = await add('Älter');
      harness.clock.setNow(back);
      await check(older, LocalDate(2026, 10, 1));
      await check(older, LocalDate(2026, 10, 2));
      final result = (await detail(older))!;
      expect(result.checkedDaysInHistory, 2);
      expect(result.series.current, 2, reason: 'yesterday and the day before');
      await check(older, LocalDate(2026, 10, 2), checked: false);
      container.listen(habitDetailProvider(older), (_, _) {});
      await settle();
      expect(
        container
            .read(habitDetailProvider(older))
            .requireValue!
            .checkedDaysInHistory,
        1,
      );
    });

    test('is null for an unknown habit and after a delete', () async {
      expect(await detail('missing'), isNull);
      final id = await add();
      expect(await detail(id), isNotNull);
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await settle();
      await pumpEventQueue();
      expect(container.read(habitDetailProvider(id)).requireValue, isNull);
    });

    test('moves with the day: the grid shifts and today is open', () async {
      final id = await add();
      await check(id, today);
      expect((await detail(id))!.history.last.date, today);
      nextDay();
      await settle();
      final result = container.read(habitDetailProvider(id)).requireValue!;
      expect(result.history.last.date, LocalDate(2026, 10, 4));
      expect(result.checkedToday, isFalse);
      expect(
        result.history[28].checked,
        isTrue,
        reason: 'yesterday is checked',
      );
      expect(result.series.current, 1);
    });

    test('an archived habit shows the hint, then reads as ended', () async {
      final id = await add();
      await repository.archive(commandId: harness.ids.newId(), id: id);
      var result = (await detail(id))!;
      expect(result.archivePending, isTrue);
      expect(result.archiveHint, 'Ab morgen archiviert');
      expect(result.ended, isFalse);
      nextDay();
      await settle();
      result = container.read(habitDetailProvider(id)).requireValue!;
      expect(result.ended, isTrue);
      expect(result.history.last.status, HabitDayStatus.archived);
      expect(result.history.last.editable, isFalse);
    });
  });
}
