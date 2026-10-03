import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_tags.dart';
import 'package:self_improvement/features/tasks/domain/text_rules.dart';
import 'package:self_improvement/shared/number_format.dart';

/// Field keys of the task form (keys of [ValidationFailure.fieldErrors]).
abstract final class TaskFields {
  static const String title = 'title';
  static const String description = 'description';
  static const String dueDate = 'dueDate';
  static const String tags = 'tags';
}

/// Maximum title length in characters.
const int maxTaskTitleLength = 120;

/// Maximum description length in characters.
const int maxTaskDescriptionLength = 1000;

/// Validates [draft] and returns it normalised: trimmed title, a blank
/// description stored as null, tags trimmed and deduplicated case-insensitively
/// (first spelling kept).
///
/// Throws a [ValidationFailure] with German hints per field (all errors at
/// once). Lengths are counted in characters (Unicode code points), exactly like
/// the database constraints. The priority is an enum and therefore always valid;
/// the due date is any calendar day (a past day makes the task overdue
/// immediately, which is allowed).
TaskDraft validateTaskDraft(TaskDraft draft) {
  final errors = <String, String>{};

  final title = draft.title.trim();
  if (title.isEmpty) {
    errors[TaskFields.title] = 'Bitte gib einen Titel ein.';
  } else if (characterCount(title) > maxTaskTitleLength) {
    errors[TaskFields.title] =
        'Der Titel darf höchstens $maxTaskTitleLength Zeichen lang sein.';
  }

  final rawDescription = draft.description?.trim();
  if (rawDescription != null &&
      characterCount(rawDescription) > maxTaskDescriptionLength) {
    errors[TaskFields.description] =
        'Die Beschreibung darf höchstens '
        '${formatThousands(maxTaskDescriptionLength)} Zeichen lang sein.';
  }

  final tags = normalizeTags(draft.tags);
  if (tags.length > maxTagsPerTask) {
    errors[TaskFields.tags] =
        'Du kannst höchstens $maxTagsPerTask Tags vergeben.';
  } else if (tags.any((tag) => characterCount(tag) > maxTagLength)) {
    errors[TaskFields.tags] =
        'Ein Tag darf höchstens $maxTagLength Zeichen lang sein.';
  }

  if (errors.isNotEmpty) {
    throw ValidationFailure(errors);
  }
  return TaskDraft(
    title: title,
    description: (rawDescription == null || rawDescription.isEmpty)
        ? null
        : rawDescription,
    priority: draft.priority,
    dueDate: draft.dueDate,
    tags: tags,
  );
}
