import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_routes.dart';
import 'package:self_improvement/features/gamification/application/gamification_providers.dart';
import 'package:self_improvement/features/gamification/data/gamification_repository.dart';
import 'package:self_improvement/features/gamification/presentation/gamification_labels.dart';
import 'package:self_improvement/features/gamification/presentation/widgets/accent_progress_bar.dart';

/// The `xp` card of the dashboard: level, XP inside the level with its bar,
/// the XP missing to the next level and the total. The card opens the progress
/// page.
///
/// While the numbers are not read yet it shows a dash, never a made-up value;
/// a failed read shows the error state with its retry action.
class XpDashboardCard extends ConsumerWidget {
  /// Creates the card.
  const XpDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(gamificationSummaryProvider);
    if (summary.hasError && !summary.isLoading) {
      return ErrorState(
        onRetry: () => ref.invalidate(gamificationSummaryProvider),
      );
    }
    return _XpCard(summary: summary.value);
  }
}

class _XpCard extends StatelessWidget {
  const _XpCard({required this.summary});

  /// The numbers, or `null` while they are not read yet.
  final GamificationSummary? summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final data = summary;
    final header = Row(
      children: <Widget>[
        Icon(
          Icons.bolt_rounded,
          size: 24,
          color: colors.accent(AppAccent.gamification),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Text(
            'XP und Level',
            style: AppTextStyles.titleCard.copyWith(color: colors.textPrimary),
          ),
        ),
        const SizedBox(width: AppSpacing.s4),
        Icon(AppIcon.chevronRight.data, size: 20, color: colors.textSecondary),
      ],
    );
    final String label;
    final List<Widget> details;
    if (data == null) {
      label = 'XP und Level, wird geladen';
      details = <Widget>[
        Text(
          '–',
          style: AppTextStyles.titleScreen.copyWith(color: colors.textPrimary),
        ),
      ];
    } else {
      final level = data.level;
      label = 'XP und Level: ${levelSemanticLabel(level, data.totalXp)}';
      details = <Widget>[
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: AppSpacing.s8,
          children: <Widget>[
            Text(
              'Level ${level.level}',
              style: AppTextStyles.titleScreen.copyWith(
                color: colors.textPrimary,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                xpInLevelText(level),
                style: AppTextStyles.bodyRegular.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AccentProgressBar(
          value: level.fraction,
          semanticLabel: xpInLevelText(level),
        ),
        const SizedBox(height: 6),
        Text(
          '${xpToNextLevelText(level)} · ${totalXpText(data.totalXp)}',
          style: AppTextStyles.captionDefault.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ];
    }
    return AppCard(
      onTap: () => context.push(DashboardRoutes.progress),
      semanticLabel: '$label. Öffnet den Fortschritt',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[header, const SizedBox(height: 12), ...details],
      ),
    );
  }
}
