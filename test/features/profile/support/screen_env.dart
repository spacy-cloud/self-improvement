import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/profile/presentation/goals_screen.dart';
import 'package:self_improvement/features/profile/presentation/profile_edit_screen.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/features/profile/presentation/profile_screen.dart';
import 'package:self_improvement/features/settings/presentation/licenses_screen.dart';
import 'package:self_improvement/features/settings/presentation/settings_screen.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import 'flaky_projection.dart';
import 'recording_commands.dart';

export 'flaky_projection.dart';

/// Database, fake clock, recording feedback and a provider container for the
/// screen tests of the profile and settings features.
class ScreenEnv {
  ScreenEnv._(this.harness, this.feedback, this.projection, this._overrides)
    : profileCommands = RecordingProfileCommands(
        database: harness.database,
        runner: harness.runner,
      ),
      goalsCommands = RecordingGoalsCommands(
        runner: harness.runner,
        versions: GoalVersionRepository(harness.database),
      ),
      settingsCommands = RecordingSettingsCommands(
        database: harness.database,
        runner: harness.runner,
      ) {
    container = newContainer();
  }

  final DataHarness harness;
  final RecordingFeedbackService feedback;
  final FlakyProjection projection;
  final List<Override> _overrides;

  /// The command layers the screens use; they record every command id.
  final RecordingProfileCommands profileCommands;
  final RecordingGoalsCommands goalsCommands;
  final RecordingSettingsCommands settingsCommands;
  late ProviderContainer container;

  /// A fresh container over the SAME database: the app process was killed and
  /// started again.
  ProviderContainer newContainer() => container = harness.createContainer(
    overrides: [
      feedbackServiceProvider.overrideWithValue(feedback),
      profileCommandsProvider.overrideWithValue(profileCommands),
      goalsCommandsProvider.overrideWithValue(goalsCommands),
      settingsCommandsProvider.overrideWithValue(settingsCommands),
      ..._overrides,
    ],
  );
}

/// Creates the environment. Modules default to all on.
Future<ScreenEnv> createScreenEnv(
  WidgetTester tester, {
  bool onboarded = true,
  Set<String>? enabledModules,
  String nowIso = '2026-10-03T08:00:00Z',
  LocalDate? startedOn,
  bool realProjection = false,
  List<Override> overrides = const [],

  /// Switches the optional daily goal "Workout heute" on from the profile
  /// start (BS-99); off by default, like in the app.
  bool workoutDailyGoal = false,
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final projection = FlakyProjection();
  final harness = (await tester.runAsync(
    () => realProjection
        ? DataHarness.create(nowIso: nowIso, realProjection: true)
        : DataHarness.create(nowIso: nowIso, projections: projection),
  ))!;
  addTearDown(() async {
    await tester.runAsync(harness.dispose);
  });
  if (onboarded) {
    await tester.runAsync(
      () => harness.seedOnboarded(
        enabledModules: enabledModules,
        startedOn: startedOn,
        workoutDailyGoal: workoutDailyGoal,
      ),
    );
  }
  return ScreenEnv._(
    harness,
    RecordingFeedbackService(ids: harness.ids),
    projection,
    overrides,
  );
}

class _Stub extends StatelessWidget {
  const _Stub(this.name);

  final String name;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('Seite $name')));
}

/// The routes of the screens under test; every other target of a link is a
/// stub that shows `Seite <route>`.
List<RouteBase> screenRoutes() => [
  GoRoute(path: '/', builder: (context, state) => const _Stub('/')),
  GoRoute(
    path: ProfileRoutes.profile,
    builder: (context, state) => const ProfileScreen(),
  ),
  GoRoute(
    path: ProfileRoutes.edit,
    builder: (context, state) => const ProfileEditScreen(),
  ),
  GoRoute(
    path: ProfileRoutes.goals,
    builder: (context, state) => const GoalsScreen(),
  ),
  GoRoute(
    path: SettingsRoutes.settings,
    builder: (context, state) => const SettingsScreen(),
  ),
  GoRoute(
    path: SettingsRoutes.licenses,
    builder: (context, state) => const LicensesScreen(),
  ),
  for (final path in [
    SettingsRoutes.data,
    SettingsRoutes.modules,
    ProfileRoutes.streak,
    ProfileRoutes.progress,
  ])
    GoRoute(path: path, builder: (context, state) => _Stub(path)),
];

/// Lets drift deliver stream data and runs pending frames (a plain `pump` is
/// not enough for database streams).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.pumpAndSettle();
}

/// Starts the app on a stub page and opens [location] on top of it, so the
/// back button and "closing after saving" have somewhere to go.
Future<GoRouter> openScreen(
  WidgetTester tester,
  ScreenEnv env,
  String location, {
  Size size = const Size(393, 852),
  double textScale = 1.0,
  AppThemeVariant theme = AppThemeVariant.light,
  EdgeInsets viewInsets = EdgeInsets.zero,
  bool reducedMotion = false,
}) async {
  final router = await pumpRouterApp(
    tester,
    routes: screenRoutes(),
    initialLocation: '/',
    container: env.container,
    size: size,
    textScale: textScale,
    theme: theme,
    viewInsets: viewInsets,
    reducedMotion: reducedMotion,
  );
  unawaited(router.push<Object?>(location));
  await settle(tester);
  return router;
}

/// Saves profile values through the real command (like the editor does).
Future<void> saveProfile(
  WidgetTester tester,
  ScreenEnv env, {
  String? name,
  int? heightCm,
  int? ageYears,
  int? startWeightGrams,
  int? targetWeightGrams,
}) {
  return tester.runCommand(
    () => env.container
        .read(profileCommandsProvider)
        .update(
          commandId: env.harness.ids.newId(),
          displayName: name,
          heightCm: heightCm,
          ageYears: ageYears,
          startWeightGrams: startWeightGrams,
          targetWeightGrams: targetWeightGrams,
        ),
  );
}

/// Records a weight measurement of [grams] at [at] (default: now).
Future<void> addWeight(
  WidgetTester tester,
  ScreenEnv env,
  int grams, {
  DateTime? at,
}) {
  return tester.runCommand(
    () => env.container
        .read(weightRepositoryProvider)
        .create(
          commandId: env.harness.ids.newId(),
          draft: WeightDraft(
            weightGrams: grams,
            occurredAtUtc: at ?? env.harness.clock.nowUtc(),
          ),
        ),
  );
}
