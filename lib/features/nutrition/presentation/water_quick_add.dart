import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/features/nutrition/application/water_quick_add_controller.dart';
import 'package:self_improvement/features/nutrition/domain/water_format.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_widgets.dart';

/// German text of a quick add that could not be saved. A storage failure says
/// that nothing was stored; anything else carries its own message.
String waterQuickAddFailureMessage(AppFailure failure) =>
    failure is StorageFailure
    ? 'Speichern fehlgeschlagen. Es wurde nichts hinzugefügt.'
    : failure.userMessage;

/// Adds [amountMl] with one tap: ONE command with a new command id, then the
/// success message with "Rückgängig" (8 s) AFTER the commit, or the failure
/// message with a retry that repeats the SAME command.
///
/// Used by the dashboard card and the water screen. Everything the future needs
/// is read before the first await, so the caller may disappear in between.
Future<void> runWaterQuickAdd(WidgetRef ref, int amountMl) {
  return _quickAdd(
    controller: ref.read(waterQuickAddProvider.notifier),
    feedback: ref.read(feedbackServiceProvider),
    amountMl: amountMl,
  );
}

/// Repeats the failed quick add with its original command id.
Future<void> retryWaterQuickAdd(WidgetRef ref) {
  final controller = ref.read(waterQuickAddProvider.notifier);
  final feedback = ref.read(feedbackServiceProvider);
  final amountMl = ref.read(waterQuickAddProvider).retryAmountMl;
  if (amountMl == null) {
    return Future<void>.value();
  }
  return _quickAdd(
    controller: controller,
    feedback: feedback,
    amountMl: amountMl,
    isRetry: true,
  );
}

Future<void> _quickAdd({
  required WaterQuickAddController controller,
  required FeedbackService feedback,
  required int amountMl,
  bool isRetry = false,
}) async {
  try {
    final outcome = isRetry
        ? await controller.retry()
        : await controller.add(amountMl);
    if (outcome != null) {
      feedback.showSaved(waterAddedMessage(amountMl), undo: outcome.undo);
    }
  } on AppFailure catch (failure) {
    feedback.showError(
      waterQuickAddFailureMessage(failure),
      onRetry: failure is StorageFailure
          ? () => _quickAdd(
              controller: controller,
              feedback: feedback,
              amountMl: amountMl,
              isRetry: true,
            )
          : null,
    );
  }
}

/// The latest unresolved quick add failure, visible on the dashboard card and
/// on the water screen until it is retried successfully or dismissed. Nothing
/// was stored, so no amount and no XP changed.
class WaterQuickAddFailureNotice extends ConsumerWidget {
  const WaterQuickAddFailureNotice({this.compact = false, super.key});

  /// Uses the small pill actions of the dashboard card (they can be measured
  /// by the card grid) instead of full buttons.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(waterQuickAddProvider);
    final failure = state.failure;
    if (failure == null) {
      return const SizedBox.shrink();
    }
    final retry = state.canRetry ? () => retryWaterQuickAdd(ref) : null;
    void dismiss() => ref.read(waterQuickAddProvider.notifier).dismissFailure();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NutritionFieldError(text: waterQuickAddFailureMessage(failure)),
          const SizedBox(height: 6),
          if (compact)
            Wrap(
              spacing: 8,
              children: [
                if (retry != null)
                  MetricCardAction(
                    label: 'Erneut versuchen',
                    icon: AppIcon.retry.data,
                    accent: AppAccent.water,
                    onPressed: retry,
                  ),
                MetricCardAction(
                  label: 'Schließen',
                  accent: AppAccent.water,
                  onPressed: dismiss,
                ),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (retry != null)
                  SecondaryButton(
                    label: 'Erneut versuchen',
                    icon: AppIcon.retry.data,
                    expand: false,
                    onPressed: retry,
                  ),
                SecondaryButton(
                  label: 'Schließen',
                  expand: false,
                  onPressed: dismiss,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
