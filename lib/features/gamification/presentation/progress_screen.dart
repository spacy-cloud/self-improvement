import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_routes.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/async_body.dart';
import 'package:self_improvement/features/gamification/application/gamification_providers.dart';
import 'package:self_improvement/features/gamification/data/gamification_repository.dart';
import 'package:self_improvement/features/gamification/domain/level.dart';
import 'package:self_improvement/features/gamification/presentation/gamification_labels.dart';
import 'package:self_improvement/features/gamification/presentation/widgets/accent_progress_bar.dart';
import 'package:self_improvement/features/gamification/presentation/widgets/badge_tile.dart';

/// "Dein Fortschritt" (`/progress`): total XP, the level with its bar
/// (XP inside the level out of 100), the three badges as earned or locked and
/// the way to the streak page.
///
/// XP, level and badges are derived from the current data by the engine; the
/// screen only shows them. A fresh installation honestly shows level 1 with
/// 0 XP and three locked badges.
class ProgressScreen extends ConsumerWidget {
  /// Creates the screen.
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(gamificationSummaryProvider);
    return AppScaffold.subpage(
      title: 'Dein Fortschritt',
      onBack: () => leaveToHome(context),
      body: AsyncBody<GamificationSummary>(
        value: summary,
        onRetry: () {
          ref
            ..invalidate(gamificationSummaryProvider)
            ..invalidate(streakProvider);
        },
        data: (data) => _ProgressContent(summary: data),
      ),
    );
  }
}

class _ProgressContent extends StatelessWidget {
  const _ProgressContent({required this.summary});

  final GamificationSummary summary;

  @override
  Widget build(BuildContext context) {
    final earned = summary.badges.where((badge) => badge.earned).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LevelCard(summary: summary),
        const SizedBox(height: AppSpacing.s12),
        const _StreakLink(),
        const SizedBox(height: AppSpacing.s16),
        _BadgesHeader(earned: earned, total: summary.badges.length),
        const SizedBox(height: AppSpacing.s8),
        AdaptiveGrid(
          maxColumns: 3,
          minCellWidth: 104,
          children: <Widget>[
            for (final badge in summary.badges) BadgeTile(badge: badge),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        const _XpInfoCard(),
      ],
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.summary});

  final GamificationSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final level = summary.level;
    return Semantics(
      container: true,
      label: levelSemanticLabel(level, summary.totalXp),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.accentTint(AppAccent.gamification),
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: colors
                .accentFill(AppAccent.gamification)
                .withValues(alpha: 0.45),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  _LevelTile(level: level.level),
                  const SizedBox(width: AppSpacing.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Level ${level.level}',
                          style: AppTextStyles.titleScreen.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          xpInLevelText(level),
                          style: AppTextStyles.bodyStrong.copyWith(
                            color: colors.accent(AppAccent.gamification),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s12),
              AccentProgressBar(
                value: level.fraction,
                semanticLabel: xpInLevelText(level),
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                xpToNextLevelText(level),
                style: AppTextStyles.bodyRegular.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              Text(
                totalXpText(summary.totalXp),
                style: AppTextStyles.bodyRegular.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The square "LVL n" tile; it grows with the text instead of clipping it.
class _LevelTile extends StatelessWidget {
  const _LevelTile({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final textColor = colors.accentTextOnTint(AppAccent.gamification);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colors.accentFill(AppAccent.gamification),
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.s4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'LVL',
                style: AppTextStyles.captionStrong.copyWith(color: textColor),
              ),
              Text(
                '$level',
                style: AppTextStyles.titleScreen.copyWith(color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreakLink extends ConsumerWidget {
  const _StreakLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(streakProvider).value;
    final title = summary == null
        ? 'Streak ansehen'
        : 'Streak: ${daysText(summary.current)} in Folge';
    return AppListGroup(
      children: <Widget>[
        EntryListTile.chevron(
          title: title,
          subtitle: 'Letzte sieben Tage und Meilensteine',
          icon: AppIcon.streak.data,
          accent: AppAccent.streak,
          onTap: () => context.push(DashboardRoutes.streak),
        ),
      ],
    );
  }
}

class _BadgesHeader extends StatelessWidget {
  const _BadgesHeader({required this.earned, required this.total});

  final int earned;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Row(
      children: <Widget>[
        const Expanded(child: AppSectionHeader(title: 'Badges')),
        Semantics(
          container: true,
          label: '$earned von $total Badges erreicht',
          excludeSemantics: true,
          child: Text(
            '$earned von $total',
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _XpInfoCard extends StatelessWidget {
  const _XpInfoCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const AppIconTile(
            icon: Icons.info_outline_rounded,
            accent: AppAccent.gamification,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(
                    'So sammelst du XP',
                    style: AppTextStyles.bodyStrong.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  'Für erfasste Aktivitäten gibt es feste Punkte. Alle '
                  '$xpPerLevel XP steigst du ein Level auf. Badges ergeben '
                  'sich aus deinen aktuellen Daten: Löschst du Einträge, kann '
                  'ein Badge wieder gesperrt sein.',
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
