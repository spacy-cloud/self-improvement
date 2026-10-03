import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/features/focus/application/focus_countdown.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';

import '../support/focus_fixtures.dart';
import '../support/manual_tick_source.dart';

/// Everything needed to drive a [FocusCountdownEngine] without a database and
/// without real time: a fake clock, a manual tick source and manual streams.
final class _Rig {
  _Rig() {
    TimeZones.ensureInitialized();
    ticker.onStart = () => phaseStart = clock.nowUtc();
    engine = FocusCountdownEngine(
      clock: clock,
      ticker: ticker,
      onReachedZero: (session) async {
        reported.add(session);
        final failure = reportFailure;
        if (failure != null) {
          throw failure;
        }
      },
    );
    subscription = engine
        .bind(sessions.stream, rebases: rebases.stream)
        .listen(values.add);
  }

  final FakeClock clock = FakeClock(t0);
  final ManualTickSource ticker = ManualTickSource();
  final StreamController<FocusSession?> sessions =
      StreamController<FocusSession?>(sync: true);
  final StreamController<void> rebases = StreamController<void>(sync: true);
  final List<FocusCountdown?> values = [];
  final List<FocusSession> reported = [];
  Object? reportFailure;

  /// The wall clock when the current foreground phase started.
  DateTime phaseStart = t0;

  late final FocusCountdownEngine engine;
  late final StreamSubscription<FocusCountdown?> subscription;

  /// The remaining seconds of everything emitted so far (null for "no
  /// session").
  List<int?> get remaining => values.map((v) => v?.remainingSeconds).toList();

  Future<void> dispose() async {
    await subscription.cancel();
    await sessions.close();
    await rebases.close();
    await ticker.close();
  }
}

