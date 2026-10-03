import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/data/reminder_input_reader.dart';
import 'package:self_improvement/core/notifications/domain/reminder_inputs.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/reminder_harness.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late ReminderHarness harness;
  late ReminderInputReader reader;
  var waterReached = false;

  setUp(() async {
    harness = await ReminderHarness.create();
    waterReached = false;
    reader = ReminderInputReader(
      database: harness.database,
      modules: harness.data.moduleStatus,
      waterGoalReachedToday: () async => waterReached,
    );
  });
  tearDown(() => harness.dispose());

  Future<ReminderInputs> read({
    NotificationPermission permission = NotificationPermission.granted,
  }) => reader.read(
    nowUtc: harness.data.clock.nowUtc(),
    timeZoneId: 'Europe/Berlin',
    permission: permission,
  );

  test('a fresh installation: reminders off, nothing configured', () async {
    final inputs = await read();
    expect(inputs.remindersWanted, isFalse);
    expect(inputs.waterRules, isEmpty);
    expect(inputs.habits, isEmpty);
    expect(inputs.focusSession, isNull);
    expect(inputs.waterGoalReachedToday, isFalse);
    // Without any module history all five modules count as enabled.
    expect(inputs.enabledModules, ModuleId.values.toSet());
  });

  test('passes through the instant, zone and the device permission', () async {
    final inputs = await read(permission: NotificationPermission.denied);
    expect(inputs.nowUtc, DateTime.utc(2026, 10, 3, 6, 30));
    expect(inputs.timeZoneId, 'Europe/Berlin');
    expect(inputs.permission, NotificationPermission.denied);
  });

  test('reads the master switch', () async {
    await harness.setWanted(true);
    expect((await read()).remindersWanted, isTrue);
    await harness.setWanted(false);
    expect((await read()).remindersWanted, isFalse);
  });

  test('reads the module statuses', () async {
    await harness.setModule(ModuleId.focus, enabled: false);
    await harness.setModule(ModuleId.nutrition, enabled: false);
    final inputs = await read();
    expect(inputs.isModuleEnabled(ModuleId.focus), isFalse);
    expect(inputs.isModuleEnabled(ModuleId.nutrition), isFalse);
    expect(inputs.isModuleEnabled(ModuleId.tasks), isTrue);

    harness.data.clock.advance(const Duration(minutes: 1));
    await harness.setModule(ModuleId.focus, enabled: true);
    expect((await read()).isModuleEnabled(ModuleId.focus), isTrue);
  });

  test('asks the injected water goal fact', () async {
    waterReached = true;
    expect((await read()).waterGoalReachedToday, isTrue);
    waterReached = false;
    expect((await read()).waterGoalReachedToday, isFalse);
  });

  test(
    'a water goal fact that cannot be answered counts as not reached',
    () async {
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = original);
      final failing = ReminderInputReader(
        database: harness.database,
        modules: harness.data.moduleStatus,
        waterGoalReachedToday: () async => throw StateError('day status'),
      );
      final inputs = await failing.read(
        nowUtc: harness.data.clock.nowUtc(),
        timeZoneId: 'Europe/Berlin',
        permission: NotificationPermission.granted,
      );
      expect(inputs.waterGoalReachedToday, isFalse);
    },
  );

  group('water rules', () {
    test('maps kind water with its time and enabled flag', () async {
      await harness.setWaterHours({10, 14});
      await harness.setWaterHours({10});
      final rules = (await read()).waterRules;
      expect(rules, hasLength(2));
      final byHour = {for (final r in rules) r.time.hour: r};
      expect(byHour[10]!.enabled, isTrue);
      expect(byHour[14]!.enabled, isFalse);
      expect(byHour[10]!.time, const LocalTime(10, 0));
    });

    test('ignores rules of other kinds and rules without a time', () async {
      Future<void> rule(String id, String kind, LocalTime? time) => harness
          .database
          .into(harness.database.reminderRules)
          .insert(
            ReminderRulesCompanion.insert(
              id: id,
              moduleId: 'tasks',
              kind: kind,
              enabled: true,
              route: '/habits',
              localTime: Value(time),
            ),
          );
      await rule('habit-rule', 'habit', const LocalTime(9, 0));
      await rule('no-time', 'water', null);
      await rule('good', 'water', const LocalTime(12, 0));
      final rules = (await read()).waterRules;
      expect(rules.map((r) => r.id), ['good']);
    });
  });

  group('habits', () {
    test('maps start, archive date, time and soft delete', () async {
      final active = await harness.addHabit(
        time: const LocalTime(7, 30),
        started: LocalDate(2026, 9, 1),
      );
      final archived = await harness.addHabit(
        archivedFrom: LocalDate(2026, 10, 4),
      );
      final deleted = await harness.addHabit(deleted: true);
      final habits = {for (final h in (await read()).habits) h.id: h};
      expect(habits, hasLength(3));
      expect(habits[active]!.reminderTime, const LocalTime(7, 30));
      expect(habits[active]!.startedOn, LocalDate(2026, 9, 1));
      expect(habits[active]!.archivedFrom, isNull);
      expect(habits[active]!.deleted, isFalse);
      expect(habits[archived]!.archivedFrom, LocalDate(2026, 10, 4));
      expect(habits[deleted]!.deleted, isTrue);
    });

    test('habits without a reminder time are not read', () async {
      await harness.addHabit(time: null);
      expect((await read()).habits, isEmpty);
    });

    test('the habit title is never part of the inputs', () async {
      await harness.addHabit(title: 'Geheime Gewohnheit');
      final habit = (await read()).habits.single;
      expect(habit.toString(), isNot(contains('Geheime')));
    });
  });

  group('open focus session', () {
    test('a running session carries its persisted segment', () async {
      final id = await harness.addFocus(
        planned: 1800,
        accumulated: 300,
        segmentStart: DateTime.utc(2026, 10, 3, 6, 10),
      );
      final focus = (await read()).focusSession!;
      expect(focus.sessionId, id);
      expect(focus.status, OpenFocusStatus.running);
      expect(focus.plannedSeconds, 1800);
      expect(focus.accumulatedSeconds, 300);
      expect(focus.segmentStartedAtUtc, DateTime.utc(2026, 10, 3, 6, 10));
      expect(focus.endsAtUtc, DateTime.utc(2026, 10, 3, 6, 35));
    });

    test('a paused session has no end', () async {
      await harness.addFocus(status: 'paused', accumulated: 600);
      final focus = (await read()).focusSession!;
      expect(focus.status, OpenFocusStatus.paused);
      expect(focus.endsAtUtc, isNull);
    });

    test('a session awaiting confirmation is open but has no end', () async {
      await harness.addFocus(
        status: 'awaiting_confirmation',
        accumulated: 1500,
      );
      final focus = (await read()).focusSession!;
      expect(focus.status, OpenFocusStatus.awaitingConfirmation);
      expect(focus.endsAtUtc, isNull);
    });

    test('completed and discarded sessions are not open', () async {
      final id = await harness.addFocus(
        segmentStart: DateTime.utc(2026, 10, 3, 6),
      );
      await harness.closeFocus(id, completed: true);
      expect((await read()).focusSession, isNull);

      final second = await harness.addFocus(
        segmentStart: DateTime.utc(2026, 10, 3, 6, 5),
      );
      await harness.closeFocus(second, completed: false);
      expect((await read()).focusSession, isNull);
    });

    test('a soft deleted open session is ignored', () async {
      final id = await harness.addFocus(
        segmentStart: DateTime.utc(2026, 10, 3, 6),
      );
      await (harness.database.update(
        harness.database.focusSessions,
      )..where((s) => s.id.equals(id))).write(
        FocusSessionsCompanion(
          deletedAtUtc: Value(harness.data.clock.nowUtc()),
        ),
      );
      expect((await read()).focusSession, isNull);
    });

    test('the focus input can be injected', () async {
      final injected = FocusEndInput(
        sessionId: 'injected',
        status: OpenFocusStatus.running,
        plannedSeconds: 600,
        accumulatedSeconds: 0,
        segmentStartedAtUtc: DateTime.utc(2026, 10, 3, 6),
      );
      final custom = ReminderInputReader(
        database: harness.database,
        modules: harness.data.moduleStatus,
        waterGoalReachedToday: () async => false,
        focusSession: () async => injected,
      );
      final inputs = await custom.read(
        nowUtc: harness.data.clock.nowUtc(),
        timeZoneId: 'Europe/Berlin',
        permission: NotificationPermission.granted,
      );
      expect(inputs.focusSession, same(injected));
    });
  });
}
