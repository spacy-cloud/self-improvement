import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/tasks/data/habit_repository.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/features/tasks/domain/habit_validation.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/task_test_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  late DataHarness harness;
  late RecordingProjectionSynchronizer projection;
  late HabitRepository repository;

  // "now" is 2026-10-03 08:00Z = 10:00 in Berlin (a Saturday).
  final today = LocalDate(2026, 10, 3);

  setUp(() async {
    projection = RecordingProjectionSynchronizer();
    harness = await DataHarness.create(projections: projection);
    repository = HabitRepository(
      database: harness.database,
      runner: harness.runner,
    );
  });
  tearDown(() => harness.dispose());

  HabitDraft draft({
    String title = 'Lesen',
    String iconKey = 'book',
    LocalTime? reminder,
  }) => HabitDraft(title: title, iconKey: iconKey, reminderTime: reminder);

  Future<String> create([HabitDraft? d, String? commandId]) async {
    final outcome = await repository.create(
      commandId: commandId ?? harness.ids.newId(),
      draft: d ?? draft(),
    );
    return outcome.entityId!;
  }

  /// Creates a habit that started [start] and returns to the "now" of the test.
  Future<String> createStartedOn(LocalDate start, [HabitDraft? d]) async {
    final back = harness.clock.nowUtc();
    setLocalNow(harness, start);
    final id = await create(d);
    harness.clock.setNow(back);
    return id;
  }

  Future<Habit> reload(String id) async => (await repository.findById(id))!;

  Future<List<HabitCheckRow>> rawChecks(String habitId) =>
      (harness.database.select(harness.database.habitChecks)
            ..where((c) => c.habitId.equals(habitId))
            ..orderBy([(c) => OrderingTerm.asc(c.localDate)]))
          .get();

  Future<HabitCheckRow> rawCheck(String habitId, LocalDate date) async =>
      (await rawChecks(habitId)).singleWhere((c) => c.localDate == date);

  Future<HabitRow> rawHabit(String id) => (harness.database.select(
    harness.database.habits,
  )..where((h) => h.id.equals(id))).getSingle();

  Future<CommandOutcome> check(
    String habitId,
    LocalDate date, {
    String? commandId,
  }) async => repository.setChecked(
    commandId: commandId ?? harness.ids.newId(),
    habitId: habitId,
    date: date,
    checked: true,
  );

  Future<CommandOutcome> uncheck(String habitId, LocalDate date) async =>
      repository.setChecked(
        commandId: harness.ids.newId(),
        habitId: habitId,
        date: date,
        checked: false,
      );

  Future<List<CommandReceiptRow>> receipts() =>
      harness.database.select(harness.database.commandReceipts).get();

  Matcher conflict(ConflictKind kind) =>
      throwsA(isA<ConflictFailure>().having((f) => f.kind, 'kind', kind));

  Future<ValidationFailure> rejection(Future<Object?> action) async {
    try {
      await action;
    } on ValidationFailure catch (error) {
      return error;
    }
    fail('expected a ValidationFailure');
  }

  group('create (T02)', () {
    test('stores the title trimmed, book as default icon, no reminder, starts today', () async {
      final id = await create(draft(title: '  Lesen  '));
      final habit = await reload(id);
      expect(habit.title, 'Lesen');
      expect(habit.icon, HabitIcon.book);
      expect(habit.reminderTime, isNull);
      expect(habit.startedOn, today);
      expect(habit.archivedFrom, isNull);
      expect(habit.rowVersion, 1);
      expect(habit.createdAtUtc, harness.clock.nowUtc());
    });

    test('icon and reminder time are stored (HH:mm)', () async {
      final id = await create(
        draft(iconKey: 'flame', reminder: const LocalTime(7, 5)),
      );
      final habit = await reload(id);
      expect(habit.icon, HabitIcon.flame);
      expect(habit.reminderTime, const LocalTime(7, 5));
      final raw = await harness.database
          .customSelect(
            'SELECT icon_key AS i, reminder_local_time AS r '
            'FROM habits WHERE id = ?1',
            variables: [Variable(id)],
          )
          .getSingle();
      expect(raw.read<String>('i'), 'flame');
      expect(raw.read<String>('r'), '07:05');
    });

    test(
      'the start day is frozen at creation, across local midnight',
      () async {
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 21, 59, 50));
        final late = await create(draft(title: 'Spät'));
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 0, 10));
        final early = await create(draft(title: 'Früh'));
        expect((await reload(late)).startedOn, LocalDate(2026, 10, 3));
        expect((await reload(early)).startedOn, LocalDate(2026, 10, 4));
      },
    );

    test('the start day on the DST days follows the local calendar', () async {
      harness.clock.setNow(DateTime.utc(2026, 3, 28, 23, 30)); // 00:30 CET
      final spring = await create(draft(title: 'Frühling'));
      harness.clock.setNow(DateTime.utc(2026, 10, 24, 22, 30)); // 00:30 CEST
      final autumn = await create(draft(title: 'Herbst'));
      harness.clock.setNow(DateTime.utc(2026, 10, 25, 23, 30)); // 00:30 CET
      final after = await create(draft(title: 'Danach'));
      expect((await reload(spring)).startedOn, LocalDate(2026, 3, 29));
      expect((await reload(autumn)).startedOn, LocalDate(2026, 10, 25));
      expect((await reload(after)).startedOn, LocalDate(2026, 10, 26));
    });

    test('a later zone change never moves the start day', () async {
      final id = await create();
      harness.clock.setTimeZone('Pacific/Auckland');
      expect((await reload(id)).startedOn, today);
    });

    test(
      'syncs today inside the command (the goal snapshot gains the habit)',
      () async {
        await create();
        expect(projection.syncs, [
          {today},
        ]);
      },
    );

    test(
      'the same command id is one habit, a new id a new habit (AT12)',
      () async {
        final first = await repository.create(commandId: 'c1', draft: draft());
        final replay = await repository.create(commandId: 'c1', draft: draft());
        expect(replay.replayed, isTrue);
        expect(replay.entityId, first.entityId);
        expect(replay.undo, isNull);
        await repository.create(commandId: 'c2', draft: draft());
        expect(await repository.watchAll().first, hasLength(2));
      },
    );

    test(
      'there is no frequency, weekday or time-of-day field: V1 is daily only',
      () {
        final columns = harness.database.habits.$columns
            .map((c) => c.name)
            .toSet();
        expect(columns, {
          'created_at_utc',
          'updated_at_utc',
          'row_version',
          'deleted_at_utc',
          'id',
          'title',
          'started_local_date',
          'archived_from_date',
          'reminder_local_time',
          'icon_key',
        });
      },
    );
  });

  group('validation at the repository', () {
    test('title 80 is stored, 81 is rejected', () async {
      await create(draft(title: 'a' * 80));
      final error = await rejection(create(draft(title: 'a' * 81)));
      expect(error.fieldErrors.keys, contains(HabitFields.title));
    });

    test('an unknown icon key is rejected with a field error', () async {
      final error = await rejection(create(draft(iconKey: 'rocket')));
      expect(error.fieldErrors[HabitFields.icon], isNotNull);
      for (final key in ['book', 'moon', 'drop', 'check', 'flame', 'heart']) {
        await create(draft(title: key, iconKey: key));
      }
      expect(await repository.watchAll().first, hasLength(6));
    });

    test(
      'a rejected draft leaves no habit, no receipt, no projection call',
      () async {
        await rejection(create(draft(title: ' ', iconKey: 'x')));
        expect(await repository.watchAll().first, isEmpty);
        expect(await receipts(), isEmpty);
        expect(projection.syncs, isEmpty);
      },
    );

    test(
      'the database also rejects an unknown icon key (CHECK constraint)',
      () async {
        await expectLater(
          harness.database
              .into(harness.database.habits)
              .insert(
                HabitsCompanion.insert(
                  id: 'raw',
                  title: 'x',
                  startedLocalDate: today,
                  iconKey: const Value('rocket'),
                  createdAtUtc: harness.clock.nowUtc(),
                  updatedAtUtc: harness.clock.nowUtc(),
                ),
              ),
          throwsA(anything),
        );
      },
    );
  });

  group('update (title, icon and reminder only)', () {
    test('changes title, icon and reminder and bumps the version', () async {
      final id = await create(draft(title: 'alt', iconKey: 'book'));
      harness.clock.advance(const Duration(minutes: 5));
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(
          title: 'neu',
          iconKey: 'moon',
          reminder: const LocalTime(21, 30),
        ),
        expectedRowVersion: 1,
      );
      final habit = await reload(id);
      expect(habit.title, 'neu');
      expect(habit.icon, HabitIcon.moon);
      expect(habit.reminderTime, const LocalTime(21, 30));
      expect(habit.rowVersion, 2);
    });

    test(
      'the reminder is a wall clock time: a zone change does not touch it',
      () async {
        final id = await create(draft(reminder: const LocalTime(7, 30)));
        harness.clock.setTimeZone('Asia/Tokyo');
        expect((await reload(id)).reminderTime, const LocalTime(7, 30));
        expect((await rawHabit(id)).reminderLocalTime, const LocalTime(7, 30));
      },
    );

    test('the reminder can be switched off again (stored as null)', () async {
      final id = await create(draft(reminder: const LocalTime(8, 0)));
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(),
        expectedRowVersion: 1,
      );
      expect((await reload(id)).reminderTime, isNull);
      expect((await rawHabit(id)).reminderLocalTime, isNull);
    });

    test(
      'never rewrites history: start day, archive date and checks stay',
      () async {
        final id = await createStartedOn(LocalDate(2026, 9, 20));
        await check(id, LocalDate(2026, 9, 25));
        await repository.archive(commandId: harness.ids.newId(), id: id);
        final before = await reload(id);
        final checkBefore = await rawCheck(id, LocalDate(2026, 9, 25));
        projection.syncs.clear();
        harness.clock.advance(const Duration(hours: 1));
        await repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(title: 'Umbenannt', iconKey: 'heart'),
          expectedRowVersion: before.rowVersion,
        );
        final after = await reload(id);
        expect(after.startedOn, LocalDate(2026, 9, 20));
        expect(after.archivedFrom, before.archivedFrom);
        final checkAfter = await rawCheck(id, LocalDate(2026, 9, 25));
        expect(checkAfter.rowVersion, checkBefore.rowVersion);
        expect(checkAfter.checkedAtUtc, checkBefore.checkedAtUtc);
        expect(checkAfter.eligibility, checkBefore.eligibility);
        expect(projection.syncs, isEmpty, reason: 'no fact day is affected');
      },
    );

    test('a stale form version is a conflict and changes nothing', () async {
      final id = await create(draft(title: 'bleibt'));
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(title: 'neu'),
          expectedRowVersion: 99,
        ),
        conflict(ConflictKind.staleVersion),
      );
      expect((await reload(id)).title, 'bleibt');
    });

    test('an invalid edit changes nothing', () async {
      final id = await create(draft(title: 'bleibt'));
      await rejection(
        repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(iconKey: 'rocket'),
          expectedRowVersion: 1,
        ),
      );
      expect((await reload(id)).rowVersion, 1);
    });

    test('a missing or deleted habit is NotFound', () async {
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: 'missing',
          draft: draft(),
          expectedRowVersion: 1,
        ),
        throwsA(isA<NotFoundFailure>()),
      );
      final id = await create();
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(),
          expectedRowVersion: 2,
        ),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('undoing an update restores title, icon and reminder', () async {
      final id = await create(
        draft(
          title: 'vorher',
          iconKey: 'drop',
          reminder: const LocalTime(6, 0),
        ),
      );
      final outcome = await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(title: 'nachher'),
        expectedRowVersion: 1,
      );
      await outcome.undo!.run(harness.ids.newId());
      final habit = await reload(id);
      expect(habit.title, 'vorher');
      expect(habit.icon, HabitIcon.drop);
      expect(habit.reminderTime, const LocalTime(6, 0));
    });

    test('undoing an update is refused after another change', () async {
      final id = await create();
      final outcome = await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(title: 'a'),
        expectedRowVersion: 1,
      );
      await repository.archive(commandId: harness.ids.newId(), id: id);
      await expectLater(
        outcome.undo!.run(harness.ids.newId()),
        conflict(ConflictKind.staleVersion),
      );
    });

    test('an archived habit can still be renamed', () async {
      final id = await create();
      await repository.archive(commandId: harness.ids.newId(), id: id);
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(title: 'Archiviert umbenannt'),
        expectedRowVersion: 2,
      );
      final habit = await reload(id);
      expect(habit.title, 'Archiviert umbenannt');
      expect(habit.archivedFrom, LocalDate(2026, 10, 4));
    });
  });

  group('the 30 day window of checks (T02, specification 9.2)', () {
    late String id;

    setUp(() async {
      id = await createStartedOn(LocalDate(2026, 8, 1));
      projection.syncs.clear();
    });

    test('today and the day -30 are allowed', () async {
      await check(id, today);
      await check(id, today.addDays(-30));
      expect(await rawChecks(id), hasLength(2));
    });

    test('the day -31 is rejected, nothing is stored', () async {
      final error = await rejection(check(id, today.addDays(-31)));
      expect(
        error.fieldErrors[HabitFields.date],
        HabitCheckDateError.tooOld.message,
      );
      expect(await rawChecks(id), isEmpty);
      expect(
        await receipts().then((r) => r.length),
        1,
        reason: 'only the create',
      );
      expect(projection.syncs, isEmpty);
    });

    test('the future is rejected', () async {
      final error = await rejection(check(id, today.addDays(1)));
      expect(
        error.fieldErrors[HabitFields.date],
        HabitCheckDateError.future.message,
      );
      expect(await rawChecks(id), isEmpty);
    });

    test('a day before the start of the habit is rejected', () async {
      final young = await create(draft(title: 'Neu'));
      final error = await rejection(check(young, today.addDays(-1)));
      expect(
        error.fieldErrors[HabitFields.date],
        HabitCheckDateError.beforeStart.message,
      );
      await check(young, today);
      expect(await rawChecks(young), hasLength(1));
    });

    test('the archive date and everything after it is rejected, the archive day is not', () async {
      await repository.archive(commandId: harness.ids.newId(), id: id);
      await check(id, today); // still applies on the archive day
      harness.clock.advance(const Duration(days: 2)); // 2026-10-05
      final newToday = LocalDate(2026, 10, 5);
      for (final date in [LocalDate(2026, 10, 4), newToday]) {
        final error = await rejection(check(id, date));
        expect(
          error.fieldErrors[HabitFields.date],
          HabitCheckDateError.archived.message,
          reason: '$date',
        );
      }
      await check(id, today); // the day before the archive date stays editable
      expect(await rawChecks(id), hasLength(1));
    });

    test('unchecking is bound to the same window', () async {
      await check(id, today.addDays(-30));
      harness.clock.advance(const Duration(days: 1));
      final error = await rejection(uncheck(id, today.addDays(-30)));
      expect(
        error.fieldErrors[HabitFields.date],
        HabitCheckDateError.tooOld.message,
      );
      expect((await rawChecks(id)).single.deletedAtUtc, isNull);
    });

    test('the window moves with the day', () async {
      harness.clock.advance(const Duration(days: 1));
      await rejection(check(id, today.addDays(-30)));
      await check(id, today.addDays(-29));
    });

    test('a deleted or unknown habit is NotFound', () async {
      await expectLater(
        repository.setChecked(
          commandId: harness.ids.newId(),
          habitId: 'missing',
          date: today,
          checked: true,
        ),
        throwsA(isA<NotFoundFailure>()),
      );
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await expectLater(check(id, today), throwsA(isA<NotFoundFailure>()));
    });
  });

  group('checking and unchecking (T02, AT21)', () {
    late String id;

    setUp(() async {
      id = await createStartedOn(LocalDate(2026, 9, 1));
      projection.syncs.clear();
    });

    test('a check freezes its day, time, zone and eligibility flag', () async {
      final outcome = await check(id, today);
      expect(outcome.undo, isNotNull);
      final row = await rawCheck(id, today);
      expect(row.localDate, today);
      expect(row.checkedAtUtc, DateTime.utc(2026, 10, 3, 8));
      expect(row.timezoneId, 'Europe/Berlin');
      expect(row.eligibility, isTrue);
      expect(row.deletedAtUtc, isNull);
      expect(row.rowVersion, 1);
      expect(projection.syncs.single, {today});
      expect((await repository.findCheck(id, today))!.date, today);
    });

    test('a retroactive check keeps ITS day and syncs that day', () async {
      final past = today.addDays(-3);
      await check(id, past);
      final row = await rawCheck(id, past);
      expect(row.localDate, past);
      expect(
        row.checkedAtUtc,
        harness.clock.nowUtc(),
        reason: 'when it was ticked',
      );
      expect(projection.syncs.single, {past});
    });

    test('eligibility is false while gamification is off', () async {
      await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
      await check(id, today);
      expect((await rawCheck(id, today)).eligibility, isFalse);
    });

    test('the same command id is a replay and changes nothing', () async {
      await check(id, today, commandId: 'tap');
      projection.syncs.clear();
      harness.clock.advance(const Duration(minutes: 5));
      final replay = await check(id, today, commandId: 'tap');
      expect(replay.replayed, isTrue);
      expect(replay.undo, isNull);
      expect(await rawChecks(id), hasLength(1));
      expect(
        (await rawCheck(id, today)).checkedAtUtc,
        DateTime.utc(2026, 10, 3, 8),
      );
      expect(projection.syncs, isEmpty);
    });

    test(
      'a NEW command id for an already checked day is a no-op without undo',
      () async {
        await check(id, today);
        final before = await rawCheck(id, today);
        projection.syncs.clear();
        harness.clock.advance(const Duration(minutes: 5));
        final again = await check(id, today);
        expect(again.undo, isNull);
        expect(again.replayed, isFalse);
        final after = await rawCheck(id, today);
        expect(after.rowVersion, before.rowVersion);
        expect(after.checkedAtUtc, before.checkedAtUtc);
        expect(projection.syncs, isEmpty);
      },
    );

    test('unchecking soft-deletes the check and syncs its day', () async {
      await check(id, today);
      projection.syncs.clear();
      final outcome = await uncheck(id, today);
      expect(outcome.undo, isNotNull);
      final row = await rawCheck(id, today);
      expect(row.deletedAtUtc, isNotNull, reason: 'the row is kept');
      expect(row.rowVersion, 2);
      expect(await repository.findCheck(id, today), isNull);
      expect(projection.syncs.single, {today});
    });

    test('unchecking an unchecked or never checked day is a no-op', () async {
      final never = await uncheck(id, today);
      expect(never.undo, isNull);
      expect(await rawChecks(id), isEmpty);
      await check(id, today);
      await uncheck(id, today);
      final again = await uncheck(id, today);
      expect(again.undo, isNull);
      expect((await rawCheck(id, today)).rowVersion, 2);
    });

    test('checking again REACTIVATES the row: one row per habit and day, fresh time and flag', () async {
      await check(id, today);
      final original = await rawCheck(id, today);
      await uncheck(id, today);
      harness.clock.advance(const Duration(minutes: 20));
      await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
      await check(id, today);
      final rows = await rawChecks(id);
      expect(rows, hasLength(1), reason: 'never a second row for the same day');
      final reactivated = rows.single;
      expect(reactivated.id, original.id);
      expect(reactivated.deletedAtUtc, isNull);
      expect(reactivated.checkedAtUtc.isAfter(original.checkedAtUtc), isTrue);
      expect(
        reactivated.eligibility,
        isFalse,
        reason: 'fresh flag, gamification is off now',
      );
      expect(reactivated.rowVersion, 3);
    });

    test(
      'check, uncheck, check, uncheck, check keeps exactly one row',
      () async {
        for (var i = 0; i < 2; i++) {
          await check(id, today);
          await uncheck(id, today);
        }
        await check(id, today);
        expect(await rawChecks(id), hasLength(1));
        expect((await rawChecks(id)).single.rowVersion, 5);
      },
    );

    test('different days are different rows', () async {
      await check(id, today);
      await check(id, today.addDays(-1));
      await check(id, today.addDays(-2));
      expect(await rawChecks(id), hasLength(3));
    });

    test('undoing a first check soft-deletes it, checking again reactivates that row', () async {
      final outcome = await check(id, today);
      final originalId = outcome.entityId;
      await outcome.undo!.run(harness.ids.newId());
      expect(await repository.findCheck(id, today), isNull);
      expect((await rawCheck(id, today)).deletedAtUtc, isNotNull);
      await check(id, today);
      final rows = await rawChecks(id);
      expect(rows, hasLength(1));
      expect(rows.single.id, originalId);
      expect(rows.single.deletedAtUtc, isNull);
    });

    test(
      'undoing an uncheck restores the EXACT earlier check incl. time and flag',
      () async {
        await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
        await check(id, today);
        final original = await rawCheck(id, today);
        expect(original.eligibility, isFalse);
        harness.clock.advance(const Duration(minutes: 10));
        await setModuleEnabled(harness, ModuleId.gamification, enabled: true);
        final unchecked = await uncheck(id, today);
        await unchecked.undo!.run(harness.ids.newId());
        final restored = await rawCheck(id, today);
        expect(restored.deletedAtUtc, isNull);
        expect(restored.checkedAtUtc, original.checkedAtUtc);
        expect(restored.timezoneId, original.timezoneId);
        expect(
          restored.eligibility,
          isFalse,
          reason: 'the old flag, not the current state',
        );
      },
    );

    test(
      'undoing a reactivation restores the earlier unchecked state',
      () async {
        await check(id, today);
        final firstCheck = await rawCheck(id, today);
        await uncheck(id, today);
        final deletedState = await rawCheck(id, today);
        harness.clock.advance(const Duration(minutes: 10));
        final reactivated = await check(id, today);
        await reactivated.undo!.run(harness.ids.newId());
        final restored = await rawCheck(id, today);
        expect(restored.deletedAtUtc, deletedState.deletedAtUtc);
        expect(restored.checkedAtUtc, firstCheck.checkedAtUtc);
        expect(await repository.findCheck(id, today), isNull);
        expect(await rawChecks(id), hasLength(1));
      },
    );

    test('an undo is refused when the check changed meanwhile', () async {
      final first = await check(id, today);
      await uncheck(id, today);
      await expectLater(
        first.undo!.run(harness.ids.newId()),
        conflict(ConflictKind.staleVersion),
      );
      expect(await repository.findCheck(id, today), isNull);
    });

    test('an undo is itself idempotent and offers no further undo', () async {
      final outcome = await check(id, today);
      final first = await outcome.undo!.run('undo-1');
      final second = await outcome.undo!.run('undo-1');
      expect(first.undo, isNull);
      expect(first.replayed, isFalse);
      expect(second.replayed, isTrue);
      expect((await rawCheck(id, today)).rowVersion, 2);
    });

    test(
      'an undo for a habit that was deleted meanwhile is NotFound',
      () async {
        await check(id, today);
        final outcome = await uncheck(id, today);
        await repository.delete(commandId: harness.ids.newId(), id: id);
        await expectLater(
          outcome.undo!.run(harness.ids.newId()),
          throwsA(isA<NotFoundFailure>()),
        );
      },
    );

    test('checks publish commit events, unchecks removal events', () async {
      final events = <AppEvent>[];
      final subscription = harness.events.stream.listen(events.add);
      await check(id, today);
      await uncheck(id, today);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(
        events.whereType<ActivityCommitted>().map((e) => e.commandType),
        contains(HabitRepository.checkType),
      );
      expect(
        events.whereType<ActivityRemoved>().map((e) => e.commandType),
        contains(HabitRepository.uncheckType),
      );
    });
  });

  group('days around DST changes and a zone change (AT25)', () {
    test(
      'checks across 2026-03-29 and 2026-10-25 keep their calendar day',
      () async {
        final id = await createStartedOn(LocalDate(2026, 3, 1));
        harness.clock.setNow(DateTime.utc(2026, 3, 30, 10));
        for (final date in [
          LocalDate(2026, 3, 28),
          LocalDate(2026, 3, 29),
          LocalDate(2026, 3, 30),
        ]) {
          await check(id, date);
        }
        harness.clock.setNow(DateTime.utc(2026, 10, 26, 10));
        final later = await createStartedOn(LocalDate(2026, 9, 1));
        for (final date in [
          LocalDate(2026, 10, 24),
          LocalDate(2026, 10, 25),
          LocalDate(2026, 10, 26),
        ]) {
          await check(later, date);
        }
        expect((await rawChecks(id)).map((c) => c.localDate), [
          LocalDate(2026, 3, 28),
          LocalDate(2026, 3, 29),
          LocalDate(2026, 3, 30),
        ]);
        expect((await rawChecks(later)).map((c) => c.localDate), [
          LocalDate(2026, 10, 24),
          LocalDate(2026, 10, 25),
          LocalDate(2026, 10, 26),
        ]);
      },
    );

    test('the window is calendar based on the 23 and 25 hour days', () async {
      // On 2026-03-30 the day -30 is 2026-02-28 (a DST change lies between).
      final id = await createStartedOn(LocalDate(2026, 1, 1));
      harness.clock.setNow(DateTime.utc(2026, 3, 30, 10));
      await check(id, LocalDate(2026, 2, 28));
      await rejection(check(id, LocalDate(2026, 2, 27)));
      // On 2026-10-26 the day -30 is 2026-09-26.
      harness.clock.setNow(DateTime.utc(2026, 10, 26, 10));
      await check(id, LocalDate(2026, 9, 26));
      await rejection(check(id, LocalDate(2026, 9, 25)));
    });

    test('a zone change never moves an existing check', () async {
      final id = await createStartedOn(LocalDate(2026, 9, 1));
      await check(id, today);
      harness.clock.setTimeZone('America/New_York');
      final row = await rawCheck(id, today);
      expect(row.localDate, today);
      expect(row.timezoneId, 'Europe/Berlin');
      // A new check in the other zone freezes that zone.
      await check(id, today.addDays(-1));
      expect(
        (await rawCheck(id, today.addDays(-1))).timezoneId,
        'America/New_York',
      );
    });

    test(
      'across a month and a year boundary the window and the days are right',
      () async {
        harness.clock.setNow(DateTime.utc(2027, 1, 5, 10));
        final id = await createStartedOn(LocalDate(2026, 11, 1));
        harness.clock.setNow(DateTime.utc(2027, 1, 5, 10));
        await check(id, LocalDate(2026, 12, 31));
        await check(id, LocalDate(2027, 1, 1));
        await check(id, LocalDate(2026, 12, 6));
        await rejection(check(id, LocalDate(2026, 12, 5)));
        expect((await rawChecks(id)).map((c) => c.localDate), [
          LocalDate(2026, 12, 6),
          LocalDate(2026, 12, 31),
          LocalDate(2027, 1, 1),
        ]);
      },
    );
  });

  group('archiving from tomorrow (T02, AT21)', () {
    test(
      'sets the archive date to tomorrow; today the habit still applies',
      () async {
        final id = await create(draft(reminder: const LocalTime(8, 0)));
        final outcome = await repository.archive(
          commandId: harness.ids.newId(),
          id: id,
        );
        expect(outcome.undo, isNull, reason: 'archiving is final');
        final habit = await reload(id);
        expect(habit.archivedFrom, LocalDate(2026, 10, 4));
        expect(habit.appliesOn(today), isTrue);
        expect(habit.isArchivePendingOn(today), isTrue);
        expect(habit.appliesOn(LocalDate(2026, 10, 4)), isFalse);
        expect(habit.rowVersion, 2);
        expect(
          habit.reminderTime,
          const LocalTime(8, 0),
          reason: 'the reminder engine ends it from the archive date',
        );
      },
    );

    test(
      'archived at 23:59 means from the next calendar day, not 24 hours',
      () async {
        final id = await create();
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 21, 59, 50));
        await repository.archive(commandId: harness.ids.newId(), id: id);
        expect((await reload(id)).archivedFrom, LocalDate(2026, 10, 4));
        final other = await create(draft(title: 'Zwei'));
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 0, 10));
        await repository.archive(commandId: harness.ids.newId(), id: other);
        expect((await reload(other)).archivedFrom, LocalDate(2026, 10, 5));
      },
    );

    test(
      'archiving twice keeps the first archive date (never extends the habit)',
      () async {
        final id = await create();
        await repository.archive(commandId: harness.ids.newId(), id: id);
        harness.clock.advance(const Duration(days: 1)); // 2026-10-04
        final second = await repository.archive(
          commandId: harness.ids.newId(),
          id: id,
        );
        expect(second.undo, isNull);
        final habit = await reload(id);
        expect(habit.archivedFrom, LocalDate(2026, 10, 4));
        expect(habit.rowVersion, 2, reason: 'the second call changed nothing');
      },
    );

    test('the same command id is a replay', () async {
      final id = await create();
      await repository.archive(commandId: 'arc', id: id);
      final replay = await repository.archive(commandId: 'arc', id: id);
      expect(replay.replayed, isTrue);
      expect((await reload(id)).rowVersion, 2);
    });

    test('archived habits keep every check and history', () async {
      final id = await createStartedOn(LocalDate(2026, 9, 25));
      await check(id, LocalDate(2026, 9, 26));
      await check(id, today);
      await repository.archive(commandId: harness.ids.newId(), id: id);
      harness.clock.advance(const Duration(days: 2));
      final index = await repository.watchChecks().first;
      expect(index.datesOf(id), {LocalDate(2026, 9, 26), today});
      expect(
        await repository.watchAll().first,
        hasLength(1),
        reason: 'still exists',
      );
    });

    test('no projection day is affected by archiving', () async {
      final id = await create();
      projection.syncs.clear();
      await repository.archive(commandId: harness.ids.newId(), id: id);
      expect(projection.syncs, isEmpty);
    });

    test('archiving a missing or deleted habit is NotFound', () async {
      await expectLater(
        repository.archive(commandId: harness.ids.newId(), id: 'missing'),
        throwsA(isA<NotFoundFailure>()),
      );
      final id = await create();
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await expectLater(
        repository.archive(commandId: harness.ids.newId(), id: id),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('delete and undo', () {
    test(
      'delete is soft: the habit and its history disappear from reads',
      () async {
        final id = await createStartedOn(LocalDate(2026, 9, 20));
        await check(id, today);
        final outcome = await repository.delete(
          commandId: harness.ids.newId(),
          id: id,
        );
        expect(outcome.undo, isNotNull);
        expect(await repository.watchAll().first, isEmpty);
        expect(await repository.findById(id), isNull);
        expect((await rawHabit(id)).deletedAtUtc, isNotNull);
        expect(
          await rawChecks(id),
          hasLength(1),
          reason: 'checks stay in the database',
        );
        expect(
          (await repository.watchChecks().first).count,
          0,
          reason: 'but are ignored',
        );
      },
    );

    test('delete syncs every day with an active check plus today', () async {
      final id = await createStartedOn(LocalDate(2026, 9, 20));
      await check(id, LocalDate(2026, 9, 25));
      await check(id, LocalDate(2026, 9, 26));
      final soft = LocalDate(2026, 9, 27);
      await check(id, soft);
      await uncheck(id, soft); // a soft-deleted check has nothing to take back
      projection.syncs.clear();
      await repository.delete(commandId: harness.ids.newId(), id: id);
      expect(projection.syncs.single, {
        today,
        LocalDate(2026, 9, 25),
        LocalDate(2026, 9, 26),
      });
    });

    test('undoing a delete restores the SAME id with its history', () async {
      final id = await createStartedOn(
        LocalDate(2026, 9, 20),
        draft(title: 'Bleibt', iconKey: 'flame'),
      );
      await check(id, today);
      final outcome = await repository.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      projection.syncs.clear();
      await outcome.undo!.run(harness.ids.newId());
      final habit = await reload(id);
      expect(habit.title, 'Bleibt');
      expect(habit.icon, HabitIcon.flame);
      expect(habit.startedOn, LocalDate(2026, 9, 20));
      expect((await repository.watchChecks().first).datesOf(id), {today});
      expect(projection.syncs.single, {today});
    });

    test('undoing a delete is refused if the row changed meanwhile', () async {
      final id = await create();
      final outcome = await repository.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      await (harness.database.update(harness.database.habits)
            ..where((h) => h.id.equals(id)))
          .write(const HabitsCompanion(rowVersion: Value(50)));
      await expectLater(
        outcome.undo!.run(harness.ids.newId()),
        conflict(ConflictKind.staleVersion),
      );
      expect(await repository.findById(id), isNull);
    });

    test('undoing a create removes that habit', () async {
      final outcome = await repository.create(commandId: 'u1', draft: draft());
      await outcome.undo!.run(harness.ids.newId());
      expect(await repository.watchAll().first, isEmpty);
    });

    test('undoing a create after an edit is refused', () async {
      final created = await repository.create(commandId: 'u1', draft: draft());
      await repository.update(
        commandId: harness.ids.newId(),
        id: created.entityId!,
        draft: draft(title: 'geändert'),
        expectedRowVersion: 1,
      );
      await expectLater(
        created.undo!.run(harness.ids.newId()),
        conflict(ConflictKind.staleVersion),
      );
    });

    test('deleting twice is NotFound', () async {
      final id = await create();
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await expectLater(
        repository.delete(commandId: harness.ids.newId(), id: id),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('atomicity (AT27)', () {
    test(
      'a failing projection stores no check and no receipt, the retry works',
      () async {
        final id = await createStartedOn(LocalDate(2026, 9, 1));
        projection.failure = StateError('disk full');
        await expectLater(
          repository.setChecked(
            commandId: 'fail',
            habitId: id,
            date: today,
            checked: true,
          ),
          throwsA(isA<StorageFailure>()),
        );
        expect(await rawChecks(id), isEmpty);
        expect((await receipts()).where((r) => r.commandId == 'fail'), isEmpty);
        projection.failure = null;
        await repository.setChecked(
          commandId: 'fail',
          habitId: id,
          date: today,
          checked: true,
        );
        expect(await rawChecks(id), hasLength(1));
      },
    );

    test('a failing delete keeps the habit', () async {
      final id = await create();
      projection.failure = StateError('disk full');
      await expectLater(
        repository.delete(commandId: 'fail', id: id),
        throwsA(isA<StorageFailure>()),
      );
      expect(await repository.findById(id), isNotNull);
    });
  });

  group('reads', () {
    test('watchAll lists existing habits oldest first, archived ones too, deleted ones not', () async {
      final a = await create(draft(title: 'A'));
      harness.clock.advance(const Duration(seconds: 1));
      final b = await create(draft(title: 'B'));
      harness.clock.advance(const Duration(seconds: 1));
      final c = await create(draft(title: 'C'));
      await repository.archive(commandId: harness.ids.newId(), id: b);
      await repository.delete(commandId: harness.ids.newId(), id: c);
      final list = await repository.watchAll().first;
      expect(list.map((h) => h.id), [a, b]);
      expect(list.last.archivedFrom, isNotNull);
    });

    test('watchById emits null after deletion and for an unknown id', () async {
      final id = await create();
      final emissions = <Habit?>[];
      final subscription = repository.watchById(id).listen(emissions.add);
      await Future<void>.delayed(Duration.zero);
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(emissions.first, isNotNull);
      expect(emissions.last, isNull);
      expect(await repository.watchById('missing').first, isNull);
    });

    test(
      'watchChecks excludes soft-deleted checks and checks of deleted habits',
      () async {
        final keep = await createStartedOn(
          LocalDate(2026, 9, 1),
          draft(title: 'Bleibt'),
        );
        final gone = await createStartedOn(
          LocalDate(2026, 9, 1),
          draft(title: 'Weg'),
        );
        await check(keep, today);
        await check(keep, today.addDays(-1));
        await uncheck(keep, today.addDays(-1));
        await check(gone, today);
        await repository.delete(commandId: harness.ids.newId(), id: gone);
        final index = await repository.watchChecks().first;
        expect(index.datesOf(keep), {today});
        expect(index.datesOf(gone), isEmpty);
        expect(index.count, 1);
      },
    );

    test('findCheck sees only the active check', () async {
      final id = await createStartedOn(LocalDate(2026, 9, 1));
      expect(await repository.findCheck(id, today), isNull);
      await check(id, today);
      expect(await repository.findCheck(id, today), isNotNull);
      await uncheck(id, today);
      expect(await repository.findCheck(id, today), isNull);
    });
  });
}
