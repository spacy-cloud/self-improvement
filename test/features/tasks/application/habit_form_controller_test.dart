import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/tasks/application/habit_form_controller.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/features/tasks/domain/habit_validation.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/habit_test_support.dart';
import '../support/task_test_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  late DataHarness harness;
  late ProviderContainer container;
  late ScriptedHabitRepository repository;

  setUp(() async {
    harness = await DataHarness.create();
    repository = ScriptedHabitRepository(
      database: harness.database,
      runner: harness.runner,
    );
    container = harness.createContainer(
      overrides: [habitRepositoryProvider.overrideWithValue(repository)],
    );
  });
  tearDown(() => harness.dispose());

  const create = HabitFormArgs.create();

  HabitFormController controller(HabitFormArgs args) =>
      container.read(habitFormProvider(args).notifier);

  HabitFormState formState(HabitFormArgs args) =>
      container.read(habitFormProvider(args));

  Future<List<Habit>> stored() => repository.watchAll().first;

  Future<Habit> seedHabit({
    String title = 'Bestehend',
    String iconKey = 'moon',
    LocalTime? reminder,
  }) async {
    final outcome = await repository.create(
      commandId: harness.ids.newId(),
      draft: HabitDraft(title: title, iconKey: iconKey, reminderTime: reminder),
    );
    repository.commandIds.clear();
    return (await repository.findById(outcome.entityId!))!;
  }

  group('new habit', () {
    test('starts empty with the book icon and the reminder off', () {
      final s = formState(create);
      expect(s.title, isEmpty);
      expect(s.icon, HabitIcon.book);
      expect(s.reminderEnabled, isFalse);
      expect(s.reminderTime, defaultHabitReminderTime);
      expect(s.dirty, isFalse);
      expect(s.submitting, isFalse);
      expect(s.fieldErrors, isEmpty);
      expect(s.submitFailure, isNull);
      expect(controller(create).isEdit, isFalse);
    });

    test(
      'an empty title is rejected with a hint and nothing is saved',
      () async {
        expect(await controller(create).submit(), isA<HabitRejected>());
        expect(
          formState(create).fieldErrors[HabitFields.title],
          'Bitte gib einen Titel ein.',
        );
        expect(await stored(), isEmpty);
        expect(repository.commandIds, isEmpty);
      },
    );

    test('title 80 is saved, title 81 is rejected', () async {
      controller(create).setTitle('a' * 81);
      expect(await controller(create).submit(), isA<HabitRejected>());
      expect(
        formState(create).fieldErrors[HabitFields.title],
        'Der Titel darf höchstens 80 Zeichen lang sein.',
      );
      controller(create).setTitle('a' * 80);
      expect(await controller(create).submit(), isA<HabitSaved>());
      expect((await stored()).single.title, 'a' * 80);
    });

    test('saves with the default icon book and no reminder, reports the message and undo', () async {
      controller(create).setTitle('  Lesen ');
      final result = await controller(create).submit();
      expect(result, isA<HabitSaved>());
      final saved = result as HabitSaved;
      expect(saved.message, 'Gewohnheit gespeichert');
      expect(saved.wasEdit, isFalse);
      expect(saved.outcome.undo, isNotNull);
      final habit = (await stored()).single;
      expect(saved.habitId, habit.id);
      expect(habit.title, 'Lesen');
      expect(habit.icon, HabitIcon.book);
      expect(habit.reminderTime, isNull);
      expect(habit.startedOn, harness.clock.today());
    });

    test('every one of the six icons can be chosen and is saved', () async {
      for (final icon in HabitIcon.values) {
        container.invalidate(habitFormProvider(create));
        controller(create).setTitle(icon.label);
        controller(create).setIcon(icon);
        expect(formState(create).icon, icon);
        expect(await controller(create).submit(), isA<HabitSaved>());
      }
      final habits = await stored();
      expect(habits.map((h) => h.icon).toSet(), HabitIcon.values.toSet());
      expect(habits, hasLength(6));
    });

    test('editing a field clears only its own error', () async {
      controller(create).setTitle('');
      await controller(create).submit();
      expect(formState(create).fieldErrors, isNotEmpty);
      controller(create).setIcon(HabitIcon.heart);
      expect(
        formState(create).fieldErrors.containsKey(HabitFields.title),
        isTrue,
      );
      controller(create).setTitle('x');
      expect(formState(create).fieldErrors, isEmpty);
    });

    test(
      'after a success a further save is a new habit (new command id)',
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

  group('reminder (daily, off by default)', () {
    test('switching on offers the default time and saves it', () async {
      controller(create).setTitle('Lesen');
      controller(create).setReminderEnabled(true);
      expect(formState(create).reminderTime, const LocalTime(20, 0));
      await controller(create).submit();
      expect((await stored()).single.reminderTime, const LocalTime(20, 0));
    });

    test(
      'choosing a time switches the reminder on and saves exactly that time',
      () async {
        controller(create).setTitle('Lesen');
        controller(create).setReminderTime(const LocalTime(7, 30));
        expect(formState(create).reminderEnabled, isTrue);
        await controller(create).submit();
        expect((await stored()).single.reminderTime, const LocalTime(7, 30));
      },
    );

    test(
      'switching off keeps the time for later but saves no reminder',
      () async {
        controller(create).setTitle('Lesen');
        controller(create).setReminderTime(const LocalTime(6, 15));
        controller(create).setReminderEnabled(false);
        expect(formState(create).reminderTime, const LocalTime(6, 15));
        await controller(create).submit();
        expect((await stored()).single.reminderTime, isNull);
        controller(create).setReminderEnabled(true);
        expect(formState(create).reminderTime, const LocalTime(6, 15));
      },
    );

    test('editing can clear a stored reminder', () async {
      final habit = await seedHabit(reminder: const LocalTime(8, 0));
      final args = HabitFormArgs.edit(habit);
      expect(formState(args).reminderEnabled, isTrue);
      expect(formState(args).reminderTime, const LocalTime(8, 0));
      controller(args).setReminderEnabled(false);
      expect(await controller(args).submit(), isA<HabitSaved>());
      expect((await repository.findById(habit.id))!.reminderTime, isNull);
    });

    test('editing can set a reminder on a habit without one', () async {
      final habit = await seedHabit();
      final args = HabitFormArgs.edit(habit);
      expect(formState(args).reminderEnabled, isFalse);
      controller(args).setReminderTime(const LocalTime(9, 45));
      await controller(args).submit();
      expect(
        (await repository.findById(habit.id))!.reminderTime,
        const LocalTime(9, 45),
      );
    });
  });

  group('dirty flag (discard dialog)', () {
    test('is set by every kind of change', () {
      final changes = <void Function()>[
        () => controller(create).setTitle('x'),
        () => controller(create).setIcon(HabitIcon.flame),
        () => controller(create).setReminderEnabled(true),
        () => controller(create).setReminderTime(const LocalTime(7, 0)),
      ];
      for (final change in changes) {
        container.invalidate(habitFormProvider(create));
        expect(formState(create).dirty, isFalse);
        change();
        expect(formState(create).dirty, isTrue);
      }
    });

    test('changes that are reverted are not dirty', () {
      controller(create).setTitle('abc');
      controller(create).setTitle('');
      expect(formState(create).dirty, isFalse);
      controller(create).setIcon(HabitIcon.moon);
      controller(create).setIcon(HabitIcon.book);
      expect(formState(create).dirty, isFalse);
      controller(create).setReminderEnabled(true);
      controller(create).setReminderEnabled(false);
      expect(formState(create).dirty, isFalse);
    });

    test(
      'whitespace only is not a change; a saved form is not dirty',
      () async {
        controller(create).setTitle('   ');
        expect(formState(create).dirty, isFalse);
        controller(create).setTitle('x');
        expect(formState(create).dirty, isTrue);
        await controller(create).submit();
        expect(formState(create).dirty, isFalse);
      },
    );

    test('an edit form compares with the opened habit', () async {
      final habit = await seedHabit();
      final args = HabitFormArgs.edit(habit);
      expect(formState(args).dirty, isFalse);
      controller(args).setIcon(HabitIcon.heart);
      expect(formState(args).dirty, isTrue);
      controller(args).setIcon(habit.icon);
      expect(formState(args).dirty, isFalse);
    });
  });

  group('edit', () {
    test('is prefilled from the habit and saves the change', () async {
      final habit = await seedHabit(title: 'Alt', iconKey: 'moon');
      final args = HabitFormArgs.edit(habit);
      expect(formState(args).title, 'Alt');
      expect(formState(args).icon, HabitIcon.moon);
      expect(controller(args).isEdit, isTrue);

      controller(args).setTitle('Neu');
      controller(args).setIcon(HabitIcon.drop);
      final result = await controller(args).submit();
      expect(result, isA<HabitSaved>());
      final saved = result as HabitSaved;
      expect(saved.message, 'Gewohnheit aktualisiert');
      expect(saved.wasEdit, isTrue);
      expect(saved.habitId, habit.id);
      final after = (await repository.findById(habit.id))!;
      expect(after.title, 'Neu');
      expect(after.icon, HabitIcon.drop);
      expect(after.rowVersion, habit.rowVersion + 1);
      expect(
        after.startedOn,
        habit.startedOn,
        reason: 'history is not rewritten',
      );
    });

    test('a stale version is a conflict: nothing saved, input kept', () async {
      final habit = await seedHabit();
      final args = HabitFormArgs.edit(habit);
      await repository.update(
        commandId: harness.ids.newId(),
        id: habit.id,
        draft: const HabitDraft(title: 'Zwischendurch'),
        expectedRowVersion: habit.rowVersion,
      );
      controller(args).setTitle('Meine Änderung');
      expect(await controller(args).submit(), isA<HabitRejected>());
      final s = formState(args);
      expect(s.submitFailure, isA<ConflictFailure>());
      expect(
        s.submitFailure!.userMessage,
        'Der Eintrag wurde inzwischen geändert.',
      );
      expect(s.title, 'Meine Änderung');
      expect((await repository.findById(habit.id))!.title, 'Zwischendurch');
    });

    test('a habit deleted meanwhile is reported, the input stays', () async {
      final habit = await seedHabit();
      final args = HabitFormArgs.edit(habit);
      await repository.delete(commandId: harness.ids.newId(), id: habit.id);
      controller(args).setTitle('Neu');
      expect(await controller(args).submit(), isA<HabitRejected>());
      expect(formState(args).submitFailure, isA<NotFoundFailure>());
      expect(formState(args).title, 'Neu');
    });

    test('form args are equal for the same habit version only', () async {
      final habit = await seedHabit();
      expect(HabitFormArgs.edit(habit), HabitFormArgs.edit(habit));
      expect(const HabitFormArgs.create(), const HabitFormArgs.create());
      await repository.update(
        commandId: harness.ids.newId(),
        id: habit.id,
        draft: const HabitDraft(title: 'x'),
        expectedRowVersion: habit.rowVersion,
      );
      final newer = (await repository.findById(habit.id))!;
      expect(HabitFormArgs.edit(newer), isNot(HabitFormArgs.edit(habit)));
    });
  });

  group('submit safety (AT12, AT27)', () {
    test('a double tap saves exactly one habit', () async {
      controller(create).setTitle('Einmal');
      final results = await Future.wait([
        controller(create).submit(),
        controller(create).submit(),
      ]);
      expect(results.whereType<HabitSaved>(), hasLength(1));
      expect(results.whereType<HabitRejected>(), hasLength(1));
      expect(await stored(), hasLength(1));
      expect(repository.commandIds, hasLength(1));
    });

    test('submitting is visible while the save runs', () async {
      container.listen(habitFormProvider(create), (_, _) {});
      controller(create).setTitle('x');
      repository.gate = Completer<void>();
      final pending = controller(create).submit();
      await pumpEventQueue();
      expect(formState(create).submitting, isTrue);
      repository.gate!.complete();
      await pending;
      expect(formState(create).submitting, isFalse);
    });

    test(
      'a storage failure keeps the input, the retry reuses the command id',
      () async {
        controller(create).setTitle('Bleibt');
        controller(create).setIcon(HabitIcon.flame);
        controller(create).setReminderTime(const LocalTime(7, 0));
        repository.failNext = 1;
        expect(await controller(create).submit(), isA<HabitRejected>());
        final s = formState(create);
        expect(s.submitFailure, isA<StorageFailure>());
        expect(s.submitting, isFalse);
        expect(s.title, 'Bleibt');
        expect(s.icon, HabitIcon.flame);
        expect(s.reminderTime, const LocalTime(7, 0));
        expect(await stored(), isEmpty);

        expect(await controller(create).submit(), isA<HabitSaved>());
        expect(formState(create).submitFailure, isNull);
        expect(await stored(), hasLength(1));
        expect(repository.commandIds, hasLength(2));
        expect(repository.commandIds.first, repository.commandIds.last);
      },
    );

    test('changed content after a failure gets a NEW command id', () async {
      controller(create).setTitle('Erst');
      repository.failNext = 1;
      await controller(create).submit();
      controller(create).setTitle('Dann anders');
      await controller(create).submit();
      expect(repository.commandIds.first, isNot(repository.commandIds.last));
      expect((await stored()).single.title, 'Dann anders');
    });

    test(
      'a real database failure rolls back; the retry succeeds (AT27)',
      () async {
        controller(create).setTitle('Echt');
        await failInsertsInto(harness, 'habits');
        expect(await controller(create).submit(), isA<HabitRejected>());
        expect(formState(create).submitFailure, isA<StorageFailure>());
        expect(await stored(), isEmpty);
        expect(
          await harness.database.select(harness.database.commandReceipts).get(),
          isEmpty,
        );
        await restoreInserts(harness, 'habits');
        expect(await controller(create).submit(), isA<HabitSaved>());
        expect(await stored(), hasLength(1));
      },
    );
  });
}
