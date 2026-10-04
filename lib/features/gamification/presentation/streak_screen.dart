import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_routes.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/async_body.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/text_scale.dart';
import 'package:self_improvement/features/gamification/presentation/gamification_labels.dart';
import 'package:self_improvement/features/gamification/presentation/widgets/accent_progress_bar.dart';
import 'package:self_improvement/features/gamification/presentation/widgets/streak_week_strip.dart';
import 'package:self_improvement/shared/local_date.dart';

/// "Deine Streak" (`/streak`): the running streak, the last seven days with
/// date and status, the longest streak, the number of active days, the next
/// milestone and the rule in one sentence.
///
/// Every number comes from the computed streak summary; nothing is stored or
/// invented. The screen works for any streak value, including 0 on the first
/// day.
class StreakScreen extends ConsumerWidget {
  /// Creates the screen.
  const StreakScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(streakProvider);
    final today = ref.watch(todayProvider);
    return AppScaffold.subpage(
      title: 'Deine Streak',
      onBack: () => leaveToHome(context),
      body: AsyncBody<StreakSummary?>(
        value: streak,
        onRetry: () => ref.invalidate(streakProvider),
        data: (summary) => summary == null
            ? const EmptyState(
                title: 'Noch keine Streak-Daten',
                message:
                    'Sobald dein Profil gestartet ist und du ein Tagesziel '
                    'erreichst, siehst du hier deine Serie.',
                icon: AppIcon.streak,
                accent: AppAccent.streak,
              )
            : _StreakContent(summary: summary, today: today),
      ),
    );
  }
}

class _StreakContent extends StatelessWidget {
  const _StreakContent({required this.summary, required this.today});

  final StreakSummary summary;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _HeroCard(summary: summary, today: today),
        const SizedBox(height: AppSpacing.s12),
        AdaptiveGrid(
          minCellWidth: 140,
          children: <Widget>[
            MetricCard(
              title: 'Längste Streak',
              value: '${summary.longest}',
              unit: summary.longest == 1 ? 'Tag' : 'Tage',
              icon: AppIcon.trophy.data,
              accent: AppAccent.gamification,
            ),
            MetricCard(
              title: 'Aktive Tage gesamt',
              value: '${summary.activeDays}',
              unit: summary.activeDays == 1 ? 'Tag' : 'Tage',
              icon: Icons.calendar_month_outlined,
              accent: AppAccent.water,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        _MilestoneCard(summary: summary),
        const SizedBox(height: AppSpacing.s12),
        const _RuleCard(),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.summary, required this.today});

  final StreakSummary summary;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final current = summary.current;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accentTint(AppAccent.streak),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: colors.accentFill(AppAccent.streak).withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    child: Icon(
                      AppIcon.streak.data,
                      size: 40,
                      color: colors.accent(AppAccent.streak),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Semantics(
              container: true,
              label: '$current ${streakUnit(current)}',
              excludeSemantics: true,
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: AppSpacing.s8,
                children: <Widget>[
                  Text(
                    '$current',
                    style: AppTextStyles.displayXl.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                    child: Text(
                      streakUnit(current),
                      style: AppTextStyles.titleSection.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              streakHint(summary),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyRegular.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            StreakWeekStrip(days: summary.lastSevenDays, today: today),
          ],
        ),
      ),
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({required this.summary});

  final StreakSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final title = Semantics(
      header: true,
      child: Text(
        'Nächster Meilenstein',
        style: AppTextStyles.titleSection.copyWith(color: colors.textPrimary),
      ),
    );
    final subtitle = Text(
      milestoneSubtitle(summary),
      style: AppTextStyles.bodyRegular.copyWith(color: colors.textSecondary),
    );
    final progress = Text(
      milestoneProgressText(summary),
      style: AppTextStyles.titleSection.copyWith(color: colors.textPrimary),
    );
    const tile = AppIconTile(
      icon: Icons.flag_outlined,
      accent: AppAccent.streak,
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (context.isLargeText) ...<Widget>[
            const Align(alignment: Alignment.centerLeft, child: tile),
            const SizedBox(height: AppSpacing.s8),
            title,
            subtitle,
            const SizedBox(height: AppSpacing.s4),
            progress,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                tile,
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[title, subtitle],
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                progress,
              ],
            ),
          const SizedBox(height: AppSpacing.s12),
          AccentProgressBar(
            value: summary.current / summary.nextMilestone,
            accent: AppAccent.streak,
            semanticLabel: milestoneSemanticLabel(summary),
          ),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const AppIconTile(
            icon: Icons.local_fire_department_outlined,
            accent: AppAccent.streak,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(
                    'So hältst du deine Streak',
                    style: AppTextStyles.bodyStrong.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  'Ein Tag zählt, sobald du mindestens eines deiner '
                  'Tagesziele erreichst. Heute kannst du bis Mitternacht noch '
                  'aktiv werden. Ein Tag ohne erreichtes Ziel setzt die Serie '
                  'zurück.',
                  style: AppTextStyles.bodyRegular.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
