import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// The persistent error above the primary button when finishing or skipping
/// could not be saved: what happened, that the input is kept, and "Erneut
/// versuchen". Announced to screen readers when it appears. The icon and the
/// text carry the state, not the colour alone.
class SubmitErrorBanner extends StatelessWidget {
  const SubmitErrorBanner({
    required this.message,
    required this.onRetry,
    super.key,
  });

  /// German explanation without technical details.
  final String message;

  /// Repeats the failed attempt; `null` disables the button while it runs.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorTint,
        borderRadius: AppRadii.cardBorder,
        border: Border.all(color: colors.error, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(
              container: true,
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: ExcludeSemantics(
                      child: Icon(
                        AppIcon.error.data,
                        size: 18,
                        color: colors.error,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      message,
                      style: AppTextStyles.bodyStrong.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            SecondaryButton(
              label: 'Erneut versuchen',
              icon: AppIcon.retry.data,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
