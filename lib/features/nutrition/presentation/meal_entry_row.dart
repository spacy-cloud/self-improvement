import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/application/nutrition_delete_controller.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/meal_format.dart';
import 'package:self_improvement/features/nutrition/presentation/meal_labels.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_routes.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_widgets.dart';

/// Confirms, deletes and reports the deletion of one meal. Shared by the list
/// rows and the edit screen. Returns true when the meal was deleted.
///
/// The success message with "Rückgängig" (8 s) appears only AFTER the commit; a
/// failure leaves the meal untouched and offers to try again (the same
/// command).
Future<bool> confirmAndDeleteMeal(
  BuildContext context,
  WidgetRef ref, {
  required MealEntry meal,
}) async {
  final feedback = ref.read(feedbackServiceProvider);
  final deleter = ref.read(nutritionDeleteProvider.notifier);
  final confirmed = await showConfirmationSheet(
    context,
    title: 'Mahlzeit „${meal.name}“ löschen?',
    message:
        'Die Mahlzeit wird entfernt. '
        'Du kannst es direkt danach rückgängig machen.',
    confirmLabel: 'Löschen',
  );
  if (!confirmed) {
    return false;
  }
  return _delete(deleter, feedback, meal.id);
}

Future<bool> _delete(
  NutritionDeleteController deleter,
  FeedbackService feedback,
  String id,
) async {
  final result = await deleter.deleteMeal(id);
  switch (result) {
    case EntryDeleted():
      feedback.showSaved(mealDeletedMessage, undo: result.outcome.undo);
      return true;
    case EntryDeleteFailed(:final failure):
      feedback.showError(
        failure is StorageFailure
            ? 'Löschen fehlgeschlagen. Die Mahlzeit ist unverändert.'
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

/// What the actions sheet of a meal can ask for.
enum MealAction { edit, delete }

/// The "more" menu of a meal as a sheet with its own close button: edit or
/// delete. Returns null when it was closed.
Future<MealAction?> showMealActionsSheet(BuildContext context, String name) {
  return showFormSheet<MealAction>(
    context,
    builder: (sheetContext) => FormSheetFrame(
      title: name,
      onClose: () => Navigator.of(sheetContext).pop(),
      child: AppListGroup(
        children: [
          EntryListTile.chevron(
            title: 'Bearbeiten',
            icon: AppIcon.edit.data,
            accent: AppAccent.nutrition,
            onTap: () => Navigator.of(sheetContext).pop(MealAction.edit),
          ),
          EntryListTile.chevron(
            title: 'Löschen',
            icon: AppIcon.delete.data,
            accent: AppAccent.nutrition,
            destructive: true,
            onTap: () => Navigator.of(sheetContext).pop(MealAction.delete),
          ),
        ],
      ),
    ),
  );
}

/// One meal in a list: name, time and the calories (or "Keine Angabe"). Tapping
/// opens the edit screen; the trailing menu offers edit and delete.
class MealEntryRow extends ConsumerWidget {
  const MealEntryRow({required this.meal, super.key});

  final MealEntry meal;

  Future<void> _openMenu(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final action = await showMealActionsSheet(context, meal.name);
    if (!context.mounted) {
      return;
    }
    switch (action) {
      case MealAction.edit:
        unawaited(router.push(NutritionRoutes.edit(meal.id)));
      case MealAction.delete:
        await confirmAndDeleteMeal(context, ref, meal: meal);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final clock = ref.watch(clockProvider);
    final time = entryTime(clock, meal.occurredAtUtc, meal.timezoneId);
    final deleting = ref.watch(nutritionDeleteProvider).contains(meal.id);
    return Row(
      children: [
        Expanded(
          child: EntryListTile(
            title: meal.name,
            subtitle: '$time Uhr',
            trailing: Text(
              mealKcalText(meal),
              style: meal.hasKcal
                  ? AppTextStyles.titleCard.copyWith(color: colors.textPrimary)
                  : AppTextStyles.bodyRegular.copyWith(
                      color: colors.textSecondary,
                    ),
            ),
            semanticLabel:
                '${meal.name}, $time Uhr, ${mealKcalSpoken(meal)}. '
                'Tippen zum Bearbeiten',
            onTap: () => context.push(NutritionRoutes.edit(meal.id)),
          ),
        ),
        AppIconButton(
          icon: Icons.more_vert_rounded,
          iconColor: colors.textSecondary,
          semanticLabel: 'Aktionen für ${meal.name}',
          onPressed: deleting ? null : () => _openMenu(context, ref),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
