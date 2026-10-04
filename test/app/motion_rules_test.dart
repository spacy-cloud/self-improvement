import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards that the app setting "Reduzierte Bewegung" is handed to every call
/// that opens an animated surface (AT35, Q03).
///
/// The framework follows only the system flag. The app setting reaches modal
/// sheets, snack bars, menus and dialogs through an animation style, and
/// pushed pages through `appPageRoute`; a call that leaves it out looks the
/// same in a test that does not look at it, so these tests read the sources
/// and fail by file name. They prove that the style is PASSED, not what the
/// surface then does: the behaviour is covered by `motion_test.dart` (page
/// changes, plus sheet) and `confirmation_sheet_scope_test.dart`. The date and
/// time pickers have no such parameter in the framework: they follow the
/// system flag only (docs/known-limitations.md).

/// [source] without comments, and with the content of string literals removed
/// (the quotes stay), so that an apostrophe in a comment or a parenthesis in a
/// string cannot confuse the scan for calls.
String codeOnly(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final char = source[i];
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end == -1 ? source.length : end; // the newline itself stays
    } else if (source.startsWith('/*', i)) {
      i = _endOfBlockComment(source, i);
    } else if (char == "'" ||
        char == '"' ||
        ((char == 'r' || char == 'R') &&
            i + 1 < source.length &&
            (source[i + 1] == "'" || source[i + 1] == '"'))) {
      out.write("''");
      i = _endOfString(source, i);
    } else {
      out.write(char);
      i++;
    }
  }
  return out.toString();
}

int _endOfBlockComment(String source, int start) {
  var depth = 0;
  var i = start;
  while (i < source.length) {
    if (source.startsWith('/*', i)) {
      depth++;
      i += 2;
    } else if (source.startsWith('*/', i)) {
      depth--;
      i += 2;
      if (depth == 0) {
        return i;
      }
    } else {
      i++;
    }
  }
  return source.length;
}

/// The index after the string literal that starts at [start].
int _endOfString(String source, int start) {
  var i = start;
  var raw = false;
  if (source[i] == 'r' || source[i] == 'R') {
    raw = true;
    i++;
  }
  final quote = source[i];
  final triple = source.startsWith('$quote$quote$quote', i);
  i += triple ? 3 : 1;
  while (i < source.length) {
    final char = source[i];
    if (!raw && char == r'\') {
      i += 2;
    } else if (!raw && char == r'$' && source.startsWith('{', i + 1)) {
      i = _endOfInterpolation(source, i + 2);
    } else if (triple
        ? source.startsWith('$quote$quote$quote', i)
        : char == quote) {
      return i + (triple ? 3 : 1);
    } else if (!triple && char == '\n') {
      return i; // an unterminated string ends with its line
    } else {
      i++;
    }
  }
  return source.length;
}

/// The index after the `}` that closes an interpolation `${` whose content
/// starts at [start]; strings inside it are skipped as strings.
int _endOfInterpolation(String source, int start) {
  var depth = 1;
  var i = start;
  while (i < source.length && depth > 0) {
    final char = source[i];
    if (char == "'" || char == '"') {
      i = _endOfString(source, i);
    } else {
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
      }
      i++;
    }
  }
  return i;
}

/// The own arguments of every CALL of [name] in [code] (see [codeOnly]): the
/// text inside the parentheses of the call WITHOUT anything inside nested
/// parentheses, brackets or braces, so a parameter of a closure or of another
/// call cannot count for the outer call. A mention that is not a call (a
/// comment is already gone, a tear-off, a plain identifier) is skipped.
List<String> argumentsOfCalls(String code, String name) {
  final calls = <String>[];
  int skipSpaces(int index) {
    var i = index;
    while (i < code.length && code[i].trim().isEmpty) {
      i++;
    }
    return i;
  }

  for (final match in RegExp('\\b$name\\b').allMatches(code)) {
    var i = skipSpaces(match.end);
    if (i < code.length && code[i] == '<') {
      var depth = 0;
      do {
        if (code[i] == '<') {
          depth++;
        } else if (code[i] == '>') {
          depth--;
        }
        i++;
      } while (i < code.length && depth > 0);
      i = skipSpaces(i);
    }
    if (i >= code.length || code[i] != '(') {
      continue;
    }
    final own = StringBuffer();
    var depth = 1;
    i++;
    while (i < code.length && depth > 0) {
      final char = code[i];
      if (depth == 1) {
        own.write(char);
      }
      if ('([{'.contains(char)) {
        depth++;
      } else if (')]}'.contains(char)) {
        depth--;
      }
      i++;
    }
    calls.add(own.toString());
  }
  return calls;
}

