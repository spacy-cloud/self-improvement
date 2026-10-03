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
      topPadding: welcomeTopSpace(context),
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

/// Space above the app mark: roomy on tall screens like the design, tight on
/// short ones so the cards stay in reach.
double welcomeTopSpace(BuildContext context) =>
    MediaQuery.sizeOf(context).height >= 760 ? 96 : AppSpacing.s32;

/// The soft circle behind the welcome screen (the design's hero background): a
/// large, pale green disc whose lower edge curves below the app mark. It starts
/// behind the status bar. Decorative: no semantics, no taps, no influence on
/// the layout.
class HeroBackdrop extends StatelessWidget {
  const HeroBackdrop({super.key});

  /// Height of the app mark and the gap between its bottom and the disc edge.
  static const double _markHeight = 96;
  static const double _edgeGap = 16;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final edge =
        MediaQuery.paddingOf(context).top +
        welcomeTopSpace(context) +
        _markHeight +
        _edgeGap;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size.infinite,
          painter: _BackdropPainter(
            color: colors.primaryTint.withValues(alpha: 0.55),
            edge: edge,
          ),
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({required this.color, required this.edge});

  final Color color;

  /// Distance from the top of the screen to the lowest point of the disc.
  final double edge;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.max(size.width * 0.8, 260.0);
    canvas.drawCircle(
      Offset(size.width / 2, edge - radius),
      radius,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.edge != edge;
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
