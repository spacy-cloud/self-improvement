import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The public documents say what the Health connection is (BS-97): only steps,
/// only on Android (Health Connect), only reading, and the switch is off until
/// the user turns it on; iOS and other kinds of data have none.
///
/// Two sentences still said "no Health connection" after the connection had
/// been built (BS-98, R1-02). A document that denies a feature of a public
/// repository next to a statement about permissions misleads whoever reads
/// it, so these tests read the documents.
void main() {
  /// Every Markdown file of the repository that a reader sees: the README and
  /// everything below `docs/`, path to text.
  final documents = <String, String>{
    'README.md': File('README.md').readAsStringSync(),
    for (final entity in Directory('docs').listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.md'))
        entity.path: entity.readAsStringSync(),
  };

  test('the documents are found (BS-98, R1-02)', () {
    expect(documents.length, greaterThan(15));
    expect(documents, contains('docs/known-limitations.md'));
    expect(documents, contains('docs/demo-script.md'));
  });

  test(
    'no document says that there is no Health connection (BS-98, R1-02)',
    () {
      final denials = <RegExp>[
        RegExp(r'keine\s+Health-Anbindung', caseSensitive: false),
        RegExp(r'ohne\s+Health-Anbindung', caseSensitive: false),
        RegExp(
          r'keine\s+Anbindung\s+an\s+(?:die\s+)?Health',
          caseSensitive: false,
        ),
      ];
      for (final MapEntry(key: path, value: text) in documents.entries) {
        for (final denial in denials) {
          final hit = denial.firstMatch(text);
          expect(
            hit,
            isNull,
            reason:
                '$path denies a Health connection ("${hit?.group(0)}"), but '
                'there is one for steps on Android (BS-97)',
          );
        }
      }
    },
  );

  test('the limits and the demo script name the connection that exists: only steps, only Android, only reading, switch off by default (BS-98, R1-02)', () {
    final limits = documents['docs/known-limitations.md']!;
    final demo = documents['docs/demo-script.md']!;

    final limit = RegExp(
      r'Eine Health-Anbindung gibt es nur für Schritte und nur unter Android'
      r'[^\n]*',
    ).firstMatch(limits);
    expect(limit, isNotNull, reason: 'the sentence of the limits');
    expect(limit!.group(0), contains('Health Connect'));
    expect(limit.group(0), contains('nur lesend'));
    expect(limit.group(0), contains('standardmäßig aus'));
    expect(limit.group(0), contains('iOS (HealthKit)'));
    expect(limit.group(0), contains('andere Datenarten'));

    final show = RegExp(r'Die App zählt keine Schritte selbst[^\n]*')
        .firstMatch(demo);
    expect(show, isNotNull, reason: 'the sentence of the demo script');
    expect(show!.group(0), contains('nur Android'));
    expect(show.group(0), contains('nur lesend'));
    expect(show.group(0), contains('standardmäßig aus'));
    expect(show.group(0), contains('Health Connect'));
    expect(show.group(0), contains('nur für Schritte'));
    expect(show.group(0), contains('nicht auf einem Gerät geprüft'));
  });
}
