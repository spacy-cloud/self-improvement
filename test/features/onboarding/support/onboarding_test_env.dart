import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/data/reminder_preferences_repository.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/profile/profile_repository.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_navigation.dart';
import 'package:self_improvement/features/onboarding/presentation/onboarding_screen.dart';

import '../../../support/pump_app.dart';

/// A repository that fails the first [failures] completions with [error] (a
/// storage failure by default; nothing is written) and then delegates to the
/// real one. Records every command id and draft it receives.
class FlakyOnboardingRepository implements OnboardingRepository {
  FlakyOnboardingRepository(
    this._real, {
    this.failures = 0,
    this.error = const StorageFailure(causeType: 'TestFailure'),
  });

  final OnboardingRepository _real;

  /// Remaining attempts that throw.
  int failures;

  /// What the failing attempts throw.
  final AppFailure error;

  /// Command ids of all attempts, failed ones included.
  final List<String> commandIds = <String>[];

  /// Drafts of all attempts.
  final List<OnboardingDraft> drafts = <OnboardingDraft>[];

  @override
  Future<CommandOutcome> complete({
    required String commandId,
    required OnboardingDraft draft,
  }) async {
    commandIds.add(commandId);
    drafts.add(draft);
    if (failures > 0) {
      failures--;
      throw error;
    }
    return _real.complete(commandId: commandId, draft: draft);
  }
}

/// A pumped [OnboardingScreen] over an empty (not onboarded) in-memory
/// database, plus readers for what was persisted.
class OnboardingEnv {
  OnboardingEnv._(
    this.harness,
    this.container,
    this.repository,
    this.exits,
    this.router,
  );

  final DataHarness harness;
  final ProviderContainer container;
  final FlakyOnboardingRepository repository;

  /// One entry per time the flow left for the dashboard (not used with a
  /// router: there the router location shows it).
  final List<String> exits;

  /// The router of a [pumpOnboarding] call with `withRouter`.
  final GoRouter? router;

  /// Runs [action] (real database I/O) outside the fake clock of the test.
  Future<T> read<T>(WidgetTester tester, Future<T> Function() action) async =>
      (await tester.runAsync(action)) as T;

  /// Reads the profile row.
  Future<UserProfile> profile(WidgetTester tester) => read(
    tester,
    () async => (await ProfileRepository(harness.database).get())!,
  );

  /// Enabled flag per module as stored by the module history.
  Future<Map<ModuleId, bool>> modules(WidgetTester tester) =>
      read(tester, harness.moduleStatus.statuses);

  /// The goal version row of every stored goal type.
  Future<Map<String, GoalVersion>> goals(WidgetTester tester) => read(
    tester,
    () async {
      final all = await GoalVersionRepository(harness.database).all();
      return <String, GoalVersion>{for (final goal in all) goal.type.key: goal};
    },
  );

  /// Number of stored weight measurements (must stay 0 after onboarding).
  Future<int> weightEntryCount(WidgetTester tester) => read(
    tester,
    () async =>
        (await harness.database.select(harness.database.weightEntries).get())
            .length,
  );

  /// Whether reminders are wanted (the master switch) and which water slots
  /// are on. Both must stay off through the onboarding.
  Future<({bool wanted, Set<int> waterHours})> reminders(WidgetTester tester) =>
      read(tester, () async {
        final repository = ReminderPreferencesRepository(
          database: harness.database,
          runner: harness.runner,
        );
        return (
          wanted: await repository.notificationsWanted(),
          waterHours: await repository.enabledWaterHours(),
        );
      });
}

/// A harness whose projection step can be made to fail: the real command runner
/// then rolls the whole completion back (a genuine database failure).
Future<DataHarness> _createHarnessWithProjection(
  WidgetTester tester,
  RecordingProjectionSynchronizer projection,
) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final harness = (await tester.runAsync(
    () => DataHarness.create(projections: projection),
  ))!;
  addTearDown(() async {
    await tester.runAsync(harness.dispose);
  });
  return harness;
}

/// Pumps the onboarding screen. [failures] makes the first completions fail
/// with [error]. Without [withRouter] the exit callback records instead of
/// navigating; with it the real go_router exit runs against a dashboard
/// placeholder at `/`.
Future<OnboardingEnv> pumpOnboarding(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double textScale = 1.0,
  EdgeInsets viewInsets = EdgeInsets.zero,
  bool reducedMotion = false,
  AppThemeVariant theme = AppThemeVariant.light,
  int failures = 0,
  AppFailure error = const StorageFailure(causeType: 'TestFailure'),
  bool withRouter = false,
  RecordingProjectionSynchronizer? projection,
}) async {
  final harness = projection == null
      ? await createTestHarness(tester, onboarded: false)
      : await _createHarnessWithProjection(tester, projection);
  final real = harness.createContainer().read(onboardingRepositoryProvider);
  final repository = FlakyOnboardingRepository(
    real,
    failures: failures,
    error: error,
  );
  final exits = <String>[];
  final container = harness.createContainer(
    overrides: [
      onboardingRepositoryProvider.overrideWithValue(repository),
      if (!withRouter)
        onboardingExitProvider.overrideWithValue((context) => exits.add('/')),
    ],
  );
  GoRouter? router;
  if (withRouter) {
    router = await pumpRouterApp(
      tester,
      routes: <RouteBase>[
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Text('Dashboard-Platzhalter')),
        ),
      ],
      initialLocation: '/onboarding',
      container: container,
      size: size,
      textScale: textScale,
      viewInsets: viewInsets,
      reducedMotion: reducedMotion,
      theme: theme,
    );
  } else {
    await pumpApp(
      tester,
      const OnboardingScreen(),
      container: container,
      size: size,
      textScale: textScale,
      viewInsets: viewInsets,
      reducedMotion: reducedMotion,
      theme: theme,
    );
  }
  return OnboardingEnv._(harness, container, repository, exits, router);
}
