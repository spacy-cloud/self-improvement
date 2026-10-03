import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/gamification/domain/badges.dart';
import 'package:self_improvement/features/gamification/presentation/gamification_labels.dart';

/// One badge: icon circle, title, short requirement and its state in words
/// ("Erreicht" / "Gesperrt"). A locked badge shows a lock and a muted surface,
/// an earned one its own icon in the colour of its meaning; the state is never
/// only a colour.
class BadgeTile extends StatelessWidget {
  /// Creates the tile of [badge].
  const BadgeTile({required this.badge, super.key});

  /// The badge with its current state (derived from the current data).
  final BadgeStatus badge;

  AppAccent get _accent => switch (badge.id) {
    BadgeId.firstStep => AppAccent.primary,
    BadgeId.oneWeek => AppAccent.streak,
    BadgeId.focusCollected => AppAccent.focus,
  };

  IconData get _icon => switch (badge.id) {
    BadgeId.firstStep => AppIcon.check.data,
    BadgeId.oneWeek => AppIcon.streak.data,
    BadgeId.focusCollected => AppIcon.focus.data,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final earned = badge.earned;
    return Semantics(
      container: true,
      label: badgeSemanticLabel(badge),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: earned ? colors.surface : colors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: colors.borderDecorative),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: AppSpacing.s12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: earned ? colors.accentTint(_accent) : colors.track,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s12),
                  child: Icon(
                    earned ? _icon : AppIcon.lock.data,
                    size: 28,
                    color: earned
                        ? colors.accent(_accent)
                        : colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                badge.title,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyStrong.copyWith(
                  color: earned ? colors.textPrimary : colors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                badgeRequirement(badge.id),
                textAlign: TextAlign.center,
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                badgeStateText(earned: earned),
                textAlign: TextAlign.center,
                style: AppTextStyles.captionStrong.copyWith(
                  color: earned ? colors.primaryText : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
