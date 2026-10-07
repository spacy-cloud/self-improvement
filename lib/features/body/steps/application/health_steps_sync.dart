import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/health/domain/health_day_range.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_status_repository.dart';
import 'package:self_improvement/core/settings/app_settings_repository.dart';
import 'package:self_improvement/core/settings/settings_commands.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/body/steps/data/steps_repository.dart';
import 'package:self_improvement/features/body/steps/domain/step_source.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Why a comparison with the health interface runs.
enum HealthSyncTrigger {
  /// The app started.
  start,

  /// The app came back to the foreground.
  resume,

  /// The user asked for it ("Aktualisieren") or allowed the access.
  action,

  /// The switch "Schritte aus Health übernehmen" was just switched on (the
  /// first comparison reloads the last seven days).
  enable,
}

/// How a comparison ended.
enum HealthSyncKind {
  /// The steps of the last days were read and compared (possibly nothing had
  /// to be written).
  synced,

  /// The switch is off: nothing was read.
  off,

  /// The module "Gewicht & Körper" is off: nothing was read and nothing
  /// changes while the steps are hidden.
  moduleOff,

  /// The device has no health interface the app supports.
  unsupported,

  /// The app of the interface is not installed.
  interfaceMissing,

  /// The app of the interface is installed but too old.
  interfaceOutdated,

  /// The interface is there, but the app may not read the steps (never asked,
  /// refused, taken away later, or the switch came from an imported backup).
  accessMissing,

  /// The comparison failed for a technical reason; nothing was written.
  failed,
}

/// The result of one comparison.
@immutable
final class HealthSyncOutcome {
  const HealthSyncOutcome(
    this.kind, {
    this.applied = HealthApplyResult.none,
    this.availability,
    this.access,
  });

  final HealthSyncKind kind;

  /// What was written (only for [HealthSyncKind.synced]).
  final HealthApplyResult applied;

  /// What the comparison learned about the interface, null when it did not
  /// ask.
  final HealthAvailability? availability;
  final HealthAccess? access;

  @override
  String toString() => 'HealthSyncOutcome(${kind.name}, $applied)';
}

/// Compares the steps of the last seven local days with the health interface
/// and writes them as step days (decision D-032).
///
/// One run:
///
/// 1. Nothing happens while the switch is off or the module "Gewicht &
///    Körper" is off.
/// 2. The interface must be available and the access granted; otherwise the
///    run ends with that state and writes nothing. No dialog is shown here.
/// 3. For each of the last [healthSyncDays] local days (today and the six days
///    before, in the zone of the device) the AGGREGATED total of that calendar
///    day is asked for. The app never reads records and never adds up several
///    values itself: the interface merges its sources.
/// 4. All totals are read first. If one read fails, nothing is written and the
///    time of the last comparison stays.
/// 5. `StepsRepository.applyHealthTotals` applies the conflict rule in one
///    command: a value the user typed in always wins, a day without a value
///    gets the total, a value of the interface is updated, "no data" changes
///    nothing.
/// 6. The time of the last comparison is stored (to the minute).
///
/// Nothing in here throws: every failure ends as a typed
/// [HealthSyncKind.failed] and is logged by its type only (never by its
/// message, which can contain values).
class HealthStepsSync {
  HealthStepsSync({
    required this._source,
    required this._steps,
    required this._settings,
    required this._settingsCommands,
    required this._modules,
    required this._clock,
    required this._ids,
  });

  final HealthStepsSource _source;
  final StepsRepository _steps;
  final AppSettingsRepository _settings;
  final SettingsCommands _settingsCommands;
  final ModuleStatusRepository _modules;
  final ClockService _clock;
  final IdGenerator _ids;

  /// Runs one comparison for [trigger]. The trigger only names the reason; the
  /// run is the same for every trigger.
  Future<HealthSyncOutcome> reconcile(HealthSyncTrigger trigger) async {
    try {
      return await _reconcile();
    } on Object catch (error) {
      // Log only the type: messages can contain values.
      debugPrint(
        'health comparison (${trigger.name}) failed: '
        '${error.runtimeType}',
      );
      return const HealthSyncOutcome(HealthSyncKind.failed);
    }
  }

  Future<HealthSyncOutcome> _reconcile() async {
    if (!await _wanted()) {
      return const HealthSyncOutcome(HealthSyncKind.off);
    }
    if (!await _modules.isEnabled(ModuleId.body)) {
      return const HealthSyncOutcome(HealthSyncKind.moduleOff);
    }
    final availability = await _source.availability();
    final unavailable = switch (availability) {
      HealthAvailability.available => null,
      HealthAvailability.missing => HealthSyncKind.interfaceMissing,
      HealthAvailability.updateRequired => HealthSyncKind.interfaceOutdated,
      HealthAvailability.unsupported => HealthSyncKind.unsupported,
    };
    if (unavailable != null) {
      return HealthSyncOutcome(unavailable, availability: availability);
    }
    final access = await _source.access();
    if (access != HealthAccess.granted) {
      return HealthSyncOutcome(
        HealthSyncKind.accessMissing,
        availability: availability,
        access: access,
      );
    }

    final totals = <LocalDate, int?>{};
    try {
      for (final range in healthSyncWindow(_clock)) {
        totals[range.day] = await _source.totalSteps(
          startUtc: range.startUtc,
          endUtc: range.endUtc,
        );
      }
    } on HealthStepsException catch (error) {
      if (error.kind == HealthFailureKind.accessDenied) {
        // The access was taken away between the check and the read.
        return HealthSyncOutcome(
          HealthSyncKind.accessMissing,
          availability: availability,
          access: HealthAccess.denied,
        );
      }
      rethrow;
    }

    // The switch may have been turned off while the interface was read.
    if (!await _wanted()) {
      return const HealthSyncOutcome(HealthSyncKind.off);
    }
    final applied = await _steps.applyHealthTotals(
      commandId: _ids.newId(),
      totals: totals,
    );
    await _storeFinishTime();
    return HealthSyncOutcome(
      HealthSyncKind.synced,
      applied: applied,
      availability: availability,
      access: access,
    );
  }

  Future<bool> _wanted() async =>
      (await _settings.get())?.healthStepsSyncEnabled ?? false;

  /// Stores when this comparison finished; a comparison in the same minute as
  /// the stored one writes nothing (the time is shown to the minute).
  Future<void> _storeFinishTime() async {
    final now = SettingsCommands.minuteOf(_clock.nowUtc());
    final stored = (await _settings.get())?.healthStepsLastSyncAtUtc;
    if (stored != null && SettingsCommands.minuteOf(stored) == now) {
      return;
    }
    try {
      await _settingsCommands.setHealthStepsLastSyncAt(
        commandId: _ids.newId(),
        atUtc: now,
      );
    } on AppFailure catch (failure) {
      // The values are stored; only the display of the time is missing.
      debugPrint('last comparison time not stored: ${failure.runtimeType}');
    }
  }
}
