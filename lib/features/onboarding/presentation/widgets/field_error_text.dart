import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// The error line below a field or row: a small icon and the German hint in the
/// error colour (never colour alone). Announced as a live region when it
/// appears.
class FieldErrorText extends StatelessWidget {
  const FieldErrorText({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: ExcludeSemantics(
                child: Icon(AppIcon.error.data, size: 14, color: colors.error),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
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
    );
  }
}
