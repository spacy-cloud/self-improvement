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
/// the sources and fail by file and line.
///
/// What is scanned:
///
/// - Every string literal of every Dart file below `lib/` (button labels,
///   semantic labels, messages, notification texts: whatever a person reads or
///   hears is a literal there). Literals that follow each other (`'And' 'roid'`)
///   or are joined by a plus (`'And' + 'roid'`) are one string for Dart, so
///   they are read as one.
/// - Every string resource of the Android app (`<string>` and the items of
///   `<string-array>` and `<plurals>` in `android/app/src/main/res/values*/`):
///   the explanation of the Health Connect permission is shown by the system
///   from there and is no literal of `lib/` (BS-98, R1-08).
///
/// A platform name counts with whatever letters follow it ("iPhones",
/// "Androidgeräte", see `test/support/platform_names.dart`).
///
/// What is not scanned, on purpose:
///
/// - Comments. They are written for developers (`/// Android adapter ...`).
/// - Identifiers and class names (`AndroidNotificationChannel`,
///   `androidIconName`) and the markup of the resource files (`parent="@android:
///   style/..."`). They are code, not text.
/// - The texts of third-party licences on the page "Lizenzen". The licence
///   registry delivers them at run time, they are not literals of `lib/`, and
///   we cannot word them.
/// - Text that is put together at run time from parts that are not literals.
///   The widget test of the reminder flow
///   (`test/features/reminders/reminder_platform_neutral_test.dart`) reads
///   what is really on the screen for that.
/// - The names the platforms give to themselves in their own files: the manifest
///   and the Info.plist hold no text of the app but the app name and the one
///   usage description iOS requires before HealthKit asks (BS-122,
///   `NSHealthShareUsageDescription`; it names no platform, and
///   `ios_health_project_test.dart` reads it).
///
/// A technical literal that has to name a platform (a channel name, a map key)
/// goes into [allowedLiterals] with the reason; the list is empty today.
///
/// The scan proves that the sources contain no such word. It does not prove
/// how a text reads on a device.

