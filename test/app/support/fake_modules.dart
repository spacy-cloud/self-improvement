import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// A screen that only names itself (and its path parameters), standing in for
/// the real screens of the modules in shell tests.
class ProbeScreen extends StatelessWidget {
  const ProbeScreen(
    this.name, {
    this.params = const <String, String>{},
    super.key,
  });

  final String name;
  final Map<String, String> params;

  @override
  Widget build(BuildContext context) {
    return AppScaffold.subpage(
      title: name,
      body: Text('probe:$name${params.isEmpty ? '' : ' $params'}'),
    );
  }
}

GoRoute probeRoute(String path, String name) => GoRoute(
  path: path,
  builder: (context, state) => ProbeScreen(name, params: state.pathParameters),
);

/// A module with fixed registrations for shell tests.
final class FakeModule extends SelfImprovementModule {
  const FakeModule(
    this.id, {
    this.title = 'Modul',
    this.paths = const <String, String>{},
    this.actions = const <QuickAction>[],
    this.check = const CanDeactivate(),
  });

  @override
  final ModuleId id;
  @override
  final String title;
  final Map<String, String> paths;
  final List<QuickAction> actions;
  final DeactivationCheck check;

  @override
  String get description => 'Beschreibung $title';

  @override
  IconData get icon => Icons.circle_outlined;

  @override
  List<RouteBase> get routes => <RouteBase>[
    for (final entry in paths.entries) probeRoute(entry.key, entry.value),
  ];

  @override
  List<DashboardCardDescriptor> get dashboardCards => const [];

  @override
  List<QuickAction> get quickActions => actions;

  @override
  Future<DeactivationCheck> canDeactivate(Ref ref) async => check;
}

QuickAction action(String id, String label, String route, int order) =>
    QuickAction(
      id: id,
      label: label,
      icon: Icons.add,
      route: route,
      plusOrder: order,
    );

/// All five modules with all eight quick actions (what the integrated app
/// offers), each pointing at a probe route.
List<SelfImprovementModule> fullFakeModules() => <SelfImprovementModule>[
  FakeModule(
    ModuleId.body,
    title: 'Gewicht & Körper',
    paths: const <String, String>{
      '/weight': 'weight',
      '/weight/new': 'weight-new',
      '/weight/all': 'weight-all',
      '/weight/:id': 'weight-edit',
      '/steps/new': 'steps-new',
    },
    actions: <QuickAction>[
      action('steps', 'Schritte', '/steps/new', 3),
      action('weight', 'Gewicht', '/weight/new', 0),
    ],
  ),
  FakeModule(
    ModuleId.nutrition,
    title: 'Wasser & Ernährung',
    paths: const <String, String>{
      '/water': 'water',
      '/nutrition/new': 'meal-new',
    },
    actions: <QuickAction>[
      action('meal', 'Mahlzeit', '/nutrition/new', 7),
      action('water', 'Wasser', '/water', 2),
    ],
  ),
  FakeModule(
    ModuleId.focus,
    title: 'Fokus & Workouts',
    paths: const <String, String>{
      '/focus': 'focus-start',
      '/focus/session': 'focus-session',
      '/workouts/new': 'workout-new',
    },
    actions: <QuickAction>[
      action('focus', 'Fokus', '/focus', 4),
      action('workout', 'Workout', '/workouts/new', 1),
    ],
  ),
  FakeModule(
    ModuleId.tasks,
    title: 'Aufgaben & Gewohnheiten',
    paths: const <String, String>{
      '/tasks/new': 'task-new',
      '/habits/new': 'habit-new',
      '/habits/:id': 'habit-detail',
    },
    actions: <QuickAction>[
      action('habit', 'Gewohnheit', '/habits/new', 6),
      action('task', 'Aufgabe', '/tasks/new', 5),
    ],
  ),
  const FakeModule(ModuleId.gamification, title: 'Gamification'),
];

/// Tab probes that keep a counter in their own state, to prove that a tab
/// keeps its state while another tab is shown.
class CounterTab extends StatefulWidget {
  const CounterTab(this.name, {super.key});

  final String name;

  @override
  State<CounterTab> createState() => _CounterTabState();
}

class _CounterTabState extends State<CounterTab> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.name,
      body: Column(
        children: <Widget>[
          Text('${widget.name}:$_count'),
          TextButton(
            onPressed: () => setState(() => _count++),
            child: Text('plus-${widget.name}'),
          ),
        ],
      ),
    );
  }
}
