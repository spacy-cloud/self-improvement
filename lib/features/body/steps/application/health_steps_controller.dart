import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/health/application/health_providers.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_sync.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/body/steps/domain/health_steps_status.dart';
import 'package:self_improvement/features/modules/application/data_epoch.dart';

/// What the device said last and what the comparison is doing; the volatile
/// part of [HealthStepsStatus] (the wish and the time of the last comparison
/// live in the settings).
@immutable
final class HealthStepsRuntime {
  const HealthStepsRuntime({
    this.availability,
    this.access,
    this.syncing = false,
    this.failed = false,
  });

  final HealthAvailability? availability;
  final HealthAccess? access;
  final bool syncing;
  final bool failed;

  HealthStepsRuntime copyWith({
    HealthAvailability? Function()? availability,
    HealthAccess? Function()? access,
    bool? syncing,
    bool? failed,
  }) => HealthStepsRuntime(
    availability: availability == null ? this.availability : availability(),
    access: access == null ? this.access : access(),
    syncing: syncing ?? this.syncing,
    failed: failed ?? this.failed,
  );
}

/// How the attempt to get the access (and then compare) ended.
enum HealthAccessResult {
  /// The access is there and the steps were compared.
  synced,

  /// The user did not allow reading the steps (or the system showed no
  /// dialog because it was refused before).
  accessDenied,

  /// The app of the interface is not installed.
  interfaceMissing,

  /// The app of the interface is too old.
  interfaceOutdated,

  /// The device has no health interface the app supports.
  unsupported,

  /// The attempt failed for a technical reason.
  failed,
}

/// How switching "Schritte aus Health übernehmen" on ended.
@immutable
sealed class HealthEnableResult {
  const HealthEnableResult();
}

/// The wish could not be stored; nothing changed.
final class HealthEnableStorageFailed extends HealthEnableResult {
  const HealthEnableStorageFailed();
}

/// The wish is stored; [access] tells how the attempt to get the access and to
/// compare ended.
final class HealthEnabled extends HealthEnableResult {
  const HealthEnabled(this.access);

  final HealthAccessResult access;
}

/// Switches the comparison with the health interface on and off, asks for the
/// access, and runs the comparison (the three triggers and the action).
///
/// The wish lives in the settings (`health_steps_sync_enabled`) and is the
/// only thing a backup carries; what the device allows is always asked from
/// the interface. The controller keeps the last answer ([HealthStepsRuntime])
/// and publishes it together with the wish as `healthStepsStatusProvider`.
class HealthStepsController extends Notifier<HealthStepsRuntime> {
  Future<HealthSyncOutcome>? _running;
  Future<void>? _reading;

  @override
  HealthStepsRuntime build() {
    // A backup import or a reset replaces everything, including the wish: what
    // the device allows must be read again for the new wish.
    ref.listen<int>(dataEpochProvider, (previous, next) {
      state = const HealthStepsRuntime();
      unawaited(_refreshWhenEnabled());
    });
    return const HealthStepsRuntime();
  }

  HealthStepsSource get _source => ref.read(healthStepsSourceProvider);

  /// The wish as stored right now (read from the database: the settings
  /// stream may not have delivered a change that was just written).
  Future<bool> _enabled() async =>
      (await ref.read(appSettingsRepositoryProvider).get())
          ?.healthStepsSyncEnabled ??
      false;

  // ----------------------------------------------------------------- status

  Future<void> _refreshWhenEnabled() async {
    if (await _enabled() && ref.mounted) {
      await refreshStatus();
    }
  }

  /// Reads what the interface says (available? access?) once, when nothing is
  /// known yet. The switch in the settings asks for it when it appears; with
  /// the switch off nothing asks the device before that.
  Future<void> ensureStatus() {
    if (state.availability != null) {
      return Future<void>.value();
    }
    return refreshStatus();
  }

  /// Reads what the interface says (available? access?). Never shows a dialog
  /// and never reads steps. Never throws.
  Future<void> refreshStatus() {
    final running = _reading;
    if (running != null) {
      return running;
    }
    final attempt = _refresh();
    _reading = attempt;
    return attempt.whenComplete(() => _reading = null);
  }

