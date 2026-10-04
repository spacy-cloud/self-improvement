import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/focus/application/focus_countdown.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/data/focus_repository.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_history.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/manual_tick_source.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late ProviderContainer container;
  late ManualTickSource ticker;
  late DateTime phaseStart;

  final today = LocalDate(2026, 10, 3);

  setUp(() async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    ticker = ManualTickSource();
    phaseStart = harness.clock.nowUtc();
    ticker.onStart = () => phaseStart = harness.clock.nowUtc();
    container = harness.createContainer(
      overrides: [focusTickSourceProvider.overrideWithValue(ticker)],
    );
  });
  tearDown(() => harness.dispose());

  FocusRepository repository() => container.read(focusRepositoryProvider);

  void advance(int seconds) =>
      harness.clock.advance(Duration(seconds: seconds));

  Future<String> start({
    int planned = 1500,
    FocusCategory category = FocusCategory.learning,
  }) async {
    final outcome = await repository().start(
      commandId: harness.ids.newId(),
      category: category,
      plannedSeconds: planned,
    );
    return outcome.entityId!;
  }

  Future<void> save(String id) =>
      repository().save(commandId: harness.ids.newId(), id: id);

  /// Starts, lets [seconds] pass, saves.
  Future<String> completed(int seconds, {int planned = 3600}) async {
    final id = await start(planned: planned);
    advance(seconds);
    await save(id);
    advance(1);
    return id;
  }

  /// A monotonic reading with the wall clock advancing in step.
  Future<void> tick(int seconds) async {
    harness.clock.setNow(phaseStart.add(Duration(seconds: seconds)));
    ticker.emitSeconds(seconds);
    await settle();
  }

  Future<int> receiptCount(String type) async =>
      (await (harness.database.select(
        harness.database.commandReceipts,
      )..where((r) => r.commandType.equals(type))).get()).length;

  group('focusSessionProvider', () {
    test(
      'follows the open session: none, running, paused, none again',
      () async {
        container.listen(focusSessionProvider, (_, _) {});
        expect(await container.read(focusSessionProvider.future), isNull);

        final id = await start();
        await settle();
        expect(container.read(focusSessionProvider).value!.id, id);
        expect(
          container.read(focusSessionProvider).value!.status,
          FocusStatus.running,
        );

        advance(60);
        await repository().pause(commandId: harness.ids.newId(), id: id);
        await settle();
        expect(
          container.read(focusSessionProvider).value!.status,
          FocusStatus.paused,
        );

        await save(id);
        await settle();
        expect(container.read(focusSessionProvider).value, isNull);
      },
    );

    test(
      'is the same session for every reader (navigation cannot create another)',
      () async {
        final id = await start();
        final other = harness.createContainer();
        other.listen(focusSessionProvider, (_, _) {});
        container.listen(focusSessionProvider, (_, _) {});
        expect((await other.read(focusSessionProvider.future))!.id, id);
        expect((await container.read(focusSessionProvider.future))!.id, id);
      },
    );
  });

  group('focusCountdownProvider', () {
    Future<FocusCountdown?> countdown() async {
      container.listen(focusCountdownProvider, (_, _) {});
      return container.read(focusCountdownProvider.future);
    }

    test('counts down once per second from the persisted session', () async {
      await start(planned: 300);
      final first = await countdown();
      expect(first!.remainingSeconds, 300);
      expect(first.remainingText, '05:00');

      await tick(1);
      expect(
        container.read(focusCountdownProvider).value!.remainingSeconds,
        299,
      );
      await tick(61);
      expect(
        container.read(focusCountdownProvider).value!.remainingSeconds,
        239,
      );
      expect(
        container.read(focusCountdownProvider).value!.progress,
        closeTo(61 / 300, 1e-9),
      );
    });

    test('never writes to the database while ticking', () async {
      final id = await start(planned: 1500);
      await countdown();
      final receiptsBefore = await harness.database
          .select(harness.database.commandReceipts)
          .get();
      final versionBefore = (await repository().findById(id))!.rowVersion;
      for (var second = 1; second <= 120; second++) {
        await tick(second);
      }
      expect(
        (await harness.database.select(harness.database.commandReceipts).get())
            .length,
        receiptsBefore.length,
      );
      expect((await repository().findById(id))!.rowVersion, versionBefore);
      expect(
        container.read(focusCountdownProvider).value!.remainingSeconds,
        1380,
      );
    });

    test('reaching zero persists awaiting confirmation exactly once', () async {
      final events = <AppEvent>[];
      final subscription = harness.events.stream.listen(events.add);
      addTearDown(subscription.cancel);
      final id = await start(planned: 300);
      await countdown();
      for (var second = 1; second <= 299; second++) {
        await tick(second);
      }
      expect(
        (await repository().findById(id))!.status,
        FocusStatus.running,
        reason: 'one second left',
      );
      expect(await receiptCount(FocusRepository.awaitType), 0);

      await tick(300);
      await settle();
      await tick(301);
      await tick(10000);
      await settle();

      final session = (await repository().findById(id))!;
      expect(session.status, FocusStatus.awaitingConfirmation);
      expect(session.accumulatedSeconds, 300);
      expect(session.segmentStartedAtUtc, isNull);
      expect(session.completedLocalDate, isNull, reason: 'nothing completed');
      expect(await receiptCount(FocusRepository.awaitType), 1);
      expect(
        events.whereType<FocusStateChanged>(),
        hasLength(2),
        reason: 'start and the single awaiting transition',
      );
      expect(await harness.totalXp(), 0, reason: 'no XP before confirmation');
      expect(ticker.activeSubscriptions, 0, reason: 'ticking stopped');

      final value = container.read(focusCountdownProvider).value!;
      expect(value.isAwaitingConfirmation, isTrue);
      expect(value.remainingSeconds, 0);
    });

    test('a wall clock jump within the foreground phase does not shift the display', () async {
      final id = await start(planned: 600);
      await countdown();
      await tick(10);
      harness.clock.advance(const Duration(hours: 5)); // user changes the time
      ticker.emitSeconds(20);
      await settle();
      final value = container.read(focusCountdownProvider).value!;
      expect(value.remainingSeconds, 580, reason: 'monotonic time wins');
      expect(value.clockAnomaly, isFalse);
      expect(
        (await repository().findById(id))!.status,
        FocusStatus.running,
        reason: 'the jump did not end the session',
      );
    });

    test(
      'a backward clock jump is shown as an anomaly, the display stays right',
      () async {
        await start(planned: 600);
        await countdown();
        await tick(10);
        harness.clock.advance(const Duration(hours: -5));
        ticker.emitSeconds(20);
        await settle();
        final value = container.read(focusCountdownProvider).value!;
        expect(value.remainingSeconds, 580);
        expect(value.clockAnomaly, isTrue);
        expect(value.anomalyMessage, contains('Bitte prüfe die Sitzungsdauer'));
      },
    );

    test(
      'pause gives a static value and stops ticking, resume starts a new phase',
      () async {
        final id = await start(planned: 600);
        await countdown();
        await tick(100);
        advance(0);
        await repository().pause(commandId: harness.ids.newId(), id: id);
        await settle();
        final paused = container.read(focusCountdownProvider).value!;
        expect(paused.isPaused, isTrue);
        expect(paused.remainingSeconds, 500);
        expect(ticker.activeSubscriptions, 0);

        advance(3600);
        await repository().resume(commandId: harness.ids.newId(), id: id);
        await settle();
        final resumed = container.read(focusCountdownProvider).value!;
        expect(resumed.isRunning, isTrue);
        expect(
          resumed.remainingSeconds,
          500,
          reason: 'paused time does not count',
        );
        expect(ticker.phasesStarted, 2);
        await tick(30);
        expect(
          container.read(focusCountdownProvider).value!.remainingSeconds,
          470,
        );
      },
    );

    test('without an open session the value is null', () async {
      expect(await countdown(), isNull);
      final id = await start();
      await settle();
      expect(container.read(focusCountdownProvider).value, isNotNull);
      advance(10);
      await save(id);
      await settle();
      expect(container.read(focusCountdownProvider).value, isNull);
      expect(ticker.activeSubscriptions, 0);
    });

    test(
      'a restore (app resumed) re-bases the phase on the persisted segments',
      () async {
        await start(planned: 3600);
        await countdown();
        await tick(5);
        expect(container.read(focusCountdownProvider).value!.elapsedSeconds, 5);
        // The device slept for 20 minutes: wall clock moved, the monotonic one did not.
        advance(20 * 60);
        await container.read(focusRestorerProvider).restore();
        await settle();
        final value = container.read(focusCountdownProvider).value!;
        expect(value.elapsedSeconds, 1205);
        expect(ticker.phasesStarted, 2);
      },
    );

    test('a restore past the end persists awaiting confirmation', () async {
      final id = await start(planned: 600);
      await countdown();
      advance(5000);
      await container.read(focusRestorerProvider).restore();
      await settle();
      expect(
        (await repository().findById(id))!.status,
        FocusStatus.awaitingConfirmation,
      );
      expect(
        container.read(focusCountdownProvider).value!.isAwaitingConfirmation,
        isTrue,
      );
      expect(await receiptCount(FocusRepository.awaitType), 1);
    });

    test(
      'is disposed with its last listener: nothing ticks without a screen',
      () async {
        await start();
        final subscription = container.listen(
          focusCountdownProvider,
          (_, _) {},
        );
        await container.read(focusCountdownProvider.future);
        expect(ticker.activeSubscriptions, 1);
        subscription.close();
        await settle();
        expect(ticker.activeSubscriptions, 0);
      },
    );

    test('a session that ran out while no screen listened is picked up by the next listener', () async {
      final id = await start(planned: 300);
      advance(10000);
      expect((await repository().findById(id))!.status, FocusStatus.running);
      final value = await countdown();
      expect(value!.remainingSeconds, 0);
      await settle();
      expect(
        (await repository().findById(id))!.status,
        FocusStatus.awaitingConfirmation,
      );
    });
  });

  group('history providers', () {
    test('lists completed sessions newest first with category, duration, end time and status', () async {
      final first = await completed(1200, planned: 1500); // früher beendet
      final second = await completed(1500, planned: 1500); // abgeschlossen
      container.listen(focusHistoryProvider, (_, _) {});
      final history = await container.read(focusHistoryProvider.future);
      expect(history.map((e) => e.id), [second, first]);
      expect(history.first.categoryLabel, 'Lernen');
      expect(history.first.actualDurationText, '25 Min.');
      expect(history.first.status, FocusHistoryStatus.completed);
      expect(history.last.actualDurationText, '20 Min.');
      expect(history.last.status, FocusHistoryStatus.finishedEarly);
      expect(history.last.subtitle, endsWith('früher beendet'));
      expect(history.first.date, today);
    });

    test(
      'discarded and open sessions are not shown as completed time',
      () async {
        container.listen(focusHistoryProvider, (_, _) {});
        final discarded = await start();
        advance(600);
        await repository().discard(
          commandId: harness.ids.newId(),
          id: discarded,
        );
        await start();
        advance(10);
        await settle();
        expect(await container.read(focusHistoryProvider.future), isEmpty);
      },
    );

    test('follows deletes and undo', () async {
      container.listen(focusHistoryProvider, (_, _) {});
      final id = await completed(600);
      await settle();
      expect(container.read(focusHistoryProvider).value, hasLength(1));
      final deleted = await repository().delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      await settle();
      expect(container.read(focusHistoryProvider).value, isEmpty);
      await deleted.undo!.run(harness.ids.newId());
      await settle();
      expect(container.read(focusHistoryProvider).value, hasLength(1));
    });

    test('the paged history limits the list', () async {
      for (var i = 0; i < 4; i++) {
        await completed(100 + i);
      }
      container.listen(focusHistoryPageProvider(2), (_, _) {});
      final page = await container.read(focusHistoryPageProvider(2).future);
      expect(page, hasLength(2));
      container.listen(focusHistoryPageProvider(10), (_, _) {});
      expect(
        await container.read(focusHistoryPageProvider(10).future),
        hasLength(4),
      );
    });

    test('a session by id emits null after it is deleted', () async {
      final id = await completed(600);
      container.listen(focusSessionByIdProvider(id), (_, _) {});
      expect(
        (await container.read(focusSessionByIdProvider(id).future))!.id,
        id,
      );
      await repository().delete(commandId: harness.ids.newId(), id: id);
      await settle();
      expect(container.read(focusSessionByIdProvider(id)).value, isNull);
    });
  });

  group('today', () {
    FocusTodaySummary summary() =>
        container.read(focusTodaySummaryProvider).requireValue;

    Future<void> listenToSummary() async {
      container.listen(focusTodaySummaryProvider, (_, _) {});
      await container.read(focusSessionsTodayProvider.future);
      await container.read(goalVersionsProvider.future);
      await settle();
    }

    test(
      'shows completed minutes (only saved time) and the number of sessions',
      () async {
        await listenToSummary();
        expect(summary().isEmpty, isTrue);
        await completed(1200);
        await completed(1500);
        await settle();
        final result = summary();
        expect(result.completedMinutes, 45);
        expect(result.completedSeconds, 2700);
        expect(result.sessionCount, 2);
      },
    );

    test('running, awaiting and discarded sessions do not count', () async {
      await listenToSummary();
      final discarded = await start();
      advance(900);
      await repository().discard(commandId: harness.ids.newId(), id: discarded);
      await start(planned: 300);
      advance(500);
      await settle();
      expect(summary().completedSeconds, 0);
      expect(summary().sessionCount, 0);
    });

    test(
      'the goal comes from the goal version in effect (default 25 minutes)',
      () async {
        await listenToSummary();
        expect(summary().goalMinutes, 25);
        await completed(1200);
        await settle();
        expect(summary().goalReached, isFalse);
        expect(summary().remainingGoalMinutes, 5);
        await completed(600);
        await settle();
        expect(summary().goalReached, isTrue);
        expect(summary().goalFraction, 1.0);
        expect(summary().completedMinutes, 30, reason: 'the real time stays');
      },
    );

    test(
      'a goal of 60 minutes: 45 of 60 is 75 percent, 15 minutes missing',
      () async {
        await harness.database
            .into(harness.database.goalVersions)
            .insert(
              GoalVersionsCompanion.insert(
                id: harness.ids.newId(),
                goalType: GoalType.focusMinutes.key,
                targetInteger: const Value(60),
                enabled: true,
                effectiveFromDate: today,
                createdAtUtc: harness.clock.nowUtc(),
              ),
            );
        await completed(2700);
        await listenToSummary();
        expect(summary().goalMinutes, 60);
        expect(summary().completedMinutes, 45);
        expect(summary().goalFraction, closeTo(0.75, 1e-9));
        expect(summary().remainingGoalMinutes, 15);
      },
    );

    test('a switched off goal gives no goal', () async {
      await harness.database
          .into(harness.database.goalVersions)
          .insert(
            GoalVersionsCompanion.insert(
              id: harness.ids.newId(),
              goalType: GoalType.focusMinutes.key,
              targetInteger: const Value(25),
              enabled: false,
              effectiveFromDate: today,
              createdAtUtc: harness.clock.nowUtc(),
            ),
          );
      await listenToSummary();
      expect(summary().goalMinutes, isNull);
      expect(summary().goalFraction, isNull);
    });

    test('a new day starts with an empty summary', () async {
      await listenToSummary();
      await completed(1200);
      await settle();
      expect(summary().completedMinutes, 20);
      harness.clock.setNow(DateTime.utc(2026, 10, 4, 8));
      container.read(todayProvider.notifier).refresh();
      await settle();
      await container.read(focusSessionsTodayProvider.future);
      await settle();
      expect(summary().date, LocalDate(2026, 10, 4));
      expect(summary().completedMinutes, 0);
      expect(summary().sessionCount, 0);
    });

    test('the sessions of today are listed newest first', () async {
      container.listen(focusSessionsTodayProvider, (_, _) {});
      final a = await completed(300);
      final b = await completed(400);
      final entries = await container.read(focusSessionsTodayProvider.future);
      await settle();
      expect(
        container.read(focusSessionsTodayProvider).value!.map((e) => e.id),
        [b, a],
      );
      expect(entries, isNotNull);
    });
  });
}
