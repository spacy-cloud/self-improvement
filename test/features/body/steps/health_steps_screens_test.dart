import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/health/application/health_providers.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';
import 'package:self_improvement/core/health/platform/fake_health_steps_source.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/body/body_module.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_controller.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_sync.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/body/steps/domain/step_day.dart';
import 'package:self_improvement/features/body/steps/domain/step_source.dart';
import 'package:self_improvement/features/body/steps/presentation/health_notice_card.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_dashboard_card.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_routes.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../../../support/pump_app.dart';

/// "Meine Schritte", the card on Home and the form with the comparison with
/// Health on (BS-97, design frames `4122:553`, `4122:667`, `4122:777`,
/// `4123:316`): the source, the notices with their way out, the typed-in
/// value that keeps its priority, and the layout and accessibility of every
/// state. A fake interface and a real in-memory database; the clock is
/// 2026-10-03 10:00 Europe/Berlin, the daily goal 10.000 steps.

class _Env {
  _Env({
    required this.harness,
    required this.container,
    required this.feedback,
    required this.source,
  });

  final DataHarness harness;
  final ProviderContainer container;
  final RecordingFeedbackService feedback;
  final FakeHealthStepsSource source;
}

Future<_Env> _env(WidgetTester tester) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final harness = (await tester.runAsync(
    () => DataHarness.create(realProjection: true),
  ))!;
  addTearDown(() async {
    await tester.runAsync(harness.dispose);
  });
  await tester.runAsync(
    () => harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1)),
  );
  final feedback = RecordingFeedbackService(ids: harness.ids);
  final source = FakeHealthStepsSource();
  final container = harness.createContainer(
    overrides: [
      feedbackServiceProvider.overrideWithValue(feedback),
      healthStepsSourceProvider.overrideWithValue(source),
    ],
  );
  return _Env(
    harness: harness,
    container: container,
    feedback: feedback,
    source: source,
  );
}

List<RouteBase> _routes() => [
  GoRoute(
    path: '/',
    builder: (context, state) => const Scaffold(
      body: SingleChildScrollView(child: StepsDashboardCard()),
    ),
  ),
  ...const BodyModule().routes,
];

Future<GoRouter> _open(
  WidgetTester tester,
  _Env env,
  String location, {
  Size size = const Size(393, 852),
  double textScale = 1.0,
  AppThemeVariant theme = AppThemeVariant.light,
}) => pumpRouterApp(
  tester,
  routes: _routes(),
  initialLocation: location,
  container: env.container,
  size: size,
  textScale: textScale,
  theme: theme,
);

final LocalDate _today = LocalDate(2026, 10, 3);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.pumpAndSettle();
}

/// A record of [count] steps at local noon of [day].
void _noon(_Env env, LocalDate day, int count) {
  final resolved = env.harness.clock.toUtc(day, const LocalTime(12, 0));
  env.source.addSteps((resolved as ZonedResolved).utc, count);
}

/// The wish "Schritte aus Health übernehmen" is on (written straight to the
/// database, the way an import does).
Future<void> _wish(WidgetTester tester, _Env env) => tester.runAsync(
  () => env.harness.database
      .update(env.harness.database.appSettings)
      .write(const AppSettingsCompanion(healthStepsSyncEnabled: Value(true))),
);

/// Runs one comparison (the start of the app) before the screen opens.
Future<void> _compare(WidgetTester tester, _Env env) => tester.runCommand(
  () => env.container
      .read(healthStepsControllerProvider.notifier)
      .reconcile(HealthSyncTrigger.start),
);

/// The switch is on and the first comparison ran: Health delivers.
Future<void> _delivering(
  WidgetTester tester,
  _Env env, {
  int? today = 7450,
}) async {
  if (today != null) {
    _noon(env, _today, today);
  }
  await _wish(tester, env);
  await _compare(tester, env);
}

Future<void> _record(
  WidgetTester tester,
  _Env env,
  LocalDate date,
  int steps,
) async {
  await tester.runCommand(
    () => env.container
        .read(stepsRepositoryProvider)
        .setSteps(commandId: env.harness.ids.newId(), date: date, steps: steps),
  );
}

Future<StepDay?> _day(WidgetTester tester, _Env env, LocalDate date) => tester
    .runAsync(() => env.container.read(stepsRepositoryProvider).findDay(date))
    .then((value) => value);

