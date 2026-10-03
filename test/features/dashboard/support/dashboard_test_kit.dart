import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/body/presentation/weight_dashboard_card.dart';
import 'package:self_improvement/features/dashboard/application/dashboard_providers.dart';
import 'package:self_improvement/features/dashboard/presentation/home_screen.dart';
import 'package:self_improvement/features/gamification/gamification_module.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';

/// Records which card areas were tapped (`open:water`, `quick:water`).
final class TapLog {
  final List<String> entries = <String>[];

  void add(String entry) => entries.add(entry);
}

/// A bundled-module stand-in with simple cards (the real modules of the other
/// work packages are not part of this branch).
final class FakeModule extends SelfImprovementModule {
  const FakeModule({
    required this.id,
    required this.title,
    this.cards = const <DashboardCardDescriptor>[],
    this.actions = const <QuickAction>[],
  });

  @override
  final ModuleId id;

  @override
  final String title;

  final List<DashboardCardDescriptor> cards;
  final List<QuickAction> actions;

  @override
  String get description => 'Testmodul';

  @override
  IconData get icon => Icons.circle_outlined;

  @override
  List<RouteBase> get routes => const <RouteBase>[];

  @override
  List<DashboardCardDescriptor> get dashboardCards => cards;

  @override
  List<QuickAction> get quickActions => actions;
}

/// A card that shows no data yet, taps are written to [log]. With
/// [quickActionLabel] it has a quick action below the body.
DashboardCardDescriptor fakeCard(
  String id,
  String title,
  int rank,
  TapLog log, {
  bool fullWidth = false,
  String? quickActionLabel,
  Future<void> Function(WidgetRef ref)? onQuickAction,
}) {
  return DashboardCardDescriptor(
    cardId: id,
    title: title,
    defaultRank: rank,
    fullWidth: fullWidth,
    builder: (context, ref) => MetricCard(
      title: title,
      value: '–',
      subtitle: 'Noch keine Daten',
      icon: Icons.circle_outlined,
      onTap: () => log.add('open:$id'),
      quickAction: quickActionLabel == null
          ? null
          : MetricCardAction(
              label: quickActionLabel,
              onPressed: () {
                log.add('quick:$id');
                if (onQuickAction != null) {
                  onQuickAction(ref);
                }
              },
            ),
    ),
  );
}

QuickAction _action(String id, String label, String route, int order) =>
    QuickAction(
      id: id,
      label: label,
      icon: Icons.add,
      route: route,
      plusOrder: order,
    );

/// The five bundled modules with the cards and plus menu entries of the real
/// ownership (steps/weight: body, water/meals: nutrition, workout/focus: focus,
/// tasks: tasks, XP: the real gamification module).
List<SelfImprovementModule> testModules(
  TapLog log, {
  bool realWeightCard = false,
  Future<void> Function(WidgetRef ref)? onWaterQuickAdd,
}) {
  return <SelfImprovementModule>[
    FakeModule(
      id: ModuleId.body,
      title: 'Körper',
      cards: <DashboardCardDescriptor>[
        fakeCard('steps', 'Schritte', 0, log),
        if (realWeightCard)
          DashboardCardDescriptor(
            cardId: 'weight',
            title: 'Gewicht',
            defaultRank: 2,
            builder: (context, ref) => const WeightDashboardCard(),
          )
        else
          fakeCard('weight', 'Gewicht', 2, log),
      ],
      actions: <QuickAction>[
        _action('weight', 'Gewicht', '/weight/new', 0),
        _action('steps', 'Schritte', '/steps/new', 3),
      ],
    ),
    FakeModule(
      id: ModuleId.nutrition,
      title: 'Ernährung',
      cards: <DashboardCardDescriptor>[
        fakeCard(
          'water',
          'Wasser',
          1,
          log,
          quickActionLabel: '+250 ml',
          onQuickAction: onWaterQuickAdd,
        ),
        fakeCard('nutrition', 'Ernährung', 6, log),
      ],
      actions: <QuickAction>[
        _action('water', 'Wasser', '/water', 2),
        _action('meal', 'Mahlzeit', '/nutrition/new', 7),
      ],
    ),
    FakeModule(
      id: ModuleId.focus,
      title: 'Fokus',
      cards: <DashboardCardDescriptor>[
        fakeCard('workout', 'Workout', 3, log),
        fakeCard('focus', 'Fokus', 4, log),
      ],
      actions: <QuickAction>[
        _action('workout', 'Workout', '/workouts/new', 1),
        _action('focus', 'Fokus', '/focus', 4),
      ],
    ),
    FakeModule(
      id: ModuleId.tasks,
      title: 'Aufgaben',
      cards: <DashboardCardDescriptor>[
        fakeCard('tasks', 'Aufgaben', 5, log, fullWidth: true),
      ],
      actions: <QuickAction>[
        _action('task', 'Aufgabe', '/tasks/new', 5),
        _action('habit', 'Gewohnheit', '/habits/new', 6),
      ],
    ),
    const GamificationModule(),
  ];
}

