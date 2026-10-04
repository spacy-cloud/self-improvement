import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/features/reminders/presentation/reminder_permission_sheet.dart';

import '../../support/pump_app.dart';

/// The explanation sheet before the system dialog (Figma 4055:317; AT28, C08).
void main() {
  ReminderPermissionChoice? result;

  Future<void> open(
    WidgetTester tester, {
    NotificationPermission permission = NotificationPermission.denied,
    Size size = const Size(393, 852),
    double textScale = 1.0,
  }) async {
    result = null;
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showReminderPermissionSheet(
                  context,
                  permission: permission,
                );
              },
              child: const Text('Sheet öffnen'),
            ),
          ),
        ),
      ),
      size: size,
      textScale: textScale,
    );
    await tester.tap(find.text('Sheet öffnen'));
    await tester.pumpAndSettle();
  }

  testWidgets('explains the purpose and promises nothing it cannot keep', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Erinnerungen erlauben?'), findsOneWidget);
    expect(
      find.textContaining('nur an das, was du einschaltest'),
      findsOneWidget,
    );
    expect(find.textContaining('Keine Werbung'), findsOneWidget);
    expect(find.textContaining('Android kann sie verzögern'), findsOneWidget);
    expect(find.textContaining('garantiert'), findsNothing);
    expect(result, isNull, reason: 'nothing is decided by opening it');
  });

  group('the device state is shown as it is', () {
    for (final (permission, text) in <(NotificationPermission, String)>[
      (
        NotificationPermission.denied,
        'Android-Status: Benachrichtigungen sind für diese App nicht erlaubt.',
      ),
      (
        NotificationPermission.unavailable,
        'Android-Status: Der Status der Benachrichtigungen ist nicht '
            'verfügbar.',
      ),
      (
        NotificationPermission.granted,
        'Android-Status: Benachrichtigungen sind erlaubt.',
      ),
    ]) {
      testWidgets(permission.name, (tester) async {
        await open(tester, permission: permission);
        expect(find.text(text), findsOneWidget);
      });
    }
  });

  group('every way out has a result', () {
    final ways =
        <
          (
            String,
            ReminderPermissionChoice,
            Future<void> Function(WidgetTester),
          )
        >[
          (
            '"Weiter zur Android-Abfrage"',
            ReminderPermissionChoice.askSystem,
            (t) => t.tap(find.text('Weiter zur Android-Abfrage')),
          ),
          (
            '"Einstellungen öffnen"',
            ReminderPermissionChoice.openSettings,
            (t) => t.tap(find.text('Einstellungen öffnen')),
          ),
          (
            '"Später"',
            ReminderPermissionChoice.later,
            (t) => t.tap(find.text('Später')),
          ),
          (
            'the close button',
            ReminderPermissionChoice.later,
            (t) => t.tap(find.byType(AppIconButton).last),
          ),
          (
            'the system back action',
            ReminderPermissionChoice.later,
            (t) => t.binding.handlePopRoute(),
          ),
          (
            'a tap on the barrier',
            ReminderPermissionChoice.later,
            (t) => t.tapAt(const Offset(196, 20)),
          ),
        ];
    for (final (name, expected, act) in ways) {
      testWidgets(name, (tester) async {
        await open(tester);
        await act(tester);
        await tester.pumpAndSettle();

        expect(find.text('Erinnerungen erlauben?'), findsNothing);
        expect(result, expected);
      });
    }
  });

  testWidgets('"Später" has the initial focus: the safe default', (
    tester,
  ) async {
    await open(tester);
    final focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull);
    expect(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is SecondaryButton && w.autofocus),
        matching: find.text('Später'),
      ),
      findsOneWidget,
    );
  });

  for (final size in responsiveSizes) {
    for (final scale in <double>[1.0, 2.0]) {
      testWidgets(
        'fits ${size.width.toInt()} px at ${(scale * 100).toInt()} % text '
        'and its actions stay reachable (AT33)',
        (tester) async {
          await open(tester, size: size, textScale: scale);
          expect(tester.takeException(), isNull);
          for (final label in <String>[
            'Weiter zur Android-Abfrage',
            'Einstellungen öffnen',
            'Später',
          ]) {
            await tester.ensureVisible(find.text(label));
            await tester.pump();
            expect(tester.takeException(), isNull);
            final rect = tester.getRect(find.text(label));
            expect(rect.bottom, lessThanOrEqualTo(size.height), reason: label);
          }
        },
      );
    }
  }

  testWidgets('tap targets and labels meet the guidelines (AT34)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(find.bySemanticsLabel('Erinnerungen erlauben?'), findsWidgets);
    expect(
      find.bySemanticsLabel(
        'Systemeinstellungen für Benachrichtigungen öffnen',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
