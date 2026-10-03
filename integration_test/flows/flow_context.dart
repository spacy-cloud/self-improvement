import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/bootstrap/bootstrap_screens.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/onboarding/presentation/onboarding_screen.dart';

/// The part of a flow run that differs between the two places the flows run:
/// the host test (in-memory database, fake clock, fake notification platform)
/// and the emulator test (the production start with a real database file, the
/// real clock and the real notification plugin).
///
/// Everything a flow cannot express with finders and taps goes through this
/// interface, so the flow bodies stay identical in both places.
abstract interface class FlowEnvironment {
  /// Disposes the running app (widget tree, provider container, database
  /// connection), like the system killing the process. The stored data stays.
  Future<void> closeApp(WidgetTester tester);

  /// Starts the app again on the data that is already stored and returns once
  /// the start is finished (see [waitForAppStart]).
  Future<void> openApp(WidgetTester tester);

  /// Lets time pass for the app's clock and returns how much did pass.
  ///
  /// The host moves its fake clock by exactly [wanted]. The emulator cannot
  /// move the real clock: it waits a short, bounded real time instead (never
  /// more than [wanted]) and returns that. Flows therefore compute their
  /// expectations from the returned duration, never from [wanted].
  Future<Duration> letTimePass(WidgetTester tester, Duration wanted);

  /// Asserts that the app's database lives in a file of the app support
  /// directory. The host uses an in-memory database: nothing to assert there.
  Future<void> expectDatabaseOnDisk();

  /// The IANA zone id the platform reports for the device right now (the real
  /// `flutter_timezone` plugin on the emulator, the fixed test zone on the
  /// host).
  Future<String> platformZoneId();
}

/// What a flow gets: the tester, the environment and small helpers that wait
/// for the screen instead of sleeping.
///
/// Every wait is a bounded loop with a real-time deadline (`pumpUntil`). There
/// is no `pumpAndSettle` anywhere: a focused text field blinks its cursor and a
/// loading indicator spins forever, so "wait until nothing is scheduled" can
/// never be trusted. A flow waits for the thing it expects instead.
final class FlowContext {
  FlowContext({required this.tester, required this.environment});

  final WidgetTester tester;
  final FlowEnvironment environment;

  /// How long one wait may take before the flow fails. Generous on purpose: the
  /// first start of the app creates and migrates the database and the CI
  /// emulator is slow.
  static const Duration defaultTimeout = Duration(seconds: 30);

  final Stopwatch _clock = Stopwatch()..start();

  /// Prints one line to the test log, so the last step shows in a failed run.
  void log(String message) => debugPrint(
    'FLOW [${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(1)} s] $message',
  );

  // ----------------------------------------------------------------- waiting

  /// Runs one step of "time passes": lets real asynchronous work (database
  /// isolate, platform channels) finish and renders one frame.
  Future<void> step() => _step(tester);

  /// Pumps until [done] is true. Fails the test with [reason] and the texts on
  /// screen after [timeout].
  Future<void> pumpUntil(
    bool Function() done, {
    required String reason,
    Duration timeout = defaultTimeout,
  }) => _pumpUntil(tester, done, reason: reason, timeout: timeout);

  /// Pumps frames until nothing animates any more, but never longer than [max]
  /// and without failing when something keeps animating (a blinking cursor).
  Future<void> settle({Duration max = const Duration(seconds: 3)}) async {
    final watch = Stopwatch()..start();
    var quiet = 0;
    while (watch.elapsed < max) {
      await step();
      if (tester.binding.hasScheduledFrame) {
        quiet = 0;
      } else if (++quiet >= 2) {
        return;
      }
    }
  }

  /// Waits until [finder] matches something on screen.
  Future<void> waitFor(
    Finder finder, {
    String? reason,
    Duration timeout = defaultTimeout,
  }) => pumpUntil(
    () => finder.evaluate().isNotEmpty,
    reason:
        reason ?? 'expected on screen: ${finder.describeMatch(Plurality.many)}',
    timeout: timeout,
  );

  /// Waits until the text [text] is on screen.
  Future<void> waitForText(String text, {Duration timeout = defaultTimeout}) =>
      waitFor(
        find.text(text),
        reason: 'expected the text "$text"',
        timeout: timeout,
      );

  /// Waits until [finder] matches nothing any more.
  Future<void> waitGone(
    Finder finder, {
    String? reason,
    Duration timeout = defaultTimeout,
  }) => pumpUntil(
    () => finder.evaluate().isEmpty,
    reason:
        reason ??
        'expected to be gone: ${finder.describeMatch(Plurality.many)}',
    timeout: timeout,
  );

  // ------------------------------------------------------------------- input

