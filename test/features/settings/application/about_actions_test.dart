import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/features/settings/application/about_actions.dart';
import 'package:self_improvement/features/settings/application/about_info.dart';
import 'package:self_improvement/features/settings/application/external_link_opener.dart';
import 'package:url_launcher/url_launcher.dart';

import '../support/about_support.dart';

const String websiteUrl = 'https://spacy.cloud/self-improvement';

ProviderContainer containerWith(FakeExternalLinkOpener opener) {
  final container = ProviderContainer(
    overrides: [externalLinkOpenerProvider.overrideWithValue(opener)],
  );
  addTearDown(container.dispose);
  return container;
}

/// Records the calls of the platform channel of `url_launcher` and answers with
/// [answer]; with [fail] it answers with a platform error, with [missing] like
/// a device on which the plugin is not registered. The platform code of the
/// plugin is not part of a host test; this channel is where the package talks
/// to it.
List<MethodCall> recordLauncherChannel(
  WidgetTester tester, {
  Object? answer = true,
  bool fail = false,
  bool missing = false,
}) {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    call,
  ) async {
    calls.add(call);
    if (missing) {
      throw MissingPluginException();
    }
    if (fail) {
      throw PlatformException(code: 'NO_ACTIVITY');
    }
    return answer;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
  return calls;
}

void main() {
  group('AboutInfo', () {
    test('puts the constants into words like the draft (BS-118)', () {
      expect(
        AboutInfo.versionLine(version: '0.2.0', build: 2),
        'Version 0.2.0 (Build 2)',
      );
      expect(
        AboutInfo.technicalLine(schema: 2, backup: 2),
        'Daten-Schema 2 · Backup-Format 2',
      );
      expect(
        AboutInfo.technicalSpoken(schema: 2, backup: 2),
        'Daten-Schema 2, Backup-Format 2',
      );
      expect(
        AboutInfo.versionRowLabel(version: '0.2.0'),
        'Version 0.2.0, Details öffnen',
      );
    });

    test('reads version, build and schema versions from the constants, they '
        'are not typed in (BS-118)', () {
      expect(
        AboutInfo.versionLine(),
        'Version ${AppConfig.appVersion} (Build ${AppConfig.buildNumber})',
      );
      expect(
        AboutInfo.technicalLine(),
        'Daten-Schema ${AppDatabase.currentSchemaVersion} · '
        'Backup-Format ${BackupFormat.schemaVersion}',
      );
      expect(
        AboutInfo.technicalSpoken(),
        'Daten-Schema ${AppDatabase.currentSchemaVersion}, '
        'Backup-Format ${BackupFormat.schemaVersion}',
      );
      expect(
        AboutInfo.versionRowLabel(),
        'Version ${AppConfig.appVersion}, Details öffnen',
      );
    });

    test('the author is the company and the website is its product page', () {
      expect(AboutInfo.author, 'Spacy.cloud');
      expect(AboutInfo.websiteUrl, websiteUrl);
      expect(Uri.parse(AboutInfo.websiteUrl).scheme, 'https');
      expect(
        AboutInfo.websiteUrl,
        'https://${AboutInfo.websiteLabel}',
        reason: 'the label is the address without the scheme',
      );
    });
  });

  group('AboutActions.openWebsite', () {
    testWidgets(
      'hands the address to the browser and copies nothing (BS-118)',
      (tester) async {
        final opener = FakeExternalLinkOpener();
        final clipboard = recordClipboard(tester);
        final actions = containerWith(opener).read(aboutActionsProvider);

        expect(await actions.openWebsite(), WebsiteOutcome.opened);
        expect(opener.opened, [Uri.parse(websiteUrl)]);
        expect(clipboard.texts, isEmpty);
      },
    );

    testWidgets('copies the address when no browser takes it (BS-118)', (
      tester,
    ) async {
      final opener = FakeExternalLinkOpener(result: false);
      final clipboard = recordClipboard(tester);
      final actions = containerWith(opener).read(aboutActionsProvider);

      expect(await actions.openWebsite(), WebsiteOutcome.copied);
      expect(opener.opened, [Uri.parse(websiteUrl)]);
      expect(clipboard.texts, [websiteUrl]);
    });

    testWidgets('reports a failure when the address cannot be copied either', (
      tester,
    ) async {
      final opener = FakeExternalLinkOpener(result: false);
      final clipboard = recordClipboard(tester, refuse: true);
      final actions = containerWith(opener).read(aboutActionsProvider);

      expect(await actions.openWebsite(), WebsiteOutcome.failed);
      expect(clipboard.texts, isEmpty);
    });

    testWidgets('ignores a tap while the previous one is still running', (
      tester,
    ) async {
      final opener = FakeExternalLinkOpener(hold: true);
      recordClipboard(tester);
      final actions = containerWith(opener).read(aboutActionsProvider);

      final first = actions.openWebsite();
      expect(await actions.openWebsite(), WebsiteOutcome.busy);
      expect(opener.opened, hasLength(1), reason: 'the second tap did nothing');

      opener.release();
      expect(await first, WebsiteOutcome.opened);

      opener.hold = false;
      expect(await actions.openWebsite(), WebsiteOutcome.opened);
      expect(opener.opened, hasLength(2), reason: 'a later tap works again');
    });
  });

  group('UrlLauncherExternalLinkOpener (the real adapter)', () {
    final uri = Uri.parse(websiteUrl);

    testWidgets(
      'launches the address in the external browser, not in a web view '
      '(BS-118)',
      (tester) async {
        final calls = recordLauncherChannel(tester);

        final opened = await const UrlLauncherExternalLinkOpener().open(uri);

        expect(opened, isTrue);
        expect(calls, hasLength(1));
        expect(calls.single.method, 'launch');
        final arguments = calls.single.arguments as Map<Object?, Object?>;
        expect(arguments['url'], websiteUrl);
        expect(arguments['useWebView'], isFalse, reason: 'no web view');
        expect(arguments['useSafariVC'], isFalse, reason: 'no in-app browser');
        expect(arguments['universalLinksOnly'], isFalse);
      },
    );

    testWidgets(
      'the default launch mode would open a web view for a web address, so '
      'the explicit external mode is what keeps the browser outside the app',
      (tester) async {
        final calls = recordLauncherChannel(tester);

        await launchUrl(uri);

        final arguments = calls.single.arguments as Map<Object?, Object?>;
        expect(arguments['useWebView'], isTrue);
      },
    );

    testWidgets('does not ask canLaunchUrl first (it needs a manifest query)', (
      tester,
    ) async {
      final calls = recordLauncherChannel(tester);

      await const UrlLauncherExternalLinkOpener().open(uri);

      expect(calls.map((call) => call.method), isNot(contains('canLaunch')));
    });

    testWidgets('answers false when no app can take the address', (
      tester,
    ) async {
      recordLauncherChannel(tester, answer: false);
      expect(await const UrlLauncherExternalLinkOpener().open(uri), isFalse);
    });

    testWidgets('answers false and does not throw on a platform error', (
      tester,
    ) async {
      recordLauncherChannel(tester, fail: true);
      expect(await const UrlLauncherExternalLinkOpener().open(uri), isFalse);
    });

    testWidgets('answers false without a platform implementation', (
      tester,
    ) async {
      // MissingPluginException inside the package: no plugin registered.
      final calls = recordLauncherChannel(tester, missing: true);
      expect(await const UrlLauncherExternalLinkOpener().open(uri), isFalse);
      expect(calls, hasLength(1), reason: 'the call was made');
    });
  });
}
