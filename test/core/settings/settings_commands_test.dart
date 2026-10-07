import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/settings/app_settings_repository.dart';
import 'package:self_improvement/core/settings/settings_commands.dart';
import 'package:self_improvement/core/testing/data_harness.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late SettingsCommands commands;
  late AppSettingsRepository repository;

  setUp(() async {
    harness = await DataHarness.create();
    commands = SettingsCommands(
      database: harness.database,
      runner: harness.runner,
    );
    repository = AppSettingsRepository(harness.database);
  });
  tearDown(() => harness.dispose());

  test('theme mode accepts the four keys and rejects anything else', () async {
    for (final key in ['system', 'light', 'dark', 'oled']) {
      await commands.setThemeMode(
        commandId: harness.ids.newId(),
        themeModeKey: key,
      );
      expect((await repository.get())!.themeModeKey, key);
    }
    await expectLater(
      commands.setThemeMode(
        commandId: harness.ids.newId(),
        themeModeKey: 'neon',
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect((await repository.get())!.themeModeKey, 'oled');
  });

  test('motion, haptics, reminder wish and timezone are stored', () async {
    await commands.setReduceMotion(commandId: 'a', value: true);
    await commands.setHaptics(commandId: 'b', value: false);
    await commands.setNotificationsEnabled(commandId: 'c', value: true);
    await commands.setLastKnownTimezone(
      commandId: 'd',
      timezoneId: 'America/New_York',
    );
    final s = (await repository.get())!;
    expect(s.reduceMotion, isTrue);
    expect(s.haptics, isFalse);
    expect(s.notificationsEnabled, isTrue);
    expect(s.lastKnownTimezone, 'America/New_York');
    expect(s.rowVersion, 5, reason: 'every change bumps the version once');
  });

  test('replaying a command changes nothing', () async {
    await commands.setReduceMotion(commandId: 'r', value: true);
    await commands.setReduceMotion(commandId: 'r', value: false);
    expect((await repository.get())!.reduceMotion, isTrue);
  });

  test('defaults: system theme, haptics on, reminders off', () async {
    final s = (await repository.get())!;
    expect(s.themeModeKey, 'system');
    expect(s.haptics, isTrue);
    expect(s.reduceMotion, isFalse);
    expect(s.notificationsEnabled, isFalse);
  });

  test('the health wish is off by default and the time of the last '
      'comparison is empty (BS-97)', () async {
    final s = (await repository.get())!;
    expect(s.healthStepsSyncEnabled, isFalse);
    expect(s.healthStepsLastSyncAtUtc, isNull);
  });

  test('the health wish is stored and switched off again (BS-97)', () async {
    await commands.setHealthStepsSyncEnabled(commandId: 'h1', value: true);
    expect((await repository.get())!.healthStepsSyncEnabled, isTrue);
    await commands.setHealthStepsSyncEnabled(commandId: 'h2', value: false);
    expect((await repository.get())!.healthStepsSyncEnabled, isFalse);
  });

  test('the wish never touches the other settings and bumps the version '
      'once (BS-97)', () async {
    await commands.setReduceMotion(commandId: 'm', value: true);
    final before = (await repository.get())!;
    await commands.setHealthStepsSyncEnabled(commandId: 'h', value: true);
    final after = (await repository.get())!;
    expect(after.rowVersion, before.rowVersion + 1);
    expect(after.reduceMotion, isTrue);
    expect(after.notificationsEnabled, before.notificationsEnabled);
    expect(after.themeModeKey, before.themeModeKey);
    expect(after.healthStepsLastSyncAtUtc, isNull);
  });

  test('the time of the last comparison is stored to the minute in UTC '
      '(BS-97)', () async {
    await commands.setHealthStepsLastSyncAt(
      commandId: 't1',
      atUtc: DateTime.utc(2026, 10, 3, 8, 15, 42, 987),
    );
    expect(
      (await repository.get())!.healthStepsLastSyncAtUtc,
      DateTime.utc(2026, 10, 3, 8, 15),
    );
    // A local instant is stored as the same instant in UTC.
    await commands.setHealthStepsLastSyncAt(
      commandId: 't2',
      atUtc: DateTime.parse('2026-10-03T10:20:59+02:00'),
    );
    expect(
      (await repository.get())!.healthStepsLastSyncAtUtc,
      DateTime.utc(2026, 10, 3, 8, 20),
    );
  });

  test('minuteOf cuts seconds and milliseconds only (BS-97)', () {
    expect(
      SettingsCommands.minuteOf(DateTime.utc(2026, 10, 3, 23, 59, 59, 999)),
      DateTime.utc(2026, 10, 3, 23, 59),
    );
    expect(
      SettingsCommands.minuteOf(DateTime.utc(2026, 10, 3, 0, 0)),
      DateTime.utc(2026, 10, 3, 0, 0),
    );
  });

  test('replaying a health command changes nothing (BS-97)', () async {
    await commands.setHealthStepsSyncEnabled(commandId: 'r', value: true);
    await commands.setHealthStepsSyncEnabled(commandId: 'r', value: false);
    expect((await repository.get())!.healthStepsSyncEnabled, isTrue);
  });
}