  /// Taps the first match of [finder] that can really be hit: waits for it,
  /// scrolls it into view when needed, taps, and lets the reaction render.
  Future<void> tap(Finder finder, {String? reason}) async {
    final what = reason ?? finder.describeMatch(Plurality.many);
    await pumpUntil(
      () => finder.evaluate().isNotEmpty,
      reason: 'cannot tap, not on screen: $what',
    );
    if (finder.hitTestable().evaluate().isEmpty) {
      await tester.ensureVisible(finder.first);
      await settle(max: const Duration(seconds: 1));
    }
    await pumpUntil(
      () => finder.hitTestable().evaluate().isNotEmpty,
      reason: 'cannot tap, covered or off screen: $what',
    );
    await tester.tap(finder.hitTestable().first);
    await tester.pump();
    await settle(max: const Duration(seconds: 2));
  }

  /// Taps the text [text].
  Future<void> tapText(String text) =>
      tap(find.text(text), reason: 'the text "$text"');

  /// Types [text] into [field] (the first match).
  Future<void> enterText(Finder field, String text) async {
    await pumpUntil(
      () => field.evaluate().isNotEmpty,
      reason: 'cannot type, no field: ${field.describeMatch(Plurality.many)}',
    );
    await tester.enterText(field.first, text);
    await tester.pump();
    await settle(max: const Duration(seconds: 1));
  }

  /// Runs [action] and pumps until it has finished. The one way to wait for a
  /// call into the app or the platform: a plain `await` can hang in a host test,
  /// where the test body runs on a fake clock.
  Future<T> run<T>(
    Future<T> Function() action, {
    required String reason,
  }) async {
    T? result;
    Object? failure;
    StackTrace? failureTrace;
    var done = false;
    unawaited(
      action().then<void>(
        (value) {
          result = value;
          done = true;
        },
        onError: (Object error, StackTrace trace) {
          failure = error;
          failureTrace = trace;
          done = true;
        },
      ),
    );
    await pumpUntil(() => done, reason: reason);
    final error = failure;
    if (error != null) {
      Error.throwWithStackTrace(error, failureTrace!);
    }
    return result as T;
  }

  // --------------------------------------------------------------- app state

  /// The provider container of the running app, for the few checks that cannot
  /// be done through the screen (the real platform adapters).
  ProviderContainer get container => ProviderScope.containerOf(
    tester.element(find.byType(Navigator).first),
    listen: false,
  );

  /// Kills the app and starts it again on the same data ("process death").
  /// With [closedFor] time passes while the app is closed. Returns how much
  /// time passed, see [FlowEnvironment.letTimePass].
  Future<Duration> restart({Duration closedFor = Duration.zero}) async {
    log('restart: closing the app');
    await environment.closeApp(tester);
    var passed = Duration.zero;
    if (closedFor > Duration.zero) {
      passed = await environment.letTimePass(tester, closedFor);
      log('restart: ${passed.inSeconds} s passed while the app was closed');
    }
    log('restart: starting the app again');
    await environment.openApp(tester);
    return passed;
  }

  /// Lets time pass while the app is open. Returns how much time passed.
  Future<Duration> letTimePass(Duration wanted) async {
    final passed = await environment.letTimePass(tester, wanted);
    await settle(max: const Duration(seconds: 2));
    return passed;
  }
}

/// One step of "time passes": a short real delay for work outside the test
/// clock (the database isolate and the platform channels on the emulator, real
/// timers on the host) followed by one frame of 50 ms.
///
/// On the emulator `runAsync` simply runs the delay and `pump` waits for a real
/// frame; on the host (fake async) the delay is what lets real asynchronous
/// work complete while `pump` moves the fake clock.
Future<void> _step(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  required String reason,
  required Duration timeout,
}) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > timeout) {
      fail(
        'Timed out after ${timeout.inSeconds} s: $reason\n'
        'Texts on screen: ${describeScreen()}',
      );
    }
    await _step(tester);
  }
}

/// A short list of the texts on screen, for failure messages.
String describeScreen() {
  final seen = <String>{};
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    if (text.trim().isNotEmpty) {
      seen.add(text.trim());
    }
  }
  final joined = seen.join(' | ');
  return joined.length > 700 ? '${joined.substring(0, 700)} ...' : joined;
}

/// Waits until the app has finished its start: the bootstrap screens are gone
/// and either the tabs (onboarded) or the onboarding are on screen. Fails with
/// the error code when the start failed.
///
/// The first start on an emulator creates and migrates the database, so the
/// deadline is generous.
Future<void> waitForAppStart(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final loading = find.byType(BootstrapLoadingScreen);
  final failed = find.byType(BootstrapErrorScreen);
  final tabs = find.byType(AppBottomNavBar);
  final onboarding = find.byType(OnboardingScreen);
  await _pumpUntil(
    tester,
    () {
      if (failed.evaluate().isNotEmpty) {
        fail(
          'The app did not start: it shows the start error screen.\n'
          'Texts on screen: ${describeScreen()}',
        );
      }
      return loading.evaluate().isEmpty &&
          (tabs.evaluate().isNotEmpty || onboarding.evaluate().isNotEmpty);
    },
    reason: 'the app did not finish its start',
    timeout: timeout,
  );
  // Let the first frames after the start settle (router redirect, first reads).
  for (var i = 0; i < 4; i++) {
    await _step(tester);
  }
}
