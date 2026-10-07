import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/dashboard/domain/dashboard_layout.dart';
import 'package:self_improvement/core/dashboard/domain/motivation.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/application/dashboard_providers.dart';
import 'package:self_improvement/features/dashboard/application/day_browser_providers.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_cards_screen.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_routes.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/async_body.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/dashboard_card_grid.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_content_transition.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_navigator.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_overview_card.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_swipe.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/first_day_section.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/level_up_notice_card.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/no_goals_card.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/not_today_banner.dart';
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
///
/// Home pages through the days (BS-93): today and up to seven days before it. A
/// swipe to the right goes to the previous day, one to the left to the next; the
/// two arrows of the day navigator do the same without a gesture. A day that is
/// not today shows the note "Nicht heute" with "Zurück zu heute", the ring of
/// that day with its sentence, and the cards of that day, which only show (see
/// `DashboardCardDescriptor.dayBuilder`). The day shown is `browsedDayProvider`;
/// a new calendar day puts Home back on today.
class HomeScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// The last model that was ready. While the model of the next day is read, the
  /// page keeps showing it: paging never blanks the page, never loses the
  /// focus of an arrow and never throws the scroll position back to the top.
  DashboardView? _ready;

  @override
  Widget build(BuildContext context) {
    final fresh = ref.watch(dashboardViewProvider);
    if (fresh.hasValue) {
      _ready = fresh.requireValue;
    }
    final ready = _ready;
    final view = !fresh.hasValue && !fresh.hasError && ready != null
        ? AsyncData<DashboardView>(ready)
        : fresh;
    final model = view.value;
    final showStreak =
        model != null && model.gamificationEnabled && !model.showWelcome;
    // Swipes page only where there is a day to page to and the page shows days
    // (not the welcome, not the empty state of switched-off modules).
    final swipes =
        model != null &&
        model.day.isBrowsable &&
        !model.showWelcome &&
        model.emptyReason != DashboardEmptyReason.allModulesOff;
    return DaySwipe(
      enabled: swipes,
      onPrevious: () => ref.read(selectedDayProvider.notifier).previous(),
      onNext: () => ref.read(selectedDayProvider.notifier).next(),
      child: AppScaffold(
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

class _Overview extends ConsumerStatefulWidget {
  const _Overview({required this.view});

  final DashboardView view;

  @override
  ConsumerState<_Overview> createState() => _OverviewState();
}

class _OverviewState extends ConsumerState<_Overview> {
  /// The date of the day navigator: where the focus goes when the button that
  /// had it ("Zurück zu heute") has gone with the note it sat in.
  final FocusNode _dateFocus = FocusNode(debugLabel: 'home-date');

  @override
  void dispose() {
    _dateFocus.dispose();
    super.dispose();
  }

  void _backToToday() {
    ref.read(selectedDayProvider.notifier).backToToday();
    _dateFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final day = view.day;
    final colors = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (day.isBrowsable)
          DayNavigator(
            day: day,
            onPrevious: () => ref.read(selectedDayProvider.notifier).previous(),
            onNext: () => ref.read(selectedDayProvider.notifier).next(),
            dateFocusNode: _dateFocus,
          )
        else ...<Widget>[
          Text(
            formatDateLong(view.today),
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
        ],
        if (day.isToday) ...<Widget>[
          if (day.isBrowsable) const SizedBox(height: AppSpacing.s4),
          Semantics(
            header: true,
            child: Text(
              'Dein Tag im Überblick',
              style: AppTextStyles.titleScreen.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ] else
          NotTodayBanner(onBackToToday: _backToToday),
        SizedBox(height: day.isToday ? AppSpacing.s12 : AppSpacing.s8),
        DayContentTransition(
          day: day.date,
          child: _DayContent(view: view),
        ),
      ],
    );
  }
}

/// What depends on the day shown: the ring of the day, the cards of the day and
/// the way to arrange the cards.
class _DayContent extends StatelessWidget {
  const _DayContent({required this.view});

  final DashboardView view;

  @override
  Widget build(BuildContext context) {
    final day = view.day;
    final status = view.dayStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (view.gamificationEnabled && day.isToday) const LevelUpNoticeCard(),
        if (view.hasRing)
          DayOverviewCard(
            fulfilled: status!.fulfilledCount,
            applicable: status.applicableCount,
            // The titles of the stands speak of "today": a day that is not
            // today shows the factual sentence only (BS-121, D-026).
            motivation: day.isToday
                ? motivationTextFor(
                    view.today,
                    fulfilled: status.fulfilledCount,
                    applicable: status.applicableCount,
                  )
                : null,
            isToday: day.isToday,
            onTap: () => context.push(DashboardRoutes.goalsToday),
          )
        else if (day.isToday)
          NoGoalsCard(onSetGoals: () => context.push(DashboardRoutes.goals))
        else
          const NoGoalsCard(pastDay: true),
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
          DashboardCardGrid(
            entries: view.entries,
            day: day.isToday ? null : day.date,
          ),
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
