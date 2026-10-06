import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/platform_names.dart';

/// Guards that no text a person can read or hear names a platform (BS-113,
/// D-017, AT28).
///
/// The app runs on Android and on iOS, so its texts say "System" or "Gerät",
/// never "Android" or "iOS". A text that is right on one platform and wrong on
/// the other reached a tester on an iPhone ("Weiter zur Android-Abfrage"), and
/// a widget test of a single state cannot find the next one. These tests read
/// the sources of `lib/` and fail by file and line.
///
/// What is scanned: every string literal of every Dart file below `lib/`
/// (button labels, semantic labels, messages, notification texts: whatever a
/// person reads or hears is a literal there). What is not scanned, on purpose:
///
/// - Comments. They are written for developers (`/// Android adapter ...`).
/// - Identifiers and class names (`AndroidNotificationChannel`,
///   `androidIconName`). They are code, not text.
/// - The texts of third-party licences on the page "Lizenzen". The licence
///   registry delivers them at run time, they are not literals of `lib/`, and
///   we cannot word them.
/// - Text that is put together at run time from parts that are not literals.
///   The widget test of the reminder flow
///   (`test/features/reminders/reminder_platform_neutral_test.dart`) reads
///   what is really on the screen for that.
///
/// A technical literal that has to name a platform (a channel name, a map key)
/// goes into [allowedLiterals] with the reason; the list is empty today.
///
/// The scan proves that the sources contain no such word. It does not prove
/// how a text reads on a device.

/// Literals that may name a platform because no person ever reads them: file
/// path (as `lib/...`) to the exact text of the literal and the reason. An
/// entry that no literal needs any more fails [main]'s last test.
const Map<String, Map<String, String>> allowedLiterals =
    <String, Map<String, String>>{};

/// Stands for an interpolated value (`$name`, `${...}`) in [SourceLiteral.text].
const String interpolationMark = '￼';

/// One string literal of a Dart source.
final class SourceLiteral {
  const SourceLiteral(this.text, this.line);

  /// The text as the program sees it: escapes are decoded, interpolated values
  /// are replaced by [interpolationMark].
  final String text;

  /// Line (counted from 1) on which the literal starts.
  final int line;
}

/// The literals of one source and whether the scan read it to the end without
/// losing track.
final class LiteralScan {
  const LiteralScan(this.literals, {required this.wellFormed});

  /// All literals, a literal inside an interpolation (`'${a ? 'x' : 'y'}'`)
  /// as an own entry.
  final List<SourceLiteral> literals;

  /// False when a string is not closed before its line or the file ends. In a
  /// compiled source that means the scanner lost track, so the result of such
  /// a scan must not be trusted.
  final bool wellFormed;
}

/// The string literals of [source]: comments are skipped, quotes, raw and
/// triple-quoted strings, escapes and interpolations are understood.
LiteralScan scanLiterals(String source) {
  final scanner = _LiteralScanner(source).._code(inInterpolation: false);
  return LiteralScan(scanner.literals, wellFormed: scanner.wellFormed);
}

final class _LiteralScanner {
  _LiteralScanner(this._source);

  final String _source;
  final List<SourceLiteral> literals = <SourceLiteral>[];
  bool wellFormed = true;
  int _i = 0;
  int _line = 1;

  /// Scans code up to the end of the source or, with [inInterpolation], up to
  /// the `}` that closes the `${` the caller just read.
  void _code({required bool inInterpolation}) {
    var depth = 0;
    while (_i < _source.length) {
      final char = _source[_i];
      if (_source.startsWith('//', _i)) {
        while (_i < _source.length && _source[_i] != '\n') {
          _i++;
        }
      } else if (_source.startsWith('/*', _i)) {
        _skipBlockComment();
      } else if (_startsString()) {
        _string();
      } else {
        if (char == '{') {
          depth++;
        } else if (char == '}') {
          if (inInterpolation && depth == 0) {
            _i++;
            return;
          }
          depth--;
        } else if (char == '\n') {
          _line++;
        }
        _i++;
      }
    }
  }

