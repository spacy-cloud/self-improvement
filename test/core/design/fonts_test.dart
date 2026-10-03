import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// Minimal sfnt reader: table directory and a few fields.
class _Font {
  _Font(this.bytes) : data = ByteData.sublistView(bytes) {
    final tableCount = data.getUint16(4);
    for (var i = 0; i < tableCount; i++) {
      final entry = 12 + 16 * i;
      final tag = String.fromCharCodes(bytes.sublist(entry, entry + 4));
      tables[tag] = data.getUint32(entry + 8);
    }
  }

  final Uint8List bytes;
  final ByteData data;
  final Map<String, int> tables = <String, int>{};

  int get sfntVersion => data.getUint32(0);
  int get weightClass => data.getUint16(tables['OS/2']! + 4);
  int get unitsPerEm => data.getUint16(tables['head']! + 18);
  int get headMagic => data.getUint32(tables['head']! + 12);

  /// Name record [id] for the Windows platform (3), US English.
  String? name(int id) {
    final start = tables['name']!;
    final count = data.getUint16(start + 2);
    final stringOffset = data.getUint16(start + 4);
    for (var i = 0; i < count; i++) {
      final record = start + 6 + 12 * i;
      final platform = data.getUint16(record);
      final language = data.getUint16(record + 4);
      final nameId = data.getUint16(record + 6);
      if (platform == 3 && language == 0x409 && nameId == id) {
        final length = data.getUint16(record + 8);
        final offset = data.getUint16(record + 10);
        final from = start + stringOffset + offset;
        final units = <int>[
          for (var j = 0; j < length; j += 2) data.getUint16(from + j),
        ];
        return String.fromCharCodes(units);
      }
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const files = <String, int>{
    'Inter-Regular.ttf': 400,
    'Inter-Medium.ttf': 500,
    'Inter-SemiBold.ttf': 600,
    'Inter-Bold.ttf': 700,
  };

  for (final entry in files.entries) {
    group(entry.key, () {
      late _Font font;

      setUpAll(() {
        font = _Font(File('assets/fonts/${entry.key}').readAsBytesSync());
      });

      test('is a valid TrueType font of the expected weight', () {
        expect(font.sfntVersion, 0x00010000);
        expect(font.headMagic, 0x5F0F3CF5);
        expect(
          font.tables.keys,
          containsAll(<String>['cmap', 'glyf', 'head', 'name', 'OS/2']),
        );
        expect(font.unitsPerEm, 2048);
        expect(font.weightClass, entry.value);
        expect(font.bytes.length, greaterThan(300000));
      });

      test('belongs to the family Inter, version 4.001 (release 4.1)', () {
        expect(font.name(1)?.startsWith('Inter'), isTrue);
        expect(font.name(5), startsWith('Version 4.001'));
      });

      test('is declared in pubspec.yaml with its weight', () {
        final pubspec = File('pubspec.yaml').readAsStringSync();
        expect(
          pubspec,
          contains(
            'asset: assets/fonts/${entry.key}\n          weight: ${entry.value}',
          ),
        );
      });
    });
  }

  test('the font family Inter is declared once', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect('family: Inter'.allMatches(pubspec).length, 1);
    expect(pubspec, contains('- assets/fonts/OFL.txt'));
  });

  test(
    'the build tool turns the pubspec declaration into the font manifest',
    () async {
      final manifest = jsonDecode(
        await rootBundle.loadString('FontManifest.json'),
      ) as List<dynamic>;
      final inter = manifest
          .cast<Map<String, dynamic>>()
          .where((family) => family['family'] == 'Inter')
          .toList();
      expect(inter, hasLength(1));
      final fonts = (inter.single['fonts'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        <String, int>{
          for (final font in fonts)
            font['asset'] as String: font['weight'] as int,
        },
        <String, int>{
          for (final entry in files.entries)
            'assets/fonts/${entry.key}': entry.value,
        },
      );
    },
  );

  test('the licence is the SIL Open Font License 1.1 of the Inter project', () {
    final text = File('assets/fonts/OFL.txt').readAsStringSync();
    expect(text, contains('The Inter Project Authors'));
    expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
  });

  test('the README lists every font file and the source release', () {
    final readme = File('assets/fonts/README.md').readAsStringSync();
    for (final name in files.keys) {
      expect(readme, contains(name));
    }
    expect(readme, contains('https://github.com/rsms/inter/releases/tag/v4.1'));
    expect(readme, contains('SIL Open Font License 1.1'));
  });
}
