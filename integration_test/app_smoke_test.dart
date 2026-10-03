import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:self_improvement/app/app.dart';
import 'package:self_improvement/app/bootstrap/app_services.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/platform/device_time_zone.dart';
import 'package:self_improvement/core/notifications/platform/fake_reminder_platform.dart';
import 'package:self_improvement/core/testing/data_harness.dart';

/// Smoke test for the emulator job: the app starts on an in-memory database
/// (already past the onboarding), the four tabs can be switched and the plus
/// menu opens and closes. The real database file, the real notification plugin
/// and the onboarding are covered by the host tests and by manual checks.
final class _BerlinZone implements DeviceTimeZoneSource {
  const _BerlinZone();

  @override
  Future<String?> currentZoneId() async => 'Europe/Berlin';
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app starts and the tabs and the plus menu work', (
    tester,
  ) async {
    final harness = await DataHarness.create();
    await harness.seedOnboarded();
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      SelfImprovementApp(
        starter: () async => AppServices(
          database: harness.database,
          clock: harness.clock,
          zoneSource: const _BerlinZone(),
          dispose: () async {},
        ),
        overrides: [
          reminderPlatformProvider.overrideWithValue(
            FakeReminderPlatform(clock: harness.clock),
          ),
        ],
      ),
    );
    final navigation = find.byType(AppBottomNavBar);
    await _pumpUntilFound(tester, navigation);

    for (final label in <String>['Analyse', 'Habits', 'Profil', 'Home']) {
      await tester.tap(
        find.descendant(of: navigation, matching: find.text(label)),
      );
      await tester.pumpAndSettle();
      expect(navigation, findsOneWidget);
    }

    await tester.tap(
      find.descendant(of: navigation, matching: find.byIcon(AppIcon.plus.data)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Was möchtest du eintragen?'), findsOneWidget);
    await tester.tap(find.byIcon(AppIcon.close.data));
    await tester.pumpAndSettle();
    expect(find.text('Was möchtest du eintragen?'), findsNothing);
  });
}
