import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/dashboard/domain/dashboard_layout.dart';
import 'package:self_improvement/core/modules/dashboard_card_repository.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';

final class _TestModule extends SelfImprovementModule {
  const _TestModule(this.id, this._cards);

  @override
  final ModuleId id;
  final List<String> _cards;

  @override
  String get title => id.key;

  @override
  String get description => id.key;

  @override
  IconData get icon => Icons.circle;

  @override
  List<RouteBase> get routes => const [];

  @override
  List<QuickAction> get quickActions => const [];

  @override
  List<DashboardCardDescriptor> get dashboardCards => [
    for (var i = 0; i < _cards.length; i++)
      DashboardCardDescriptor(
        cardId: _cards[i],
        title: _cards[i],
        defaultRank: i,
        builder: (context, ref) => const SizedBox.shrink(),
      ),
  ];
}

void main() {
  const modules = [
    _TestModule(ModuleId.body, ['steps', 'weight']),
    _TestModule(ModuleId.nutrition, ['water', 'nutrition']),
    _TestModule(ModuleId.focus, ['workout', 'focus']),
    _TestModule(ModuleId.tasks, ['tasks']),
    _TestModule(ModuleId.gamification, ['xp']),
  ];

  List<DashboardCardConfig> configs({Set<String> hidden = const {}}) {
    const order = [
      'steps',
      'water',
      'weight',
      'workout',
      'focus',
      'tasks',
      'nutrition',
      'xp',
    ];
    const owner = {
      'steps': ModuleId.body,
      'weight': ModuleId.body,
      'water': ModuleId.nutrition,
      'nutrition': ModuleId.nutrition,
      'workout': ModuleId.focus,
      'focus': ModuleId.focus,
      'tasks': ModuleId.tasks,
      'xp': ModuleId.gamification,
    };
    return [
      for (var i = 0; i < order.length; i++)
        DashboardCardConfig(
          cardId: order[i],
          module: owner[order[i]]!,
          visible: !hidden.contains(order[i]),
          sortIndex: i,
        ),
    ];
  }

  Map<ModuleId, bool> allOn() => {for (final m in ModuleId.values) m: true};

  List<String> ids(List<DashboardEntry> entries) => [
    for (final e in entries) e.config.cardId,
  ];

  test('default: all eight cards in the configured order', () {
    final shown = visibleDashboardEntries(
      configs: configs(),
      moduleStatuses: allOn(),
      modules: modules,
    );
    expect(ids(shown), [
      'steps',
      'water',
      'weight',
      'workout',
      'focus',
      'tasks',
      'nutrition',
      'xp',
    ]);
    expect(
      dashboardEmptyReason(shown: shown, moduleStatuses: allOn()),
      DashboardEmptyReason.none,
    );
  });

  test('hidden cards are skipped but a custom order is respected', () {
    final custom = [
      for (final c in configs(hidden: {'water'}))
        DashboardCardConfig(
          cardId: c.cardId,
          module: c.module,
          visible: c.visible,
          sortIndex: c.cardId == 'xp' ? -1 : c.sortIndex,
        ),
    ];
    final shown = visibleDashboardEntries(
      configs: custom,
      moduleStatuses: allOn(),
      modules: modules,
    );
    expect(ids(shown).first, 'xp');
    expect(ids(shown), isNot(contains('water')));
  });

  test(
    'a deactivated module hides all its cards but keeps nothing else out',
    () {
      final statuses = allOn()..[ModuleId.body] = false;
      final shown = visibleDashboardEntries(
        configs: configs(),
        moduleStatuses: statuses,
        modules: modules,
      );
      expect(ids(shown), [
        'water',
        'workout',
        'focus',
        'tasks',
        'nutrition',
        'xp',
      ]);
    },
  );

  test('all modules off: empty with the module hint', () {
    final off = {for (final m in ModuleId.values) m: false};
    final shown = visibleDashboardEntries(
      configs: configs(),
      moduleStatuses: off,
      modules: modules,
    );
    expect(shown, isEmpty);
    expect(
      dashboardEmptyReason(shown: shown, moduleStatuses: off),
      DashboardEmptyReason.allModulesOff,
    );
  });

  test('modules on but every card hidden: empty with the configure hint', () {
    final shown = visibleDashboardEntries(
      configs: configs(
        hidden: {
          'steps',
          'water',
          'weight',
          'workout',
          'focus',
          'tasks',
          'nutrition',
          'xp',
        },
      ),
      moduleStatuses: allOn(),
      modules: modules,
    );
    expect(shown, isEmpty);
    expect(
      dashboardEmptyReason(shown: shown, moduleStatuses: allOn()),
      DashboardEmptyReason.allCardsHidden,
    );
  });

  test('a card without a stored row is appended in default rank order', () {
    final partial = configs().where((c) => c.cardId != 'xp').toList();
    final shown = visibleDashboardEntries(
      configs: partial,
      moduleStatuses: allOn(),
      modules: modules,
    );
    expect(ids(shown).last, 'xp');
    expect(shown.last.config.visible, isTrue);
  });

  test('stored cards without a descriptor are ignored', () {
    final extra = [
      ...configs(),
      const DashboardCardConfig(
        cardId: 'sleep',
        module: ModuleId.body,
        visible: true,
        sortIndex: 99,
      ),
    ];
    final shown = visibleDashboardEntries(
      configs: extra,
      moduleStatuses: allOn(),
      modules: modules,
    );
    expect(ids(shown), isNot(contains('sleep')));
  });
}
