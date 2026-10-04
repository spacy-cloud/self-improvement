import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// German titles of the dashboard cards for cards whose module has not
/// registered a descriptor (yet). A registered descriptor always wins.
const Map<String, String> fallbackCardTitles = <String, String>{
  'steps': 'Schritte',
  'water': 'Wasser',
  'weight': 'Gewicht',
  'workout': 'Workout',
  'focus': 'Fokus',
  'tasks': 'Aufgaben',
  'nutrition': 'Ernährung',
  'xp': 'XP und Level',
};

/// The title of dashboard card [cardId]: the registered descriptor first, then
/// the fallback table, finally the id itself (never empty).
String cardTitle(String cardId, Iterable<SelfImprovementModule> modules) {
  for (final module in modules) {
    for (final card in module.dashboardCards) {
      if (card.cardId == cardId) {
        return card.title;
      }
    }
  }
  return fallbackCardTitles[cardId] ?? cardId;
}

/// Accent of a module in the module manager (Figma: nutrition shows the water
/// blue, because the module covers water and meals).
AppAccent managerAccentFor(ModuleId module) {
  return switch (module) {
    ModuleId.body => AppAccent.weight,
    ModuleId.nutrition => AppAccent.water,
    ModuleId.focus => AppAccent.focus,
    ModuleId.tasks => AppAccent.habits,
    ModuleId.gamification => AppAccent.gamification,
  };
}

/// True when every module is switched off.
bool allModulesOff(Map<ModuleId, bool> statuses) =>
    ModuleId.values.every((module) => !(statuses[module] ?? true));

/// Moves [from] to [to] and clamps; used to decide which move buttons are
/// available (the first card cannot move up, the last cannot move down).
bool canMove({required int index, required int count, required int delta}) {
  final target = index + delta;
  return target >= 0 && target < count;
}