/// Pages the dashboard can open, shown as a plain text so a test can see where
/// a tap led.
const List<String> probePaths = <String>[
  '/goals',
  '/settings/modules',
  '/weight',
  '/weight/new',
  '/steps/new',
  '/water',
  '/workouts/new',
  '/focus',
  '/tasks/new',
  '/habits/new',
  '/nutrition/new',
];

/// Creates an onboarded in-memory harness (profile started on [startedOn],
/// default today) and disposes it with the test.
Future<DataHarness> createHarness(
  WidgetTester tester, {
  Set<String>? enabledModules,
  LocalDate? startedOn,
  String nowIso = '2026-10-03T08:00:00Z',
  bool realProjection = true,
  String? displayName,
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final harness = (await tester.runAsync(
    () => DataHarness.create(nowIso: nowIso, realProjection: realProjection),
  ))!;
  addTearDown(() async {
    await tester.runAsync(harness.dispose);
  });
  await tester.runAsync(() async {
    await harness.seedOnboarded(
      enabledModules: enabledModules,
      startedOn: startedOn,
    );
    if (displayName != null) {
      await harness.database
          .update(harness.database.profile)
          .write(ProfileCompanion(displayName: Value<String?>(displayName)));
    }
  });
  return harness;
}

/// What a Home test works with.
final class HomeFixture {
  const HomeFixture({
    required this.harness,
    required this.container,
    required this.feedback,
    required this.router,
    required this.log,
  });

  final DataHarness harness;
  final ProviderContainer container;
  final RecordingFeedbackService feedback;
  final GoRouter router;
  final TapLog log;
}

/// Pumps the dashboard at `/` in a router app with the module routes of the
/// gamification module and a text page for every other destination.
Future<HomeFixture> pumpHome(
  WidgetTester tester,
  DataHarness harness, {
  Size size = const Size(393, 852),
  double textScale = 1.0,
  bool realWeightCard = false,
  Future<void> Function(WidgetRef ref)? onWaterQuickAdd,
  List<Override> overrides = const <Override>[],
  TapLog? log,
  String initialLocation = '/',
  AppThemeVariant theme = AppThemeVariant.light,
}) async {
  final tapLog = log ?? TapLog();
  final feedback = RecordingFeedbackService();
  final modules = testModules(
    tapLog,
    realWeightCard: realWeightCard,
    onWaterQuickAdd: onWaterQuickAdd,
  );
  final container = harness.createContainer(
    overrides: <Override>[
      feedbackServiceProvider.overrideWithValue(feedback),
      dashboardModulesProvider.overrideWithValue(modules),
      ...overrides,
    ],
  );
  final router = await pumpRouterApp(
    tester,
    container: container,
    size: size,
    textScale: textScale,
    theme: theme,
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      ...const GamificationModule().routes,
      for (final path in probePaths)
        GoRoute(
          path: path,
          builder: (context, state) =>
              Scaffold(body: Center(child: Text('Seite $path'))),
        ),
    ],
  );
  await settle(tester);
  return HomeFixture(
    harness: harness,
    container: container,
    feedback: feedback,
    router: router,
    log: tapLog,
  );
}

/// Lets the first database reads of all providers arrive (several streams
/// answer one after the other) and rebuilds the tree.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
