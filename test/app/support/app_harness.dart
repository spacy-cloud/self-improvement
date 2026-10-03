import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/app.dart';
import 'package:self_improvement/app/bootstrap/app_services.dart';
import 'package:self_improvement/app/bootstrap/bootstrap_screens.dart';
import 'package:self_improvement/app/router/app_router.dart';
import 'package:self_improvement/app/router/navigation.dart';
import 'package:self_improvement/app/shell/plus_sheet.dart';
import 'package:self_improvement/core/backup/backup_providers.dart';
import 'package:self_improvement/core/backup/testing/in_memory_backup_adapters.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/platform/device_time_zone.dart';
import 'package:self_improvement/core/notifications/platform/fake_reminder_platform.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';

import '../../support/pump_app.dart';

/// The device zone of the host tests.
final class FixedZoneSource implements DeviceTimeZoneSource {
  const FixedZoneSource([this.zoneId = 'Europe/Berlin']);

  final String zoneId;

  @override
  Future<String?> currentZoneId() async => zoneId;
}

/// A running app on the in-memory database of a [DataHarness].
class AppFixture {
  AppFixture({
    required this.tester,
    required this.harness,
    required this.platform,
    required this.backupFiles,
  });

  final WidgetTester tester;
  final DataHarness harness;
  final FakeReminderPlatform platform;
  final InMemoryBackupFileGateway backupFiles;

  /// The app's provider container.
  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

  GoRouter get router => container.read(appRouterProvider);

  /// The location of the top-most page.
  String get location => currentPath(router);

  /// The full location including the query.
  String get fullLocation =>
      router.routerDelegate.currentConfiguration.uri.toString();

  /// Runs [action] (a command on the real database) and lets the streams and
  /// widgets catch up.
  Future<T> run<T>(Future<T> Function() action) => tester.runCommand(action);

  /// Lets pending streams and frames settle.
  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Presses the system back button.
  Future<bool> systemBack() async {
    final handled = await tester.binding.handlePopRoute().then((_) => true);
    await settle();
    return handled;
  }
}

/// Starts the whole app (bootstrap, router, shell) on an in-memory database
/// and waits until the real app is on screen.
Future<AppFixture> pumpFullApp(
  WidgetTester tester, {
  bool onboarded = true,
  Set<String>? enabledModules,
  List<SelfImprovementModule>? modules,
  AppTabBuilders tabs = const AppTabBuilders(),
  Size size = const Size(393, 852),
  double textScale = 1.0,
  EdgeInsets viewInsets = EdgeInsets.zero,
  String nowIso = '2026-10-03T08:00:00Z',
  List<Override> overrides = const <Override>[],
  Future<AppServices> Function(DataHarness harness)? starter,
  bool waitForReady = true,
}) async {
  final harness = await createTestHarness(
    tester,
    onboarded: onboarded,
    enabledModules: enabledModules,
    nowIso: nowIso,
  );
  final platform = FakeReminderPlatform(clock: harness.clock);
  final backupFiles = InMemoryBackupFileGateway();
  await tester.runAsync(loadInterFont);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = FakeViewPadding(bottom: viewInsets.bottom);
  addTearDown(tester.view.reset);
  final app = SelfImprovementApp(
    starter: starter == null
        ? () async => AppServices(
            database: harness.database,
            clock: harness.clock,
            zoneSource: const FixedZoneSource(),
            dispose: () async {},
          )
        : () => starter(harness),
    modules: modules ?? bundledModules,
    tabs: tabs,
    overrides: <Override>[
      reminderPlatformProvider.overrideWithValue(platform),
      backupFileGatewayProvider.overrideWithValue(backupFiles),
      idGeneratorProvider.overrideWithValue(harness.ids),
      ...overrides,
    ],
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: appBoundaryKey,
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: app,
        ),
      ),
    ),
  );
  final fixture = AppFixture(
    tester: tester,
    harness: harness,
    platform: platform,
    backupFiles: backupFiles,
  );
  if (waitForReady) {
    await tester.pumpUntil(
      () =>
          find.byType(BootstrapLoadingScreen).evaluate().isEmpty &&
          find.byType(BootstrapErrorScreen).evaluate().isEmpty,
      reason: 'the app did not leave the bootstrap screens',
    );
    await fixture.settle();
  }
  return fixture;
}

/// The plus button of the navigation bar.
Finder plusButton() => find.descendant(
  of: find.byType(AppBottomNavBar),
  matching: find.byIcon(AppIcon.plus.data),
);

/// The navigation tab with [label].
Finder navTab(String label) => find.descendant(
  of: find.byType(AppBottomNavBar),
  matching: find.text(label),
);

/// The plus menu.
Finder plusSheet() => find.byType(PlusSheet);
