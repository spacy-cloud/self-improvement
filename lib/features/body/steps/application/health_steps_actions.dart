import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_controller.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_sync.dart';
import 'package:self_improvement/features/body/steps/domain/health_steps_status.dart';

/// What the buttons of the Health comparison do and what they tell the user
/// afterwards (decision D-033): the switch in the settings, the notices and
/// the card use the same actions, so the same state always gets the same
/// words.
///
/// Every message names the interface by its display name and never a
/// platform. A request that cannot be done is said so; nothing is claimed that
/// did not happen.
class HealthStepsActions {
  HealthStepsActions(this._ref);

  final Ref _ref;

  HealthStepsController get _controller =>
      _ref.read(healthStepsControllerProvider.notifier);

  FeedbackService get _feedback => _ref.read(feedbackServiceProvider);

  String get _name => _ref.read(healthStepsStatusProvider).sourceName;

  /// Switches the comparison on (the explanation was shown before): stores the
  /// wish, asks for the access when it is missing and compares.
  Future<void> enable() async {
    final result = await _controller.enable();
    switch (result) {
      case HealthEnableStorageFailed():
        _feedback.showError(
          'Die Einstellung konnte nicht gespeichert werden. Der bisherige '
          'Wert bleibt aktiv.',
          onRetry: () => unawaited(enable()),
        );
      case HealthEnabled(:final access):
        _announceEnabled(access);
    }
  }

  void _announceEnabled(HealthAccessResult access) {
    switch (access) {
      case HealthAccessResult.synced:
        _feedback.showSaved('Schritte aus Health eingeschaltet.');
      case HealthAccessResult.accessDenied:
        _feedback.showInfo(
          'Zugriff nicht erteilt. Die Schritte werden nicht übernommen, bis '
          'du den Zugriff erlaubst.',
        );
      case HealthAccessResult.interfaceMissing:
        _feedback.showInfo(
          '$_name ist nicht installiert. Installiere es, damit Schritte '
          'übernommen werden.',
        );
      case HealthAccessResult.interfaceOutdated:
        _feedback.showInfo(
          '$_name ist veraltet. Aktualisiere es, damit Schritte übernommen '
          'werden.',
        );
      case HealthAccessResult.unsupported:
        _feedback.showInfo(
          'Auf diesem Gerät gibt es keine Schnittstelle für Schritte aus '
          'Health.',
        );
      case HealthAccessResult.failed:
        _feedback.showError(
          'Der Abgleich ist fehlgeschlagen. Deine Werte sind unverändert.',
          onRetry: () => unawaited(refresh()),
        );
    }
  }

  /// Switches the comparison off. The values that were taken over stay.
  Future<void> disable() async {
    if (await _controller.disable()) {
      _feedback.showSaved(
        'Schritte aus Health ausgeschaltet. Bereits übernommene Werte '
        'bleiben.',
      );
    } else {
      _feedback.showError(
        'Die Einstellung konnte nicht gespeichert werden. Der bisherige Wert '
        'bleibt aktiv.',
        onRetry: () => unawaited(disable()),
      );
    }
  }

  /// "Aktualisieren": compares now. A failure is said so; a state that needs
  /// the user (no access, interface missing) is shown by the notices.
  Future<void> refresh() async {
    final outcome = await _controller.reconcile(HealthSyncTrigger.action);
    switch (outcome.kind) {
      case HealthSyncKind.synced:
        _feedback.showInfo('Schritte aus $_name abgeglichen.');
      case HealthSyncKind.failed:
        _feedback.showError(
          'Der Abgleich ist fehlgeschlagen. Deine Werte sind unverändert.',
          onRetry: () => unawaited(refresh()),
        );
      case HealthSyncKind.off:
      case HealthSyncKind.moduleOff:
      case HealthSyncKind.unsupported:
      case HealthSyncKind.interfaceMissing:
      case HealthSyncKind.interfaceOutdated:
      case HealthSyncKind.accessMissing:
        break;
    }
  }

  /// "Zugriff erlauben": shows the system dialog and compares when it was
  /// given.
  Future<void> allowAccess() async {
    final result = await _controller.allowAccess();
    switch (result) {
      case HealthAccessResult.synced:
        _feedback.showSaved('Zugriff erlaubt. Die Schritte werden übernommen.');
      case HealthAccessResult.accessDenied:
        _feedback.showInfo(
          'Zugriff nicht erteilt. Erscheint keine Abfrage mehr, erlaube die '
          'Schritte über „Einstellungen öffnen“.',
        );
      case HealthAccessResult.interfaceMissing:
      case HealthAccessResult.interfaceOutdated:
      case HealthAccessResult.unsupported:
        _announceEnabled(result);
      case HealthAccessResult.failed:
        _feedback.showError(
          'Der Zugriff konnte nicht angefragt werden. Versuche es noch '
          'einmal.',
          onRetry: () => unawaited(allowAccess()),
        );
    }
  }

  /// Opens the page where the interface is installed or updated.
  Future<void> openInstallPage() async {
    if (!await _controller.openInstallPage()) {
      _feedback.showInfo(
        'Der Store konnte nicht geöffnet werden. Installiere oder '
        'aktualisiere $_name über den App-Store deines Geräts.',
      );
    }
  }

  /// Opens the system place where the access can be allowed.
  Future<void> openAccessSettings() async {
    if (!await _controller.openAccessSettings()) {
      _feedback.showInfo(
        'Die Systemeinstellungen konnten nicht geöffnet werden. Erlaube den '
        'Zugriff auf Schritte in den Einstellungen von $_name.',
      );
    }
  }

  /// Runs the action of a notice button.
  Future<void> perform(HealthNoticeAction action) => switch (action) {
    HealthNoticeAction.allowAccess => allowAccess(),
    HealthNoticeAction.openSettings => openAccessSettings(),
    HealthNoticeAction.openInstallPage => openInstallPage(),
    HealthNoticeAction.retry => refresh(),
  };
}

/// The actions of the Health comparison for the screens.
final healthStepsActionsProvider = Provider<HealthStepsActions>(
  HealthStepsActions.new,
);
