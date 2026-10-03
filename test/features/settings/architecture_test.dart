import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'profile and settings never ask for a permission by themselves (AT28)',
    () {
      // The reminders block owns the permission flow ("Erlaubnis nur nach
      // Tippen"); nothing in the profile or settings code may reach for the
      // notification plugin or its platform adapters.
      final offenders = <String>[];
      for (final root in ['lib/features/profile', 'lib/features/settings']) {
        for (final entity in Directory(root).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) {
            continue;
          }
          for (final line in entity.readAsLinesSync()) {
            final isImport = line.trimLeft().startsWith('import ');
            if (isImport &&
                (line.contains('flutter_local_notifications') ||
                    line.contains('core/notifications') ||
                    line.contains('permission'))) {
              offenders.add('${entity.path}: $line');
            }
          }
        }
      }
      expect(offenders, isEmpty);
    },
  );

  test(
    'the settings screens use no hard-coded colours or sizes (design system)',
    () {
      final offenders = <String>[];
      for (final root in [
        'lib/features/profile/presentation',
        'lib/features/settings/presentation',
      ]) {
        for (final entity in Directory(root).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) {
            continue;
          }
          final text = entity.readAsStringSync();
          if (RegExp(r'Color\(0x|Colors\.(?!transparent)\w+').hasMatch(text)) {
            offenders.add(entity.path);
          }
        }
      }
      expect(offenders, isEmpty);
    },
  );
}
