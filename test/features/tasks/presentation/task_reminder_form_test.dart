import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/reminder_texts.dart';
import 'package:self_improvement/core/notifications/platform/fake_reminder_platform.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/features/reminders/presentation/reminder_labels.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';

import '../../../support/pump_app.dart';
import '../support/task_test_support.dart';
import '../support/ui_support.dart';

/// The block "Erinnerung" of the task form (BS-111, Figma 4121:314, 4121:414,
/// 4121:517, 4121:621): the quick choices and the pickers, saving and undoing
/// the reminder, and the honest line or notice for every state of the
/// reminders (off, not allowed by the system, not available, planning error,
/// active). The reminder engine behind it is the real one on a fake platform.
void main() {
  setUpAll(allowMultipleDatabases);

  // "now" is 2026-10-03 10:00 in Berlin (a Saturday).
  final titleField = find.byType(TextField).at(0);

  /// The environment of a test: the task screens on the real reminder engine.
  Future<_Env> start(
    WidgetTester tester, {
    NotificationPermission permission = NotificationPermission.granted,
    bool wanted = true,
    String nowIso = '2026-10-03T08:00:00Z',
  }) async {
    final platform = FakeReminderPlatform(permission: permission);
    final env = await createTasksUiEnv(
      tester,
      nowIso: nowIso,
      extraOverrides: [reminderPlatformProvider.overrideWithValue(platform)],
    );
    addTearDown(platform.dispose);
    if (wanted) {
      await tester.runAsync(
        () => env.container
            .read(reminderPreferencesRepositoryProvider)
            .setNotificationsEnabled(
              commandId: env.harness.ids.newId(),
              enabled: true,
            ),
      );
    }
    return _Env(env, platform);
  }

  Future<GoRouter> openForm(
    WidgetTester tester,
    TasksUiEnv env, {
    String location = '/tasks/new',
    Size size = const Size(393, 852),
    double textScale = 1.0,
    AppThemeVariant theme = AppThemeVariant.light,
  }) async {
    final router = await pumpRouterApp(
      tester,
      routes: [
        ...tasksUiRoutes(),
        GoRoute(
          path: '/settings',
          builder: (context, state) =>
              const Scaffold(body: Text('probe:settings')),
        ),
      ],
      initialLocation: '/habits',
      container: env.container,
      size: size,
      textScale: textScale,
      theme: theme,
    );
    await pumpData(tester);
    unawaited(router.push(location));
    await tester.pumpAndSettle();
    await pumpData(tester);
    return router;
  }

  Finder chip(String label) => find.widgetWithText(AppChoiceChip, label);

  bool selected(WidgetTester tester, String label) =>
      tester.widget<AppChoiceChip>(chip(label)).selected;

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.ensureVisible(chip(label));
    await tester.tap(chip(label));
    await tester.pump();
    await pumpData(tester);
  }

  Future<void> save(
    WidgetTester tester, [
    String label = 'Aufgabe speichern',
  ]) async {
    await tester.pump();
    await tester.tap(find.text(label));
    await tester.pump();
  }

  Future<void> waitForFeedback(
    WidgetTester tester,
    TasksUiEnv env, [
    int count = 1,
  ]) async {
    await tester.pumpUntil(() => env.feedback.events.length >= count);
    await tester.pumpAndSettle();
    await pumpData(tester);
  }

  /// A task with a reminder, created through the real command.
  Future<String> addTaskWithReminder(
    WidgetTester tester,
    TasksUiEnv env,
    DateTime at, {
    String title = 'Steuer machen',
  }) async {
    final outcome = (await tester.runAsync(
      () => env.tasks.create(
        commandId: env.harness.ids.newId(),
        draft: TaskDraft(title: title, reminderAtUtc: at),
      ),
    ))!;
    env.tasks.commandIds.clear();
    return outcome.entityId!;
  }

  DateTime at(_Env e, int hours) =>
      e.env.harness.clock.nowUtc().add(Duration(hours: hours));

  group('without a reminder (Figma 4121:314)', () {
    testWidgets('the block is optional, "Aus" is chosen and there is no field '
        '(BS-111)', (tester) async {
      final e = await start(tester);
      await openForm(tester, e.env);

      expect(find.text('Erinnerung'), findsOneWidget);
      expect(selected(tester, 'Aus'), isTrue);
      expect(chip('Heute 18:00'), findsOneWidget);
      expect(chip('Morgen 09:00'), findsOneWidget);
      expect(selected(tester, 'Heute 18:00'), isFalse);
      expect(
        find.text('Ohne Erinnerung kommt keine Benachrichtigung.'),
        findsOneWidget,
      );
      expect(find.textContaining('Uhr'), findsNothing);
      expect(find.text('Erinnerung entfernen'), findsNothing);
    });

    testWidgets('the order of the chips: the evening, the morning, then "Aus" '
        '(BS-111)', (tester) async {
      final e = await start(tester);
      await openForm(tester, e.env);
      final labels = [
        for (final widget in tester.widgetList<AppChoiceChip>(
          find.byType(AppChoiceChip),
        ))
          widget.label,
      ];
      expect(labels, [
        'Heute',
        'Morgen',
        'Kein Datum',
        'Heute 18:00',
        'Morgen 09:00',
        'Aus',
      ]);
    });

    testWidgets('after 18:00 the chip "Heute 18:00" is not offered '
        '(BS-111)', (tester) async {
      // 19:00 in Berlin.
      final e = await start(tester, nowIso: '2026-10-03T17:00:00Z');
      await openForm(tester, e.env);
      expect(chip('Heute 18:00'), findsNothing);
      expect(chip('Morgen 09:00'), findsOneWidget);
      expect(selected(tester, 'Aus'), isTrue);
    });

    testWidgets('a task without a reminder saves none (BS-111, T01)', (
      tester,
    ) async {
      final e = await start(tester);
      await openForm(tester, e.env);
      await tester.enterText(titleField, 'Einkaufen');
      await save(tester);
      await waitForFeedback(tester, e.env);
      expect((await e.env.allTasks(tester)).single.reminder, isNull);
    });
  });

  group('choosing a reminder (Figma 4121:414)', () {
    testWidgets('"Heute 18:00" sets the moment, shows the field and the line '
        '(BS-111)', (tester) async {
      final e = await start(tester);
      await openForm(tester, e.env);
      await choose(tester, 'Heute 18:00');

      expect(selected(tester, 'Heute 18:00'), isTrue);
      expect(selected(tester, 'Aus'), isFalse);
      expect(find.text('Samstag, 3. Oktober, 18:00'), findsOneWidget);
      expect(
        find.text('Du bekommst ungefähr zu dieser Zeit eine Benachrichtigung.'),
        findsOneWidget,
      );
      expect(
        find.text('Ohne Erinnerung kommt keine Benachrichtigung.'),
        findsNothing,
      );
      // A new task has "Aus" as the way back, no separate removal.
      expect(find.text('Erinnerung entfernen'), findsNothing);
    });

    testWidgets('"Morgen 09:00" and "Aus" switch between the choices '
        '(BS-111)', (tester) async {
      final e = await start(tester);
      await openForm(tester, e.env);

      await choose(tester, 'Morgen 09:00');
      expect(find.text('Sonntag, 4. Oktober, 09:00'), findsOneWidget);
      expect(selected(tester, 'Morgen 09:00'), isTrue);

      await choose(tester, 'Aus');
      expect(find.text('Sonntag, 4. Oktober, 09:00'), findsNothing);
      expect(selected(tester, 'Aus'), isTrue);
      expect(
        find.text('Ohne Erinnerung kommt keine Benachrichtigung.'),
        findsOneWidget,
      );
    });

    testWidgets('saving stores the reminder with the task and the engine hands '
        'it to the system: neutral title, route of the task (BS-111, T01, '
        'AT28)', (tester) async {
      final e = await start(tester);
      // The listener of the app root: every committed change plans.
      e.env.container.read(reminderAutoReconcileProvider);
      await openForm(tester, e.env);
      await tester.enterText(titleField, 'Geheime Steuerunterlagen');
      await choose(tester, 'Heute 18:00');

      await save(tester);
      await waitForFeedback(tester, e.env);
      await tester.pumpUntil(() => e.platform.alarms.isNotEmpty);

      final task = (await e.env.allTasks(tester)).single;
      expect(task.reminder!.atUtc, DateTime.utc(2026, 10, 3, 16));
      expect(task.reminder!.timezoneId, 'Europe/Berlin');
      final alarm = e.platform.alarms.values.single;
      expect(alarm.fireAtUtc, DateTime.utc(2026, 10, 3, 16));
      expect(alarm.title, ReminderTexts.taskTitle);
      expect(alarm.payload, '/tasks/${task.id}');
      expect('${alarm.title}${alarm.payload}', isNot(contains('Steuer')));
    });

    testWidgets('the undo of the snackbar takes the task and with it the '
        'notification away (BS-111)', (tester) async {
      final e = await start(tester);
      e.env.container.read(reminderAutoReconcileProvider);
      await openForm(tester, e.env);
      await tester.enterText(titleField, 'Steuer machen');
      await choose(tester, 'Morgen 09:00');
      await save(tester);
      await waitForFeedback(tester, e.env);
      await tester.pumpUntil(() => e.platform.alarms.isNotEmpty);

      await tester.runAsync(e.env.feedback.last!.undo!.perform);
      await tester.pumpUntil(() => e.platform.alarms.isEmpty);
      expect(await e.env.allTasks(tester), isEmpty);
    });
  });

  group('the pickers (BS-111)', () {
    testWidgets('the field opens the date picker and then the time picker; '
        'both confirmed set the moment', (tester) async {
      final e = await start(tester);
      await openForm(tester, e.env);
      await choose(tester, 'Morgen 09:00');

      await tester.tap(find.text('Sonntag, 4. Oktober, 09:00'));
      await tester.pumpAndSettle();
      expect(find.text('Datum der Erinnerung'), findsOneWidget);
      await tester.tap(find.text('15'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Uhrzeit der Erinnerung'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Donnerstag, 15. Oktober, 09:00'), findsOneWidget);
      // No chip stands for a free moment.
      expect(selected(tester, 'Morgen 09:00'), isFalse);
      expect(selected(tester, 'Heute 18:00'), isFalse);
      expect(selected(tester, 'Aus'), isFalse);
    });

    testWidgets('cancelling the date or the time picker changes nothing', (
      tester,
    ) async {
      final e = await start(tester);
      await openForm(tester, e.env);
      await choose(tester, 'Morgen 09:00');

      await tester.tap(find.text('Sonntag, 4. Oktober, 09:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.text('Sonntag, 4. Oktober, 09:00'), findsOneWidget);

      await tester.tap(find.text('Sonntag, 4. Oktober, 09:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.text('Sonntag, 4. Oktober, 09:00'), findsOneWidget);
      expect(selected(tester, 'Morgen 09:00'), isTrue);
    });

    testWidgets('a moment in the past is refused with a hint at the field, the '
        'old one stays, a valid choice clears the hint (BS-111)', (
      tester,
    ) async {
      // 23:30 in Berlin: today 18:00 is gone, "Morgen 09:00" is the way in.
      final e = await start(tester, nowIso: '2026-10-03T21:30:00Z');
      await openForm(tester, e.env);
      await choose(tester, 'Morgen 09:00');

      await tester.tap(find.text('Sonntag, 4. Oktober, 09:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3')); // today
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // 09:00 of today: long gone
      await tester.pumpAndSettle();

      const hint =
          'Dieser Zeitpunkt ist schon vorbei. Wähle einen späteren Zeitpunkt '
          'für die Erinnerung.';
      expect(find.text(hint), findsOneWidget);
      expect(find.text('Sonntag, 4. Oktober, 09:00'), findsOneWidget);
      // The hint is announced when it appears (AT34).
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel(hint)),
        isSemantics(isLiveRegion: true, label: hint),
      );
      semantics.dispose();

      await choose(tester, 'Aus');
      expect(find.text(hint), findsNothing);
    });

    testWidgets('a reminder in the past cannot be saved even when the form '
        'was open long enough for it to pass (BS-111)', (tester) async {
      final e = await start(tester);
      await openForm(tester, e.env);
      await tester.enterText(titleField, 'Steuer machen');
      await choose(tester, 'Heute 18:00');
      // The user takes a break: it is 18:05 when "Speichern" is tapped.
      e.env.harness.clock.setNow(DateTime.utc(2026, 10, 3, 16, 5));

      await save(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await pumpData(tester);

      expect(
        find.text(
          'Dieser Zeitpunkt ist schon vorbei. Wähle einen späteren Zeitpunkt '
          'für die Erinnerung.',
        ),
        findsOneWidget,
      );
      expect(await e.env.allTasks(tester), isEmpty);
      expect(e.env.feedback.events, isEmpty);
    });
  });

  group('editing the reminder (Figma 4121:517)', () {
    testWidgets('opens with the reminder, the field and "Erinnerung '
        'entfernen" (BS-111)', (tester) async {
      final e = await start(tester);
      final id = await addTaskWithReminder(
        tester,
        e.env,
        DateTime.utc(2026, 10, 3, 16),
      );
      await openForm(tester, e.env, location: '/tasks/$id');

      expect(find.text('Aufgabe bearbeiten'), findsWidgets);
      expect(selected(tester, 'Heute 18:00'), isTrue);
      expect(find.text('Samstag, 3. Oktober, 18:00'), findsOneWidget);
      expect(find.text('Erinnerung entfernen'), findsOneWidget);
      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
        isNull,
        reason: 'nothing changed yet',
      );
    });

    testWidgets('changing it saves the new moment and the undo restores the '
        'old one with its date and zone (BS-111, T01)', (tester) async {
      final e = await start(tester);
      final id = await addTaskWithReminder(
        tester,
        e.env,
        DateTime.utc(2026, 10, 3, 16),
      );
      final before = (await e.env.readTask(tester, id))!.reminder!;
      await openForm(tester, e.env, location: '/tasks/$id');

      await choose(tester, 'Morgen 09:00');
      await save(tester, 'Änderungen speichern');
      await waitForFeedback(tester, e.env);
      expect(
        (await e.env.readTask(tester, id))!.reminder!.atUtc,
        DateTime.utc(2026, 10, 4, 7),
      );

      await tester.runAsync(e.env.feedback.last!.undo!.perform);
      expect((await e.env.readTask(tester, id))!.reminder, before);
    });

    testWidgets('"Erinnerung entfernen" and then saving removes it; the undo '
        'brings it back (BS-111, T01)', (tester) async {
      final e = await start(tester);
      e.env.container.read(reminderAutoReconcileProvider);
      final id = await addTaskWithReminder(
        tester,
        e.env,
        DateTime.utc(2026, 10, 3, 16),
      );
      final before = (await e.env.readTask(tester, id))!.reminder!;
      await tester.pumpUntil(() => e.platform.alarms.isNotEmpty);
      await openForm(tester, e.env, location: '/tasks/$id');

      await tester.ensureVisible(find.text('Erinnerung entfernen'));
      await tester.tap(find.text('Erinnerung entfernen'));
      await tester.pump();
      expect(selected(tester, 'Aus'), isTrue);
      expect(find.text('Samstag, 3. Oktober, 18:00'), findsNothing);
      expect(find.text('Erinnerung entfernen'), findsNothing);
      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
        isNotNull,
        reason: 'a removal is a change',
      );

      await save(tester, 'Änderungen speichern');
      await waitForFeedback(tester, e.env);
      expect((await e.env.readTask(tester, id))!.reminder, isNull);
      await tester.pumpUntil(() => e.platform.alarms.isEmpty);

      await tester.runAsync(e.env.feedback.last!.undo!.perform);
      expect((await e.env.readTask(tester, id))!.reminder, before);
      await tester.pumpUntil(() => e.platform.alarms.isNotEmpty);
    });

    testWidgets('a reminder that has gone off is shown as such and does not '
        'block saving another change (BS-111)', (tester) async {
      final e = await start(tester);
      final id = await addTaskWithReminder(
        tester,
        e.env,
        DateTime.utc(2026, 10, 3, 9),
      );
      // Two hours later the reminder (11:00 Berlin) lies behind us.
      e.env.harness.clock.setNow(DateTime.utc(2026, 10, 3, 11));
      await openForm(tester, e.env, location: '/tasks/$id');

      expect(find.text('Samstag, 3. Oktober, 11:00'), findsOneWidget);
      expect(
        find.text(
          'Dieser Zeitpunkt ist vorbei. Wähle einen neuen Zeitpunkt oder '
          'entferne die Erinnerung.',
        ),
        findsOneWidget,
      );

      await tester.enterText(titleField, 'Steuer erklären');
      await save(tester, 'Änderungen speichern');
      await waitForFeedback(tester, e.env);
      final saved = (await e.env.readTask(tester, id))!;
      expect(saved.title, 'Steuer erklären');
      expect(saved.reminder!.atUtc, DateTime.utc(2026, 10, 3, 9));
    });

    testWidgets('a completed task says that nothing will be delivered '
        '(BS-111)', (tester) async {
      final e = await start(tester);
      final id = await addTaskWithReminder(tester, e.env, at(e, 8));
      await tester.runAsync(
        () => e.env.tasks.setCompleted(
          commandId: e.env.harness.ids.newId(),
          id: id,
          completed: true,
        ),
      );
      await openForm(tester, e.env, location: '/tasks/$id');

      expect(
        find.text(
          'Die Aufgabe ist erledigt, deshalb kommt keine Benachrichtigung.',
        ),
        findsOneWidget,
      );
      // No notice about permissions: nothing would be delivered anyway.
      expect(find.text('Systemeinstellungen öffnen'), findsNothing);
    });
  });

  group('the honest states (Figma 4121:621, AT28)', () {
    testWidgets('the reminders are off: the notice says so, the task and the '
        'reminder are saved, and the way leads to the settings '
        '(BS-111, AT28)', (tester) async {
      final e = await start(tester, wanted: false);
      final router = await openForm(tester, e.env);
      await tester.enterText(titleField, 'Steuer machen');
      await choose(tester, 'Heute 18:00');

      expect(find.text('Erinnerungen sind ausgeschaltet'), findsOneWidget);
      expect(
        find.text(
          'Die Aufgabe wird gespeichert. Die Erinnerung kommt erst an, wenn '
          'du Erinnerungen in den Einstellungen einschaltest.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Du bekommst ungefähr zu dieser Zeit eine Benachrichtigung.'),
        findsNothing,
      );

      // The way: the settings, the form stays below with its input.
      await tester.ensureVisible(find.text('Einstellungen öffnen'));
      await tester.tap(find.text('Einstellungen öffnen'));
      await tester.pumpAndSettle();
      expect(find.text('probe:settings'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Neue Aufgabe'), findsOneWidget);
      expect(selected(tester, 'Heute 18:00'), isTrue);

      // And it is saved as it is.
      await save(tester);
      await waitForFeedback(tester, e.env);
      expect((await e.env.allTasks(tester)).single.reminder, isNotNull);
    });

    testWidgets('the system does not allow notifications: the notice of the '
        'design, the reminder is saved, the way leads to the system settings '
        '(BS-111, AT28)', (tester) async {
      final e = await start(tester, permission: NotificationPermission.denied);
      await openForm(tester, e.env);
      await tester.enterText(titleField, 'Steuer machen');
      await choose(tester, 'Heute 18:00');

      expect(
        find.text('Benachrichtigungen sind nicht erlaubt'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Die Aufgabe wird gespeichert. Die Erinnerung kommt erst an, wenn '
          'du Benachrichtigungen in den Systemeinstellungen erlaubst.',
        ),
        findsOneWidget,
      );
      expect(find.text('Systemeinstellungen öffnen'), findsOneWidget);

      await tester.ensureVisible(find.text('Systemeinstellungen öffnen'));
      await tester.tap(find.text('Systemeinstellungen öffnen'));
      await tester.pump();
      expect(e.platform.openSettingsCalls, 1);
      expect(e.env.feedback.events, isEmpty);

      await save(tester);
      await waitForFeedback(tester, e.env);
      final task = (await e.env.allTasks(tester)).single;
      expect(task.reminder!.atUtc, DateTime.utc(2026, 10, 3, 16));
      // And honestly nothing was handed to the system.
      expect(e.platform.scheduleCalls, isEmpty);
    });

    testWidgets('when the system settings cannot be opened the app says how '
        'to get there (BS-111, AT28)', (tester) async {
      final e = await start(tester, permission: NotificationPermission.denied);
      e.platform.settingsCanOpen = false;
      await openForm(tester, e.env);
      await choose(tester, 'Heute 18:00');

      await tester.ensureVisible(find.text('Systemeinstellungen öffnen'));
      await tester.tap(find.text('Systemeinstellungen öffnen'));
      await tester.pump();
      await tester.pump();

      expect(e.env.feedback.last!.kind, 'info');
      expect(e.env.feedback.last!.message, ReminderLabels.settingsNotOpened);
    });

    testWidgets('allowing the notifications in the system settings makes the '
        'notice go away by itself (BS-111, AT28)', (tester) async {
      final e = await start(tester, permission: NotificationPermission.denied);
      await openForm(tester, e.env);
      await choose(tester, 'Heute 18:00');
      expect(
        find.text('Benachrichtigungen sind nicht erlaubt'),
        findsOneWidget,
      );

      // The user comes back from the system settings; the app plans again.
      e.platform.permission = NotificationPermission.granted;
      await tester.runAsync(
        () => e.env.container.read(reminderServiceProvider).reconcile(),
      );
      await pumpData(tester);

      expect(find.text('Benachrichtigungen sind nicht erlaubt'), findsNothing);
      expect(
        find.text('Du bekommst ungefähr zu dieser Zeit eine Benachrichtigung.'),
        findsOneWidget,
      );
    });

    testWidgets('the device cannot show notifications: the notice offers to '
        'check again (BS-111, AT28)', (tester) async {
      final e = await start(
        tester,
        permission: NotificationPermission.unavailable,
      );
      await openForm(tester, e.env);
      await choose(tester, 'Heute 18:00');

      expect(find.text('Benachrichtigungen nicht verfügbar'), findsOneWidget);
      final before = e.platform.permissionStatusCalls;
      await tester.ensureVisible(find.text('Erneut prüfen'));
      await tester.tap(find.text('Erneut prüfen'));
      await tester.pump();
      await pumpData(tester);
      expect(e.platform.permissionStatusCalls, greaterThan(before));
    });

    testWidgets('the system refuses to plan: the notice names the cause and '
        'offers to try again (BS-111, AT28)', (tester) async {
      final e = await start(tester);
      await addTaskWithReminder(tester, e.env, at(e, 4), title: 'Vorhanden');
      e.platform.scheduleFailure = const ReminderPlatformException(
        PlatformFailureKind.failed,
      );
      await tester.runAsync(
        () => e.env.container.read(reminderServiceProvider).reconcile(),
      );
      await openForm(tester, e.env);
      await choose(tester, 'Heute 18:00');

      expect(find.text('Planungsfehler'), findsOneWidget);
      expect(
        find.textContaining('Das System hat das Einplanen abgelehnt.'),
        findsOneWidget,
      );

      e.platform.scheduleFailure = null;
      await tester.ensureVisible(find.text('Wiederholen'));
      await tester.tap(find.text('Wiederholen'));
      await tester.pump();
      await pumpData(tester);
      expect(find.text('Planungsfehler'), findsNothing);
    });

    testWidgets('without a reminder no notice appears, whatever the state '
        'of the reminders is (BS-111)', (tester) async {
      final e = await start(tester, wanted: false);
      await openForm(tester, e.env);
      // No reminder: only the quiet line, whatever the state is.
      expect(find.text('Erinnerungen sind ausgeschaltet'), findsNothing);
      expect(find.text('Benachrichtigungen sind nicht erlaubt'), findsNothing);
    });

    testWidgets('with very many reminders the limit of the engine is named '
        '(BS-111)', (tester) async {
      final e = await start(tester);
      for (var i = 1; i <= 41; i++) {
        await addTaskWithReminder(tester, e.env, at(e, i), title: 'Aufgabe $i');
      }
      final status = (await tester.runAsync(
        () => e.env.container.read(reminderServiceProvider).reconcile(),
      ))!;
      expect(status.planLimitReached, isTrue);

      await openForm(tester, e.env);
      await choose(tester, 'Morgen 09:00');
      expect(find.text(ReminderTexts.limitNotice), findsOneWidget);
      expect(
        find.text('Du bekommst ungefähr zu dieser Zeit eine Benachrichtigung.'),
        findsOneWidget,
      );
    });
  });

  group('the wording (BS-111, AT28)', () {
    testWidgets('no text of the block names a platform', (tester) async {
      for (final permission in NotificationPermission.values) {
        for (final wanted in [true, false]) {
          for (final state in [
            ReminderStatus(
              wanted: wanted,
              permission: permission,
              scheduledCount: 0,
            ),
            ReminderStatus(
              wanted: wanted,
              permission: permission,
              scheduledCount: 0,
              lastError: ReminderErrorCategory.permission,
            ),
          ]) {
            final notice = ReminderLabels.taskNotice(state);
            if (notice == null) {
              continue;
            }
            for (final text in [
              notice.title,
              notice.text,
              notice.actionLabel,
              notice.actionSemanticLabel ?? '',
            ]) {
              expect(
                RegExp(
                  r'Android|iOS|iPhone|iPad',
                  caseSensitive: false,
                ).hasMatch(text),
                isFalse,
                reason: text,
              );
            }
          }
        }
      }
    });
  });

  group('the form keeps working (BS-111, regression)', () {
    testWidgets('a task without a reminder has no engine call at all, so the '
        'form works where the platform is not available', (tester) async {
      final e = await start(tester, wanted: false);
      await openForm(tester, e.env);
      await tester.enterText(titleField, 'Einkaufen');
      await save(tester);
      await waitForFeedback(tester, e.env);
      expect(e.platform.permissionStatusCalls, 0);
      expect(e.platform.scheduleCalls, isEmpty);
    });

    testWidgets('the due day and the reminder are independent (BS-111)', (
      tester,
    ) async {
      final e = await start(tester);
      await openForm(tester, e.env);
      await tester.enterText(titleField, 'Steuer machen');
      await tester.tap(find.text('Morgen').first);
      await tester.pump();
      await choose(tester, 'Heute 18:00');
      await save(tester);
      await waitForFeedback(tester, e.env);

      final task = (await e.env.allTasks(tester)).single;
      expect(task.dueDate, e.env.harness.clock.today().addDays(1));
      expect(task.reminder!.atUtc, DateTime.utc(2026, 10, 3, 16));
    });
  });
}

/// The environment of a test.
class _Env {
  const _Env(this.env, this.platform);

  final TasksUiEnv env;
  final FakeReminderPlatform platform;
}
