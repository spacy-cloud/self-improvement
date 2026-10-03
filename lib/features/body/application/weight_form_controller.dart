import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/attempt_clock.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/domain/weight_input.dart';
import 'package:self_improvement/features/body/domain/weight_validation.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';
import 'package:self_improvement/shared/number_format.dart';

/// Identifies a weight form: new entry (`entry == null`) or editing [entry].
@immutable
final class WeightFormArgs {
  const WeightFormArgs.create() : entry = null;

  const WeightFormArgs.edit(WeightEntry this.entry);

  final WeightEntry? entry;

  @override
  bool operator ==(Object other) =>
      other is WeightFormArgs &&
      other.entry?.id == entry?.id &&
      other.entry?.rowVersion == entry?.rowVersion;

  @override
  int get hashCode => Object.hash(entry?.id, entry?.rowVersion);
}

/// State of the weight form. All input stays here when saving fails.
@immutable
final class WeightFormState {
  const WeightFormState({
    required this.weightText,
    required this.date,
    required this.time,
    required this.beforeToilet,
    required this.afterDrinking,
    required this.afterEating,
    required this.note,
    required this.dirty,
    this.suggestionGrams,
    this.fieldErrors = const {},
    this.submitting = false,
    this.submitFailure,
    this.duplicateOfId,
  });

  /// What the user typed (comma or period).
  final String weightText;

  /// The last known weight as an UNCONFIRMED suggestion (shown as a hint, never
  /// saved unless the user accepts it). Null without history.
  final int? suggestionGrams;

  /// Measurement date and wall clock time in the current device zone.
  final LocalDate date;
  final LocalTime time;

  final bool beforeToilet;
  final bool afterDrinking;
  final bool afterEating;
  final String note;

  /// True once the user changed anything (drives the "Änderungen verwerfen?"
  /// dialog).
  final bool dirty;

  /// Field key -> German hint (see `WeightFields`).
  final Map<String, String> fieldErrors;

  /// True while a save is running; further saves are ignored.
  final bool submitting;

  /// A persistent form level failure (e.g. storage); input is kept.
  final AppFailure? submitFailure;

  /// Set when a measurement with exactly this time exists: offer to edit it.
  final String? duplicateOfId;

  WeightFormState copyWith({
    String? weightText,
    LocalDate? date,
    LocalTime? time,
    bool? beforeToilet,
    bool? afterDrinking,
    bool? afterEating,
    String? note,
    bool? dirty,
    Map<String, String>? fieldErrors,
    bool? submitting,
    int? Function()? suggestionGrams,
    AppFailure? Function()? submitFailure,
    String? Function()? duplicateOfId,
  }) => WeightFormState(
    weightText: weightText ?? this.weightText,
    suggestionGrams: suggestionGrams == null
        ? this.suggestionGrams
        : suggestionGrams(),
    date: date ?? this.date,
    time: time ?? this.time,
    beforeToilet: beforeToilet ?? this.beforeToilet,
    afterDrinking: afterDrinking ?? this.afterDrinking,
    afterEating: afterEating ?? this.afterEating,
    note: note ?? this.note,
    dirty: dirty ?? this.dirty,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    submitting: submitting ?? this.submitting,
    submitFailure: submitFailure == null ? this.submitFailure : submitFailure(),
    duplicateOfId: duplicateOfId == null ? this.duplicateOfId : duplicateOfId(),
  );
}

/// Outcome of [WeightFormController.submit].
sealed class WeightSubmitResult {
  const WeightSubmitResult();
}

/// Saved. [outcome] carries the undo action for the snackbar.
final class WeightSaved extends WeightSubmitResult {
  const WeightSaved(this.outcome, {required this.wasEdit});

  final CommandOutcome outcome;
  final bool wasEdit;

  /// Success message after the commit.
  String get message =>
      wasEdit ? 'Gewicht aktualisiert' : 'Gewicht gespeichert';
}

/// Not saved; the form shows the reason and keeps all input.
final class WeightRejected extends WeightSubmitResult {
  const WeightRejected();
}

/// Outcome of [WeightFormController.deleteEntry].
sealed class WeightDeleteResult {
  const WeightDeleteResult();
}

/// Deleted. [outcome] carries the undo action that restores the same id.
final class WeightDeleted extends WeightDeleteResult {
  const WeightDeleted(this.outcome);

