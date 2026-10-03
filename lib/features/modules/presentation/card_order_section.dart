import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/modules/dashboard_card_repository.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/modules/application/dashboard_card_controller.dart';
import 'package:self_improvement/features/modules/application/module_providers.dart';
import 'package:self_improvement/features/modules/domain/module_presentation.dart';
import 'package:self_improvement/features/modules/presentation/neutral_loading.dart';

/// "Reihenfolge im Dashboard": every card with its position, buttons to move
/// it up or down (the button alternative to dragging) and a button to hide or
/// show it. The order and visibility are stored; cards of switched-off modules
/// stay in the list (marked), so reactivating a module restores its card.
class DashboardCardOrderSection extends ConsumerWidget {
  const DashboardCardOrderSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(dashboardCardsProvider);
    final statuses =
        ref.watch(moduleStatusesProvider).value ?? const <ModuleId, bool>{};
    final busy = ref.watch(dashboardCardControllerProvider);
    final modules = ref.watch(appModulesProvider);
    final items = cards.value;
    if (items == null) {
      if (cards.hasError) {
        return ErrorState(
          onRetry: () => ref.invalidate(dashboardCardsProvider),
        );
      }
      return const SizedBox(height: 96, child: NeutralLoading());
    }
    final feedback = ref.read(feedbackServiceProvider);
    final controller = ref.read(dashboardCardControllerProvider.notifier);

    Future<void> report(Future<AppFailure?> change) async {
      final failure = await change;
      if (failure != null) {
        feedback.showError(failure.userMessage);
      }
    }

    return AppListGroup(
      children: <Widget>[
        for (var index = 0; index < items.length; index++)
          _CardOrderRow(
            key: ValueKey<String>('card-order-${items[index].cardId}'),
            position: index + 1,
            count: items.length,
            title: cardTitle(items[index].cardId, modules),
            visible: items[index].visible,
            moduleOn: statuses[items[index].module] ?? true,
            canMoveUp:
                !busy && canMove(index: index, count: items.length, delta: -1),
            canMoveDown:
                !busy && canMove(index: index, count: items.length, delta: 1),
            canToggleVisible: !busy,
            onMoveUp: () =>
                unawaited(report(controller.moveBy(items[index].cardId, -1))),
            onMoveDown: () =>
                unawaited(report(controller.moveBy(items[index].cardId, 1))),
            onToggleVisible: () => unawaited(
              report(
                controller.setVisible(
                  items[index].cardId,
                  visible: !items[index].visible,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Whether at least one card would be shown on the dashboard right now: its
/// own visibility is on and its module is switched on.
bool hasVisibleCards(
  List<DashboardCardConfig> cards,
  Map<ModuleId, bool> statuses,
) => cards.any((card) => card.visible && (statuses[card.module] ?? true));

class _CardOrderRow extends StatelessWidget {
  const _CardOrderRow({
    required this.position,
    required this.count,
    required this.title,
    required this.visible,
    required this.moduleOn,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canToggleVisible,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggleVisible,
    super.key,
  });

  final int position;
  final int count;
  final String title;
  final bool visible;
  final bool moduleOn;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canToggleVisible;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onToggleVisible;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final stacked = scale > AppSizes.stackTextScale;
    final note = !moduleOn
        ? 'Modul ausgeschaltet'
        : (visible ? null : 'Ausgeblendet');
    final spoken = StringBuffer('$title, Position $position von $count');
    if (note != null) {
      spoken.write(', $note');
    }

    final label = Semantics(
      container: true,
      label: spoken.toString(),
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Text(
              '$position',
              style: AppTextStyles.captionStrong.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: AppTextStyles.bodyDefault.copyWith(
                    color: visible && moduleOn
                        ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                ),
                if (note != null)
                  Text(
                    note,
                    style: AppTextStyles.captionDefault.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppIconButton(
          icon: visible
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          semanticLabel: visible ? '$title ausblenden' : '$title einblenden',
          onPressed: canToggleVisible ? onToggleVisible : null,
        ),
        AppIconButton(
          icon: AppIcon.collapse.data,
          semanticLabel: '$title nach oben',
          onPressed: canMoveUp ? onMoveUp : null,
        ),
        AppIconButton(
          icon: AppIcon.expand.data,
          semanticLabel: '$title nach unten',
          onPressed: canMoveDown ? onMoveDown : null,
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(padding: const EdgeInsets.only(top: 8), child: label),
                  Align(alignment: Alignment.centerRight, child: controls),
                ],
              )
            : Row(
                children: <Widget>[
                  Expanded(child: label),
                  controls,
                ],
              ),
      ),
    );
  }
}
