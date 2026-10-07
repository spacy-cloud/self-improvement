import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards that every text input of the app closes the keyboard on a tap
/// outside and that the scroll views around the inputs close it on a drag
/// (BS-112, D-018, AT33).
///
/// On iOS the number pad has no key that closes it and the system has no Back
/// gesture. Flutter keeps the keyboard on a touch screen unless a field asks
/// otherwise, and a field that forgets it looks the same in every test that
/// does not tap beside it, so these tests read the sources and fail by file
/// and line. They prove that the callback and the parameter are PASSED, not
/// what the keyboard then does: that is covered by
/// `test/core/design/components/keyboard_dismiss_test.dart` (the components)
/// and `test/app/form_keyboard_test.dart` (the forms of the running app).

/// [source] without comments, and with the content of string literals removed
/// (the quotes stay), so that an apostrophe in a comment or a parenthesis in a
/// string cannot confuse the scan for calls. The same scan as in
/// `motion_rules_test.dart`, kept apart so the two rule files do not depend on
/// each other.
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
/// tear-off, a plain identifier, a longer name such as `AppTextField`) is
/// skipped.
List<String> argumentsOfCalls(String code, String name) {
  final blanks = RegExp(r'\s+');
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
    // One line of single spaces: the formatter may break a parameter anywhere.
    calls.add(own.toString().replaceAll(blanks, ' '));
  }
  return calls;
}

void main() {
  group('the scanner', () {
    test('finds the own arguments of a call, not those of a closure', () {
      final code = codeOnly('''
final a = TextField(
  controller: c,
  onChanged: (v) => Other(onTapOutside: dismiss),
);
''');
      final own = argumentsOfCalls(code, 'TextField').single;
      expect(own, contains('controller: c'));
      expect(own, isNot(contains('onTapOutside')));
    });

    test(
      'does not take AppTextField or TextFieldTapRegion for a TextField',
      () {
        final code = codeOnly('''
AppTextField(label: 'a');
TextFieldTapRegion(child: x);
final f = TextField(onTapOutside: dismissKeyboardOnTapOutside);
''');
        final calls = argumentsOfCalls(code, 'TextField');
        expect(calls, hasLength(1));
        expect(
          calls.single,
          contains('onTapOutside: dismissKeyboardOnTapOutside'),
        );
      },
    );

    test('skips comments and strings that mention a call', () {
      final code = codeOnly('''
/// Use TextField(onTapOutside: x) here.
const hint = 'TextField(';
''');
      expect(argumentsOfCalls(code, 'TextField'), isEmpty);
    });
  });

  final sources = <File>[
    for (final entity in Directory('lib').listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          !entity.path.endsWith('.g.dart'))
        entity,
  ]..sort((a, b) => a.path.compareTo(b.path));

  test('every TextField in lib/ closes the keyboard on a tap outside (BS-112, AT33)', () {
    var found = 0;
    for (final file in sources) {
      final code = codeOnly(file.readAsStringSync());
      for (final arguments in argumentsOfCalls(code, 'TextField')) {
        found++;
        expect(
          arguments,
          contains('onTapOutside: dismissKeyboardOnTapOutside'),
          reason:
              '${file.path}: a TextField must pass onTapOutside: '
              'dismissKeyboardOnTapOutside, or an iPhone user cannot close '
              'its keyboard (use AppTextField where the design allows it)',
        );
      }
    }
    expect(found, greaterThanOrEqualTo(7), reason: 'the scan finds the fields');
  });

  test('the scroll views around the inputs close the keyboard on a drag (BS-112, AT33)', () {
    // The frames every form page and sheet is built in, plus the one list with
    // a search field. A new page needs nothing: it is built in AppScaffold.
    const frames = <String>[
      'lib/core/design/components/app_scaffold.dart',
      'lib/features/reminders/presentation/sheet_frame.dart',
      'lib/features/nutrition/presentation/nutrition_widgets.dart',
      'lib/features/onboarding/presentation/widgets/step_page.dart',
      'lib/features/tasks/presentation/tasks_list_view.dart',
    ];
    var found = 0;
    for (final path in frames) {
      final code = codeOnly(File(path).readAsStringSync());
      for (final name in <String>[
        'SingleChildScrollView',
        'CustomScrollView',
      ]) {
        for (final arguments in argumentsOfCalls(code, name)) {
          found++;
          expect(
            arguments,
            contains(
              'keyboardDismissBehavior: '
              'ScrollViewKeyboardDismissBehavior.onDrag',
            ),
            reason:
                '$path: a $name of a form must close the keyboard on a drag',
          );
        }
      }
    }
    expect(found, greaterThanOrEqualTo(6), reason: 'the scan finds the frames');
  });
}
