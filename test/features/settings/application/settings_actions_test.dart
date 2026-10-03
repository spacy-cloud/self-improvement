import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/settings/app_settings_value.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/settings/application/settings_actions.dart';
import 'package:self_improvement/features/settings/application/settings_providers.dart';

import '../../profile/support/flaky_projection.dart';
import '../../profile/support/recording_commands.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late FlakyProjection projection;
  late RecordingSettingsCommands commands;
  late ProviderContainer container;

  ProviderContainer newContainer() {
    final created = harness.createContainer(
      overrides: [settingsCommandsProvider.overrideWithValue(commands)],
    );
    // The app shell keeps the settings alive; so do the tests.
    created.listen(appSettingsProvider, (_, _) {});
    return created;
  }

  setUp(() async {
    projection = FlakyProjection();
    harness = await DataHarness.create(projections: projection);
    await harness.seedOnboarded();
    commands = RecordingSettingsCommands(
      database: harness.database,
      runner: harness.runner,
    );
    container = newContainer();
    await container.read(appSettingsProvider.future);
  });
  tearDown(() => harness.dispose());

  SettingsActions actions() => container.read(settingsActionsProvider);

  /// Lets the stream deliver the committed row to the providers.
  Future<AppSettingsValue> settings() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final value = await container.read(appSettingsProvider.future);
    return value!;
  }

  group('defaults', () {
    test('follow the system, keep motion, haptics on', () async {
      final value = await settings();
      expect(value.themeModeKey, 'system');
      expect(value.reduceMotion, isFalse);
      expect(value.haptics, isTrue);
      expect(container.read(appThemeModeProvider), AppThemeMode.system);
      expect(container.read(reduceMotionProvider), isFalse);
      expect(container.read(hapticsEnabledProvider), isTrue);
    });

    test('an unknown stored theme falls back to the system theme', () {
      final unknown = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(
              const AppSettingsValue(
                themeModeKey: 'neon',
                reduceMotion: false,
                haptics: true,
                notificationsEnabled: false,
                rowVersion: 1,
              ),
            ),
          ),
        ],
      );
      addTearDown(unknown.dispose);
      unknown.listen(appSettingsProvider, (_, _) {});
      expect(unknown.read(appThemeModeProvider), AppThemeMode.system);
    });
  });

  group('theme (C06, AT35)', () {
    test(
      'every choice is saved and reaches AppTheme through the settings',
      () async {
        for (final mode in AppThemeMode.values) {
          expect(await actions().setThemeMode(mode), isA<SettingsSaved>());
          final value = await settings();
          expect(value.themeModeKey, mode.key);
          expect(container.read(appThemeModeProvider), mode);

          // What MaterialApp gets for a light and a dark device.
          final onLight = themeFor(
            container.read(appThemeModeProvider),
            Brightness.light,
          );
          final onDark = themeFor(
            container.read(appThemeModeProvider),
            Brightness.dark,
          );
          switch (mode) {
            case AppThemeMode.system:
              expect(identical(onLight, AppTheme.light()), isTrue);
              expect(
                identical(onDark, AppTheme.dark()),
                isTrue,
                reason: 'a dark device never gets OLED on its own',
              );
            case AppThemeMode.light:
              expect(identical(onLight, AppTheme.light()), isTrue);
              expect(identical(onDark, AppTheme.light()), isTrue);
            case AppThemeMode.dark:
              expect(identical(onLight, AppTheme.dark()), isTrue);
              expect(identical(onDark, AppTheme.dark()), isTrue);
            case AppThemeMode.oled:
              expect(identical(onLight, AppTheme.oled()), isTrue);
              expect(identical(onDark, AppTheme.oled()), isTrue);
          }
        }
      },
    );

    test('the three variants really look different (true black for OLED)', () {
      expect(AppTheme.oled().scaffoldBackgroundColor, const Color(0xFF000000));
      expect(
        AppTheme.dark().scaffoldBackgroundColor,
        isNot(AppTheme.oled().scaffoldBackgroundColor),
      );
      expect(
        AppTheme.light().scaffoldBackgroundColor,
        isNot(AppTheme.dark().scaffoldBackgroundColor),
      );
    });

    test('the MaterialApp theme mode follows the choice', () {
      expect(AppThemeMode.system.themeMode, ThemeMode.system);
      expect(AppThemeMode.light.themeMode, ThemeMode.light);
      expect(AppThemeMode.dark.themeMode, ThemeMode.dark);
      expect(AppThemeMode.oled.themeMode, ThemeMode.dark);
    });
  });

  group('reduced motion and haptics', () {
    test('are saved and visible through their providers', () async {
      await actions().setReduceMotion(value: true);
      await actions().setHaptics(value: false);
      final value = await settings();
      expect(value.reduceMotion, isTrue);
      expect(value.haptics, isFalse);
      expect(container.read(reduceMotionProvider), isTrue);
      expect(container.read(hapticsEnabledProvider), isFalse);
    });

    testWidgets('the saved switch reaches the motion of the whole app', (
      tester,
    ) async {
      await tester.runAsync(() => actions().setReduceMotion(value: true));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      Duration? standard;
      Duration? fast;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) => ReducedMotionScope(
              reduce: ref.watch(reduceMotionProvider),
              child: Builder(
                builder: (context) {
                  final motion = AppMotion.of(context);
                  standard = motion.standard;
                  fast = motion.fast;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      expect(standard, Duration.zero);
      expect(fast, Duration.zero);
    });

    test('haptic feedback only vibrates while the setting is on', () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              calls.add('${call.arguments}');
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final haptics = container.read(appHapticsProvider);

      await haptics.confirm();
      expect(calls, hasLength(1), reason: 'on by default');

      await actions().setHaptics(value: false);
      await settings();
      await haptics.confirm();
      expect(calls, hasLength(1), reason: 'switched off');

      await haptics.confirm(force: true);
      expect(calls, hasLength(2), reason: 'forced right after switching on');
    });

    test('a device without haptics never makes the action fail', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            throw PlatformException(code: 'unavailable');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await container.read(appHapticsProvider).confirm();
    });
  });

  group('persistence (AT02)', () {
    test('every setting survives a process restart', () async {
      await actions().setThemeMode(AppThemeMode.oled);
      await actions().setReduceMotion(value: true);
      await actions().setHaptics(value: false);
      await settings();

      container = newContainer(); // killed and started again
      final value = await settings();
      expect(value.themeModeKey, 'oled');
      expect(value.reduceMotion, isTrue);
      expect(value.haptics, isFalse);
      expect(container.read(appThemeModeProvider), AppThemeMode.oled);
    });
  });

  group('failures', () {
    test(
      'a failed write changes nothing and the retry reuses the command id',
      () async {
        projection.failure = StateError('disk full');
        final failed = await actions().setReduceMotion(value: true);
        expect(failed, isA<SettingsFailed>());
        expect((failed as SettingsFailed).failure, isA<StorageFailure>());
        expect((await settings()).reduceMotion, isFalse, reason: 'old value');
        final before = (await settings()).rowVersion;

        projection.failure = null;
        expect(
          await actions().setReduceMotion(value: true),
          isA<SettingsSaved>(),
        );
        expect(commands.commandIds, hasLength(2));
        expect(commands.commandIds[0], commands.commandIds[1]);
        final after = await settings();
        expect(after.reduceMotion, isTrue);
        expect(after.rowVersion, before + 1, reason: 'written once');
      },
    );

    test('a different value after a failure is a new action', () async {
      projection.failure = StateError('disk full');
      await actions().setReduceMotion(value: true);
      projection.failure = null;
      await actions().setReduceMotion(value: false);
      expect(commands.commandIds[0], isNot(commands.commandIds[1]));
    });

    test('a tap on a setting that is still being saved is ignored', () async {
      final first = actions().setReduceMotion(value: true);
      final second = actions().setReduceMotion(value: true);
      expect(await second, isA<SettingsBusy>());
      expect(await first, isA<SettingsSaved>());
      expect(commands.commandIds, hasLength(1));
    });

    test('different settings do not block each other', () async {
      final results = await Future.wait([
        actions().setThemeMode(AppThemeMode.dark),
        actions().setHaptics(value: false),
        actions().setReduceMotion(value: true),
      ]);
      expect(results.whereType<SettingsSaved>(), hasLength(3));
      final value = await settings();
      expect(value.themeModeKey, 'dark');
      expect(value.haptics, isFalse);
      expect(value.reduceMotion, isTrue);
    });
  });
}
