import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/tap_surface.dart';

/// Frame of a selectable card: tinted fill and a heavier green border when
/// [selected], white with the decorative border otherwise. The change is
/// animated with [AppMotion] and immediate with reduced motion. The state is
/// never colour only: cards carry a check box or a switch.
class OptionCardFrame extends StatelessWidget {
  const OptionCardFrame({
    required this.selected,
    required this.child,
    super.key,
  });

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    return AnimatedContainer(
      duration: motion.fast,
      curve: motion.curve,
      decoration: BoxDecoration(
        color: selected ? colors.primaryTint : colors.surface,
        borderRadius: AppRadii.cardBorder,
        border: Border.all(
          color: selected ? colors.primaryButton : colors.borderDecorative,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: ClipRRect(borderRadius: AppRadii.cardBorder, child: child),
    );
  }
}

/// The icon tile of the onboarding cards (40 px, like the design).
Widget onboardingIconTile(IconData icon, AppAccent accent) =>
    AppIconTile(icon: icon, accent: accent, size: 40, iconSize: 22);

/// Whether the decorative icon tiles are drawn. From 160 % text size on they
/// are dropped, so the text keeps the room: long words such as "Gamification"
/// would otherwise break inside the word on a narrow screen.
bool showOnboardingIconTile(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) / 16 < 1.6;

/// A selectable goal card: icon tile, title, one line and a check box on the
/// right. The whole card is one multi-select control; screen readers hear
/// "ausgewählt" or "nicht ausgewählt" (and the platform checked state).
class GoalOptionCard extends StatelessWidget {
  const GoalOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final AppAccent accent;
  final bool selected;

  /// Called with the new selection.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final showTile = showOnboardingIconTile(context);
    void toggle() => onChanged(!selected);
    return Semantics(
      container: true,
      checked: selected,
      value: selected ? 'ausgewählt' : 'nicht ausgewählt',
      label: '$title, $subtitle',
      onTap: toggle,
      excludeSemantics: true,
      child: OptionCardFrame(
        selected: selected,
        child: TapSurface(
          onTap: toggle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: <Widget>[
                  if (showTile) ...<Widget>[
                    onboardingIconTile(icon, accent),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
                          style: AppTextStyles.titleCard.copyWith(
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
                  const SizedBox(width: 6),
                  ExcludeSemantics(
                    child: IgnorePointer(
                      child: RoundCheckbox(
                        value: selected,
                        onChanged: (_) {},
                        semanticLabel: title,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card with a switch (a module, an on/off goal): the whole card switches
/// the option. Uses the design system's list row, so the semantics are the
/// usual toggle ("ein", "aus") with the name and what it offers.
class ToggleOptionCard extends StatelessWidget {
  const ToggleOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final AppAccent accent;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return OptionCardFrame(
      selected: enabled,
      child: EntryListTile.toggle(
        title: title,
        subtitle: subtitle,
        value: enabled,
        onToggle: onChanged,
        leading: showOnboardingIconTile(context)
            ? onboardingIconTile(icon, accent)
            : null,
      ),
    );
  }
}
