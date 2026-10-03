import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/day_facts_source.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_manager.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/application/focus_restorer.dart';
import 'package:self_improvement/features/focus/data/focus_repository.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/manual_tick_source.dart';

/// Acceptance flows AT12, AT16-AT19, AT23, AT25 and AT26 for the focus timer
/// with the REAL projection (XP and goal snapshots) and a simulated process
/// restart (a fresh provider container on the same database).
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late ProviderContainer container;
  late ManualTickSource ticker;

  final today = LocalDate(2026, 10, 3);

  ProviderContainer newContainer() => harness.createContainer(
    overrides: [focusTickSourceProvider.overrideWithValue(ticker)],
  );

  setUp(() async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    ticker = ManualTickSource();
    container = newContainer();
  });
  tearDown(() => harness.dispose());

  FocusRepository repoOf(ProviderContainer c) =>
      c.read(focusRepositoryProvider);

  void advance(int seconds) =>
      harness.clock.advance(Duration(seconds: seconds));

  Future<String> start({int planned = 1500, ProviderContainer? from}) async {
    final outcome = await repoOf(from ?? container).start(
      commandId: harness.ids.newId(),
      category: FocusCategory.learning,
      plannedSeconds: planned,
    );
    return outcome.entityId!;
  }

  Future<void> save(String id, {ProviderContainer? from}) =>
      repoOf(from ?? container).save(commandId: harness.ids.newId(), id: id);

  /// Starts a session, lets [seconds] pass and saves it.
  Future<String> completed(int seconds, {int planned = 1500}) async {
    final id = await start(planned: planned);
    advance(seconds);
    await save(id);
    advance(1);
    return id;
  }

  Future<FocusSessionRow> rowOf(String id) => (harness.database.select(
    harness.database.focusSessions,
  )..where((f) => f.id.equals(id))).getSingle();

  Future<List<XpAwardRow>> awards() =>
      harness.database.select(harness.database.xpAwards).get();

  Future<int> focusSecondsOn(LocalDate day) async =>
      (await DayFactsSource(harness.database).factsFor(day))
          .focusCompletedSeconds;

  List<AppEvent> collectEvents() {
    final events = <AppEvent>[];
    final subscription = harness.events.stream.listen(events.add);
    addTearDown(subscription.cancel);
    return events;
  }

  group('AT16: start, pause, resume and a process restart', () {
    test('the persisted values are right at every step', () async {
      final id = await start();
      var row = await rowOf(id);
      expect(
        [row.status, row.accumulatedSeconds, row.plannedSeconds],
        ['running', 0, 1500],
      );
      expect(row.segmentStartedAtUtc, DateTime.utc(2026, 10, 3, 8));

      advance(600);
      await repoOf(container).pause(commandId: harness.ids.newId(), id: id);
      row = await rowOf(id);
      expect([row.status, row.accumulatedSeconds], ['paused', 600]);
      expect(row.segmentStartedAtUtc, isNull);

      advance(300);
      await repoOf(container).resume(commandId: harness.ids.newId(), id: id);
      row = await rowOf(id);
      expect([row.status, row.accumulatedSeconds], ['running', 600]);
      expect(row.segmentStartedAtUtc, DateTime.utc(2026, 10, 3, 8, 15));
      expect(row.rowVersion, 3);
    });

    test(
      'a restart restores the remaining time from the UTC segments',
      () async {
        final id = await start();
        advance(600);
        await repoOf(container).pause(commandId: harness.ids.newId(), id: id);
        advance(300);
        await repoOf(container).resume(commandId: harness.ids.newId(), id: id);
        final versionBefore = (await rowOf(id)).rowVersion;

        container.dispose(); // the process dies
        advance(400); // the app stays closed

        final restarted = newContainer();
        final result = await restarted.read(focusRestorerProvider).restore();
        expect(result.outcome, FocusRestoreOutcome.unchanged);
        expect(result.session!.id, id);
        expect(result.elapsed!.elapsedSeconds, 1000, reason: '600 + 400');
        expect(result.elapsed!.remainingSeconds, 500);
        expect(
          (await rowOf(id)).rowVersion,
          versionBefore,
          reason: 'restoring a running session writes nothing',
        );

        restarted.listen(focusCountdownProvider, (_, _) {});

        final countdown = await restarted.read(focusCountdownProvider.future);
        expect(countdown!.remainingSeconds, 500);
        expect(countdown.isRunning, isTrue);
      },
    );

    test('a paused session survives a restart untouched, however long it is closed', () async {
      final id = await start();
      advance(200);
      await repoOf(container).pause(commandId: harness.ids.newId(), id: id);
      container.dispose();
      advance(3 * 86400);
      final restarted = newContainer();
      final result = await restarted.read(focusRestorerProvider).restore();
      expect(result.outcome, FocusRestoreOutcome.unchanged);
      expect(result.session!.status, FocusStatus.paused);
      expect(result.elapsed!.elapsedSeconds, 200);
      restarted.listen(focusCountdownProvider, (_, _) {});
      final countdown = await restarted.read(focusCountdownProvider.future);
      expect(countdown!.remainingSeconds, 1300);
      expect(countdown.isPaused, isTrue);
    });

    test('without an open session there is nothing to restore', () async {
      final result = await container.read(focusRestorerProvider).restore();
      expect(result.outcome, FocusRestoreOutcome.noOpenSession);
      expect(result.session, isNull);
    });
  });

  group('AT17: the process is gone past the end time', () {
    test('awaiting confirmation: no XP, no completed record; saving twice gives one completion', () async {
      final id = await start(planned: 1500);
      container.dispose(); // process death
      advance(2 * 3600); // far past the planned end

      final events = collectEvents();
      final restarted = newContainer();
      final result = await restarted.read(focusRestorerProvider).restore();
      expect(result.outcome, FocusRestoreOutcome.movedToAwaitingConfirmation);
      expect(result.session!.status, FocusStatus.awaitingConfirmation);

      final row = await rowOf(id);
      expect(row.status, 'awaiting_confirmation');
      expect(row.accumulatedSeconds, 1500, reason: 'never above the plan');
      expect(row.segmentStartedAtUtc, isNull);
      expect(row.completedLocalDate, isNull, reason: 'no completed record');
      expect(row.endedAtUtc, isNull);
      expect(await harness.totalXp(), 0, reason: 'no automatic XP');
      expect(await awards(), isEmpty);
      expect(await focusSecondsOn(today), 0, reason: 'no automatic focus time');
      await settle();
      expect(events.whereType<FocusStateChanged>(), hasLength(1));

      // Restoring again changes nothing (idempotent).
      final again = await restarted.read(focusRestorerProvider).restore();
      expect(again.outcome, FocusRestoreOutcome.unchanged);
      expect((await rowOf(id)).rowVersion, row.rowVersion);

      // The user confirms: exactly one completion, whichever way it is repeated.
      final repository = repoOf(restarted);
      await repository.save(commandId: 'save-1', id: id);
      await repository.save(commandId: 'save-1', id: id);
      await repository.save(commandId: 'save-2', id: id);
      final saved = await rowOf(id);
      expect(saved.status, 'completed');
      expect(saved.accumulatedSeconds, 1500);
      expect(saved.completedLocalDate, LocalDate(2026, 10, 3));
      expect(await focusSecondsOn(today), 1500);
      expect(await harness.totalXp(), 10);
      expect((await awards()).single.awardKey, 'focus:$id');
      expect(
        await harness.database.select(harness.database.focusSessions).get(),
        hasLength(1),
      );
    });

    test(
      'the end exactly now is already over, one second before it is not',
      () async {
        final id = await start(planned: 600);
        advance(599);
        final early = await container.read(focusRestorerProvider).restore();
        expect(early.outcome, FocusRestoreOutcome.unchanged);
        expect(early.elapsed!.remainingSeconds, 1);
        advance(1);
        final over = await container.read(focusRestorerProvider).restore();
        expect(over.outcome, FocusRestoreOutcome.movedToAwaitingConfirmation);
        expect((await rowOf(id)).status, 'awaiting_confirmation');
      },
    );

    test(
      'an awaiting session survives further restarts and still earns nothing',
      () async {
        final id = await start();
        advance(5000);
        await container.read(focusRestorerProvider).restore();
        container.dispose();
        advance(86400);
        final restarted = newContainer();
        final result = await restarted.read(focusRestorerProvider).restore();
        expect(result.outcome, FocusRestoreOutcome.unchanged);
        expect(result.session!.status, FocusStatus.awaitingConfirmation);
        expect(await harness.totalXp(), 0);
        expect((await rowOf(id)).completedLocalDate, isNull);
      },
    );
  });

  group('AT18: below five minutes, discard and the XP threshold', () {
    test(
      '299 seconds are saved but earn no XP, 300 seconds earn 10 XP',
      () async {
        await completed(299);
        expect(await focusSecondsOn(today), 299, reason: 'the time is saved');
        expect(await harness.totalXp(), 0);
        expect(await awards(), isEmpty);

        final second = await completed(300);
        expect(await focusSecondsOn(today), 599);
        expect(await harness.totalXp(), 10);
        expect((await awards()).single.awardKey, 'focus:$second');
      },
    );

    test(
      'one second is the shortest saved session and earns nothing',
      () async {
        final id = await start();
        advance(1);
        await save(id);
        expect(await focusSecondsOn(today), 1);
        expect(await harness.totalXp(), 0);
      },
    );

    test('finishing early at five minutes earns XP, the time saved is what was run', () async {
      final id = await completed(300, planned: 3600);
      expect((await rowOf(id)).accumulatedSeconds, 300);
      expect(await harness.totalXp(), 10);
    });

    test(
      'discarding leaves no completed time and no XP from any open state',
      () async {
        final repository = repoOf(container);
        final running = await start();
        advance(900);
        await repository.discard(commandId: harness.ids.newId(), id: running);

        final paused = await start();
        advance(900);
        await repository.pause(commandId: harness.ids.newId(), id: paused);
        await repository.discard(commandId: harness.ids.newId(), id: paused);

        final awaiting = await start(planned: 300);
        advance(400);
        await repository.markAwaitingConfirmation(
          commandId: harness.ids.newId(),
          id: awaiting,
        );
        await repository.discard(commandId: harness.ids.newId(), id: awaiting);

        expect(await focusSecondsOn(today), 0);
        expect(await harness.totalXp(), 0);
        expect(await awards(), isEmpty);
        expect(await repository.watchHistory().first, isEmpty);
        for (final id in [running, paused, awaiting]) {
          final row = await rowOf(id);
          expect(row.status, 'discarded');
          expect(row.completedLocalDate, isNull);
        }
      },
    );

    test('open sessions earn nothing in any state', () async {
      final id = await start(planned: 600);
      expect(await harness.totalXp(), 0);
      advance(300);
      await repoOf(container).pause(commandId: harness.ids.newId(), id: id);
      expect(await harness.totalXp(), 0);
      await repoOf(container).resume(commandId: harness.ids.newId(), id: id);
      advance(600);
      await repoOf(container)
          .markAwaitingConfirmation(commandId: harness.ids.newId(), id: id);
      expect(await harness.totalXp(), 0);
      expect(await focusSecondsOn(today), 0);
    });
  });

  group('XP limits and the day ring', () {
    test(
      'at most four qualifying sessions earn XP per day, the next one moves up',
      () async {
        final ids = <String>[];
        for (var i = 0; i < 5; i++) {
          ids.add(await completed(300));
        }
        expect(await harness.totalXp(), 40, reason: 'four times 10 XP');
        expect(await awards(), hasLength(4));
        await repoOf(container)
            .delete(commandId: harness.ids.newId(), id: ids.first);
        expect(await harness.totalXp(), 40, reason: 'the fifth moved up');
        expect(
          (await awards()).map((a) => a.awardKey),
          isNot(contains('focus:${ids.first}')),
        );
      },
    );

    test('the focus goal of the day ring uses completed time only (25 minutes default)', () async {
      final status = harness.dayStatusRepository();
      Future<bool> fulfilled() async =>
          (await status.statusFor(today))!.goals
              .singleWhere((g) => g.goalKey == 'focus_minutes')
              .fulfilled;
      await completed(1499);
      expect(await fulfilled(), isFalse, reason: '24:59 is below 25 minutes');
      final id = await start();
      advance(1);
      expect(
        await fulfilled(),
        isFalse,
        reason: 'a running session counts nothing',
      );
      await save(id);
      expect(await fulfilled(), isTrue, reason: '1499 + 1 = 25:00');
    });
  });

  group('AT19: the module guard', () {
    late ModuleManager manager;

    setUp(() {
      manager = ModuleManager(
        database: harness.database,
        runner: harness.runner,
        status: harness.moduleStatus,
      );
    });

    Future<void> deactivate() => manager
        .setEnabled(
          commandId: harness.ids.newId(),
          module: ModuleId.focus,
          enabled: false,
        )
        .then((_) {});

    Matcher blocked() => throwsA(
      isA<ConflictFailure>().having(
        (f) => f.kind,
        'kind',
        ConflictKind.openFocusSession,
      ),
    );

    test(
      'every open state blocks the deactivation and nothing is deleted',
      () async {
        final repository = repoOf(container);
        final id = await start();
        await expectLater(deactivate(), blocked());

        advance(100);
        await repository.pause(commandId: harness.ids.newId(), id: id);
        await expectLater(deactivate(), blocked());

        await repository.discard(commandId: harness.ids.newId(), id: id);
        final awaiting = await start(planned: 300);
        advance(400);
        await repository.markAwaitingConfirmation(
          commandId: harness.ids.newId(),
          id: awaiting,
        );
        await expectLater(deactivate(), blocked());

        expect(await harness.moduleStatus.isEnabled(ModuleId.focus), isTrue);
        expect(
          await harness.database.select(harness.database.focusSessions).get(),
          hasLength(2),
          reason: 'no session is deleted',
        );
      },
    );

    test(
      'saving resolves it: the module can be deactivated, the data stays',
      () async {
        final id = await start();
        advance(600);
        await expectLater(deactivate(), blocked());
        await save(id);
        await deactivate();
        expect(await harness.moduleStatus.isEnabled(ModuleId.focus), isFalse);
        final row = await rowOf(id);
        expect(row.status, 'completed');
        expect(row.accumulatedSeconds, 600);
        expect(await harness.totalXp(), 10, reason: 'valid XP stays');
      },
    );

    test('discarding resolves it as well', () async {
      final id = await start();
      advance(10);
      await repoOf(container).discard(commandId: harness.ids.newId(), id: id);
      await deactivate();
      expect(await harness.moduleStatus.isEnabled(ModuleId.focus), isFalse);
      expect(
        await harness.database.select(harness.database.focusSessions).get(),
        hasLength(1),
      );
    });

    test('an open session after a restart still blocks it', () async {
      await start();
      container.dispose();
      advance(60);
      final restarted = newContainer();
      await restarted.read(focusRestorerProvider).restore();
      await expectLater(deactivate(), blocked());
    });
  });

  group('AT12: idempotent commands with the real projection', () {
    test(
      'a replayed save never awards twice, a replayed start never starts twice',
      () async {
        final repository = repoOf(container);
        final started = await repository.start(
          commandId: 's1',
          category: FocusCategory.reading,
          plannedSeconds: 600,
        );
        await repository.start(
          commandId: 's1',
          category: FocusCategory.reading,
          plannedSeconds: 600,
        );
        advance(400);
        await repository.save(commandId: 'x1', id: started.entityId!);
        await repository.save(commandId: 'x1', id: started.entityId!);
        expect(await harness.totalXp(), 10);
        expect(
          await harness.database.select(harness.database.focusSessions).get(),
          hasLength(1),
        );
      },
    );
  });

  group('AT23 and AT25: corrections and dates', () {
    test(
      'deleting a past session changes the day ring and XP, undo restores both',
      () async {
        harness.clock.setNow(DateTime.utc(2026, 10, 2, 8));
        final id = await completed(1800, planned: 3600);
        final yesterday = LocalDate(2026, 10, 2);
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 8));
        final status = harness.dayStatusRepository();
        Future<bool> fulfilled() async =>
            (await status.statusFor(yesterday))!.goals
                .singleWhere((g) => g.goalKey == 'focus_minutes')
                .fulfilled;
        expect(await fulfilled(), isTrue);
        expect(await harness.totalXp(), 10);

        final deleted = await repoOf(container)
            .delete(commandId: harness.ids.newId(), id: id);
        expect(await fulfilled(), isFalse);
        expect(await harness.totalXp(), 0);
        expect(await focusSecondsOn(yesterday), 0);

        await deleted.undo!.run(harness.ids.newId());
        expect(await fulfilled(), isTrue);
        expect(await harness.totalXp(), 10);
        expect(await focusSecondsOn(yesterday), 1800);
      },
    );

    test(
      'undoing a save takes the XP back and the session is open again',
      () async {
        final id = await start(planned: 3600);
        advance(900);
        final saved = await repoOf(container)
            .save(commandId: harness.ids.newId(), id: id);
        expect(await harness.totalXp(), 10);
        await saved.undo!.run(harness.ids.newId());
        expect(await harness.totalXp(), 0);
        expect(await focusSecondsOn(today), 0);
        expect((await repoOf(container).findOpen())!.id, id);
      },
    );

    test(
      'a session over midnight counts on the confirmation day with its XP',
      () async {
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 21, 50));
        final id = await start(planned: 3600);
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 10));
        await save(id);
        final tomorrow = LocalDate(2026, 10, 4);
        expect(await focusSecondsOn(today), 0);
        expect(await focusSecondsOn(tomorrow), 1200, reason: 'not split');
        final award = (await awards()).single;
        expect(award.awardKey, 'focus:$id');
        expect(award.localDate, tomorrow);
      },
    );

    test('a later time zone change moves nothing', () async {
      final id = await completed(600);
      harness.clock.setTimeZone('Pacific/Auckland');
      harness.clock.advance(const Duration(days: 1));
      expect((await rowOf(id)).completedLocalDate, today);
      expect(await focusSecondsOn(today), 600);
    });
  });

  group('AT26: gamification switched off', () {
    Future<void> setGamification(bool enabled) => harness.database
        .into(harness.database.moduleStatusHistory)
        .insert(
          ModuleStatusHistoryCompanion.insert(
            id: harness.ids.newId(),
            moduleId: ModuleId.gamification.key,
            effectiveAtUtc: harness.clock.nowUtc(),
            localDate: harness.clock.today(),
            enabled: enabled,
          ),
        );

    test(
      'a session saved while it is off earns nothing, not even later',
      () async {
        await setGamification(false);
        advance(1);
        await completed(600);
        expect(await harness.totalXp(), 0);
        expect(await focusSecondsOn(today), 600, reason: 'the time is saved');
        advance(1);
        await setGamification(true);
        await harness.projections.syncDays({today});
        expect(await harness.totalXp(), 0, reason: 'no back-payment');
      },
    );

    test('XP earned before stays when it is switched off afterwards', () async {
      await completed(600);
      expect(await harness.totalXp(), 10);
      advance(1);
      await setGamification(false);
      await harness.projections.syncDays({today});
      expect(await harness.totalXp(), 10);
    });
  });
}
