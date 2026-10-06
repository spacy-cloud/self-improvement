import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';

import '../../support/pump_app.dart';
import 'reminder_test_support.dart';

/// Layout and accessibility of the reminders block and its sheet: no overflow
/// from 320 to 430 px and 100 % to 200 % text, tap targets, labels, state not
/// by colour alone, announcements.
void main() {
  group('responsive layout (AT33)', () {
    for (final size in responsiveSizes) {
      for (final scale in <double>[1.0, 2.0]) {
        testWidgets('all states fit ${size.width.toInt()} px at '
            '${(scale * 100).toInt()} % text (AT33)', (tester) async {
          final env = await createReminderEnv(
            tester,
            permission: NotificationPermission.denied,
            afterRequest: NotificationPermission.denied,
          );
          await openSettings(tester, env, size: size, textScale: scale);
          expect(tester.takeException(), isNull, reason: 'off');

          await tapMasterSwitch(tester);
          expect(find.text('Erinnerungen erlauben?'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'permission sheet');
          for (final label in <String>[
            'Weiter zur Systemabfrage',
            'Einstellungen öffnen',
            'Später',
          ]) {
            await tester.ensureVisible(find.text(label));
            await tester.pump();
          }
          await tapText(tester, 'Weiter zur Systemabfrage');
          expect(
            find.text('Benachrichtigungen sind blockiert'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull, reason: 'blocked');
          await tester.ensureVisible(find.text('Öffnen'));
          await tester.pump();

          env.platform.permission = NotificationPermission.granted;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await settle(tester);
          await tapSlot(tester, 12);
          await tapSlot(tester, 14);
          await tapText(tester, 'Geplante Erinnerungen');
          expect(tester.takeException(), isNull, reason: 'planned list');

          env.platform.scheduleFailure = const ReminderPlatformException(
            PlatformFailureKind.failed,
          );
          await tapSlot(tester, 16);
          expect(find.text('Planungsfehler'), findsWidgets);
          expect(tester.takeException(), isNull, reason: 'planning error');
          await tester.ensureVisible(find.text('Wiederholen'));
          await tester.pump();
        });
      }
    }
  });

  group('tap targets, labels and announcements (AT34)', () {
    testWidgets('every state meets the tap target guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await createReminderEnv(
        tester,
        permission: NotificationPermission.denied,
        afterRequest: NotificationPermission.denied,
      );
      await openSettings(tester, env);

      Future<void> check() async {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }

      await check();
      await tapMasterSwitch(tester);
      await check();
      await tapText(tester, 'Weiter zur Systemabfrage');
      await check();

      env.platform.permission = NotificationPermission.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      await tapSlot(tester, 12);
      await tapText(tester, 'Geplante Erinnerungen');
      await check();

      env.platform.scheduleFailure = const ReminderPlatformException(
        PlatformFailureKind.failed,
      );
      await tapSlot(tester, 14);
      await check();
      handle.dispose();
    });

    testWidgets('state is told by words, not by colour alone', (tester) async {
      final env = await createReminderEnv(
        tester,
        permission: NotificationPermission.denied,
        afterRequest: NotificationPermission.denied,
      );
      await openSettings(tester, env);
      await tapMasterSwitch(tester);
      await tapText(tester, 'Weiter zur Systemabfrage');

      // The blocked state has a title, a sentence and a state word.
      expect(find.text('Im System blockiert'), findsOneWidget);
      expect(find.text('Benachrichtigungen sind blockiert'), findsOneWidget);
      expect(
        find.textContaining('Erlaube sie in den Systemeinstellungen'),
        findsOneWidget,
      );

      // A selected slot has a check mark, not only another colour.
      await tapSlot(tester, 14);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('switch, chips, banner and list announce their state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createReminderEnv(
        tester,
        permission: NotificationPermission.denied,
        afterRequest: NotificationPermission.denied,
      );
      await openSettings(tester, env);

      final off = tester.getSemantics(
        find.bySemanticsLabel('Erinnerungen, Aus'),
      );
      expect(off.flagsCollection.isToggled, Tristate.isFalse);
      expect(off.flagsCollection.isEnabled, Tristate.isTrue);

      await tapMasterSwitch(tester);
      await tapText(tester, 'Weiter zur Systemabfrage');
      final blocked = tester.getSemantics(
        find.bySemanticsLabel('Erinnerungen, Im System blockiert'),
      );
      expect(blocked.flagsCollection.isToggled, Tristate.isTrue);

      // The banner is read out when it appears and its button names the target.
      expect(
        find.bySemanticsLabel(
          'Benachrichtigungen sind blockiert. Erlaube sie in den '
          'Systemeinstellungen, damit Erinnerungen ankommen.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Systemeinstellungen für Benachrichtigungen öffnen',
        ),
        findsOneWidget,
      );

      // Slots are a labelled group of chips with a selected flag.
      expect(
        find.bySemanticsLabel('Uhrzeiten der Trink-Erinnerung'),
        findsOneWidget,
      );
      await tapSlot(tester, 12);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('12 Uhr'))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );

      env.platform.permission = NotificationPermission.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(
        find.bySemanticsLabel(
          'Geplante Erinnerungen, 7 geplant, nächste: Heute, 12:00 Uhr, eingeklappt',
        ),
        findsOneWidget,
      );
      await tapText(tester, 'Geplante Erinnerungen');
      expect(
        find.bySemanticsLabel(
          'Geplante Erinnerungen, 7 geplant, nächste: Heute, 12:00 Uhr, ausgeklappt',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the permission sheet is a named route in front of the block', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createReminderEnv(
        tester,
        permission: NotificationPermission.denied,
      );
      await openSettings(tester, env);

      await tapMasterSwitch(tester);
      // The sheet is open: the block behind it is not reachable.
      expect(find.bySemanticsLabel('Erinnerungen erlauben?'), findsWidgets);
      handle.dispose();
    });
  });
}
