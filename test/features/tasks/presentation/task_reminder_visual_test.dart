import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/platform/fake_reminder_platform.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';

import '../../../support/pump_app.dart';
import '../support/task_test_support.dart';
import '../support/ui_support.dart';

/// Writes the four states of the block "Erinnerung" as PNGs below the
/// git-ignored `build/screens/` for the comparison with the Figma frames
/// 4121:314, 4121:414, 4121:517 and 4121:621 (BS-111). The frames are 393 px
/// wide; the screens are rendered on a tall screen so the whole form shows.
/// These tests check nothing but that the screens render.
void main() {
  setUpAll(allowMultipleDatabases);

  Future<void> render(
    WidgetTester tester, {
    required String name,
    required String location,
    NotificationPermission permission = NotificationPermission.granted,
    String? choose,
    bool seedTask = false,
    double textScale = 1.0,
    Size size = const Size(393, 1100),
    AppThemeVariant theme = AppThemeVariant.light,
  }) async {
    final platform = FakeReminderPlatform(permission: permission);
    final env = await createTasksUiEnv(
      tester,
      extraOverrides: [reminderPlatformProvider.overrideWithValue(platform)],
    );
    addTearDown(platform.dispose);
    await tester.runAsync(
      () => env.container
          .read(reminderPreferencesRepositoryProvider)
          .setNotificationsEnabled(
            commandId: env.harness.ids.newId(),
            enabled: true,
          ),
    );
    var path = location;
    if (seedTask) {
      final outcome = (await tester.runAsync(
        () => env.tasks.create(
          commandId: env.harness.ids.newId(),
          draft: TaskDraft(
            title: 'Figma-Prototyp verlinken',
            reminderAtUtc: DateTime.utc(2026, 10, 3, 16),
          ),
        ),
      ))!;
      path = '/tasks/${outcome.entityId}';
    }
    final router = await pumpRouterApp(
      tester,
      routes: tasksUiRoutes(),
      initialLocation: '/habits',
      container: env.container,
      size: size,
      textScale: textScale,
      theme: theme,
    );
    await pumpData(tester);
    unawaited(router.push(path));
    await tester.pumpAndSettle();
    await pumpData(tester);
    if (location == '/tasks/new') {
      await tester.enterText(
        find.byType(TextField).first,
        'Figma-Prototyp verlinken',
      );
    }
    if (choose != null) {
      await tester.tap(find.widgetWithText(AppChoiceChip, choose));
      await tester.pump();
      await pumpData(tester);
    }
    await tester.pump(const Duration(milliseconds: 300));
    await savePng(tester, 'build/screens/task-reminder-$name.png');
  }

  testWidgets('create, no reminder (4121:314)', (tester) async {
    await render(tester, name: 'create-off', location: '/tasks/new');
  });

  testWidgets('create, reminder on (4121:414)', (tester) async {
    await render(
      tester,
      name: 'create-on',
      location: '/tasks/new',
      choose: 'Heute 18:00',
    );
  });

  testWidgets('edit, change or remove (4121:517)', (tester) async {
    await render(tester, name: 'edit', location: '/tasks/x', seedTask: true);
  });

  testWidgets('create, notifications not allowed (4121:621)', (tester) async {
    await render(
      tester,
      name: 'create-blocked',
      location: '/tasks/new',
      permission: NotificationPermission.denied,
      choose: 'Heute 18:00',
    );
  });

  testWidgets('create, notifications not allowed, 200 % at 320 px', (
    tester,
  ) async {
    await render(
      tester,
      name: 'create-blocked-200',
      location: '/tasks/new',
      permission: NotificationPermission.denied,
      choose: 'Heute 18:00',
      textScale: 2.0,
      size: const Size(320, 2600),
    );
  });

  testWidgets('create, notifications not allowed, dark', (tester) async {
    await render(
      tester,
      name: 'create-blocked-dark',
      location: '/tasks/new',
      permission: NotificationPermission.denied,
      choose: 'Heute 18:00',
      theme: AppThemeVariant.dark,
    );
  });
}
