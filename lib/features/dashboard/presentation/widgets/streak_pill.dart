import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/tap_surface.dart';

/// The streak entry in the dashboard header: a flame and the number of days in
/// a row. It opens the streak screen (`/streak`).
///
/// The Home screen only builds it while the module "Fortschritt" is on. While
/// the streak is not known (loading, or no profile yet) nothing is shown, never
/// a made-up number.
class StreakPill extends ConsumerWidget {
  /// Creates the pill.
  const StreakPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(streakProvider).value;
    if (summary == null) {
      return const SizedBox.shrink();
    }
    final days = summary.current;
    final label = days == 1
        ? 'Streak: 1 Tag in Folge'
        : 'Streak: $days Tage in Folge';
    final colors = context.tokens.colors;
    void open() => context.push('/streak');
    return Semantics(
      container: true,
      button: true,
      label: '$label, öffnen',
      onTap: open,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
        child: Align(
          widthFactor: 1,
          child: TapSurface(
            onTap: open,
            shape: const StadiumBorder(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
              child: Align(
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: colors.accentTint(AppAccent.streak),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: colors.accentFill(AppAccent.gamification),
                      ),
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSizes.iconButtonVisual,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            AppIcon.streak.data,
                            size: AppSizes.icon,
                            color: colors.accent(AppAccent.streak),
                          ),
                          const SizedBox(width: AppSpacing.s4),
                          Text(
                            '$days',
                            style: AppTextStyles.titleSection.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
