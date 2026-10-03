import 'package:flutter/widgets.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// The fixed plus menu: exactly these eight entries exist, in this order
/// (Figma `2037:18`). A module contributes the ones it owns through its
/// `quickActions`; ids outside this list are ignored, so no module can grow the
/// menu.
const List<String> plusEntryIds = <String>[
  'weight',
  'workout',
  'water',
  'steps',
  'focus',
  'task',
  'habit',
  'meal',
];

/// One resolved entry of the plus menu.
@immutable
final class PlusEntry {
  const PlusEntry({
    required this.id,
    required this.label,
    required this.icon,
    required this.route,
    required this.accent,
    required this.module,
  });

  final String id;
  final String label;
  final IconData icon;

  /// Where the entry leads (pushed on top of the current tab).
  final String route;
  final AppAccent accent;
  final ModuleId module;
}

/// Icon tile accent per entry (Figma: weight and task use the brand tint).
AppAccent plusAccentFor(String id) => switch (id) {
  'weight' => AppAccent.weight,
  'workout' => AppAccent.workout,
  'water' => AppAccent.water,
  'steps' => AppAccent.steps,
  'focus' => AppAccent.focus,
  'habit' => AppAccent.habits,
  'meal' => AppAccent.nutrition,
  _ => AppAccent.primary,
};

/// The plus menu for the current state:
///
/// - only quick actions of ACTIVE modules (a module without status row counts
///   as active),
/// - only the eight known entry ids, each at most once,
/// - ordered by the actions' `plusOrder` (ties keep the fixed menu order),
/// - with an open focus session "Fokus" becomes "Fokus fortsetzen" and leads
///   to the running session instead of starting a second one.
List<PlusEntry> resolvePlusEntries({
  required Iterable<SelfImprovementModule> modules,
  required Map<ModuleId, bool> statuses,
  required bool focusSessionOpen,
  required String Function(QuickAction action) labelOf,
}) {
  final byId = <String, ({QuickAction action, ModuleId module})>{};
  for (final module in modules) {
    if (!(statuses[module.id] ?? true)) {
      continue;
    }
    for (final action in module.quickActions) {
      if (plusEntryIds.contains(action.id)) {
        byId.putIfAbsent(action.id, () => (action: action, module: module.id));
      }
    }
  }
  final entries = <PlusEntry>[
    for (final id in plusEntryIds)
      if (byId[id] case (:final action, :final module))
        if (id == 'focus' && focusSessionOpen)
          PlusEntry(
            id: id,
            label: 'Fokus fortsetzen',
            icon: action.icon,
            route: AppRoutes.focusSession,
            accent: plusAccentFor(id),
            module: module,
          )
        else
          PlusEntry(
            id: id,
            label: labelOf(action),
            icon: action.icon,
            route: action.route,
            accent: plusAccentFor(id),
            module: module,
          ),
  ];
  final order = <String, int>{
    for (final entry in byId.entries) entry.key: entry.value.action.plusOrder,
  };
  final fixedIndex = <String, int>{
    for (var i = 0; i < plusEntryIds.length; i++) plusEntryIds[i]: i,
  };
  entries.sort((a, b) {
    final byOrder = order[a.id]!.compareTo(order[b.id]!);
    return byOrder != 0
        ? byOrder
        : fixedIndex[a.id]!.compareTo(fixedIndex[b.id]!);
  });
  return entries;
}
