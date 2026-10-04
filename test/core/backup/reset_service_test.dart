import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/reset_service.dart';
import 'package:self_improvement/core/backup/testing/in_memory_backup_adapters.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_status_repository.dart';
import 'package:self_improvement/core/profile/profile_repository.dart';
import 'package:self_improvement/core/settings/app_settings_repository.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import 'support/backup_fixtures.dart';

/// A clock that fails on demand (to make the seeding inside the reset
/// transaction fail after the rows were already deleted).
final class _FailingClock implements ClockService {
  _FailingClock(this._inner);

  final FakeClock _inner;
  bool failing = false;

  @override
  DateTime nowUtc() {
    if (failing) {
      throw StateError('simulated clock failure');
    }
    return _inner.nowUtc();
  }

  @override
  String get timeZoneId => _inner.timeZoneId;

  @override
  LocalDate today() => _inner.today();

  @override
  LocalDate localDateOf(DateTime utc, {String? timeZoneId}) =>
      _inner.localDateOf(utc, timeZoneId: timeZoneId);

  @override
  LocalDateTime toLocal(DateTime utc, {String? timeZoneId}) =>
      _inner.toLocal(utc, timeZoneId: timeZoneId);

  @override
  ZonedResolution toUtc(LocalDate date, LocalTime time, {String? timeZoneId}) =>
      _inner.toUtc(date, time, timeZoneId: timeZoneId);
}