/// Literals that may name a platform because no person ever reads them: file
/// path (as `lib/...` or `android/...`) to the exact text of the literal and
/// the reason. An entry that no literal needs any more fails [main]'s last
/// test.
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
  /// as an own entry. Literals that Dart joins (`'a' 'b'`, `'a' + 'b'`) are one
  /// entry, on the line of the first one.
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
    // The last literal of this level. It may still grow: Dart joins string
    // literals that follow each other ('a' 'b') or sit on both sides of a plus
    // ('a' + 'b') into one string, so a word split over them is one word.
    SourceLiteral? open;
    var openEnd = 0;
    void close() {
      if (open != null) {
        literals.add(open!);
        open = null;
      }
    }

    while (_i < _source.length) {
      final char = _source[_i];
      if (_source.startsWith('//', _i)) {
        while (_i < _source.length && _source[_i] != '\n') {
          _i++;
        }
      } else if (_source.startsWith('/*', _i)) {
        _skipBlockComment();
      } else if (_startsString()) {
        final start = _i;
        final literal = _string();
        if (open != null && _joins(openEnd, start)) {
          open = SourceLiteral('${open!.text}${literal.text}', open!.line);
        } else {
          close();
          open = literal;
        }
        openEnd = _i;
      } else {
        if (char == '{') {
          depth++;
        } else if (char == '}') {
          if (inInterpolation && depth == 0) {
            _i++;
            close();
            return;
          }
          depth--;
        } else if (char == '\n') {
          _line++;
        }
        _i++;
      }
    }
    close();
  }

  /// Whether nothing but blanks, comments and at most one plus lies between
  /// [from] and [to]: then the literal that ends at [from] and the one that
  /// starts at [to] are one string.
  bool _joins(int from, int to) {
    var plus = false;
    var i = from;
    while (i < to) {
      final char = _source[i];
      if (char == ' ' || char == '\t' || char == '\r' || char == '\n') {
        i++;
      } else if (_source.startsWith('//', i)) {
        while (i < to && _source[i] != '\n') {
          i++;
        }
      } else if (_source.startsWith('/*', i)) {
        final end = _source.indexOf('*/', i + 2);
        if (end == -1 || end + 2 > to) {
          return false;
        }
        i = end + 2;
      } else if (char == '+' && !plus) {
        plus = true;
        i++;
      } else {
        return false;
      }
    }
    return true;
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

  SourceLiteral _string() {
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
    return SourceLiteral(text.toString(), startLine);
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

/// The texts of the string resources of an Android `values*/*.xml` source: the
/// content of `<string>` and of the items of `<string-array>` and `<plurals>`.
///
/// Comments and everything that is no text (styles, colours, attribute values
/// such as `parent="@android:style/..."`) are skipped. Entities, CDATA and the
/// escapes of Android resources are decoded and markup inside a text (`<b>`) is
/// dropped, so none of them can hide a word. [LiteralScan.wellFormed] is true:
/// the resource files are read with patterns, which cannot lose track.
LiteralScan scanXmlStrings(String xml) {
  // Blank the comments out but keep their line breaks, so lines stay right.
  final source = xml.replaceAllMapped(
    RegExp(r'<!--.*?-->', dotAll: true),
    (match) => match.group(0)!.replaceAll(RegExp(r'[^\n]'), ' '),
  );
  final literals = <SourceLiteral>[];
  void add(String raw, int offset) {
    final line = '\n'.allMatches(source.substring(0, offset)).length + 1;
    literals.add(SourceLiteral(_androidResourceText(raw), line));
  }

  // The opening tag of an element that is not self-closing (`<string
  // name="a">`, `<string>`) is the first group, the text the last one; the text
  // starts after the tag.
  const open = r'(?:\s[^>]*[^/>])?>';
  for (final match in RegExp(
    '(<string$open)(.*?)</string\\s*>',
    dotAll: true,
  ).allMatches(source)) {
    add(match.group(2)!, match.start + match.group(1)!.length);
  }
  for (final list in RegExp(
    '(<(string-array|plurals)$open)(.*?)</\\2\\s*>',
    dotAll: true,
  ).allMatches(source)) {
    final listStart = list.start + list.group(1)!.length;
    for (final item in RegExp(
      '(<item$open)(.*?)</item\\s*>',
      dotAll: true,
    ).allMatches(list.group(3)!)) {
      add(item.group(2)!, listStart + item.start + item.group(1)!.length);
    }
  }
  literals.sort((a, b) => a.line.compareTo(b.line));
  return LiteralScan(literals, wellFormed: true);
}

/// What a person reads for the raw content of a string resource.
String _androidResourceText(String raw) {
  var text = raw.replaceAllMapped(
    RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true),
    (match) => match.group(1)!,
  );
  text = text.replaceAll(RegExp(r'</?[A-Za-z][^>]*>'), '');
  text = text.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-z]+);'), (
    match,
  ) {
    final entity = match.group(1)!;
    switch (entity) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final code = entity.startsWith('#x')
        ? int.tryParse(entity.substring(2), radix: 16)
        : int.tryParse(entity.substring(1));
    return code == null || code < 0 || code > 0x10FFFF
        ? match.group(0)!
        : String.fromCharCode(code);
  });
  return text.replaceAllMapped(RegExp(r'\\(u[0-9a-fA-F]{4}|.)', dotAll: true), (
    match,
  ) {
    final escaped = match.group(1)!;
    return switch (escaped[0]) {
      'n' => '\n',
      't' => '\t',
      'u' when escaped.length == 5 => String.fromCharCode(
        int.parse(escaped.substring(1), radix: 16),
      ),
      _ => escaped,
    };
  });
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

