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
}
