import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';

/// A dashboard card contributed by a module.
///
/// `cardId` must be one of `SchemaKeys.dashboardCards` (unknown ids are
/// invalid). The owning module determines whether the card is visible at all;
/// the user may additionally hide and reorder cards.
@immutable
final class DashboardCardDescriptor {
  const DashboardCardDescriptor({
    required this.cardId,
    required this.title,
    required this.defaultRank,
    required this.builder,
    this.fullWidth = false,
    this.dayBuilder,
  });

  /// Stable id, e.g. `water`.
  final String cardId;

  /// German title used in the card configuration UI.
  final String title;

  /// Default position (lower first). The default order is
  /// steps, water, weight, workout, focus, tasks, nutrition, xp.
  final int defaultRank;

  /// Large overview cards (tasks, XP) use the full width; small metric cards
  /// share a row when there is room (two columns at normal text scale).
  final bool fullWidth;

  /// Builds the card. Quick actions inside the card must not trigger the card
  /// tap (detail navigation).
  final Widget Function(BuildContext context, WidgetRef ref) builder;

  /// Builds the card for a day that is NOT today (BS-93), the day Home shows
  /// when a person pages back through the last days. The card shows what that
  /// day had, from the facts and the goals of that day, and only shows: no quick
  /// action, nothing that records something. Opening the module page from the
  /// card stays possible, because recording for an earlier day happens in the
  /// forms.
  ///
  /// `null` means the module has no card for another day; Home then leaves the
  /// card out on those days rather than show today's numbers under the date of
  /// another day.
  final Widget Function(BuildContext context, WidgetRef ref, LocalDate day)?
  dayBuilder;
}

/// An entry offered by the plus menu to create a record.
@immutable
final class QuickAction {
  const QuickAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.route,
    required this.plusOrder,
    this.dynamicLabel,
  });

  /// Stable id, e.g. `weight`, `workout`, `water`, `steps`, `focus`, `task`,
  /// `habit`, `meal`.
  final String id;

  /// German label, e.g. "Gewicht".
  final String label;

  final IconData icon;

  /// Route opened on selection (root navigator).
  final String route;

  /// Position in the fixed plus menu order: Gewicht 0, Workout 1, Wasser 2,
  /// Schritte 3, Fokus 4, Aufgabe 5, Gewohnheit 6, Mahlzeit 7.
  final int plusOrder;

  /// Optional state dependent label, e.g. "Sitzung fortsetzen" while a focus
  /// timer runs. Falls back to [label].
  final String Function(WidgetRef ref)? dynamicLabel;
}

/// Result of asking a module whether it may be switched off.
@immutable
sealed class DeactivationCheck {
  const DeactivationCheck();
}

/// The module can be deactivated right away.
final class CanDeactivate extends DeactivationCheck {
  const CanDeactivate();
}

/// An open resource blocks deactivation (e.g. a running focus session). The
/// UI shows [message] and the resolution action instead of deactivating.
final class MustResolveFirst extends DeactivationCheck {
  const MustResolveFirst({required this.message, required this.resolveLabel});

  /// German explanation, e.g. "Beende zuerst die laufende Sitzung".
  final String message;

  /// German label of the primary resolution action, e.g. "Sitzung zuerst beenden".
  final String resolveLabel;
}

/// Contract of a bundled functional module (no plugin marketplace, no loaded
/// code). Activation only shows/hides screens and actions; data is never
/// deleted by deactivation.
abstract class SelfImprovementModule {
  const SelfImprovementModule();

  /// Stable id (`body`, `nutrition`, `focus`, `tasks`, `gamification`).
  ModuleId get id;

  /// German display name, e.g. "Körper".
  String get title;

  /// German one-line description for the module manager.
  String get description;

  IconData get icon;

  /// Routes of this module (registered once, guarded centrally by status).
  List<RouteBase> get routes;

  /// Dashboard cards of this module, in default order.
  List<DashboardCardDescriptor> get dashboardCards;

  /// Plus menu entries of this module.
  List<QuickAction> get quickActions;

  /// Asynchronous, idempotent initialisation: no duplicate timers or
  /// subscriptions when called repeatedly.
  Future<void> initialize(Ref ref) async {}

  /// Whether the module may be deactivated now.
  Future<DeactivationCheck> canDeactivate(Ref ref) async =>
      const CanDeactivate();

  /// Releases resources. Must never delete persisted data.
  void dispose() {}
}
