import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/commands/command_context.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/testing/test_database.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Projection that records calls and can be told to fail.
final class _RecordingProjection implements ProjectionSynchronizer {
  final List<Set<LocalDate>> syncs = [];
  Object? failure;
  int xp = 0;

  @override
  Future<void> syncDays(Set<LocalDate> days) async {
    syncs.add(days);
    if (failure != null) {
      throw failure!;
    }
    xp += 5;
  }

  @override
  Future<int> totalXp() async => xp;
}

void main() {
  setUpAll(TimeZones.ensureInitialized);

  late AppDatabase db;
  late FakeClock clock;
  late _RecordingProjection projection;
  late CommandEvents events;
  late CommandRunner runner;
  late List<AppEvent> published;
  late StreamSubscription<AppEvent> subscription;
  var gamificationOn = true;

  setUp(() {
    db = createTestDatabase();
    clock = FakeClock.at('2026-10-03T08:00:00Z');
    projection = _RecordingProjection();
    events = CommandEvents();
    published = [];
    subscription = events.stream.listen(published.add);
    gamificationOn = true;
    runner = CommandRunner(
      database: db,
      clock: clock,
      ids: SequentialIdGenerator(),
      projections: projection,
      events: events,
      gamificationEnabled: () async => gamificationOn,
    );
  });

  tearDown(() async {
    await subscription.cancel();
    await events.dispose();
    await db.close();
  });

  Future<void> insertWater(String id, int ml, DateTime now) {
    return db
        .into(db.waterEntries)
        .insert(
          WaterEntriesCompanion.insert(
            id: id,
            amountMl: ml,
            occurredAtUtc: now,
            localDate: LocalDate(2026, 10, 3),
            timezoneId: 'Europe/Berlin',
            gamificationEligible: true,
            createdAtUtc: now,
            updatedAtUtc: now,
          ),
        );
  }

  Future<int> waterCount() async =>
      (await db.select(db.waterEntries).get()).length;

  Future<int> receiptCount() async =>
      (await db.select(db.commandReceipts).get()).length;

  test('commits mutation, projection and receipt together', () async {
    final outcome = await runner.run(
      commandId: 'cmd-1',
      type: 'water.add',
      body: (ctx) async {
        await insertWater('w1', 250, ctx.nowUtc);
        return CommandEffect(
          entityId: 'w1',
          affectedDays: {LocalDate(2026, 10, 3)},
        );
      },
    );

    expect(outcome.entityId, 'w1');
    expect(outcome.replayed, isFalse);
    expect(await waterCount(), 1);
    expect(await receiptCount(), 1);
    expect(projection.syncs, [
      {LocalDate(2026, 10, 3)},
    ]);
    final receipt = await db.select(db.commandReceipts).getSingle();
    expect(receipt.commandId, 'cmd-1');
    expect(receipt.commandType, 'water.add');
    expect(receipt.resultEntityId, 'w1');
    expect(receipt.committedAtUtc, DateTime.utc(2026, 10, 3, 8));
  });

  test(
    'replaying the same command id performs exactly one effect (AT12)',
    () async {
      var executions = 0;
      Future<CommandOutcome> submit(String id) => runner.run(
        commandId: id,
        type: 'water.add',
        body: (ctx) async {
          executions++;
          await insertWater('w-$executions', 250, ctx.nowUtc);
          return CommandEffect(
            entityId: 'w-$executions',
            affectedDays: {LocalDate(2026, 10, 3)},
          );
        },
      );

      final first = await submit('same');
      final second = await submit('same');
      final third = await submit('same');

      expect(executions, 1);
      expect(await waterCount(), 1);
      expect(second.replayed, isTrue);
      expect(third.replayed, isTrue);
      expect(second.entityId, first.entityId);
      expect(second.undo, isNull, reason: 'a replay offers no new undo');
      expect(projection.syncs, hasLength(1));
      expect(published.whereType<ActivityCommitted>(), hasLength(1));
    },
  );

  test('a new command id is a new input', () async {
    var n = 0;
    Future<CommandOutcome> submit(String id) => runner.run(
      commandId: id,
      type: 'water.add',
      body: (ctx) async {
        n++;
        await insertWater('w-$n', 250, ctx.nowUtc);
        return CommandEffect(entityId: 'w-$n');
      },
    );
    await submit('a');
    await submit('b');
    expect(await waterCount(), 2);
    expect(await receiptCount(), 2);
  });

  test(
    'a validation failure rolls back and a retry with the same id works',
    () async {
      var attempt = 0;
      Future<CommandOutcome> submit() => runner.run(
        commandId: 'retry-me',
        type: 'water.add',
        body: (ctx) async {
          attempt++;
          await insertWater('w1', 250, ctx.nowUtc);
          if (attempt == 1) {
            throw ValidationFailure.field('amount', 'Zu klein');
          }
          return CommandEffect(entityId: 'w1');
        },
      );

      await expectLater(submit(), throwsA(isA<ValidationFailure>()));
      expect(await waterCount(), 0, reason: 'mutation must be rolled back');
      expect(
        await receiptCount(),
        0,
        reason: 'no receipt for a failed command',
      );
      expect(published, isEmpty);

      final outcome = await submit();
      expect(outcome.replayed, isFalse);
      expect(await waterCount(), 1);
      expect(await receiptCount(), 1);
    },
  );

  test('database write errors roll everything back and become StorageFailure (AT27)', () async {
    await expectLater(
      runner.run(
        commandId: 'bad-write',
        type: 'water.add',
        body: (ctx) async {
          await insertWater('w1', 250, ctx.nowUtc);
          // Violates the CHECK constraint (amount_ml BETWEEN 50 AND 2000).
          await insertWater('w2', 10, ctx.nowUtc);
          return CommandEffect(
            entityId: 'w1',
            affectedDays: {LocalDate(2026, 10, 3)},
          );
        },
      ),
      throwsA(
        isA<StorageFailure>().having(
          (f) => f.causeType,
          'causeType',
          isNotNull,
        ),
      ),
    );
    expect(await waterCount(), 0);
    expect(await receiptCount(), 0);
    expect(projection.xp, 0);
    expect(published, isEmpty);
  });

  test('a failing projection rolls back the fact and the receipt', () async {
    projection.failure = StateError('projection broke');
    await expectLater(
      runner.run(
        commandId: 'proj-fail',
        type: 'water.add',
        body: (ctx) async {
          await insertWater('w1', 250, ctx.nowUtc);
          return CommandEffect(
            entityId: 'w1',
            affectedDays: {LocalDate(2026, 10, 3)},
          );
        },
      ),
      throwsA(isA<StorageFailure>()),
    );
    expect(await waterCount(), 0);
    expect(await receiptCount(), 0);
  });

  test('events are published after commit with xp before and after', () async {
    await runner.run(
      commandId: 'e1',
      type: 'water.add',
      body: (ctx) async {
        await insertWater('w1', 250, ctx.nowUtc);
        return CommandEffect(
          entityId: 'w1',
          affectedDays: {LocalDate(2026, 10, 3)},
          extraEvents: const [GoalsChanged()],
        );
      },
    );
    await Future<void>.delayed(Duration.zero);
    final committed = published.whereType<ActivityCommitted>().single;
    expect(committed.commandType, 'water.add');
    expect(committed.entityId, 'w1');
    expect(committed.xpBefore, 0);
    expect(committed.xpAfter, 5);
    expect(published.whereType<GoalsChanged>(), hasLength(1));

    await runner.run(
      commandId: 'e2',
      type: 'water.delete',
      body: (ctx) async =>
          const CommandEffect(entityId: 'w1', kind: EffectKind.removed),
    );
    await Future<void>.delayed(Duration.zero);
    expect(published.whereType<ActivityRemoved>(), hasLength(1));
  });

  test('no projection sync when no days are affected', () async {
    await runner.run(
      commandId: 'p1',
      type: 'settings.change',
      body: (ctx) async => const CommandEffect(),
    );
    expect(projection.syncs, isEmpty);
  });

  test(
    'context freezes one instant and the zone for the whole command',
    () async {
      late DateTime first;
      late DateTime second;
      late FrozenInstant frozen;
      await runner.run(
        commandId: 'ctx',
        type: 'x',
        body: (ctx) async {
          first = ctx.nowUtc;
          clock.advance(const Duration(hours: 5));
          second = ctx.nowUtc;
          frozen = ctx.frozenNow;
          return const CommandEffect();
        },
      );
      expect(first, second);
      expect(frozen.utc, DateTime.utc(2026, 10, 3, 8));
      expect(frozen.localDate, LocalDate(2026, 10, 3));
      expect(frozen.timezoneId, 'Europe/Berlin');
    },
  );

  test('context freezes the business date in the zone of the event', () async {
    clock.setNow(DateTime.utc(2026, 10, 3, 22, 30));
    late FrozenInstant frozen;
    await runner.run(
      commandId: 'late',
      type: 'x',
      body: (ctx) async {
        frozen = ctx.frozenNow;
        return const CommandEffect();
      },
    );
    // 22:30 UTC is already the next day in Berlin (CEST).
    expect(frozen.localDate, LocalDate(2026, 10, 4));
    clock.setTimeZone('America/New_York');
    expect(frozen.localDate, LocalDate(2026, 10, 4), reason: 'frozen');
  });

  test('gamification eligibility is read inside the command', () async {
    final seen = <bool>[];
    Future<void> submit(String id) => runner.run(
      commandId: id,
      type: 'x',
      body: (ctx) async {
        seen.add(await ctx.isGamificationEnabled());
        return const CommandEffect();
      },
    );
    await submit('g1');
    gamificationOn = false;
    await submit('g2');
    expect(seen, [true, false]);
  });

  test('undo actions run as a new command and can fail on conflict', () async {
    final first = await runner.run(
      commandId: 'create',
      type: 'water.add',
      body: (ctx) async {
        await insertWater('w1', 250, ctx.nowUtc);
        return CommandEffect(
          entityId: 'w1',
          undo: UndoAction(
            run: (undoId) => runner.run(
              commandId: undoId,
              type: 'water.undo',
              body: (ctx) async {
                final row = await (db.select(
                  db.waterEntries,
                )..where((r) => r.id.equals('w1'))).getSingle();
                if (row.rowVersion != 1) {
                  throw const ConflictFailure(ConflictKind.staleVersion);
                }
                await (db.update(
                  db.waterEntries,
                )..where((r) => r.id.equals('w1'))).write(
                  WaterEntriesCompanion(deletedAtUtc: Value(ctx.nowUtc)),
                );
                return const CommandEffect(
                  entityId: 'w1',
                  kind: EffectKind.removed,
                );
              },
            ),
          ),
        );
      },
    );
    expect(first.undo, isNotNull);

    // The record is edited meanwhile -> undo must refuse.
    await (db.update(db.waterEntries)..where((r) => r.id.equals('w1'))).write(
      const WaterEntriesCompanion(rowVersion: Value(2)),
    );
    await expectLater(
      first.undo!.run('undo-1'),
      throwsA(
        isA<ConflictFailure>().having(
          (f) => f.kind,
          'kind',
          ConflictKind.staleVersion,
        ),
      ),
    );
    final row = await db.select(db.waterEntries).getSingle();
    expect(
      row.deletedAtUtc,
      isNull,
      reason: 'conflicting undo changes nothing',
    );

    // Unchanged record: undo works, and is itself idempotent.
    await (db.update(db.waterEntries)..where((r) => r.id.equals('w1'))).write(
      const WaterEntriesCompanion(rowVersion: Value(1)),
    );
    final undone = await first.undo!.run('undo-2');
    expect(undone.replayed, isFalse);
    expect(
      (await db.select(db.waterEntries).getSingle()).deletedAtUtc,
      isNotNull,
    );
    final again = await first.undo!.run('undo-2');
    expect(again.replayed, isTrue);
  });
}
