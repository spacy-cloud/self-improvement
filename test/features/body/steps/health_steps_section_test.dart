import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/health/application/health_providers.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';
import 'package:self_improvement/core/health/platform/fake_health_steps_source.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_controller.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_sync.dart';
import 'package:self_improvement/features/body/steps/domain/step_source.dart';
import 'package:self_improvement/features/body/steps/presentation/health_explanation_sheet.dart';
import 'package:self_improvement/features/body/steps/presentation/health_notice_card.dart';
import 'package:self_improvement/features/body/steps/presentation/health_steps_section.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/features/reminders/presentation/reminders_section.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../../../support/pump_app.dart';
import '../../profile/support/screen_env.dart';
import 'support/explanation_sheet_support.dart';

/// The group "Schritte" of the settings with the switch "Schritte aus Health
/// übernehmen" (BS-97, design frames `4122:314` and `4122:509`): hidden
/// without an interface, the explanation before the system dialog, every state
/// of the row and its notice, and what a refused dialog, an import and a write
/// error do. A fake interface; the clock is 2026-10-03 10:00 Europe/Berlin.

const String _row = 'Schritte aus Health übernehmen';

Finder _switchOfRow() => find.byWidgetPredicate(
  (widget) => widget is AppSwitch && widget.semanticLabel == _row,
);

bool _isOn(WidgetTester tester) =>
    tester.widget<AppSwitch>(_switchOfRow()).value;

Future<ScreenEnv> _env(
  WidgetTester tester,
  FakeHealthStepsSource source, {
  Set<String>? enabledModules,
}) => createScreenEnv(
  tester,
  enabledModules: enabledModules,
  overrides: [healthStepsSourceProvider.overrideWithValue(source)],
);

Future<void> _open(
  WidgetTester tester,
  ScreenEnv env, {
  Size size = const Size(393, 852),
  double textScale = 1.0,
  AppThemeVariant theme = AppThemeVariant.light,
}) async {
  await openScreen(
    tester,
    env,
    SettingsRoutes.settings,
    size: size,
    textScale: textScale,
    theme: theme,
  );
}

/// The group alone on a page of its own, so a guideline looks only at it (the
/// settings page around it has other blocks that scroll partly out of view).
Future<void> _pumpSection(
  WidgetTester tester,
  ScreenEnv env, {
  Size size = const Size(393, 852),
  double textScale = 1.0,
}) async {
  await pumpApp(
    tester,
    const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: HealthStepsSection(),
    ),
    container: env.container,
    size: size,
    textScale: textScale,
    wrapInScaffold: true,
  );
  await settle(tester);
}

Future<void> _showRow(WidgetTester tester) async {
  await tester.ensureVisible(find.text(_row));
  await tester.pump();
}

/// Taps the row and lets the sheet open.
Future<void> _tapRow(WidgetTester tester) async {
  await _showRow(tester);
  await tester.tap(find.text(_row));
  await settle(tester);
}

void _noon(ScreenEnv env, FakeHealthStepsSource source, LocalDate day, int n) {
  final resolved = env.harness.clock.toUtc(day, const LocalTime(12, 0));
  source.addSteps((resolved as ZonedResolved).utc, n);
}

/// The wish written straight to the database, the way an import does.
Future<void> _wish(WidgetTester tester, ScreenEnv env, {bool on = true}) =>
    tester.runAsync(
      () => env.harness.database
          .update(env.harness.database.appSettings)
          .write(AppSettingsCompanion(healthStepsSyncEnabled: Value(on))),
    );

final LocalDate _today = LocalDate(2026, 10, 3);

