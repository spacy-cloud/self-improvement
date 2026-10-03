import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/features/settings/application/license_providers.dart';

/// "Lizenzen" (Figma `4056:558`): the bundled font, the Flutter SDK and the
/// Dart and Flutter packages of the app, read from Flutter's licence registry
/// (everything is local, no network). Each entry opens its full text.
///
/// Deviation from the frame: the third entry shows the real number of packages
/// instead of a build note, and the footer names the icons that are really
/// used (Material Icons) instead of calling them own designs.
class LicensesScreen extends ConsumerWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licenses = ref.watch(licenseCollectionProvider);
    return AppScaffold.subpage(
      title: 'Lizenzen',
      onBack: () => leaveScreen(context, fallback: SettingsRoutes.settings),
      body: licenses.when(
        loading: () => const _Loading(),
        error: (error, stack) => ErrorState(
          title: 'Lizenzen konnten nicht geladen werden',
          message:
              'Die Lizenztexte sind Teil der App. Versuche es noch einmal.',
          onRetry: () => ref.invalidate(licenseCollectionProvider),
        ),
        data: (collection) => collection.groups.isEmpty
            ? const EmptyState(
                title: 'Keine Lizenztexte gefunden',
                message:
                    'In dieser Ausführung sind keine Lizenzen registriert.',
              )
            : _LicenseList(collection: collection),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Lizenzen werden geladen …',
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _LicenseList extends StatelessWidget {
  const _LicenseList({required this.collection});

  final LicenseCollection collection;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final packages = collection.packages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppListGroup(
          children: [
            for (final group in collection.pinned)
              EntryListTile.chevron(
                title: group.displayName,
                subtitle: group.subtitle,
                onTap: () => _open(
                  context,
                  _LicenseTextScreen(title: group.displayName, group: group),
                ),
              ),
            if (packages.isNotEmpty)
              EntryListTile.chevron(
                title: 'Open-Source-Pakete',
                subtitle: packages.length == 1
                    ? '1 Paket'
                    : '${packages.length} Pakete',
                onTap: () =>
                    _open(context, _PackagesScreen(packages: packages)),
              ),
          ],
        ),
        if (collection.incomplete) ...[
          const SizedBox(height: 12),
          const _NoteText(
            text:
                'Die Liste konnte nicht vollständig gelesen werden. Die '
                'angezeigten Lizenzen sind vollständig, es können aber '
                'weitere Pakete fehlen.',
          ),
        ],
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'Die Symbole der App stammen aus den Material Icons von Flutter '
            '(Apache License 2.0). Illustrationen sind eigene Entwürfe '
            'dieses Projekts.',
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// A short note in the list; a plain text on the page background.
class _NoteText extends StatelessWidget {
  const _NoteText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        text,
        style: AppTextStyles.captionStrong.copyWith(
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

Future<void> _open(BuildContext context, Widget screen) {
  return Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => screen));
}

/// The packages in alphabetical order, one row each.
class _PackagesScreen extends StatelessWidget {
  const _PackagesScreen({required this.packages});

  final List<LicenseGroup> packages;

  @override
  Widget build(BuildContext context) {
    return AppScaffold.subpage(
      title: 'Open-Source-Pakete',
      scrollable: false,
      body: ListView.separated(
        itemCount: packages.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final group = packages[index];
          return AppCard(
            padding: EdgeInsets.zero,
            showShadow: false,
            child: EntryListTile.chevron(
              title: group.displayName,
              subtitle: group.subtitle,
              onTap: () => _open(
                context,
                _LicenseTextScreen(title: group.displayName, group: group),
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _BlockKind { licenseName, textHeader, body }

typedef _Block = ({String text, int indent, _BlockKind kind});

/// The full licence text(s) of one package. The text is laid out as a lazy
/// list of paragraphs, so even long texts open at once, wrap to the screen
/// width and scroll at any text size.
class _LicenseTextScreen extends StatelessWidget {
  const _LicenseTextScreen({required this.title, required this.group});

  final String title;
  final LicenseGroup group;

  List<_Block> _blocks() {
    final name = group.licenseName;
    return [
      if (name != null) (text: name, indent: 0, kind: _BlockKind.licenseName),
      for (var i = 0; i < group.texts.length; i++) ...[
        if (group.texts.length > 1)
          (
            text: 'Lizenztext ${i + 1} von ${group.texts.length}',
            indent: 0,
            kind: _BlockKind.textHeader,
          ),
        for (final paragraph in group.texts[i].paragraphs)
          (
            text: paragraph.text,
            indent: paragraph.indent,
            kind: _BlockKind.body,
          ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final blocks = _blocks();
    return AppScaffold.subpage(
      title: title,
      scrollable: false,
      body: ListView.builder(
        itemCount: blocks.length,
        itemBuilder: (context, index) {
          final block = blocks[index];
          final style = switch (block.kind) {
            _BlockKind.licenseName => AppTextStyles.titleSection,
            _BlockKind.textHeader => AppTextStyles.bodyStrong,
            _BlockKind.body => AppTextStyles.bodyRegular,
          }.copyWith(color: colors.textPrimary);
          final paragraph = _Paragraph(
            text: block.text,
            indent: block.indent,
            style: style,
          );
          return block.kind == _BlockKind.body
              ? paragraph
              : Semantics(header: true, child: paragraph);
        },
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.text, required this.style, this.indent = 0});

  final String text;
  final TextStyle style;

  /// Indentation level of the registry; `LicenseParagraph.centeredIndent`
  /// centres the text.
  final int indent;

  @override
  Widget build(BuildContext context) {
    final centered = indent == LicenseParagraph.centeredIndent;
    final level = indent.clamp(0, 6);
    return Padding(
      padding: EdgeInsets.only(left: centered ? 0 : level * 12.0, bottom: 10),
      child: Text(
        text,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: style,
      ),
    );
  }
}
