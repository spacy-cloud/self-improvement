import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/focus_countdown.dart';
import 'package:self_improvement/features/focus/application/focus_restorer.dart';
import 'package:self_improvement/features/focus/data/focus_repository.dart';
import 'package:self_improvement/features/focus/domain/focus_history.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';

final focusRepositoryProvider = Provider<FocusRepository>(
  (ref) => FocusRepository(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
  ),
);

/// The open session (running, paused or awaiting confirmation) straight from
/// the database, or null. Independent of any screen; the Plus menu, the
/// dashboard card and the focus screens all read it, so navigation can never
/// create a second session.
final focusSessionProvider = StreamProvider<FocusSession?>(
  (ref) => ref.watch(focusRepositoryProvider).watchOpen(),
);

/// One active session by id (history detail); emits null when it does not
/// exist (any more).
final focusSessionByIdProvider = StreamProvider.family<FocusSession?, String>(
  (ref, id) => ref.watch(focusRepositoryProvider).watchById(id),
);

/// The source of foreground ticks with a monotonic time reading. Tests
/// override it with a manual source.
final focusTickSourceProvider = Provider<FocusTickSource>(
  (ref) => const StopwatchTickSource(),
);

/// Counts foreground phases. `FocusRestorer.restore` bumps it, which makes the
/// running countdown start a fresh phase from the persisted state (needed
/// after the app was resumed: the monotonic clock may have stopped while the
/// device slept).
class FocusForegroundEpoch extends Notifier<int> {
  @override
  int build() => 0;

  /// Starts a new foreground phase.
  void bump() => state++;
}

final focusForegroundEpochProvider =
    NotifierProvider<FocusForegroundEpoch, int>(FocusForegroundEpoch.new);

/// The live countdown of the open session: about one value per second while it
/// runs (monotonic within a foreground phase, see `FocusCountdownEngine`), one
/// static value while paused or awaiting confirmation, null without an open
/// session.
///
/// When the countdown reaches zero it persists `awaiting_confirmation`
/// exactly once (no XP, no completed record). The provider is auto-disposed,
/// so nothing ticks while no screen shows it; the app shell may keep it alive
/// by listening to it at the root if it wants that transition to happen even
/// without a focus screen. A session that ran out meanwhile is picked up by
/// `FocusRestorer.restore` or by the next listener.
final focusCountdownProvider = StreamProvider.autoDispose<FocusCountdown?>((
  ref,
) {
  final repository = ref.watch(focusRepositoryProvider);
  final ids = ref.watch(idGeneratorProvider);
  final engine = FocusCountdownEngine(
    clock: ref.watch(clockProvider),
    ticker: ref.watch(focusTickSourceProvider),
    onReachedZero: (session) async {
      await repository.markAwaitingConfirmation(
        commandId: ids.newId(),
        id: session.id,
      );
    },
  );
  final rebases = StreamController<void>.broadcast();
  ref.onDispose(() => unawaited(rebases.close()));
  ref.listen<int>(focusForegroundEpochProvider, (_, _) => rebases.add(null));
  return engine.bind(repository.watchOpen(), rebases: rebases.stream);
});

/// Completed sessions, newest first (category, saved duration, end time,
/// status). Discarded and open sessions are not part of the history.
final focusHistoryProvider = StreamProvider<List<FocusHistoryEntry>>((ref) {
  final clock = ref.watch(clockProvider);
  return ref
      .watch(focusRepositoryProvider)
      .watchHistory()
      .map(
        (sessions) => [
          for (final session in sessions)
            FocusHistoryEntry.fromSession(session, clock),
        ],
      );
});

/// The newest [limit] completed sessions (lazy lists load more by raising the
/// limit).
final focusHistoryPageProvider =
    StreamProvider.family<List<FocusHistoryEntry>, int>((ref, limit) {
      final clock = ref.watch(clockProvider);
      return ref
          .watch(focusRepositoryProvider)
          .watchHistory(limit: limit)
          .map(
            (sessions) => [
              for (final session in sessions)
                FocusHistoryEntry.fromSession(session, clock),
            ],
          );
    });

/// The sessions completed today ("Sitzungen heute"), newest first. Follows
/// the calendar day.
final focusSessionsTodayProvider = StreamProvider<List<FocusHistoryEntry>>((
  ref,
) {
  final today = ref.watch(todayProvider);
  final clock = ref.watch(clockProvider);
  return ref
      .watch(focusRepositoryProvider)
      .watchCompletedOn(today)
      .map(
        (sessions) => [
          for (final session in sessions)
            FocusHistoryEntry.fromSession(session, clock),
        ],
      );
});

/// Today's focus time: completed minutes (only SAVED durations count), number
/// of sessions and the progress towards the daily focus goal.
final focusTodaySummaryProvider = Provider<AsyncValue<FocusTodaySummary>>((
  ref,
) {
  final sessions = ref.watch(focusSessionsTodayProvider);
  final versions = ref.watch(goalVersionsProvider);
  final today = ref.watch(todayProvider);
  return sessions.when(
    loading: () => const AsyncLoading(),
    error: AsyncError.new,
    data: (entries) {
      final goalVersions = versions.value;
      if (goalVersions == null) {
        return versions.hasError
            ? AsyncError(versions.error!, versions.stackTrace!)
            : const AsyncLoading();
      }
      return AsyncData(
        buildFocusTodaySummary(
          [for (final entry in entries) entry.session],
          today: today,
          goalMinutes: focusGoalMinutesOn(goalVersions, today),
        ),
      );
    },
  );
});

/// Restores the open session on bootstrap and on every app resume (see
/// `FocusRestorer`).
final focusRestorerProvider = Provider<FocusRestorer>(
  (ref) => FocusRestorer(
    repository: ref.watch(focusRepositoryProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    onRestored: () => ref.read(focusForegroundEpochProvider.notifier).bump(),
  ),
);
