import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/focus/domain/focus_formatting.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/features/focus/domain/focus_timer.dart';

/// The live state of the open session as the focus screens show it.
///
/// Emitted by `focusCountdownProvider`: about once per second while the session
/// runs, once per state change otherwise.
@immutable
final class FocusCountdown {
  const FocusCountdown({
    required this.session,
    required this.elapsedSeconds,
    this.clockAnomaly = false,
  });

  /// The open session this value belongs to.
  final FocusSession session;

  /// Seconds of focus time so far (`0..planned`).
  final int elapsedSeconds;

  /// The device clock was set back; the UI shows [anomalyMessage] so the user
  /// can check the duration.
  final bool clockAnomaly;

  FocusStatus get status => session.status;

  int get plannedSeconds => session.plannedSeconds;

  /// `planned - elapsed`; 0 once the time is over.
  int get remainingSeconds => plannedSeconds - elapsedSeconds;

  /// Progress in `0..1` for the ring.
  double get progress => plannedSeconds <= 0
      ? 0
      : (elapsedSeconds / plannedSeconds).clamp(0.0, 1.0);

  bool get isRunning => status == FocusStatus.running;

  bool get isPaused => status == FocusStatus.paused;

  /// The countdown reached zero and the user still has to confirm.
  bool get isAwaitingConfirmation => status == FocusStatus.awaitingConfirmation;

  /// The remaining time as `MM:SS` (`H:MM:SS` from one hour).
  String get remainingText => formatCountdown(remainingSeconds);

  /// The planned time as `MM:SS` ("verbleibend von 25:00").
  String get plannedText => formatCountdown(plannedSeconds);

  /// German hint to check the duration, or null when the clock is fine.
  String? get anomalyMessage => clockAnomaly ? focusClockAnomalyMessage : null;

  @override
  bool operator ==(Object other) =>
      other is FocusCountdown &&
      other.session == session &&
      other.elapsedSeconds == elapsedSeconds &&
      other.clockAnomaly == clockAnomaly;

  @override
  int get hashCode => Object.hash(session, elapsedSeconds, clockAnomaly);

  @override
  String toString() =>
      'FocusCountdown(${session.id}, ${status.key}, $elapsedSeconds/'
      '$plannedSeconds s${clockAnomaly ? ', clock anomaly' : ''})';
}

/// Source of foreground ticks together with a MONOTONIC time reading.
///
/// The countdown measures time within one foreground phase with this source,
/// not with the wall clock, so a changed device clock cannot shift the display.
/// Tests inject a manual source; nothing ever sleeps for real there.
abstract interface class FocusTickSource {
  /// A new measurement: the returned stream emits, roughly every few hundred
  /// milliseconds, the monotonic time that has passed since this method was
  /// called. Values never decrease. The measurement ends when the subscription
  /// is cancelled. Listen to the stream right away.
  Stream<Duration> ticks();
}

/// The production tick source: a periodic timer plus a [Stopwatch].
///
/// A [Stopwatch] is monotonic. Note that on Android the monotonic clock stops
/// while the device is suspended; that is why the app re-bases the countdown
/// on the persisted UTC segments whenever it is resumed (see `FocusRestorer`).
final class StopwatchTickSource implements FocusTickSource {
  const StopwatchTickSource({
    this.interval = const Duration(milliseconds: 250),
  });

  /// Time between two ticks. Shorter than a second so that the displayed
  /// second never lags noticeably; the countdown only emits a value when the
  /// whole second changes.
  final Duration interval;

  @override
  Stream<Duration> ticks() {
    final stopwatch = Stopwatch()..start();
    return Stream<Duration>.periodic(interval, (_) => stopwatch.elapsed);
  }
}

/// Drives the foreground countdown of the open session.
///
/// [bind] turns a stream of the open session into a stream of
/// [FocusCountdown]s:
///
/// * a RUNNING session starts a foreground PHASE: the elapsed time at its
///   start is computed once from the persisted UTC segments and the injected
///   clock; afterwards only the monotonic [FocusTickSource] advances it, so
///   wall clock jumps during the phase do not move the display. A backwards
///   jump of the clock during the phase is detected (wall time advances less
///   than monotonic time) and reported as [FocusCountdown.clockAnomaly];
/// * when the remaining time reaches zero, `onReachedZero` is called exactly
///   once per phase, then the ticking stops;
/// * paused and awaiting sessions give one static value;
/// * a `rebase` event starts a new phase from the persisted state (app
///   resumed, the device may have slept).
///
/// Nothing is written to the database except by `onReachedZero`.
final class FocusCountdownEngine {
  FocusCountdownEngine({
    required this._clock,
    required this._ticker,
    required this._onReachedZero,
    this.clockJumpToleranceMillis = 2000,
  });

  final ClockService _clock;
  final FocusTickSource _ticker;
  final Future<void> Function(FocusSession session) _onReachedZero;

  /// How much slower than the monotonic time the wall clock may advance
  /// before a backwards jump is reported.
  final int clockJumpToleranceMillis;

  /// The countdown stream for [sessions] (the open session or null). [rebases]
  /// restarts the foreground phase of a running session. The returned stream
  /// is single-subscription; cancelling it stops all ticking.
  Stream<FocusCountdown?> bind(
    Stream<FocusSession?> sessions, {
    Stream<void>? rebases,
  }) => _CountdownRun(this, sessions, rebases).stream;
}

