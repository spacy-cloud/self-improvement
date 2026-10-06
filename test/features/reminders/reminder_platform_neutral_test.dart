import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/reminder_texts.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/features/reminders/presentation/reminder_labels.dart';
import 'package:self_improvement/features/reminders/presentation/reminder_permission_sheet.dart';

import '../../support/platform_names.dart';
import '../../support/pump_app.dart';
import 'reminder_test_support.dart';

/// The texts of the reminder flow name no platform (BS-113, D-017, AT28).
///
/// A tester on an iPhone read "Weiter zur Android-Abfrage". The source rule in
/// `test/app/user_text_rules_test.dart` finds such words in the literals of
/// `lib/`; these tests read what is really on the screen and in the screen
/// reader tree in every state of the flow, once with Android and once with iOS
/// as the platform, and the wording of the two Figma drafts (4118:5272 and
/// 4118:5313 on the page "v0.2.0 – Neue Screens"). They prove the texts, not
/// how the system dialog or the system settings look on a device.
void main() {
  const platforms = TargetPlatformVariant(<TargetPlatform>{
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  /// Tall enough that nothing of the block or the sheet is scrolled out of the
  /// accessibility tree.
  const tall = Size(430, 2400);

  /// Everything a person can read or hear right now: the text of every text
  /// widget, label, value, hint and tooltip of the screen reader tree and the
  /// messages the app showed in a snack bar.
  List<String> readable(WidgetTester tester, ReminderEnv? env) {
    final texts = <String>[
      for (final rich in tester.widgetList<RichText>(find.byType(RichText)))
        rich.text.toPlainText(),
      for (final node
          in tester.semantics.simulatedAccessibilityTraversal()) ...<String>[
        node.label,
        node.value,
        node.hint,
        node.tooltip,
      ],
      if (env != null)
        for (final event in env.feedback.events) event.message,
    ];
    return <String>[
      for (final text in texts)
        if (text.trim().isNotEmpty) text,
    ];
  }

  /// Fails when anything readable names a platform. [reads] are words the
  /// screen must really contain, so a sweep that reads nothing cannot pass.
  void expectNeutral(
    WidgetTester tester,
    ReminderEnv? env,
    String state, {
    List<String> reads = const <String>[],
  }) {
    final texts = readable(tester, env);
    for (final word in reads) {
      expect(
        texts.any((text) => text.contains(word)),
        isTrue,
        reason: '$state: the sweep did not read "$word"',
      );
    }
    expect(
      <String>[
        for (final text in texts)
          if (platformNameIn(text) != null) text,
      ],
      isEmpty,
      reason: '$state names a platform on ${defaultTargetPlatform.name}',
    );
  }

  /// [body] with the screen reader tree switched on.
  Future<void> withSemantics(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await body();
    } finally {
      handle.dispose();
    }
  }

  group('the wording of the design', () {
    testWidgets(
      'the sheet goes on to the system query (BS-113, Figma 4118:5272, AT28)',
      (tester) async {
        final env = await createReminderEnv(
          tester,
          permission: NotificationPermission.denied,
        );
        await openSettings(tester, env);
        await tapMasterSwitch(tester);

        expect(find.text('Erinnerungen erlauben?'), findsOneWidget);
        expect(
          find.widgetWithText(PrimaryButton, 'Weiter zur Systemabfrage'),
          findsOneWidget,
        );
        expect(find.widgetWithText(SecondaryButton, 'Später'), findsOneWidget);
        expect(
          find.textContaining('Dafür fragt das System einmal nach deiner '),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the blocked banner points to the system settings (BS-113, Figma 4118:5313, AT28)',
      (tester) async {
        await withSemantics(tester, () async {
          final env = await createReminderEnv(
            tester,
            permission: NotificationPermission.denied,
            afterRequest: NotificationPermission.denied,
          );
          await openSettings(tester, env);
          await tapMasterSwitch(tester);
          await tapText(tester, 'Weiter zur Systemabfrage');

          expect(
            find.text('Benachrichtigungen sind blockiert'),
            findsOneWidget,
          );
          expect(
            find.text(
              'Erlaube sie in den Systemeinstellungen, damit Erinnerungen '
              'ankommen.',
            ),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(SecondaryButton, 'Öffnen'),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(
              'Systemeinstellungen für Benachrichtigungen öffnen',
            ),
            findsOneWidget,
          );
        });
      },
    );

    testWidgets('both ways to the settings use the same words (BS-113, AT28)', (
      tester,
    ) async {
      await withSemantics(tester, () async {
        final env = await createReminderEnv(
          tester,
          permission: NotificationPermission.denied,
          afterRequest: NotificationPermission.denied,
        );
        await openSettings(tester, env);
        await tapMasterSwitch(tester);
        // The sheet and the banner offer the same step to the same place.
        expect(
          find.bySemanticsLabel(
            'Systemeinstellungen für Benachrichtigungen öffnen',
          ),
          findsOneWidget,
        );
        await tapText(tester, 'Weiter zur Systemabfrage');
        expect(
          find.bySemanticsLabel(
            'Systemeinstellungen für Benachrichtigungen öffnen',
          ),
          findsOneWidget,
        );
      });
    });
  });

  group('every state of the flow, on every platform', () {
    testWidgets(
      'permission refused: sheet, banner and messages (BS-113, AT28)',
      (tester) async {
        await withSemantics(tester, () async {
          final env = await createReminderEnv(
            tester,
            permission: NotificationPermission.denied,
            afterRequest: NotificationPermission.denied,
          );
          await openSettings(tester, env, size: tall);
          expectNeutral(
            tester,
            env,
            'off, not asked yet',
            reads: <String>['Systemstatus: Benachrichtigungen sind noch nicht'],
          );

          await tapMasterSwitch(tester);
          expectNeutral(
            tester,
            env,
            'permission sheet',
            reads: <String>[
              'Weiter zur Systemabfrage',
              'Systemstatus: Benachrichtigungen sind für diese App nicht',
              'Dafür fragt das System',
              'das System kann sie verzögern',
            ],
          );

          await tapText(tester, 'Weiter zur Systemabfrage');
          expectNeutral(
            tester,
            env,
            'blocked',
            reads: <String>[
              'Erlaube sie in den Systemeinstellungen',
              'Systemeinstellungen für Benachrichtigungen öffnen',
              'das System blockiert Benachrichtigungen noch',
            ],
          );

          env.platform.settingsCanOpen = false;
          await tapText(tester, 'Öffnen');
          expectNeutral(
            tester,
            env,
            'the settings page cannot be opened',
            reads: <String>['Einstellungen deines Geräts'],
          );
        });
      },
      variant: platforms,
    );

    testWidgets(
      'the sheet offers the settings and they cannot be opened (BS-113, AT28)',
      (tester) async {
        await withSemantics(tester, () async {
          final env = await createReminderEnv(
            tester,
            permission: NotificationPermission.denied,
            afterRequest: NotificationPermission.denied,
          );
          env.platform.settingsCanOpen = false;
          await openSettings(tester, env, size: tall);
          await tapMasterSwitch(tester);
          await tapText(tester, 'Einstellungen öffnen');

          expect(env.platform.openSettingsCalls, 1);
          expectNeutral(
            tester,
            env,
            'the settings page cannot be opened from the sheet',
            reads: <String>['Einstellungen deines Geräts'],
          );
        });
      },
      variant: platforms,
    );

    testWidgets('notifications unavailable: sheet and banner (BS-113, AT28)', (
      tester,
    ) async {
      await withSemantics(tester, () async {
        final env = await createReminderEnv(
          tester,
          permission: NotificationPermission.unavailable,
          afterRequest: NotificationPermission.unavailable,
        );
        await openSettings(tester, env, size: tall);
        await tapMasterSwitch(tester);
        expectNeutral(
          tester,
          env,
          'permission sheet, status unreadable',
          reads: <String>['Systemstatus: Der Status der Benachrichtigungen'],
        );

        await tapText(tester, 'Weiter zur Systemabfrage');
        expectNeutral(
          tester,
          env,
          'unavailable',
          reads: <String>['Benachrichtigungen nicht verfügbar'],
        );
      });
    }, variant: platforms);

    testWidgets(
      'planned, list open and a refused scheduling run (BS-113, AT28)',
      (tester) async {
        await withSemantics(tester, () async {
          final env = await createReminderEnv(tester);
          await openSettings(tester, env, size: tall);
          await tapSlot(tester, 12);
          await tapMasterSwitch(tester);
          await tapText(tester, 'Geplante Erinnerungen');
          expectNeutral(
            tester,
            env,
            'active, list open',
            reads: <String>['Systemstatus: Benachrichtigungen sind erlaubt.'],
          );

          env.platform.scheduleFailure = const ReminderPlatformException(
            PlatformFailureKind.permissionMissing,
          );
          await tapSlot(tester, 14);
          expectNeutral(
            tester,
            env,
            'the system refused for a missing permission',
            reads: <String>[
              'Das System hat das Einplanen wegen fehlender Berechtigung '
                  'abgelehnt.',
            ],
          );

          env.platform.scheduleFailure = const ReminderPlatformException(
            PlatformFailureKind.failed,
          );
          await tapSlot(tester, 16);
          expectNeutral(
            tester,
            env,
            'the system failed in another way',
            reads: <String>['Das System hat das Einplanen abgelehnt.'],
          );
        });
      },
      variant: platforms,
    );

    for (final permission in NotificationPermission.values) {
      testWidgets(
        'the sheet itself with the permission ${permission.name} (BS-113, AT28)',
        (tester) async {
          await withSemantics(tester, () async {
            await pumpApp(
              tester,
              Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showReminderPermissionSheet(
                        context,
                        permission: permission,
                      ),
                      child: const Text('Sheet öffnen'),
                    ),
                  ),
                ),
              ),
              size: tall,
            );
            await tester.tap(find.text('Sheet öffnen'));
            await tester.pumpAndSettle();

            expectNeutral(
              tester,
              null,
              'the sheet with ${permission.name}',
              reads: <String>['Erinnerungen erlauben?', 'Systemstatus: '],
            );
          });
        },
        variant: platforms,
      );
    }
  });

  group('the words of the pure labels', () {
    test('no label of the block names a platform (BS-113, AT28)', () {
      final errors = <ReminderErrorCategory?>[
        null,
        ...ReminderErrorCategory.values,
      ];
      final texts = <String>[];
      for (final wanted in <bool>[false, true]) {
        for (final permission in NotificationPermission.values) {
          for (final error in errors) {
            final status = ReminderStatus(
              wanted: wanted,
              permission: permission,
              scheduledCount: 3,
              lastError: error,
            );
            texts
              ..add(ReminderLabels.stateSubtitle(status))
              ..add(ReminderLabels.permissionLine(status));
          }
        }
      }
      for (final error in errors) {
        texts.add(ReminderLabels.schedulingErrorText(error));
      }

      expect(texts.length, greaterThan(40), reason: 'all states are covered');
      expect(<String>[
        for (final text in texts)
          if (platformNameIn(text) != null) text,
      ], isEmpty);
    });

    test('no notification text names a platform (BS-113, AT28)', () {
      final texts = <String>[
        for (final kind in ReminderKind.values) ReminderTexts.titleFor(kind),
        ReminderTexts.channelName,
        ReminderTexts.channelDescription,
        ReminderTexts.limitNotice,
        ReminderTexts.deliveryNotice,
      ];
      expect(texts, hasLength(7));
      expect(<String>[
        for (final text in texts)
          if (platformNameIn(text) != null) text,
      ], isEmpty);
    });

    test('the permission line and the refusal read neutral (BS-113, AT28)', () {
      const blockedAfterAsking = ReminderStatus(
        wanted: true,
        permission: NotificationPermission.denied,
        scheduledCount: 0,
      );
      const notAskedYet = ReminderStatus(
        wanted: false,
        permission: NotificationPermission.denied,
        scheduledCount: 0,
      );
      expect(
        ReminderLabels.permissionLine(notAskedYet),
        'Systemstatus: Benachrichtigungen sind noch nicht erlaubt. '
        'Das System fragt erst, wenn du Erinnerungen einschaltest.',
      );
      expect(
        ReminderLabels.permissionLine(blockedAfterAsking),
        'Systemstatus: Benachrichtigungen sind blockiert.',
      );
      expect(
        ReminderLabels.schedulingErrorText(ReminderErrorCategory.permission),
        'Das System hat das Einplanen wegen fehlender Berechtigung '
        'abgelehnt. Deine Einträge sind davon nicht betroffen.',
      );
    });
  });
}
