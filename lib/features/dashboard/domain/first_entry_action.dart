import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// The plus menu entries of all ENABLED modules in the fixed plus menu order
/// (`QuickAction.plusOrder`).
List<QuickAction> availableQuickActions({
  required Iterable<SelfImprovementModule> modules,
  required Map<ModuleId, bool> moduleStatuses,
}) {
  final actions = <QuickAction>[
    for (final module in modules)
      if (moduleStatuses[module.id] ?? true) ...module.quickActions,
  ]..sort((a, b) => a.plusOrder.compareTo(b.plusOrder));
  return List.unmodifiable(actions);
}

/// Ids of the entries the welcome hint prefers, in this order: weight, water,
/// habit (the three starting points of the design).
const List<String> _preferredFirstEntries = <String>[
  'weight',
  'water',
  'habit',
];

/// The entry the welcome hint opens ("Ersten Eintrag hinzufügen"), or `null`
/// when no enabled module offers a quick action.
///
/// It prefers the starting points of the design (weight, water, habit) and
/// falls back to the first entry of the plus menu.
QuickAction? firstEntryAction(List<QuickAction> actions) {
  for (final id in _preferredFirstEntries) {
    for (final action in actions) {
      if (action.id == id) {
        return action;
      }
    }
  }
  return actions.isEmpty ? null : actions.first;
}

/// A starting point of the first day: where a new user can begin.
@immutable
final class QuickStart {
  const QuickStart({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  /// The id of the plus menu entry (`weight`, `water`, `habit`).
  final String id;

  /// German title of the row.
  final String title;

  /// German second line.
  final String subtitle;

  /// The route the row opens (the route of the plus menu entry).
  final String route;
}

/// The starting points of the first day ("Schnell starten"): weight, water
/// and the first habit, in this order. An entry appears only when its module is
/// on, so the list never offers something that leads nowhere. Every row only
/// opens the entry screen; nothing is saved without the user's confirmation.
List<QuickStart> quickStartEntries(List<QuickAction> actions) {
  QuickAction? find(String id) {
    for (final action in actions) {
      if (action.id == id) {
        return action;
      }
    }
    return null;
  }

  final weight = find('weight');
  final water = find('water');
  final habit = find('habit');
  return List.unmodifiable(<QuickStart>[
    if (weight != null)
      QuickStart(
        id: weight.id,
        title: 'Gewicht eintragen',
        subtitle: 'Dein Startpunkt für den Verlauf',
        route: weight.route,
      ),
    if (water != null)
      QuickStart(
        id: water.id,
        title: 'Wasser eintragen',
        subtitle: 'Ein Tippen auf die Menge genügt',
        route: water.route,
      ),
    if (habit != null)
      QuickStart(
        id: habit.id,
        title: 'Erstes Habit anlegen',
        subtitle: 'z. B. 10 Min. lesen',
        route: habit.route,
      ),
  ]);
}
