import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/features/focus/application/focus_countdown.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/application/focus_session_controller.dart';
import 'package:self_improvement/features/focus/application/focus_ui_providers.dart';
import 'package:self_improvement/features/focus/domain/focus_formatting.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/features/focus/domain/focus_timer.dart';
import 'package:self_improvement/features/focus/presentation/focus_end_sheet.dart';
import 'package:self_improvement/features/focus/presentation/focus_labels.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';
import 'package:self_improvement/features/focus/presentation/focus_timer_widgets.dart';
import 'package:self_improvement/features/focus/presentation/focus_widgets.dart';

/// The open session: the countdown while it runs, the pause, and the
/// confirmation once the planned time is over.
///
/// The screen only SHOWS the persisted session (`focusCountdownProvider`); it
/// never owns the timer. Leaving the screen, switching tabs or closing the app
/// does not touch the session. Everything the user does here is one command:
/// pause, resume, end early (save or discard), save and discard.
class FocusSessionScreen extends ConsumerStatefulWidget {
  const FocusSessionScreen({super.key});

  @override
  ConsumerState<FocusSessionScreen> createState() => _FocusSessionScreenState();
}

class _FocusSessionScreenState extends ConsumerState<FocusSessionScreen>
    with WidgetsBindingObserver {
  /// Set once the session was saved or discarded here. The screen then keeps
  /// showing its last state while it closes instead of flashing "no session".
  var _leaving = false;
  FocusCountdown? _lastCountdown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_restore());
    }
  }

  /// A resumed app starts a fresh foreground phase from the persisted session
  /// (the monotonic clock may have stopped while the device slept) and turns a
  /// session that ran out meanwhile into "awaiting confirmation". The app shell
  /// does the same; the call is idempotent.
  Future<void> _restore() async {
    try {
      await ref.read(focusRestorerProvider).restore();
    } on AppFailure {
      // The stream of the open session reports storage problems itself.
    }
  }

  FocusSessionController get _controller =>
      ref.read(focusSessionControllerProvider.notifier);

  void _leave(GoRouter router) {
    setState(() => _leaving = true);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
  }

  /// Runs one action. A success message with undo is shown after the commit
  /// ([showResult]); a failure keeps the session untouched and offers a retry
  /// that reuses the command id.
  Future<void> _run(
    Future<FocusActionResult> Function() action, {
    required String failureMessage,
    bool showResult = false,
    bool leaves = false,
  }) async {
    if (!mounted) {
      return;
    }
    final feedback = ref.read(feedbackServiceProvider);
    final router = GoRouter.of(context);
    final result = await action();
    switch (result) {
      case FocusActionDone():
        if (showResult) {
          feedback.showSaved(result.message, undo: result.undo);
        }
        if (leaves && mounted) {
          _leave(router);
        }
      case FocusActionFailed(:final failure):
        if (failure is StorageFailure) {
          feedback.showError(
            failureMessage,
            onRetry: () => unawaited(
              _run(
                action,
                failureMessage: failureMessage,
                showResult: showResult,
                leaves: leaves,
              ),
            ),
          );
        } else {
          feedback.showError(failure.userMessage);
        }
      case FocusActionIgnored():
        break;
    }
  }

  Future<void> _pause(String id) => _run(
    () => _controller.pause(id),
    failureMessage: 'Pausieren fehlgeschlagen. Die Sitzung läuft weiter.',
  );

  Future<void> _resume(String id) => _run(
    () => _controller.resume(id),
    failureMessage: 'Fortsetzen fehlgeschlagen. Die Sitzung bleibt pausiert.',
  );

  Future<void> _save(String id) => _run(
    () => _controller.save(id),
    failureMessage: 'Speichern fehlgeschlagen. Deine Sitzung bleibt erhalten.',
    showResult: true,
    leaves: true,
  );

  Future<void> _discard(String id) => _run(
    () => _controller.discard(id),
    failureMessage: 'Verwerfen fehlgeschlagen. Die Sitzung bleibt unverändert.',
    showResult: true,
    leaves: true,
  );

  /// "Verwerfen" of the confirmation screen: asks first, the time is lost.
  Future<void> _confirmDiscard(String id) async {
    final confirmed = await showConfirmationSheet(
      context,
      title: 'Sitzung verwerfen?',
      message:
          'Die Zeit dieser Sitzung wird nicht gespeichert. Du kannst das '
          'direkt danach rückgängig machen.',
      confirmLabel: 'Verwerfen',
    );
    if (confirmed && mounted) {
      await _discard(id);
    }
  }

  /// "Beenden": shows the time so far and asks whether to save or discard.
  Future<void> _end(FocusCountdown countdown) async {
    final elapsed = countdown.elapsedSeconds;
    final canSave = elapsed >= minFocusSavedSeconds;
    final xp = focusXpText(ref.read(focusXpOutcomeProvider(elapsed)));
    final choice = await showFocusEndSheet(
      context,
      message: canSave
          ? 'Bisher ${formatCountdown(elapsed)} von ${countdown.plannedText}. '
                'Du kannst die Zeit speichern oder die Sitzung verwerfen.'
          : focusTooShortMessage,
      hint: canSave ? xp : null,
      canSave: canSave,
    );
    if (choice == null || !mounted) {
      return;
    }
    switch (choice) {
      case FocusEndChoice.save:
        await _save(countdown.session.id);
      case FocusEndChoice.discard:
        await _discard(countdown.session.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(focusCountdownProvider);
    final busy = ref.watch(
      focusSessionControllerProvider.select((state) => state.busy),
    );
    var countdown = async.value;
    if (countdown != null) {
      _lastCountdown = countdown;
    } else if (_leaving) {
      countdown = _lastCountdown;
    }
    final shown = countdown;
    return AppScaffold.subpage(
      title: 'Fokus',
      onBack: () => leaveFocusScreen(context),
      primaryAction: shown == null
          ? null
          : _ActionBar(
              status: shown.status,
              busy: busy || _leaving,
              onPause: () => unawaited(_pause(shown.session.id)),
              onResume: () => unawaited(_resume(shown.session.id)),
              onEnd: () => unawaited(_end(shown)),
              onSave: () => unawaited(_save(shown.session.id)),
              onDiscard: () => unawaited(_confirmDiscard(shown.session.id)),
            ),
      body: shown != null
          ? _SessionBody(countdown: shown)
          : async.when(
              loading: () => const ScreenLoading(),
              error: (error, stack) => ErrorState(
                onRetry: () {
                  ref
                    ..invalidate(focusCountdownProvider)
                    ..invalidate(focusSessionProvider);
                },
              ),
              data: (_) => const _NoSession(),
            ),
    );
  }
}

/// Nothing is open (finished here or elsewhere, or a stale link).
class _NoSession extends StatelessWidget {
  const _NoSession();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: 'Keine laufende Sitzung',
      message: 'Starte eine neue Sitzung, um deine Fokuszeit zu messen.',
      actionLabel: 'Fokus starten',
      onAction: () => context.go(FocusRoutes.start),
      icon: AppIcon.focus,
      accent: AppAccent.focus,
    );
  }
}

