import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/notifications/data/reminder_preferences_repository.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/shared/local_time.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late ReminderPreferencesRepository repository;

  setUp(() async {
    harness = await DataHarness.create();
    repository = ReminderPreferencesRepository(
      database: harness.database,
      runner: harness.runner,
    );
  });
  tearDown(() => harness.dispose());

  Future<List<ReminderRuleRow>> rules() => (harness.database.select(
    harness.database.reminderRules,
  )..orderBy([(r) => OrderingTerm.asc(r.localTime)])).get();

  Future<AppSettingsRow> settings() =>
      harness.database.select(harness.database.appSettings).getSingle();

  group('master switch', () {
    test('reminders are off by default', () async {
      expect(await repository.notificationsWanted(), isFalse);
    });

    test('switching on and off is stored and bumps the row version', () async {
      final before = (await settings()).rowVersion;
      await repository.setNotificationsEnabled(
        commandId: harness.ids.newId(),
        enabled: true,
      );
      expect(await repository.notificationsWanted(), isTrue);
      expect((await settings()).rowVersion, before + 1);

      await repository.setNotificationsEnabled(
        commandId: harness.ids.newId(),
        enabled: false,
      );
      expect(await repository.notificationsWanted(), isFalse);
      expect((await settings()).rowVersion, before + 2);
    });

    test('a retry with the same command id changes nothing twice', () async {
      const commandId = '11111111-1111-4111-8111-111111111111';
      final before = (await settings()).rowVersion;
      await repository.setNotificationsEnabled(
        commandId: commandId,
        enabled: true,
      );
      final replay = await repository.setNotificationsEnabled(
        commandId: commandId,
        enabled: true,
      );
      expect(replay.replayed, isTrue);
      expect((await settings()).rowVersion, before + 1);
    });

    test('it does not touch other settings', () async {
      final before = await settings();
      await repository.setNotificationsEnabled(
        commandId: harness.ids.newId(),
        enabled: true,
      );
      final after = await settings();
      expect(after.themeMode, before.themeMode);
      expect(after.haptics, before.haptics);
      expect(after.reduceMotion, before.reduceMotion);
      expect(after.lastKnownTimezone, before.lastKnownTimezone);
    });

    test('a missing settings row is a typed not found failure', () async {
      await harness.database.delete(harness.database.appSettings).go();
      await expectLater(
        repository.setNotificationsEnabled(
          commandId: harness.ids.newId(),
          enabled: true,
        ),
        throwsA(isA<NotFoundFailure>()),
      );
      expect(await repository.notificationsWanted(), isFalse);
    });
  });

  group('water slots', () {
    test('the offered slots are 10, 12, 14, 16 and 18 o\'clock', () {
      expect(ReminderPreferencesRepository.waterSlotHours, [
        10,
        12,
        14,
        16,
        18,
      ]);
    });

    test('none are enabled at first', () async {
      expect(await repository.enabledWaterHours(), isEmpty);
      expect(await rules(), isEmpty);
    });

    test('enabling slots stores one rule per slot', () async {
      await repository.setWaterSlots(
        commandId: harness.ids.newId(),
        hours: {10, 14},
      );
      final stored = await rules();
      expect(stored, hasLength(2));
      for (final rule in stored) {
        expect(rule.kind, 'water');
        expect(rule.moduleId, 'nutrition');
        expect(rule.route, '/water');
        expect(rule.enabled, isTrue);
      }
      expect(stored.map((r) => r.localTime), [
        const LocalTime(10, 0),
        const LocalTime(14, 0),
      ]);
      expect(await repository.enabledWaterHours(), {10, 14});
    });

    test('rule ids are UUID shaped', () async {
      await repository.setWaterSlots(
        commandId: harness.ids.newId(),
        hours: {10},
      );
      final id = (await rules()).single.id;
      expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    });

    test(
      'changing the selection keeps ids and disables the removed slot',
      () async {
        await repository.setWaterSlots(
          commandId: harness.ids.newId(),
          hours: {10, 14},
        );
        final before = {for (final r in await rules()) r.localTime!.hour: r.id};

        await repository.setWaterSlots(
          commandId: harness.ids.newId(),
          hours: {14, 18},
        );
        final after = await rules();
        expect(after, hasLength(3));
        final byHour = {for (final r in after) r.localTime!.hour: r};
        expect(byHour[10]!.enabled, isFalse);
        expect(byHour[10]!.id, before[10], reason: 'the row stays');
        expect(byHour[14]!.enabled, isTrue);
        expect(
          byHour[14]!.id,
          before[14],
          reason: 'unchanged slot keeps its id',
        );
        expect(byHour[18]!.enabled, isTrue);
        expect(await repository.enabledWaterHours(), {14, 18});
      },
    );

    test('an empty selection switches every slot off', () async {
      await repository.setWaterSlots(
        commandId: harness.ids.newId(),
        hours: {10, 12, 14, 16, 18},
      );
      expect(await repository.enabledWaterHours(), hasLength(5));
      await repository.setWaterSlots(
        commandId: harness.ids.newId(),
        hours: <int>{},
      );
      expect(await repository.enabledWaterHours(), isEmpty);
      expect(await rules(), hasLength(5));
    });

    test('re-enabling a slot reuses its row', () async {
      await repository.setWaterSlots(
        commandId: harness.ids.newId(),
        hours: {10},
      );
      final id = (await rules()).single.id;
      await repository.setWaterSlots(
        commandId: harness.ids.newId(),
        hours: <int>{},
      );
      await repository.setWaterSlots(
        commandId: harness.ids.newId(),
        hours: {10},
      );
      final rows = await rules();
      expect(rows, hasLength(1));
      expect(rows.single.id, id);
      expect(rows.single.enabled, isTrue);
    });

    test('a retry with the same command id adds nothing', () async {
      const commandId = '22222222-2222-4222-8222-222222222222';
      await repository.setWaterSlots(commandId: commandId, hours: {10, 12});
      await repository.setWaterSlots(commandId: commandId, hours: {10, 12});
      expect(await rules(), hasLength(2));
    });

    test(
      'an hour that is not offered is rejected and nothing is written',
      () async {
        for (final hours in [
          {9},
          {11},
          {19},
          {0},
          {24},
          {-1},
          {10, 13},
        ]) {
          await expectLater(
            repository.setWaterSlots(
              commandId: harness.ids.newId(),
              hours: hours,
            ),
            throwsA(isA<ValidationFailure>()),
            reason: '$hours',
          );
        }
        expect(await rules(), isEmpty);
        // The rejected command left no receipt behind either.
        expect(
          await harness.database.select(harness.database.commandReceipts).get(),
          isEmpty,
        );
      },
    );

    test('rules of other kinds and other times are ignored', () async {
      Future<void> insert(String id, String kind, LocalTime time) => harness
          .database
          .into(harness.database.reminderRules)
          .insert(
            ReminderRulesCompanion.insert(
              id: id,
              moduleId: kind == 'water' ? 'nutrition' : 'tasks',
              kind: kind,
              enabled: true,
              route: '/water',
              localTime: Value(time),
            ),
          );
      await insert('r-habit', 'habit', const LocalTime(10, 0));
      await insert('r-half', 'water', const LocalTime(10, 30));
      await insert('r-odd', 'water', const LocalTime(9, 0));
      await insert('r-ok', 'water', const LocalTime(12, 0));
      expect(await repository.enabledWaterHours(), {12});
    });

    test('rules that are not an offered slot are left untouched', () async {
      Future<void> insert(String id, LocalTime time) => harness.database
          .into(harness.database.reminderRules)
          .insert(
            ReminderRulesCompanion.insert(
              id: id,
              moduleId: 'nutrition',
              kind: 'water',
              enabled: true,
              route: '/water',
              localTime: Value(time),
            ),
          );
      await insert('r-half', const LocalTime(10, 30));
      await insert('r-nine', const LocalTime(9, 0));
      await repository.setWaterSlots(
        commandId: harness.ids.newId(),
        hours: {10},
      );
      await repository.setWaterSlots(
        commandId: harness.ids.newId(),
        hours: <int>{},
      );
      final byId = {for (final r in await rules()) r.id: r};
      expect(byId['r-half']!.enabled, isTrue);
      expect(byId['r-nine']!.enabled, isTrue);
      expect(byId, hasLength(3), reason: 'plus the 10:00 slot of its own');
      expect(await repository.enabledWaterHours(), isEmpty);
    });

    test('watch emits the enabled slots after each change', () async {
      final emissions = <Set<int>>[];
      final subscription = repository.watchEnabledWaterHours().listen(
        emissions.add,
      );
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(emissions.last, isEmpty);

      await repository.setWaterSlots(
        commandId: harness.ids.newId(),
        hours: {16},
      );
      await pumpEventQueue();
      expect(emissions.last, {16});
    });
  });
}