  final CommandOutcome outcome;

  /// Success message after the commit.
  String get message => 'Messung gelöscht';
}

/// Ignored because a save or delete is already running (double tap).
final class WeightDeleteBusy extends WeightDeleteResult {
  const WeightDeleteBusy();
}

/// Not deleted (for example the entry vanished or the database failed).
final class WeightDeleteFailed extends WeightDeleteResult {
  const WeightDeleteFailed(this.failure);

  final AppFailure failure;
}

/// Controller of the new/edit weight form.
class WeightFormController extends Notifier<WeightFormState> {
  WeightFormController(this.args);

  final WeightFormArgs args;

  late SubmissionTracker _tracker;
  final AttemptClock _attempt = AttemptClock();
  DateTime? _originalInstant;
  var _timeTouched = false;

  bool get isEdit => args.entry != null;

  @override
  WeightFormState build() {
    final clock = ref.read(clockProvider);
    // build() runs again after invalidation: reset all per-form bookkeeping.
    _tracker = SubmissionTracker(ref.read(idGeneratorProvider));
    _timeTouched = false;
    _attempt.reset();
    final entry = args.entry;
    final local = clock.toLocal(entry?.occurredAtUtc ?? clock.nowUtc());
    _originalInstant = entry?.occurredAtUtc;
    final latest = ref.read(weightEntriesProvider).value;
    if (entry == null) {
      // The history may still be loading when the form opens (for example
      // when the dashboard card is hidden): offer the last value as soon as
      // it arrives, without touching what the user typed meanwhile.
      ref.listen(weightEntriesProvider, (previous, next) {
        final loaded = next.value;
        if (loaded == null || loaded.isEmpty || state.suggestionGrams != null) {
          return;
        }
        state = state.copyWith(suggestionGrams: () => loaded.first.weightGrams);
      });
    }
    return WeightFormState(
      weightText: entry == null ? '' : formatKilograms(entry.weightGrams),
      suggestionGrams: entry == null && latest != null && latest.isNotEmpty
          ? latest.first.weightGrams
          : null,
      date: local.date,
      time: local.time,
      beforeToilet: entry?.beforeToilet ?? false,
      afterDrinking: entry?.afterDrinking ?? false,
      afterEating: entry?.afterEating ?? false,
      note: entry?.note ?? '',
      dirty: false,
    );
  }

  void setWeightText(String text) => state = state.copyWith(
    weightText: text,
    dirty: true,
    fieldErrors: _without(WeightFields.weight),
    duplicateOfId: () => null,
  );

  /// Plus (+1) or minus (-1) button: 0,1 kg per step, starting from the typed
  /// value or the suggestion.
  void step(int direction) {
    final grams = stepWeightGrams(
      currentText: state.weightText,
      direction: direction,
      fallbackGrams: state.suggestionGrams,
    );
    if (grams != null) {
      setWeightText(formatKilograms(grams));
    }
  }

  /// Explicit confirmation of the unconfirmed suggestion.
  void acceptSuggestion() {
    final suggestion = state.suggestionGrams;
    if (suggestion != null) {
      setWeightText(formatKilograms(suggestion));
    }
  }

  void setDate(LocalDate date) {
    _timeTouched = true;
    state = state.copyWith(
      date: date,
      dirty: true,
      fieldErrors: _without(WeightFields.measuredAt),
      duplicateOfId: () => null,
    );
  }

  void setTime(LocalTime time) {
    _timeTouched = true;
    state = state.copyWith(
      time: time,
      dirty: true,
      fieldErrors: _without(WeightFields.measuredAt),
      duplicateOfId: () => null,
    );
  }

  void setBeforeToilet(bool value) =>
      state = state.copyWith(beforeToilet: value, dirty: true);

  void setAfterDrinking(bool value) =>
      state = state.copyWith(afterDrinking: value, dirty: true);

  void setAfterEating(bool value) =>
      state = state.copyWith(afterEating: value, dirty: true);

  void setNote(String value) => state = state.copyWith(
    note: value,
    dirty: true,
    fieldErrors: _without(WeightFields.note),
  );

