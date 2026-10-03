import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// Visibility and position of one dashboard card.
@immutable
final class DashboardCardConfig {
  const DashboardCardConfig({
    required this.cardId,
    required this.module,
    required this.visible,
    required this.sortIndex,
  });

  final String cardId;
  final ModuleId module;
  final bool visible;
  final int sortIndex;
}

/// Persistent card configuration. Cards of a deactivated module are hidden by
/// the dashboard but their configuration is kept.
class DashboardCardRepository {
  DashboardCardRepository({required this._database, required this._runner});

  static const String setVisibleType = 'dashboard.card.set_visible';
  static const String moveType = 'dashboard.card.move';

  final AppDatabase _database;
  final CommandRunner _runner;

  /// All cards in display order (position, then id).
  Stream<List<DashboardCardConfig>> watchCards() =>
      (_database.select(_database.dashboardCards)..orderBy([
            (c) => OrderingTerm.asc(c.sortIndex),
            (c) => OrderingTerm.asc(c.cardId),
          ]))
          .watch()
          .map(
            (rows) => rows.map(_map).whereType<DashboardCardConfig>().toList(),
          );

  Future<List<DashboardCardConfig>> cards() => watchCards().first;

  /// Shows or hides one card.
  Future<CommandOutcome> setVisible({
    required String commandId,
    required String cardId,
    required bool visible,
  }) {
    return _runner.run(
      commandId: commandId,
      type: setVisibleType,
      body: (ctx) async {
        final row = await (_database.select(
          _database.dashboardCards,
        )..where((c) => c.cardId.equals(cardId))).getSingleOrNull();
        if (row == null) {
          throw NotFoundFailure(entity: 'dashboard_card', id: cardId);
        }
        await (_database.update(_database.dashboardCards)
              ..where((c) => c.cardId.equals(cardId)))
            .write(DashboardCardsCompanion(visible: Value(visible)));
        return CommandEffect(entityId: cardId);
      },
    );
  }

  /// Moves a card to [toIndex] (0-based position in the full list); all other
  /// positions are renumbered contiguously. Used by drag handles AND by the
  /// up/down buttons ([moveBy]).
  Future<CommandOutcome> move({
    required String commandId,
    required String cardId,
    required int toIndex,
  }) {
    return _runner.run(
      commandId: commandId,
      type: moveType,
      body: (ctx) async {
        final rows =
            await (_database.select(_database.dashboardCards)..orderBy([
                  (c) => OrderingTerm.asc(c.sortIndex),
                  (c) => OrderingTerm.asc(c.cardId),
                ]))
                .get();
        final from = rows.indexWhere((c) => c.cardId == cardId);
        if (from < 0) {
          throw NotFoundFailure(entity: 'dashboard_card', id: cardId);
        }
        final target = toIndex.clamp(0, rows.length - 1);
        final reordered = [...rows];
        final moved = reordered.removeAt(from);
        reordered.insert(target, moved);
        for (var position = 0; position < reordered.length; position++) {
          final card = reordered[position];
          if (card.sortIndex != position) {
            await (_database.update(_database.dashboardCards)
                  ..where((c) => c.cardId.equals(card.cardId)))
                .write(DashboardCardsCompanion(sortIndex: Value(position)));
          }
        }
        return CommandEffect(entityId: cardId);
      },
    );
  }

  /// Moves a card up (`-1`) or down (`+1`) by one position: the accessible
  /// alternative to dragging.
  Future<CommandOutcome> moveBy({
    required String commandId,
    required String cardId,
    required int delta,
  }) async {
    final all = await cards();
    final index = all.indexWhere((c) => c.cardId == cardId);
    if (index < 0) {
      throw NotFoundFailure(entity: 'dashboard_card', id: cardId);
    }
    return move(commandId: commandId, cardId: cardId, toIndex: index + delta);
  }

  static DashboardCardConfig? _map(DashboardCardRow row) {
    final module = ModuleId.tryParse(row.moduleId);
    if (module == null) {
      return null;
    }
    return DashboardCardConfig(
      cardId: row.cardId,
      module: module,
      visible: row.visible,
      sortIndex: row.sortIndex,
    );
  }
}
