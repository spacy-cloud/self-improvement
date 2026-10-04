import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/modules/dashboard_card_repository.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// One row of the card configuration page: the descriptor the owning module
/// registered and the stored visibility and position.
@immutable
final class ConfigurableCard {
  const ConfigurableCard({required this.descriptor, required this.config});

  final DashboardCardDescriptor descriptor;
  final DashboardCardConfig config;

  String get cardId => config.cardId;

  bool get visible => config.visible;

  ModuleId get module => config.module;
}

/// The cards the user can configure, in stored order.
///
/// These are all cards of ENABLED modules, visible or hidden. Cards of a
/// switched-off module are left out (they cannot appear on the dashboard
/// anyway) but keep their stored configuration, so nothing is lost when the
/// module is switched on again. Stored cards without a descriptor are ignored,
/// like on the dashboard itself.
///
/// [configs] is expected in the stored order (position, then id), as
/// `DashboardCardRepository.watchCards` delivers it.
List<ConfigurableCard> configurableDashboardCards({
  required Iterable<DashboardCardConfig> configs,
  required Map<ModuleId, bool> moduleStatuses,
  required Iterable<SelfImprovementModule> modules,
}) {
  final descriptors = <String, DashboardCardDescriptor>{
    for (final module in modules)
      for (final card in module.dashboardCards) card.cardId: card,
  };
  return List.unmodifiable(<ConfigurableCard>[
    for (final config in configs)
      if ((moduleStatuses[config.module] ?? true) &&
          descriptors.containsKey(config.cardId))
        ConfigurableCard(
          descriptor: descriptors[config.cardId]!,
          config: config,
        ),
  ]);
}

/// How many stored cards belong to switched-off modules and are therefore not
/// offered for configuration (the page tells the user where they went).
int hiddenByModuleCount({
  required Iterable<DashboardCardConfig> configs,
  required Map<ModuleId, bool> moduleStatuses,
  required Iterable<SelfImprovementModule> modules,
}) {
  final known = <String>{
    for (final module in modules)
      for (final card in module.dashboardCards) card.cardId,
  };
  return configs
      .where(
        (config) =>
            known.contains(config.cardId) &&
            !(moduleStatuses[config.module] ?? true),
      )
      .length;
}

/// The position to hand to `DashboardCardRepository.move` when the card at
/// [fromShown] takes the place of the card at [toShown].
///
/// Both indexes refer to [shown] (the configurable list). The repository
/// numbers ALL stored cards, including those of switched-off modules that are
/// not listed, so a plain "one step up" could swap with an invisible card and
/// change nothing on screen. The target is therefore the position of the
/// neighbour in the full list [all].
///
/// Returns `null` when there is nothing to do: same position, an index outside
/// the list or a neighbour that is not stored.
int? fullListTargetIndex({
  required List<DashboardCardConfig> all,
  required List<ConfigurableCard> shown,
  required int fromShown,
  required int toShown,
}) {
  if (fromShown == toShown ||
      fromShown < 0 ||
      toShown < 0 ||
      fromShown >= shown.length ||
      toShown >= shown.length) {
    return null;
  }
  final target = shown[toShown].cardId;
  final index = all.indexWhere((config) => config.cardId == target);
  return index < 0 ? null : index;
}
