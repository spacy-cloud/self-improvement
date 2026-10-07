/// German texts of "Schritte aus Health übernehmen" (pure Dart).
///
/// The texts name the interface through its display name (`Health Connect` on
/// Android) and never a platform, so the same words fit a later iOS adapter.
/// Every state says only what the app knows: it never claims a value arrived
/// that did not.
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/body/steps/domain/health_steps_status.dart';
import 'package:self_improvement/shared/german_date.dart';

/// `heute, 09:41`, `gestern, 21:10` or `Mo., 14. Sep., 09:41`: when [utc] was
/// in the zone of [clock].
String healthTimeText(DateTime utc, ClockService clock) {
  final local = clock.toLocal(utc);
  final today = clock.today();
  final daysAgo = local.date.daysUntil(today);
  final time = local.time.toIso();
  if (daysAgo == 0) {
    return 'heute, $time';
  }
  if (daysAgo == 1) {
    return 'gestern, $time';
  }
  return '${formatDateShort(local.date, contextYear: today.year)}, $time';
}

/// The second line of the source card of "Meine Schritte": `Zuletzt: heute,
/// 09:41`, or what is happening instead.
String healthSourceLine(HealthStepsStatus status, ClockService clock) {
  if (status.syncing) {
    return 'Wird abgeglichen …';
  }
  if (status.condition == HealthStepsCondition.failed) {
    return 'Abgleich fehlgeschlagen';
  }
  final last = status.lastSyncAtUtc;
  return last == null
      ? 'Noch nicht abgeglichen'
      : 'Zuletzt: ${healthTimeText(last, clock)}';
}

/// The line of the card on Home: `Health · 09:41` (today shows only the time),
/// `Health · gestern, 21:10`, or what is happening instead.
String healthCardSourceText(HealthStepsStatus status, ClockService clock) {
  if (status.syncing) {
    return 'Health · wird abgeglichen …';
  }
  if (status.condition == HealthStepsCondition.failed) {
    return 'Health · Abgleich fehlgeschlagen';
  }
  final last = status.lastSyncAtUtc;
  if (last == null) {
    return 'Health · noch nicht abgeglichen';
  }
  final text = healthTimeText(last, clock);
  return 'Health · ${text.startsWith('heute, ') ? text.substring(7) : text}';
}

/// The subtitle of the switch in the settings.
String healthSettingsSubtitle(HealthStepsStatus status, ClockService clock) {
  final name = status.sourceName;
  return switch (status.condition) {
    HealthStepsCondition.hidden ||
    HealthStepsCondition.unknown ||
    HealthStepsCondition.off => 'Nur lesen, nur Schritte',
    HealthStepsCondition.ready =>
      status.syncing
          ? 'Wird abgeglichen …'
          : (status.lastSyncAtUtc == null
                ? 'Noch nicht abgeglichen'
                : 'Zuletzt abgeglichen: '
                      '${healthTimeText(status.lastSyncAtUtc!, clock)}'),
    HealthStepsCondition.failed => 'Abgleich fehlgeschlagen',
    HealthStepsCondition.accessMissing => 'Kein Zugriff auf $name',
    HealthStepsCondition.interfaceMissing => '$name ist nicht installiert',
    HealthStepsCondition.interfaceOutdated => '$name ist veraltet',
  };
}

/// One button of a notice.
@immutable
final class HealthNoticeButton {
  const HealthNoticeButton(this.action, this.label, {this.semanticLabel});

  final HealthNoticeAction action;
  final String label;

  /// The spoken text when it differs from [label].
  final String? semanticLabel;
}

/// A notice for a state in which the values of Health do not arrive: the
/// honest explanation and the ways out. The texts follow the design (frames
/// `4122:667` and `4122:777`).
@immutable
final class HealthNotice {
  const HealthNotice({
    required this.title,
    required this.text,
    required this.buttons,
  });

  final String title;
  final String text;
  final List<HealthNoticeButton> buttons;

