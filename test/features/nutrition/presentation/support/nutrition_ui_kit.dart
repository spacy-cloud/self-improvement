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
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/data/meal_repository.dart';
import 'package:self_improvement/features/nutrition/data/water_repository.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/meal_input.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/nutrition_module.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../../support/pump_app.dart';
import '../../support/nutrition_test_kit.dart';

export '../../../../support/pump_app.dart';
export '../../support/nutrition_test_kit.dart'
    show FlakyProjection, RecordingIdGenerator;

/// "Today" of the harness clock: 2026-10-03, 10:00 in Berlin.
final LocalDate uiToday = LocalDate(2026, 10, 3);

/// The profile start of the seeded state (goals exist from this day on).
final LocalDate uiStart = LocalDate(2026, 9, 1);

/// A UTC instant [ago] before the harness clock's "now" (2026-10-03T08:00Z).
DateTime instantAgo(NutritionUi ui, Duration ago) =>
    ui.harness.clock.nowUtc().subtract(ago);

/// A stub of the dashboard: the real cards of the module in the real grid.
class _HomeStub extends StatelessWidget {
  const _HomeStub();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Home-Stub',
      body: Consumer(
        builder: (context, ref, _) => AdaptiveGrid(
          children: [
            for (final card in const NutritionModule().dashboardCards)
              card.builder(context, ref),
          ],
        ),
      ),
    );
  }
}

/// A fully wired nutrition UI test: in-memory database with the onboarded
/// state, the fixed clock, the real command runner and a recording feedback
/// service.
class NutritionUi {
  NutritionUi._(this.tester, this.harness, this.container, this.feedback);

  final WidgetTester tester;
  final DataHarness harness;
  final ProviderContainer container;
  final RecordingFeedbackService feedback;

  /// Creates the harness. [projection] injects failures, [ids] records command
  /// ids, [realProjection] runs snapshots and XP like the app.
  static Future<NutritionUi> create(
    WidgetTester tester, {
    bool realProjection = false,
    FlakyProjection Function(DataHarness harness)? projection,
    RecordingIdGenerator Function(DataHarness harness)? ids,
    List<Override> overrides = const <Override>[],
  }) async {
    final harness = await createTestHarness(
      tester,
      onboarded: false,
      realProjection: realProjection,
    );
    await tester.runAsync(() => harness.seedOnboarded(startedOn: uiStart));
    final feedback = RecordingFeedbackService(ids: harness.ids);
    final flaky = projection?.call(harness);
    final recorder = ids?.call(harness);
    // Like the app: one container over the harness database, clock and
    // events. A projection or id source can be swapped to inject failures.
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        appDatabaseProvider.overrideWithValue(harness.database),
        clockProvider.overrideWithValue(harness.clock),
        idGeneratorProvider.overrideWithValue(recorder ?? harness.ids),
        commandEventsProvider.overrideWithValue(harness.events),
        projectionSynchronizerProvider.overrideWithValue(
          flaky ?? harness.projections,
        ),
        feedbackServiceProvider.overrideWithValue(feedback),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    return NutritionUi._(tester, harness, container, feedback);
  }

  WaterRepository get water => container.read(waterRepositoryProvider);
  MealRepository get meals => container.read(mealRepositoryProvider);
  AppDatabase get database => harness.database;

  /// Pumps the module routes plus a dashboard stub at `/`.
  Future<GoRouter> pumpRoute(
    String location, {
    Size size = const Size(393, 852),
    double textScale = 1.0,
    EdgeInsets viewInsets = EdgeInsets.zero,
    AppThemeVariant theme = AppThemeVariant.light,
  }) async {
    final router = await pumpRouterApp(
      tester,
      routes: [
        GoRoute(path: '/', builder: (context, state) => const _HomeStub()),
        ...const NutritionModule().routes,
      ],
      initialLocation: location,
      container: container,
      size: size,
      textScale: textScale,
      viewInsets: viewInsets,
      theme: theme,
    );
    await settle();
    return router;
  }

  /// Scrolls the lazy list until [finder] is built and fully on screen.
  Future<void> reveal(Finder finder) async {
    await tester.scrollUntilVisible(finder, 300);
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  /// Lets the database streams deliver (real time) and rebuilds the tree.
  Future<void> settle() async {
    for (var round = 0; round < 3; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Stores a water entry [ago] before now (default: 30 minutes) and returns
  /// it. The command runs outside the fake clock.
  Future<WaterEntry> addWater(
    int amountMl, {
    Duration ago = const Duration(minutes: 30),
    String? note,
  }) async {
    final outcome = await tester.runCommand(
      () => water.create(
        commandId: harness.ids.newId(),
        draft: WaterDraft(
          amountMl: amountMl,
          occurredAtUtc: instantAgo(this, ago),
          note: note,
        ),
      ),
    );
    return (await tester.runAsync(() => water.findById(outcome.entityId!)))!;
  }

  /// Stores a meal [ago] before now (default: 30 minutes) and returns it.
  Future<MealEntry> addMeal(
    String name, {
    int? kcal,
    Duration ago = const Duration(minutes: 30),
    String? note,
  }) async {
    final outcome = await tester.runCommand(
      () => meals.create(
        commandId: harness.ids.newId(),
        draft: MealDraft(
          name: name,
          kcal: kcal,
          occurredAtUtc: instantAgo(this, ago),
          note: note,
        ),
      ),
    );
    return (await tester.runAsync(() => meals.findById(outcome.entityId!)))!;
  }

  /// Total of today's active water entries in ml, read from the database.
  Future<int> waterTotalMl() async =>
      (await tester.runAsync(() => water.loadToday(uiToday)))!.totalMl;

  /// Number of today's active water entries.
  Future<int> waterCount() async =>
      (await tester.runAsync(() => water.loadToday(uiToday)))!.entryCount;

  /// All command receipts (one per committed command id).
  Future<List<CommandReceiptRow>> receipts() async => (await tester.runAsync(
    () => database.select(database.commandReceipts).get(),
  ))!;

  /// All XP award rows.
  Future<int> totalXp() async => (await tester.runAsync(harness.totalXp))!;

  /// Presses "Rückgängig" of the latest recorded snack bar and waits for the
  /// result.
  Future<UndoResult> pressUndo() async {
    final undo = feedback.last!.undo!;
    return tester.runCommand(undo.perform);
  }

  /// Waits until [done] holds (real time for the database, pumping between).
  Future<void> until(bool Function() done, {String reason = 'condition'}) =>
      tester.pumpUntil(done, reason: reason);
}

/// A finder for a [RichText] whose plain text equals [text] (a `Text.rich`).
Finder richText(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText() == text,
  description: 'RichText "$text"',
);

/// A finder for the icon button whose spoken label contains [part].
Finder iconButtonLabelled(String part) => find.byWidgetPredicate(
  (widget) => widget is AppIconButton && widget.semanticLabel.contains(part),
  description: 'AppIconButton labelled "$part"',
);