void main() {
  group('the scanner', () {
    test('finds a call with nested generic arguments', () {
      final calls = argumentsOfCalls(
        'await showModalBottomSheet<List<String>>(context: c, a: 1);',
        'showModalBottomSheet',
      );
      expect(calls, hasLength(1));
      expect(calls.single, contains('context: c'));
    });

    test('is not confused by an apostrophe in a comment', () {
      final code = codeOnly('''
// Don't touch this.
foo() {
  /* it's a "block" */
  showSnackBar(snackBarAnimationStyle: AppMotion.surfaceStyleOf(c)); // isn't
}
''');
      final calls = argumentsOfCalls(code, 'showSnackBar');
      expect(calls, hasLength(1));
      expect(calls.single, contains('snackBarAnimationStyle: '));
    });

    test('is not confused by quotes and parentheses in strings', () {
      final code = codeOnly(
        r"""showDialog(title: 'a ) b', c: "it's ${items.join(', ')}", d: r'\', e: 1);""",
      );
      final calls = argumentsOfCalls(code, 'showDialog');
      expect(calls, hasLength(1));
      expect(calls.single, contains('e: 1'));
    });

    test('counts a parameter only at the top level of the call', () {
      final code = codeOnly('''
showModalBottomSheet<void>(
  context: c,
  builder: (_) => Other(sheetAnimationStyle: AppMotion.surfaceStyleOf(c)),
);
''');
      final own = argumentsOfCalls(code, 'showModalBottomSheet').single;
      expect(own, isNot(contains('sheetAnimationStyle: AppMotion')));
      expect(own, contains('context: c'));
    });

    test('keeps the parameter of the call itself', () {
      final code = codeOnly('''
showModalBottomSheet<void>(
  context: c,
  sheetAnimationStyle: AppMotion.surfaceStyleOf(c),
  builder: (_) => Other(),
);
''');
      expect(
        argumentsOfCalls(code, 'showModalBottomSheet').single,
        contains('sheetAnimationStyle: AppMotion.surfaceStyleOf('),
      );
    });

    test('skips a mention that is not a call', () {
      final code = codeOnly('''
/// Uses showModalBottomSheet(...) internally.
final open = showModalBottomSheet;
''');
      expect(argumentsOfCalls(code, 'showModalBottomSheet'), isEmpty);
    });

    test('ends on an unterminated string without looping', () {
      expect(() => codeOnly("a = 'open\nb = 1;"), returnsNormally);
      expect(() => codeOnly('/* open'), returnsNormally);
    });
  });

  final sources = <File>[
    for (final entity in Directory('lib').listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ];

  void everyCallPasses(String name, String parameter, {int atLeast = 1}) {
    var found = 0;
    for (final file in sources) {
      final code = codeOnly(file.readAsStringSync());
      for (final arguments in argumentsOfCalls(code, name)) {
        found++;
        expect(
          arguments,
          contains('$parameter: AppMotion.surfaceStyleOf('),
          reason:
              '${file.path}: a call of $name must pass $parameter so the '
              'app setting reaches it',
        );
      }
    }
    expect(
      found,
      greaterThanOrEqualTo(atLeast),
      reason: 'the scan finds the known calls of $name',
    );
  }

  test('every modal bottom sheet follows the app setting', () {
    everyCallPasses('showModalBottomSheet', 'sheetAnimationStyle', atLeast: 6);
  });

  test('every snack bar follows the app setting', () {
    everyCallPasses('showSnackBar', 'snackBarAnimationStyle');
  });

  test('every pop-up menu follows the app setting', () {
    everyCallPasses('PopupMenuButton', 'popUpAnimationStyle');
  });

  test('every dialog follows the app setting', () {
    for (final name in <String>[
      'showDialog',
      'showAdaptiveDialog',
      'showGeneralDialog',
    ]) {
      everyCallPasses(name, 'animationStyle', atLeast: 0);
    }
  });

  test('pages are pushed through appPageRoute only', () {
    for (final file in sources) {
      if (file.path == 'lib/core/design/motion/app_page_route.dart') {
        continue;
      }
      final code = codeOnly(file.readAsStringSync());
      for (final route in <String>[
        'MaterialPageRoute',
        'CupertinoPageRoute',
        'PageRouteBuilder',
      ]) {
        expect(
          code,
          isNot(contains(route)),
          reason:
              '${file.path} builds a $route itself: use appPageRoute so the '
              'app setting reaches the transition',
        );
      }
    }
  });
}
