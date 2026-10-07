import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/app/shell/plus_entries.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/shared/local_date.dart';

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

/// All goal types that are on by default (the planning default, BS-99 added the
/// optional daily workout goal, which is off until it is switched on) except
/// [off].
Set<GoalType> _goals({Set<GoalType> off = const <GoalType>{}}) => {
  for (final type in GoalType.values)
    if (type.defaultEnabled && !off.contains(type)) type,
};

/// The entries of the active modules, filtered by the goals that are on.
List<PlusEntry> _menu({
  Map<ModuleId, bool>? statuses,
  Set<GoalType>? goals,
  List<SelfImprovementModule>? modules,
}) => filterPlusEntriesByGoals(
  _resolve(modules: modules, statuses: statuses),
  goals ?? _goals(),
);

final LocalDate _today = LocalDate(2026, 10, 3);
final LocalDate _tomorrow = LocalDate(2026, 10, 4);

GoalVersion _version(
  GoalType type, {
  required bool enabled,
  required LocalDate from,
  int? target,
}) => GoalVersion(
  type: type,
  target: target ?? type.defaultTarget,
  enabled: enabled,
  effectiveFrom: from,
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

  group('goals of Meine Ziele filter the entries (BS-117)', () {
    test(
      '(BS-117, C02) six entries belong to a goal, habit and meal to none',
      () {
        expect(
          {for (final id in plusEntryIds) id: plusGoalFor(id)},
          <String, GoalType?>{
            'weight': GoalType.weightEntry,
            'workout': GoalType.workoutWeekly,
            'water': GoalType.water,
            'steps': GoalType.steps,
            'focus': GoalType.focusMinutes,
            'task': GoalType.taskCompletion,
            'habit': null,
            'meal': null,
          },
        );
        expect(plusGoalFor('sleep'), isNull);
        for (final entry in _resolve()) {
          expect(entry.goal, plusGoalFor(entry.id), reason: entry.id);
        }
      },
    );

    test('(BS-117, C02) the goal of an entry belongs to the module that offers '
        'it', () {
      var withGoal = 0;
      for (final module in bundledModules) {
        for (final action in module.quickActions) {
          final goal = plusGoalFor(action.id);
          if (goal == null) {
            continue;
          }
          withGoal++;
          expect(goal.module, module.id, reason: action.id);
        }
      }
      expect(withGoal, 6);
    });

    test('(BS-117, C02) with every goal on all eight entries stay in the fixed '
        'order', () {
      expect(_ids(_menu()), plusEntryIds);
    });

    for (final id in plusEntryIds.where((id) => plusGoalFor(id) != null)) {
      final goal = plusGoalFor(id)!;
      test('(BS-117, C02) $id is offered only with its module on AND its goal '
          'on', () {
        for (final moduleOn in <bool>[true, false]) {
          for (final goalOn in <bool>[true, false]) {
            final entries = _menu(
              statuses: _all(off: moduleOn ? <ModuleId>{} : {goal.module}),
              goals: _goals(off: goalOn ? <GoalType>{} : {goal}),
            );
            expect(
              _ids(entries).contains(id),
              moduleOn && goalOn,
              reason:
                  'module ${moduleOn ? 'on' : 'off'}, goal '
                  '${goalOn ? 'on' : 'off'}',
            );
          }
        }
      });
    }

    test('(BS-117, C02) a goal off hides only its own entry, the order of the '
        'rest stays', () {
      final entries = _menu(
        goals: _goals(
          off: {GoalType.weightEntry, GoalType.steps, GoalType.taskCompletion},
        ),
      );
      expect(_ids(entries), <String>[
        'workout',
        'water',
        'focus',
        'habit',
        'meal',
      ]);
    });

    test('(BS-117, C02) habit and meal have no goal: with every goal off only '
        'their module hides them', () {
      final everyGoalOff = _goals(off: GoalType.values.toSet());
      expect(_ids(_menu(goals: everyGoalOff)), <String>['habit', 'meal']);
      expect(
        _ids(
          _menu(
            goals: everyGoalOff,
            statuses: _all(off: {ModuleId.tasks}),
          ),
        ),
        <String>['meal'],
      );
      expect(
        _ids(
          _menu(
            goals: everyGoalOff,
            statuses: _all(off: {ModuleId.nutrition}),
          ),
        ),
        <String>['habit'],
      );
      expect(
        _menu(
          goals: everyGoalOff,
          statuses: _all(off: {ModuleId.tasks, ModuleId.nutrition}),
        ),
        isEmpty,
      );
    });

    test('(BS-117, C02) the filter keeps the plusOrder of the actions', () {
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
          actions: <QuickAction>[
            action('water', 'Wasser', '/water', 5),
            action('meal', 'Mahlzeit', '/nutrition/new', 0),
          ],
        ),
      ];
      expect(_ids(_menu(modules: modules)), <String>[
        'meal',
        'steps',
        'water',
        'weight',
      ]);
      expect(
        _ids(
          _menu(
            modules: modules,
            goals: _goals(off: {GoalType.water}),
          ),
        ),
        <String>['meal', 'steps', 'weight'],
      );
    });

    test('(BS-117, C02) a running focus session follows the goal of Fokus, '
        'like Fokus itself', () {
      final session = filterPlusEntriesByGoals(
        _resolve(focusOpen: true),
        _goals(off: {GoalType.focusMinutes}),
      );
      expect(_ids(session), isNot(contains('focus')));
      expect(_ids(session), hasLength(7));
      final open = filterPlusEntriesByGoals(
        _resolve(focusOpen: true),
        _goals(),
      );
      expect(
        open.singleWhere((e) => e.id == 'focus').label,
        'Fokus fortsetzen',
      );
    });

    group('activeGoalTypes', () {
      test('(BS-117, C07) without stored versions every goal counts as on '
          '(the planning default)', () {
        expect(activeGoalTypes(const <GoalVersion>[], _today), _goals());
      });

      test('(BS-117, C07) a goal is on when its switch is on, whatever its '
          'value', () {
        final versions = <GoalVersion>[
          for (final type in GoalType.values)
            _version(type, enabled: true, from: _today, target: type.minTarget),
        ];
        expect(activeGoalTypes(versions, _today), GoalType.values.toSet());
      });

      test('(BS-117, AT24) the menu follows the state saved for tomorrow at '
          'once, today\'s ring keeps the old one', () {
        final versions = <GoalVersion>[
          _version(GoalType.weightEntry, enabled: true, from: _today),
          // What "Meine Ziele" saves: a version that applies from tomorrow.
          _version(GoalType.weightEntry, enabled: false, from: _tomorrow),
        ];
        expect(
          resolveGoalVersion(versions, GoalType.weightEntry, _today)!.enabled,
          isTrue,
          reason: 'today still counts the goal',
        );
        expect(
          activeGoalTypes(versions, _today),
          _goals(off: {GoalType.weightEntry}),
        );
      });

      test('(BS-117, C07) a goal switched on again for tomorrow is on again, '
          'although it was off today', () {
        final versions = <GoalVersion>[
          _version(GoalType.steps, enabled: false, from: _today),
          _version(GoalType.steps, enabled: true, from: _tomorrow),
        ];
        expect(activeGoalTypes(versions, _today), _goals());
      });

      test('(BS-117, C07) a version of a later day is not looked at yet', () {
        final versions = <GoalVersion>[
          _version(
            GoalType.water,
            enabled: false,
            from: LocalDate(2026, 10, 5),
          ),
        ];
        expect(activeGoalTypes(versions, _today), _goals());
        expect(
          activeGoalTypes(versions, _tomorrow),
          _goals(off: {GoalType.water}),
        );
      });

      test('(BS-117, C07) goals are independent of each other', () {
        final versions = <GoalVersion>[
          _version(GoalType.focusMinutes, enabled: false, from: _today),
          _version(GoalType.workoutWeekly, enabled: false, from: _today),
        ];
        expect(
          activeGoalTypes(versions, _today),
          _goals(off: {GoalType.focusMinutes, GoalType.workoutWeekly}),
        );
      });
    });
  });
}