void main() {
  group('when the group is shown (BS-97)', () {
    testWidgets('a device without an interface shows no group and no '
        'switch', (tester) async {
      final source = FakeHealthStepsSource(
        availabilityValue: HealthAvailability.unsupported,
      );
      final env = await _env(tester, source);
      await _open(tester, env);
      expect(find.byType(HealthStepsSection), findsOneWidget);
      expect(find.text('SCHRITTE'), findsNothing);
      expect(find.text(_row), findsNothing);
      expect(_switchOfRow(), findsNothing);
    });

    testWidgets('the module "Gewicht & Körper" off hides it', (tester) async {
      final source = FakeHealthStepsSource();
      final env = await _env(
        tester,
        source,
        enabledModules: {'nutrition', 'focus', 'tasks', 'gamification'},
      );
      await _open(tester, env);
      expect(find.text('SCHRITTE'), findsNothing);
      expect(find.text(_row), findsNothing);
    });

    testWidgets('with an interface: the group between the reminders and the '
        'modules, the switch off, the subtitle of the design', (tester) async {
      final source = FakeHealthStepsSource();
      final env = await _env(tester, source);
      await _open(tester, env);

      expect(find.text('SCHRITTE'), findsOneWidget);
      expect(find.text(_row), findsOneWidget);
      expect(find.text('Nur lesen, nur Schritte'), findsOneWidget);
      expect(_isOn(tester), isFalse, reason: 'off by default');
      expect(find.byType(HealthNoticeCard), findsNothing);

      final remindersBottom = tester
          .getBottomLeft(find.byType(RemindersSection))
          .dy;
      final group = tester.getTopLeft(find.text('SCHRITTE')).dy;
      final modules = tester.getTopLeft(find.text('MODULE')).dy;
      expect(group, greaterThan(remindersBottom));
      expect(group, lessThan(modules));
    });

    testWidgets('the device is asked once when the page opens and never '
        'shows a dialog or reads a step by itself', (tester) async {
      final source = FakeHealthStepsSource();
      final env = await _env(tester, source);
      await _open(tester, env);
      expect(source.availabilityCalls, 1);
      expect(source.requestAccessCalls, 0);
      expect(source.totalCalls, isEmpty);
    });

    testWidgets('the texts name the interface, never a platform', (
      tester,
    ) async {
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied);
      final env = await _env(tester, source);
      await _wish(tester, env);
      await _open(tester, env);
      await _showRow(tester);
      final texts = find
          .byType(Text)
          .evaluate()
          .map((element) => (element.widget as Text).data ?? '')
          .join(' ');
      for (final platform in ['Android', 'iOS', 'HealthKit']) {
        expect(texts.contains(platform), isFalse, reason: platform);
      }
    });
  });

  group('switching on (BS-97, frame 4122:509, AT28)', () {
    testWidgets('the explanation comes first, the system dialog only after '
        '"Weiter zur Systemabfrage"', (tester) async {
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied);
      final env = await _env(tester, source);
      await _open(tester, env);
      await _tapRow(tester);

      expect(find.byType(HealthExplanationSheet), findsOneWidget);
      expect(find.text('Schritte aus Health übernehmen?'), findsOneWidget);
      expect(
        find.text(
          'Die App liest deine Schritte aus Health Connect: nur lesend, nur '
          'Schritte, nur auf diesem Gerät. Von Hand eingetragene Tage '
          'bleiben unverändert.',
        ),
        findsOneWidget,
      );
      expect(find.text('Weiter zur Systemabfrage'), findsOneWidget);
      expect(find.text('Nicht jetzt'), findsOneWidget);
      expect(source.requestAccessCalls, 0, reason: 'nothing asks yet');
      expect(_isOn(tester), isFalse, reason: 'still the stored value');
    });

    testWidgets('"Nicht jetzt" changes nothing: no dialog, no wish, no '
        'read', (tester) async {
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied);
      final env = await _env(tester, source);
      await _open(tester, env);
      await _tapRow(tester);
      await tester.tap(find.text('Nicht jetzt'));
      await settle(tester);

      expect(find.byType(HealthExplanationSheet), findsNothing);
      expect(_isOn(tester), isFalse);
      expect(source.requestAccessCalls, 0);
      expect(source.totalCalls, isEmpty);
      expect(env.feedback.last, isNull);
    });

    testWidgets('the close button, a tap beside the sheet and the system back '
        'action do the same as "Nicht jetzt"', (tester) async {
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied);
      final env = await _env(tester, source);
      await _open(tester, env);

      // The close button of the sheet itself (the barrier has the same name).
      await _tapRow(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(HealthExplanationSheet),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AppIconButton && widget.semanticLabel == 'Schließen',
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(HealthExplanationSheet), findsNothing);
      expect(_isOn(tester), isFalse);

      // A tap on the barrier beside the sheet.
      await _tapRow(tester);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      expect(find.byType(HealthExplanationSheet), findsNothing);
      expect(_isOn(tester), isFalse);

      // The system back action.
      await _tapRow(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(HealthExplanationSheet), findsNothing);
      expect(_isOn(tester), isFalse);
      expect(source.requestAccessCalls, 0);
      expect(source.totalCalls, isEmpty);
    });

    testWidgets('"Weiter zur Systemabfrage" shows the dialog, stores the wish, '
        'reloads the seven days and says so (AT28)', (tester) async {
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied);
      final env = await _env(tester, source);
      _noon(env, source, _today, 7450);
      await _open(tester, env);
      await _tapRow(tester);
      await tester.tap(find.text('Weiter zur Systemabfrage'));
      await settle(tester);

      expect(source.requestAccessCalls, 1);
      expect(source.totalCalls, hasLength(7));
      expect(_isOn(tester), isTrue);
      expect(find.text('Zuletzt abgeglichen: heute, 10:00'), findsOneWidget);
      expect(env.feedback.last?.kind, 'saved');
      expect(env.feedback.last?.message, 'Schritte aus Health eingeschaltet.');
      expect(find.byType(HealthNoticeCard), findsNothing);
      final day = await tester.runAsync(
        () => env.harness.database.select(env.harness.database.stepDays).get(),
      );
      expect(day!.single.steps, 7450);
      expect(day.single.source, StepSource.health.key);
    });

    testWidgets('an access that is already given asks no dialog', (
      tester,
    ) async {
      final source = FakeHealthStepsSource();
      final env = await _env(tester, source);
      await _open(tester, env);
      await _tapRow(tester);
      await tester.tap(find.text('Weiter zur Systemabfrage'));
      await settle(tester);
      expect(source.requestAccessCalls, 0);
      expect(_isOn(tester), isTrue);
    });

    testWidgets('while the system dialog is open the switch waits, so a second '
        'tap cannot start a second change', (tester) async {
      final gate = Completer<void>();
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied)
        ..requestGate = gate.future;
      final env = await _env(tester, source);
      await _open(tester, env);
      await _tapRow(tester);
      await tester.tap(find.text('Weiter zur Systemabfrage'));
      await settle(tester);

      expect(source.requestAccessCalls, 1, reason: 'the dialog is open');
      expect(
        tester.widget<AppSwitch>(_switchOfRow()).onChanged,
        isNull,
        reason: 'the switch is disabled while the change runs',
      );
      await _showRow(tester);
      await tester.tap(find.text(_row), warnIfMissed: false);
      await settle(tester);
      expect(find.byType(HealthExplanationSheet), findsNothing);
      expect(source.requestAccessCalls, 1);

      gate.complete();
      await settle(tester);
      expect(tester.widget<AppSwitch>(_switchOfRow()).onChanged, isNotNull);
      expect(_isOn(tester), isTrue);
    });

    testWidgets('while the system dialog is open the buttons of the notice '
        'wait as well', (tester) async {
      final gate = Completer<void>();
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied)
        ..accessAfterRequest = HealthAccess.denied;
      final env = await _env(tester, source);
      await _wish(tester, env);
      await _open(tester, env);
      await _showRow(tester);
      expect(find.byType(HealthNoticeCard), findsOneWidget);

      HealthTextAction action(String label) => tester.widget<HealthTextAction>(
        find.widgetWithText(HealthTextAction, label),
      );
      expect(action('Zugriff erlauben').onPressed, isNotNull);
      expect(action('Einstellungen öffnen').onPressed, isNotNull);

      source.requestGate = gate.future;
      await tester.ensureVisible(find.text('Zugriff erlauben'));
      await tester.tap(find.text('Zugriff erlauben'));
      await settle(tester);
      expect(find.byType(HealthExplanationSheet), findsOneWidget);
      expect(source.requestAccessCalls, 0, reason: 'the explanation is first');
      await tester.tap(find.text('Weiter zur Systemabfrage'));
      await settle(tester);
      expect(source.requestAccessCalls, 1, reason: 'the dialog is open');
      expect(action('Zugriff erlauben').onPressed, isNull);
      expect(action('Einstellungen öffnen').onPressed, isNull);

      gate.complete();
      await settle(tester);
      expect(action('Zugriff erlauben').onPressed, isNotNull);
      expect(action('Einstellungen öffnen').onPressed, isNotNull);
    });

    testWidgets('a refused dialog keeps the switch on with an honest state '
        'and the way out, and reads nothing (AT28)', (tester) async {
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied)
        ..accessAfterRequest = HealthAccess.denied;
      final env = await _env(tester, source);
      _noon(env, source, _today, 7450);
      await _open(tester, env);
      await _tapRow(tester);
      await tester.tap(find.text('Weiter zur Systemabfrage'));
      await settle(tester);

      expect(_isOn(tester), isTrue);
      expect(
        find.text('Kein Zugriff auf Health Connect'),
        findsNWidgets(2),
        reason: 'the subtitle of the row and the title of the notice',
      );
      expect(find.byType(HealthNoticeCard), findsOneWidget);
      expect(find.text('Zugriff erlauben'), findsOneWidget);
      expect(find.text('Einstellungen öffnen'), findsOneWidget);
      expect(source.totalCalls, isEmpty);
      expect(env.feedback.last?.kind, 'info');
      expect(
        env.feedback.last?.message,
        'Zugriff nicht erteilt. Die Schritte werden nicht übernommen, bis du '
        'den Zugriff erlaubst.',
      );
    });

    testWidgets('"Zugriff erlauben" in the notice gets the access and '
        'compares', (tester) async {
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied)
        ..accessAfterRequest = HealthAccess.denied;
      final env = await _env(tester, source);
      _noon(env, source, _today, 4000);
      await _open(tester, env);
      await _tapRow(tester);
      await tester.tap(find.text('Weiter zur Systemabfrage'));
      await settle(tester);
      expect(find.byType(HealthNoticeCard), findsOneWidget);

      source.accessAfterRequest = HealthAccess.granted;
      await tester.ensureVisible(find.text('Zugriff erlauben'));
      await tester.tap(find.text('Zugriff erlauben'));
      await settle(tester);
      expect(find.byType(HealthExplanationSheet), findsOneWidget);
      await tester.tap(find.text('Weiter zur Systemabfrage'));
      await settle(tester);
      expect(find.byType(HealthNoticeCard), findsNothing);
      expect(find.text('Zuletzt abgeglichen: heute, 10:00'), findsOneWidget);
      expect(source.totalCalls, hasLength(7));
    });

    testWidgets('the interface is not installed: the sheet says so, no '
        'dialog follows, the notice shows the way to install it', (
      tester,
    ) async {
      final source = FakeHealthStepsSource(
        availabilityValue: HealthAvailability.missing,
      );
      final env = await _env(tester, source);
      await _open(tester, env);
      await _tapRow(tester);
      expect(
        find.textContaining(
          'Health Connect ist auf diesem Gerät nicht '
          'installiert',
        ),
        findsOneWidget,
      );
      expect(find.text('Einschalten'), findsOneWidget);
      expect(find.text('Weiter zur Systemabfrage'), findsNothing);
      await tester.tap(find.text('Einschalten'));
      await settle(tester);

      expect(source.requestAccessCalls, 0);
      expect(_isOn(tester), isTrue);
      expect(
        find.text('Health Connect ist nicht installiert'),
        findsNWidgets(2),
      );
      expect(find.text('Health Connect installieren'), findsOneWidget);
      await tester.ensureVisible(find.text('Health Connect installieren'));
      await tester.tap(find.text('Health Connect installieren'));
      await settle(tester);
      expect(source.installPageCalls, 1);
    });

    testWidgets('the interface is outdated: the sheet and the notice say so '
        '(AT28)', (tester) async {
      final source = FakeHealthStepsSource(
        availabilityValue: HealthAvailability.updateRequired,
      );
      final env = await _env(tester, source);
      await _open(tester, env);
      await _tapRow(tester);
      expect(
        find.textContaining('Health Connect ist auf diesem Gerät veraltet'),
        findsOneWidget,
      );
      await tester.tap(find.text('Einschalten'));
      await settle(tester);
      expect(find.text('Health Connect ist veraltet'), findsNWidgets(2));
      expect(find.text('Health Connect aktualisieren'), findsOneWidget);
    });

    testWidgets('a wish that cannot be stored keeps the old position and '
        'offers a retry (AT27)', (tester) async {
      final source = FakeHealthStepsSource();
      final env = await _env(tester, source);
      await tester.runAsync(
        () => env.harness.database.customStatement(
          'CREATE TRIGGER refuse_settings BEFORE UPDATE ON app_settings '
          "BEGIN SELECT RAISE(ABORT, 'refused'); END",
        ),
      );
      await _open(tester, env);
      await _tapRow(tester);
      await tester.tap(find.text('Weiter zur Systemabfrage'));
      await settle(tester);

      expect(_isOn(tester), isFalse);
      expect(env.feedback.last?.kind, 'error');
      expect(
        env.feedback.last?.message,
        'Die Einstellung konnte nicht gespeichert werden. Der bisherige Wert '
        'bleibt aktiv.',
      );
      expect(env.feedback.last?.onRetry, isNotNull);
      expect(source.requestAccessCalls, 0);
      expect(source.totalCalls, isEmpty);
    });
  });

  group('"Zugriff erlauben" in the notice shows the explanation first '
      '(BS-97, R2-01, AT28)', () {
    /// The wish came with an imported backup: the explanation was never shown
    /// on this device and the system has not been asked.
    Future<ScreenEnv> importedWithoutAccess(
      WidgetTester tester,
      FakeHealthStepsSource source,
    ) async {
      final env = await _env(tester, source);
      _noon(env, source, _today, 4000);
      await _wish(tester, env);
      await _open(tester, env);
      expect(find.byType(HealthNoticeCard), findsOneWidget);
      expect(find.byType(HealthExplanationSheet), findsNothing);
      return env;
    }

    Future<void> tapAllow(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Zugriff erlauben'));
      await tester.tap(find.text('Zugriff erlauben'));
      await settle(tester);
    }

    testWidgets('(BS-97, R2-01, AT28) after an import with the switch on the '
        'tap shows the explanation and no dialog, "Weiter zur Systemabfrage" '
        'asks once and compares', (tester) async {
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied)
        ..accessAfterRequest = HealthAccess.granted;
      final env = await importedWithoutAccess(tester, source);

      await tapAllow(tester);
      expect(find.byType(HealthExplanationSheet), findsOneWidget);
      expect(find.text('Schritte aus Health übernehmen?'), findsOneWidget);
      expect(find.text('Weiter zur Systemabfrage'), findsOneWidget);
      expect(find.text('Nicht jetzt'), findsOneWidget);
      expect(source.requestAccessCalls, 0, reason: 'no dialog yet');
      expect(source.totalCalls, isEmpty, reason: 'nothing is read yet');

      await tester.tap(find.text('Weiter zur Systemabfrage'));
      await settle(tester);
      expect(find.byType(HealthExplanationSheet), findsNothing);
      expect(source.requestAccessCalls, 1);
      expect(find.byType(HealthNoticeCard), findsNothing);
      expect(source.totalCalls, hasLength(7));
      expect(
        env.feedback.last?.message,
        'Zugriff erlaubt. Die Schritte werden übernommen.',
      );
    });

    for (final how in SheetDismissal.values) {
      testWidgets('(BS-97, R2-01, AT28) ${how.label} closes the explanation '
          'and changes nothing: no dialog, nothing read, the notice stays', (
        tester,
      ) async {
        final source = FakeHealthStepsSource(accessValue: HealthAccess.denied)
          ..accessAfterRequest = HealthAccess.granted;
        final env = await importedWithoutAccess(tester, source);

        await tapAllow(tester);
        expect(find.byType(HealthExplanationSheet), findsOneWidget);
        await dismissExplanationSheet(tester, how, () => settle(tester));

        expect(find.byType(HealthExplanationSheet), findsNothing);
        expect(source.requestAccessCalls, 0);
        expect(source.totalCalls, isEmpty);
        expect(find.byType(HealthNoticeCard), findsOneWidget);
        expect(_isOn(tester), isTrue, reason: 'the wish stays');
        expect(env.feedback.last, isNull);
        // The buttons work again: a second tap shows the explanation again.
        await tapAllow(tester);
        expect(find.byType(HealthExplanationSheet), findsOneWidget);
        expect(source.requestAccessCalls, 0);
      });
    }

    testWidgets('(BS-97, R2-01, AT28) the notice that asks again after a '
        'refusal shows the explanation again', (tester) async {
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied)
        ..accessAfterRequest = HealthAccess.denied;
      final env = await importedWithoutAccess(tester, source);

      for (var round = 1; round <= 2; round++) {
        await tapAllow(tester);
        expect(find.byType(HealthExplanationSheet), findsOneWidget);
        expect(source.requestAccessCalls, round - 1);
        await tester.tap(find.text('Weiter zur Systemabfrage'));
        await settle(tester);
        expect(source.requestAccessCalls, round);
        expect(find.byType(HealthNoticeCard), findsOneWidget);
      }
      expect(env.feedback.last?.kind, 'info');
    });

    testWidgets('(BS-97, R2-01) the other button of the notice asks for no '
        'explanation: it opens the system settings at once', (tester) async {
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied);
      await importedWithoutAccess(tester, source);
      await tester.ensureVisible(find.text('Einstellungen öffnen'));
      await tester.tap(find.text('Einstellungen öffnen'));
      await settle(tester);
      expect(find.byType(HealthExplanationSheet), findsNothing);
      expect(source.accessSettingsCalls, 1);
      expect(source.requestAccessCalls, 0);
    });
  });

  group('switching off and the other states of the row (BS-97)', () {
    testWidgets('switching off keeps every value and says so', (tester) async {
      final source = FakeHealthStepsSource();
      final env = await _env(tester, source);
      _noon(env, source, _today, 7450);
      await _open(tester, env);
      await _tapRow(tester);
      await tester.tap(find.text('Weiter zur Systemabfrage'));
      await settle(tester);
      expect(_isOn(tester), isTrue);

      source.clearCalls();
      await _showRow(tester);
      await tester.tap(find.text(_row));
      await settle(tester);
      expect(
        find.byType(HealthExplanationSheet),
        findsNothing,
        reason: 'switching off asks nothing',
      );
      expect(_isOn(tester), isFalse);
      expect(find.text('Nur lesen, nur Schritte'), findsOneWidget);
      expect(
        env.feedback.last?.message,
        'Schritte aus Health ausgeschaltet. Bereits übernommene Werte '
        'bleiben.',
      );
      final days = await tester.runAsync(
        () => env.harness.database.select(env.harness.database.stepDays).get(),
      );
      expect(days, hasLength(1));
      expect(source.totalCalls, isEmpty);
    });

    testWidgets('a switch that is on after an import without access: honest '
        'state, notice, no dialog, nothing read (AT30)', (tester) async {
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied);
      final env = await _env(tester, source);
      await _wish(tester, env);
      await _open(tester, env);

      expect(_isOn(tester), isTrue);
      expect(find.text('Kein Zugriff auf Health Connect'), findsNWidgets(2));
      expect(find.byType(HealthNoticeCard), findsOneWidget);
      expect(source.requestAccessCalls, 0);
      expect(source.totalCalls, isEmpty);
    });

    testWidgets('the last comparison and a running one show in the '
        'subtitle', (tester) async {
      final source = FakeHealthStepsSource();
      final env = await _env(tester, source);
      await _wish(tester, env);
      await _open(tester, env);
      expect(find.text('Nur lesen, nur Schritte'), findsNothing);
      // The switch is on, the first comparison has not run yet.
      expect(find.text('Noch nicht abgeglichen'), findsOneWidget);

      await tester.runCommand(
        () => env.container
            .read(healthStepsControllerProvider.notifier)
            .reconcile(HealthSyncTrigger.start),
      );
      expect(find.text('Zuletzt abgeglichen: heute, 10:00'), findsOneWidget);

      final gate = Completer<void>();
      source.totalGate = gate.future;
      unawaited(
        env.container
            .read(healthStepsControllerProvider.notifier)
            .reconcile(HealthSyncTrigger.action),
      );
      await settle(tester);
      expect(find.text('Wird abgeglichen …'), findsOneWidget);
      gate.complete();
      await settle(tester);
      expect(find.text('Wird abgeglichen …'), findsNothing);
    });

    testWidgets('a failed comparison is said so with a way to repeat it', (
      tester,
    ) async {
      final source = FakeHealthStepsSource();
      final env = await _env(tester, source);
      await _wish(tester, env);
      await _open(tester, env);
      source.totalFailure = StateError('x');
      await tester.runCommand(
        () => env.container
            .read(healthStepsControllerProvider.notifier)
            .reconcile(HealthSyncTrigger.action),
      );
      expect(find.text('Abgleich fehlgeschlagen'), findsNWidgets(2));
      expect(find.text('Erneut versuchen'), findsOneWidget);

      source.totalFailure = null;
      await tester.ensureVisible(find.text('Erneut versuchen'));
      await tester.tap(find.text('Erneut versuchen'));
      await settle(tester);
      expect(find.text('Abgleich fehlgeschlagen'), findsNothing);
      expect(find.text('Zuletzt abgeglichen: heute, 10:00'), findsOneWidget);
    });

    testWidgets('"Einstellungen öffnen" opens the system settings (frame '
        '4122:667)', (tester) async {
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied);
      final env = await _env(tester, source);
      await _wish(tester, env);
      await _open(tester, env);
      await tester.ensureVisible(find.text('Einstellungen öffnen'));
      await tester.tap(find.text('Einstellungen öffnen'));
      await settle(tester);
      expect(source.accessSettingsCalls, 1);
    });
  });

  group('layout and accessibility (BS-97, AT33, AT34, AT35)', () {
    Future<void> prepare(
      WidgetTester tester,
      ScreenEnv env,
      FakeHealthStepsSource source,
      String state,
    ) async {
      switch (state) {
        case 'off':
          break;
        case 'ready':
          _noon(env, source, _today, 7450);
          await _wish(tester, env);
          await tester.runCommand(
            () => env.container
                .read(healthStepsControllerProvider.notifier)
                .reconcile(HealthSyncTrigger.start),
          );
        case 'no-access':
          source.accessValue = HealthAccess.denied;
          await _wish(tester, env);
        case 'missing':
          source.availabilityValue = HealthAvailability.missing;
          await _wish(tester, env);
        case 'outdated':
          source.availabilityValue = HealthAvailability.updateRequired;
          await _wish(tester, env);
      }
    }

    const states = ['off', 'ready', 'no-access', 'missing', 'outdated'];

    for (final width in [320.0, 360.0, 393.0, 430.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('the group fits $width px at ${(scale * 100).round()} % '
            'text, keeps 48 x 48 controls and meets the guidelines (AT33, '
            'AT34)', (tester) async {
          for (final state in states) {
            final handle = tester.ensureSemantics();
            final source = FakeHealthStepsSource();
            final env = await _env(tester, source);
            await prepare(tester, env, source, state);
            await _pumpSection(
              tester,
              env,
              size: Size(width, 800),
              textScale: scale,
            );
            expect(tester.takeException(), isNull, reason: state);
            expect(find.text(_row), findsOneWidget, reason: state);
            final row = tester.getSize(
              find
                  .ancestor(
                    of: find.text(_row),
                    matching: find.byType(EntryListTile),
                  )
                  .first,
            );
            expect(row.height, greaterThanOrEqualTo(48), reason: state);
            for (final element in find.byType(HealthTextAction).evaluate()) {
              final size = tester.getSize(find.byWidget(element.widget));
              expect(size.width, greaterThanOrEqualTo(48), reason: state);
              expect(size.height, greaterThanOrEqualTo(48), reason: state);
            }
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            handle.dispose();
            await tester.pumpWidget(const SizedBox.shrink());
          }
        });
      }
    }

    testWidgets('the explanation sheet fits every width at 200 % text with '
        'both buttons reachable (AT33)', (tester) async {
      for (final width in [320.0, 360.0, 393.0, 430.0]) {
        final source = FakeHealthStepsSource();
        final env = await _env(tester, source);
        await _open(tester, env, size: Size(width, 700), textScale: 2.0);
        await _tapRow(tester);
        expect(tester.takeException(), isNull, reason: '$width');
        for (final label in ['Weiter zur Systemabfrage', 'Nicht jetzt']) {
          await tester.ensureVisible(find.text(label));
          final size = tester.getSize(
            find
                .ancestor(of: find.text(label), matching: find.byType(InkWell))
                .first,
          );
          expect(
            size.height,
            greaterThanOrEqualTo(48),
            reason: '$width $label',
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    for (final theme in AppThemeVariant.values) {
      testWidgets('the group, its notices and the sheet render in the '
          '${theme.name} theme (AT35)', (tester) async {
        for (final state in states) {
          final source = FakeHealthStepsSource();
          final env = await _env(tester, source);
          await prepare(tester, env, source, state);
          await _open(tester, env, theme: theme);
          await _showRow(tester);
          expect(tester.takeException(), isNull, reason: state);
          if (state == 'off') {
            await _tapRow(tester);
            expect(find.byType(HealthExplanationSheet), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }

    testWidgets('the switch is one switch with a name and a state, the notice '
        'a live region with named buttons (AT34)', (tester) async {
      final handle = tester.ensureSemantics();
      final source = FakeHealthStepsSource(accessValue: HealthAccess.denied);
      final env = await _env(tester, source);
      await _wish(tester, env);
      await _open(tester, env);
      await _showRow(tester);

      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^$_row')).first,
      );
      expect(node.label, contains(_row));
      expect(node.label, contains('Kein Zugriff auf Health Connect'));
      expect(node.flagsCollection.isToggled, Tristate.isTrue, reason: 'on');
      expect(
        find.bySemanticsLabel(
          'Kein Zugriff auf Health Connect. Die Schritte werden nicht '
          'übernommen. Erlaube den Zugriff auf Schritte in den '
          'Systemeinstellungen.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Zugriff auf Schritte erlauben'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Systemeinstellungen für den Zugriff öffnen'),
        findsOneWidget,
      );
      final notice = tester.getSemantics(find.byType(HealthNoticeCard));
      expect(
        notice.flagsCollection.isLiveRegion,
        isTrue,
        reason: 'the notice is announced when it appears',
      );
      handle.dispose();
    });

    testWidgets('the explanation is a route with the question as its name '
        '(AT34)', (tester) async {
      final handle = tester.ensureSemantics();
      final source = FakeHealthStepsSource();
      final env = await _env(tester, source);
      await _open(tester, env);
      await _tapRow(tester);
      expect(
        find.bySemanticsLabel('Schritte aus Health übernehmen?'),
        findsWidgets,
      );
      handle.dispose();
    });
  });
}
