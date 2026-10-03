import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the claim "the app setting 'Reduzierte Bewegung' reaches every
/// animated surface of the app" (AT35, Q03).
///
/// The framework follows only the system flag. The app setting reaches modal
/// sheets, snack bars, menus and dialogs through an animation style, and
/// pushed pages through `appPageRoute`; a call that leaves it out looks the
/// same in a test that does not look at it, so these tests read the sources
/// and fail by file name. The date and time pickers have no such parameter in
/// the framework: they follow the system flag only (docs/known-limitations.md).
void main() {
  final sources = <File>[
    for (final entity in Directory('lib').listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ];

  /// The argument text of every call that starts like [start] (the name, an
  /// optional type argument and the opening parenthesis), up to the matching
  /// closing parenthesis.
  List<(File, String)> callsOf(RegExp start) {
    final calls = <(File, String)>[];
    for (final file in sources) {
      final text = file.readAsStringSync();
      for (final match in start.allMatches(text)) {
        var depth = 1;
        var i = match.end;
        while (i < text.length && depth > 0) {
          final char = text[i];
          if (char == "'" || char == '"') {
            i = text.indexOf(char, i + 1);
            while (i > 0 && text[i - 1] == r'\') {
              i = text.indexOf(char, i + 1);
            }
          } else if (char == '(') {
            depth++;
          } else if (char == ')') {
            depth--;
          }
          i++;
        }
        calls.add((file, text.substring(match.end, i)));
      }
    }
    return calls;
  }

  void everyCallPasses(RegExp start, String parameter, {int atLeast = 1}) {
    final calls = callsOf(start);
    expect(
      calls.length,
      greaterThanOrEqualTo(atLeast),
      reason: 'the scan finds the known calls (${start.pattern})',
    );
    for (final (file, arguments) in calls) {
      expect(
        arguments,
        contains('$parameter: AppMotion.surfaceStyleOf('),
        reason:
            '${file.path}: a ${start.pattern} call must pass $parameter so '
            'the app setting reaches it',
      );
    }
  }

  test('every modal bottom sheet follows the app setting', () {
    everyCallPasses(
      RegExp(r'\bshowModalBottomSheet\s*(<[^>(]*>)?\s*\('),
      'sheetAnimationStyle',
      atLeast: 6,
    );
  });

  test('every snack bar follows the app setting', () {
    everyCallPasses(RegExp(r'\bshowSnackBar\s*\('), 'snackBarAnimationStyle');
  });

  test('every pop-up menu follows the app setting', () {
    everyCallPasses(
      RegExp(r'\bPopupMenuButton\s*(<[^>(]*>)?\s*\('),
      'popUpAnimationStyle',
    );
  });

  test('every dialog follows the app setting', () {
    everyCallPasses(
      RegExp(
        r'\b(showDialog|showAdaptiveDialog|showGeneralDialog)\s*(<[^>(]*>)?\s*\(',
      ),
      'animationStyle',
      atLeast: 0,
    );
  });

  test('pages are pushed through appPageRoute only', () {
    for (final file in sources) {
      if (file.path == 'lib/core/design/motion/app_page_route.dart') {
        continue;
      }
      final text = file.readAsStringSync();
      for (final route in <String>[
        'MaterialPageRoute',
        'CupertinoPageRoute',
        'PageRouteBuilder',
      ]) {
        expect(
          text,
          isNot(contains(route)),
          reason:
              '${file.path} builds a $route itself: use appPageRoute so the '
              'app setting reaches the transition',
        );
      }
    }
  });
}
