import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/application/nutrition_delete_controller.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_format.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_routes.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_widgets.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Confirms, deletes and reports the deletion of one water entry. Shared by the
/// history rows and the edit screen. Returns true when the entry was deleted.
///
/// The success message with "Rückgängig" (8 s) appears only AFTER the commit; a
/// failure leaves the entry untouched and offers to try again (the same
/// command).
Future<bool> confirmAndDeleteWater(
  BuildContext context,
  WidgetRef ref, {
  required WaterEntry entry,
  required String when,
}) async {
  final feedback = ref.read(feedbackServiceProvider);
  final deleter = ref.read(nutritionDeleteProvider.notifier);
  final confirmed = await showConfirmationSheet(
    context,
    title: 'Eintrag von $when löschen?',
    message:
        '${formatWaterMl(entry.amountMl)} werden entfernt. '
        'Du kannst es direkt danach rückgängig machen.',
    confirmLabel: 'Löschen',
  );
  if (!confirmed) {
    return false;
  }
  return _delete(deleter, feedback, entry.id);
}

Future<bool> _delete(
  NutritionDeleteController deleter,
  FeedbackService feedback,
  String id,
) async {
  final result = await deleter.deleteWater(id);
  switch (result) {
    case EntryDeleted():
      feedback.showSaved(waterDeletedMessage, undo: result.outcome.undo);
      return true;
    case EntryDeleteFailed(:final failure):
      feedback.showError(
        failure is StorageFailure
            ? 'Löschen fehlgeschlagen. Der Eintrag ist unverändert.'
            : failure.userMessage,
        onRetry: failure is StorageFailure
            ? () => _delete(deleter, feedback, id)
            : null,
      );
      return false;
    case EntryDeleteBusy():
      return false;
  }
}

/// The dot in front of a water entry (the water accent; decorative).
class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: context.tokens.colors.moduleWaterChart,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// One entry of the water history: time and amount, tapping opens the edit
/// screen, the trailing button deletes after a confirmation.
class WaterEntryRow extends ConsumerWidget {
  const WaterEntryRow({required this.entry, required this.today, super.key});

  final WaterEntry entry;

  /// "Today" of the screen: entries of earlier days name their date in the
  /// delete question.
  final LocalDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final clock = ref.watch(clockProvider);
    final time = entryTime(clock, entry.occurredAtUtc, entry.timezoneId);
    final when = entry.localDate == today
        ? '$time Uhr'
        : '${formatDayMonth(entry.localDate)}, $time Uhr';
    final amount = formatWaterMl(entry.amountMl);
    final deleting = ref.watch(nutritionDeleteProvider).contains(entry.id);
    return Row(
      children: [
        Expanded(
          child: EntryListTile(
            title: '$time Uhr',
            leading: const _Dot(),
            trailing: Text(
              amount,
              style: AppTextStyles.titleCard.copyWith(
                color: colors.textPrimary,
              ),
            ),
            semanticLabel: '$time Uhr, $amount. Tippen zum Bearbeiten',
            onTap: () => context.push(WaterRoutes.edit(entry.id)),
          ),
        ),
        AppIconButton(
          icon: AppIcon.close.data,
          iconColor: colors.textSecondary,
          semanticLabel: 'Eintrag von $when, $amount, löschen',
          onPressed: deleting
              ? null
              : () => confirmAndDeleteWater(
                  context,
                  ref,
                  entry: entry,
                  when: when,
                ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
