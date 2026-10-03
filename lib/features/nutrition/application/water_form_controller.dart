import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/nutrition_rules.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_format.dart';
import 'package:self_improvement/features/nutrition/domain/water_input.dart';
import 'package:self_improvement/features/nutrition/domain/water_validation.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Identifies a water form: new entry (`entry == null`, the "Eigene Menge"
/// state) or editing [entry].
@immutable
final class WaterFormArgs {
  const WaterFormArgs.create() : entry = null;

  const WaterFormArgs.edit(WaterEntry this.entry);

  final WaterEntry? entry;

  @override
  bool operator ==(Object other) =>
      other is WaterFormArgs &&
      other.entry?.id == entry?.id &&
      other.entry?.rowVersion == entry?.rowVersion;

  @override
  int get hashCode => Object.hash(entry?.id, entry?.rowVersion);
}

/// State of the water form. All input stays here when saving fails.
@immutable
final class WaterFormState {
  const WaterFormState({
    required this.amountText,
    required this.date,
    required this.time,
    required this.note,
    required this.dirty,
    this.fieldErrors = const {},
    this.submitting = false,
    this.submitFailure,
  });

  /// What the user typed: whole millilitres (empty at the start of a new
  /// entry, nothing is pre-filled).
  final String amountText;

  /// Date and wall clock time of the drink in the current device zone.
  final LocalDate date;
  final LocalTime time;

  /// Free text; blank is saved as no note.
  final String note;

  /// True once the user changed anything (drives the "Änderungen verwerfen?"
  /// dialog); false again after a successful save.
  final bool dirty;

  /// Field key -> German hint (see `WaterFields`).
  final Map<String, String> fieldErrors;

  /// True while a save is running; further saves are ignored.
  final bool submitting;

  /// A persistent form level failure (storage, stale version, entry gone);
  /// input is kept.
  final AppFailure? submitFailure;

  WaterFormState copyWith({
    String? amountText,
    LocalDate? date,
    LocalTime? time,
    String? note,
    bool? dirty,
    Map<String, String>? fieldErrors,
    bool? submitting,
    AppFailure? Function()? submitFailure,
  }) => WaterFormState(
    amountText: amountText ?? this.amountText,
    date: date ?? this.date,
    time: time ?? this.time,
    note: note ?? this.note,
    dirty: dirty ?? this.dirty,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    submitting: submitting ?? this.submitting,
    submitFailure: submitFailure == null ? this.submitFailure : submitFailure(),
  );
}

/// Outcome of [WaterFormController.submit].
sealed class WaterSubmitResult {
  const WaterSubmitResult();
}

/// Saved. [outcome] carries the undo action for the snackbar.
final class WaterSaved extends WaterSubmitResult {
  const WaterSaved(
    this.outcome, {
    required this.wasEdit,
    required this.amountMl,
  });

  final CommandOutcome outcome;
  final bool wasEdit;

  /// The saved amount in ml.
  final int amountMl;

  /// Success message after the commit (German).
  String get message =>
      wasEdit ? waterUpdatedMessage : waterAddedMessage(amountMl);
}

/// Not saved; the form shows the reason and keeps all input.
final class WaterRejected extends WaterSubmitResult {
  const WaterRejected();
}

/// Controller of the "Eigene Menge" / edit form of a water entry.
///
/// Same pattern as the weight form: strict amount parsing with German hints,
/// date and time in the device zone, field errors, a submit lock against double
/// taps and a command id that is reused for a retry with unchanged content.
class WaterFormController extends Notifier<WaterFormState> {
  WaterFormController(this.args);

  final WaterFormArgs args;

  late SubmissionTracker _tracker;
  DateTime? _originalInstant;
  DateTime? _attemptInstant;
  var _timeTouched = false;

  bool get isEdit => args.entry != null;

  @override
  WaterFormState build() {
    final clock = ref.read(clockProvider);
    // build() runs again after invalidation: reset all per-form bookkeeping.
    _tracker = SubmissionTracker(ref.read(idGeneratorProvider));
    _timeTouched = false;
    _attemptInstant = null;
    final entry = args.entry;
    final local = clock.toLocal(entry?.occurredAtUtc ?? clock.nowUtc());
    _originalInstant = entry?.occurredAtUtc;
    return WaterFormState(
      amountText: entry == null ? '' : '${entry.amountMl}',
      date: local.date,
      time: local.time,
      note: entry?.note ?? '',
      dirty: false,
    );
  }