Finder _action(String label) => find.bySemanticsLabel(label);

void main() {
  group('overview: the source and the notices (BS-97)', () {
    testWidgets('switch off: nothing of Health shows, the hint and the source '
        'are the ones of a value typed in', (tester) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 7450);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);

      expect(find.byType(HealthSourceCard), findsNothing);
      expect(find.byType(HealthNoticeCard), findsNothing);
      expect(find.text('Health Connect'), findsNothing);
      expect(find.text('Von Hand'), findsOneWidget);
      expect(find.text('Einmal am Tag eintragen'), findsOneWidget);
      expect(find.text('Health liefert den Tageswert'), findsNothing);
      expect(env.source.availabilityCalls, 0, reason: 'nothing asks');
    });

    testWidgets('Health delivers: the source card, the value from Health and '
        'the hint about the order of the sources (frame 4122:553)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _delivering(tester, env);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);

      expect(find.byType(HealthSourceCard), findsOneWidget);
      expect(find.text('Health Connect'), findsOneWidget);
      expect(find.text('Zuletzt: heute, 10:00'), findsOneWidget);
      expect(find.text('Aktualisieren'), findsOneWidget);
      expect(find.textContaining('7.450'), findsWidgets);
      expect(find.text('Noch 2.550'), findsOneWidget);
      expect(find.text('75 % vom Tagesziel'), findsOneWidget);
      expect(find.text('Aus Health'), findsOneWidget);
      expect(find.text('Von Hand'), findsNothing);
      expect(find.text('Health liefert den Tageswert'), findsOneWidget);
      expect(
        find.text(
          'Ein von Hand eingetragener Wert hat Vorrang und wird nicht '
          'überschrieben. Health füllt nur Tage ohne eigenen Wert.',
        ),
        findsOneWidget,
      );
      expect(find.text('Einmal am Tag eintragen'), findsNothing);
      expect(find.byType(HealthNoticeCard), findsNothing);
      // The manual way stays: the action below.
      expect(find.text('Schritte eintragen'), findsOneWidget);
    });

    testWidgets('the days that Health filled show up in the history with '
        'their values', (tester) async {
      final env = await _env(tester);
      _noon(env, _today, 7450);
      _noon(env, _today.addDays(-1), 12800);
      await _wish(tester, env);
      await _compare(tester, env);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);
      expect(find.text('12.800'), findsWidgets);
      expect(find.textContaining('2 von 7 Tagen erfasst'), findsOneWidget);
    });

    testWidgets('a day Health has no data for says so, not "noch nicht '
        'eingetragen"', (tester) async {
      final env = await _env(tester);
      await _delivering(tester, env, today: null);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);

      expect(find.byType(HealthSourceCard), findsOneWidget);
      expect(
        find.text('Health meldet für heute noch keine Schritte'),
        findsOneWidget,
      );
      expect(find.text('Heute noch nicht eingetragen'), findsNothing);
      expect(find.text('Aus Health'), findsNothing);
      expect(find.text('Von Hand'), findsNothing);
    });

    testWidgets('a value typed in keeps its priority and its source', (
      tester,
    ) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 5000);
      await _delivering(tester, env, today: 9000);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);

      expect(find.text('Von Hand'), findsOneWidget);
      expect(find.text('Aus Health'), findsNothing);
      expect(find.textContaining('5.000'), findsWidgets);
      expect(find.byType(HealthSourceCard), findsOneWidget);
      await tester.tap(find.text('Aktualisieren'));
      await _settle(tester);
      expect((await _day(tester, env, _today))!.steps, 5000);
      expect((await _day(tester, env, _today))!.source, StepSource.manual);
    });

    testWidgets('"Aktualisieren" compares now, shows the new value and the '
        'time, and says so', (tester) async {
      final env = await _env(tester);
      await _delivering(tester, env, today: 3000);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);
      expect(find.textContaining('3.000'), findsWidgets);

      env.source
        ..clearSteps()
        ..clearCalls();
      _noon(env, _today, 4200);
      env.harness.clock.advance(const Duration(minutes: 5));
      await tester.tap(find.text('Aktualisieren'));
      await _settle(tester);

      expect(env.source.totalCalls, hasLength(7));
      expect((await _day(tester, env, _today))!.steps, 4200);
      expect(find.textContaining('4.200'), findsWidgets);
      expect(find.text('Zuletzt: heute, 10:05'), findsOneWidget);
      expect(
        env.feedback.last?.message,
        'Schritte aus Health Connect abgeglichen.',
      );
    });

    testWidgets('while a comparison runs the line says so and the action '
        'waits', (tester) async {
      final env = await _env(tester);
      await _delivering(tester, env);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);

      final gate = Completer<void>();
      env.source.totalGate = gate.future;
      await tester.tap(find.text('Aktualisieren'));
      await _settle(tester);
      expect(find.text('Wird abgeglichen …'), findsOneWidget);
      final refresh = tester.widget<HealthTextAction>(
        find.byType(HealthTextAction),
      );
      expect(refresh.onPressed, isNull, reason: 'a second tap does nothing');

      gate.complete();
      await _settle(tester);
      expect(find.text('Wird abgeglichen …'), findsNothing);
      expect(find.text('Zuletzt: heute, 10:00'), findsOneWidget);
    });

    testWidgets('a failed comparison is said so and can be repeated', (
      tester,
    ) async {
      final env = await _env(tester);
      await _delivering(tester, env);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);

      env.source.totalFailure = StateError('x');
      await tester.tap(find.text('Aktualisieren'));
      await _settle(tester);
      expect(find.text('Abgleich fehlgeschlagen'), findsOneWidget);
      expect(env.feedback.last?.kind, 'error');
      expect(
        env.feedback.last?.message,
        'Der Abgleich ist fehlgeschlagen. Deine Werte sind unverändert.',
      );
      expect(find.textContaining('7.450'), findsWidgets, reason: 'values stay');

      env.source.totalFailure = null;
      await tester.tap(find.text('Aktualisieren'));
      await _settle(tester);
      expect(find.text('Abgleich fehlgeschlagen'), findsNothing);
      expect(find.text('Zuletzt: heute, 10:00'), findsOneWidget);
    });

    testWidgets('no access (frame 4122:667): the notice with both ways out, '
        'the value stays, nothing is read', (tester) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 7450);
      await _wish(tester, env);
      env.source.accessValue = HealthAccess.denied;
      await _compare(tester, env);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);

      expect(find.byType(HealthNoticeCard), findsOneWidget);
      expect(find.text('Kein Zugriff auf Health Connect'), findsOneWidget);
      expect(
        find.text(
          'Die Schritte werden nicht übernommen. Erlaube den Zugriff auf '
          'Schritte in den Systemeinstellungen.',
        ),
        findsOneWidget,
      );
      expect(find.text('Zugriff erlauben'), findsOneWidget);
      expect(find.text('Einstellungen öffnen'), findsOneWidget);
      expect(find.byType(HealthSourceCard), findsNothing);
      expect(find.textContaining('7.450'), findsWidgets);
      expect(find.text('Von Hand'), findsOneWidget);
      expect(find.text('Einmal am Tag eintragen'), findsOneWidget);
      expect(env.source.totalCalls, isEmpty);
      expect(env.source.requestAccessCalls, 0, reason: 'only a tap asks');
    });

    testWidgets('"Zugriff erlauben" shows the dialog and, when it was given, '
        'fills the days and replaces the notice by the source', (tester) async {
      final env = await _env(tester);
      _noon(env, _today, 4000);
      await _wish(tester, env);
      env.source.accessValue = HealthAccess.denied;
      await _compare(tester, env);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);

      await tester.tap(find.text('Zugriff erlauben'));
      await _settle(tester);
      expect(env.source.requestAccessCalls, 1);
      expect(find.byType(HealthNoticeCard), findsNothing);
      expect(find.byType(HealthSourceCard), findsOneWidget);
      expect(find.textContaining('4.000'), findsWidgets);
      expect(
        env.feedback.last?.message,
        'Zugriff erlaubt. Die Schritte werden übernommen.',
      );
    });

    testWidgets('a refused dialog stays honest and points to the settings', (
      tester,
    ) async {
      final env = await _env(tester);
      await _wish(tester, env);
      env.source
        ..accessValue = HealthAccess.denied
        ..accessAfterRequest = HealthAccess.denied;
      await _compare(tester, env);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);

      await tester.tap(find.text('Zugriff erlauben'));
      await _settle(tester);
      expect(find.byType(HealthNoticeCard), findsOneWidget);
      expect(env.feedback.last?.kind, 'info');
      expect(env.feedback.last?.message, contains('„Einstellungen öffnen“'));
    });

    testWidgets('"Einstellungen öffnen" opens the system settings and says '
        'so when it cannot', (tester) async {
      final env = await _env(tester);
      await _wish(tester, env);
      env.source.accessValue = HealthAccess.denied;
      await _compare(tester, env);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);

      await tester.tap(find.text('Einstellungen öffnen'));
      await _settle(tester);
      expect(env.source.accessSettingsCalls, 1);
      expect(env.feedback.last, isNull);

      env.source.accessSettingsCanOpen = false;
      await tester.tap(find.text('Einstellungen öffnen'));
      await _settle(tester);
      expect(env.source.accessSettingsCalls, 2);
      expect(env.feedback.last?.kind, 'info');
      expect(
        env.feedback.last?.message,
        contains('Einstellungen von Health Connect'),
      );
    });

    testWidgets('the interface is missing (frame 4122:777): the notice and '
        'the way to install it', (tester) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 7450);
      await _wish(tester, env);
      env.source.availabilityValue = HealthAvailability.missing;
      await _compare(tester, env);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);

      expect(find.text('Health Connect ist nicht installiert'), findsOneWidget);
      expect(
        find.text(
          'Installiere Health Connect, um Schritte zu übernehmen. Bis dahin '
          'trägst du Schritte weiter von Hand ein.',
        ),
        findsOneWidget,
      );
      expect(find.text('Health Connect installieren'), findsOneWidget);
      expect(find.byType(HealthSourceCard), findsNothing);
      expect(find.textContaining('7.450'), findsWidgets);

      await tester.tap(find.text('Health Connect installieren'));
      await _settle(tester);
      expect(env.source.installPageCalls, 1);
      expect(env.feedback.last, isNull);

      env.source.installPageCanOpen = false;
      await tester.tap(find.text('Health Connect installieren'));
      await _settle(tester);
      expect(env.feedback.last?.kind, 'info');
      expect(
        env.feedback.last?.message,
        contains('über den App-Store deines Geräts'),
      );
    });

    testWidgets('the interface is outdated: the notice and the way to update '
        'it', (tester) async {
      final env = await _env(tester);
      await _wish(tester, env);
      env.source.availabilityValue = HealthAvailability.updateRequired;
      await _compare(tester, env);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);
      expect(find.text('Health Connect ist veraltet'), findsOneWidget);
      expect(find.text('Health Connect aktualisieren'), findsOneWidget);
    });

    testWidgets('a device without an interface and a switched-off module '
        'show nothing of Health, even with the wish on', (tester) async {
      final env = await _env(tester);
      await _wish(tester, env);
      env.source.availabilityValue = HealthAvailability.unsupported;
      await _compare(tester, env);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);
      expect(find.byType(HealthSourceCard), findsNothing);
      expect(find.byType(HealthNoticeCard), findsNothing);
      expect(find.text('Einmal am Tag eintragen'), findsOneWidget);
    });

    testWidgets('the texts name the interface, never a platform', (
      tester,
    ) async {
      final env = await _env(tester);
      await _wish(tester, env);
      env.source.accessValue = HealthAccess.denied;
      await _compare(tester, env);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);
      final texts = find
          .byType(Text)
          .evaluate()
          .map((element) => (element.widget as Text).data ?? '')
          .join(' ');
      expect(texts, isNot(contains('Android')));
      expect(texts, isNot(contains('iOS')));
      expect(texts, isNot(contains('HealthKit')));
    });
  });

  group('the form with a day from Health (BS-97)', () {
    testWidgets('says the value is from Health and that saving makes it '
        'a value typed in (AT15)', (tester) async {
      final env = await _env(tester);
      await _delivering(tester, env, today: 7450);
      await _open(tester, env, StepsRoutes.create);
      await _settle(tester);

      expect(
        find.text('Für heute sind schon 7.450 aus Health eingetragen'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Wenn du speicherst, gilt dein Wert: Health ändert diesen Tag '
          'danach nicht mehr.',
        ),
        findsOneWidget,
      );
      expect(find.text('Tageswert ersetzen'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '8000');
      await tester.pump();
      await tester.tap(find.text('Tageswert ersetzen'));
      await _settle(tester);
      final day = (await _day(tester, env, _today))!;
      expect(day.steps, 8000);
      expect(day.source, StepSource.manual);
      expect(env.feedback.last?.message, 'Schritte aktualisiert');
    });

    testWidgets('the undo of that save gives the day back to Health (AT15)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _delivering(tester, env, today: 7450);
      await _open(tester, env, StepsRoutes.create);
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, '8000');
      await tester.pump();
      await tester.tap(find.text('Tageswert ersetzen'));
      await _settle(tester);
      await tester.runAsync(() => env.feedback.last!.undo!.perform());
      final day = (await _day(tester, env, _today))!;
      expect(day.steps, 7450);
      expect(day.source, StepSource.health);
    });

    testWidgets('a value typed in keeps the notice of V1', (tester) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 7450);
      await _open(tester, env, StepsRoutes.create);
      await _settle(tester);
      expect(
        find.text('Für heute sind schon 7.450 eingetragen'),
        findsOneWidget,
      );
      expect(
        find.text('Beim Speichern wird der Tageswert ersetzt, nicht addiert.'),
        findsOneWidget,
      );
    });

    testWidgets('deleting a day names the refill while the switch is on and '
        'not while it is off', (tester) async {
      final env = await _env(tester);
      await _delivering(tester, env, today: 7450);
      await _open(tester, env, StepsRoutes.create);
      await _settle(tester);
      await tester.ensureVisible(find.text('Tageswert löschen'));
      await tester.tap(find.text('Tageswert löschen'));
      await _settle(tester);
      expect(
        find.textContaining(
          'trägt Health den Tag beim nächsten Abgleich '
          'wieder ein',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Abbrechen'));
      await _settle(tester);

      // Switch off: the sentence is gone.
      await tester.runCommand(
        () => env.container
            .read(healthStepsControllerProvider.notifier)
            .disable(),
      );
      await tester.ensureVisible(find.text('Tageswert löschen'));
      await tester.tap(find.text('Tageswert löschen'));
      await _settle(tester);
      expect(find.textContaining('Health den Tag'), findsNothing);
      expect(
        find.textContaining('Du kannst es direkt danach rückgängig machen.'),
        findsOneWidget,
      );
    });
  });

  group('the card on Home with Health (BS-97, frame 4123:316)', () {
    testWidgets('switch off: the card is the one of V1 and BS-108', (
      tester,
    ) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 7450);
      await _open(tester, env, '/');
      await _settle(tester);
      expect(find.text('Schritte aktualisieren'), findsOneWidget);
      expect(find.textContaining('Health'), findsNothing);
      expect(env.source.availabilityCalls, 0);
    });

    testWidgets('a value from Health: value, bar, the source with the time '
        'and the refresh button instead of the action', (tester) async {
      final env = await _env(tester);
      await _delivering(tester, env);
      await _open(tester, env, '/');
      await _settle(tester);

      expect(find.textContaining('7.450'), findsOneWidget);
      expect(find.text('75 % erreicht'), findsOneWidget);
      expect(find.text('Health · 10:00'), findsOneWidget);
      expect(find.text('Schritte aktualisieren'), findsNothing);
      expect(find.text('Schritte eintragen'), findsNothing);
      final refresh = _action('Schritte aus Health Connect aktualisieren');
      expect(refresh, findsOneWidget);
      expect(tester.getSize(refresh).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(refresh).height, greaterThanOrEqualTo(48));
    });

    testWidgets('the refresh button of the card compares now', (tester) async {
      final env = await _env(tester);
      await _delivering(tester, env, today: 3000);
      await _open(tester, env, '/');
      await _settle(tester);
      env.source
        ..clearSteps()
        ..clearCalls();
      _noon(env, _today, 3300);
      env.harness.clock.advance(const Duration(minutes: 10));
      await tester.tap(_action('Schritte aus Health Connect aktualisieren'));
      await _settle(tester);
      expect(env.source.totalCalls, hasLength(7));
      expect(find.textContaining('3.300'), findsOneWidget);
      expect(find.text('Health · 10:10'), findsOneWidget);
    });

    testWidgets('a tap on the card body still opens the overview', (
      tester,
    ) async {
      final env = await _env(tester);
      await _delivering(tester, env);
      await _open(tester, env, '/');
      await _settle(tester);
      await tester.tap(find.text('Schritte'));
      await _settle(tester);
      expect(find.text('Meine Schritte'), findsOneWidget);
    });

    testWidgets('no data yet today: "–" and the honest line, with the source '
        'row', (tester) async {
      final env = await _env(tester);
      await _delivering(tester, env, today: null);
      await _open(tester, env, '/');
      await _settle(tester);
      expect(find.text('–'), findsOneWidget);
      expect(
        find.text('Health meldet für heute noch keine Schritte'),
        findsOneWidget,
      );
      expect(find.text('Health · 10:00'), findsOneWidget);
    });

    testWidgets('a value typed in keeps the action of BS-108 and shows no '
        'Health row', (tester) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 5000);
      await _delivering(tester, env, today: 9000);
      await _open(tester, env, '/');
      await _settle(tester);
      expect(find.textContaining('5.000'), findsOneWidget);
      expect(find.text('Schritte aktualisieren'), findsOneWidget);
      expect(find.textContaining('Health ·'), findsNothing);
    });

    testWidgets('no access: the warning, the way out and the last value '
        '(frame 4123:472)', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await _env(tester);
      await _delivering(tester, env, today: 6100);
      env.source.accessValue = HealthAccess.denied;
      await _compare(tester, env);
      await _open(tester, env, '/');
      await _settle(tester);

      expect(find.textContaining('6.100'), findsOneWidget);
      expect(find.text('61 % erreicht'), findsOneWidget);
      expect(find.text('Health: kein Zugriff'), findsOneWidget);
      expect(find.text('Zugriff erlauben'), findsOneWidget);
      expect(find.text('Schritte aktualisieren'), findsNothing);
      expect(find.textContaining('Health ·'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Schritte, 6.100 / 10.000, 61 % erreicht, aus Health, '
          'Health: kein Zugriff',
        ),
        findsOneWidget,
        reason: 'the warning is part of the spoken name of the card',
      );

      env.source.accessAfterRequest = HealthAccess.granted;
      await tester.tap(find.text('Zugriff erlauben'));
      await _settle(tester);
      expect(env.source.requestAccessCalls, 1);
      expect(find.text('Health: kein Zugriff'), findsNothing);
      expect(find.textContaining('Health ·'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('no access and no value: "–", the warning and no manual '
        'pill', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await _env(tester);
      await _wish(tester, env);
      env.source.accessValue = HealthAccess.denied;
      await _compare(tester, env);
      await _open(tester, env, '/');
      await _settle(tester);
      expect(find.text('–'), findsOneWidget);
      expect(find.text('Heute noch nicht eingetragen'), findsOneWidget);
      expect(find.text('Health: kein Zugriff'), findsOneWidget);
      expect(find.text('Schritte eintragen'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Schritte, heute noch nicht eingetragen, Health: kein Zugriff',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the interface is missing or outdated: the chip and the way '
        'to install or update it', (tester) async {
      final env = await _env(tester);
      await _record(tester, env, _today, 7450);
      await _wish(tester, env);
      env.source.availabilityValue = HealthAvailability.missing;
      await _compare(tester, env);
      await _open(tester, env, '/');
      await _settle(tester);
      expect(find.text('Health Connect fehlt'), findsOneWidget);
      expect(find.text('Health Connect installieren'), findsOneWidget);
      await tester.tap(find.text('Health Connect installieren'));
      await _settle(tester);
      expect(env.source.installPageCalls, 1);

      env.source.availabilityValue = HealthAvailability.updateRequired;
      await _compare(tester, env);
      await _settle(tester);
      expect(find.text('Health Connect veraltet'), findsOneWidget);
      expect(find.text('Health Connect aktualisieren'), findsOneWidget);
    });

    testWidgets('while comparing and after a failure the line says so', (
      tester,
    ) async {
      final env = await _env(tester);
      await _delivering(tester, env);
      await _open(tester, env, '/');
      await _settle(tester);
      final gate = Completer<void>();
      env.source.totalGate = gate.future;
      await tester.tap(_action('Schritte aus Health Connect aktualisieren'));
      await _settle(tester);
      expect(find.text('Health · wird abgeglichen …'), findsOneWidget);
      final refresh = tester.widget<AppIconButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppIconButton &&
              widget.semanticLabel ==
                  'Schritte aus Health Connect aktualisieren',
        ),
      );
      expect(refresh.onPressed, isNull, reason: 'a second tap does nothing');
      gate.complete();
      await _settle(tester);

      env.source
        ..totalGate = null
        ..totalFailure = StateError('x');
      await tester.tap(_action('Schritte aus Health Connect aktualisieren'));
      await _settle(tester);
      expect(find.text('Health · Abgleich fehlgeschlagen'), findsOneWidget);
    });

    testWidgets('the card is named for a screen reader with its source '
        '(AT34)', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await _env(tester);
      await _delivering(tester, env);
      await _open(tester, env, '/');
      await _settle(tester);
      expect(
        find.bySemanticsLabel(
          'Schritte, 7.450 / 10.000, 75 % erreicht, aus Health',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Health · 10:00'), findsOneWidget);
      handle.dispose();
    });
  });

  group('layout and accessibility of every state (BS-97, AT33, AT34)', () {
    // The states: switch off is covered by the V1 tests; here the ones Health
    // adds. Each opens a screen and checks it at four widths and two scales.
    Future<void> prepare(WidgetTester tester, _Env env, String state) async {
      switch (state) {
        case 'delivering':
          await _delivering(tester, env);
        case 'no-data':
          await _delivering(tester, env, today: null);
        case 'no-access':
          await _delivering(tester, env, today: 6100);
          env.source.accessValue = HealthAccess.denied;
          await _compare(tester, env);
        case 'missing':
          await _record(tester, env, _today, 7450);
          await _wish(tester, env);
          env.source.availabilityValue = HealthAvailability.missing;
          await _compare(tester, env);
        case 'outdated':
          await _wish(tester, env);
          env.source.availabilityValue = HealthAvailability.updateRequired;
          await _compare(tester, env);
      }
    }

    const states = [
      'delivering',
      'no-data',
      'no-access',
      'missing',
      'outdated',
    ];
    for (final width in [320.0, 360.0, 393.0, 430.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final location in [StepsRoutes.overview, '/']) {
          testWidgets('$location with every Health state fits $width px at '
              '${(scale * 100).round()} % text without overflow and keeps '
              '48 x 48 actions (AT33, AT34)', (tester) async {
            for (final state in states) {
              final handle = tester.ensureSemantics();
              final env = await _env(tester);
              await prepare(tester, env, state);
              await _open(
                tester,
                env,
                location,
                size: Size(width, 800),
                textScale: scale,
              );
              await _settle(tester);
              expect(tester.takeException(), isNull, reason: state);
              final actions = <Finder>[
                find.byType(HealthTextAction),
                find.byType(AppIconButton),
              ];
              for (final finder in actions) {
                for (final element in finder.evaluate()) {
                  final size = tester.getSize(find.byWidget(element.widget));
                  expect(size.width, greaterThanOrEqualTo(48), reason: state);
                  expect(size.height, greaterThanOrEqualTo(48), reason: state);
                }
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
    }

    for (final theme in AppThemeVariant.values) {
      testWidgets('the Health states render in the ${theme.name} theme '
          '(AT35)', (tester) async {
        for (final state in states) {
          final env = await _env(tester);
          await prepare(tester, env, state);
          for (final location in [StepsRoutes.overview, '/']) {
            await _open(tester, env, location, theme: theme);
            await _settle(tester);
            expect(tester.takeException(), isNull, reason: '$state $location');
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }

    testWidgets('the notice is a live region with one readable label and '
        'separate buttons (AT34)', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await _env(tester);
      await _wish(tester, env);
      env.source.accessValue = HealthAccess.denied;
      await _compare(tester, env);
      await _open(tester, env, StepsRoutes.overview);
      await _settle(tester);
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
      final node = tester.getSemantics(
        find.bySemanticsLabel('Zugriff auf Schritte erlauben'),
      );
      expect(node.flagsCollection.isButton, isTrue);
      final notice = tester.getSemantics(find.byType(HealthNoticeCard));
      expect(
        notice.flagsCollection.isLiveRegion,
        isTrue,
        reason: 'the notice is announced when it appears',
      );
      handle.dispose();
    });
  });
}
