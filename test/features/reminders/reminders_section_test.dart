import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/data/reminder_preferences_repository.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/reminder_texts.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/core/providers/core_providers.dart';

import 'reminder_test_support.dart';

/// Widget tests of the reminders block against a real in-memory database, the
/// real reminder engine and a fake of the operating system (clock 2026-10-03
/// 10:00 Europe/Berlin: the 12:00 water slot is the next one of the day).
void main() {
  Tristate toggled(WidgetTester tester, String label) => tester
      .getSemantics(find.bySemanticsLabel(label))
      .flagsCollection
      .isToggled;

  group('off by default', () {
    testWidgets(
      'nothing asks for the permission and the state is honest (AT28, C08)',
      (tester) async {
        final handle = tester.ensureSemantics();
        final env = await createReminderEnv(
          tester,
          permission: NotificationPermission.denied,
        );
        await openSettings(tester, env);

        expect(find.text('Erinnerungen'), findsOneWidget);
        expect(find.text('Aus'), findsOneWidget);
        expect(toggled(tester, 'Erinnerungen, Aus'), Tristate.isFalse);
        expect(find.textContaining('noch nicht erlaubt'), findsOneWidget);
        expect(find.textContaining('Android fragt erst'), findsOneWidget);
        expect(find.text('Benachrichtigungen sind blockiert'), findsNothing);
        expect(find.text('Erinnerungen erlauben?'), findsNothing);
        expect(find.textContaining('Planungsfehler'), findsNothing);
        // No delivery promise while reminders are off, and no cloud or account.
        expect(find.textContaining('ungenau getaktet'), findsNothing);
        expect(find.textContaining('Cloud'), findsNothing);
        expect(find.textContaining('Konto'), findsNothing);
        expect(env.platform.requestPermissionCalls, 0);
        expect(env.platform.scheduleCalls, isEmpty);
        expect(await env.wanted(tester), isFalse);
        handle.dispose();
      },
    );

    testWidgets('the five water slots are offered and none is selected', (
      tester,
    ) async {
      final env = await createReminderEnv(tester);
      await openSettings(tester, env);

      for (final hour in <int>[10, 12, 14, 16, 18]) {
        expect(find.text('$hour:00'), findsOneWidget);
      }
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(
        find.text('Keine Uhrzeit gewählt: Es gibt keine Trink-Erinnerungen.'),
        findsOneWidget,
      );
    });
  });

  group('switching on', () {
    testWidgets(
      'with the permission granted no sheet appears and reminders are planned (C08)',
      (tester) async {
        final env = await createReminderEnv(tester);
        await openSettings(tester, env);
        await tapSlot(tester, 12);
        await tapSlot(tester, 14);
        expect(env.platform.scheduleCalls, isEmpty, reason: 'still off');

        await tapMasterSwitch(tester);

        expect(find.text('Erinnerungen erlauben?'), findsNothing);
        expect(env.platform.requestPermissionCalls, 0);
        expect(await env.wanted(tester), isTrue);
        // Today 12:00 and 14:00, then six more days of both slots.
        expect(env.platform.alarms, hasLength(14));
        expect(find.text('Eingeschaltet, 14 geplant'), findsOneWidget);
        expect(
          find.textContaining('lokal und ungenau getaktet'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Systemstatus: Benachrichtigungen sind erlaubt.'),
          findsOneWidget,
        );
        expect(env.feedback.last!.kind, 'saved');
        expect(env.feedback.last!.message, 'Erinnerungen eingeschaltet.');
      },
    );

    testWidgets('without slots, habits or a session nothing is planned', (
      tester,
    ) async {
      final env = await createReminderEnv(tester);
      await openSettings(tester, env);

      await tapMasterSwitch(tester);

      expect(
        find.text('Eingeschaltet, aktuell nichts geplant'),
        findsOneWidget,
      );
      expect(find.textContaining('Aktuell ist nichts geplant'), findsOneWidget);
      expect(env.platform.alarms, isEmpty);
    });

    testWidgets(
      'denied: the sheet explains first, the system dialog only after "Weiter" (AT28, C08)',
      (tester) async {
        final env = await createReminderEnv(
          tester,
          permission: NotificationPermission.denied,
        );
        await openSettings(tester, env);

        await tapMasterSwitch(tester);

        expect(find.text('Erinnerungen erlauben?'), findsOneWidget);
        expect(
          find.textContaining('nur an das, was du einschaltest'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Android-Status: Benachrichtigungen sind für diese App nicht erlaubt.',
          ),
          findsOneWidget,
        );
        expect(env.platform.requestPermissionCalls, 0, reason: 'not asked yet');
        expect(await env.wanted(tester), isFalse);

        await tapText(tester, 'Weiter zur Android-Abfrage');

        expect(env.platform.requestPermissionCalls, 1);
        expect(find.text('Erinnerungen erlauben?'), findsNothing);
        expect(await env.wanted(tester), isTrue);
        expect(
          find.text('Eingeschaltet, aktuell nichts geplant'),
          findsOneWidget,
        );
        expect(env.feedback.last!.kind, 'saved');
      },
    );

    for (final (name, close) in <(String, Future<void> Function(WidgetTester))>[
      ('"Später"', (t) => tapText(t, 'Später')),
      (
        'the close button',
        (t) async {
          await t.tap(find.byType(AppIconButton).last);
          await settle(t);
        },
      ),
      (
        'the system back action',
        (t) async {
          await t.binding.handlePopRoute();
          await settle(t);
        },
      ),
    ]) {
      testWidgets('closing the sheet with $name keeps reminders off (AT28)', (
        tester,
      ) async {
        final env = await createReminderEnv(
          tester,
          permission: NotificationPermission.denied,
        );
        await openSettings(tester, env);

        await tapMasterSwitch(tester);
        expect(find.text('Erinnerungen erlauben?'), findsOneWidget);
        await close(tester);

        expect(find.text('Erinnerungen erlauben?'), findsNothing);
        expect(env.platform.requestPermissionCalls, 0);
        expect(env.platform.openSettingsCalls, 0);
        expect(await env.wanted(tester), isFalse);
        expect(find.text('Aus'), findsOneWidget);
        expect(env.feedback.events, isEmpty);
      });
    }

    testWidgets('an unreadable status is told in the sheet', (tester) async {
      final env = await createReminderEnv(
        tester,
        permission: NotificationPermission.unavailable,
      );
      await openSettings(tester, env);

      await tapMasterSwitch(tester);

      expect(
        find.textContaining(
          'Android-Status: Der Status der Benachrichtigungen ist nicht '
          'verfügbar',
        ),
        findsOneWidget,
      );
    });
  });

  group('permission refused', () {
    testWidgets(
      'blocked state with the way to the system settings, the app stays usable (AT28, C08)',
      (tester) async {
        final handle = tester.ensureSemantics();
        final env = await createReminderEnv(
          tester,
          permission: NotificationPermission.denied,
          afterRequest: NotificationPermission.denied,
        );
        await openSettings(tester, env);

        await tapMasterSwitch(tester);
        await tapText(tester, 'Weiter zur Android-Abfrage');

        expect(env.platform.requestPermissionCalls, 1);
        expect(find.text('Im System blockiert'), findsOneWidget);
        expect(find.text('Benachrichtigungen sind blockiert'), findsOneWidget);
        expect(
          find.textContaining('Erlaube sie in den Android-Einstellungen'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Systemstatus: Benachrichtigungen sind blockiert',
          ),
          findsOneWidget,
        );
        // The wish stays on, nothing is planned, nothing claims delivery.
        expect(await env.wanted(tester), isTrue);
        expect(
          toggled(tester, 'Erinnerungen, Im System blockiert'),
          Tristate.isTrue,
        );
        expect(env.platform.scheduleCalls, isEmpty);
        expect(env.feedback.last!.kind, 'info');
        expect(env.feedback.last!.message, contains('Android blockiert'));
        // The rest of the block still works.
        await tapSlot(tester, 14);
        expect(await env.waterHours(tester), {14});

        expect(env.platform.openSettingsCalls, 0);
        await tapText(tester, 'Öffnen');
        expect(env.platform.openSettingsCalls, 1);
        handle.dispose();
      },
    );

    testWidgets(
      'the system settings can be chosen in the sheet itself (AT28)',
      (tester) async {
        final env = await createReminderEnv(
          tester,
          permission: NotificationPermission.denied,
          afterRequest: NotificationPermission.denied,
        );
        await openSettings(tester, env);
        await tapSlot(tester, 12);

        await tapMasterSwitch(tester);
        await tapText(tester, 'Einstellungen öffnen');

        expect(
          env.platform.requestPermissionCalls,
          0,
          reason: 'no system dialog',
        );
        expect(env.platform.openSettingsCalls, 1);
        expect(await env.wanted(tester), isTrue);
        expect(find.text('Im System blockiert'), findsOneWidget);

        // The user grants the permission in the system settings and comes back.
        env.platform.permission = NotificationPermission.granted;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle(tester);

        expect(find.text('Im System blockiert'), findsNothing);
        expect(find.text('Eingeschaltet, 7 geplant'), findsOneWidget);
        expect(env.platform.alarms, hasLength(7));
      },
    );

    testWidgets(
      'permission granted later: planning works after returning (AT28)',
      (tester) async {
        final env = await createReminderEnv(
          tester,
          permission: NotificationPermission.denied,
          afterRequest: NotificationPermission.denied,
        );
        await openSettings(tester, env);
        await tapSlot(tester, 12);
        await tapMasterSwitch(tester);
        await tapText(tester, 'Weiter zur Android-Abfrage');
        expect(find.text('Im System blockiert'), findsOneWidget);
        expect(env.platform.alarms, isEmpty);

        env.platform.permission = NotificationPermission.granted;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle(tester);

        expect(find.text('Benachrichtigungen sind blockiert'), findsNothing);
        expect(find.text('Eingeschaltet, 7 geplant'), findsOneWidget);
        expect(env.platform.alarms, hasLength(7));
      },
    );

    testWidgets('permission revoked later: the block turns to blocked', (
      tester,
    ) async {
      final env = await createReminderEnv(tester);
      await openSettings(tester, env);
      await tapSlot(tester, 12);
      await tapMasterSwitch(tester);
      expect(find.text('Eingeschaltet, 7 geplant'), findsOneWidget);

      env.platform.permission = NotificationPermission.denied;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(find.text('Im System blockiert'), findsOneWidget);
      expect(find.text('Öffnen'), findsOneWidget);
      expect(env.platform.alarms, isEmpty, reason: 'nothing is promised');
    });

    testWidgets('a settings page that cannot open is said so', (tester) async {
      final env = await createReminderEnv(
        tester,
        permission: NotificationPermission.denied,
        afterRequest: NotificationPermission.denied,
      );
      env.platform.settingsCanOpen = false;
      await openSettings(tester, env);
      await tapMasterSwitch(tester);
      await tapText(tester, 'Weiter zur Android-Abfrage');

      await tapText(tester, 'Öffnen');

      expect(env.feedback.last!.kind, 'info');
      expect(
        env.feedback.last!.message,
        contains('Systemeinstellungen konnten nicht geöffnet werden'),
      );
    });

    testWidgets(
      'unavailable notifications are explained and can be checked again',
      (tester) async {
        final env = await createReminderEnv(
          tester,
          permission: NotificationPermission.unavailable,
          afterRequest: NotificationPermission.unavailable,
        );
        await openSettings(tester, env);
        await tapMasterSwitch(tester);
        await tapText(tester, 'Weiter zur Android-Abfrage');

        expect(find.text('Benachrichtigungen nicht verfügbar'), findsOneWidget);
        expect(find.text('Auf diesem Gerät nicht verfügbar'), findsOneWidget);

        env.platform.permission = NotificationPermission.granted;
        await tapText(tester, 'Erneut prüfen');

        expect(find.text('Benachrichtigungen nicht verfügbar'), findsNothing);
        expect(
          find.text('Eingeschaltet, aktuell nichts geplant'),
          findsOneWidget,
        );
      },
    );
  });

  group('switching off', () {
    testWidgets('removes everything the app planned (C08)', (tester) async {
      final env = await createReminderEnv(tester);
      await openSettings(tester, env);
      await tapSlot(tester, 12);
      await tapMasterSwitch(tester);
      expect(env.platform.alarms, hasLength(7));

      await tapMasterSwitch(tester);

      expect(env.platform.alarms, isEmpty);
      expect(await env.wanted(tester), isFalse);
      expect(find.text('Aus'), findsOneWidget);
      expect(
        find.textContaining('geplant'),
        findsNothing,
        reason: 'no planned list while off',
      );
      expect(env.feedback.last!.kind, 'saved');
      expect(env.feedback.last!.message, 'Erinnerungen ausgeschaltet.');
      // The slots are kept for the next time.
      expect(await env.waterHours(tester), {12});
    });

    testWidgets('a system that cannot cancel is told honestly', (tester) async {
      final env = await createReminderEnv(tester);
      await openSettings(tester, env);
      await tapSlot(tester, 12);
      await tapMasterSwitch(tester);
      env.platform.cancelFailure = StateError('no alarm service');

      await tapMasterSwitch(tester);

      expect(await env.wanted(tester), isFalse);
      expect(env.feedback.last!.kind, 'info');
      expect(env.feedback.last!.message, contains('erscheinen eventuell noch'));
    });
  });

  group('water slots', () {
    testWidgets('are stored, planned and shown as selected (C08)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createReminderEnv(tester);
      await openSettings(tester, env);
      await tapMasterSwitch(tester);

      await tapSlot(tester, 12);
      await tapSlot(tester, 16);

      expect(await env.waterHours(tester), {12, 16});
      expect(env.platform.alarms, hasLength(14));
      final chip = tester.getSemantics(find.bySemanticsLabel('12 Uhr'));
      expect(chip.flagsCollection.isSelected, Tristate.isTrue);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('14 Uhr'))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );

      await tapSlot(tester, 12);
      expect(await env.waterHours(tester), {16});
      expect(env.platform.alarms, hasLength(7));
      handle.dispose();
    });

    testWidgets('survive a restart of the app (C08)', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await createReminderEnv(tester);
      await openSettings(tester, env);
      await tapSlot(tester, 10);
      await tapSlot(tester, 18);
      await tapMasterSwitch(tester);

      // A new app start on the same database.
      await openSettings(tester, env, container: env.restart());

      expect(await env.waterHours(tester), {10, 18});
      for (final hour in <int>[10, 18]) {
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('$hour Uhr'))
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
      }
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('12 Uhr'))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      expect(
        toggled(tester, 'Erinnerungen, Eingeschaltet, 13 geplant'),
        Tristate.isTrue,
      );
      handle.dispose();
    });

    testWidgets('two quick taps on two slots store both', (tester) async {
      final env = await createReminderEnv(tester);
      await openSettings(tester, env);

      await tester.tap(find.text('12:00'));
      await tester.tap(find.text('14:00'));
      await settle(tester);

      expect(await env.waterHours(tester), {12, 14});
    });

    testWidgets('are editable while reminders are off', (tester) async {
      final env = await createReminderEnv(tester);
      await openSettings(tester, env);

      await tapSlot(tester, 14);

      expect(await env.waterHours(tester), {14});
      expect(env.platform.scheduleCalls, isEmpty);
      expect(await env.wanted(tester), isFalse);
    });

    testWidgets('a switched off nutrition module is told (AT29, C08)', (
      tester,
    ) async {
      final env = await createReminderEnv(
        tester,
        enabledModules: {'body', 'focus', 'tasks', 'gamification'},
      );
      await openSettings(tester, env);

      expect(
        find.textContaining('Das Modul Ernährung ist ausgeschaltet'),
        findsOneWidget,
      );

      await tapSlot(tester, 12);
      await tapMasterSwitch(tester);

      expect(
        env.platform.alarms,
        isEmpty,
        reason: 'module off: no water reminders',
      );
      expect(
        find.text('Eingeschaltet, aktuell nichts geplant'),
        findsOneWidget,
      );
    });
  });

  group('failures', () {
    testWidgets(
      'a failing switch keeps the old state; the retry reuses the command id',
      (tester) async {
        late _FlakyPreferences prefs;
        final env = await createReminderEnv(
          tester,
          overrides: [
            reminderPreferencesRepositoryProvider.overrideWith(
              (ref) => prefs = _FlakyPreferences(
                ref.watch(appDatabaseProvider),
                ref.watch(commandRunnerProvider),
              ),
            ),
          ],
        );
        await openSettings(tester, env);
        prefs.failEnable = 1;

        await tapMasterSwitch(tester);

        expect(await env.wanted(tester), isFalse);
        expect(find.text('Aus'), findsOneWidget);
        expect(env.feedback.last!.kind, 'error');
        expect(
          env.feedback.last!.message,
          'Speichern fehlgeschlagen. Die Einstellung ist unverändert.',
        );

        env.feedback.last!.onRetry!();
        await settle(tester);

        expect(await env.wanted(tester), isTrue);
        expect(prefs.enableIds, hasLength(2));
        expect(prefs.enableIds.first, prefs.enableIds.last);
        expect(env.feedback.last!.kind, 'saved');
      },
    );

    testWidgets(
      'a failing slot change keeps the stored set; the retry reuses the id',
      (tester) async {
        late _FlakyPreferences prefs;
        final env = await createReminderEnv(
          tester,
          overrides: [
            reminderPreferencesRepositoryProvider.overrideWith(
              (ref) => prefs = _FlakyPreferences(
                ref.watch(appDatabaseProvider),
                ref.watch(commandRunnerProvider),
              ),
            ),
          ],
        );
        await openSettings(tester, env);
        prefs.failSlots = 1;

        await tapSlot(tester, 16);

        expect(await env.waterHours(tester), isEmpty);
        expect(env.feedback.last!.kind, 'error');
        expect(
          env.feedback.last!.message,
          'Speichern fehlgeschlagen. Die Uhrzeiten sind unverändert.',
        );

        env.feedback.last!.onRetry!();
        await settle(tester);

        expect(await env.waterHours(tester), {16});
        expect(prefs.slotIds, hasLength(2));
        expect(prefs.slotIds.first, prefs.slotIds.last);
      },
    );

    testWidgets('a planning error is shown with a retry (C08)', (tester) async {
      final env = await createReminderEnv(tester);
      await openSettings(tester, env);
      await tapSlot(tester, 12);
      await tapMasterSwitch(tester);
      expect(find.text('Eingeschaltet, 7 geplant'), findsOneWidget);

      env.platform.scheduleFailure = const ReminderPlatformException(
        PlatformFailureKind.failed,
      );
      await tapSlot(tester, 14);

      expect(find.text('Planungsfehler'), findsWidgets);
      expect(
        find.textContaining('Das System hat das Einplanen abgelehnt.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Deine Einträge sind davon nicht betroffen'),
        findsOneWidget,
      );
      expect(await env.waterHours(tester), {
        12,
        14,
      }, reason: 'the choice is saved');

      env.platform.scheduleFailure = null;
      await tapText(tester, 'Wiederholen');

      expect(find.text('Planungsfehler'), findsNothing);
      expect(find.text('Eingeschaltet, 14 geplant'), findsOneWidget);
    });

    testWidgets(
      'enabling with a failing planner reports it and keeps the wish',
      (tester) async {
        final env = await createReminderEnv(tester);
        env.platform.scheduleFailure = const ReminderPlatformException(
          PlatformFailureKind.failed,
        );
        await openSettings(tester, env);
        await tapSlot(tester, 12);

        await tapMasterSwitch(tester);

        expect(await env.wanted(tester), isTrue);
        expect(find.text('Planungsfehler'), findsWidgets);
        expect(env.feedback.last!.kind, 'error');
        expect(env.feedback.last!.onRetry, isNotNull);

        env.platform.scheduleFailure = null;
        env.feedback.last!.onRetry!();
        await settle(tester);

        expect(find.text('Planungsfehler'), findsNothing);
        expect(env.platform.alarms, hasLength(7));
      },
    );
  });

  group('planned reminders (AT29)', () {
    testWidgets(
      'the list shows what is planned, soonest first, and no history',
      (tester) async {
        final env = await createReminderEnv(tester);
        await openSettings(tester, env);
        await tapSlot(tester, 12);
        await tapSlot(tester, 14);
        await tapMasterSwitch(tester);

        expect(
          find.text('14 geplant, nächste: Heute, 12:00 Uhr'),
          findsOneWidget,
        );
        expect(
          find.text(ReminderTexts.waterTitle),
          findsNothing,
          reason: 'collapsed',
        );

        await tapText(tester, 'Geplante Erinnerungen');

        expect(find.text(ReminderTexts.waterTitle), findsNWidgets(8));
        expect(find.text('Heute, 12:00 Uhr'), findsOneWidget);
        expect(find.text('Heute, 14:00 Uhr'), findsOneWidget);
        expect(find.text('Morgen, 12:00 Uhr'), findsOneWidget);
        expect(
          find.text('6 weitere Erinnerungen sind geplant.'),
          findsOneWidget,
        );
        expect(find.textContaining('zugestellt'), findsNothing);

        await tapText(tester, 'Geplante Erinnerungen');
        expect(find.text(ReminderTexts.waterTitle), findsNothing);
      },
    );

    testWidgets('tapping a reminder opens its target', (tester) async {
      final env = await createReminderEnv(tester);
      final router = await openSettings(tester, env);
      await tapSlot(tester, 12);
      await tapMasterSwitch(tester);
      await tapText(tester, 'Geplante Erinnerungen');

      await tapText(tester, 'Heute, 12:00 Uhr');

      expect(router.routerDelegate.currentConfiguration.uri.path, '/water');
      expect(find.text('Wasser'), findsOneWidget);
    });

    testWidgets('a switched off module opens the dashboard instead', (
      tester,
    ) async {
      final env = await createReminderEnv(tester);
      final router = await openSettings(tester, env);
      await tapSlot(tester, 12);
      await tapMasterSwitch(tester);
      await tapText(tester, 'Geplante Erinnerungen');
      // The module is switched off after the reminder was planned.
      await tester.runAsync(() async {
        final db = env.harness.database;
        await db
            .into(db.moduleStatusHistory)
            .insert(
              ModuleStatusHistoryCompanion.insert(
                id: env.harness.ids.newId(),
                moduleId: ModuleId.nutrition.key,
                effectiveAtUtc: env.harness.clock.nowUtc(),
                localDate: env.harness.clock.today(),
                enabled: false,
              ),
            );
      });

      await tapText(tester, 'Heute, 12:00 Uhr');

      expect(router.routerDelegate.currentConfiguration.uri.path, '/');
      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('the planning limit is documented', (tester) async {
      final env = await createReminderEnv(tester);
      await env.addHabitsWithReminders(tester, 6);
      await openSettings(tester, env);

      await tapMasterSwitch(tester);

      expect(find.text('Eingeschaltet, 40 geplant'), findsOneWidget);
      expect(find.text(ReminderTexts.limitNotice), findsOneWidget);
    });
  });

  group('loading and errors', () {
    testWidgets('a short neutral line while the state is read', (tester) async {
      final env = await createReminderEnv(
        tester,
        overrides: [
          reminderStatusProvider.overrideWith(
            (ref) => StreamController<ReminderStatus>().stream,
          ),
        ],
      );
      await openSettings(tester, env);

      expect(find.text('Erinnerungen werden geladen …'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Erinnerungen'), findsNothing);
    });

    testWidgets('a load error offers a retry that reads again', (tester) async {
      var attempts = 0;
      final env = await createReminderEnv(
        tester,
        overrides: [
          reminderStatusProvider.overrideWith((ref) {
            attempts++;
            return attempts == 1
                ? Stream<ReminderStatus>.error(StateError('db'))
                : Stream<ReminderStatus>.value(
                    const ReminderStatus(
                      wanted: false,
                      permission: NotificationPermission.granted,
                      scheduledCount: 0,
                    ),
                  );
          }),
        ],
      );
      await openSettings(tester, env);

      expect(
        find.text('Erinnerungen konnten nicht geladen werden'),
        findsOneWidget,
      );
      expect(find.textContaining('sicher gespeichert'), findsOneWidget);

      await tapText(tester, 'Erneut versuchen');

      expect(attempts, 2);
      expect(
        find.text('Erinnerungen konnten nicht geladen werden'),
        findsNothing,
      );
      expect(find.text('Aus'), findsOneWidget);
    });
  });
}

/// Preferences that fail a given number of times before they work, and record
/// the command ids they were called with.
class _FlakyPreferences extends ReminderPreferencesRepository {
  _FlakyPreferences(AppDatabase database, CommandRunner runner)
    : super(database: database, runner: runner);

  int failEnable = 0;
  int failSlots = 0;
  final List<String> enableIds = [];
  final List<String> slotIds = [];

  @override
  Future<CommandOutcome> setNotificationsEnabled({
    required String commandId,
    required bool enabled,
  }) {
    enableIds.add(commandId);
    if (failEnable > 0) {
      failEnable--;
      throw const StorageFailure();
    }
    return super.setNotificationsEnabled(
      commandId: commandId,
      enabled: enabled,
    );
  }

  @override
  Future<CommandOutcome> setWaterSlots({
    required String commandId,
    required Set<int> hours,
  }) {
    slotIds.add(commandId);
    if (failSlots > 0) {
      failSlots--;
      throw const StorageFailure();
    }
    return super.setWaterSlots(commandId: commandId, hours: hours);
  }
}
