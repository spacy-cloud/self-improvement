import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/features/settings/application/external_link_opener.dart';
import 'package:self_improvement/features/settings/application/license_providers.dart';

import '../../../support/pump_app.dart';
import '../../profile/support/screen_env.dart';
import '../support/about_support.dart';

const String websiteUrl = 'https://spacy.cloud/self-improvement';

/// The texts the page is expected to show, built from the constants and not
/// typed in as numbers: the page must follow them when the release changes
/// them (BS-118, BS-98).
final String versionLine =
    'Version ${AppConfig.appVersion} (Build ${AppConfig.buildNumber})';
final String technicalLine =
    'Daten-Schema ${AppDatabase.currentSchemaVersion} · '
    'Backup-Format ${BackupFormat.schemaVersion}';
final String technicalSpoken =
    'Daten-Schema ${AppDatabase.currentSchemaVersion}, '
    'Backup-Format ${BackupFormat.schemaVersion}';

/// A started page together with its environment.
typedef Opened = ({ScreenEnv env, GoRouter router});

Future<Opened> open(
  WidgetTester tester, {
  FakeExternalLinkOpener? opener,
  String location = SettingsRoutes.about,
  Size size = const Size(393, 852),
  double textScale = 1.0,
  AppThemeVariant theme = AppThemeVariant.light,
}) async {
  final env = await createScreenEnv(
    tester,
    overrides: [
      externalLinkOpenerProvider.overrideWithValue(
        opener ?? FakeExternalLinkOpener(),
      ),
      licenseSourceProvider.overrideWithValue(
        () => Stream.fromIterable([
          LicenseEntryWithLineBreaks(['Inter'], 'SIL OPEN FONT LICENSE'),
        ]),
      ),
    ],
  );
  final router = await openScreen(
    tester,
    env,
    location,
    size: size,
    textScale: textScale,
    theme: theme,
  );
  return (env: env, router: router);
}

Future<void> tapRow(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await settle(tester);
}

Future<void> tapBack(WidgetTester tester) async {
  await tester.tap(
    find.byWidgetPredicate(
      (w) => w is AppIconButton && w.semanticLabel == 'Zurück',
    ),
  );
  await settle(tester);
}

