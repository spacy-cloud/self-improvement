import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_routes.dart';
import 'package:self_improvement/features/gamification/application/gamification_providers.dart';
import 'package:self_improvement/features/gamification/domain/level.dart';
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
    final data = summary.value;
    return XpCardBody(level: data?.level, totalXp: data?.totalXp);
  }
}

/// The body of the XP card: level, XP inside the level with its bar, the XP
/// missing to the next level and the total. The card opens the progress page.
///
/// [level] and [totalXp] are `null` while the numbers are not read yet (a dash,
/// never a made-up value). With [stand] (a line such as "Stand am Ende dieses
/// Tages", BS-93) the card says which moment the numbers belong to.
class XpCardBody extends StatelessWidget {
  /// Creates the body.
  const XpCardBody({
    required this.level,
    required this.totalXp,
    this.stand,
    super.key,
  });

  /// Level and progress inside it, or `null` while loading.
  final LevelProgress? level;

  /// Total XP, or `null` while loading.
  final int? totalXp;

  /// Which moment the numbers belong to; `null` is now.
  final String? stand;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final level = this.level;
    final totalXp = this.totalXp;
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
    if (level == null || totalXp == null) {
      label = 'XP und Level, wird geladen';
      details = <Widget>[
        Text(
          '–',
          style: AppTextStyles.titleScreen.copyWith(color: colors.textPrimary),
        ),
      ];
    } else {
      label =
          'XP und Level: ${levelSemanticLabel(level, totalXp)}'
          '${stand == null ? '' : ', $stand'}';
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
          '${xpToNextLevelText(level)} · ${totalXpText(totalXp)}',
          style: AppTextStyles.captionDefault.copyWith(
            color: colors.textSecondary,
          ),
        ),
        if (stand != null)
          Text(
            stand!,
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
