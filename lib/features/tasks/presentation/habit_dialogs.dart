import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/presentation/action_feedback.dart';

/// Asks for confirmation and deletes [habit] with undo. Shared by the detail
/// screen and the edit form. Returns whether the habit was deleted.
Future<bool> confirmAndDeleteHabit(BuildContext context, Habit habit) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final confirmed = await showConfirmationSheet(
    context,
    title: 'Gewohnheit löschen?',
    message:
        '„${habit.title}“ und ihr Verlauf zählen dann nicht mehr. Du kannst '
        'es direkt danach rückgängig machen.',
    confirmLabel: 'Löschen',
  );
  if (!confirmed) {
    return false;
  }
  return deleteHabitWithFeedback(container, habit.id);
}

/// Asks for confirmation and archives [habit] from tomorrow on. Archiving is
/// final: there is no undo, the habit is never reactivated. Returns whether it
/// was archived.
Future<bool> confirmAndArchiveHabit(BuildContext context, Habit habit) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final confirmed = await showConfirmationSheet(
    context,
    title: 'Gewohnheit archivieren?',
    message:
        '„${habit.title}“ zählt ab morgen nicht mehr. Der Verlauf bleibt '
        'erhalten. Das lässt sich nicht rückgängig machen.',
    confirmLabel: 'Archivieren',
    destructive: false,
  );
  if (!confirmed) {
    return false;
  }
  return archiveHabitWithFeedback(container, habit.id);
}
