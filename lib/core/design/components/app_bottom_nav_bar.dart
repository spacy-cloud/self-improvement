import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/icons/app_icons.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/motion/app_motion.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// A destination of [AppBottomNavBar].
class AppNavDestination {
  /// Creates a destination.
  const AppNavDestination({required this.icon, required this.label});

  /// Glyph key (the selected state uses the filled glyph where there is one).
  final AppIcon icon;

  /// Visible and spoken label.
  final String label;
}

/// Main navigation: four destinations (Home, Analyse, Habits, Profil) and the
/// centre plus button that opens the plus menu. The plus button is an action,
/// not a fifth tab.
///
/// The selected destination has a tinted pill, a filled icon and is announced
/// as selected; labels follow the system font scale up to 1.3 so that four
/// destinations plus the button fit on narrow screens. The plus button is
/// announced as "Eintrag hinzufügen"; with [plusOpen] it rotates into a close
/// button (150 ms, immediate with reduced motion) announced as "Schließen".
class AppBottomNavBar extends StatelessWidget {
  /// Creates the navigation bar.
  const AppBottomNavBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.onPlusPressed,
    super.key,
    this.plusOpen = false,
    this.plusLabel = 'Eintrag hinzufügen',
    this.plusOpenLabel = 'Schließen',
  });

  /// The four destinations in display order.
  static const List<AppNavDestination> destinations = <AppNavDestination>[
    AppNavDestination(icon: AppIcon.home, label: 'Home'),
    AppNavDestination(icon: AppIcon.analysis, label: 'Analyse'),
    AppNavDestination(icon: AppIcon.habits, label: 'Habits'),
    AppNavDestination(icon: AppIcon.profile, label: 'Profil'),
  ];

  /// Index of the selected destination (0 Home, 1 Analyse, 2 Habits, 3 Profil).
  final int selectedIndex;

  /// Called with the index of a tapped destination (also when it is already
  /// selected, so the shell can scroll to the top).
  final ValueChanged<int> onSelected;

  /// Called when the plus button is pressed.
  final VoidCallback onPlusPressed;

  /// Whether the plus menu is open (draws the close state).
  final bool plusOpen;

  /// Spoken label of the plus button.
  final String plusLabel;

  /// Spoken label of the plus button while the menu is open.
  final String plusOpenLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const overhang = 12.0;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Hauptnavigation',
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            top: overhang,
            child: ColoredBox(color: colors.surface),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              overhang + 12,
              14,
              8 + bottomInset,
            ),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: AppSizes.navLabelMaxTextScale,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final pill =
                      ((constraints.maxWidth - AppSizes.navPlusHalo) / 4).clamp(
                        AppSizes.touchMin,
                        AppSizes.navPillWidth,
                      );
                  Widget tab(int index) {
                    return _NavPill(
                      destination: destinations[index],
                      width: pill,
                      selected: index == selectedIndex,
                      onTap: () => onSelected(index),
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      tab(0),
                      tab(1),
                      const SizedBox(width: AppSizes.navPlusHalo),
                      tab(2),
                      tab(3),
                    ],
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: _PlusButton(
                open: plusOpen,
                label: plusOpen ? plusOpenLabel : plusLabel,
                onPressed: onPlusPressed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.destination,
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final AppNavDestination destination;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final foreground = selected ? colors.primaryText : colors.textSecondary;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: destination.label,
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: InkSurface(
          onTap: onTap,
          color: selected ? colors.primaryTint : null,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(28)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizes.navPillHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    AppIcons.of(destination.icon, selected: selected),
                    size: AppSizes.icon,
                    color: foreground,
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      softWrap: false,
                      style: AppTextStyles.captionNav.copyWith(
                        color: foreground,
                        fontWeight: selected ? FontWeight.w600 : null,
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

class _PlusButton extends StatelessWidget {
  const _PlusButton({
    required this.open,
    required this.label,
    required this.onPressed,
  });

  final bool open;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: AppSizes.navPlusHalo,
        child: InkSurface(
          onTap: onPressed,
          color: open ? colors.errorTint : colors.primaryTint,
          shape: const CircleBorder(),
          child: Center(
            child: AnimatedContainer(
              duration: motion.fast,
              curve: motion.curve,
              width: AppSizes.navPlusButton,
              height: AppSizes.navPlusButton,
              decoration: BoxDecoration(
                color: open ? colors.error : colors.primaryButton,
                shape: BoxShape.circle,
              ),
              child: AnimatedRotation(
                turns: open ? 0.125 : 0,
                duration: motion.fast,
                curve: motion.curve,
                child: Icon(
                  AppIcon.plus.data,
                  size: 30,
                  color: open ? colors.onError : colors.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