void main() {
  late _Rig rig;

  setUp(() => rig = _Rig());
  tearDown(() => rig.dispose());

  /// Pushes a session and lets the engine emit.
  Future<void> open(FocusSession? session) async {
    rig.sessions.add(session);
    await settle();
  }

  /// One monotonic reading while the wall clock advances in step (a normal
  /// device), then the engine emits.
  Future<void> tick(int seconds, {int millis = 0}) async {
    final reading = Duration(seconds: seconds, milliseconds: millis);
    rig.clock.setNow(rig.phaseStart.add(reading));
    rig.ticker.emit(reading);
    await settle();
  }

  /// One monotonic reading WITHOUT touching the wall clock (the test moved it
  /// itself).
  Future<void> tickRaw(int seconds, {int millis = 0}) async {
    rig.ticker.emit(Duration(seconds: seconds, milliseconds: millis));
    await settle();
  }

  group('a running session (foreground phase)', () {
    test(
      'starts from the persisted segments and counts down once per second',
      () async {
        await open(focusSession(planned: 300));
        expect(rig.remaining, [300]);
        expect(rig.values.single!.elapsedSeconds, 0);
        expect(rig.values.single!.isRunning, isTrue);
        expect(rig.ticker.phasesStarted, 1);

        await tick(0, millis: 250);
        await tick(0, millis: 999);
        expect(rig.remaining, [
          300,
        ], reason: 'the same second is not re-emitted');
        await tick(1);
        await tick(1, millis: 500);
        await tick(2);
        await tick(3, millis: 999);
        expect(rig.remaining, [300, 299, 298, 297]);
        expect(rig.values.last!.elapsedSeconds, 3);
        expect(rig.reported, isEmpty);
      },
    );

    test('the elapsed time at the phase start includes accumulated time and the current segment', () async {
      rig.clock.setNow(after(100));
      await open(focusSession(planned: 600, accumulated: 50));
      // 50 accumulated + 100 s since the segment start.
      expect(rig.values.single!.elapsedSeconds, 150);
      expect(rig.values.single!.remainingSeconds, 450);
      await tick(10);
      expect(rig.values.last!.elapsedSeconds, 160);
    });

    test('keeps the sub-second part of the persisted segment', () async {
      rig.clock.setNow(after(10, millis: 500));
      await open(focusSession(planned: 300));
      expect(rig.values.single!.elapsedSeconds, 10);
      await tick(0, millis: 499);
      expect(rig.values.last!.elapsedSeconds, 10);
      await tick(0, millis: 500);
      expect(rig.values.last!.elapsedSeconds, 11, reason: '10.5 s + 0.5 s');
    });

    test('shows the planned and remaining text for the ring', () async {
      await open(focusSession(planned: 1500));
      expect(rig.values.single!.remainingText, '25:00');
      expect(rig.values.single!.plannedText, '25:00');
      await tick(0, millis: 888);
      await tick(1);
      expect(rig.values.last!.remainingText, '24:59');
      expect(rig.values.last!.progress, closeTo(1 / 1500, 1e-9));
    });
  });

  group('reaching zero', () {
    test('calls onReachedZero exactly once and stops ticking', () async {
      final session = focusSession(planned: 300);
      await open(session);
      for (var second = 1; second <= 299; second++) {
        await tick(second);
      }
      expect(rig.reported, isEmpty);
      expect(rig.values.last!.remainingSeconds, 1);
      expect(rig.ticker.activeSubscriptions, 1);

      await tick(300);
      expect(rig.reported, [session]);
      expect(rig.values.last!.remainingSeconds, 0);
      expect(rig.ticker.activeSubscriptions, 0, reason: 'ticking stopped');

      // Further readings or repeated emissions change nothing.
      await tick(301);
      await tick(10000);
      rig.sessions.add(session);
      await settle();
      expect(rig.reported, hasLength(1));
      expect(rig.values.last!.remainingSeconds, 0);
      expect(
        rig.remaining.where((r) => r == 0),
        hasLength(1),
        reason: 'zero is emitted once',
      );
    });

    test(
      'never counts below zero when a tick arrives far past the end',
      () async {
        await open(focusSession(planned: 300));
        await tick(100000);
        expect(rig.values.last!.remainingSeconds, 0);
        expect(rig.values.last!.elapsedSeconds, 300);
        expect(rig.reported, hasLength(1));
      },
    );

    test(
      'a session already past its end at the phase start is reported at once',
      () async {
        rig.clock.setNow(after(7200));
        await open(focusSession(planned: 600));
        expect(rig.values.single!.remainingSeconds, 0);
        expect(rig.reported, hasLength(1));
        expect(rig.ticker.phasesStarted, 0, reason: 'nothing to tick');
      },
    );

    test('a failing report is swallowed; a rebase tries again', () async {
      rig.reportFailure = StateError('disk full');
      await open(focusSession(planned: 300));
      await tick(300);
      expect(rig.reported, hasLength(1));
      expect(rig.values.last!.remainingSeconds, 0);
      await tick(301);
      expect(rig.reported, hasLength(1), reason: 'no retry loop');

      rig.reportFailure = null;
      rig.clock.setNow(after(400));
      rig.rebases.add(null);
      await settle();
      expect(rig.reported, hasLength(2), reason: 'a new phase reports again');
    });

    test(
      'the awaiting session that follows emits one static zero value',
      () async {
        await open(focusSession(planned: 300));
        await tick(300);
        await open(
          focusSession(
            planned: 300,
            accumulated: 300,
            status: FocusStatus.awaitingConfirmation,
            rowVersion: 2,
          ),
        );
        expect(rig.values.last!.isAwaitingConfirmation, isTrue);
        expect(rig.values.last!.remainingSeconds, 0);
        expect(rig.reported, hasLength(1));
        expect(rig.ticker.activeSubscriptions, 0);
      },
    );
  });

  group('wall clock jumps within a foreground phase', () {
    test('a forward jump does not shift the display', () async {
      await open(focusSession(planned: 600));
      await tick(5);
      rig.clock.advance(const Duration(hours: 3));
      await tickRaw(10);
      expect(rig.values.last!.remainingSeconds, 590);
      expect(rig.values.last!.clockAnomaly, isFalse);
      expect(rig.reported, isEmpty);
    });

    test('a backward jump does not shift the display and is reported as an anomaly', () async {
      await open(focusSession(planned: 600));
      await tick(5);
      expect(rig.values.last!.clockAnomaly, isFalse);
      rig.clock.setNow(t0.subtract(const Duration(hours: 2)));
      await tickRaw(20);
      expect(rig.values.last!.remainingSeconds, 580);
      expect(rig.values.last!.clockAnomaly, isTrue);
      expect(
        rig.values.last!.anomalyMessage,
        'Die Uhr des Geräts wurde zurückgestellt. Bitte prüfe die Sitzungsdauer.',
      );
      await tickRaw(21);
      expect(
        rig.values.last!.clockAnomaly,
        isTrue,
        reason: 'stays for the phase',
      );
    });

    test('a small backward step inside the tolerance is no anomaly', () async {
      await open(focusSession(planned: 600));
      rig.clock.setNow(t0.add(const Duration(seconds: 30)));
      await tickRaw(32); // the wall clock lags 2 s: exactly the tolerance
      expect(rig.values.last!.clockAnomaly, isFalse);
      await tickRaw(33); // lags 3 s
      expect(rig.values.last!.clockAnomaly, isTrue);
    });

    test('a segment that starts in the future counts as 0 and sets the anomaly flag', () async {
      rig.clock.setNow(t0.subtract(const Duration(hours: 1)));
      await open(focusSession(planned: 600, accumulated: 200));
      expect(rig.values.single!.elapsedSeconds, 200);
      expect(rig.values.single!.clockAnomaly, isTrue);
      expect(rig.values.single!.anomalyMessage, isNotNull);
      await tick(5);
      expect(rig.values.last!.elapsedSeconds, 205);
    });
  });

  group('paused, awaiting and no session', () {
    test('a paused session gives one static value and no ticking', () async {
      await open(
        focusSession(
          planned: 1500,
          accumulated: 612,
          status: FocusStatus.paused,
        ),
      );
      expect(rig.values, hasLength(1));
      expect(rig.values.single!.isPaused, isTrue);
      expect(rig.values.single!.remainingSeconds, 888);
      expect(rig.values.single!.elapsedSeconds, 612);
      expect(rig.ticker.phasesStarted, 0);
    });

    test('an awaiting session shows zero and reports nothing', () async {
      await open(
        focusSession(
          planned: 600,
          accumulated: 600,
          status: FocusStatus.awaitingConfirmation,
        ),
      );
      expect(rig.values.single!.isAwaitingConfirmation, isTrue);
      expect(rig.values.single!.remainingSeconds, 0);
      expect(rig.reported, isEmpty);
    });

    test('no session emits null once', () async {
      await open(null);
      await open(null);
      expect(rig.values, [isNull]);
    });

    test('a session that disappears stops the ticking', () async {
      await open(focusSession());
      expect(rig.ticker.activeSubscriptions, 1);
      await open(null);
      expect(rig.values.last, isNull);
      expect(rig.ticker.activeSubscriptions, 0);
    });
  });

  group('changes of the open session', () {
    test(
      'pause stops the ticking, resume starts a new phase from the new segment',
      () async {
        final running = focusSession(planned: 600);
        await open(running);
        await tick(100);
        expect(rig.values.last!.remainingSeconds, 500);

        final paused = focusSession(
          planned: 600,
          accumulated: 100,
          status: FocusStatus.paused,
          rowVersion: 2,
        );
        await open(paused);
        expect(rig.ticker.activeSubscriptions, 0);
        expect(rig.values.last!.isPaused, isTrue);
        expect(rig.values.last!.remainingSeconds, 500);

        rig.clock.setNow(after(1000));
        final resumed = focusSession(
          planned: 600,
          accumulated: 100,
          segmentStart: after(1000),
          rowVersion: 3,
        );
        await open(resumed);
        expect(rig.ticker.phasesStarted, 2);
        expect(rig.values.last!.isRunning, isTrue);
        expect(rig.values.last!.remainingSeconds, 500);
        await tick(30);
        expect(rig.values.last!.remainingSeconds, 470);
      },
    );

    test('a stale tick of an ended phase is ignored', () async {
      await open(focusSession(planned: 600));
      await open(
        focusSession(
          planned: 600,
          accumulated: 50,
          status: FocusStatus.paused,
          rowVersion: 2,
        ),
      );
      final emitted = rig.values.length;
      rig.ticker.emitSeconds(5);
      await settle();
      expect(rig.values, hasLength(emitted), reason: 'nobody listens any more');
    });

    test('the same session value again does not restart the phase', () async {
      final session = focusSession(planned: 600);
      await open(session);
      await tick(10);
      await open(session);
      await open(session);
      expect(rig.ticker.phasesStarted, 1);
      expect(rig.values.last!.remainingSeconds, 590);
    });

    test('a different session starts its own phase', () async {
      await open(focusSession(id: 'a', planned: 600));
      await tick(5);
      await open(
        focusSession(id: 'b', planned: 900, segmentStart: rig.clock.nowUtc()),
      );
      expect(rig.ticker.phasesStarted, 2);
      expect(rig.values.last!.session.id, 'b');
      expect(rig.values.last!.remainingSeconds, 900);
    });
  });

  group('rebase (app resumed)', () {
    test('recomputes the elapsed time from the persisted segments', () async {
      await open(focusSession(planned: 3600));
      await tick(10);
      expect(rig.values.last!.elapsedSeconds, 10);
      // The device slept: the wall clock advanced, the monotonic clock did not.
      rig.clock.advance(const Duration(minutes: 20));
      rig.rebases.add(null);
      await settle();
      expect(rig.values.last!.elapsedSeconds, 1210, reason: '10 s + 20 min');
      expect(rig.ticker.phasesStarted, 2);
      await tick(5);
      expect(rig.values.last!.elapsedSeconds, 1215);
    });

    test('a rebase after the end reports zero', () async {
      await open(focusSession(planned: 600));
      rig.clock.advance(const Duration(hours: 1));
      rig.rebases.add(null);
      await settle();
      expect(rig.values.last!.remainingSeconds, 0);
      expect(rig.reported, hasLength(1));
    });

    test('is ignored without a running session', () async {
      rig.rebases.add(null);
      await settle();
      expect(rig.values, isEmpty);
      await open(focusSession(accumulated: 100, status: FocusStatus.paused));
      final emitted = rig.values.length;
      rig.rebases.add(null);
      await settle();
      expect(rig.values, hasLength(emitted));
      expect(rig.ticker.phasesStarted, 0);
    });

    test(
      'clears a clock anomaly once the persisted state is sound again',
      () async {
        await open(focusSession(planned: 600));
        rig.clock.setNow(t0.subtract(const Duration(hours: 1)));
        await tickRaw(30);
        expect(rig.values.last!.clockAnomaly, isTrue);
        rig.clock.setNow(after(60));
        rig.rebases.add(null);
        await settle();
        expect(rig.values.last!.clockAnomaly, isFalse);
        expect(rig.values.last!.elapsedSeconds, 60);
      },
    );
  });

  group('lifecycle', () {
    test('cancelling stops all ticking and all reports', () async {
      await open(focusSession(planned: 300));
      await tick(10);
      expect(rig.ticker.activeSubscriptions, 1);
      await rig.subscription.cancel();
      expect(rig.ticker.activeSubscriptions, 0);
      rig.ticker.emitSeconds(1000);
      await settle();
      expect(rig.reported, isEmpty);
    });

    test('errors of the session stream are forwarded', () async {
      final errors = <Object>[];
      final controller = StreamController<FocusSession?>();
      final engine = FocusCountdownEngine(
        clock: rig.clock,
        ticker: rig.ticker,
        onReachedZero: (_) async {},
      );
      final subscription = engine
          .bind(controller.stream)
          .listen((_) {}, onError: errors.add);
      controller.addError(StateError('boom'));
      await settle();
      expect(errors.single, isA<StateError>());
      await subscription.cancel();
      await controller.close();
    });
  });
}
