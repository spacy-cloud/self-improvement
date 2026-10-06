import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/settings/application/own_license.dart';

/// The licence of the own code (BS-120): the file `LICENSE` is the one source
/// of the text, for the repository and for the page "Über die App".

/// Collapses every run of white space to one blank, so a text can be compared
/// with another one that is wrapped differently.
String normalized(String text) =>
    text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).join(' ');

/// The standard text of the MIT licence (SPDX `MIT`) with the holder of this
/// project. The file must hold exactly this text, apart from the wrapping.
const String standardMitText = '''
MIT License

Copyright (c) 2026 Spacy.cloud

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
''';

/// Text files below the repository root that the scan for the old holder reads.
bool _isScanned(String path) {
  const skippedFolders = <String>{
    '.git',
    '.dart_tool',
    '.idea',
    '.gradle',
    'build',
    'Pods',
  };
  final segments = path.split('/');
  if (segments.any(skippedFolders.contains)) {
    return false;
  }
  const textEndings = <String>{
    '.md',
    '.dart',
    '.yaml',
    '.yml',
    '.txt',
    '.xml',
    '.plist',
    '.kts',
    '.gradle',
    '.json',
    '.properties',
    '.sh',
  };
  return segments.last == 'LICENSE' ||
      textEndings.any((ending) => segments.last.endsWith(ending));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseOwnLicense', () {
    test(
      'puts every paragraph into one line and keeps their order (BS-120)',
      () {
        final text = parseOwnLicense(
          'MIT License\n'
          '\n'
          'Copyright (c) 2026 Spacy.cloud\n'
          '\n'
          'Permission is hereby granted,\n'
          'free of charge, to any person.\n'
          '\n'
          'The above notice shall be\n'
          'included.\n',
        );
        expect(text.title, 'MIT License');
        expect(text.paragraphs, <String>[
          'Copyright (c) 2026 Spacy.cloud',
          'Permission is hereby granted, free of charge, to any person.',
          'The above notice shall be included.',
        ]);
        expect(
          text.plainText,
          'MIT License\n\nCopyright (c) 2026 Spacy.cloud\n\n'
          'Permission is hereby granted, free of charge, to any person.\n\n'
          'The above notice shall be included.',
        );
      },
    );

    test(
      'reads Windows line breaks, trailing blanks and extra blank lines',
      () {
        final text = parseOwnLicense(
          'MIT License  \r\n\r\n\r\n  \r\nCopyright (c) 2026 Spacy.cloud\r\n'
          '\r\nA text\r\nover two lines.\r\n\r\n',
        );
        expect(text.title, 'MIT License');
        expect(text.paragraphs, <String>[
          'Copyright (c) 2026 Spacy.cloud',
          'A text over two lines.',
        ]);
      },
    );

    test('rejects a file without a name and a text', () {
      expect(() => parseOwnLicense(''), throwsFormatException);
      expect(() => parseOwnLicense('  \n\n  '), throwsFormatException);
      expect(() => parseOwnLicense('MIT License\n'), throwsFormatException);
    });

    test('changes no word: the text is the file with other line breaks', () {
      const source = 'A\nB b\n\nC  c\n\n\nD';
      expect(normalized(parseOwnLicense(source).plainText), normalized(source));
    });
  });

  group('the file LICENSE', () {
    test('names Spacy.cloud as the holder and holds the standard MIT text '
        '(BS-120)', () {
      final file = File('LICENSE').readAsStringSync();
      expect(file.split('\n').take(3).toList(), <String>[
        'MIT License',
        '',
        'Copyright (c) 2026 Spacy.cloud',
      ]);
      expect(
        normalized(file),
        normalized(standardMitText),
        reason: 'nothing but the name line differs from the MIT licence',
      );
    });

    test(
      'is parsed into the name, the copyright line and three paragraphs',
      () {
        final text = parseOwnLicense(File('LICENSE').readAsStringSync());
        expect(text.title, 'MIT License');
        expect(text.paragraphs, hasLength(4));
        expect(text.paragraphs.first, 'Copyright (c) 2026 Spacy.cloud');
        expect(text.paragraphs[1], startsWith('Permission is hereby granted'));
        expect(text.paragraphs[2], startsWith('The above copyright notice'));
        expect(text.paragraphs[3], startsWith('THE SOFTWARE IS PROVIDED'));
        expect(text.paragraphs[3], endsWith('DEALINGS IN THE SOFTWARE.'));
      },
    );

    test('the README names Spacy.cloud as the holder (BS-120)', () {
      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('[MIT-Lizenz](LICENSE) (Copyright Spacy.cloud)'));
    });

    test('no line that mentions the copyright names the old holder (BS-120)', () {
      // What `git grep -i copyright` shows must not contain the team name of
      // the project description. The name is written in two pieces so that this
      // file does not match itself.
      const oldHolder =
          'IA'
          '24';
      final offenders = <String>[];
      for (final entity in Directory('.').listSync(recursive: true)) {
        if (entity is! File) {
          continue;
        }
        final path = entity.path.startsWith('./')
            ? entity.path.substring(2)
            : entity.path;
        if (!_isScanned(path)) {
          continue;
        }
        final String text;
        try {
          text = entity.readAsStringSync();
        } on FormatException {
          continue; // not a text file
        }
        final lines = const LineSplitter().convert(text);
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.toLowerCase().contains('copyright') &&
              line.contains(oldHolder)) {
            offenders.add('$path:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('the asset (the one source of the text)', () {
    test(
      'the file LICENSE is registered as an asset in pubspec.yaml (BS-120)',
      () {
        expect(ownLicenseAsset, 'LICENSE');
        expect(
          File('pubspec.yaml').readAsStringSync(),
          contains('\n    - LICENSE\n'),
        );
      },
    );

    test(
      'the app bundle holds exactly the file of the repository (BS-120)',
      () async {
        final bundled = await rootBundle.loadString(
          ownLicenseAsset,
          cache: false,
        );
        expect(bundled, File('LICENSE').readAsStringSync());
      },
    );
  });
}
