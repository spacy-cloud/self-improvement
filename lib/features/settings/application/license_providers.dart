import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design_licenses.dart';

/// One licence text of a package: the paragraphs as the registry delivers them.
@immutable
final class LicenseText {
  const LicenseText(this.paragraphs);

  final List<LicenseParagraph> paragraphs;

  /// The text without layout, one line break between paragraphs.
  String get plainText => paragraphs.map((p) => p.text).join('\n');

  /// Identity of the text (paragraph text and indentation).
  String get _identity => paragraphs.map((p) => '${p.indent}:${p.text}').join('\n');
}

/// All licence texts of one package.
@immutable
final class LicenseGroup {
  const LicenseGroup({required this.packageName, required this.texts});

  /// Package name as registered, for example `Inter` or `flutter`.
  final String packageName;

  /// The distinct licence texts of the package (at least one).
  final List<LicenseText> texts;

  /// Title in the list: the font and the SDK get their plain names.
  String get displayName => switch (packageName) {
    'Inter' => 'Inter (Schrift)',
    'flutter' => 'Flutter SDK',
    _ => packageName,
  };

  /// The licence name when it is known for sure (our own font asset and the
  /// Flutter SDK), otherwise `null`.
  String? get licenseName => switch (packageName) {
    'Inter' => 'SIL Open Font License 1.1',
    'flutter' => 'BSD-3-Clause',
    _ => null,
  };

  /// Second line in the list.
  String get subtitle =>
      licenseName ?? (texts.length == 1 ? '1 Lizenztext' : '${texts.length} Lizenztexte');

  /// The font and the SDK are listed before the other packages.
  bool get isPinned => packageName == 'Inter' || packageName == 'flutter';
}

/// The licences of the app, grouped by package.
@immutable
final class LicenseCollection {
  const LicenseCollection({required this.groups, this.incomplete = false});

  /// The font first, then the SDK, then all other packages alphabetically.
  final List<LicenseGroup> groups;

  /// True when reading the registry stopped with an error; the groups are what
  /// was read until then.
  final bool incomplete;

  /// The pinned entries (font and SDK).
  List<LicenseGroup> get pinned =>
      groups.where((group) => group.isPinned).toList(growable: false);

  /// All other packages.
  List<LicenseGroup> get packages =>
      groups.where((group) => !group.isPinned).toList(growable: false);
}

/// Groups licence [entries] by package. Identical texts of one package appear
/// once; `Inter` comes first, then `flutter`, then the rest alphabetically
/// (ignoring case).
List<LicenseGroup> groupLicenseEntries(Iterable<LicenseEntry> entries) {
  final byPackage = <String, List<LicenseText>>{};
  final identities = <String, Set<String>>{};
  for (final entry in entries) {
    final text = LicenseText(entry.paragraphs.toList(growable: false));
    if (text.paragraphs.isEmpty) {
      continue;
    }
    for (final package in entry.packages) {
      final seen = identities.putIfAbsent(package, () => <String>{});
      if (seen.add(text._identity)) {
        byPackage.putIfAbsent(package, () => <LicenseText>[]).add(text);
      }
    }
  }
  int rank(String package) => switch (package) {
    'Inter' => 0,
    'flutter' => 1,
    _ => 2,
  };
  final names = byPackage.keys.toList()
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) {
        return byRank;
      }
      final byName = a.toLowerCase().compareTo(b.toLowerCase());
      return byName != 0 ? byName : a.compareTo(b);
    });
  return List.unmodifiable([
    for (final name in names)
      LicenseGroup(
        packageName: name,
        texts: List.unmodifiable(byPackage[name]!),
      ),
  ]);
}

/// Reads [source] completely and groups the entries. A failure while reading
/// keeps what was read ([LicenseCollection.incomplete]); only a failure without
/// any entry is thrown.
Future<LicenseCollection> loadLicenseCollection(
  Stream<LicenseEntry> source,
) async {
  final entries = <LicenseEntry>[];
  Object? failure;
  StackTrace? failureTrace;
  try {
    await for (final entry in source) {
      entries.add(entry);
    }
  } catch (error, stackTrace) {
    failure = error;
    failureTrace = stackTrace;
  }
  if (failure != null && entries.isEmpty) {
    Error.throwWithStackTrace(failure, failureTrace ?? StackTrace.current);
  }
  return LicenseCollection(
    groups: groupLicenseEntries(entries),
    incomplete: failure != null,
  );
}

/// Where the licences come from: Flutter's [LicenseRegistry] with the licences
/// of the bundled design assets (the font Inter) registered. Everything is
/// local, so the screen works without network. Tests override it.
final licenseSourceProvider = Provider<Stream<LicenseEntry> Function()>((ref) {
  return () {
    registerDesignLicenses();
    return LicenseRegistry.licenses;
  };
});

/// The licences of the app, grouped by package.
final licenseCollectionProvider = FutureProvider.autoDispose<LicenseCollection>(
  (ref) => loadLicenseCollection(ref.watch(licenseSourceProvider)()),
);
