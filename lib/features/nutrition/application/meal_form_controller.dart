import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/meal_format.dart';
import 'package:self_improvement/features/nutrition/domain/meal_input.dart';
import 'package:self_improvement/features/nutrition/domain/meal_validation.dart';
import 'package:self_improvement/features/nutrition/domain/nutrition_rules.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Identifies a meal form: new meal (`entry == null`) or editing [entry].
@immutable
final class MealFormArgs {
  const MealFormArgs.create() : entry = null;

  const MealFormArgs.edit(MealEntry this.entry);

  final MealEntry? entry;

  @override
  bool operator ==(Object other) =>
      other is MealFormArgs &&
      other.entry?.id == entry?.id &&
      other.entry?.rowVersion == entry?.rowVersion;

  @override
  int get hashCode => Object.hash(entry?.id, entry?.rowVersion);
}

/// State of the meal form. All input stays here when saving fails.
@immutable
final class MealFormState {
  const MealFormState({
    required this.nameText,
    required this.kcalText,
    required this.date,
    required this.time,
    required this.note,
    required this.dirty,
    this.fieldErrors = const {},
    this.submitting = false,
    this.submitFailure,
  });

  /// The meal name as typed (trimmed on save, 1 to 80 characters).
  final String nameText;

  /// The optional calories as typed: whole kcal 0 to 5000. EMPTY means "not
  /// given" (no calorie value is saved), `0` is a deliberate zero.
  final String kcalText;

  /// Date and wall clock time of the meal in the current device zone.
  final LocalDate date;
  final LocalTime time;

  /// Free text; blank is saved as no note.
  final String note;

  /// True once the user changed anything (drives the "Änderungen verwerfen?"
  /// dialog); false again after a successful save.
  final bool dirty;

  /// Field key -> German hint (see `MealFields`).
  final Map<String, String> fieldErrors;

  /// True while a save is running; further saves are ignored.
  final bool submitting;

  /// A persistent form level failure (storage, stale version, meal gone);
  /// input is kept.
  final AppFailure? submitFailure;

  MealFormState copyWith({
    String? nameText,
    String? kcalText,
    LocalDate? date,
    LocalTime? time,
    String? note,
    bool? dirty,
    Map<String, String>? fieldErrors,
    bool? submitting,
    AppFailure? Function()? submitFailure,
  }) => MealFormState(
    nameText: nameText ?? this.nameText,
    kcalText: kcalText ?? this.kcalText,
    date: date ?? this.date,
    time: time ?? this.time,
    note: note ?? this.note,
    dirty: dirty ?? this.dirty,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    submitting: submitting ?? this.submitting,
    submitFailure: submitFailure == null ? this.submitFailure : submitFailure(),
  );
}

/// Outcome of [MealFormController.submit].
sealed class MealSubmitResult {
  const MealSubmitResult();
}

/// Saved. [outcome] carries the undo action for the snackbar.
final class MealSaved extends MealSubmitResult {
  const MealSaved(this.outcome, {required this.wasEdit});

  final CommandOutcome outcome;
  final bool wasEdit;

  /// Success message after the commit (German).
  String get message => wasEdit ? mealUpdatedMessage : mealSavedMessage;
}

/// Not saved; the form shows the reason and keeps all input.
final class MealRejected extends MealSubmitResult {
  const MealRejected();
}

/// Controller of the new/edit meal form.
///
/// Same pattern as the weight form: strict parsing with German hints, date and
/// time in the device zone, field errors, a submit lock against double taps and
/// a command id that is reused for a retry with unchanged content. The
/// calorie field is optional: empty saves "not given", never 0.
class MealFormController extends Notifier<MealFormState> {
  MealFormController(this.args);

  final MealFormArgs args;

  late SubmissionTracker _tracker;
  DateTime? _originalInstant;
  DateTime? _attemptInstant;
  var _timeTouched = false;

  bool get isEdit => args.entry != null;

  @override
  MealFormState build() {
    final clock = ref.read(clockProvider);
    // build() runs again after invalidation: reset all per-form bookkeeping.
    _tracker = SubmissionTracker(ref.read(idGeneratorProvider));
    _timeTouched = false;
    _attemptInstant = null;
    final entry = args.entry;
    final local = clock.toLocal(entry?.occurredAtUtc ?? clock.nowUtc());
    _originalInstant = entry?.occurredAtUtc;
    return MealFormState(
      nameText: entry?.name ?? '',
      kcalText: entry?.kcal?.toString() ?? '',
      date: local.date,
      time: local.time,
      note: entry?.note ?? '',
      dirty: false,
    );
  }

