import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/features/nutrition/data/water_repository.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/nutrition_test_kit.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late NutritionKit kit;
  late WaterRepository repository;

  tearDown(() => kit.dispose());

  Future<String> add(int ml, DateTime when, {String? note}) async {
    final outcome = await repository.create(
      commandId: kit.newId(),
      draft: WaterDraft(amountMl: ml, occurredAtUtc: when, note: note),
    );
    return outcome.entityId!;
  }

  Future<void> writeGoal({
    required int target,
    required LocalDate from,
    bool enabled = true,
    String id = 'goal',
  }) => kit.database
      .into(kit.database.goalVersions)
      .insert(
        GoalVersionsCompanion.insert(
          id: id,
          goalType: 'water',
          targetInteger: Value(target),
          enabled: enabled,
          effectiveFromDate: from,
          createdAtUtc: DateTime.utc(2026, 10, 3, 7),
        ),
        mode: InsertMode.insertOrReplace,
      );

  group('today without onboarding data (defaults)', () {
    setUp(() async {
      kit = await NutritionKit.create();
      repository = kit.water;
    });

    test(
      'an empty day: nothing drunk, the default target of 2500 ml',
      () async {
        final today = await repository.loadToday(kitToday);
        expect(today.date, kitToday);
        expect(today.totalMl, 0);
        expect(today.isEmpty, isTrue);
        expect(today.targetMl, 2500);
        expect(today.fraction, 0.0);
        expect(today.percent, 0);
        expect(today.remainingMl, 2500);
        expect(today.goalReached, isFalse);
      },
    );

    test(
      'only the entries of the stored local day count, newest first',
      () async {
        await add(250, at(5));
        await add(300, at(7));
        await add(500, at(6, 30));
        await add(400, DateTime.utc(2026, 10, 2, 12));
        final today = await repository.loadToday(kitToday);
        expect(today.totalMl, 1050);
        expect(today.entriesNewestFirst.map((e) => e.amountMl), [
          300,
          500,
          250,
        ]);
      },
    );

    test('deleted entries do not count', () async {
      final id = await add(250, at(5));
      await add(300, at(7));
      await repository.delete(commandId: kit.newId(), id: id);
      expect((await repository.loadToday(kitToday)).totalMl, 300);
    });

    test(
      'the model follows a changed goal version (no snapshot yet)',
      () async {
        await writeGoal(target: 3000, from: LocalDate(2026, 9, 1));
        expect((await repository.loadToday(kitToday)).targetMl, 3000);
      },
    );

    test(
      'a goal switched off means no target and no progress, the total stays',
      () async {
        await writeGoal(
          target: 2500,
          from: LocalDate(2026, 9, 1),
          enabled: false,
        );
        await add(250, at(5));
        final today = await repository.loadToday(kitToday);
        expect(today.hasTarget, isFalse);
        expect(today.targetMl, isNull);
        expect(today.fraction, isNull);
        expect(today.percent, isNull);
        expect(today.remainingMl, isNull);
        expect(today.goalReached, isFalse);
        expect(today.totalMl, 250, reason: 'drinking is still recorded');
        expect(today.entryCount, 1);
      },
    );

    test('the nutrition module switched off means no target', () async {
      await kit.database
          .into(kit.database.moduleStatusHistory)
          .insert(
            ModuleStatusHistoryCompanion.insert(
              id: 'nutrition-off',
              moduleId: 'nutrition',
              effectiveAtUtc: kit.harness.clock.nowUtc(),
              localDate: kitToday,
              enabled: false,
            ),
          );
      expect((await repository.loadToday(kitToday)).targetMl, isNull);
    });

    test('days before the profile start have no goal', () async {
      // The profile started on kitToday (bootstrap), so the day before has no
      // goal at all.
      await add(250, DateTime.utc(2026, 10, 2, 12));
      final history = await repository.loadHistory(today: kitToday, days: 7);
      expect(history.daysNewestFirst.single.date, LocalDate(2026, 10, 2));
      expect(history.daysNewestFirst.single.targetMl, isNull);
      expect(history.daysNewestFirst.single.goalReached, isFalse);
    });

    test(
      'the target reaches the progress fields: capped bar, real percent',
      () async {
        await add(1500, at(5));
        await add(1300, at(6));
        final today = await repository.loadToday(kitToday);
        expect(today.totalMl, 2800);
        expect(today.fraction, 1.0);
        expect(today.percent, 112);
        expect(today.goalReached, isTrue);
        expect(today.remainingMl, 0);
        expect(today.entryCount, 2, reason: 'no extra record for reaching it');
        expect(await kit.waterRows(), hasLength(2));
      },
    );
  });

  group('history', () {
    setUp(() async {
      kit = await NutritionKit.create(
        realProjection: true,
        onboarded: true,
        startedOn: LocalDate(2026, 9, 1),
      );
      repository = kit.water;
    });

    test(
      'groups the entries per local day, newest day first, with totals',
      () async {
        await add(250, DateTime.utc(2026, 10, 1, 8));
        await add(500, DateTime.utc(2026, 10, 1, 9));
        await add(300, DateTime.utc(2026, 10, 2, 8));
        await add(200, at(6));
        await add(400, at(7));
        final history = await repository.loadHistory(today: kitToday, days: 14);
        expect(history.days, 14);
        expect(history.daysNewestFirst.map((d) => d.date), [
          LocalDate(2026, 10, 3),
          LocalDate(2026, 10, 2),
          LocalDate(2026, 10, 1),
        ]);
        expect(history.daysNewestFirst.map((d) => d.totalMl), [600, 300, 750]);
        expect(
          history.daysNewestFirst.first.entriesNewestFirst.map(
            (e) => e.amountMl,
          ),
          [400, 200],
        );
        expect(
          history.daysNewestFirst.last.entriesNewestFirst.map(
            (e) => e.amountMl,
          ),
          [500, 250],
        );
      },
    );

    test('Berlin day boundary: 22:30Z is the next local day', () async {
      kit.harness.clock.setNow(DateTime.utc(2026, 10, 4, 6));
      await add(100, DateTime.utc(2026, 10, 3, 21, 59)); // 23:59 on the 3rd
      await add(200, DateTime.utc(2026, 10, 3, 22, 0)); // 00:00 on the 4th
      await add(300, DateTime.utc(2026, 10, 3, 22, 30)); // 00:30 on the 4th
      final history = await repository.loadHistory(
        today: LocalDate(2026, 10, 4),
        days: 7,
      );
      expect(history.daysNewestFirst.map((d) => d.date), [
        LocalDate(2026, 10, 4),
        LocalDate(2026, 10, 3),
      ]);
      expect(history.daysNewestFirst.first.totalMl, 500);
      expect(history.daysNewestFirst.last.totalMl, 100);
    });

    test('the window is N local days including today', () async {
      // today = 2026-10-03, 14 days: 2026-09-20 .. 2026-10-03.
      await add(100, DateTime.utc(2026, 9, 20, 10));
      await add(200, DateTime.utc(2026, 9, 19, 10));
      final history = await repository.loadHistory(today: kitToday, days: 14);
      expect(history.daysNewestFirst.map((d) => d.date), [
        LocalDate(2026, 9, 20),
      ]);
      final longer = await repository.loadHistory(today: kitToday, days: 15);
      expect(longer.daysNewestFirst.map((d) => d.date), [
        LocalDate(2026, 9, 20),
        LocalDate(2026, 9, 19),
      ]);
      expect(
        (await repository.loadHistory(today: kitToday, days: 1)).isEmpty,
        isTrue,
      );
    });

    test(
      'days without an entry do not appear, deleted entries do not count',
      () async {
        final id = await add(250, DateTime.utc(2026, 10, 1, 8));
        await add(300, DateTime.utc(2026, 10, 2, 8));
        await repository.delete(commandId: kit.newId(), id: id);
        final history = await repository.loadHistory(today: kitToday, days: 14);
        expect(history.daysNewestFirst.map((d) => d.date), [
          LocalDate(2026, 10, 2),
        ]);
      },
    );

    test('every day shows its own frozen threshold and goal flag', () async {
      // Oct 2 reached 2600 of 2500 and gets its snapshot with the command.
      kit.harness.clock.setNow(DateTime.utc(2026, 10, 2, 20));
      await add(1300, DateTime.utc(2026, 10, 2, 8));
      await add(1300, DateTime.utc(2026, 10, 2, 9));
      // A new goal applies from Oct 3 on.
      await writeGoal(target: 3000, from: LocalDate(2026, 10, 3));
      kit.harness.clock.setNow(DateTime.utc(2026, 10, 3, 20));
      await add(1300, DateTime.utc(2026, 10, 3, 8));
      await add(1300, DateTime.utc(2026, 10, 3, 9));
      final history = await repository.loadHistory(today: kitToday, days: 7);
      final today = history.daysNewestFirst.first;
      final yesterday = history.daysNewestFirst.last;
      expect(yesterday.targetMl, 2500);
      expect(yesterday.goalReached, isTrue);
      expect(today.targetMl, 3000);
      expect(today.goalReached, isFalse, reason: '2600 of 3000');
    });

    test('an entry stored with a later local date than today stays reachable', () async {
      // Created in Berlin at 00:30 on the 4th, then the device moves west: the
      // local date of the new zone is still the 3rd.
      kit.harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 45));
      await add(250, DateTime.utc(2026, 10, 3, 22, 30));
      kit.harness.clock.setTimeZone('America/Los_Angeles');
      final today = kit.harness.clock.today();
      expect(today, LocalDate(2026, 10, 3));
      final history = await repository.loadHistory(today: today, days: 7);
      expect(history.daysNewestFirst.single.date, LocalDate(2026, 10, 4));
      expect(
        (await repository.loadToday(today)).totalMl,
        0,
        reason: 'today only shows entries of its own stored date',
      );
    });

    test('a window shorter than one day is a programming error', () {
      expect(
        () => repository.loadHistory(today: kitToday, days: 0),
        throwsArgumentError,
      );
    });
  });

  group('reactive models', () {
    setUp(() async {
      kit = await NutritionKit.create(realProjection: true, onboarded: true);
      repository = kit.water;
    });

    test('watchToday follows quick adds, edits, deletes and undo', () async {
      final models = <WaterToday>[];
      final subscription = repository.watchToday(kitToday).listen(models.add);
      await pumpUntil(() => models.isNotEmpty, reason: 'initial model');
      expect(models.last.totalMl, 0);

      final outcome = await repository.quickAdd(commandId: 'a', amountMl: 250);
      await pumpUntil(() => models.last.totalMl == 250, reason: 'after add');
      expect(models.last.entryCount, 1);

      await repository.update(
        commandId: kit.newId(),
        id: outcome.entityId!,
        draft: WaterDraft(amountMl: 400, occurredAtUtc: at(8)),
        expectedRowVersion: 1,
      );
      await pumpUntil(() => models.last.totalMl == 400, reason: 'after edit');

      final deleted = await repository.delete(
        commandId: kit.newId(),
        id: outcome.entityId!,
      );
      await pumpUntil(() => models.last.totalMl == 0, reason: 'after delete');

      await deleted.undo!.run(kit.newId());
      await pumpUntil(() => models.last.totalMl == 400, reason: 'after undo');
      await subscription.cancel();
    });

    test('watchToday follows a goal change that applies today', () async {
      final models = <WaterToday>[];
      final subscription = repository.watchToday(kitToday).listen(models.add);
      await pumpUntil(() => models.isNotEmpty, reason: 'initial model');
      expect(models.last.targetMl, 2500);
      await kit.database.delete(kit.database.goalVersions).go();
      await writeGoal(target: 3500, from: kitStart);
      await pumpUntil(() => models.last.targetMl == 3500, reason: 'new target');
      await subscription.cancel();
    });

    test('equal consecutive models are not emitted again', () async {
      final models = <WaterToday>[];
      final subscription = repository.watchToday(kitToday).listen(models.add);
      await pumpUntil(() => models.isNotEmpty, reason: 'initial model');
      final count = models.length;
      // An unrelated change of a watched table must not re-emit an equal model.
      await (kit.database.update(kit.database.profile))
          .write(const ProfileCompanion(displayName: Value('Test')));
      await pumpTurns();
      expect(models, hasLength(count));
      await subscription.cancel();
    });

    test('watchHistory follows new entries', () async {
      final histories = <WaterHistory>[];
      final subscription = repository
          .watchHistory(today: kitToday, days: 14)
          .listen(histories.add);
      await pumpUntil(() => histories.isNotEmpty, reason: 'initial history');
      expect(histories.last.isEmpty, isTrue);
      await repository.quickAdd(commandId: 'a', amountMl: 250);
      await pumpUntil(() => !histories.last.isEmpty, reason: 'after add');
      expect(histories.last.daysNewestFirst.single.totalMl, 250);
      await subscription.cancel();
    });
  });
}