  void _skipBlockComment() {
    var depth = 0;
    while (_i < _source.length) {
      if (_source.startsWith('/*', _i)) {
        depth++;
        _i += 2;
      } else if (_source.startsWith('*/', _i)) {
        depth--;
        _i += 2;
        if (depth == 0) {
          return;
        }
      } else {
        if (_source[_i] == '\n') {
          _line++;
        }
        _i++;
      }
    }
  }

  bool _startsString() {
    final char = _source[_i];
    if (char == "'" || char == '"') {
      return true;
    }
    if ((char == 'r' || char == 'R') &&
        _i + 1 < _source.length &&
        (_source[_i + 1] == "'" || _source[_i + 1] == '"')) {
      return _i == 0 || !_isIdentifierPart(_source.codeUnitAt(_i - 1));
    }
    return false;
  }

  void _string() {
    final startLine = _line;
    var raw = false;
    if (_source[_i] == 'r' || _source[_i] == 'R') {
      raw = true;
      _i++;
    }
    final quote = _source[_i];
    final triple = _source.startsWith(quote * 3, _i);
    _i += triple ? 3 : 1;
    final text = StringBuffer();
    while (true) {
      if (_i >= _source.length) {
        wellFormed = false;
        break;
      }
      final char = _source[_i];
      if (char == quote && (!triple || _source.startsWith(quote * 3, _i))) {
        _i += triple ? 3 : 1;
        break;
      }
      if (char == '\n') {
        if (!triple) {
          wellFormed = false; // an unclosed string ends with its line
          break;
        }
        _line++;
        text.write(char);
        _i++;
      } else if (!raw && char == r'\') {
        _escape(text);
      } else if (!raw && char == r'$') {
        _interpolation(text);
      } else {
        text.write(char);
        _i++;
      }
    }
    literals.add(SourceLiteral(text.toString(), startLine));
  }

  /// Reads the escape sequence that starts at the backslash at [_i].
  void _escape(StringBuffer text) {
    if (_i + 1 >= _source.length) {
      _i++;
      return;
    }
    final next = _source[_i + 1];
    _i += 2;
    switch (next) {
      case 'n':
        text.write('\n');
      case 'r':
        text.write('\r');
      case 't':
        text.write('\t');
      case 'b':
        text.write('\b');
      case 'f':
        text.write('\f');
      case 'v':
        text.write('\v');
      case 'x':
        _hexEscape(text, 2);
      case 'u':
        if (_i < _source.length && _source[_i] == '{') {
          final end = _source.indexOf('}', _i);
          if (end != -1) {
            _writeCodePoint(text, _source.substring(_i + 1, end));
            _i = end + 1;
          }
        } else {
          _hexEscape(text, 4);
        }
      case '\n':
        _line++; // a backslash before a line break continues the string
      default:
        text.write(next);
    }
  }

  void _hexEscape(StringBuffer text, int digits) {
    final end = _i + digits;
    if (end <= _source.length) {
      _writeCodePoint(text, _source.substring(_i, end));
      _i = end;
    }
  }

  void _writeCodePoint(StringBuffer text, String hex) {
    final value = int.tryParse(hex, radix: 16);
    if (value != null && value >= 0 && value <= 0x10FFFF) {
      text.writeCharCode(value);
    }
  }

  /// Reads the interpolation that starts at the dollar sign at [_i].
  void _interpolation(StringBuffer text) {
    final next = _i + 1 < _source.length ? _source[_i + 1] : '';
    if (next == '{') {
      _i += 2;
      _code(inInterpolation: true);
      text.write(interpolationMark);
    } else if (next.isNotEmpty && _isIdentifierStart(next.codeUnitAt(0))) {
      _i += 2;
      while (_i < _source.length && _isIdentifierPart(_source.codeUnitAt(_i))) {
        _i++;
      }
      text.write(interpolationMark);
    } else {
      text.write(r'$');
      _i++;
    }
  }

