import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/data/focus_repository.dart';
import 'package:self_improvement/features/focus/data/workout_day_mark_repository.dart';
import 'package:self_improvement/features/focus/data/workout_repository.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_day_mark.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_intensity.dart';
import 'package:self_improvement/features/focus/focus_module.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import 'manual_tick_source.dart';
import 'recording_ids.dart';

/// Everything a focus or workout UI test needs: the in-memory database with a
/// fake clock (2026-10-03 10:00 in Berlin unless told otherwise), a manual
/// tick source for the countdown, a feedback recorder and a recording id
/// generator.
final class FocusUi {
  FocusUi({
    required this.harness,
    required this.container,
    required this.ticker,
    required this.feedback,
    required this.ids,
    this.extraOverrides = const [],
  });

  final DataHarness harness;
  final ProviderContainer container;
  final ManualTickSource ticker;
  final RecordingFeedbackService feedback;
  final RecordingIdGenerator ids;
  final List<Override> extraOverrides;

  var _phase = 0;
  var _monotonicSeconds = 0;

  FocusRepository get focusRepository =>
      container.read(focusRepositoryProvider);

  WorkoutRepository get workoutRepository =>
      container.read(workoutRepositoryProvider);

  WorkoutDayMarkRepository get workoutDayMarkRepository =>
      container.read(workoutDayMarkRepositoryProvider);

  AppDatabase get database => harness.database;

  /// Moves the fake clock forward (the app is closed or the screen is idle:
  /// no foreground ticks).
  void advance(int seconds) =>
      harness.clock.advance(Duration(seconds: seconds));

  /// Foreground time passes: the wall clock and the monotonic tick source both
  /// move by [seconds]. A new foreground phase restarts the monotonic reading.
  void tickBy(int seconds) {
    if (ticker.phasesStarted != _phase) {
      _phase = ticker.phasesStarted;
      _monotonicSeconds = 0;
    }
    _monotonicSeconds += seconds;
    harness.clock.advance(Duration(seconds: seconds));
    ticker.emitSeconds(_monotonicSeconds);
  }

  /// A new process on the same database: a fresh container with its own tick
  /// source and feedback recorder. The old container is disposed.
  FocusUi restarted() {
    container.dispose();
    return _build(harness, extraOverrides: extraOverrides, ids: ids);
  }

  /// The router of a test: a stub home with the module routes behind it.
  List<RouteBase> get routes => [
    GoRoute(
      path: '/',
      builder: (context, state) => const Scaffold(body: Text('HOME-STUB')),
    ),
    GoRoute(
      path: '/goals',
      builder: (context, state) => const Scaffold(body: Text('GOALS-STUB')),
    ),
    ...const FocusModule().routes,
  ];
}

FocusUi _build(
  DataHarness harness, {
  required List<Override> extraOverrides,
  required RecordingIdGenerator ids,
}) {
  final ticker = ManualTickSource();
  final feedback = RecordingFeedbackService();
  final container = ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: [
      appDatabaseProvider.overrideWithValue(harness.database),
      clockProvider.overrideWithValue(harness.clock),
      idGeneratorProvider.overrideWithValue(ids),
      commandEventsProvider.overrideWithValue(harness.events),
      projectionSynchronizerProvider.overrideWithValue(harness.projections),
      focusTickSourceProvider.overrideWithValue(ticker),
      feedbackServiceProvider.overrideWithValue(feedback),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);
  return FocusUi(
    harness: harness,
    container: container,
    ticker: ticker,
    feedback: feedback,
    ids: ids,
    extraOverrides: extraOverrides,
  );
}