/// One foreground phase of a running session.
final class _Phase {
  _Phase({
    required this.session,
    required this.baselineMillis,
    required this.startedAtUtc,
    required this.clockAnomaly,
  });

  final FocusSession session;

  /// Elapsed milliseconds when the phase started (persisted segments).
  final int baselineMillis;

  /// Wall clock at the start of the phase (only to detect a backwards jump).
  final DateTime startedAtUtc;

  bool clockAnomaly;
  bool zeroReported = false;
}

final class _CountdownRun {
  _CountdownRun(this._engine, this._sessions, this._rebases) {
    _controller = StreamController<FocusCountdown?>(
      onListen: _handleListen,
      onCancel: _handleCancel,
    );
  }

  final FocusCountdownEngine _engine;
  final Stream<FocusSession?> _sessions;
  final Stream<void>? _rebases;
  late final StreamController<FocusCountdown?> _controller;

  StreamSubscription<FocusSession?>? _sessionSubscription;
  StreamSubscription<void>? _rebaseSubscription;
  StreamSubscription<Duration>? _tickSubscription;

  var _hasSession = false;
  FocusSession? _session;
  _Phase? _phase;
  var _hasEmitted = false;
  FocusCountdown? _lastEmitted;

  Stream<FocusCountdown?> get stream => _controller.stream;

  void _handleListen() {
    _sessionSubscription = _sessions.listen(
      _handleSession,
      onError: _controller.addError,
    );
    _rebaseSubscription = _rebases?.listen((_) => _handleRebase());
  }

  Future<void> _handleCancel() async {
    _phase = null;
    await _tickSubscription?.cancel();
    _tickSubscription = null;
    await _sessionSubscription?.cancel();
    _sessionSubscription = null;
    await _rebaseSubscription?.cancel();
    _rebaseSubscription = null;
    await _controller.close();
  }

  void _handleSession(FocusSession? session) {
    if (_hasSession && session == _session) {
      return;
    }
    _hasSession = true;
    _session = session;
    _stopPhase();
    if (session == null) {
      _emit(null);
    } else if (session.status == FocusStatus.running) {
      _startPhase(session);
    } else {
      _emit(
        FocusCountdown(
          session: session,
          elapsedSeconds: computeFocusElapsed(
            session,
            _engine._clock.nowUtc(),
          ).elapsedSeconds,
        ),
      );
    }
  }

  void _handleRebase() {
    final session = _session;
    if (session == null || session.status != FocusStatus.running) {
      return;
    }
    _stopPhase();
    _startPhase(session);
  }

  void _startPhase(FocusSession session) {
    final now = _engine._clock.nowUtc();
    var baseline = session.accumulatedSeconds * 1000;
    final start = session.segmentStartedAtUtc;
    var anomaly = false;
    if (start != null) {
      if (now.isBefore(start)) {
        anomaly = true;
      } else {
        baseline += now.difference(start).inMilliseconds;
      }
    }
    final phase = _Phase(
      session: session,
      baselineMillis: baseline.clamp(0, session.plannedSeconds * 1000),
      startedAtUtc: now,
      clockAnomaly: anomaly,
    );
    _phase = phase;
    if (_publish(phase, 0) <= 0) {
      _reportZero(phase);
      return;
    }
    _tickSubscription = _engine._ticker.ticks().listen(
      (monotonic) => _handleTick(phase, monotonic),
    );
  }

  void _handleTick(_Phase phase, Duration monotonic) {
    if (!identical(phase, _phase)) {
      return;
    }
    final monotonicMillis = monotonic.inMilliseconds;
    final wallMillis = _engine._clock
        .nowUtc()
        .difference(phase.startedAtUtc)
        .inMilliseconds;
    if (wallMillis < monotonicMillis - _engine.clockJumpToleranceMillis) {
      phase.clockAnomaly = true;
    }
    if (_publish(phase, monotonicMillis) <= 0) {
      _reportZero(phase);
    }
  }

  /// Emits the countdown for [monotonicMillis] into the phase and returns the
  /// remaining seconds.
  int _publish(_Phase phase, int monotonicMillis) {
    final planned = phase.session.plannedSeconds;
    final elapsed = ((phase.baselineMillis + monotonicMillis) ~/ 1000).clamp(
      0,
      planned,
    );
    _emit(
      FocusCountdown(
        session: phase.session,
        elapsedSeconds: elapsed,
        clockAnomaly: phase.clockAnomaly,
      ),
    );
    return planned - elapsed;
  }

  /// The countdown is at zero: tell the owner once, then stop ticking.
  void _reportZero(_Phase phase) {
    if (phase.zeroReported) {
      return;
    }
    phase.zeroReported = true;
    _stopTicks();
    unawaited(_callReachedZero(phase.session));
  }

  Future<void> _callReachedZero(FocusSession session) async {
    try {
      await _engine._onReachedZero(session);
    } catch (error) {
      // The persisted session stays `running`; the next resume or restoration
      // turns it into awaiting_confirmation. Log only the type.
      debugPrint('focus countdown: marking failed: ${error.runtimeType}');
    }
  }

  void _stopPhase() {
    _phase = null;
    _stopTicks();
  }

  void _stopTicks() {
    unawaited(_tickSubscription?.cancel());
    _tickSubscription = null;
  }

  void _emit(FocusCountdown? value) {
    if (_controller.isClosed || (_hasEmitted && value == _lastEmitted)) {
      return;
    }
    _hasEmitted = true;
    _lastEmitted = value;
    _controller.add(value);
  }
}
