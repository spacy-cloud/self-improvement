import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the design of the flow tests: both entry points (the emulator test
/// and the host test) run the same flows, and a flow body knows nothing about
/// where it runs and never waits by sleeping.
///
/// These tests read the sources, so they run on the host without a device.
void main() {
  final device = File('integration_test/app_flows_test.dart');
  final host = File('test/app/flows/app_flows_host_test.dart');
  final flowDir = Directory('integration_test/flows');

  final testNamePattern = RegExp(
    r'''testWidgets\(\s*(?:'([^']*)'|"([^"]*)")''',
    multiLine: true,
  );
  // Adjacent string literals ('a ' 'b') are joined by the parser; the entry
  // points keep every name on one literal so this pattern sees all of it.
  final flowCallPattern = RegExp(r'_runFlow\(\s*tester,\s*(\w+)\s*\)');

  List<String> testNames(File file) => <String>[
    for (final match in testNamePattern.allMatches(file.readAsStringSync()))
      (match.group(1) ?? match.group(2)!).replaceAll(RegExp(r'\s+'), ' '),
  ];

  List<String> flowCalls(File file) => <String>[
    for (final match in flowCallPattern.allMatches(file.readAsStringSync()))
      match.group(1)!,
  ];

  /// The files that define flows (`*_flow.dart`), each used by both entries.
  List<File> flowFiles() => <File>[
    for (final entity in flowDir.listSync())
      if (entity is File && entity.path.endsWith('_flow.dart')) entity,
  ];

  /// Everything a flow runs through, except the context that hosts the waiting
  /// helpers (it is the one place with a real-time delay on purpose).
  List<File> flowBodies() => <File>[
    for (final entity in flowDir.listSync())
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          !entity.path.endsWith('flow_context.dart'))
        entity,
  ];

  /// The source without comments, so the rules do not trip over prose.
  String code(File file) => file
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('both entry points exist and run flows', () {
    expect(device.existsSync(), isTrue);
    expect(host.existsSync(), isTrue);
    expect(flowCalls(device), isNotEmpty);
  });

  test('the emulator and the host run the same flows under the same names', () {
    expect(
      flowCalls(host),
      flowCalls(device),
      reason: 'every flow must run on the emulator and on the host',
    );
    expect(
      testNames(host),
      testNames(device),
      reason: 'the test names carry the acceptance ids, keep them identical',
    );
  });

  test('every flow file is used by both entry points', () {
    final deviceCode = device.readAsStringSync();
    final hostCode = host.readAsStringSync();
    for (final file in flowFiles()) {
      final name = file.uri.pathSegments.last;
      expect(deviceCode, contains("flows/$name'"), reason: '$name on device');
      expect(hostCode, contains("flows/$name'"), reason: '$name on host');
    }
  });

  test('flow bodies never wait by sleeping or by settling', () {
    for (final file in flowBodies()) {
      final source = code(file);
      for (final forbidden in <String>[
        'pumpAndSettle',
        'Future.delayed',
        'Future<void>.delayed',
        'sleep(',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason:
              '${file.path} must wait for the screen (ctx.waitFor...), '
              'not with $forbidden',
        );
      }
    }
  });

  test('flow bodies do not depend on where they run', () {
    for (final file in flowBodies()) {
      final source = code(file);
      for (final forbidden in <String>[
        'dart:io',
        'FakeClock',
        'DataHarness',
        'FakeReminderPlatform',
        'defaultTargetPlatform',
        'kIsWeb',
        'getApplicationSupportDirectory',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason:
              '${file.path} must stay the same on the host and on the '
              'emulator: the difference belongs in the entry point '
              '($forbidden)',
        );
      }
    }
  });
}