  void setAmountText(String text) {
    _attemptInstant = null;
    state = state.copyWith(
      amountText: text,
      dirty: true,
      fieldErrors: _without(WaterFields.amount),
    );
  }

  /// Plus (+1) or minus (-1) button: 10 ml per step from the typed amount
  /// (see [stepWaterMl]); an empty field starts at 250 ml.
  void step(int direction) {
    setAmountText(
      '${stepWaterMl(currentText: state.amountText, direction: direction)}',
    );
  }

  void setDate(LocalDate date) {
    _timeTouched = true;
    _attemptInstant = null;
    state = state.copyWith(
      date: date,
      dirty: true,
      fieldErrors: _without(WaterFields.occurredAt),
    );
  }

  void setTime(LocalTime time) {
    _timeTouched = true;
    _attemptInstant = null;
    state = state.copyWith(
      time: time,
      dirty: true,
      fieldErrors: _without(WaterFields.occurredAt),
    );
  }

  void setNote(String value) {
    _attemptInstant = null;
    state = state.copyWith(
      note: value,
      dirty: true,
      fieldErrors: _without(WaterFields.note),
    );
  }

  /// Validates and saves. Ignored while a save is running (double tap).
  Future<WaterSubmitResult> submit() async {
    if (state.submitting) {
      return const WaterRejected();
    }
    final errors = <String, String>{};
    final clock = ref.read(clockProvider);
    final now = clock.nowUtc();

    int? amount;
    switch (parseWaterMl(state.amountText)) {
      case WaterMlParsed(:final ml):
        amount = ml;
      case WaterMlInvalid(:final error):
        errors[WaterFields.amount] = waterMlErrorMessage(error);
    }

    DateTime? occurredAt;
    if (!_timeTouched && _originalInstant != null) {
      // Untouched edit: keep the exact stored instant (seconds included).
      occurredAt = _originalInstant;
    } else if (!_timeTouched) {
      // Untouched new entry: "now" at the moment of saving, frozen for retries
      // of the same content so they reuse the command id.
      occurredAt = _attemptInstant ??= now;
    } else {
      switch (clock.toUtc(state.date, state.time)) {
        case ZonedResolved(:final utc):
          occurredAt = utc;
        case ZonedNonexistent(:final nextValid):
          errors[WaterFields.occurredAt] = dstGapMessage(nextValid);
      }
    }

    // The shared rules (time and note) run here with the same function the
    // repository uses, so all hints appear at once and no command is spent on
    // input that cannot be saved. Stand-ins keep already reported fields quiet.
    try {
      validateWaterDraft(
        WaterDraft(
          amountMl: amount ?? minWaterEntryMl,
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

    if (errors.isNotEmpty || amount == null || occurredAt == null) {
      state = state.copyWith(fieldErrors: errors);
      return const WaterRejected();
    }

    final draft = WaterDraft(
      amountMl: amount,
      occurredAtUtc: occurredAt,
      note: state.note,
    );
    final commandId = _tracker.idFor((
      args.entry?.id,
      draft.amountMl,
      draft.occurredAtUtc,
      draft.note?.trim() ?? '',
    ));

    state = state.copyWith(
      submitting: true,
      fieldErrors: const {},
      submitFailure: () => null,
    );
    final repository = ref.read(waterRepositoryProvider);
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
      return WaterSaved(
        outcome,
        wasEdit: entry != null,
        amountMl: draft.amountMl,
      );
    } on ValidationFailure catch (failure) {
      state = state.copyWith(
        submitting: false,
        fieldErrors: failure.fieldErrors,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(submitting: false, submitFailure: () => failure);
    }
    return const WaterRejected();
  }

  Map<String, String> _without(String field) {
    final copy = Map<String, String>.of(state.fieldErrors)..remove(field);
    return copy;
  }
}

/// Provider of a water form; auto-disposed with its screen.
final waterFormProvider = NotifierProvider.autoDispose
    .family<WaterFormController, WaterFormState, WaterFormArgs>(
      WaterFormController.new,
    );
