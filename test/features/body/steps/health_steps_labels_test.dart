import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/features/body/steps/domain/health_steps_status.dart';
import 'package:self_improvement/features/body/steps/presentation/health_steps_labels.dart';

/// The state of the Health comparison and its German texts (BS-97): which
/// state a combination of wish, device answer and run is, and what each state
/// says.
void main() {
  setUpAll(TimeZones.ensureInitialized);

  HealthStepsStatus status({
    bool enabled = true,
    bool bodyEnabled = true,
    HealthAvailability? availability = HealthAvailability.available,
    HealthAccess? access = HealthAccess.granted,
    bool syncing = false,
    bool failed = false,
    DateTime? last,
    String name = 'Health Connect',
  }) => HealthStepsStatus(
    enabled: enabled,
    bodyEnabled: bodyEnabled,
    sourceName: name,
    availability: availability,
    access: access,
    syncing: syncing,
    failed: failed,
    lastSyncAtUtc: last,
  );

  group('the state (HealthStepsStatus.condition)', () {
    test('every combination of the wish, the device and the run (BS-97)', () {
      final table = <(HealthStepsStatus, HealthStepsCondition, String)>[
        (status(bodyEnabled: false), HealthStepsCondition.hidden, 'module off'),
        (
          status(availability: HealthAvailability.unsupported),
          HealthStepsCondition.hidden,
          'no interface',
        ),
        (
          status(availability: HealthAvailability.unsupported, enabled: false),
          HealthStepsCondition.hidden,
          'no interface, switch off',
        ),
        (
          status(enabled: false, availability: null, access: null),
          HealthStepsCondition.hidden,
          'switch off, not asked',
        ),
        (
          status(availability: null, access: null),
          HealthStepsCondition.unknown,
          'switch on, not asked',
        ),
        (
          status(enabled: false),
          HealthStepsCondition.off,
          'switch off, interface there',
        ),
        (
          status(enabled: false, availability: HealthAvailability.missing),
          HealthStepsCondition.off,
          'switch off, interface missing',
        ),
        (
          status(availability: HealthAvailability.missing, access: null),
          HealthStepsCondition.interfaceMissing,
          'interface missing',
        ),
        (
          status(availability: HealthAvailability.updateRequired, access: null),
          HealthStepsCondition.interfaceOutdated,
          'interface outdated',
        ),
        (
          status(access: HealthAccess.denied),
          HealthStepsCondition.accessMissing,
          'no access',
        ),
        (
          status(access: HealthAccess.denied, failed: true),
          HealthStepsCondition.accessMissing,
          'no access wins over a failure',
        ),
        (status(access: null), HealthStepsCondition.unknown, 'no answer'),
        (status(), HealthStepsCondition.ready, 'ready'),
        (status(syncing: true), HealthStepsCondition.ready, 'running'),
        (status(failed: true), HealthStepsCondition.failed, 'last run failed'),
      ];
      for (final (value, expected, name) in table) {
        expect(value.condition, expected, reason: name);
      }
    });

    test('visible and reading follow the state (BS-97)', () {
      expect(status().visible, isTrue);
      expect(status(bodyEnabled: false).visible, isFalse);
      expect(
        status(availability: HealthAvailability.unsupported).visible,
        isFalse,
      );
      expect(status().reading, isTrue);
      expect(status(failed: true).reading, isTrue);
      expect(status(access: HealthAccess.denied).reading, isFalse);
      expect(status(enabled: false).reading, isFalse);
    });

    test('equal values are equal (BS-97)', () {
      expect(status(), status());
      expect(status().hashCode, status().hashCode);
      expect(status(), isNot(status(syncing: true)));
      expect(status(), isNot(status(last: DateTime.utc(2026))));
    });
  });

  group('times', () {
    final clock = FakeClock.at('2026-10-03T08:00:00Z'); // 10:00 in Berlin

    test('today, yesterday, a weekday-free short date, with a year when it '
        'differs (BS-97)', () {
      expect(
        healthTimeText(DateTime.utc(2026, 10, 3, 7, 41), clock),
        'heute, 09:41',
      );
      expect(
        healthTimeText(DateTime.utc(2026, 10, 2, 19, 10), clock),
        'gestern, 21:10',
      );
      expect(
        healthTimeText(DateTime.utc(2026, 9, 14, 7, 41), clock),
        'Mo., 14. Sep., 09:41',
      );
      expect(
        healthTimeText(DateTime.utc(2025, 12, 31, 22, 5), clock),
        'Mi., 31. Dez. 2025, 23:05',
      );
    });

    test('the clock zone decides which day it was (AT25)', () {
      final other = FakeClock.at(
        '2026-10-03T08:00:00Z',
        timeZoneId: 'America/New_York',
      );
      // 23:30 UTC on the 2nd is the 3rd in Berlin but still the 2nd in New
      // York, where it is 04:00 on the 3rd: "gestern".
      expect(
        healthTimeText(DateTime.utc(2026, 10, 2, 23, 30), other),
        'gestern, 19:30',
      );
      expect(
        healthTimeText(DateTime.utc(2026, 10, 2, 23, 30), clock),
        'heute, 01:30',
      );
    });
  });

  group('lines and subtitles', () {
    final clock = FakeClock.at('2026-10-03T08:00:00Z');
    final last = DateTime.utc(2026, 10, 3, 7, 41);

    test('the source card says when it was compared or what happens '
        '(BS-97)', () {
      expect(
        healthSourceLine(status(last: last), clock),
        'Zuletzt: heute, 09:41',
      );
      expect(healthSourceLine(status(), clock), 'Noch nicht abgeglichen');
      expect(
        healthSourceLine(status(syncing: true, last: last), clock),
        'Wird abgeglichen …',
      );
      expect(
        healthSourceLine(status(failed: true, last: last), clock),
        'Abgleich fehlgeschlagen',
      );
    });

    test('the card on Home shows the time of today without the word '
        '(BS-97)', () {
      expect(healthCardSourceText(status(last: last), clock), 'Health · 09:41');
      expect(
        healthCardSourceText(
          status(last: DateTime.utc(2026, 10, 2, 19, 10)),
          clock,
        ),
        'Health · gestern, 21:10',
      );
      expect(
        healthCardSourceText(status(), clock),
        'Health · noch nicht abgeglichen',
      );
      expect(
        healthCardSourceText(status(syncing: true), clock),
        'Health · wird abgeglichen …',
      );
      expect(
        healthCardSourceText(status(failed: true), clock),
        'Health · Abgleich fehlgeschlagen',
      );
    });

    test('the subtitle of the switch in every state (BS-97)', () {
      final table = <(HealthStepsStatus, String)>[
        (status(enabled: false), 'Nur lesen, nur Schritte'),
        (status(availability: null, access: null), 'Nur lesen, nur Schritte'),
        (status(), 'Noch nicht abgeglichen'),
        (status(last: last), 'Zuletzt abgeglichen: heute, 09:41'),
        (status(syncing: true, last: last), 'Wird abgeglichen …'),
        (status(failed: true), 'Abgleich fehlgeschlagen'),
        (
          status(access: HealthAccess.denied),
          'Kein Zugriff auf Health Connect',
        ),
        (
          status(availability: HealthAvailability.missing, access: null),
          'Health Connect ist nicht installiert',
        ),
        (
          status(availability: HealthAvailability.updateRequired, access: null),
          'Health Connect ist veraltet',
        ),
      ];
      for (final (value, text) in table) {
        expect(healthSettingsSubtitle(value, clock), text);
      }
    });

    test('the name of the interface comes from the status, so another '
        'adapter brings its own (BS-97)', () {
      expect(
        healthSettingsSubtitle(
          status(access: HealthAccess.denied, name: 'Apple Health'),
          clock,
        ),
        'Kein Zugriff auf Apple Health',
      );
    });
  });

  group('the notices and the card warning (frames 4122:667, 4122:777)', () {
    test('no access: the text of the design and both ways out (BS-97)', () {
      final notice = HealthNotice.of(status(access: HealthAccess.denied))!;
      expect(notice.title, 'Kein Zugriff auf Health Connect');
      expect(
        notice.text,
        'Die Schritte werden nicht übernommen. Erlaube den Zugriff auf '
        'Schritte in den Systemeinstellungen.',
      );
      expect(notice.buttons.map((button) => button.action), [
        HealthNoticeAction.allowAccess,
        HealthNoticeAction.openSettings,
      ]);
      expect(notice.buttons.map((button) => button.label), [
        'Zugriff erlauben',
        'Einstellungen öffnen',
      ]);
    });

    test('interface missing and outdated: the text of the design and the '
        'way to the store (BS-97)', () {
      final missing = HealthNotice.of(
        status(availability: HealthAvailability.missing, access: null),
      )!;
      expect(missing.title, 'Health Connect ist nicht installiert');
      expect(
        missing.text,
        'Installiere Health Connect, um Schritte zu übernehmen. Bis dahin '
        'trägst du Schritte weiter von Hand ein.',
      );
      expect(missing.buttons.single.label, 'Health Connect installieren');
      expect(missing.buttons.single.action, HealthNoticeAction.openInstallPage);

      final outdated = HealthNotice.of(
        status(availability: HealthAvailability.updateRequired, access: null),
      )!;
      expect(outdated.title, 'Health Connect ist veraltet');
      expect(outdated.buttons.single.label, 'Health Connect aktualisieren');
      expect(
        outdated.buttons.single.action,
        HealthNoticeAction.openInstallPage,
      );
    });

    test('a failed run offers to repeat it (BS-97)', () {
      final notice = HealthNotice.of(status(failed: true))!;
      expect(notice.title, 'Abgleich fehlgeschlagen');
      expect(notice.buttons.single.action, HealthNoticeAction.retry);
    });

    test('ready, off, hidden and unknown have no notice (BS-97)', () {
      expect(HealthNotice.of(status()), isNull);
      expect(HealthNotice.of(status(enabled: false)), isNull);
      expect(HealthNotice.of(status(bodyEnabled: false)), isNull);
      expect(HealthNotice.of(status(availability: null, access: null)), isNull);
    });

    test('the card warning and its action (frame 4123:472)', () {
      expect(
        healthCardWarning(status(access: HealthAccess.denied)),
        'Health: kein Zugriff',
      );
      expect(
        healthCardWarningAction(status(access: HealthAccess.denied))?.label,
        'Zugriff erlauben',
      );
      expect(
        healthCardWarning(
          status(availability: HealthAvailability.missing, access: null),
        ),
        'Health Connect fehlt',
      );
      expect(
        healthCardWarningAction(
          status(availability: HealthAvailability.missing, access: null),
        )?.label,
        'Health Connect installieren',
      );
      expect(
        healthCardWarning(
          status(availability: HealthAvailability.updateRequired, access: null),
        ),
        'Health Connect veraltet',
      );
      expect(healthCardWarning(status()), isNull);
      expect(healthCardWarning(status(failed: true)), isNull);
      expect(healthCardWarningAction(status()), isNull);
    });

    test('no text names a platform, and every text is in German with real '
        'umlauts (BS-97)', () {
      final texts = <String>[];
      for (final value in [
        status(access: HealthAccess.denied),
        status(availability: HealthAvailability.missing, access: null),
        status(availability: HealthAvailability.updateRequired, access: null),
        status(failed: true),
        status(),
        status(enabled: false),
      ]) {
        final notice = HealthNotice.of(value);
        if (notice != null) {
          texts
            ..add(notice.title)
            ..add(notice.text)
            ..addAll(notice.buttons.map((button) => button.label))
            ..addAll(
              notice.buttons.map((button) => button.semanticLabel ?? ''),
            );
        }
        texts
          ..add(
            healthSettingsSubtitle(value, FakeClock.at('2026-10-03T08:00:00Z')),
          )
          ..add(healthCardWarning(value) ?? '')
          ..add(healthRefreshLabel(value));
      }
      texts
        ..add(healthDayNoticeText)
        ..add(healthDeleteRefillText)
        ..add(healthDayNoticeTitle(existing: '7.450', when: 'heute'));
      final all = texts.join('\n');
      for (final platform in ['Android', 'iOS', 'HealthKit', 'Google']) {
        expect(all, isNot(contains(platform)), reason: platform);
      }
      // Real umlauts, never the ASCII replacements of the typical words.
      for (final ascii in ['uebernehmen', 'Schluessel', 'fuer ', 'aendert']) {
        expect(all, isNot(contains(ascii)), reason: ascii);
      }
      expect(all, contains('übernommen'));
    });

    test('the refresh label names the interface (BS-97)', () {
      expect(
        healthRefreshLabel(status()),
        'Schritte aus Health Connect aktualisieren',
      );
    });

    test('the sentences of the form (BS-97)', () {
      expect(
        healthDayNoticeTitle(existing: '7.450', when: 'heute'),
        'Für heute sind schon 7.450 aus Health eingetragen',
      );
      expect(
        healthDayNoticeText,
        'Wenn du speicherst, gilt dein Wert: Health ändert diesen Tag danach '
        'nicht mehr.',
      );
      expect(healthDeleteRefillText, contains('trägt Health den Tag'));
    });
  });
}
