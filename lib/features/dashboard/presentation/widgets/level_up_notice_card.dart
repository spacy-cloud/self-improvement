import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/dashboard/application/level_up_notice.dart';
import 'package:self_improvement/features/gamification/application/gamification_providers.dart';
import 'package:self_improvement/features/gamification/domain/level.dart';
import 'package:self_improvement/shared/number_format.dart';

/// "Level n erreicht": the quiet notice after a committed activity pushed the
/// total XP over a level boundary.
///
/// It shows only for a level reached today and only while the total XP still
/// reaches that level (an undo that takes the XP back hides it again), and it
/// can be closed. It is announced to screen readers when it appears.
class LevelUpNoticeCard extends ConsumerWidget {
  /// Creates the notice.
  const LevelUpNoticeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(levelUpNoticeProvider);
    if (notice == null) {
      return const SizedBox.shrink();
    }
    final today = ref.watch(todayProvider);
    final totalXp = ref.watch(totalXpProvider).value;
    final levelNow = totalXp == null
        ? notice.levelUp.level
        : levelFor(totalXp).level;
    if (notice.day != today || levelNow < notice.levelUp.level) {
      return const SizedBox.shrink();
    }
    final colors = context.tokens.colors;
    final title = 'Level ${notice.levelUp.level} erreicht';
    final subtitle =
        'Du hast jetzt ${formatThousands(notice.levelUp.xpAfter)} XP '
        'gesammelt.';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            const AppIconTile(
              icon: Icons.bolt_rounded,
              accent: AppAccent.gamification,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Semantics(
                container: true,
                liveRegion: true,
                label: '$title. $subtitle',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppTextStyles.bodyStrong.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodyRegular.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AppIconButton(
              icon: AppIcon.close.data,
              semanticLabel: 'Hinweis schließen',
              onPressed: () =>
                  ref.read(levelUpNoticeProvider.notifier).dismiss(),
            ),
          ],
        ),
      ),
    );
  }
}