  Future<void> _refresh() async {
    try {
      final availability = await _source.availability();
      HealthAccess? access;
      if (availability == HealthAvailability.available) {
        access = await _source.access();
      }
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        availability: () => availability,
        access: () => access,
      );
    } on Object catch (error) {
      debugPrint('health state not readable: ${error.runtimeType}');
    }
  }

  // -------------------------------------------------------------- comparison

  /// Compares the steps of the last seven days with the health interface
  /// ([HealthStepsSync.reconcile]). A call while a comparison runs joins it.
  /// Never throws.
  Future<HealthSyncOutcome> reconcile(HealthSyncTrigger trigger) {
    final running = _running;
    if (running != null) {
      return running;
    }
    final run = _reconcile(trigger);
    _running = run;
    return run.whenComplete(() => _running = null);
  }

  Future<HealthSyncOutcome> _reconcile(HealthSyncTrigger trigger) async {
    if (!await _enabled()) {
      // Nothing to do; the state of the interface stays as it is.
      return const HealthSyncOutcome(HealthSyncKind.off);
    }
    if (!ref.mounted) {
      return const HealthSyncOutcome(HealthSyncKind.off);
    }
    state = state.copyWith(syncing: true);
    final outcome = await ref.read(healthStepsSyncProvider).reconcile(trigger);
    if (ref.mounted) {
      state = _after(outcome);
    }
    return outcome;
  }

  HealthStepsRuntime _after(HealthSyncOutcome outcome) {
    switch (outcome.kind) {
      case HealthSyncKind.off:
      case HealthSyncKind.moduleOff:
        return state.copyWith(syncing: false, failed: false);
      case HealthSyncKind.failed:
        return state.copyWith(syncing: false, failed: true);
      case HealthSyncKind.synced:
      case HealthSyncKind.unsupported:
      case HealthSyncKind.interfaceMissing:
      case HealthSyncKind.interfaceOutdated:
      case HealthSyncKind.accessMissing:
        return HealthStepsRuntime(
          availability: outcome.availability,
          access: outcome.access,
        );
    }
  }

  // ----------------------------------------------------------------- switch

  /// Switches the comparison on: stores the wish, asks the device for the
  /// access when it is missing (the explanation was shown before; this is the
  /// call that shows the system dialog), and compares the last seven days. The
  /// wish stays on when the access or the interface is missing: the screens
  /// then show that state with its way out.
  Future<HealthEnableResult> enable() async {
    try {
      await ref
          .read(settingsCommandsProvider)
          .setHealthStepsSyncEnabled(
            commandId: ref.read(idGeneratorProvider).newId(),
            value: true,
          );
    } on AppFailure {
      return const HealthEnableStorageFailed();
    }
    return HealthEnabled(await _askAndCompare(HealthSyncTrigger.enable));
  }

  /// "Zugriff erlauben": asks the device for the access (the system dialog)
  /// and compares when it was given.
  Future<HealthAccessResult> allowAccess() =>
      _askAndCompare(HealthSyncTrigger.action);

  Future<HealthAccessResult> _askAndCompare(HealthSyncTrigger trigger) async {
    try {
      final availability = await _source.availability();
      if (availability != HealthAvailability.available) {
        if (ref.mounted) {
          state = state.copyWith(
            availability: () => availability,
            access: () => null,
          );
        }
        return switch (availability) {
          HealthAvailability.missing => HealthAccessResult.interfaceMissing,
          HealthAvailability.updateRequired =>
            HealthAccessResult.interfaceOutdated,
          _ => HealthAccessResult.unsupported,
        };
      }
      var access = await _source.access();
      if (access != HealthAccess.granted) {
        access = await _source.requestAccess();
      }
      if (ref.mounted) {
        state = state.copyWith(
          availability: () => availability,
          access: () => access,
        );
      }
      if (access != HealthAccess.granted) {
        return HealthAccessResult.accessDenied;
      }
      final outcome = await reconcile(trigger);
      return outcome.kind == HealthSyncKind.synced
          ? HealthAccessResult.synced
          : HealthAccessResult.failed;
    } on Object catch (error) {
      debugPrint('health access not obtained: ${error.runtimeType}');
      return HealthAccessResult.failed;
    }
  }

  /// Switches the comparison off. The values that were taken over stay; the
  /// access itself stays in the system until the user takes it away there.
  /// Returns false when the wish could not be stored.
  Future<bool> disable() async {
    try {
      await ref
          .read(settingsCommandsProvider)
          .setHealthStepsSyncEnabled(
            commandId: ref.read(idGeneratorProvider).newId(),
            value: false,
          );
      return true;
    } on AppFailure {
      return false;
    }
  }

  // ------------------------------------------------------------ system pages

  /// Opens the place where the interface is installed or updated.
  Future<bool> openInstallPage() async {
    try {
      return await _source.openInstallPage();
    } on Object {
      return false;
    }
  }

  /// Opens the system place where the access to the steps can be allowed.
  Future<bool> openAccessSettings() async {
    try {
      return await _source.openAccessSettings();
    } on Object {
      return false;
    }
  }
}

