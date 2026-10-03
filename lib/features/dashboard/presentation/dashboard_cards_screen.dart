import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/dashboard/application/dashboard_cards_controller.dart';
import 'package:self_improvement/features/dashboard/application/dashboard_providers.dart';
import 'package:self_improvement/features/dashboard/domain/card_configuration.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_routes.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/delayed_loading_text.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/text_scale.dart';

/// Opens the card configuration above the whole app (also above the bottom
/// navigation), like the entry forms.
Future<void> openDashboardCards(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(builder: (context) => const DashboardCardsScreen()),
  );
}

/// "Karten anpassen": every card of the active modules with a switch for its
/// visibility and two ways to move it: the drag handle and the visible buttons
/// "nach oben" and "nach unten" (dragging is never the only way).
///
/// Every change is one stored command: it shows on the dashboard at once and
/// survives a restart. Cards of switched-off modules are not listed; their
/// settings are kept and come back with the module. A failed change leaves
/// everything as it was and offers the same change again.
class DashboardCardsScreen extends ConsumerWidget {
  /// Creates the page.
  const DashboardCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(configurableCardsProvider);
    // Keeps the controller alive while the page is open.
    ref.watch(dashboardCardsControllerProvider);
    final failed = cards.hasError && !cards.isLoading;
    final list = failed ? null : cards.value;
    return AppScaffold.subpage(
      title: 'Karten anpassen',
      scrollable: false,
      padding: EdgeInsets.zero,
      body: CustomScrollView(
        slivers: <Widget>[
          if (list == null || list.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverToBoxAdapter(
                child: _StateBody(failed: failed, loaded: list != null),
              ),
            )
          else
            ..._listSlivers(context, ref, list),
        ],
      ),
    );
  }

  List<Widget> _listSlivers(
    BuildContext context,
    WidgetRef ref,
    List<ConfigurableCard> cards,
  ) {
    final offModules = ref.watch(cardsOfOffModulesProvider);
    return <Widget>[
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
        sliver: SliverToBoxAdapter(child: _Intro()),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverReorderableList(
          itemCount: cards.length,
          onReorderItem: (oldIndex, newIndex) {
            if (newIndex == oldIndex) {
              return;
            }
            final card = cards[oldIndex];
            unawaited(
              _change(
                context,
                ref,
                action: () => ref
                    .read(dashboardCardsControllerProvider.notifier)
                    .reorder(oldIndex, newIndex),
                done:
                    '${card.descriptor.title} an Position ${newIndex + 1} von '
                    '${cards.length} verschoben',
              ),
            );
          },
          itemBuilder: (context, index) {
            final card = cards[index];
            return _CardRow(
              key: ValueKey<String>('dashboard-card-row-${card.cardId}'),
              card: card,
              index: index,
              count: cards.length,
              onVisibleChanged: (visible) => unawaited(
                _change(
                  context,
                  ref,
                  action: () => ref
                      .read(dashboardCardsControllerProvider.notifier)
                      .setVisible(card.cardId, visible: visible),
                  done: visible
                      ? '${card.descriptor.title} wird angezeigt'
                      : '${card.descriptor.title} ist ausgeblendet',
                ),
              ),
              onMove: (delta) => unawaited(
                _change(
                  context,
                  ref,
                  action: () => ref
                      .read(dashboardCardsControllerProvider.notifier)
                      .moveBy(card.cardId, delta),
                  done:
                      '${card.descriptor.title} an Position '
                      '${index + delta + 1} von ${cards.length} verschoben',
                ),
              ),
            );
          },
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        sliver: SliverToBoxAdapter(child: _OffModulesNote(count: offModules)),
      ),
    ];
  }

  /// Runs one change, tells screen readers what happened and reports a failure
  /// with the same change as retry (same command id, so it can never apply
  /// twice).
  Future<void> _change(
    BuildContext context,
    WidgetRef ref, {
    required Future<AppFailure?> Function() action,
    required String done,
  }) async {
    final FeedbackService feedback = ref.read(feedbackServiceProvider);
    final failure = await action();
    if (failure != null) {
      feedback.showError(
        failure is StorageFailure
            ? 'Die Änderung konnte nicht gespeichert werden. Deine Karten '
                  'sind unverändert.'
            : failure.userMessage,
        onRetry: () {
          if (context.mounted) {
            unawaited(_change(context, ref, action: action, done: done));
          }
        },
      );
      return;
    }
    if (context.mounted) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          done,
          Directionality.of(context),
        ),
      );
    }
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Blende Karten ein oder aus und ändere ihre Reihenfolge. Ziehe dazu den '
      'Griff oder nutze die Pfeiltasten.',
      style: AppTextStyles.bodyRegular.copyWith(
        color: context.tokens.colors.textSecondary,
      ),
    );
  }
}

