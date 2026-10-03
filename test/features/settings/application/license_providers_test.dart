import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/settings/application/license_providers.dart';

LicenseEntry entry(List<String> packages, String text) =>
    LicenseEntryWithLineBreaks(packages, text);

Stream<LicenseEntry> stream(List<LicenseEntry> entries) =>
    Stream.fromIterable(entries);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('grouping', () {
    test('lists the font first, the SDK second, the rest alphabetically', () {
      final groups = groupLicenseEntries([
        entry(['zeta'], 'Z license'),
        entry(['flutter'], 'BSD'),
        entry(['Beta'], 'B license'),
        entry(['Inter'], 'OFL'),
        entry(['alpha'], 'A license'),
      ]);
      expect(groups.map((g) => g.packageName), [
        'Inter',
        'flutter',
        'alpha',
        'Beta',
        'zeta',
      ]);
    });

    test('an identical text of one package appears once', () {
      final groups = groupLicenseEntries([
        entry(['pkg'], 'Same text'),
        entry(['pkg'], 'Same text'),
        entry(['pkg'], 'Other text'),
      ]);
      expect(groups.single.texts, hasLength(2));
    });

    test('an entry for several packages is listed under each of them', () {
      final groups = groupLicenseEntries([
        entry(['one', 'two'], 'Shared text'),
      ]);
      expect(groups.map((g) => g.packageName), ['one', 'two']);
      expect(groups.first.texts.single.plainText, 'Shared text');
    });

    test('entries without any text are skipped', () {
      final groups = groupLicenseEntries([
        entry(['empty'], ''),
      ]);
      expect(groups, isEmpty);
    });

    test('the list is not modifiable from outside', () {
      final groups = groupLicenseEntries([
        entry(['pkg'], 'T'),
      ]);
      expect(() => groups.add(groups.first), throwsUnsupportedError);
    });
  });

  group('names', () {
    test('font and SDK have plain names and known licences', () {
      final groups = groupLicenseEntries([
        entry(['Inter'], 'OFL'),
        entry(['flutter'], 'BSD'),
        entry(['other'], 'x'),
      ]);
      expect(groups[0].displayName, 'Inter (Schrift)');
      expect(groups[0].licenseName, 'SIL Open Font License 1.1');
      expect(groups[0].subtitle, 'SIL Open Font License 1.1');
      expect(groups[1].displayName, 'Flutter SDK');
      expect(groups[1].licenseName, 'BSD-3-Clause');
      expect(groups[2].displayName, 'other');
      expect(groups[2].licenseName, isNull, reason: 'never guessed');
      expect(groups[2].subtitle, '1 Lizenztext');
      expect(groups[0].isPinned && groups[1].isPinned, isTrue);
      expect(groups[2].isPinned, isFalse);
    });

    test('the number of texts is spelled out for packages', () {
      final groups = groupLicenseEntries([
        entry(['many'], 'one'),
        entry(['many'], 'two'),
        entry(['many'], 'three'),
      ]);
      expect(groups.single.subtitle, '3 Lizenztexte');
    });

    test('the collection separates pinned entries from packages', () {
      final collection = LicenseCollection(
        groups: groupLicenseEntries([
          entry(['Inter'], 'a'),
          entry(['flutter'], 'b'),
          entry(['x'], 'c'),
          entry(['y'], 'd'),
        ]),
      );
      expect(collection.pinned.map((g) => g.packageName), ['Inter', 'flutter']);
      expect(collection.packages.map((g) => g.packageName), ['x', 'y']);
      expect(collection.incomplete, isFalse);
    });
  });

  group('reading the registry', () {
    test('reads everything and is complete', () async {
      final collection = await loadLicenseCollection(
        stream([
          entry(['a'], 'A'),
          entry(['b'], 'B'),
        ]),
      );
      expect(collection.groups, hasLength(2));
      expect(collection.incomplete, isFalse);
    });

    test(
      'a failure after some entries keeps them and says "incomplete"',
      () async {
        Stream<LicenseEntry> failing() async* {
          yield entry(['a'], 'A');
          throw StateError('asset missing');
        }

        final collection = await loadLicenseCollection(failing());
        expect(collection.groups.single.packageName, 'a');
        expect(collection.incomplete, isTrue);
      },
    );

    test('a failure without any entry is thrown, not hidden', () async {
      Stream<LicenseEntry> failing() async* {
        throw StateError('no registry');
      }

      await expectLater(loadLicenseCollection(failing()), throwsStateError);
    });

    test('an empty registry gives an empty, complete collection', () async {
      final collection = await loadLicenseCollection(stream([]));
      expect(collection.groups, isEmpty);
      expect(collection.incomplete, isFalse);
    });
  });

  group('provider', () {
    test('reads the injected source', () async {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          licenseSourceProvider.overrideWithValue(
            () => stream([
              entry(['pkg'], 'Text'),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      final collection = await container.read(licenseCollectionProvider.future);
      expect(collection.groups.single.packageName, 'pkg');
    });

    test('the real registry contains the bundled font licence', () async {
      final container = ProviderContainer(retry: (_, _) => null);
      addTearDown(container.dispose);
      final collection = await container.read(licenseCollectionProvider.future);
      final inter = collection.groups.firstWhere(
        (g) => g.packageName == 'Inter',
      );
      expect(
        inter.texts.first.plainText.toUpperCase(),
        contains('SIL OPEN FONT LICENSE'),
      );
      expect(collection.groups.first.packageName, 'Inter');
    });
  });
}