/// The comparison itself (plain class, no state).
final healthStepsSyncProvider = Provider<HealthStepsSync>(
  (ref) => HealthStepsSync(
    source: ref.watch(healthStepsSourceProvider),
    steps: ref.watch(stepsRepositoryProvider),
    settings: ref.watch(appSettingsRepositoryProvider),
    settingsCommands: ref.watch(settingsCommandsProvider),
    modules: ref.watch(moduleStatusRepositoryProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);

/// Controller of the comparison; see [HealthStepsController].
final healthStepsControllerProvider =
    NotifierProvider<HealthStepsController, HealthStepsRuntime>(
      HealthStepsController.new,
    );

/// The wish, the answer of the device and the running state in one model.
final healthStepsStatusProvider = Provider<HealthStepsStatus>((ref) {
  final settings = ref.watch(appSettingsProvider).value;
  final runtime = ref.watch(healthStepsControllerProvider);
  final bodyEnabled =
      ref.watch(moduleStatusesProvider).value?[ModuleId.body] ?? true;
  return HealthStepsStatus(
    enabled: settings?.healthStepsSyncEnabled ?? false,
    bodyEnabled: bodyEnabled,
    sourceName: ref.watch(healthStepsSourceProvider).displayName,
    availability: runtime.availability,
    access: runtime.access,
    syncing: runtime.syncing,
    failed: runtime.failed,
    lastSyncAtUtc: settings?.healthStepsLastSyncAtUtc,
  );
});

/// The three triggers of the comparison: the app starts, the app comes back to
/// the foreground, and (not here) the user asks for it. The third one is
/// `HealthStepsController.reconcile` with [HealthSyncTrigger.action], called by
/// the "Aktualisieren" button.
///
/// Nothing is read while the switch is off; every trigger then ends at once.
final class HealthStepsAutoSync with WidgetsBindingObserver {
  HealthStepsAutoSync({required this._reconcile});

  final Future<HealthSyncOutcome> Function(HealthSyncTrigger trigger)
  _reconcile;
  bool _attached = false;

  /// Starts observing the app lifecycle and runs the comparison for the start
  /// of the app. Idempotent.
  void start() {
    if (_attached) {
      return;
    }
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_reconcile(HealthSyncTrigger.start));
  }

  /// Stops observing.
  void dispose() {
    if (!_attached) {
      return;
    }
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reconcile(HealthSyncTrigger.resume));
    }
  }
}

/// Starts the triggers "start" and "resume". Read it once at the app root
/// after the start (needs the widgets binding).
final healthStepsAutoSyncProvider = Provider<HealthStepsAutoSync>((ref) {
  final controller = ref.read(healthStepsControllerProvider.notifier);
  final autoSync = HealthStepsAutoSync(reconcile: controller.reconcile)
    ..start();
  ref.onDispose(autoSync.dispose);
  return autoSync;
});