class _OffModulesNote extends StatelessWidget {
  const _OffModulesNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return const SizedBox.shrink();
    }
    final colors = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          count == 1
              ? '1 weitere Karte gehört zu einem ausgeschalteten Modul. Sie '
                    'erscheint wieder, sobald du das Modul einschaltest.'
              : '$count weitere Karten gehören zu ausgeschalteten Modulen. Sie '
                    'erscheinen wieder, sobald du die Module einschaltest.',
          style: AppTextStyles.bodyRegular.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        SecondaryButton(
          label: 'Module verwalten',
          onPressed: () => context.push(DashboardRoutes.modules),
        ),
      ],
    );
  }
}

/// Loading, error and empty list of the page.
class _StateBody extends ConsumerWidget {
  const _StateBody({required this.failed, required this.loaded});

  final bool failed;
  final bool loaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (failed) {
      return ErrorState(
        onRetry: () {
          ref
            ..invalidate(dashboardCardsProvider)
            ..invalidate(moduleStatusesProvider);
        },
      );
    }
    if (!loaded) {
      return const DelayedLoadingText();
    }
    return EmptyState(
      title: 'Keine Karten verfügbar',
      message:
          'Schalte Module ein, damit ihre Karten hier erscheinen. Deine '
          'Einstellungen bleiben erhalten.',
      icon: AppIcon.modules,
      actionLabel: 'Module auswählen',
      onAction: () => context.push(DashboardRoutes.modules),
    );
  }
}

/// One card: drag handle, name and state in words, the buttons "nach oben" and
/// "nach unten" and the visibility switch. With large text or on a narrow
/// screen the controls move to their own line, so no label is squeezed.
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.card,
    required this.index,
    required this.count,
    required this.onVisibleChanged,
    required this.onMove,
    super.key,
  });

  final ConfigurableCard card;
  final int index;
  final int count;
  final ValueChanged<bool> onVisibleChanged;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final title = card.descriptor.title;
    final handle = ReorderableDragStartListener(
      index: index,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: AppSizes.touchMin,
          child: Center(
            child: Icon(
              Icons.drag_indicator_rounded,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          style: AppTextStyles.bodyStrong.copyWith(
            color: card.visible ? colors.textPrimary : colors.textSecondary,
          ),
        ),
        Text(
          card.visible ? 'Sichtbar' : 'Ausgeblendet',
          style: AppTextStyles.captionDefault.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
    final up = AppIconButton(
      icon: Icons.arrow_upward_rounded,
      semanticLabel: '$title nach oben verschieben',
      onPressed: index > 0 ? () => onMove(-1) : null,
    );
    final down = AppIconButton(
      icon: Icons.arrow_downward_rounded,
      semanticLabel: '$title nach unten verschieben',
      onPressed: index < count - 1 ? () => onMove(1) : null,
    );
    final toggle = AppSwitch(
      value: card.visible,
      onChanged: onVisibleChanged,
      semanticLabel: '$title auf dem Dashboard anzeigen',
    );
    final stacked =
        context.isLargeText || MediaQuery.sizeOf(context).width < 360;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      handle,
                      Expanded(child: texts),
                      toggle,
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[up, down],
                  ),
                ],
              )
            : Row(
                children: <Widget>[
                  handle,
                  Expanded(child: texts),
                  up,
                  down,
                  toggle,
                ],
              ),
      ),
    );
  }
}
