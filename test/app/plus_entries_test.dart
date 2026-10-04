import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/app/shell/plus_entries.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';

import 'support/fake_modules.dart';

Map<ModuleId, bool> _all({Set<ModuleId> off = const <ModuleId>{}}) => {
  for (final module in ModuleId.values) module: !off.contains(module),
};

List<String> _ids(List<PlusEntry> entries) => [
  for (final entry in entries) entry.id,
];

List<PlusEntry> _resolve({
  List<SelfImprovementModule>? modules,
  Map<ModuleId, bool>? statuses,
  bool focusOpen = false,
}) => resolvePlusEntries(
  modules: modules ?? fullFakeModules(),
  statuses: statuses ?? _all(),
  focusSessionOpen: focusOpen,
  labelOf: (action) => action.label,
);

void main() {
  test('the menu has exactly the eight entries in the fixed order (C02)', () {
    final entries = _resolve();
    expect(_ids(entries), <String>[
      'weight',
      'workout',
      'water',
      'steps',
      'focus',
      'task',
      'habit',
      'meal',
    ]);
    expect(entries.map((e) => e.label), <String>[
      'Gewicht',
      'Workout',
      'Wasser',
      'Schritte',
      'Fokus',
      'Aufgabe',
      'Gewohnheit',
      'Mahlzeit',
    ]);
  });

  test('only actions of active modules are offered (C02)', () {
    final entries = _resolve(statuses: _all(off: {ModuleId.nutrition}));
    expect(_ids(entries), isNot(contains('water')));
    expect(_ids(entries), isNot(contains('meal')));
    expect(entries, hasLength(6));
    final bodyOff = _resolve(statuses: _all(off: {ModuleId.body}));
    expect(_ids(bodyOff), isNot(contains('weight')));
    expect(_ids(bodyOff), isNot(contains('steps')));
  });

  test('a module without a status row counts as active', () {
    final entries = _resolve(statuses: const <ModuleId, bool>{});
    expect(entries, hasLength(8));
  });

  test('with every module off no entry is offered (AT04)', () {
    final everything = _all(off: ModuleId.values.toSet());
    expect(_resolve(statuses: everything), isEmpty);
  });

  test('the order follows the plusOrder of the actions', () {
    final modules = <SelfImprovementModule>[
      FakeModule(
        ModuleId.body,
        actions: <QuickAction>[
          action('weight', 'Gewicht', '/weight/new', 9),
          action('steps', 'Schritte', '/steps/new', 1),
        ],
      ),
      FakeModule(
        ModuleId.nutrition,
        actions: <QuickAction>[action('water', 'Wasser', '/water', 5)],
      ),
    ];
    expect(_ids(_resolve(modules: modules)), <String>[
      'steps',
      'water',
      'weight',
    ]);
  });

  test('actions outside the fixed eight are ignored, duplicates once', () {
    final modules = <SelfImprovementModule>[
      FakeModule(
        ModuleId.body,
        actions: <QuickAction>[
          action('weight', 'Gewicht', '/weight/new', 0),
          action('sleep', 'Schlaf', '/sleep/new', 1),
        ],
      ),
      FakeModule(
        ModuleId.nutrition,
        actions: <QuickAction>[action('weight', 'Gewicht 2', '/other', 0)],
      ),
    ];
    final entries = _resolve(modules: modules);
    expect(_ids(entries), <String>['weight']);
    expect(entries.single.route, '/weight/new');
  });

  test('a running focus session turns Fokus into Fokus fortsetzen', () {
    final entries = _resolve(focusOpen: true);
    final focus = entries.singleWhere((entry) => entry.id == 'focus');
    expect(focus.label, 'Fokus fortsetzen');
    expect(focus.route, AppRoutes.focusSession);
    expect(entries, hasLength(8));
    final idle = _resolve().singleWhere((entry) => entry.id == 'focus');
    expect(idle.label, 'Fokus');
    expect(idle.route, '/focus');
  });

  test('the dynamic label of a quick action is used when present', () {
    final modules = <SelfImprovementModule>[
      FakeModule(
        ModuleId.body,
        actions: <QuickAction>[
          QuickAction(
            id: 'weight',
            label: 'Gewicht',
            icon: Icons.add,
            route: '/weight/new',
            plusOrder: 0,
            dynamicLabel: (ref) => 'Gewicht heute',
          ),
        ],
      ),
    ];
    final entries = resolvePlusEntries(
      modules: modules,
      statuses: _all(),
      focusSessionOpen: false,
      labelOf: (action) => 'Gewicht heute',
    );
    expect(entries.single.label, 'Gewicht heute');
  });
}