  static bool _isIdentifierStart(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      unit == 0x5F;

  static bool _isIdentifierPart(int unit) =>
      _isIdentifierStart(unit) ||
      (unit >= 0x30 && unit <= 0x39) ||
      unit == 0x24;
}

/// The platform names in the literals of [source], one line per hit
/// (`line N: "text"`). A literal in [allowed] (exact text) is skipped.
List<String> platformNamesInLiterals(
  String source, {
  Set<String> allowed = const <String>{},
}) {
  return <String>[
    for (final literal in scanLiterals(source).literals)
      if (!allowed.contains(literal.text) &&
          platformNameIn(literal.text) != null)
        'line ${literal.line}: "${literal.text}"',
  ];
}

void main() {
  group('the scanner', () {
    List<String> texts(String source) => <String>[
      for (final literal in scanLiterals(source).literals) literal.text,
    ];

    test('finds single, double, triple and raw quoted strings', () {
      final found = texts(r'''
a = 'one'; b = "two";
c = """three
3""";
d = r'fo\ur';
''');
      expect(found, <String>['one', 'two', 'three\n3', r'fo\ur']);
    });

    test('knows the line of a literal', () {
      final scan = scanLiterals("a;\n\nb = 'x';\nc = '''y\nz''';\nd = 'w';");
      expect(<int>[for (final l in scan.literals) l.line], <int>[3, 4, 6]);
    });

    test('ignores comments, identifiers and class names', () {
      const source = '''
/// Android adapter. "iOS" too.
// Android's channel, an apostrophe ' and a quote "
/* AndroidNotificationChannel and iOS: 'not a string' */
final androidIconName = AndroidNotificationChannel(iOS: ios);
''';
      final scan = scanLiterals(source);
      expect(scan.literals, isEmpty);
      expect(scan.wellFormed, isTrue);
      expect(platformNamesInLiterals(source), isEmpty);
    });

    test('does not take a comment marker inside a string for a comment', () {
      final found = texts("a = 'https://example.org/Android'; b = 'x'; // n");
      expect(found, <String>['https://example.org/Android', 'x']);
    });

    test('is not confused by quotes of the other kind', () {
      final found = texts(r"""a = "it's Android"; b = 'say "iOS"';""");
      expect(found, <String>["it's Android", 'say "iOS"']);
    });

    test('decodes escapes, so an escape cannot hide or fake a word', () {
      final found = texts(
        r"a = '\nAndroid \u0069OS \x69Phone \u{69}Pad \$ \\';",
      );
      expect(found, <String>['\nAndroid iOS iPhone iPad \$ \\']);
      expect(platformNamesInLiterals(r"a = '\u0041ndroid';"), hasLength(1));
    });

    test('leaves interpolated values out and reads literals inside them', () {
      final scan = scanLiterals(
        r"a = 'Hello $name, ${cond ? 'Android' : 'x'} and ${m['k']}!';",
      );
      final found = <String>[for (final l in scan.literals) l.text];
      expect(
        found,
        containsAll(<String>[
          'Android',
          'x',
          'k',
          'Hello $interpolationMark, $interpolationMark and '
              '$interpolationMark!',
        ]),
      );
      expect(scan.wellFormed, isTrue);
    });

    test('a dollar sign that starts nothing stays a dollar sign', () {
      expect(texts("a = 'costs 5\$ or \$ 5 or 5 \$';"), <String>[
        r'costs 5$ or $ 5 or 5 $',
      ]);
      expect(texts("a = 'only \$';"), <String>[r'only $']);
    });

    test('counts braces inside an interpolation', () {
      final scan = scanLiterals(r"a = '${{'k': 1}['k']} Android'; b = 'y';");
      expect(<String>[for (final l in scan.literals) l.text], contains('y'));
      expect(platformNamesInLiterals(r"a = '${{'k': 1}['k']} Android';"), [
        'line 1: "$interpolationMark Android"',
      ]);
    });

    test('reads an unclosed string to the end of its line and says so', () {
      final scan = scanLiterals("a = 'open\nb = 'closed';");
      expect(scan.wellFormed, isFalse);
      expect(scanLiterals("a = 'open").wellFormed, isFalse);
      expect(scanLiterals('/* open').literals, isEmpty);
    });

    test('an allowed literal is skipped, any other one is still found', () {
      const source = "a = 'Android'; b = 'iOS';";
      expect(platformNamesInLiterals(source), <String>[
        'line 1: "Android"',
        'line 1: "iOS"',
      ]);
      expect(
        platformNamesInLiterals(source, allowed: <String>{'Android'}),
        <String>['line 1: "iOS"'],
      );
    });
  });

  group('the platform names', () {
    test('are matched as whole words, without regard to case', () {
      for (final text in <String>[
        'Android-Status: erlaubt',
        'Zeigt Android keine Abfrage',
        'auf dem iPhone',
        'Das iOS-Update',
        'ANDROID',
        'ios',
        'iPad und iPadOS',
      ]) {
        expect(platformNameIn(text), isNotNull, reason: text);
      }
    });

    test('are not found inside other words', () {
      for (final text in <String>[
        'Studios',
        'Biosphäre',
        'Radios',
        'Weiter zur Systemabfrage',
        'Systemstatus: Benachrichtigungen sind erlaubt.',
        'Das System fragt erst, wenn du Erinnerungen einschaltest.',
        'Pad, Phone, Droid',
      ]) {
        expect(platformNameIn(text), isNull, reason: text);
      }
    });
  });

  final sources = <File>[
    for (final entity in Directory('lib').listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          !entity.path.endsWith('.g.dart'))
        entity,
  ]..sort((a, b) => a.path.compareTo(b.path));
  final scans = <String, LiteralScan>{
    for (final file in sources)
      file.path: scanLiterals(file.readAsStringSync()),
  };

  group('the texts of the app (BS-113, D-017, AT28)', () {
    test('no string literal in lib/ names a platform', () {
      final hits = <String>[];
      for (final MapEntry(key: path, value: scan) in scans.entries) {
        final allowed = allowedLiterals[path]?.keys.toSet() ?? <String>{};
        for (final literal in scan.literals) {
          final name = platformNameIn(literal.text);
          if (name != null && !allowed.contains(literal.text)) {
            hits.add('$path:${literal.line} names "$name": ${literal.text}');
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason:
            'Texts say "System" or "Gerät", never the platform: a person on '
            'the other platform reads them too. A technical literal that '
            'must name one goes into allowedLiterals with the reason.',
      );
    });

    test('the scan reads every source of lib/ to the end', () {
      expect(sources.length, greaterThan(150), reason: 'the scan finds lib/');
      final lost = <String>[
        for (final entry in scans.entries)
          if (!entry.value.wellFormed) entry.key,
      ];
      expect(
        lost,
        isEmpty,
        reason: 'a string that is never closed means the scanner lost track',
      );
    });

    test('the scan reaches texts, buttons and semantic labels', () {
      List<String> literalsOf(String path) => <String>[
        for (final literal in scans[path]!.literals) literal.text,
      ];
      const reminders = 'lib/features/reminders/presentation';
      expect(
        literalsOf('$reminders/reminder_permission_sheet.dart'),
        containsAll(<String>[
          'Erinnerungen erlauben?', // a title
          'Später', // a button
        ]),
      );
      expect(
        literalsOf('$reminders/reminders_section.dart'),
        containsAll(<String>[
          'Benachrichtigungen sind blockiert', // a banner title
          'Uhrzeiten der Trink-Erinnerung', // a semantics label
        ]),
      );
      expect(
        literalsOf('$reminders/sheet_frame.dart'),
        contains('Schließen'), // the label of a close button
      );
      expect(
        literalsOf('lib/core/notifications/domain/reminder_texts.dart'),
        contains('Zeit für ein Glas Wasser'), // a notification title
      );
    });

    test('every allowed literal is still there and still needed', () {
      for (final MapEntry(key: path, value: entries)
          in allowedLiterals.entries) {
        expect(scans, contains(path), reason: '$path is not a source of lib/');
        final texts = <String>{
          for (final literal in scans[path]!.literals) literal.text,
        };
        for (final MapEntry(key: text, value: reason) in entries.entries) {
          expect(reason.trim(), isNotEmpty, reason: '$path: "$text"');
          expect(
            texts,
            contains(text),
            reason: '$path no longer has "$text": drop the entry',
          );
          expect(
            platformNameIn(text),
            isNotNull,
            reason: '"$text" names no platform: drop the entry',
          );
        }
      }
    });
  });
}