  /// Validates and saves. Ignored while a save is running (double tap).
  Future<WeightSubmitResult> submit() async {
    if (state.submitting) {
      return const WeightRejected();
    }
    final errors = <String, String>{};

    int? grams;
    switch (parseWeightKg(state.weightText)) {
      case WeightKgParsed(grams: final parsedGrams):
        grams = parsedGrams;
      case WeightKgInvalid(:final error):
        errors[WeightFields.weight] = weightKgErrorMessage(error);
    }

    final clock = ref.read(clockProvider);
    DateTime? occurredAt;
    if (!_timeTouched && _originalInstant != null) {
      occurredAt = _originalInstant;
    } else if (!_timeTouched && !isEdit) {
      // Untouched new entry: "now" at the moment of saving (not form open),
      // frozen for retries of the same content so they reuse the command id.
      occurredAt = _attempt.instantFor((
        grams,
        state.beforeToilet,
        state.afterDrinking,
        state.afterEating,
        state.note.trim(),
      ), clock.nowUtc);
    } else {
      switch (clock.toUtc(state.date, state.time)) {
        case ZonedResolved(:final utc):
          occurredAt = utc;
        case ZonedNonexistent(:final nextValid):
          errors[WeightFields.measuredAt] =
              'Diese Uhrzeit gibt es wegen der Zeitumstellung nicht. '
              'Bitte wähle ${nextValid.toIso()} Uhr oder später.';
      }
    }

    if (errors.isNotEmpty || grams == null || occurredAt == null) {
      state = state.copyWith(fieldErrors: errors);
      return const WeightRejected();
    }

    final draft = WeightDraft(
      weightGrams: grams,
      occurredAtUtc: occurredAt,
      beforeToilet: state.beforeToilet,
      afterDrinking: state.afterDrinking,
      afterEating: state.afterEating,
      note: state.note,
    );
    final commandId = _tracker.idFor((
      args.entry?.id,
      draft.weightGrams,
      draft.occurredAtUtc,
      draft.beforeToilet,
      draft.afterDrinking,
      draft.afterEating,
      draft.note?.trim() ?? '',
    ));

    state = state.copyWith(
      submitting: true,
      fieldErrors: const {},
      submitFailure: () => null,
      duplicateOfId: () => null,
    );
    final repository = ref.read(weightRepositoryProvider);
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
      _attempt.reset();
      if (ref.mounted) {
        state = state.copyWith(submitting: false, dirty: false);
      }
      return WeightSaved(outcome, wasEdit: entry != null);
    } on ValidationFailure catch (failure) {
      if (ref.mounted) {
        state = state.copyWith(
          submitting: false,
          fieldErrors: failure.fieldErrors,
        );
      }
    } on ConflictFailure catch (failure) {
      if (!ref.mounted) {
        return const WeightRejected();
      }
      state = state.copyWith(
        submitting: false,
        duplicateOfId: failure.kind == ConflictKind.duplicateMeasurement
            ? () => failure.relatedEntityId
            : null,
        submitFailure: () => failure,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(submitting: false, submitFailure: () => failure);
    }
    return const WeightRejected();
  }

  /// Deletes the edited measurement (soft delete with an undo that restores
  /// the same id). Only valid in edit mode; the UI asks for confirmation first.
  Future<WeightDeleteResult> deleteEntry() async {
    final entry = args.entry;
    if (entry == null) {
      throw StateError('Only an existing measurement can be deleted');
    }
    if (state.submitting) {
      return const WeightDeleteBusy();
    }
    final commandId = _tracker.idFor(('delete', entry.id));
    state = state.copyWith(submitting: true, submitFailure: () => null);
    try {
      final outcome = await ref
          .read(weightRepositoryProvider)
          .delete(commandId: commandId, id: entry.id);
      _tracker.completed();
      if (ref.mounted) {
        state = state.copyWith(submitting: false, dirty: false);
      }
      return WeightDeleted(outcome);
    } on AppFailure catch (failure) {
      if (ref.mounted) {
        state = state.copyWith(submitting: false, submitFailure: () => failure);
      }
      return WeightDeleteFailed(failure);
    }
  }

  Map<String, String> _without(String field) {
    final copy = Map<String, String>.of(state.fieldErrors)..remove(field);
    return copy;
  }
}

/// Provider of a weight form; auto-disposed with its screen.
final weightFormProvider = NotifierProvider.autoDispose
    .family<WeightFormController, WeightFormState, WeightFormArgs>(
      WeightFormController.new,
    );
