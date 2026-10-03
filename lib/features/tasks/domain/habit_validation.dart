import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/features/tasks/domain/text_rules.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Field keys of the habit form and of a check (keys of
/// [ValidationFailure.fieldErrors]).
abstract final class HabitFields {
  static const String title = 'title';
  static const String icon = 'icon';
  static const String date = 'date';
}

/// Maximum title length in characters.
const int maxHabitTitleLength = 80;

/// How many days back from today a check may be set or removed: today minus 30
/// is still allowed, today minus 31 is not.
const int habitBackfillDays = 30;

/// How many days the history grid of the habit detail shows (today and the 29
/// days before it). All of them lie inside the editable window.
const int habitHistoryDays = 30;

/// The hint shown while a habit is archived but still applies today.
const String habitArchivePendingHint = 'Ab morgen archiviert';

/// Validates [draft] and returns it normalised (trimmed title).
///
/// Throws a [ValidationFailure] with German hints per field. The icon key must
/// be one of the six known keys: an unknown key is rejected, never replaced by
/// the default. The reminder time needs no validation (a [LocalTime] is always
/// a valid wall clock time; null means off).
HabitDraft validateHabitDraft(HabitDraft draft) {
  final errors = <String, String>{};

  final title = draft.title.trim();
  if (title.isEmpty) {
    errors[HabitFields.title] = 'Bitte gib einen Titel ein.';
  } else if (characterCount(title) > maxHabitTitleLength) {
    errors[HabitFields.title] =
        'Der Titel darf höchstens $maxHabitTitleLength Zeichen lang sein.';
  }

  if (HabitIcon.tryParse(draft.iconKey) == null) {
    errors[HabitFields.icon] = 'Bitte wähle ein Symbol aus der Liste.';
  }

  if (errors.isNotEmpty) {
    throw ValidationFailure(errors);
  }
  return HabitDraft(
    title: title,
    iconKey: draft.iconKey,
    reminderTime: draft.reminderTime,
  );
}

/// Why a check on a date is not allowed.
enum HabitCheckDateError {
  /// The date lies after today.
  future,

  /// The date lies before the day the habit was created.
  beforeStart,

  /// The date is the archive date or later: the habit no longer applies.
  archived,

  /// The date is more than 30 days back.
  tooOld;

  /// German hint for the snackbar or the day cell.
  String get message => switch (this) {
    HabitCheckDateError.future =>
      'Für zukünftige Tage kann nichts abgehakt werden.',
    HabitCheckDateError.beforeStart =>
      'Vor dem Start der Gewohnheit kann nichts abgehakt werden.',
    HabitCheckDateError.archived =>
      'Ab dem Archivierungstag kann nichts mehr abgehakt werden.',
    HabitCheckDateError.tooOld =>
      'Rückwirkend sind nur die letzten $habitBackfillDays Tage möglich.',
  };
}

/// Checks whether [habit] may be checked or unchecked on [date], seen from
/// [today]. Returns the first violated rule or null when the date is allowed:
///
/// - not in the future,
/// - not before the habit's start day,
/// - not on or after its archive date,
/// - not more than [habitBackfillDays] days back (the day `today - 30` is the
///   oldest allowed day).
HabitCheckDateError? checkDateError({
  required Habit habit,
  required LocalDate date,
  required LocalDate today,
}) {
  if (date.isAfter(today)) {
    return HabitCheckDateError.future;
  }
  if (date.isBefore(habit.startedOn)) {
    return HabitCheckDateError.beforeStart;
  }
  final archivedFrom = habit.archivedFrom;
  if (archivedFrom != null && !date.isBefore(archivedFrom)) {
    return HabitCheckDateError.archived;
  }
  if (date.isBefore(today.addDays(-habitBackfillDays))) {
    return HabitCheckDateError.tooOld;
  }
  return null;
}

/// Throws a [ValidationFailure] on [HabitFields.date] when [checkDateError]
/// finds a violation.
void validateCheckDate({
  required Habit habit,
  required LocalDate date,
  required LocalDate today,
}) {
  final error = checkDateError(habit: habit, date: date, today: today);
  if (error != null) {
    throw ValidationFailure.field(HabitFields.date, error.message);
  }
}
