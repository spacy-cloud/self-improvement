import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/platform/fake_reminder_platform.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';

import '../../../support/pump_app.dart';
import '../support/task_test_support.dart';
import '../support/ui_support.dart';

/// The block "Erinnerung" of the task form in every state it can show, on the
/// four design widths, with 200 % text and in the three themes (BS-111,
/// AT33, AT34, AT35): it lays out without overflow, every control is at least
/// 48 by 48 and has a label, and the screen reader hears what the eye sees.
void main() {
  setUpAll(allowMultipleDatabases);

  /// One state of the block: the permission of the system, the wish of the
  /// user, whether the form edits a task that has a reminder, and the chip to
  /// tap in the new form.
  final states = <_State>[
    const _State('new form, no reminder'),
    const _State(
      'new form, reminder, reminders off',
      wanted: false,
      choose: 'Morgen 09:00',
    ),
    const _State(
      'new form, reminder, notifications not allowed',
      permission: NotificationPermission.denied,
      choose: 'Morgen 09:00',
    ),
    const _State(
      'new form, reminder, not available',
      permission: NotificationPermission.unavailable,
      choose: 'Morgen 09:00',
    ),
    const _State(
      'new form, reminder, planning error',
      planningError: true,
      choose: 'Morgen 09:00',
    ),
    const _State('new form, reminder, active', choose: 'Morgen 09:00'),
    const _State('edit form with a reminder', edit: true),
  ];

  Future<_Env> prepare(WidgetTester tester, _State state) async {
    final platform = FakeReminderPlatform(permission: state.permission);
    final env = await createTasksUiEnv(
      tester,
      extraOverrides: [reminderPlatformProvider.overrideWithValue(platform)],
    );
    addTearDown(platform.dispose);
    if (state.wanted) {
      await tester.runAsync(
        () => env.container
            .read(reminderPreferencesRepositoryProvider)
            .setNotificationsEnabled(
              commandId: env.harness.ids.newId(),
              enabled: true,
            ),
      );
    }
    String? taskId;
    if (state.edit || state.planningError) {
      final outcome = (await tester.runAsync(
        () => env.tasks.create(
          commandId: env.harness.ids.newId(),
          draft: TaskDraft(
            title: 'Präsentation Lernfeld zehn vorbereiten und abgeben',
            reminderAtUtc: DateTime.utc(2026, 10, 4, 7),
          ),
        ),
      ))!;
      taskId = outcome.entityId;
    }
    if (state.planningError) {
      platform.scheduleFailure = const ReminderPlatformException(
        PlatformFailureKind.failed,
      );
      await tester.runAsync(
        () => env.container.read(reminderServiceProvider).reconcile(),
      );
    }
    return _Env(env, state.edit ? '/tasks/$taskId' : '/tasks/new');
  }

  Future<void> show(
    WidgetTester tester,
    _Env e,
    _State state, {
    Size size = const Size(393, 852),
    double scale = 1.0,
    AppThemeVariant theme = AppThemeVariant.light,
  }) async {
    final router = await pumpRouterApp(
      tester,
      routes: [
        ...tasksUiRoutes(),
        GoRoute(
          path: '/settings',
          builder: (context, routeState) =>
              const Scaffold(body: Text('probe:settings')),
        ),
      ],
      initialLocation: '/habits',
      container: e.env.container,
      size: size,
      textScale: scale,
      theme: theme,
    );
    await pumpData(tester);
    unawaited(router.push(e.location));
    await tester.pumpAndSettle();
    await pumpData(tester);
    final label = state.choose;
    if (label != null) {
      final chip = find.widgetWithText(AppChoiceChip, label);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
      await pumpData(tester);
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('layout (AT33)', () {
    for (final scale in [1.0, 2.0]) {
      for (final state in states) {
        testWidgets(
          '${state.name} fits 320, 360, 393 and 430 px at ${scale}x text '
          '(BS-111)',
          (tester) async {
            final e = await prepare(tester, state);
            for (final size in responsiveSizes) {
              await show(tester, e, state, size: size, scale: scale);
              expect(
                tester.takeException(),
                isNull,
                reason: '${state.name} at ${size.width}x${size.height}',
              );
            }
          },
        );
      }
    }
  });

  group('tap targets and labels (AT33, AT34)', () {
    for (final scale in [1.0, 2.0]) {
      for (final state in states) {
        testWidgets(
          '${state.name} has 48 px targets with labels at ${scale}x text '
          '(BS-111)',
          (tester) async {
            final handle = tester.ensureSemantics();
            final e = await prepare(tester, state);
            // The guidelines measure what is visible, and a control cut by the
            // edge of the scroll area is measured as cut. A tall screen shows
            // the whole form, so every control is measured whole.
            for (final width in [320.0, 430.0]) {
              await show(
                tester,
                e,
                state,
                size: Size(width, 3200),
                scale: scale,
              );
              await expectLater(
                tester,
                meetsGuideline(androidTapTargetGuideline),
              );
              await expectLater(
                tester,
                meetsGuideline(labeledTapTargetGuideline),
              );
            }
            handle.dispose();
          },
        );
      }
    }
  });

  group('themes (AT35)', () {
    for (final theme in AppThemeVariant.values) {
      for (final state in states) {
        testWidgets('${state.name} works in the ${theme.name} theme '
            '(BS-111)', (tester) async {
          final handle = tester.ensureSemantics();
          final e = await prepare(tester, state);
          await show(tester, e, state, theme: theme);
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          handle.dispose();
        });
      }
    }
  });

  group('screen reader (AT34)', () {
    testWidgets('the choices are one group; the chosen one is selected and the '
        'field and the notice are read as one message each (BS-111)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      const state = _State(
        'blocked',
        permission: NotificationPermission.denied,
        choose: 'Heute 18:00',
      );
      final e = await prepare(tester, state);
      await show(tester, e, state);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Heute 18:00 Uhr')),
        isSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Morgen 09:00 Uhr')),
        isSemantics(
          isButton: true,
          hasSelectedState: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      expect(find.bySemanticsLabel('Keine Erinnerung'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Zeitpunkt der Erinnerung wählen, Samstag, 3. Oktober, 18:00 Uhr',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Benachrichtigungen sind nicht erlaubt. Die Aufgabe wird gespeichert. '
          'Die Erinnerung kommt erst an, wenn du Benachrichtigungen in den '
          'Systemeinstellungen erlaubst.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Systemeinstellungen für Benachrichtigungen öffnen',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('"Erinnerung entfernen" is a button with its own label in the '
        'edit form (BS-111)', (tester) async {
      final handle = tester.ensureSemantics();
      const state = _State('edit', edit: true);
      final e = await prepare(tester, state);
      await show(tester, e, state);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Erinnerung entfernen')),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });
}

class _State {
  const _State(
    this.name, {
    this.permission = NotificationPermission.granted,
    this.wanted = true,
    this.choose,
    this.edit = false,
    this.planningError = false,
  });

  final String name;
  final NotificationPermission permission;
  final bool wanted;

  /// The chip to tap once the new form is open; null taps nothing.
  final String? choose;

  /// Open the edit form of a task that has a reminder.
  final bool edit;

  /// Make the engine fail once, so the status says "Planungsfehler".
  final bool planningError;
}

class _Env {
  const _Env(this.env, this.location);

  final TasksUiEnv env;
  final String location;
}
