import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/modules/application/dashboard_card_controller.dart';
import 'package:self_improvement/features/modules/domain/module_presentation.dart';
import 'package:self_improvement/features/modules/presentation/card_order_section.dart';
import 'package:self_improvement/features/modules/presentation/module_toggle_list.dart';
import 'package:self_improvement/features/modules/presentation/neutral_loading.dart';

/// "Module verwalten" (`/settings/modules`, Figma `4042:141`): switch the five
/// modules on or off, see that the data is kept, and set the order and
/// visibility of the dashboard cards.
///
/// Switching a module off only hides its screens and actions; with an open
/// focus session the focus module refuses and the user is led to the session.
/// With every module off the screen explains the state and offers to switch
/// them back on, so the user is never stuck.
class ModulesScreen extends ConsumerWidget {
  const ModulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statuses = ref.watch(moduleStatusesProvider);
    final value = statuses.value;
    return AppScaffold.subpage(
      title: 'Module',
      onBack: () => _leave(context),
      body: value != null
          ? _Content(statuses: value)
          : statuses.hasError
          ? ErrorState(onRetry: () => ref.invalidate(moduleStatusesProvider))
          : const SizedBox(height: 160, child: NeutralLoading()),
    );
  }

  static void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.statuses});

  final Map<ModuleId, bool> statuses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final allOff = allModulesOff(statuses);
    final cards = ref.watch(dashboardCardsProvider).value;
    final noVisibleCards =
        !allOff &&
        cards != null &&
        cards.isNotEmpty &&
        !hasVisibleCards(cards, statuses);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'Blende Bereiche aus, die du gerade nicht brauchst. '
            'Deine Daten bleiben dabei erhalten.',
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        if (allOff) ...<Widget>[
          EmptyState(
            title: 'Alle Module sind ausgeschaltet',
            message:
                'Das Dashboard zeigt dann keine Karten und das Plus-Menü '
                'bietet keine Einträge. Deine Daten bleiben erhalten.',
            actionLabel: 'Alle Module einschalten',
            onAction: () => unawaited(enableAllModules(context, ref)),
            icon: AppIcon.modules,
          ),
          const SizedBox(height: AppSpacing.s12),
        ],
        const ModuleToggleList(),
        const SizedBox(height: AppSpacing.s24),
        const AppSectionHeader(title: 'Reihenfolge im Dashboard'),
        const SizedBox(height: AppSpacing.s8),
        if (allOff)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'Ohne aktive Module gibt es keine Dashboard-Karten. Schalte '
              'ein Modul ein, um seine Karten zu ordnen.',
              style: AppTextStyles.bodyRegular.copyWith(
                color: colors.textSecondary,
              ),
            ),
          )
        else ...<Widget>[
          if (noVisibleCards) ...<Widget>[
            EmptyState(
              title: 'Alle Karten sind ausgeblendet',
              message:
                  'Das Dashboard zeigt keine Karten. Blende Karten wieder '
                  'ein, um deine Übersicht zurückzubekommen.',
              actionLabel: 'Alle Karten einblenden',
              onAction: () => unawaited(_showAllCards(context, ref)),
              icon: AppIcon.info,
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          const DashboardCardOrderSection(),
        ],
      ],
    );
  }

  Future<void> _showAllCards(BuildContext context, WidgetRef ref) async {
    final cards = ref.read(dashboardCardsProvider).value ?? const [];
    final hidden = [
      for (final card in cards)
        if (!card.visible) card.cardId,
    ];
    final failure = await ref
        .read(dashboardCardControllerProvider.notifier)
        .showAll(hidden);
    if (failure != null) {
      ref.read(feedbackServiceProvider).showError(failure.userMessage);
    }
  }
}
