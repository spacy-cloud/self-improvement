// Lists which automated tests mention which acceptance case (AT01-AT36).
//
// Usage (repository root): dart run tool/at_coverage.dart [--markdown]
//
// A test counts for an AT id when the id appears in the name of the `test`,
// `testWidgets` or `group` call (e.g. `test('... (AT12)', ...)`). This is an
// evidence index for docs/requirements-matrix.md, not a proof of correctness.
import 'dart:io';

final RegExp _callPattern = RegExp(
  r'''(?:test|testWidgets|group)\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
);
final RegExp _atPattern = RegExp(r'AT(\d{2})(?:\s*[-–]\s*AT(\d{2}))?');

void main(List<String> args) {
  final markdown = args.contains('--markdown');
  final byAt = <String, Map<String, int>>{};
  for (final root in ['test', 'integration_test']) {
    final dir = Directory(root);
    if (!dir.existsSync()) {
      continue;
    }
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('_test.dart')) {
        continue;
      }
      final text = entity.readAsStringSync();
      for (final call in _callPattern.allMatches(text)) {
        final name = call.group(1) ?? call.group(2) ?? '';
        for (final at in _atPattern.allMatches(name)) {
          final from = int.parse(at.group(1)!);
          final to = at.group(2) == null ? from : int.parse(at.group(2)!);
          for (var n = from; n <= to; n++) {
            final id = 'AT${n.toString().padLeft(2, '0')}';
            final files = byAt.putIfAbsent(id, () => {});
            files[entity.path] = (files[entity.path] ?? 0) + 1;
          }
        }
      }
    }
  }
  for (var n = 1; n <= 36; n++) {
    final id = 'AT${n.toString().padLeft(2, '0')}';
    final files = byAt[id];
    if (files == null) {
      stdout.writeln(
        markdown ? '| $id | _kein Test benennt diesen Fall_ |' : '$id: none',
      );
      continue;
    }
    final entries = files.entries
        .map((e) => '${e.key} (${e.value})')
        .join(', ');
    stdout.writeln(markdown ? '| $id | $entries |' : '$id: $entries');
  }
}
