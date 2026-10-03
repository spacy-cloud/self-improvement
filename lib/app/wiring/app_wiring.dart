import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/app/router/route_guard.dart';
import 'package:self_improvement/core/backup/backup_providers.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Everything that keeps running for the lifetime of the app after a
/// successful start: the reminder triggers, the clock (resume and midnight),
/// the cleanup of temporary export files and the way notifications lead into
/// the app.
///
/// The cold-start contract (see `NotificationRouteResolver`): the reminder
/// platform is initialized before the first frame (done by the app root), the
/// launch payload is read exactly once after the start succeeded and ONLY when
/// onboarding is completed (during onboarding the user sees the start flow, not
/// a module screen), and every payload, launch or tap, goes through
/// `NotificationEntryResolver` before the router sees it.
final class AppWiring {
  AppWiring({
    required this.container,
    required this.router,
    required this.guard,
  });

  final ProviderContainer container;
  final GoRouter router;
  final RouteGuardState Function() guard;

  StreamSubscription<String>? _taps;
  _ClockLifecycle? _clock;
  bool _started = false;

  /// Starts the triggers. Safe to call once; later calls do nothing.
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    // Reminders: one run now and one for every database change, and one on
    // every resume (after the device zone was read again).
    container
      ..read(reminderAutoReconcileProvider)
      ..read(reminderLifecycleProvider);
    _clock = _ClockLifecycle(container)..attach();
    // Leftover temporary export copies from an earlier session (never throws).
    unawaited(container.read(backupServiceProvider).cleanUpTemporaryExports());
    _taps = container
        .read(reminderPlatformProvider)
        .tapStream
        .listen((payload) => unawaited(openFromNotification(payload)));
    if (guard().onboardingCompleted) {
      await _openLaunchPayload();
    }
  }

  Future<void> _openLaunchPayload() async {
    String? payload;
    try {
      payload = await container.read(reminderPlatformProvider).launchPayload();
    } on Object catch (error) {
      debugPrint('launch payload not readable: ${error.runtimeType}');
      return;
    }
    if (payload != null) {
      await openFromNotification(payload);
    }
  }

  /// Opens the in-app route for a notification [payload] (launch or tap). The
  /// resolver turns anything unknown, a switched-off module or a missing
  /// record into a safe route. The target is pushed on top of what is open,
  /// so back returns to where the user was; an open form is never discarded.
  /// Ignored before the start state is known and during onboarding.
  Future<void> openFromNotification(String? payload) async {
    final state = guard();
    if (!state.ready || !state.onboardingCompleted) {
      return;
    }
    final String route;
    try {
      route = await container
          .read(notificationEntryResolverProvider)
          .resolve(payload);
    } on Object catch (error) {
      debugPrint('notification entry failed: ${error.runtimeType}');
      return;
    }
    final path = router.routerDelegate.currentConfiguration.uri.path;
    if (route == AppRoutes.home) {
      if (AppRoutes.isTabRoot(path)) {
        router.go(AppRoutes.home);
      }
      return;
    }
    unawaited(router.push<void>(route));
  }

  /// Stops the triggers.
  Future<void> dispose() async {
    _clock?.detach();
    _clock = null;
    await _taps?.cancel();
    _taps = null;
  }
}

/// Keeps "today" right: re-reads the device zone and the date when the app
/// comes back to the foreground and when the local day changes while the app
/// runs (a timer to the next local midnight).
class _ClockLifecycle with WidgetsBindingObserver {
  _ClockLifecycle(this._container);

  final ProviderContainer _container;
  Timer? _timer;
  bool _attached = false;

  void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
  }

  void detach() {
    if (!_attached) {
      return;
    }
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    await _container.read(deviceZoneTrackerProvider).refresh();
    if (!_attached) {
      return;
    }
    _container.read(todayProvider.notifier).refresh();
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _timer?.cancel();
    final clock = _container.read(clockProvider);
    final now = clock.nowUtc();
    final tomorrow = clock.today().addDays(1);
    var resolved = clock.toUtc(tomorrow, const LocalTime(0, 0));
    if (resolved is ZonedNonexistent) {
      // Midnight does not exist that day (a zone skipped it): the first
      // valid minute starts the new day.
      resolved = clock.toUtc(tomorrow, resolved.nextValid);
    }
    final target = resolved is ZonedResolved
        ? resolved.utc
        : now.add(const Duration(hours: 1));
    // One second after midnight, so the date has surely changed; never a
    // zero delay (no tight loop if the clock was set back).
    final delay = target.difference(now) + const Duration(seconds: 1);
    _timer = Timer(delay.isNegative ? const Duration(seconds: 1) : delay, () {
      if (!_attached) {
        return;
      }
      _container.read(todayProvider.notifier).refresh();
      _scheduleMidnight();
    });
  }
}
