import 'package:flutter/widgets.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';

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

  /// The goals of "Meine Ziele" this entry belongs to, empty for an entry
  /// without one ([plusGoalsFor]).
  Set<GoalType> get goals => plusGoalsFor(id);
}

/// The goals of "Meine Ziele" an entry belongs to, empty when it has none. An
/// entry with several goals is offered while at least one of them is on
/// ([filterPlusEntriesByGoals]).
///
/// Weight ("Gewicht erfassen"), water, steps, focus and task ("Aufgabe
/// erledigen") each have one goal there. Workout has two: the weekly goal
/// "Workouts" and the optional daily goal "Workout heute" (BS-99). Both ask for
/// workouts to be recorded, so the entry stays while either one is on; with the
/// daily goal on and the weekly one off the menu still leads to the workout
/// form. A habit carries its own daily goal inside the habit and a meal has no
/// goal at all, so those two stay in the menu whenever their module is on
/// (BS-117).
Set<GoalType> plusGoalsFor(String id) => switch (id) {
  'weight' => const <GoalType>{GoalType.weightEntry},
  'workout' => const <GoalType>{GoalType.workoutWeekly, GoalType.workoutDaily},
  'water' => const <GoalType>{GoalType.water},
  'steps' => const <GoalType>{GoalType.steps},
  'focus' => const <GoalType>{GoalType.focusMinutes},
  'task' => const <GoalType>{GoalType.taskCompletion},
  _ => const <GoalType>{},
};

/// The goals the user has switched on, in the state the user saved last.
///
/// A goal counts as set when its switch is on, whatever its value ("Täglich",
/// "1× pro Woche", 10.000 steps); "Aus" means it is not set. A goal without a
/// stored version counts as on (its planning default), exactly as in the goal
/// editor. The target weight of the profile is no goal here: "Gewicht
/// erfassen" decides about the weight entry.
///
/// Goal edits are saved for TOMORROW (the day ring and the streak keep today's
/// goals), and the editor starts from that state. The menu follows the saved
/// state at once: a goal switched off a moment ago is gone the next time the
/// menu is looked at, and a goal switched on shows its entry again, although
/// today's ring still counts the old state.
Set<GoalType> activeGoalTypes(Iterable<GoalVersion> versions, LocalDate today) {
  final from = nextEffectiveDate(today);
  return <GoalType>{
    for (final type in GoalType.values)
      if (effectiveGoalOrDefault(versions, type, from).enabled) type,
  };
}

/// The entries of [entries] with at least one goal in [activeGoals], plus the
/// entries without a goal (habit, meal). The order stays as it is.
List<PlusEntry> filterPlusEntriesByGoals(
  Iterable<PlusEntry> entries,
  Set<GoalType> activeGoals,
) => <PlusEntry>[
  for (final entry in entries)
    if (entry.goals.isEmpty || entry.goals.any(activeGoals.contains)) entry,
];

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
///
/// The goals of the user are a second filter that comes afterwards
/// ([filterPlusEntriesByGoals]): this function knows modules only.
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