/// The platform names in the string resources of [xml], one line per hit
/// (`line N: "text"`). A text in [allowed] (exact text) is skipped.
List<String> platformNamesInResources(
  String xml, {
  Set<String> allowed = const <String>{},
}) {
  return <String>[
    for (final literal in scanXmlStrings(xml).literals)
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

    test('joins literals that follow each other, as Dart does: a word split over two of them is found (BS-113, R1-08)', () {
      expect(texts("a = 'And' 'roid';"), <String>['Android']);
      expect(platformNamesInLiterals("a = 'And' 'roid';"), <String>[
        'line 1: "Android"',
      ]);
      // Over lines, with a comment in between and in other quotes.
      expect(texts("a = 'i'\n    // note\n    /* more */ \"OS\";"), <String>[
        'iOS',
      ]);
      expect(
        platformNamesInLiterals("x;\nf(\n  'Für iPh'\n  'ones'\n);"),
        <String>['line 3: "Für iPhones"'],
        reason: 'the line is the one of the first literal',
      );
      // Three in a row and a raw one.
      expect(texts("a = 'An' 'dro' r'id';"), <String>['Android']);
    });

    test('joins the two sides of a plus between literals (BS-113, R1-08)', () {
      expect(texts("a = 'And' + 'roid';"), <String>['Android']);
      expect(texts("a = 'And'\n    + 'roid'\n    + 's';"), <String>[
        'Androids',
      ]);
      expect(platformNamesInLiterals("a = 'i' + 'Phone';"), <String>[
        'line 1: "iPhone"',
      ]);
    });

    test('keeps literals apart that are not joined (BS-113, R1-08)', () {
      // A comma, a call, an operator or an identifier in between: two strings.
      expect(texts("f('And', 'roid');"), <String>['And', 'roid']);
      expect(texts("a = ['And', 'roid'];"), <String>['And', 'roid']);
      expect(texts("a = 'And' + b + 'roid';"), <String>['And', 'roid']);
      expect(texts("a = 'And'; b = 'roid';"), <String>['And', 'roid']);
      expect(texts("a = g('And') + 'roid';"), <String>['And', 'roid']);
      expect(texts("a = 'And' ? 'roid' : 'x';"), <String>['And', 'roid', 'x']);
      expect(platformNamesInLiterals("f('And', 'roid');"), isEmpty);
    });

    test(
      'joins literals around an interpolation and inside one (BS-113, R1-08)',
      () {
        expect(texts(r"a = 'x$y' 'Phone';"), <String>[
          'x${interpolationMark}Phone',
        ]);
        expect(
          platformNamesInLiterals(r"a = '${c ? 'i' 'OS' : 'x'}';"),
          <String>['line 1: "iOS"'],
        );
      },
    );
  });

  group('the string resources of the Android app (BS-98, R1-08)', () {
    List<String> texts(String xml) => <String>[
      for (final literal in scanXmlStrings(xml).literals) literal.text,
    ];

    test(
      'finds strings, the items of arrays and plurals, with their lines',
      () {
        const xml = '''
<resources>
    <string name="a">Eins</string>
    <string name="b" translatable="false">Zwei</string>
    <string-array name="c">
        <item>Drei</item>
        <item>Vier</item>
    </string-array>
    <plurals name="d">
        <item quantity="one">Fuenf</item>
        <item quantity="other">Sechs</item>
    </plurals>
</resources>
''';
        final scan = scanXmlStrings(xml);
        expect(
          <String>[for (final l in scan.literals) l.text],
          <String>['Eins', 'Zwei', 'Drei', 'Vier', 'Fuenf', 'Sechs'],
        );
        expect(
          <int>[for (final l in scan.literals) l.line],
          <int>[2, 3, 5, 6, 9, 10],
        );
        expect(scan.wellFormed, isTrue);
      },
    );

    test('skips comments, styles, colours and attribute values', () {
      const xml = '''
<resources>
    <!-- The Android window, "iOS" too: <string name="x">iPhone</string> -->
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/android_background</item>
    </style>
    <color name="c">#FF0000</color>
    <string name="empty"/>
    <string name="app_name">App-Name</string>
</resources>
''';
      expect(texts(xml), <String>['App-Name']);
      expect(platformNamesInResources(xml), isEmpty);
    });

    test('decodes entities, escapes and CDATA, and drops markup, so none of '
        'them hides a word', () {
      const xml = r'''
<resources>
    <string name="a">&#65;ndroid und &#x69;OS</string>
    <string name="b">\u0069Phone und \u0041ndroid</string>
    <string name="c">Auf <b>Android</b> und <xliff:g id="x">iPad</xliff:g></string>
    <string name="d"><![CDATA[Android <b>CDATA</b>]]></string>
    <string name="e">Fish &amp; Chips, 5 &lt; 6, \'quoted\' \@home \n\t.</string>
</resources>
''';
      expect(texts(xml), <String>[
        'Android und iOS',
        'iPhone und Android',
        'Auf Android und iPad',
        'Android CDATA',
        "Fish & Chips, 5 < 6, 'quoted' @home \n\t.",
      ]);
      expect(platformNamesInResources(xml), hasLength(4));
    });

    test('finds a platform name in a text and says where (BS-113, R1-08)', () {
      const xml = '''
<resources>
    <string name="title">Schritte aus Health Connect</string>
    <string name="text">Diese App liest\nunter Android deine Schritte.</string>
</resources>
''';
      expect(platformNamesInResources(xml), <String>[
        'line 3: "Diese App liest\nunter Android deine Schritte."',
      ]);
      expect(
        platformNamesInResources(
          xml,
          allowed: <String>{'Diese App liest\nunter Android deine Schritte.'},
        ),
        isEmpty,
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

    test('are found in the plural and in compounds, and reported whole (BS-113, R1-08)', () {
      for (final (text, found) in <(String, String)>[
        ('Für iPhones und iPads', 'iPhones'),
        ('Nur auf iPads', 'iPads'),
        ('Androidgeräte werden unterstützt', 'Androidgeräte'),
        ('Das Android-Gerät', 'Android'),
        ('Die iOS-Version', 'iOS'),
        ('iPhone-Nutzer', 'iPhone'),
        ('iPhonetastatur', 'iPhonetastatur'),
        ('Androids Sicht', 'Androids'),
        ('ANDROIDGERÄTE', 'ANDROIDGERÄTE'),
        ('IOSGeräte', 'IOSGeräte'),
        ('Gerätetyp: iPadOS-Tablet', 'iPadOS'),
      ]) {
        expect(platformNameIn(text), found, reason: text);
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
        // The letters have to follow the name at the start of a word.
        'Auto-Radios und Videostudios',
        'Anionen und Kationen (Ionen)',
        'Mobilgeräte, Handys und Tablets',
        // Health Connect is the name of a service, no platform.
        'Schritte aus Health Connect',
        'Diese App kann deine Schritte aus Health Connect übernehmen.',
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

  // The string resources of the Android app: the system shows them (the
  // explanation of the Health Connect permission), they are no literal of lib/.
  final resources = <File>[
    for (final directory in Directory(
      'android/app/src/main/res',
    ).listSync().whereType<Directory>())
      if (directory.path.split('/').last.startsWith('values'))
        for (final file in directory.listSync().whereType<File>())
          if (file.path.endsWith('.xml')) file,
  ]..sort((a, b) => a.path.compareTo(b.path));
  final resourceScans = <String, LiteralScan>{
    for (final file in resources)
      file.path: scanXmlStrings(file.readAsStringSync()),
  };

  /// One line per text in [scanned] that names a platform and is not allowed.
  List<String> platformHits(Map<String, LiteralScan> scanned) {
    final hits = <String>[];
    for (final MapEntry(key: path, value: scan) in scanned.entries) {
      final allowed = allowedLiterals[path]?.keys.toSet() ?? <String>{};
      for (final literal in scan.literals) {
        final name = platformNameIn(literal.text);
        if (name != null && !allowed.contains(literal.text)) {
          hits.add('$path:${literal.line} names "$name": ${literal.text}');
        }
      }
    }
    return hits;
  }

  group('the texts of the app (BS-113, D-017, AT28)', () {
    test('no string literal in lib/ names a platform', () {
      expect(
        platformHits(scans),
        isEmpty,
        reason:
            'Texts say "System" or "Gerät", never the platform: a person on '
            'the other platform reads them too. A technical literal that '
            'must name one goes into allowedLiterals with the reason.',
      );
    });

    test(
      'no string resource of the Android app names a platform (BS-113, R1-08)',
      () {
        expect(
          platformHits(resourceScans),
          isEmpty,
          reason:
              'The system shows these texts, for example the explanation of '
              'the Health Connect permission: they say "System" or "Gerät" '
              'too. A technical text that must name a platform goes into '
              'allowedLiterals with the reason.',
        );
      },
    );

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

    test('the scan reaches the string resources of the Android app (BS-98, '
        'R1-08)', () {
      const rationale = 'android/app/src/main/res/values/health_rationale.xml';
      expect(resourceScans, contains(rationale));
      final texts = <String>[
        for (final literal in resourceScans[rationale]!.literals) literal.text,
      ];
      expect(texts, hasLength(2));
      expect(texts, contains('Schritte aus Health Connect'));
      expect(
        texts.last,
        allOf(contains('Health Connect'), contains('nur die Zahl deiner')),
      );
      expect(
        texts.last,
        contains('\n\n'),
        reason: 'the escapes of the resource are decoded',
      );
      expect(
        resourceScans,
        contains('android/app/src/main/res/values/strings.xml'),
      );
      // The styles are in the same folders and hold no text.
      expect(
        resourceScans['android/app/src/main/res/values/styles.xml']!.literals,
        isEmpty,
      );
      for (final entry in resourceScans.entries) {
        expect(entry.value.wellFormed, isTrue, reason: entry.key);
      }
    });

    test('every allowed literal is still there and still needed', () {
      final everything = <String, LiteralScan>{...scans, ...resourceScans};
      for (final MapEntry(key: path, value: entries)
          in allowedLiterals.entries) {
        expect(
          everything,
          contains(path),
          reason: '$path is not a source of lib/ or a string resource',
        );
        final texts = <String>{
          for (final literal in everything[path]!.literals) literal.text,
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