  void setName(String text) {
    _attemptInstant = null;
    state = state.copyWith(
      nameText: text,
      dirty: true,
      fieldErrors: _without(MealFields.name),
    );
  }

  void setKcalText(String text) {
    _attemptInstant = null;
    state = state.copyWith(
      kcalText: text,
      dirty: true,
      fieldErrors: _without(MealFields.kcal),
    );
  }

  void setDate(LocalDate date) {
    _timeTouched = true;
    _attemptInstant = null;
    state = state.copyWith(
      date: date,
      dirty: true,
      fieldErrors: _without(MealFields.occurredAt),
    );
  }

  void setTime(LocalTime time) {
    _timeTouched = true;
    _attemptInstant = null;
    state = state.copyWith(
      time: time,
      dirty: true,
      fieldErrors: _without(MealFields.occurredAt),
    );
  }

  void setNote(String value) {
    _attemptInstant = null;
    state = state.copyWith(
      note: value,
      dirty: true,
      fieldErrors: _without(MealFields.note),
    );
  }

  /// Validates and saves. Ignored while a save is running (double tap).
  Future<MealSubmitResult> submit() async {
    if (state.submitting) {
      return const MealRejected();
    }
    final errors = <String, String>{};
    final clock = ref.read(clockProvider);
    final now = clock.nowUtc();

    int? kcal;
    switch (parseKcal(state.kcalText)) {
      case KcalParsed(kcal: final parsed):
        kcal = parsed;
      case KcalInvalid(:final error):
        errors[MealFields.kcal] = kcalErrorMessage(error);
    }

    DateTime? occurredAt;
    if (!_timeTouched && _originalInstant != null) {
      // Untouched edit: keep the exact stored instant (seconds included).
      occurredAt = _originalInstant;
    } else if (!_timeTouched) {
      // Untouched new meal: "now" at the moment of saving, frozen for retries
      // of the same content so they reuse the command id.
      occurredAt = _attemptInstant ??= now;
    } else {
      switch (clock.toUtc(state.date, state.time)) {
        case ZonedResolved(:final utc):
          occurredAt = utc;
        case ZonedNonexistent(:final nextValid):
          errors[MealFields.occurredAt] = dstGapMessage(nextValid);
      }
    }

    // The shared rules (name, time, note) run here with the same function the
    // repository uses, so all hints appear at once and no command is spent on
    // input that cannot be saved. The calorie text was checked while parsing;
    // a stand-in time keeps an already reported time error quiet.
    try {
      validateMealDraft(
        MealDraft(
          name: state.nameText,
          kcal: kcal,
          occurredAtUtc: occurredAt ?? now,
          note: state.note,
        ),
        nowUtc: now,
        clock: clock,
      );
    } on ValidationFailure catch (failure) {
      for (final entry in failure.fieldErrors.entries) {
        errors.putIfAbsent(entry.key, () => entry.value);
      }
    }

    if (errors.isNotEmpty || occurredAt == null) {
      state = state.copyWith(fieldErrors: errors);
      return const MealRejected();
    }

    final draft = MealDraft(
      name: state.nameText,
      kcal: kcal,
      occurredAtUtc: occurredAt,
      note: state.note,
    );
    final commandId = _tracker.idFor((
      args.entry?.id,
      draft.name.trim(),
      draft.kcal,
      draft.occurredAtUtc,
      draft.note?.trim() ?? '',
    ));

    state = state.copyWith(
      submitting: true,
      fieldErrors: const {},
      submitFailure: () => null,
    );
    final repository = ref.read(mealRepositoryProvider);
    try {
      final entry = args.entry;
      final outcome = entry == null
          ? await repository.create(commandId: commandId, draft: draft)
          : await repository.update(
              commandId: commandId,
              id: entry.id,
              draft: draft,
              expectedRowVersion: entry.rowVersion,
            );
      _tracker.completed();
      _attemptInstant = null;
      state = state.copyWith(submitting: false, dirty: false);
      return MealSaved(outcome, wasEdit: entry != null);
    } on ValidationFailure catch (failure) {
      state = state.copyWith(
        submitting: false,
        fieldErrors: failure.fieldErrors,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(submitting: false, submitFailure: () => failure);
    }
    return const MealRejected();
  }

  Map<String, String> _without(String field) {
    final copy = Map<String, String>.of(state.fieldErrors)..remove(field);
    return copy;
  }
}

/// Provider of a meal form; auto-disposed with its screen.
final mealFormProvider = NotifierProvider.autoDispose
    .family<MealFormController, MealFormState, MealFormArgs>(
      MealFormController.new,
    );
