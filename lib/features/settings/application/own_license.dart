import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asset key of the licence of the own code: the file `LICENSE` in the root of
/// the repository, registered as an asset in `pubspec.yaml`.
///
/// This is the ONE source of the licence text. The file in the repository and
/// the text on the page "Über die App" are the same bytes, so they cannot drift
/// apart; there is no copy of the text in the code (decision D-021).
const String ownLicenseAsset = 'LICENSE';

/// The licence text of the own code in the shape of the page: the name of the
/// licence, then the paragraphs.
///
/// The file is wrapped at 80 columns. A paragraph here has no line breaks
/// inside (a screen reader reads it as one block, and the card wraps it to the
/// width of the screen); nothing else is changed, no word is added, dropped or
/// reordered.
@immutable
final class OwnLicenseText {
  const OwnLicenseText({required this.title, required this.paragraphs});

  /// The first paragraph of the file: the name of the licence ("MIT License").
  final String title;

  /// All other paragraphs in file order: the copyright line first, then the
  /// permission, the notice condition and the disclaimer.
  final List<String> paragraphs;

  /// The whole text, paragraphs separated by one blank line.
  String get plainText => <String>[title, ...paragraphs].join('\n\n');
}

/// Splits the content of the file `LICENSE` into its paragraphs (separated by
/// blank lines) and puts each paragraph into one line.
///
/// Throws a [FormatException] for a file without a name and a text, so the page
/// shows its error state instead of an empty card.
OwnLicenseText parseOwnLicense(String source) {
  final paragraphs = source
      .replaceAll('\r\n', '\n')
      .split(RegExp(r'\n[ \t]*\n'))
      .map(
        (paragraph) => paragraph
            .split(RegExp(r'\s+'))
            .where((word) => word.isNotEmpty)
            .join(' '),
      )
      .where((paragraph) => paragraph.isNotEmpty)
      .toList(growable: false);
  if (paragraphs.length < 2) {
    throw const FormatException(
      'The licence file needs a name and at least one paragraph.',
    );
  }
  return OwnLicenseText(
    title: paragraphs.first,
    paragraphs: List<String>.unmodifiable(paragraphs.skip(1)),
  );
}

/// Where the text comes from: the app's asset bundle (local, no network). Tests
/// override it to show the loading and the error state.
///
/// The read does not use the cache of the asset bundle: the file is about one
/// kilobyte, and a cached future would outlive the zone it was created in (a
/// second widget test in one process would wait for it forever).
final ownLicenseSourceProvider = Provider<Future<String> Function()>(
  (ref) =>
      () => rootBundle.loadString(ownLicenseAsset, cache: false),
);

/// The licence text of the own code.
final ownLicenseProvider = FutureProvider.autoDispose<OwnLicenseText>(
  (ref) async => parseOwnLicense(await ref.watch(ownLicenseSourceProvider)()),
);
