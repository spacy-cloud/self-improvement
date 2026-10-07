import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/goals/data/goal_snapshot_service.dart';
import 'package:self_improvement/core/health/domain/health_day_range.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';
import 'package:self_improvement/core/health/platform/fake_health_steps_source.dart';
import 'package:self_improvement/core/health/platform/unsupported_health_steps_source.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/settings/app_settings_repository.dart';
import 'package:self_improvement/core/settings/settings_commands.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_sync.dart';
import 'package:self_improvement/features/body/steps/data/steps_repository.dart';
import 'package:self_improvement/features/body/steps/domain/step_source.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// One comparison with the health interface (BS-97): when it reads, what it
/// asks for (the calendar day aggregation in the zone of the clock), what it
/// writes, and how it ends. A fake interface and a real in-memory database;
/// the clock is 2026-10-03 10:00 Europe/Berlin.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late FakeHealthStepsSource source;
  late StepsRepository steps;
  late SettingsCommands settingsCommands;
  late AppSettingsRepository settings;
  late HealthStepsSync sync;

  final today = LocalDate(2026, 10, 3);

  Future<void> start({
    RecordingProjectionSynchronizer? projection,
    String nowIso = '2026-10-03T08:00:00Z',
  }) async {
    harness = await DataHarness.create(
      realProjection: projection == null,
      projections: projection,
      nowIso: nowIso,
    );
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    source = FakeHealthStepsSource();
    steps = StepsRepository(
      database: harness.database,
      runner: harness.runner,
      snapshots: GoalSnapshotService(
        database: harness.database,
        clock: harness.clock,
        ids: harness.ids,
      ),
    );
    settingsCommands = SettingsCommands(
      database: harness.database,
      runner: harness.runner,
    );
    settings = AppSettingsRepository(harness.database);
    sync = HealthStepsSync(
      source: source,
      steps: steps,
      settings: settings,
      settingsCommands: settingsCommands,
      modules: harness.moduleStatus,
      clock: harness.clock,
      ids: harness.ids,
    );
  }

  setUp(start);
  tearDown(() => harness.dispose());

  Future<void> switchOn({bool value = true}) => settingsCommands
      .setHealthStepsSyncEnabled(commandId: harness.ids.newId(), value: value);

  /// A record at local noon of [day] in the zone of the clock.
  void noon(LocalDate day, int count, {String origin = 'phone'}) {
    final resolved = harness.clock.toUtc(day, const LocalTime(12, 0));
    source.addSteps((resolved as ZonedResolved).utc, count, origin: origin);
  }

  /// A value typed in by the user for [day].
  Future<void> typeIn(LocalDate day, int value) =>
      steps.setSteps(commandId: harness.ids.newId(), date: day, steps: value);

  Future<List<StepDayRow>> rows() =>
      harness.database.select(harness.database.stepDays).get();

  Future<int> receipts() async =>
      (await harness.database.select(harness.database.commandReceipts).get())
          .length;

  Future<HealthSyncOutcome> run([
    HealthSyncTrigger trigger = HealthSyncTrigger.action,
  ]) => sync.reconcile(trigger);

  void expectNoCalls() {
    expect(source.availabilityCalls, 0);
    expect(source.accessCalls, 0);
    expect(source.requestAccessCalls, 0);
    expect(source.totalCalls, isEmpty);
  }

  group('when a run reads nothing (BS-97)', () {
    test(
      'the switch is off: the interface is not asked at all (AT28)',
      () async {
        noon(today, 5000);
        final outcome = await run();
        expect(outcome.kind, HealthSyncKind.off);
        expectNoCalls();
        expect(await rows(), isEmpty);
      },
    );

    test('every trigger ends at once while the switch is off', () async {
      for (final trigger in HealthSyncTrigger.values) {
        expect((await run(trigger)).kind, HealthSyncKind.off);
      }
      expectNoCalls();
    });

    test('the module "Gewicht & Körper" is off: nothing is read or '
        'written', () async {
      await switchOn();
      noon(today, 5000);
      await harness.database
          .into(harness.database.moduleStatusHistory)
          .insert(
            ModuleStatusHistoryCompanion.insert(
              id: 'body-off',
              moduleId: ModuleId.body.key,
              effectiveAtUtc: DateTime.utc(2026, 10, 3, 8, 5),
              localDate: today,
              enabled: false,
            ),
          );
      final outcome = await run();
      expect(outcome.kind, HealthSyncKind.moduleOff);
      expectNoCalls();
      expect(await rows(), isEmpty);
    });

    for (final (availability, kind) in <(HealthAvailability, HealthSyncKind)>[
      (HealthAvailability.missing, HealthSyncKind.interfaceMissing),
      (HealthAvailability.updateRequired, HealthSyncKind.interfaceOutdated),
      (HealthAvailability.unsupported, HealthSyncKind.unsupported),
    ]) {
      test('the interface is ${availability.name}: the run ends before any '
          'read', () async {
        await switchOn();
        noon(today, 5000);
        source.availabilityValue = availability;
        final outcome = await run();
        expect(outcome.kind, kind);
        expect(outcome.availability, availability);
        expect(source.availabilityCalls, 1);
        expect(source.accessCalls, 0);
        expect(source.requestAccessCalls, 0);
        expect(source.totalCalls, isEmpty);
        expect(await rows(), isEmpty);
      });
    }

    test('no access: the run ends before any read and shows no dialog '
        '(AT28)', () async {
      await switchOn();
      noon(today, 5000);
      source.accessValue = HealthAccess.denied;
      final outcome = await run();
      expect(outcome.kind, HealthSyncKind.accessMissing);
      expect(outcome.availability, HealthAvailability.available);
      expect(outcome.access, HealthAccess.denied);
      expect(source.requestAccessCalls, 0, reason: 'only an action asks');
      expect(source.totalCalls, isEmpty);
      expect(await rows(), isEmpty);
      expect(
        (await settings.get())!.healthStepsLastSyncAtUtc,
        isNull,
        reason: 'no comparison happened',
      );
    });

    test('an access taken away during the read ends as missing access, '
        'nothing is written', () async {
      await switchOn();
      noon(today, 5000);
      source.totalFailure = const HealthStepsException(
        HealthFailureKind.accessDenied,
      );
      final outcome = await run();
      expect(outcome.kind, HealthSyncKind.accessMissing);
      expect(outcome.access, HealthAccess.denied);
      expect(await rows(), isEmpty);
    });
  });

  group('what a run asks for (BS-97, AT25)', () {
    test('one aggregated total per local day: today and the six days before, '
        'oldest first', () async {
      await switchOn();
      final outcome = await run(HealthSyncTrigger.enable);
      expect(outcome.kind, HealthSyncKind.synced);
      final window = healthSyncWindow(harness.clock);
      expect(source.totalCalls, hasLength(7));
      expect(
        [for (final call in source.totalCalls) (call.startUtc, call.endUtc)],
        [for (final range in window) (range.startUtc, range.endUtc)],
      );
      expect(window.first.day, LocalDate(2026, 9, 27));
      expect(window.last.day, today);
    });

    test('every trigger reloads the same seven days (BS-97)', () async {
      await switchOn();
      for (final trigger in HealthSyncTrigger.values) {
        source.clearCalls();
        await run(trigger);
        expect(source.totalCalls, hasLength(7), reason: trigger.name);
      }
    });

    test('records on both sides of local midnight land on different days '
        '(AT25)', () async {
      await switchOn();
      // 2026-10-02 23:59:59 and 2026-10-03 00:00:00 local (CEST, UTC+2).
      source
        ..addSteps(DateTime.utc(2026, 10, 2, 21, 59, 59), 100)
        ..addSteps(DateTime.utc(2026, 10, 2, 22), 40);
      await run();
      expect((await steps.findDay(LocalDate(2026, 10, 2)))!.steps, 100);
      expect((await steps.findDay(today))!.steps, 40);
    });

    test('the day the clocks go back has 25 hours and all of it counts on '
        'that day (AT25)', () async {
      await harness.dispose();
      await start(nowIso: '2026-10-26T08:00:00Z');
      await switchOn();
      source
        // 2026-10-24 23:59:59 CEST: still the 24th.
        ..addSteps(DateTime.utc(2026, 10, 24, 21, 59, 59), 1)
        // 2026-10-25 00:00:00 CEST: the first moment of the 25th.
        ..addSteps(DateTime.utc(2026, 10, 24, 22), 10)
        // 2026-10-25 02:30 CEST and 02:30 CET (the repeated hour).
        ..addSteps(DateTime.utc(2026, 10, 25, 0, 30), 100)
        ..addSteps(DateTime.utc(2026, 10, 25, 1, 30), 1000)
        // 2026-10-25 23:59:59 CET: the last moment of the 25th.
        ..addSteps(DateTime.utc(2026, 10, 25, 22, 59, 59), 10000)
        // 2026-10-26 00:00:00 CET: the 26th.
        ..addSteps(DateTime.utc(2026, 10, 25, 23), 7);
      await run();
      expect((await steps.findDay(LocalDate(2026, 10, 24)))!.steps, 1);
      expect(
        (await steps.findDay(LocalDate(2026, 10, 25)))!.steps,
        10 + 100 + 1000 + 10000,
      );
      expect((await steps.findDay(LocalDate(2026, 10, 26)))!.steps, 7);
    });

    test('the day the clocks go forward has 23 hours (AT25)', () async {
      await harness.dispose();
      await start(nowIso: '2026-03-30T08:00:00Z');
      await switchOn();
      source
        // 2026-03-29 00:00 CET up to 03:00 CEST.
        ..addSteps(DateTime.utc(2026, 3, 28, 23), 10)
        ..addSteps(DateTime.utc(2026, 3, 29, 0, 59), 100)
        // 2026-03-29 03:00 CEST (= 01:00Z) is the next hour on the clock.
        ..addSteps(DateTime.utc(2026, 3, 29, 1), 1000)
        // 2026-03-29 23:59:59 CEST and 2026-03-30 00:00 CEST.
        ..addSteps(DateTime.utc(2026, 3, 29, 21, 59, 59), 10000)
        ..addSteps(DateTime.utc(2026, 3, 29, 22), 7);
      await run();
      expect(
        (await steps.findDay(LocalDate(2026, 3, 29)))!.steps,
        10 + 100 + 1000 + 10000,
      );
      expect((await steps.findDay(LocalDate(2026, 3, 30)))!.steps, 7);
    });

    test('a record is counted once, in the day of its time, whatever else '
        'is around (BS-97)', () async {
      await switchOn();
      noon(today, 3000, origin: 'phone');
      noon(today.addDays(-1), 4000, origin: 'watch');
      await run();
      expect((await steps.findDay(today))!.steps, 3000);
      expect((await steps.findDay(today.addDays(-1)))!.steps, 4000);
      expect(await rows(), hasLength(2));
    });

    test('another zone asks other ranges: Health days follow it, typed-in '
        'days stay (AT25)', () async {
      await switchOn();
      // 2026-10-02 23:30Z: the 3rd in Berlin (01:30), the 2nd in New York.
      source.addSteps(DateTime.utc(2026, 10, 2, 23, 30), 500);
      await typeIn(LocalDate(2026, 10, 1), 7777);
      await run();
      expect((await steps.findDay(today))!.steps, 500);
      expect(await steps.findDay(LocalDate(2026, 10, 2)), isNull);

      harness.clock.setTimeZone('America/New_York');
      await run();
      expect(
        (await steps.findDay(LocalDate(2026, 10, 2)))!.steps,
        500,
        reason: 'in New York the record belongs to the 2nd',
      );
      expect(
        (await steps.findDay(today))!.steps,
        500,
        reason:
            'the old Health value stays until Health says otherwise: the '
            'comparison only fills and updates days it has data for',
      );
      expect((await steps.findDay(LocalDate(2026, 10, 1)))!.steps, 7777);
      expect(
        (await steps.findDay(LocalDate(2026, 10, 1)))!.source,
        StepSource.manual,
      );
    });

    test('the window follows the clock across midnight (AT25)', () async {
      await switchOn();
      harness.clock.setNow(DateTime.utc(2026, 10, 3, 21, 59)); // 23:59 Berlin
      await run();
      expect(source.totalCalls.last.endUtc, DateTime.utc(2026, 10, 3, 22));
      source.clearCalls();
      harness.clock.setNow(DateTime.utc(2026, 10, 3, 22)); // 00:00 Berlin
      await run();
      expect(source.totalCalls.last.endUtc, DateTime.utc(2026, 10, 4, 22));
      expect(source.totalCalls.first.startUtc, DateTime.utc(2026, 9, 27, 22));
    });
  });

  group('what a run writes (BS-97)', () {
    test('every day with data gets its total with the source health, days '
        'without data stay empty', () async {
      await switchOn();
      noon(today, 7450);
      noon(today.addDays(-2), 12000);
      noon(today.addDays(-6), 100);
      final outcome = await run(HealthSyncTrigger.enable);
      expect(outcome.kind, HealthSyncKind.synced);
      expect(outcome.applied.created, 3);
      expect(outcome.applied.noData, 4);
      expect(outcome.applied.total, 7);
      final stored = await rows();
      expect(stored, hasLength(3));
      expect(stored.every((row) => row.source == 'health'), isTrue);
      expect((await steps.findDay(today))!.steps, 7450);
      expect((await steps.findDay(today.addDays(-2)))!.steps, 12000);
      expect((await steps.findDay(today.addDays(-6)))!.steps, 100);
      expect(await steps.findDay(today.addDays(-1)), isNull);
      expect(
        await steps.findDay(today.addDays(-7)),
        isNull,
        reason: 'only seven days are looked at',
      );
    });

    test(
      'a value typed in is kept, the other days are filled (AT15)',
      () async {
        await switchOn();
        await typeIn(today, 5000);
        noon(today, 9000);
        noon(today.addDays(-1), 6000);
        final outcome = await run();
        expect(outcome.applied.keptManual, 1);
        expect(outcome.applied.created, 1);
        expect((await steps.findDay(today))!.steps, 5000);
        expect((await steps.findDay(today))!.source, StepSource.manual);
        expect(
          (await steps.findDay(today.addDays(-1)))!.source,
          StepSource.health,
        );
      },
    );

    test('a later run updates the value of Health and nothing else', () async {
      await switchOn();
      noon(today, 3000);
      await run();
      source.clearSteps();
      noon(today, 3600);
      final outcome = await run(HealthSyncTrigger.resume);
      expect(outcome.applied.updated, 1);
      expect((await steps.findDay(today))!.steps, 3600);
    });

    test(
      'a run with nothing new writes no step command (no receipt)',
      () async {
        await switchOn();
        noon(today, 3000);
        await run();
        final before = await receipts();
        harness.clock.advance(const Duration(minutes: 5));
        await run();
        // Only the time of the last comparison moved on.
        expect(await receipts(), before + 1);
        expect((await rows()).single.rowVersion, 1);
      },
    );

    test('the time of the last comparison is stored to the minute and only '
        'when the minute changes', () async {
      await switchOn();
      expect((await settings.get())!.healthStepsLastSyncAtUtc, isNull);
      harness.clock.setNow(DateTime.utc(2026, 10, 3, 8, 15, 42, 500));
      await run();
      expect(
        (await settings.get())!.healthStepsLastSyncAtUtc,
        DateTime.utc(2026, 10, 3, 8, 15),
      );
      final version = (await settings.get())!.rowVersion;
      harness.clock.setNow(DateTime.utc(2026, 10, 3, 8, 15, 59));
      await run();
      expect(
        (await settings.get())!.rowVersion,
        version,
        reason: 'the same minute writes nothing',
      );
      harness.clock.setNow(DateTime.utc(2026, 10, 3, 8, 16, 1));
      await run();
      expect(
        (await settings.get())!.healthStepsLastSyncAtUtc,
        DateTime.utc(2026, 10, 3, 8, 16),
      );
    });

    test('the run never throws: an unknown error of the interface ends as '
        '"failed"', () async {
      await switchOn();
      noon(today, 3000);
      for (final error in <Object>[
        StateError('boom'),
        PlatformException(code: 'x', message: 'secret 7450'),
        const HealthStepsException(HealthFailureKind.failed),
        const HealthStepsException(HealthFailureKind.unavailable),
        MissingPluginException(),
      ]) {
        source.totalFailure = error;
        final outcome = await run();
        expect(outcome.kind, HealthSyncKind.failed, reason: '$error');
      }
      expect(await rows(), isEmpty);
    });

    test('a failing read of one day writes nothing: all days or none, and '
        'the time of the last comparison stays', () async {
      await switchOn();
      noon(today, 3000);
      noon(today.addDays(-1), 4000);
      final window = healthSyncWindow(harness.clock);
      source.failTotalAtStarts.add(window[3].startUtc);
      final outcome = await run();
      expect(outcome.kind, HealthSyncKind.failed);
      expect(await rows(), isEmpty);
      expect((await settings.get())!.healthStepsLastSyncAtUtc, isNull);
      expect(
        source.totalCalls,
        hasLength(4),
        reason: 'it stopped at the failure',
      );
    });

    test('a failing write ends as "failed" and keeps the time of the last '
        'comparison', () async {
      final projection = RecordingProjectionSynchronizer();
      await harness.dispose();
      await start(projection: projection);
      await switchOn();
      noon(today, 3000);
      projection.failure = StateError('projection');
      final outcome = await run();
      expect(outcome.kind, HealthSyncKind.failed);
      expect(await rows(), isEmpty);
      expect((await settings.get())!.healthStepsLastSyncAtUtc, isNull);
    });

    test('after a failure the next run works again', () async {
      await switchOn();
      noon(today, 3000);
      source.totalFailure = StateError('once');
      expect((await run()).kind, HealthSyncKind.failed);
      source.totalFailure = null;
      expect((await run()).kind, HealthSyncKind.synced);
      expect((await steps.findDay(today))!.steps, 3000);
    });
  });

  group('while a run is in the middle of its work (BS-97)', () {
    test('the switch turned off during the read: nothing is written', () async {
      await switchOn();
      noon(today, 3000);
      final gate = Completer<void>();
      source.totalGate = gate.future;
      final running = run();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await switchOn(value: false);
      gate.complete();
      final outcome = await running;
      expect(outcome.kind, HealthSyncKind.off);
      expect(await rows(), isEmpty);
    });

    test('a value typed in during the read wins over the total that was '
        'read (AT15)', () async {
      await switchOn();
      noon(today, 3000);
      final gate = Completer<void>();
      source.totalGate = gate.future;
      final running = run();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await typeIn(today, 8000);
      gate.complete();
      final outcome = await running;
      expect(outcome.kind, HealthSyncKind.synced);
      expect(outcome.applied.keptManual, 1);
      final day = (await steps.findDay(today))!;
      expect(day.steps, 8000);
      expect(day.source, StepSource.manual);
    });
  });

  group('the source can only aggregate (BS-97)', () {
    test('the fake counts a record in the range that contains its time, '
        'the end is excluded and no record is none, not 0', () async {
      final noon0 = DateTime.utc(2026, 10, 3, 12);
      source.addSteps(noon0, 5);
      Future<int?> total(DateTime from, DateTime to) =>
          source.totalSteps(startUtc: from, endUtc: to);
      expect(await total(noon0, noon0.add(const Duration(hours: 1))), 5);
      expect(
        await total(noon0.subtract(const Duration(hours: 1)), noon0),
        isNull,
      );
      expect(
        await total(
          noon0.add(const Duration(seconds: 1)),
          noon0.add(const Duration(hours: 1)),
        ),
        isNull,
      );
      source
        ..clearSteps()
        ..addSteps(noon0, 0);
      expect(await total(noon0, noon0.add(const Duration(hours: 1))), 0);
    });
  });

  group('the unsupported adapter (BS-97)', () {
    test('reports no interface and fails every read', () async {
      const adapter = UnsupportedHealthStepsSource();
      expect(await adapter.availability(), HealthAvailability.unsupported);
      expect(await adapter.access(), HealthAccess.denied);
      expect(await adapter.requestAccess(), HealthAccess.denied);
      expect(await adapter.openInstallPage(), isFalse);
      expect(await adapter.openAccessSettings(), isFalse);
      await expectLater(
        adapter.totalSteps(
          startUtc: DateTime.utc(2026, 10, 3),
          endUtc: DateTime.utc(2026, 10, 4),
        ),
        throwsA(isA<HealthStepsException>()),
      );
    });
  });
}
