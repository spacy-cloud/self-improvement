import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/dashboard/domain/first_entry_action.dart';

import '../support/dashboard_test_kit.dart';

QuickAction _action(String id, int order, [String? route]) => QuickAction(
  id: id,
  label: id,
  icon: Icons.add,
  route: route ?? '/$id',
  plusOrder: order,
);

void main() {
  final modules = testModules(TapLog());
  Map<ModuleId, bool> on({Set<ModuleId> off = const <ModuleId>{}}) => {
    for (final module in ModuleId.values) module: !off.contains(module),
  };

  group('availableQuickActions', () {
    test('lists the entries of active modules in the plus menu order', () {
      final actions = availableQuickActions(
        modules: modules,
        moduleStatuses: on(),
      );
      expect(
        [for (final action in actions) action.id],
        [
          'weight',
          'workout',
          'water',
          'steps',
          'focus',
          'task',
          'habit',
          'meal',
        ],
      );
    });

    test('drops the entries of a switched-off module (C03)', () {
      final actions = availableQuickActions(
        modules: modules,
        moduleStatuses: on(off: {ModuleId.body, ModuleId.tasks}),
      );
      expect(
        [for (final action in actions) action.id],
        ['workout', 'water', 'focus', 'meal'],
      );
    });

    test('is empty when every module is off', () {
      expect(
        availableQuickActions(
          modules: modules,
          moduleStatuses: {for (final module in ModuleId.values) module: false},
        ),
        isEmpty,
      );
    });
  });

  group('firstEntryAction', () {
    test('prefers weight, then water, then habit', () {
      expect(
        firstEntryAction([
          _action('water', 2),
          _action('habit', 6),
          _action('weight', 0),
        ])?.id,
        'weight',
      );
      expect(
        firstEntryAction([_action('habit', 6), _action('water', 2)])?.id,
        'water',
      );
      expect(
        firstEntryAction([_action('meal', 7), _action('habit', 6)])?.id,
        'habit',
      );
    });

    test('falls back to the first entry of the menu, null without any', () {
      expect(
        firstEntryAction([_action('meal', 7), _action('focus', 4)])?.id,
        'meal',
      );
      expect(firstEntryAction(const []), isNull);
    });
  });

  group('quickStartEntries', () {
    test('offers weight, water and habit with the routes of the entries', () {
      final starts = quickStartEntries(
        availableQuickActions(modules: modules, moduleStatuses: on()),
      );
      expect(
        [for (final start in starts) start.id],
        ['weight', 'water', 'habit'],
      );
      expect(
        [for (final start in starts) start.route],
        ['/weight/new', '/water', '/habits/new'],
      );
      expect(starts.first.title, 'Gewicht eintragen');
    });

    test('never offers something whose module is off', () {
      final starts = quickStartEntries(
        availableQuickActions(
          modules: modules,
          moduleStatuses: on(off: {ModuleId.body, ModuleId.nutrition}),
        ),
      );
      expect([for (final start in starts) start.id], ['habit']);
    });

    test('is empty without any of the three entries', () {
      expect(quickStartEntries([_action('focus', 4)]), isEmpty);
    });
  });
}