/// All texts on the page, one string.
String allTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  group('content', () {
    testWidgets(
      'shows the symbol, name, version with build number, author, website, '
      'privacy note, technical versions and the licences row (BS-118)',
      (tester) async {
        await open(tester);

        expect(find.text('Über die App'), findsOneWidget, reason: 'title');
        expect(find.text('ÜBER DIE APP'), findsOneWidget, reason: 'group');
        expect(
          find.byIcon(Icons.trending_up_rounded),
          findsOneWidget,
          reason: 'app symbol',
        );
        expect(find.text(AppConfig.appName), findsOneWidget);
        expect(find.text(versionLine), findsOneWidget);

        expect(find.text('Autor'), findsOneWidget);
        expect(find.text('Spacy.cloud'), findsOneWidget);
        expect(find.text('Website'), findsOneWidget);
        expect(find.text('spacy.cloud/self-improvement'), findsOneWidget);
        expect(find.text('Datenschutz'), findsOneWidget);
        expect(
          find.text(
            'Alle Daten bleiben auf dem Gerät. Kein Konto, keine Cloud, '
            'keine Telemetrie.',
          ),
          findsOneWidget,
        );
        expect(find.text('Technische Angaben'), findsOneWidget);
        expect(find.text(technicalLine), findsOneWidget);
        expect(find.text('Lizenzen'), findsOneWidget);
        expect(find.text('Lizenzen der verwendeten Pakete'), findsOneWidget);
        await savePng(tester, 'build/profile_shots/about.png');
      },
    );

    testWidgets(
      'names no team, no GitHub address and no web address (BS-118)',
      (tester) async {
        await open(tester);
        final texts = allTexts(tester);
        expect(texts, isNot(contains('IA24')));
        expect(texts.toLowerCase(), isNot(contains('github')));
        expect(texts, isNot(contains('http')), reason: 'shown without scheme');
        expect(find.text('Spacy.cloud'), findsOneWidget, reason: 'the author');
      },
    );

    testWidgets('only the website and the licences rows react (BS-118)', (
      tester,
    ) async {
      await open(tester);
      final tiles = tester.widgetList<EntryListTile>(
        find.byType(EntryListTile),
      );
      expect(tiles.map((tile) => tile.title), [
        'Autor',
        'Website',
        'Datenschutz',
        'Technische Angaben',
        'Lizenzen',
      ]);
      expect(
        [
          for (final tile in tiles)
            if (tile.onTap != null) tile.title,
        ],
        ['Website', 'Lizenzen'],
      );
    });

    testWidgets('lists the website without a scheme and no switches', (
      tester,
    ) async {
      await open(tester);
      expect(find.byType(AppSwitch), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('navigation', () {
    testWidgets(
      'the Version row of the settings opens the page and back returns (BS-118)',
      (tester) async {
        await open(tester, location: SettingsRoutes.settings);
        expect(find.text('Einstellungen'), findsOneWidget);
        await tapRow(tester, 'Version');
        expect(find.text(versionLine), findsOneWidget);
        expect(
          find.text('Einstellungen'),
          findsNothing,
          reason: 'page changed',
        );

        await tapBack(tester);
        expect(find.text('Einstellungen'), findsOneWidget);
        expect(find.text(versionLine), findsNothing);
      },
    );

    testWidgets('Android back returns to the settings (BS-118)', (
      tester,
    ) async {
      await open(tester, location: SettingsRoutes.settings);
      await tapRow(tester, 'Version');
      expect(find.text(versionLine), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Einstellungen'), findsOneWidget);
      expect(find.text(versionLine), findsNothing);
    });

    testWidgets(
      'opened from outside (no page below) back goes to the settings',
      (tester) async {
        final env = await createScreenEnv(tester);
        await pumpRouterApp(
          tester,
          routes: screenRoutes(),
          initialLocation: SettingsRoutes.about,
          container: env.container,
        );
        await settle(tester);
        expect(find.text(versionLine), findsOneWidget);
        await tapBack(tester);
        expect(find.text('Einstellungen'), findsOneWidget);
      },
    );

    testWidgets('the licences row opens the licence page and back returns', (
      tester,
    ) async {
      await open(tester);
      await tapRow(tester, 'Lizenzen');
      expect(find.text('Inter (Schrift)'), findsOneWidget);
      expect(find.text(versionLine), findsNothing);

      await tapBack(tester);
      expect(find.text(versionLine), findsOneWidget);
    });
  });

  group('website', () {
    testWidgets(
      'a tap hands https://spacy.cloud/self-improvement to the browser and '
      'says nothing more (BS-118)',
      (tester) async {
        final opener = FakeExternalLinkOpener();
        final clipboard = recordClipboard(tester);
        final (:env, router: _) = await open(tester, opener: opener);

        await tapRow(tester, 'Website');

        expect(opener.opened, [Uri.parse(websiteUrl)]);
        expect(env.feedback.events, isEmpty);
        expect(clipboard.texts, isEmpty);
        expect(find.text(versionLine), findsOneWidget, reason: 'page stays');
      },
    );

    testWidgets(
      'without a browser the address is copied and a hint is shown (BS-118)',
      (tester) async {
        final opener = FakeExternalLinkOpener(result: false);
        final clipboard = recordClipboard(tester);
        final (:env, router: _) = await open(tester, opener: opener);

        await tapRow(tester, 'Website');

        expect(opener.opened, [Uri.parse(websiteUrl)]);
        expect(clipboard.texts, [websiteUrl]);
        expect(env.feedback.events, hasLength(1));
        expect(env.feedback.last!.kind, 'info');
        expect(
          env.feedback.last!.message,
          'Kein Browser gefunden. Die Adresse spacy.cloud/self-improvement '
          'wurde kopiert.',
        );
      },
    );

    testWidgets(
      'when the address cannot be copied either, the hint names it (BS-118)',
      (tester) async {
        final opener = FakeExternalLinkOpener(result: false);
        final clipboard = recordClipboard(tester, refuse: true);
        final (:env, router: _) = await open(tester, opener: opener);

        await tapRow(tester, 'Website');

        expect(clipboard.texts, isEmpty);
        expect(env.feedback.events, hasLength(1));
        expect(env.feedback.last!.kind, 'info');
        expect(
          env.feedback.last!.message,
          'Die Adresse konnte nicht geöffnet werden: '
          'spacy.cloud/self-improvement',
        );
      },
    );

    testWidgets('a double tap opens the browser once (BS-118)', (tester) async {
      final opener = FakeExternalLinkOpener(hold: true);
      recordClipboard(tester);
      await open(tester, opener: opener);

      await tester.ensureVisible(find.text('Website'));
      await tester.tap(find.text('Website'));
      await tester.tap(find.text('Website'));
      await settle(tester);
      expect(opener.opened, hasLength(1), reason: 'second tap is ignored');

      opener.release();
      await settle(tester);
      await tester.tap(find.text('Website'));
      await settle(tester);
      expect(opener.opened, hasLength(2), reason: 'a later tap works again');
    });

    testWidgets(
      'the answer still reaches the user when the page was left meanwhile '
      '(BS-118)',
      (tester) async {
        final opener = FakeExternalLinkOpener(result: false, hold: true);
        final clipboard = recordClipboard(tester);
        final (:env, router: _) = await open(
          tester,
          opener: opener,
          location: SettingsRoutes.settings,
        );
        await tapRow(tester, 'Version');
        await tapRow(tester, 'Website');
        expect(opener.opened, hasLength(1));

        await tapBack(tester);
        expect(find.text('Einstellungen'), findsOneWidget);
        opener.release();
        await settle(tester);

        expect(clipboard.texts, [websiteUrl]);
        expect(env.feedback.last!.kind, 'info');
      },
    );
  });

  group('accessibility', () {
    testWidgets('rows have spoken labels, the website row is a button (AT34)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester);

      SemanticsNode node(String label) =>
          tester.getSemantics(find.bySemanticsLabel(label));
      bool taps(SemanticsNode n) =>
          n.getSemanticsData().hasAction(SemanticsAction.tap);

      final website = node(
        'Website, spacy.cloud/self-improvement, öffnet im Browser',
      );
      expect(website.flagsCollection.isButton, isTrue);
      expect(taps(website), isTrue);

      final licences = node('Lizenzen der verwendeten Pakete');
      expect(licences.flagsCollection.isButton, isTrue);
      expect(taps(licences), isTrue);

      for (final label in [
        'Autor, Spacy.cloud',
        'Datenschutz, Alle Daten bleiben auf dem Gerät. Kein Konto, keine '
            'Cloud, keine Telemetrie.',
        'Technische Angaben, $technicalSpoken',
      ]) {
        final info = node(label);
        expect(info.flagsCollection.isButton, isFalse, reason: label);
        expect(taps(info), isFalse, reason: label);
      }
      expect(find.bySemanticsLabel('Zurück'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the page has headings: title, app name and group (AT34)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      for (final heading in [
        'Über die App',
        AppConfig.appName,
        'ÜBER DIE APP',
      ]) {
        expect(
          tester
              .getSemantics(find.bySemanticsLabel(heading))
              .flagsCollection
              .isHeader,
          isTrue,
          reason: heading,
        );
      }
      handle.dispose();
    });

    testWidgets('the app symbol is decorative and has no semantics (AT34)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      final symbol = find.ancestor(
        of: find.byIcon(Icons.trending_up_rounded),
        matching: find.byType(ExcludeSemantics),
      );
      expect(symbol, findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Symbol|Logo|Pfeil')), findsNothing);
      handle.dispose();
    });

    testWidgets('the Version row of the settings is a button with its label '
        '(BS-118, AT34)', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, location: SettingsRoutes.settings);
      final row = tester.getSemantics(
        find.bySemanticsLabel(
          'Version ${AppConfig.appVersion}, Details öffnen',
        ),
      );
      expect(row.flagsCollection.isButton, isTrue);
      expect(row.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('the Version row is a button with its label at 200 % text', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester, location: SettingsRoutes.settings, textScale: 2);
      await tester.scrollUntilVisible(
        find.text('Version'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final row = tester.getSemantics(
        find.bySemanticsLabel(
          'Version ${AppConfig.appVersion}, Details öffnen',
        ),
      );
      expect(row.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });

  group('layout', () {
    testWidgets(
      'at 200 % text on a small screen the page scrolls to its end and keeps '
      'room at the bottom (AT33, BS-118)',
      (tester) async {
        await open(tester, size: const Size(320, 568), textScale: 2);
        expect(tester.takeException(), isNull, reason: 'no overflow');

        final scrollable = find.byType(Scrollable).first;
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(
          position.maxScrollExtent,
          greaterThan(0),
          reason: 'the content does not fit, so the page has to scroll',
        );
        await tester.scrollUntilVisible(
          find.text('Lizenzen der verwendeten Pakete'),
          200,
          scrollable: scrollable,
        );
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();

        // The last card is the one with the licence text (BS-120), or its note
        // while it loads.
        final lastCard = tester.getRect(find.byType(AppCard).last);
        expect(
          lastCard.bottom,
          lessThanOrEqualTo(568 - 16 + 0.5),
          reason: 'the last card ends above the 16 px page margin',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('long website address and privacy text wrap at 200 % (AT33)', (
      tester,
    ) async {
      await open(tester, size: const Size(320, 640), textScale: 2);
      expect(tester.takeException(), isNull);
      final address = find.text('spacy.cloud/self-improvement');
      await tester.ensureVisible(address);
      expect(
        tester.getSize(address).width,
        lessThanOrEqualTo(320),
        reason: 'inside the screen',
      );
    });

    for (final variant in AppThemeVariant.values) {
      testWidgets(
        'renders in the ${variant.name} theme with its tokens (AT35)',
        (tester) async {
          await open(tester, theme: variant);
          final tokens = AppTokens.forVariant(variant);
          final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
          expect(scaffold.backgroundColor, tokens.colors.background);

          final title = tester.widget<Text>(find.text('Autor'));
          expect(title.style?.color, tokens.colors.textPrimary);
          final detail = tester.widget<Text>(find.text('Spacy.cloud'));
          expect(detail.style?.color, tokens.colors.textSecondary);

          final mark = tester.widget<Container>(
            find
                .ancestor(
                  of: find.byIcon(Icons.trending_up_rounded),
                  matching: find.byType(Container),
                )
                .first,
          );
          final gradient =
              (mark.decoration! as BoxDecoration).gradient! as LinearGradient;
          expect(gradient.colors, [
            tokens.colors.primary,
            tokens.colors.primaryButton,
          ]);
          await savePng(
            tester,
            'build/profile_shots/about_${variant.name}.png',
          );
        },
      );
    }
  });
}
