import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/app/router/navigation.dart';
import 'package:self_improvement/app/router/route_guard.dart';
import 'package:self_improvement/core/backup/backup_providers.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_controller.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/modules/application/module_lifecycle.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Everything that keeps running for the lifetime of the app after a
/// successful start: the module lifecycle (`initialize` for active modules,
/// `dispose` when one is switched off), the reminder triggers, the triggers of
/// the comparison with the health interface (start and resume; nothing is read
/// while the switch is off), the clock (resume and midnight),
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
      ..read(moduleLifecycleProvider)
      ..read(reminderAutoReconcileProvider)
      ..read(reminderLifecycleProvider)
      // Steps from the health interface: one comparison now (start) and one on
      // every resume. Ends at once while the switch is off.
      ..read(healthStepsAutoSyncProvider);
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
  /// record into a safe route (the dashboard, the habit list, or the task
  /// list). A screen target is pushed on top of what is open, so back returns
  /// to where the user was; a tab target selects the tab, but only while a tab
  /// is on top (an open form is never discarded). When the page on top already
  /// is the target (the form of that task is open) nothing is opened: a second
  /// copy of a form would only be a second, conflicting way to edit the same
  /// record. Ignored before the start state is known and during onboarding.
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
    if (AppRoutes.isTabRoot(route)) {
      // A tab is selected, not pushed. Only from another tab: never take a
      // screen away from the user (an open form keeps its input).
      if (AppRoutes.isTabRoot(currentPath(router))) {
        router.go(route);
      }
      return;
    }
    if (currentPath(router) == route) {
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
/// runs (a timer to the next local midnight). On every return to the foreground
/// an open focus session is restored as well: its countdown starts a fresh
/// phase from the persisted segments (the monotonic clock may have stopped
/// while the device slept), and a session that ran out meanwhile becomes
/// "awaiting confirmation", also when the user lands on a screen other than the
/// session screen.
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
    try {
      await _container.read(focusRestorerProvider).restore();
    } on Object catch (error) {
      // The focus screens report a storage problem themselves.
      debugPrint('focus session not restored: ${error.runtimeType}');
    }
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