  /// The notice of [status], or null when there is nothing to say.
  static HealthNotice? of(HealthStepsStatus status) {
    final name = status.sourceName;
    switch (status.condition) {
      case HealthStepsCondition.accessMissing:
        return HealthNotice(
          title: 'Kein Zugriff auf $name',
          text:
              'Die Schritte werden nicht übernommen. Erlaube den Zugriff auf '
              'Schritte in den Systemeinstellungen.',
          buttons: const [
            HealthNoticeButton(
              HealthNoticeAction.allowAccess,
              'Zugriff erlauben',
              semanticLabel: 'Zugriff auf Schritte erlauben',
            ),
            HealthNoticeButton(
              HealthNoticeAction.openSettings,
              'Einstellungen öffnen',
              semanticLabel: 'Systemeinstellungen für den Zugriff öffnen',
            ),
          ],
        );
      case HealthStepsCondition.interfaceMissing:
        return HealthNotice(
          title: '$name ist nicht installiert',
          text:
              'Installiere $name, um Schritte zu übernehmen. Bis dahin '
              'trägst du Schritte weiter von Hand ein.',
          buttons: [
            HealthNoticeButton(
              HealthNoticeAction.openInstallPage,
              '$name installieren',
            ),
          ],
        );
      case HealthStepsCondition.interfaceOutdated:
        return HealthNotice(
          title: '$name ist veraltet',
          text:
              'Aktualisiere $name, um Schritte zu übernehmen. Bis dahin '
              'trägst du Schritte weiter von Hand ein.',
          buttons: [
            HealthNoticeButton(
              HealthNoticeAction.openInstallPage,
              '$name aktualisieren',
            ),
          ],
        );
      case HealthStepsCondition.failed:
        return HealthNotice(
          title: 'Abgleich fehlgeschlagen',
          text:
              'Die Schritte konnten nicht aus $name gelesen werden. Deine '
              'Werte sind unverändert.',
          buttons: const [
            HealthNoticeButton(HealthNoticeAction.retry, 'Erneut versuchen'),
          ],
        );
      case HealthStepsCondition.hidden:
      case HealthStepsCondition.unknown:
      case HealthStepsCondition.off:
      case HealthStepsCondition.ready:
        return null;
    }
  }
}

/// The warning chip on the card on Home for a state in which Health does not
/// deliver (`Health: kein Zugriff`), or null.
String? healthCardWarning(HealthStepsStatus status) {
  final name = status.sourceName;
  return switch (status.condition) {
    HealthStepsCondition.accessMissing => 'Health: kein Zugriff',
    HealthStepsCondition.interfaceMissing => '$name fehlt',
    HealthStepsCondition.interfaceOutdated => '$name veraltet',
    _ => null,
  };
}

/// The button below the warning chip on the card on Home.
HealthNoticeButton? healthCardWarningAction(HealthStepsStatus status) {
  final name = status.sourceName;
  return switch (status.condition) {
    HealthStepsCondition.accessMissing => const HealthNoticeButton(
      HealthNoticeAction.allowAccess,
      'Zugriff erlauben',
      semanticLabel: 'Zugriff auf Schritte erlauben',
    ),
    HealthStepsCondition.interfaceMissing => HealthNoticeButton(
      HealthNoticeAction.openInstallPage,
      '$name installieren',
    ),
    HealthStepsCondition.interfaceOutdated => HealthNoticeButton(
      HealthNoticeAction.openInstallPage,
      '$name aktualisieren',
    ),
    _ => null,
  };
}

/// The spoken label of the refresh button.
String healthRefreshLabel(HealthStepsStatus status) =>
    'Schritte aus ${status.sourceName} aktualisieren';

/// What the day total on the form says about its source.
String healthDayNoticeTitle({required String existing, required String when}) =>
    'Für $when sind schon $existing aus Health eingetragen';

/// The text of the notice for a day that came from Health.
const String healthDayNoticeText =
    'Wenn du speicherst, gilt dein Wert: Health ändert diesen Tag danach '
    'nicht mehr.';

/// The sentence added to the delete confirmation while the switch is on.
const String healthDeleteRefillText =
    ' Solange „Schritte aus Health übernehmen“ an ist, trägt Health den Tag '
    'beim nächsten Abgleich wieder ein, wenn dort Schritte stehen.';
