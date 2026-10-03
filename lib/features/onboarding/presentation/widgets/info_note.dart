import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// A quiet explanation in the style of the design's hint box: tinted fill, a
/// small icon and one or two lines. With [liveRegion] screen readers announce
/// it when it appears.
class InfoNote extends StatelessWidget {
  const InfoNote({
    required this.text,
    super.key,
    this.icon = AppIcon.hint,
    this.liveRegion = false,
  });

  final String text;
  final AppIcon icon;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.primaryTint,
          borderRadius: BorderRadius.circular(AppRadii.tile),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: ExcludeSemantics(
                  child: Icon(icon.data, size: 16, color: colors.primaryText),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.captionStrong.copyWith(
                    color: colors.primaryText,
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
