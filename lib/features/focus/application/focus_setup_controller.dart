import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/application/focus_session_controller.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_timer.dart';

/// Smallest and largest planned duration in minutes (5 and 180).
const int minFocusPlannedMinutes = minFocusPlannedSeconds ~/ 60;
const int maxFocusPlannedMinutes = maxFocusPlannedSeconds ~/ 60;

/// Planned minutes preselected in the setup (25) and the stepper step (5).
const int defaultFocusPlannedMinutes = defaultFocusPlannedSeconds ~/ 60;
const int focusPlannedMinutesStep = focusPlanStepSeconds ~/ 60;

/// State of the focus setup card (category chips, duration stepper).
@immutable
final class FocusSetupState {
  const FocusSetupState({
    required this.category,
    required this.plannedMinutes,
    this.submitting = false,
    this.fieldErrors = const {},
    this.failure,
  });

  /// The selected category (preselected: "Sonstiges").
  final FocusCategory category;

  /// The planned countdown in minutes (5 to 180, default 25).
  final int plannedMinutes;

  /// A start is running; further starts are ignored.
  final bool submitting;

  /// Field key (see `FocusFields`) -> German hint.
  final Map<String, String> fieldErrors;

  /// The failure of the last start (e.g. a session is already open).
  final AppFailure? failure;

  /// The planned countdown in seconds (what the start command takes).
  int get plannedSeconds => plannedMinutes * 60;

  /// Whether the minus button can still reduce the time (above 5 minutes).
  bool get canStepDown => plannedMinutes > minFocusPlannedMinutes;

  /// Whether the plus button can still raise the time (below 180 minutes).
  bool get canStepUp => plannedMinutes < maxFocusPlannedMinutes;

  FocusSetupState copyWith({
    FocusCategory? category,
    int? plannedMinutes,
    bool? submitting,
    Map<String, String>? fieldErrors,
    AppFailure? Function()? failure,
  }) => FocusSetupState(
    category: category ?? this.category,
    plannedMinutes: plannedMinutes ?? this.plannedMinutes,
    submitting: submitting ?? this.submitting,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    failure: failure == null ? this.failure : failure(),
  );
}

/// Controller of the focus setup card: category, planned duration and the
/// start. Starting persists the session first; the countdown screens show the
/// running state from the database afterwards.
class FocusSetupController extends Notifier<FocusSetupState> {
  late SubmissionTracker _tracker;

  @override
  FocusSetupState build() {
    _tracker = SubmissionTracker(ref.read(idGeneratorProvider));
    return const FocusSetupState(
      category: FocusCategory.other,
      plannedMinutes: defaultFocusPlannedMinutes,
    );
  }

  void selectCategory(FocusCategory category) =>
      state = state.copyWith(category: category);

  /// Plus (+1) or minus (-1) button: [focusPlannedMinutesStep] minutes per
  /// step, kept within 5 to 180.
  void stepPlannedMinutes(int direction) => setPlannedMinutes(
    state.plannedMinutes + direction * focusPlannedMinutesStep,
  );

  /// Sets the planned minutes, clamped to 5 to 180.
  void setPlannedMinutes(int minutes) => state = state.copyWith(
    plannedMinutes: minutes.clamp(
      minFocusPlannedMinutes,
      maxFocusPlannedMinutes,
    ),
    fieldErrors: const {},
  );

  /// Starts the session. A start with unchanged choices after a failure reuses
  /// the command id (a retry can never create two sessions). If a session is
  /// already open, the result is a [FocusActionFailed] with
  /// `ConflictFailure(openFocusSession)` whose `relatedEntityId` is the open
  /// session: show it instead of starting a new one.
  Future<FocusActionResult> start() async {
    if (state.submitting) {
      return const FocusActionIgnored();
    }
    final category = state.category;
    final seconds = state.plannedSeconds;
    final commandId = _tracker.idFor((category.key, seconds));
    state = state.copyWith(
      submitting: true,
      fieldErrors: const {},
      failure: () => null,
    );
    try {
      final outcome = await ref
          .read(focusRepositoryProvider)
          .start(
            commandId: commandId,
            category: category,
            plannedSeconds: seconds,
          );
      _tracker.completed();
      state = state.copyWith(submitting: false);
      return FocusActionDone(FocusAction.start, outcome);
    } on ValidationFailure catch (failure) {
      state = state.copyWith(
        submitting: false,
        fieldErrors: failure.fieldErrors,
      );
      return FocusActionFailed(failure);
    } on AppFailure catch (failure) {
      state = state.copyWith(submitting: false, failure: () => failure);
      return FocusActionFailed(failure);
    }
  }
}

/// The setup card state; auto-disposed with its screen.
final focusSetupProvider =
    NotifierProvider.autoDispose<FocusSetupController, FocusSetupState>(
      FocusSetupController.new,
    );
