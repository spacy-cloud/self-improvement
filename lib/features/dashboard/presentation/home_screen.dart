import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/dashboard/domain/dashboard_layout.dart';
import 'package:self_improvement/core/dashboard/domain/motivation.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/application/dashboard_providers.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_cards_screen.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_routes.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/async_body.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/dashboard_card_grid.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_overview_card.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/first_day_section.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/level_up_notice_card.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/no_goals_card.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/streak_pill.dart';
import 'package:self_improvement/shared/german_date.dart';

/// The dashboard (`/`): date, day ring, streak entry and the configured cards
/// of the active modules.
///
/// Everything shown comes from the live projections (day status, streak) and
/// from the cards the modules register; the screen itself holds no business
/// rule and recomputes nothing. States: first day (welcome and starting
/// points), all modules off, all cards hidden, loading (a neutral line only
/// when it takes a moment) and error with retry. Success feedback after a save
/// comes from the saving flows; the dashboard only shows the new numbers.
class HomeScreen extends ConsumerWidget {
  /// Creates the screen.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(dashboardViewProvider);
    final model = view.value;
    final showStreak =
        model != null && model.gamificationEnabled && !model.showWelcome;
    return AppScaffold(
      title: 'Mein Dashboard',
      actions: <Widget>[if (showStreak) const StreakPill()],
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s32,
      ),
      body: AsyncBody<DashboardView>(
        value: view,
        onRetry: () => reloadDashboard(ref),
        data: (data) => _HomeContent(view: data),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.view});

  final DashboardView view;

  @override
  Widget build(BuildContext context) {
    if (view.emptyReason == DashboardEmptyReason.allModulesOff) {
      return EmptyState(
        title: 'Alle Module sind ausgeschaltet',
        message:
            'Schalte mindestens ein Modul ein, um Karten und Eingaben zu '
            'sehen. Deine Daten bleiben erhalten.',
        icon: AppIcon.modules,
        actionLabel: 'Module auswählen',
        onAction: () => context.push(DashboardRoutes.modules),
      );
    }
    if (view.showWelcome) {
      final first = view.firstEntry;
      return FirstDaySection(
        name: view.welcomeName,
        quickStarts: view.quickStarts,
        hasFirstEntry: first != null,
        onFirstEntry: () =>
            context.push(first?.route ?? DashboardRoutes.modules),
        onQuickStart: (start) => context.push(start.route),
      );
    }
    return _Overview(view: view);
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.view});

  final DashboardView view;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final day = view.dayStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          formatDateLong(view.today),
          style: AppTextStyles.bodyRegular.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Semantics(
          header: true,
          child: Text(
            'Dein Tag im Überblick',
            style: AppTextStyles.titleScreen.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        if (view.gamificationEnabled) const LevelUpNoticeCard(),
        if (view.hasRing)
          DayOverviewCard(
            fulfilled: day!.fulfilledCount,
            applicable: day.applicableCount,
            motivation: motivationTextFor(
              view.today,
              fulfilled: day.fulfilledCount,
              applicable: day.applicableCount,
            ),
            onTap: () => context.push(DashboardRoutes.goalsToday),
          )
        else
          NoGoalsCard(onSetGoals: () => context.push(DashboardRoutes.goals)),
        const SizedBox(height: AppSpacing.s12),
        if (view.entries.isEmpty)
          EmptyState(
            title: 'Alle Karten sind ausgeblendet',
            message:
                'Blende mindestens eine Karte wieder ein, damit sie hier '
                'erscheint.',
            icon: AppIcon.modules,
            actionLabel: 'Karten anpassen',
            onAction: () => unawaited(openDashboardCards(context)),
          )
        else ...<Widget>[
          DashboardCardGrid(entries: view.entries),
          const SizedBox(height: AppSpacing.s16),
          SecondaryButton(
            label: 'Karten anpassen',
            icon: Icons.tune_rounded,
            onPressed: () => unawaited(openDashboardCards(context)),
          ),
        ],
      ],
    );
  }
}
