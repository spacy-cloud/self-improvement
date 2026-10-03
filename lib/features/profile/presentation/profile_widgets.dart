import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// Round profile picture: the initials of the name, or the neutral profile
/// icon without a name. Decorative: the texts next to it carry the meaning.
///
/// Solid button green with white text (4.5:1 in all themes); the Figma
/// gradient would drop below the contrast limit at its light end.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({required this.initials, this.size = 56, super.key});

  /// Initials of at most two name parts, or `null` for the neutral icon.
  final String? initials;

  /// Diameter.
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final text = initials;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: text == null ? colors.primaryTint : colors.primaryButton,
          ),
          child: Center(
            child: text == null
                ? Icon(
                    AppIcon.profile.data,
                    size: size * 0.5,
                    color: colors.primaryText,
                  )
                : MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Text(
                      text,
                      maxLines: 1,
                      style: AppTextStyles.titleSection.copyWith(
                        fontSize: size * 0.36,
                        color: colors.onPrimary,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Error message below a field: icon and text on the error tint (never colour
/// alone). Announced as soon as it appears.
class LiveFieldError extends StatelessWidget {
  const LiveFieldError({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorTint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(AppIcon.error.data, size: 14, color: colors.error),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: AppTextStyles.captionStrong.copyWith(
                    color: colors.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Information block on a tinted surface with a leading icon (for example the
/// "gilt ab morgen" notice of the goal editor). The icon is decorative.
class InfoNotice extends StatelessWidget {
  const InfoNotice({
    required this.text,
    this.icon = AppIcon.info,
    this.accent = AppAccent.water,
    super.key,
  });

  final String text;
  final AppIcon icon;
  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.accentTint(accent),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon.data, size: 18, color: colors.accent(accent)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.captionDefault.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks "Änderungen verwerfen?"; `true` means discard. "Weiter bearbeiten" is
/// the safe default and the sheet closes with Android back.
Future<bool> confirmDiscardChanges(BuildContext context) {
  return showConfirmationSheet(
    context,
    title: 'Änderungen verwerfen?',
    message: 'Deine Eingaben sind noch nicht gespeichert.',
    confirmLabel: 'Verwerfen',
    cancelLabel: 'Weiter bearbeiten',
  );
}
