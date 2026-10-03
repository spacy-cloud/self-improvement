import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/tasks/application/habit_actions_controller.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/habit_test_support.dart';
import '../support/task_test_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  late DataHarness harness;
  late ProviderContainer container;
  late ScriptedHabitRepository repository;

  final today = LocalDate(2026, 10, 3);
  final yesterday = LocalDate(2026, 10, 2);

  setUp(() async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    repository = ScriptedHabitRepository(
      database: harness.database,
      runner: harness.runner,
    );
    container = harness.createContainer(
      overrides: [habitRepositoryProvider.overrideWithValue(repository)],
    );
    container.listen(habitActionsProvider, (_, _) {});
  });
  tearDown(() => harness.dispose());

  HabitActionsController actions() =>
      container.read(habitActionsProvider.notifier);

  HabitActionsState actionsState() => container.read(habitActionsProvider);

  /// A habit that started on 2026-09-20.
  Future<String> add([String title = 'Lesen']) async {
    final back = harness.clock.nowUtc();
    setLocalNow(harness, LocalDate(2026, 9, 20));
    final outcome = await repository.create(
      commandId: harness.ids.newId(),
      draft: HabitDraft(title: title),
    );
    harness.clock.setNow(back);
    repository.commandIds.clear();
    return outcome.entityId!;
  }

  Future<bool> isChecked(String id, LocalDate date) async =>
      await repository.findCheck(id, date) != null;

  group('checking days (AT21, AT12)', () {
    test(
      'checking reports the German message and an undo, XP is awarded',
      () async {
        final id = await add();
        final result = await actions().setChecked(id, today, checked: true);
        expect(result, isA<HabitActionSucceeded>());
        final ok = result as HabitActionSucceeded;
        expect(ok.message, 'Abgehakt');
        expect(ok.undo, isNotNull);
        expect(await isChecked(id, today), isTrue);
        expect(await harness.totalXp(), 5);
      },
    );

    test('unchecking reports its message and takes the XP back', () async {
      final id = await add();
      await actions().setChecked(id, today, checked: true);
      final result = await actions().setChecked(id, today, checked: false);
      expect((result as HabitActionSucceeded).message, 'Haken entfernt');
      expect(await isChecked(id, today), isFalse);
      expect(await harness.totalXp(), 0);
    });

    test(
      'checking a checked day is a success without undo and without a change',
      () async {
        final id = await add();
        await actions().setChecked(id, today, checked: true);
        final result = await actions().setChecked(id, today, checked: true);
        expect((result as HabitActionSucceeded).undo, isNull);
        expect(await harness.totalXp(), 5);
      },
    );

    test('a retroactive check keeps its day', () async {
      final id = await add();
      await actions().setChecked(id, yesterday, checked: true);
      expect(await isChecked(id, yesterday), isTrue);
      expect(await isChecked(id, today), isFalse);
    });

    test('a date outside the window fails with the German rule text', () async {
      final id = await add();
      final future = await actions().setChecked(
        id,
        today.addDays(1),
        checked: true,
      );
      expect(future, isA<HabitActionFailed>());
      expect(
        (future as HabitActionFailed).message,
        'Für zukünftige Tage kann nichts abgehakt werden.',
      );
      final old = await actions().setChecked(
        id,
        LocalDate(2026, 9, 19),
        checked: true,
      );
      expect(
        (old as HabitActionFailed).message,
        'Vor dem Start der Gewohnheit kann nichts abgehakt werden.',
      );
      final tooOld = await actions().setChecked(
        id,
        today.addDays(-31),
        checked: true,
      );
      expect(tooOld, isA<HabitActionFailed>());
      expect(await harness.totalXp(), 0);
    });

    test('a double tap on the same day runs one command, the second is ignored (AT12)', () async {
      final id = await add();
      final results = await Future.wait([
        actions().setChecked(id, today, checked: true),
        actions().setChecked(id, today, checked: true),
      ]);
      expect(results[0], isA<HabitActionSucceeded>());
      expect(results[1], isA<HabitActionBusy>());
      expect(repository.commandIds, hasLength(1));
      expect(await harness.totalXp(), 5);
    });

    test('different days of one habit do not block each other', () async {
      final id = await add();
      final results = await Future.wait([
        actions().setChecked(id, today, checked: true),
        actions().setChecked(id, yesterday, checked: true),
      ]);
      expect(results.whereType<HabitActionSucceeded>(), hasLength(2));
      expect(await harness.totalXp(), 10);
    });

    test('busy is visible per habit and day while the command runs', () async {
      final id = await add();
      repository.gate = Completer<void>();
      final pending = actions().setChecked(id, today, checked: true);
      await pumpEventQueue();
      expect(actionsState().isCheckBusy(id, today), isTrue);
      expect(actionsState().isCheckBusy(id, yesterday), isFalse);
      expect(actionsState().isHabitBusy(id), isFalse);
      repository.gate!.complete();
      await pending;
      expect(actionsState().isCheckBusy(id, today), isFalse);
    });

    test(
      'a failure reports the German text; the retry reuses the command id',
      () async {
        final id = await add();
        repository.failNext = 1;
        final failed = await actions().setChecked(id, today, checked: true);
        expect(failed, isA<HabitActionFailed>());
        expect((failed as HabitActionFailed).failure, isA<StorageFailure>());
        expect(await isChecked(id, today), isFalse);
        expect(actionsState().isCheckBusy(id, today), isFalse);

        final retry = await actions().setChecked(id, today, checked: true);
        expect(retry, isA<HabitActionSucceeded>());
        expect(repository.commandIds, hasLength(2));
        expect(repository.commandIds.first, repository.commandIds.last);
        expect(await harness.totalXp(), 5);
      },
    );

    test('a new action after a success uses a new command id', () async {
      final id = await add();
      await actions().setChecked(id, today, checked: true);
      await actions().setChecked(id, today, checked: false);
      expect(repository.commandIds.toSet(), hasLength(2));
    });

    test(
      'a real database failure rolls back check and XP; the retry works (AT27)',
      () async {
        final id = await add();
        await failInsertsInto(harness, 'habit_checks');
        final failed = await actions().setChecked(id, today, checked: true);
        expect(failed, isA<HabitActionFailed>());
        expect(await isChecked(id, today), isFalse);
        expect(await harness.totalXp(), 0);
        await restoreInserts(harness, 'habit_checks');
        final retry = await actions().setChecked(id, today, checked: true);
        expect(retry, isA<HabitActionSucceeded>());
        expect(await harness.totalXp(), 5);
      },
    );

    test('a missing habit fails with the not-found text', () async {
      final result = await actions().setChecked(
        'missing',
        today,
        checked: true,
      );
      expect(
        (result as HabitActionFailed).message,
        'Dieser Eintrag ist nicht mehr vorhanden.',
      );
    });
  });

  group('undo', () {
    test('undoing a check removes it and its XP', () async {
      final id = await add();
      final done = await actions().setChecked(id, today, checked: true);
      final undone = await actions().undo((done as HabitActionSucceeded).undo!);
      expect((undone as HabitActionSucceeded).message, 'Rückgängig gemacht');
      expect(await isChecked(id, today), isFalse);
      expect(await harness.totalXp(), 0);
    });

    test('undoing an uncheck restores the check and its XP', () async {
      final id = await add();
      await actions().setChecked(id, today, checked: true);
      final removed = await actions().setChecked(id, today, checked: false);
      await actions().undo((removed as HabitActionSucceeded).undo!);
      expect(await isChecked(id, today), isTrue);
      expect(await harness.totalXp(), 5);
    });

    test(
      'an undo after a later change is a conflict, nothing is overwritten',
      () async {
        final id = await add();
        final done = await actions().setChecked(id, today, checked: true);
        await actions().setChecked(id, today, checked: false);
        final result = await actions().undo(
          (done as HabitActionSucceeded).undo!,
        );
        expect(result, isA<HabitActionFailed>());
        expect(
          (result as HabitActionFailed).message,
          'Der Eintrag wurde inzwischen geändert.',
        );
        expect(await isChecked(id, today), isFalse);
      },
    );

    test('a second tap on "Rückgängig" while it runs is ignored', () async {
      final id = await add();
      final done = await actions().setChecked(id, today, checked: true);
      final undo = (done as HabitActionSucceeded).undo!;
      final results = await Future.wait([
        actions().undo(undo),
        actions().undo(undo),
      ]);
      expect(results[0], isA<HabitActionSucceeded>());
      expect(results[1], isA<HabitActionBusy>());
      expect(actionsState().undoRunning, isFalse);
    });
  });

  group('archive and delete', () {
    test('archiving reports "Ab morgen archiviert" without an undo, the habit still applies today', () async {
      final id = await add();
      final result = await actions().archive(id);
      expect((result as HabitActionSucceeded).message, 'Ab morgen archiviert');
      expect(result.undo, isNull);
      final habit = (await repository.findById(id))!;
      expect(habit.archivedFrom, LocalDate(2026, 10, 4));
      expect(habit.appliesOn(today), isTrue);
    });

    test('archiving twice keeps the first archive date', () async {
      final id = await add();
      await actions().archive(id);
      harness.clock.advance(const Duration(days: 1));
      final second = await actions().archive(id);
      expect(second, isA<HabitActionSucceeded>());
      expect(
        (await repository.findById(id))!.archivedFrom,
        LocalDate(2026, 10, 4),
      );
    });

    test('a double tap on archive runs one command', () async {
      final id = await add();
      final results = await Future.wait([
        actions().archive(id),
        actions().archive(id),
      ]);
      expect(results[1], isA<HabitActionBusy>());
      expect(repository.commandIds, hasLength(1));
    });

    test('archiving keeps the checks and the earned XP', () async {
      final id = await add();
      await actions().setChecked(id, today, checked: true);
      await actions().archive(id);
      expect(await isChecked(id, today), isTrue);
      expect(await harness.totalXp(), 5);
    });

    test('delete reports its message; undo restores the habit, its checks and the XP', () async {
      final id = await add();
      await actions().setChecked(id, today, checked: true);
      await actions().setChecked(id, yesterday, checked: true);
      expect(await harness.totalXp(), 10);
      final deleted = await actions().delete(id);
      expect((deleted as HabitActionSucceeded).message, 'Gewohnheit gelöscht');
      expect(await repository.findById(id), isNull);
      expect(await harness.totalXp(), 0);

      final undone = await actions().undo(deleted.undo!);
      expect(undone, isA<HabitActionSucceeded>());
      expect(await repository.findById(id), isNotNull);
      expect(await isChecked(id, today), isTrue);
      expect(await harness.totalXp(), 10);
    });

    test('busy per habit is visible during archive and delete', () async {
      final id = await add();
      repository.gate = Completer<void>();
      final pending = actions().delete(id);
      await pumpEventQueue();
      expect(actionsState().isHabitBusy(id), isTrue);
      repository.gate!.complete();
      await pending;
      expect(actionsState().isHabitBusy(id), isFalse);
    });

    test('deleting an unknown habit fails with the not-found text', () async {
      final result = await actions().delete('missing');
      expect(
        (result as HabitActionFailed).message,
        'Dieser Eintrag ist nicht mehr vorhanden.',
      );
    });

    test('a failed archive can be retried with the same command id', () async {
      final id = await add();
      repository.failNext = 1;
      expect(await actions().archive(id), isA<HabitActionFailed>());
      expect(await actions().archive(id), isA<HabitActionSucceeded>());
      expect(repository.commandIds.first, repository.commandIds.last);
      expect((await repository.findById(id))!.archivedFrom, isNotNull);
    });

    test('the busy key of a check is habit and day', () {
      expect(
        HabitActionsController.checkKey('h1', LocalDate(2026, 10, 3)),
        'h1|2026-10-03',
      );
    });
  });

  group('after midnight (AT25)', () {
    test(
      'a check on the new day after midnight lands on the new day',
      () async {
        final id = await add();
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 21, 59, 50));
        await actions().setChecked(id, today, checked: true);
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 0, 10));
        await actions().setChecked(id, LocalDate(2026, 10, 4), checked: true);
        expect(await isChecked(id, today), isTrue);
        expect(await isChecked(id, LocalDate(2026, 10, 4)), isTrue);
        expect(await harness.totalXp(), 10);
      },
    );

    test(
      'a stale screen that still shows yesterday as today can still check it',
      () async {
        final id = await add();
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 0, 10));
        final result = await actions().setChecked(id, today, checked: true);
        expect(
          result,
          isA<HabitActionSucceeded>(),
          reason: 'yesterday is inside the 30 day window',
        );
      },
    );
  });
}