void main() {
  setUpAll(() {
    TimeZones.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late DataHarness harness;
  late RecordingNotificationCanceller canceller;
  late RecordingBackupListener listener;
  late InMemoryBackupFileGateway files;
  late ResetService service;

  setUp(() async {
    harness = await DataHarness.create();
    addTearDown(harness.dispose);
    await populateRichDatabase(harness.database);
    canceller = RecordingNotificationCanceller();
    listener = RecordingBackupListener();
    files = InMemoryBackupFileGateway()
      ..files['/cache/backup_exports/old.json'] = Uint8List.fromList(
        utf8.encode('{}'),
      );
    service = ResetService(
      database: harness.database,
      clock: harness.clock,
      notifications: canceller,
      listener: listener,
      files: files,
    );
  });

  group('confirmation (AT32: cancelling changes nothing)', () {
    test('the phrase is LÖSCHEN, ignoring case and surrounding spaces', () {
      expect(ResetService.confirmationPhrase, 'LÖSCHEN');
      for (final input in [
        'LÖSCHEN',
        'löschen',
        'Löschen',
        '  LÖSCHEN  ',
        '\nlöschen\t',
      ]) {
        expect(ResetService.isConfirmation(input), isTrue, reason: input);
      }
      for (final input in [
        '',
        ' ',
        'LOESCHEN',
        'LÖSCHEN!',
        'LÖSCH',
        'LÖSCHEN LÖSCHEN',
        'DELETE',
        'LÖSCHEN.',
        'Loschen',
      ]) {
        expect(ResetService.isConfirmation(input), isFalse, reason: input);
      }
    });

    test('a wrong confirmation changes nothing and cancels nothing', () async {
      final before = await dumpDatabase(harness.database);
      for (final input in ['', 'nein', 'LOESCHEN', 'LÖSCH']) {
        await expectLater(
          service.resetAllData(confirmation: input),
          throwsA(isA<ValidationFailure>()),
        );
      }
      expect(await dumpDatabase(harness.database), before);
      expect(canceller.calls, 0);
      expect(listener.calls, 0);
      expect(files.deleteCalls, isEmpty);
      expect(files.files, isNotEmpty);
    });

    test('the failure explains what to type, in German', () async {
      try {
        await service.resetAllData(confirmation: 'x');
        fail('expected a ValidationFailure');
      } on ValidationFailure catch (failure) {
        expect(failure.fieldErrors.keys, ['confirmation']);
        expect(failure.userMessage, 'Bitte gib zur Bestätigung „LÖSCHEN“ ein.');
      }
    });

    test(
      'doing nothing is the default: an unused service changes nothing',
      () async {
        final before = await dumpDatabase(harness.database);
        expect(await dumpDatabase(harness.database), before);
        expect(canceller.calls, 0);
      },
    );
  });

  group('after a confirmed reset', () {
    test('every table is empty except the re-created singletons', () async {
      await service.resetAllData(confirmation: 'LÖSCHEN');
      final dump = await dumpDatabase(harness.database);
      for (final entry in dump.entries) {
        if (entry.key == 'profile' || entry.key == 'app_settings') {
          expect(entry.value, hasLength(1), reason: entry.key);
        } else {
          expect(entry.value, isEmpty, reason: entry.key);
        }
      }
    });

    test('the profile is brand new and onboarding is open again', () async {
      harness.clock.advance(const Duration(days: 30));
      await service.resetAllData(confirmation: 'LÖSCHEN');

      final profile = (await ProfileRepository(harness.database).get())!;
      expect(profile.onboardingCompleted, isFalse);
      expect(profile.displayName, isNull);
      expect(profile.heightCm, isNull);
      expect(profile.ageYears, isNull);
      expect(profile.startWeightGrams, isNull);
      expect(profile.targetWeightGrams, isNull);
      expect(profile.motivationGoals, isEmpty);
      expect(profile.rowVersion, 1);
      expect(
        profile.startedOn,
        LocalDate(2026, 11, 2),
        reason: 'today, not the old start',
      );
      final row = await harness.database
          .select(harness.database.profile)
          .getSingle();
      expect(row.id, 'local');
      expect(row.createdAtUtc, DateTime.utc(2026, 11, 2, 8));
    });

    test('settings are back to their defaults', () async {
      await service.resetAllData(confirmation: 'LÖSCHEN');
      final settings = (await AppSettingsRepository(harness.database).get())!;
      expect(settings.themeModeKey, 'system');
      expect(settings.reduceMotion, isFalse);
      expect(settings.haptics, isTrue);
      expect(settings.notificationsEnabled, isFalse);
      expect(settings.lastKnownTimezone, 'Europe/Berlin');
      expect(settings.rowVersion, 1);
    });

    test('modules, cards and goals start from scratch', () async {
      await service.resetAllData(confirmation: 'LÖSCHEN');
      expect(
        await harness.database
            .select(harness.database.moduleStatusHistory)
            .get(),
        isEmpty,
      );
      expect(
        await harness.database.select(harness.database.dashboardCards).get(),
        isEmpty,
      );
      expect(
        await harness.database.select(harness.database.goalVersions).get(),
        isEmpty,
      );
      // Without history all modules count as enabled (fresh installation).
      final statuses = await ModuleStatusRepository(harness.database)
          .statuses();
      expect(statuses.values, everyElement(isTrue));
      expect(statuses.keys, ModuleId.values);
    });

    test('a running timer is gone with its session', () async {
      final db = harness.database;
      await (db.delete(db.focusSessions)).go();
      await db
          .into(db.focusSessions)
          .insert(
            FocusSessionsCompanion.insert(
              id: uuid(0xF01),
              category: 'reading',
              plannedSeconds: 1500,
              segmentStartedAtUtc: Value(at(4, 8)),
              startedAtUtc: at(4, 8),
              timezoneId: berlin,
              status: 'running',
              createdAtUtc: at(4, 8),
              updatedAtUtc: at(4, 8),
            ),
          );
      await service.resetAllData(confirmation: 'LÖSCHEN');
      expect(await db.select(db.focusSessions).get(), isEmpty);
    });

    test(
      'the OS notifications are cancelled and cache files removed',
      () async {
        final outcome = await service.resetAllData(confirmation: 'LÖSCHEN');
        expect(canceller.calls, 1);
        expect(files.files, isEmpty);
        expect(files.deleteCalls, [true], reason: 'including share copies');
        expect(listener.calls, 1);
        expect(outcome.notificationsCancelled, isTrue);
        expect(outcome.temporaryFilesDeleted, isTrue);
        expect(outcome.listenerNotified, isTrue);
        expect(outcome.followUpSucceeded, isTrue);
      },
    );

    test('a second reset on the fresh state works as well', () async {
      await service.resetAllData(confirmation: 'LÖSCHEN');
      final first = await dumpDatabase(harness.database);
      await service.resetAllData(confirmation: 'löschen');
      expect(await dumpDatabase(harness.database), first);
    });

    test('no trace of the old data is left in a new export', () async {
      await service.resetAllData(confirmation: 'LÖSCHEN');
      final backup = await BackupExporter(
        database: harness.database,
        clock: harness.clock,
      ).export();
      final text = utf8.decode(backup.bytes);
      expect(text, isNot(contains('Mia Muster')));
      expect(text, isNot(contains('Lesen')));
      expect(backup.recordCount, 2);
      expect(backup.isRestorable, isTrue);
    });

    test('without a file gateway the cache step counts as done', () async {
      final bare = ResetService(
        database: harness.database,
        clock: harness.clock,
        notifications: canceller,
      );
      final outcome = await bare.resetAllData(confirmation: 'LÖSCHEN');
      expect(outcome.temporaryFilesDeleted, isTrue);
      expect(
        outcome.listenerNotified,
        isTrue,
        reason: 'the default no-op listener',
      );
    });
  });

  group('follow-ups run AFTER the commit and never undo it', () {
    test('cancelling sees the data already gone', () async {
      var weightsSeen = -1;
      var onboardingSeen = true;
      final observing = RecordingNotificationCanceller(
        onCancel: () async {
          weightsSeen =
              (await harness.database
                      .select(harness.database.weightEntries)
                      .get())
                  .length;
          onboardingSeen = (await ProfileRepository(
            harness.database,
          ).get())!.onboardingCompleted;
        },
      );
      await ResetService(
        database: harness.database,
        clock: harness.clock,
        notifications: observing,
      ).resetAllData(confirmation: 'LÖSCHEN');
      expect(weightsSeen, 0, reason: 'the commit happened before cancelling');
      expect(onboardingSeen, isFalse);
    });

    test('the listener sees the data already gone', () async {
      var weightsSeen = -1;
      final observing = RecordingBackupListener(
        onReplaced: () async => weightsSeen =
            (await harness.database
                    .select(harness.database.weightEntries)
                    .get())
                .length,
      );
      await ResetService(
        database: harness.database,
        clock: harness.clock,
        notifications: canceller,
        listener: observing,
      ).resetAllData(confirmation: 'LÖSCHEN');
      expect(weightsSeen, 0);
    });

    test('a cancel failure does not undo the reset', () async {
      canceller.failure = StateError('platform plugin missing');
      final outcome = await service.resetAllData(confirmation: 'LÖSCHEN');
      expect(outcome.notificationsCancelled, isFalse);
      expect(outcome.followUpSucceeded, isFalse);
      expect(
        outcome.temporaryFilesDeleted,
        isTrue,
        reason: 'later steps still run',
      );
      expect(outcome.listenerNotified, isTrue);
      expect(
        await harness.database.select(harness.database.weightEntries).get(),
        isEmpty,
      );
      expect(
        (await ProfileRepository(harness.database).get())!.onboardingCompleted,
        isFalse,
      );
    });

    test(
      'failing cache cleanup or listener are reported, not thrown',
      () async {
        files.deleteFailure = StateError('disk');
        listener.failure = StateError('ui');
        final outcome = await service.resetAllData(confirmation: 'LÖSCHEN');
        expect(outcome.notificationsCancelled, isTrue);
        expect(outcome.temporaryFilesDeleted, isFalse);
        expect(outcome.listenerNotified, isFalse);
        expect(
          await harness.database.select(harness.database.weightEntries).get(),
          isEmpty,
        );
      },
    );
  });

  group('atomicity', () {
    test(
      'a failure while re-creating the singletons rolls the reset back',
      () async {
        final failing = _FailingClock(harness.clock);
        final before = await dumpDatabase(harness.database);
        failing.failing = true;
        final guarded = ResetService(
          database: harness.database,
          clock: failing,
          notifications: canceller,
          listener: listener,
          files: files,
        );
        await expectLater(
          guarded.resetAllData(confirmation: 'LÖSCHEN'),
          throwsA(
            isA<StorageFailure>().having(
              (f) => f.causeType,
              'causeType',
              'StateError',
            ),
          ),
        );
        expect(await dumpDatabase(harness.database), before);
        expect(
          canceller.calls,
          0,
          reason: 'nothing was reset, nothing to cancel',
        );
        expect(listener.calls, 0);
        expect(files.deleteCalls, isEmpty);
      },
    );

    test('the failure carries no data', () async {
      final failing = _FailingClock(harness.clock)..failing = true;
      try {
        await ResetService(
          database: harness.database,
          clock: failing,
          notifications: canceller,
        ).resetAllData(confirmation: 'LÖSCHEN');
        fail('expected a StorageFailure');
      } on StorageFailure catch (failure) {
        expect(failure.toString(), 'StorageFailure(storage)');
        expect(failure.userMessage, isNot(contains('Mia')));
      }
    });

    test('a reset after a failed reset works', () async {
      final failing = _FailingClock(harness.clock)..failing = true;
      final guarded = ResetService(
        database: harness.database,
        clock: failing,
        notifications: canceller,
      );
      await expectLater(
        guarded.resetAllData(confirmation: 'LÖSCHEN'),
        throwsA(isA<StorageFailure>()),
      );
      failing.failing = false;
      await guarded.resetAllData(confirmation: 'LÖSCHEN');
      expect(
        await harness.database.select(harness.database.weightEntries).get(),
        isEmpty,
      );
      expect(canceller.calls, 1);
    });
  });
}
