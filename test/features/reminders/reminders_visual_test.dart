import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';

import '../../support/pump_app.dart';
import 'reminder_test_support.dart';

/// Renders the reminders block and the permission sheet to PNG files below
/// `build/screens/reminders/` for the comparison with the Figma frames (the
/// folder is ignored by git). The test only fails when rendering throws.
void main() {
  Future<void> shot(WidgetTester tester, String name) =>
      savePng(tester, 'build/screens/reminders/$name.png');

  for (final spec in <(String, double, double, double)>[
    ('393', 393, 852, 1.0),
    ('320_x2', 320, 640, 2.0),
  ]) {
    testWidgets('renders the states at ${spec.$1}', (tester) async {
      final env = await createReminderEnv(
        tester,
        permission: NotificationPermission.denied,
        afterRequest: NotificationPermission.denied,
      );
      final size = Size(spec.$2, spec.$3);
      await openSettings(tester, env, size: size, textScale: spec.$4);
      await shot(tester, 'off_${spec.$1}');
      expect(tester.takeException(), isNull);

      await tapMasterSwitch(tester);
      await shot(tester, 'sheet_${spec.$1}');
      expect(tester.takeException(), isNull);

      await tapText(tester, 'Weiter zur Android-Abfrage');
      await shot(tester, 'blocked_${spec.$1}');
      expect(tester.takeException(), isNull);

      env.platform.permission = NotificationPermission.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      await tapSlot(tester, 12);
      await tapSlot(tester, 14);
      await tapText(tester, 'Geplante Erinnerungen');
      await shot(tester, 'active_${spec.$1}');
      expect(tester.takeException(), isNull);

      env.platform.scheduleFailure = const ReminderPlatformException(
        PlatformFailureKind.failed,
      );
      await tapSlot(tester, 16);
      await shot(tester, 'error_${spec.$1}');
      expect(tester.takeException(), isNull);
    });
  }
}
