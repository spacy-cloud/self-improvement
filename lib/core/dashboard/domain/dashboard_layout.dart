import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/modules/dashboard_card_repository.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// A card the dashboard shows, with its descriptor and stored configuration.
@immutable
final class DashboardEntry {
  const DashboardEntry({required this.descriptor, required this.config});

  final DashboardCardDescriptor descriptor;
  final DashboardCardConfig config;
}

/// Why the dashboard has no cards to show.
enum DashboardEmptyReason {
  /// There are cards to show.
  none,

  /// Every module is switched off: offer "Module auswählen".
  allModulesOff,

  /// Modules are on but the user hid all their cards: offer to configure.
  allCardsHidden,
}

/// The cards to show, in display order.
///
/// A card is shown when its stored configuration is visible, its module is
/// enabled and the module actually provides a descriptor for the card id.
/// Cards without a stored row (not expected after onboarding) are appended in
/// their default rank. Cards of a switched-off module keep their configuration
/// but are not shown.
List<DashboardEntry> visibleDashboardEntries({
  required Iterable<DashboardCardConfig> configs,
  required Map<ModuleId, bool> moduleStatuses,
  required Iterable<SelfImprovementModule> modules,
}) {
  final descriptors = {
    for (final module in modules)
      for (final card in module.dashboardCards) card.cardId: card,
  };
  final byId = {for (final config in configs) config.cardId: config};

  final entries = <DashboardEntry>[];
  for (final config in byId.values) {
    final descriptor = descriptors[config.cardId];
    if (descriptor == null ||
        !config.visible ||
        !(moduleStatuses[config.module] ?? true)) {
      continue;
    }
    entries.add(DashboardEntry(descriptor: descriptor, config: config));
  }
  entries.sort((a, b) {
    final byIndex = a.config.sortIndex.compareTo(b.config.sortIndex);
    return byIndex != 0 ? byIndex : a.config.cardId.compareTo(b.config.cardId);
  });

  // Descriptors without a stored configuration follow in default rank order.
  final missing = [
    for (final module in modules)
      if (moduleStatuses[module.id] ?? true)
        for (final card in module.dashboardCards)
          if (!byId.containsKey(card.cardId)) card,
  ]..sort((a, b) => a.defaultRank.compareTo(b.defaultRank));
  for (final card in missing) {
    entries.add(
      DashboardEntry(
        descriptor: card,
        config: DashboardCardConfig(
          cardId: card.cardId,
          module: modules
              .firstWhere(
                (m) => m.dashboardCards.any((c) => c.cardId == card.cardId),
              )
              .id,
          visible: true,
          sortIndex: 1000 + card.defaultRank,
        ),
      ),
    );
  }
  return entries;
}

/// Which empty state applies when [shown] is empty.
DashboardEmptyReason dashboardEmptyReason({
  required List<DashboardEntry> shown,
  required Map<ModuleId, bool> moduleStatuses,
}) {
  if (shown.isNotEmpty) {
    return DashboardEmptyReason.none;
  }
  final anyModuleOn = ModuleId.values.any((m) => moduleStatuses[m] ?? true);
  return anyModuleOn
      ? DashboardEmptyReason.allCardsHidden
      : DashboardEmptyReason.allModulesOff;
}
