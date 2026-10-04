import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:self_improvement/core/notifications/application/device_zone_tracker.dart';
import 'package:self_improvement/core/notifications/application/reminder_service.dart';

/// Reconciles the reminders when the app returns to the foreground.
///
/// On resume the device time zone is read again (the user may have travelled
/// or changed it while the app was in the background) and the reminders are
/// reconciled. That covers the "resume" and "time zone change" triggers; the
/// "start" trigger is the first run of `ReminderAutoReconciler`, and every
/// change that is written to the database is covered by it as well.
///
/// The reconcile is also needed without a zone change: the day may have
/// changed (the seven day horizon moves), the permission may have been
/// changed in the system settings, and alarms may have fired.
final class ReminderLifecycleObserver with WidgetsBindingObserver {
  ReminderLifecycleObserver({required this._service, required this._zones});

  final ReminderService _service;
  final DeviceZoneTracker _zones;
  bool _attached = false;

  /// Starts observing the app lifecycle. Idempotent.
  void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Stops observing.
  void detach() {
    if (!_attached) {
      return;
    }
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(onResumed());
    }
  }

  /// What a resume does: refresh the zone, then reconcile. Exposed so the app
  /// shell can run the same steps from its own resume handling and tests can
  /// await the result. Never throws.
  Future<void> onResumed() async {
    await _zones.refresh();
    await _service.reconcile();
  }
}
