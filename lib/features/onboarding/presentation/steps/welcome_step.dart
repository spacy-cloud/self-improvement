import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/step_page.dart';

/// Screen 1: welcome. The app name, one line of what the app is for and three
/// short feature cards. No account, no sign-in and no data are asked here.
class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return StepPage(
      topPadding: AppSpacing.s32,
      children: <Widget>[
        const Center(child: _AppMark()),
        const SizedBox(height: AppSpacing.s32),
        Semantics(
          header: true,
          child: Text(
            AppConfig.appName,
            textAlign: TextAlign.center,
            style: AppTextStyles.displayL.copyWith(color: colors.textPrimary),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Kleine Schritte, große Veränderungen.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyDefault.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s32),
        const _FeatureCard(
          icon: Icons.check_rounded,
          accent: AppAccent.primary,
          title: 'Alles im Blick behalten',
          subtitle: 'Gewicht, Wasser & Workouts tracken',
        ),
        const SizedBox(height: AppSpacing.s12),
        _FeatureCard(
          icon: AppIcon.habits.data,
          accent: AppAccent.habits,
          title: 'Gute Gewohnheiten aufbauen',
          subtitle: 'mit Habits und Erinnerungen',
        ),
        const SizedBox(height: AppSpacing.s12),
        _FeatureCard(
          icon: AppIcon.flame.data,
          accent: AppAccent.streak,
          title: 'Dranbleiben mit deiner Streak',
          subtitle: 'jeden Tag ein kleines Ziel',
        ),
      ],
    );
  }
}

/// The soft circle behind the welcome screen (the design's hero background).
/// Decorative: no semantics, no taps, no influence on the layout.
class HeroBackdrop extends StatelessWidget {
  const HeroBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final diameter = math.max(520.0, constraints.maxWidth * 1.3);
            return ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                maxWidth: diameter,
                maxHeight: diameter,
                child: Transform.translate(
                  offset: const Offset(0, -210),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primaryTint.withValues(alpha: 0.55),
                    ),
                    child: SizedBox.square(dimension: diameter),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The app mark: a green rounded square with a rising arrow, 96 px. Drawn
/// with the design tokens, decorative.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return ExcludeSemantics(
      child: Container(
        width: 96,
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            colors: <Color>[colors.primary, colors.primaryButton],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(
          Icons.trending_up_rounded,
          size: 52,
          color: colors.onPrimary,
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final AppAccent accent;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      label: '$title, $subtitle',
      excludeSemantics: true,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        child: Row(
          children: <Widget>[
            AppIconTile(icon: icon, accent: accent, size: 40, iconSize: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: AppTextStyles.bodyStrong.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.captionDefault.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
