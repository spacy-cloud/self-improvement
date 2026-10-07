import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/health/application/health_providers.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';
import 'package:self_improvement/core/health/platform/fake_health_steps_source.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_controller.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_sync.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/body/steps/domain/health_steps_status.dart';
import 'package:self_improvement/features/body/steps/domain/step_source.dart';
import 'package:self_improvement/features/modules/application/data_epoch.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// The switch "Schritte aus Health übernehmen" as a state machine (BS-97): the
/// wish in the settings, what the device says, the first comparison when the
/// switch goes on, the three triggers, and the honest state after an import.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late FakeHealthStepsSource source;
  late ProviderContainer container;

  final today = LocalDate(2026, 10, 3);

  Future<void> settle([int milliseconds = 60]) =>
      Future<void>.delayed(Duration(milliseconds: milliseconds));

  Future<void> start() async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    source = FakeHealthStepsSource();
    container = harness.createContainer(
      overrides: [healthStepsSourceProvider.overrideWithValue(source)],
    );
    // Keep the streams of the settings and the modules alive, like the app.
    container
      ..listen(appSettingsProvider, (previous, next) {})
      ..listen(moduleStatusesProvider, (previous, next) {})
      ..listen(healthStepsStatusProvider, (previous, next) {});
    await container.read(appSettingsProvider.future);
    await container.read(moduleStatusesProvider.future);
  }

  setUp(start);
  tearDown(() => harness.dispose());

  HealthStepsController controller() =>
      container.read(healthStepsControllerProvider.notifier);

  HealthStepsStatus status() => container.read(healthStepsStatusProvider);

  /// A record at local noon of [day].
  void noon(LocalDate day, int count) {
    final resolved = harness.clock.toUtc(day, const LocalTime(12, 0));
    source.addSteps((resolved as ZonedResolved).utc, count);
  }

  /// Writes the wish straight into the database, the way an import does.
  Future<void> wishFromBackup({required bool value, DateTime? lastSync}) async {
    await harness.database
        .update(harness.database.appSettings)
        .write(
          AppSettingsCompanion(
            healthStepsSyncEnabled: Value(value),
            healthStepsLastSyncAtUtc: Value(lastSync),
          ),
        );
    await settle();
  }

  Future<List<StepDayRow>> rows() =>
      harness.database.select(harness.database.stepDays).get();

  group('the state the screens see (BS-97)', () {
    test('nothing is known before the device was asked and a switch that is '
        'off shows nothing', () {
      expect(status().condition, HealthStepsCondition.hidden);
      expect(status().visible, isFalse);
      expect(source.availabilityCalls, 0, reason: 'nothing asks by itself');
    });

    test(
      'asking once shows an available interface with the switch off',
      () async {
        await controller().ensureStatus();
        expect(status().condition, HealthStepsCondition.off);
        expect(status().visible, isTrue);
        expect(status().sourceName, 'Health Connect');
        expect(status().enabled, isFalse);
        expect(source.availabilityCalls, 1);
        expect(source.accessCalls, 1);
        await controller().ensureStatus();
        expect(source.availabilityCalls, 1, reason: 'known: not asked again');
      },
    );

    test('a device without an interface hides the switch (BS-97)', () async {
      source.availabilityValue = HealthAvailability.unsupported;
      await controller().ensureStatus();
      expect(status().condition, HealthStepsCondition.hidden);
      expect(status().visible, isFalse);
    });

    test('the module "Gewicht & Körper" off hides it too', () async {
      await controller().ensureStatus();
      expect(status().visible, isTrue);
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
      await settle();
      expect(status().condition, HealthStepsCondition.hidden);
    });

    for (final (availability, access, condition)
        in <(HealthAvailability, HealthAccess, HealthStepsCondition)>[
          (
            HealthAvailability.missing,
            HealthAccess.denied,
            HealthStepsCondition.interfaceMissing,
          ),
          (
            HealthAvailability.updateRequired,
            HealthAccess.denied,
            HealthStepsCondition.interfaceOutdated,
          ),
          (
            HealthAvailability.available,
            HealthAccess.denied,
            HealthStepsCondition.accessMissing,
          ),
          (
            HealthAvailability.available,
            HealthAccess.granted,
            HealthStepsCondition.ready,
          ),
        ]) {
      test('switch on, ${availability.name}, ${access.name}: '
          '${condition.name}', () async {
        await wishFromBackup(value: true);
        source
          ..availabilityValue = availability
          ..accessValue = access;
        await controller().refreshStatus();
        expect(status().condition, condition);
        expect(status().enabled, isTrue);
        expect(source.totalCalls, isEmpty, reason: 'asking reads no steps');
        expect(source.requestAccessCalls, 0, reason: 'asking shows no dialog');
      });
    }

    test('an enabled switch that was not asked yet is shown neutrally so it '
        'can still be switched off', () async {
      await wishFromBackup(value: true);
      expect(status().condition, HealthStepsCondition.unknown);
      expect(status().visible, isTrue);
    });

    test('the time of the last comparison comes from the settings', () async {
      final at = DateTime.utc(2026, 10, 2, 7, 41);
      await wishFromBackup(value: true, lastSync: at);
      expect(status().lastSyncAtUtc, at);
    });

    test(
      'a failing read of the state is not fatal and leaves it unknown',
      () async {
        source.availabilityFailure = StateError('x');
        await controller().ensureStatus();
        expect(status().condition, HealthStepsCondition.hidden);
        source.availabilityFailure = null;
        await controller().ensureStatus();
        expect(status().condition, HealthStepsCondition.off);
      },
    );
  });

  group('switching on (BS-97, AT28)', () {
    test('stores the wish, asks for the access once and reloads the seven '
        'days', () async {
      source.accessValue = HealthAccess.denied;
      noon(today, 7450);
      noon(today.addDays(-3), 12000);
      final result = await controller().enable();
      expect(result, isA<HealthEnabled>());
      expect((result as HealthEnabled).access, HealthAccessResult.synced);
      expect(source.requestAccessCalls, 1);
      expect(source.totalCalls, hasLength(7));
      await settle();
      expect(status().enabled, isTrue);
      expect(status().condition, HealthStepsCondition.ready);
      expect(status().lastSyncAtUtc, DateTime.utc(2026, 10, 3, 8));
      expect((await rows()).map((row) => row.source).toSet(), {'health'});
      expect(await rows(), hasLength(2));
    });

    test('with the access already given no dialog is shown', () async {
      noon(today, 100);
      await controller().enable();
      expect(source.requestAccessCalls, 0);
      expect(source.totalCalls, hasLength(7));
    });

    test('a refused dialog keeps the wish, shows "no access" and reads '
        'nothing (AT28)', () async {
      source
        ..accessValue = HealthAccess.denied
        ..accessAfterRequest = HealthAccess.denied;
      noon(today, 7450);
      final result = await controller().enable();
      expect((result as HealthEnabled).access, HealthAccessResult.accessDenied);
      await settle();
      expect(status().enabled, isTrue);
      expect(status().condition, HealthStepsCondition.accessMissing);
      expect(source.totalCalls, isEmpty);
      expect(await rows(), isEmpty);
    });

    test('a missing interface shows no dialog and keeps the wish', () async {
      source.availabilityValue = HealthAvailability.missing;
      final result = await controller().enable();
      expect(
        (result as HealthEnabled).access,
        HealthAccessResult.interfaceMissing,
      );
      await settle();
      expect(status().condition, HealthStepsCondition.interfaceMissing);
      expect(source.requestAccessCalls, 0);
      expect(source.totalCalls, isEmpty);
    });

    test('an outdated interface shows no dialog either', () async {
      source.availabilityValue = HealthAvailability.updateRequired;
      final result = await controller().enable();
      expect(
        (result as HealthEnabled).access,
        HealthAccessResult.interfaceOutdated,
      );
      await settle();
      expect(status().condition, HealthStepsCondition.interfaceOutdated);
      expect(source.requestAccessCalls, 0);
    });

    test('a device without an interface ends as unsupported', () async {
      source.availabilityValue = HealthAvailability.unsupported;
      final result = await controller().enable();
      expect((result as HealthEnabled).access, HealthAccessResult.unsupported);
    });

    test('a failing dialog is not fatal and ends as "failed"', () async {
      source
        ..accessValue = HealthAccess.denied
        ..requestFailure = StateError('x');
      final result = await controller().enable();
      expect((result as HealthEnabled).access, HealthAccessResult.failed);
      await settle();
      expect(status().enabled, isTrue);
    });

    test('a wish that cannot be stored changes nothing and asks nothing '
        '(AT27)', () async {
      await harness.database.customStatement(
        'CREATE TRIGGER refuse_settings BEFORE UPDATE ON app_settings '
        "BEGIN SELECT RAISE(ABORT, 'refused'); END",
      );
      final result = await controller().enable();
      expect(result, isA<HealthEnableStorageFailed>());
      expect(source.availabilityCalls, 0);
      expect(source.requestAccessCalls, 0);
      await settle();
      expect(status().enabled, isFalse);
    });

    test(
      '"Zugriff erlauben" asks again and compares when it was given',
      () async {
        source
          ..accessValue = HealthAccess.denied
          ..accessAfterRequest = HealthAccess.denied;
        noon(today, 4000);
        await controller().enable();
        expect(await rows(), isEmpty);
        source.accessAfterRequest = HealthAccess.granted;
        final result = await controller().allowAccess();
        expect(result, HealthAccessResult.synced);
        expect(source.requestAccessCalls, 2);
        expect((await rows()).single.steps, 4000);
        await settle();
        expect(status().condition, HealthStepsCondition.ready);
      },
    );

    test('"Zugriff erlauben" that is refused again stays honest', () async {
      source
        ..accessValue = HealthAccess.denied
        ..accessAfterRequest = HealthAccess.denied;
      await controller().enable();
      expect(await controller().allowAccess(), HealthAccessResult.accessDenied);
      expect(status().condition, HealthStepsCondition.accessMissing);
    });
  });

  group('switching off (BS-97)', () {
    test('keeps every value, stops reading and keeps the access in the '
        'system', () async {
      noon(today, 7450);
      await controller().enable();
      await settle();
      expect(await rows(), hasLength(1));

      expect(await controller().disable(), isTrue);
      await settle();
      expect(status().enabled, isFalse);
      expect(status().condition, HealthStepsCondition.off);
      expect(await rows(), hasLength(1), reason: 'the values stay');

      source.clearCalls();
      noon(today.addDays(-1), 100);
      expect(
        (await controller().reconcile(HealthSyncTrigger.resume)).kind,
        HealthSyncKind.off,
      );
      expect(source.totalCalls, isEmpty);
      expect(source.availabilityCalls, 0);
      expect(await rows(), hasLength(1));
      expect(source.accessValue, HealthAccess.granted);
    });

    test('switching on again reloads the seven days', () async {
      noon(today, 7450);
      await controller().enable();
      await controller().disable();
      source.clearCalls();
      noon(today.addDays(-2), 2000);
      await controller().enable();
      expect(source.totalCalls, hasLength(7));
      expect(await rows(), hasLength(2));
    });

    test('a wish that cannot be stored is reported (AT27)', () async {
      await controller().enable();
      await harness.database.customStatement(
        'CREATE TRIGGER refuse_settings BEFORE UPDATE ON app_settings '
        "BEGIN SELECT RAISE(ABORT, 'refused'); END",
      );
      expect(await controller().disable(), isFalse);
    });
  });

  group('the three triggers (BS-97)', () {
    test('the action runs a comparison and shows "running" while it '
        'does', () async {
      await controller().enable();
      source.clearCalls();
      final gate = Completer<void>();
      source.totalGate = gate.future;
      final running = controller().reconcile(HealthSyncTrigger.action);
      await settle(20);
      expect(status().syncing, isTrue);
      gate.complete();
      final outcome = await running;
      expect(outcome.kind, HealthSyncKind.synced);
      expect(status().syncing, isFalse);
      expect(source.totalCalls, hasLength(7));
    });

    test('a call while a comparison runs joins it: seven reads, not '
        'fourteen', () async {
      await controller().enable();
      source.clearCalls();
      final gate = Completer<void>();
      source.totalGate = gate.future;
      final first = controller().reconcile(HealthSyncTrigger.resume);
      final second = controller().reconcile(HealthSyncTrigger.action);
      await settle(20);
      gate.complete();
      await Future.wait([first, second]);
      expect(source.totalCalls, hasLength(7));
    });

    test(
      'a comparison that fails is shown and the next one clears it',
      () async {
        await controller().enable();
        source.totalFailure = StateError('x');
        final outcome = await controller().reconcile(HealthSyncTrigger.action);
        expect(outcome.kind, HealthSyncKind.failed);
        expect(status().condition, HealthStepsCondition.failed);
        expect(status().reading, isTrue);
        source.totalFailure = null;
        await controller().reconcile(HealthSyncTrigger.action);
        expect(status().condition, HealthStepsCondition.ready);
      },
    );

    test(
      'an access that was taken away shows up at the next comparison',
      () async {
        await controller().enable();
        expect(status().condition, HealthStepsCondition.ready);
        source.accessValue = HealthAccess.denied;
        final outcome = await controller().reconcile(HealthSyncTrigger.resume);
        expect(outcome.kind, HealthSyncKind.accessMissing);
        expect(status().condition, HealthStepsCondition.accessMissing);
      },
    );

    test('the start of the app runs one comparison, a return to the '
        'foreground another one, nothing else does', () async {
      await controller().enable();
      source.clearCalls();
      final autoSync = container.read(healthStepsAutoSyncProvider);
      addTearDown(autoSync.dispose);
      await settle();
      expect(source.totalCalls, hasLength(7), reason: 'start');

      source.clearCalls();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await settle();
      expect(source.totalCalls, isEmpty, reason: 'leaving reads nothing');

      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle();
      expect(source.totalCalls, hasLength(7), reason: 'resume');
    });

    test(
      'with the switch off neither start nor resume asks the device',
      () async {
        final autoSync = container.read(healthStepsAutoSyncProvider);
        addTearDown(autoSync.dispose);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await settle();
        expect(source.availabilityCalls, 0);
        expect(source.accessCalls, 0);
        expect(source.totalCalls, isEmpty);
      },
    );

    test('after dispose the app lifecycle runs nothing', () async {
      await controller().enable();
      final autoSync = container.read(healthStepsAutoSyncProvider);
      await settle();
      autoSync.dispose();
      source.clearCalls();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle();
      expect(source.totalCalls, isEmpty);
    });

    test(
      'start is idempotent: a second start adds no second observer',
      () async {
        await controller().enable();
        final calls = <HealthSyncTrigger>[];
        final autoSync = HealthStepsAutoSync(
          reconcile: (trigger) async {
            calls.add(trigger);
            return const HealthSyncOutcome(HealthSyncKind.off);
          },
        )..start();
        addTearDown(autoSync.dispose);
        autoSync.start();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await settle(10);
        expect(calls, [HealthSyncTrigger.start, HealthSyncTrigger.resume]);
      },
    );
  });

  group('a backup with the switch on (BS-97, AT30)', () {
    test('without access the state is honest and nothing is read until a '
        'trigger runs', () async {
      source.accessValue = HealthAccess.denied;
      await wishFromBackup(
        value: true,
        lastSync: DateTime.utc(2026, 9, 30, 21, 5),
      );
      container.read(dataEpochProvider.notifier).bump();
      await settle();
      expect(status().enabled, isTrue);
      expect(status().condition, HealthStepsCondition.accessMissing);
      expect(
        status().lastSyncAtUtc,
        DateTime.utc(2026, 9, 30, 21, 5),
        reason: 'the time comes from the backup',
      );
      expect(source.totalCalls, isEmpty);
      expect(source.requestAccessCalls, 0, reason: 'a file never asks');
    });

    test('the values of Health from the backup stay until a comparison with '
        'access updates them', () async {
      noon(today, 9000);
      // A Health day from the backup.
      await harness.database
          .into(harness.database.stepDays)
          .insert(
            StepDaysCompanion.insert(
              id: 'imported',
              localDate: today,
              steps: 5000,
              timezoneId: 'Europe/Berlin',
              source: const Value('health'),
              createdAtUtc: DateTime.utc(2026, 10, 1),
              updatedAtUtc: DateTime.utc(2026, 10, 1),
            ),
          );
      source.accessValue = HealthAccess.denied;
      await wishFromBackup(value: true);
      container.read(dataEpochProvider.notifier).bump();
      await settle();
      await controller().reconcile(HealthSyncTrigger.start);
      expect((await rows()).single.steps, 5000, reason: 'no access: no read');
      source.accessValue = HealthAccess.granted;
      await controller().reconcile(HealthSyncTrigger.action);
      final day = (await rows()).single;
      expect(day.steps, 9000);
      expect(day.source, 'health');
    });

    test('with the access of this device the state is "ready" after the '
        'import and the next trigger compares', () async {
      await wishFromBackup(value: true);
      container.read(dataEpochProvider.notifier).bump();
      await settle();
      expect(status().condition, HealthStepsCondition.ready);
      noon(today, 1234);
      await controller().reconcile(HealthSyncTrigger.resume);
      expect(
        (await container.read(stepsRepositoryProvider).findDay(today))!.source,
        StepSource.health,
      );
    });

    test('an import with the switch off asks the device nothing', () async {
      container.read(dataEpochProvider.notifier).bump();
      await settle();
      expect(source.availabilityCalls, 0);
      expect(status().condition, HealthStepsCondition.hidden);
    });
  });
}
