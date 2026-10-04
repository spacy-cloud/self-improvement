import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/meal_input.dart';
import 'package:self_improvement/features/nutrition/domain/nutrition_rules.dart';

/// Field keys of the meal form (keys of [ValidationFailure.fieldErrors]).
abstract final class MealFields {
  static const String name = 'name';
  static const String kcal = 'kcal';
  static const String occurredAt = 'occurredAt';
  static const String note = 'note';
}

/// German hint: the name is empty after trimming.
const String mealNameEmptyMessage = 'Bitte gib einen Namen ein.';

/// German hint: the name is longer than [maxMealNameLength].
const String mealNameTooLongMessage =
    'Der Name darf höchstens $maxMealNameLength Zeichen lang sein.';

/// Validates a meal draft and returns it normalised (trimmed name, trimmed
/// note, blank note is none). Throws a [ValidationFailure] with ALL field
/// errors:
///
/// - name: 1 to 80 characters after trimming;
/// - kcal: null ("not given") or an integer 0 to 5000;
/// - time: not after [nowUtc], not before 2000-01-01 in the device zone;
/// - note: at most 500 characters after trimming.
MealDraft validateMealDraft(
  MealDraft draft, {
  required DateTime nowUtc,
  required ClockService clock,
}) {
  final errors = <String, String>{};

  final name = draft.name.trim();
  if (name.isEmpty) {
    errors[MealFields.name] = mealNameEmptyMessage;
  } else if (characterCount(name) > maxMealNameLength) {
    errors[MealFields.name] = mealNameTooLongMessage;
  }

  final kcal = draft.kcal;
  if (kcal != null && (kcal < minMealKcal || kcal > maxMealKcal)) {
    errors[MealFields.kcal] = mealKcalRangeMessage;
  }

  final timeError = eventTimeError(
    occurredAtUtc: draft.occurredAtUtc,
    nowUtc: nowUtc,
    clock: clock,
  );
  if (timeError != null) {
    errors[MealFields.occurredAt] = timeError;
  }

  final note = normalizeNote(draft.note);
  if (note.error != null) {
    errors[MealFields.note] = note.error!;
  }

  if (errors.isNotEmpty) {
    throw ValidationFailure(errors);
  }
  return MealDraft(
    name: name,
    kcal: kcal,
    occurredAtUtc: draft.occurredAtUtc,
    note: note.note,
  );
}