/// Pill, ring and the texts of the current state.
class _SessionBody extends StatelessWidget {
  const _SessionBody({required this.countdown});

  final FocusCountdown countdown;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final status = countdown.status;
    final session = countdown.session;
    final pausedAt = session.pausedAtUtc;
    final ring = status == FocusStatus.paused && pausedAt != null
        ? PausedForBuilder(
            pausedAtUtc: pausedAt,
            builder: (context, pausedFor) =>
                FocusTimerRing(countdown: countdown, pausedFor: pausedFor),
          )
        : FocusTimerRing(countdown: countdown);
    final hint = switch (status) {
      FocusStatus.running =>
        'Der Timer läuft weiter, auch wenn du die App schließt.',
      FocusStatus.paused => 'Pausierte Zeit zählt nicht zur Fokuszeit.',
      FocusStatus.awaitingConfirmation =>
        'Die Zeit zählt erst, wenn du die Sitzung speicherst.',
      FocusStatus.completed || FocusStatus.discarded => '',
    };
    final anomaly = countdown.anomalyMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: FocusStatusPill(status: status, category: session.category),
        ),
        const SizedBox(height: 20),
        Center(child: ring),
        const SizedBox(height: 16),
        if (status == FocusStatus.awaitingConfirmation)
          _ConfirmationInfo(plannedSeconds: countdown.plannedSeconds),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            hint,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
        if (anomaly != null) ...[
          const SizedBox(height: 12),
          Center(
            child: InlineMessage(
              text: anomaly,
              tone: InlineMessageTone.warning,
            ),
          ),
        ],
      ],
    );
  }
}

/// What saving does once the time is over: the XP hint (only while the
/// gamification module is on) and the effect on today's focus time.
class _ConfirmationInfo extends ConsumerWidget {
  const _ConfirmationInfo({required this.plannedSeconds});

  final int plannedSeconds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final xp = focusXpText(ref.watch(focusXpOutcomeProvider(plannedSeconds)));
    final today = ref.watch(focusTodaySummaryProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (xp != null) ...[
          Center(
            child: AppBadge(
              label: xp,
              accent: AppAccent.gamification,
              icon: Icons.star_rounded,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (today != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              focusSaveEffectText(savedSeconds: plannedSeconds, today: today),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyRegular.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// The actions of the current state, pinned below the scrolling content: all
/// of them are visible buttons (no gestures), at least 48 high, and they stack
/// on large text.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.status,
    required this.busy,
    required this.onPause,
    required this.onResume,
    required this.onEnd,
    required this.onSave,
    required this.onDiscard,
  });

  final FocusStatus status;
  final bool busy;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onEnd;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final stacked = scale > AppSizes.stackTextScale;
    final end = SecondaryButton(
      label: 'Beenden',
      icon: Icons.stop_rounded,
      semanticLabel: 'Sitzung beenden',
      onPressed: busy ? null : onEnd,
    );
    switch (status) {
      case FocusStatus.awaitingConfirmation:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrimaryButton(
              label: 'Sitzung speichern',
              loading: busy,
              onPressed: onSave,
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Verwerfen',
              onPressed: busy ? null : onDiscard,
            ),
          ],
        );
      case FocusStatus.running:
      case FocusStatus.paused:
        final first = status == FocusStatus.running
            ? SecondaryButton(
                label: 'Pausieren',
                icon: Icons.pause_rounded,
                onPressed: busy ? null : onPause,
              )
            : PrimaryButton(
                label: 'Fortsetzen',
                icon: Icons.play_arrow_rounded,
                onPressed: busy ? null : onResume,
              );
        if (stacked) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 8), end],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: end),
          ],
        );
      case FocusStatus.completed:
      case FocusStatus.discarded:
        return const SizedBox.shrink();
    }
  }
}