/// Creates the harness (seeded as onboarded) and the container.
Future<FocusUi> createFocusUi(
  WidgetTester tester, {
  String nowIso = '2026-10-03T08:00:00Z',
  bool realProjection = false,
  ProjectionSynchronizer? projection,
  Set<String>? enabledModules,
  List<Override> overrides = const [],

  /// Switches the optional daily goal "Workout heute" on from the profile
  /// start (BS-99); off by default, like in the app.
  bool workoutDailyGoal = false,
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final harness = (await tester.runAsync(
    () => DataHarness.create(
      nowIso: nowIso,
      realProjection: realProjection,
      projections: projection,
    ),
  ))!;
  addTearDown(() async {
    await tester.runAsync(harness.dispose);
  });
  await tester.runAsync(
    () => harness.seedOnboarded(
      enabledModules: enabledModules,
      startedOn: LocalDate(2026, 9, 1),
      workoutDailyGoal: workoutDailyGoal,
    ),
  );
  return _build(
    harness,
    extraOverrides: overrides,
    ids: RecordingIdGenerator(harness.ids),
  );
}

extension FocusUiTester on WidgetTester {
  /// Lets pending database work finish (real time) and rebuilds the tree.
  Future<void> settleDb() async {
    await runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await pump(const Duration(milliseconds: 50));
    await runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await pump(const Duration(milliseconds: 300));
  }

  /// Taps [finder] and waits for the database work the tap started.
  Future<void> tapAndSettleDb(Finder finder) async {
    await ensureVisible(finder);
    await tap(finder);
    await settleDb();
  }

  /// Foreground time passes by [seconds] (see [FocusUi.tickBy]) and the screen
  /// shows the new value.
  Future<void> tick(FocusUi ui, int seconds) async {
    ui.tickBy(seconds);
    // The countdown stream delivers its value in a microtask: flush it, then
    // build the frame that shows it.
    await pump(Duration.zero);
    await pump(Duration.zero);
  }

  /// Starts a focus session through the repository.
  Future<String> startFocus(
    FocusUi ui, {
    int plannedSeconds = 1500,
    FocusCategory category = FocusCategory.learning,
  }) async {
    final outcome = await runCommand(
      () => ui.focusRepository.start(
        commandId: ui.ids.newId(),
        category: category,
        plannedSeconds: plannedSeconds,
      ),
    );
    return outcome.entityId!;
  }

  /// Starts a session, lets [seconds] pass on the fake clock and saves it.
  Future<String> completeFocus(
    FocusUi ui, {
    required int seconds,
    int plannedSeconds = 1500,
    FocusCategory category = FocusCategory.learning,
  }) async {
    final id = await startFocus(
      ui,
      plannedSeconds: plannedSeconds,
      category: category,
    );
    ui.advance(seconds);
    await runCommand(
      () => ui.focusRepository.save(commandId: ui.ids.newId(), id: id),
    );
    return id;
  }

  /// Creates a workout through the repository.
  Future<WorkoutEntry> addWorkout(
    FocusUi ui, {
    TrainingCategory category = TrainingCategory.strength,
    int minutes = 45,
    String? title,
    List<MuscleGroup> groups = const [],
    WorkoutIntensity? intensity,
    String? note,
    DateTime? at,
  }) async {
    final outcome = await runCommand(
      () => ui.workoutRepository.create(
        commandId: ui.ids.newId(),
        draft: WorkoutDraft(
          category: category,
          durationMinutes: minutes,
          occurredAtUtc: at ?? ui.harness.clock.nowUtc(),
          title: title,
          muscleGroups: groups,
          intensity: intensity,
          note: note,
        ),
      ),
    );
    return (await runAsync(
      () => ui.workoutRepository.findById(outcome.entityId!),
    ))!;
  }

  /// Marks today (or [date]) as a rest day or a skipped day through the
  /// repository (BS-99).
  Future<WorkoutDayMark> markWorkoutDay(
    FocusUi ui,
    WorkoutDayMarkKind kind, {
    LocalDate? date,
  }) async {
    await runCommand(
      () => ui.workoutDayMarkRepository.mark(
        commandId: ui.ids.newId(),
        kind: kind,
        date: date,
      ),
    );
    return (await runAsync(
      () =>
          ui.workoutDayMarkRepository.findDay(date ?? ui.harness.clock.today()),
    ))!;
  }

  /// Inserts [count] completed sessions directly (fast), one per hour going
  /// back from [newestEnd]; the newest has the id `bulk-0`. For list tests.
  Future<void> insertCompletedSessions(
    FocusUi ui,
    int count, {
    required DateTime newestEnd,
  }) async {
    await runAsync(() async {
      for (var i = 0; i < count; i++) {
        final end = newestEnd.subtract(Duration(hours: i));
        await ui.database
            .into(ui.database.focusSessions)
            .insert(
              FocusSessionsCompanion.insert(
                id: 'bulk-$i',
                category: 'learning',
                plannedSeconds: 1500,
                accumulatedSeconds: const Value(1500),
                startedAtUtc: end.subtract(const Duration(minutes: 25)),
                endedAtUtc: Value(end),
                completedLocalDate: Value(ui.harness.clock.localDateOf(end)),
                timezoneId: 'Europe/Berlin',
                status: 'completed',
                createdAtUtc: end,
                updatedAtUtc: end,
              ),
            );
      }
    });
    await settleDb();
  }

  /// Inserts [count] workouts directly (fast), one per day going back from
  /// [newest]; the newest has the id `bulk-0`. For list tests.
  Future<void> insertWorkouts(
    FocusUi ui,
    int count, {
    required DateTime newest,
  }) async {
    await runAsync(() async {
      for (var i = 0; i < count; i++) {
        final at = newest.subtract(Duration(days: i));
        await ui.database
            .into(ui.database.workoutEntries)
            .insert(
              WorkoutEntriesCompanion.insert(
                id: 'bulk-$i',
                trainingCategory: 'cardio',
                durationMinutes: 30,
                occurredAtUtc: at,
                localDate: ui.harness.clock.localDateOf(at),
                timezoneId: 'Europe/Berlin',
                gamificationEligible: false,
                createdAtUtc: at,
                updatedAtUtc: at,
              ),
            );
      }
    });
    await settleDb();
  }

  /// Rows of the focus sessions table (also discarded and deleted ones).
  Future<List<FocusSessionRow>> focusRows(FocusUi ui) async => (await runAsync(
    () => ui.database.select(ui.database.focusSessions).get(),
  ))!;

  /// Rows of the workout table.
  Future<List<WorkoutEntryRow>> workoutRows(FocusUi ui) async =>
      (await runAsync(
        () => ui.database.select(ui.database.workoutEntries).get(),
      ))!;

  /// Committed command receipts of [commandType].
  Future<List<CommandReceiptRow>> receipts(
    FocusUi ui,
    String commandType,
  ) async => (await runAsync(
    () => (ui.database.select(
      ui.database.commandReceipts,
    )..where((r) => r.commandType.equals(commandType))).get(),
  ))!;

  /// Awarded XP rows.
  Future<List<XpAwardRow>> xpAwards(FocusUi ui) async =>
      (await runAsync(() => ui.database.select(ui.database.xpAwards).get()))!;
}

/// Runs the restoration the app shell runs on bootstrap and on every resume,
/// in the test zone (like a lifecycle callback), and waits for it.
Future<void> restoreFocus(WidgetTester tester, FocusUi ui) async {
  var finished = false;
  unawaited(
    ui.container
        .read(focusRestorerProvider)
        .restore()
        .whenComplete(() => finished = true),
  );
  await tester.pumpUntil(() => finished, reason: 'restore did not finish');
  await tester.settleDb();
}

/// Sends the app to the background and back (a resumed lifecycle event).
Future<void> resumeApp(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.settleDb();
}

/// Pumps the module routes at [initialLocation] and waits until the first
/// database reads have been delivered.
Future<GoRouter> pumpFocusApp(
  WidgetTester tester,
  FocusUi ui, {
  String initialLocation = '/focus',
  Size size = const Size(393, 852),
  double textScale = 1.0,
  EdgeInsets viewInsets = EdgeInsets.zero,
  bool reducedMotion = false,
  AppThemeVariant theme = AppThemeVariant.light,
}) async {
  final router = await pumpRouterApp(
    tester,
    routes: ui.routes,
    initialLocation: initialLocation,
    container: ui.container,
    size: size,
    textScale: textScale,
    viewInsets: viewInsets,
    reducedMotion: reducedMotion,
    theme: theme,
  );
  await tester.settleDb();
  return router;
}

/// Runs [body] with the semantics tree enabled (what a screen reader sees).
/// The handle is released before the test ends. Written as a helper so tests
/// stay literal `testWidgets` calls that `tool/at_coverage.dart` can index.
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

/// Removes the app from the screen (the process ends).
Future<void> closeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
