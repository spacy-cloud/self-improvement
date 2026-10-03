import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// How an [InlineMessage] is tinted. The tone never carries the meaning alone:
/// every message has an icon and a text.
enum InlineMessageTone { error, warning }

/// A short message directly at the thing it is about (a field, a card): icon
/// and text on a tint, announced as a live region when it appears.
class InlineMessage extends StatelessWidget {
  const InlineMessage({
    required this.text,
    super.key,
    this.tone = InlineMessageTone.error,
  });

  final String text;
  final InlineMessageTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final isError = tone == InlineMessageTone.error;
    final foreground = isError ? colors.error : colors.warningText;
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isError ? colors.errorTint : colors.warningTint,
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
                child: Icon(
                  isError ? AppIcon.error.data : AppIcon.info.data,
                  size: 14,
                  color: foreground,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: AppTextStyles.captionStrong.copyWith(
                    color: foreground,
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

/// The neutral loading text of a screen (no endless spinner).
class ScreenLoading extends StatelessWidget {
  const ScreenLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          'Wird geladen …',
          style: AppTextStyles.bodyRegular.copyWith(
            color: context.tokens.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// A heading line of a card: icon, title and an optional trailing text. The
/// trailing text sits at the right edge and moves below the title when there is
/// no room (large text), instead of squeezing the title.
class CardHeading extends StatelessWidget {
  const CardHeading({
    required this.icon,
    required this.title,
    required this.accent,
    super.key,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final AppAccent accent;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: colors.accent(accent)),
        const SizedBox(width: 8),
        Flexible(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: AppTextStyles.titleCard.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
    if (trailing == null) {
      return heading;
    }
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        heading,
        Text(
          trailing!,
          style: AppTextStyles.captionDefault.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// A section title with a small hint at the right edge ("optional"). The hint
/// moves below the title when there is no room.
class TitleWithHint extends StatelessWidget {
  const TitleWithHint({required this.title, required this.hint, super.key});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 2,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: AppTextStyles.titleCard.copyWith(color: colors.textPrimary),
          ),
        ),
        Text(
          hint,
          style: AppTextStyles.captionDefault.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
