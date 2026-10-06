import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile and settings never ask for a permission by themselves', () {
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
  });

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

  test('web addresses are opened by one adapter, in the external browser and '
      'without canLaunchUrl (BS-118)', () {
    // `launchUrl` in the external mode needs no <queries> entry in the Android
    // manifest, `canLaunchUrl` would. The default mode opens a web view inside
    // the app for a web address. So the one place that knows `url_launcher`
    // asks for the external mode and never for the check.
    // The source without its comment lines, so that the explanation in the
    // adapter does not trip the scan.
    String code(File file) => file
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    final users = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final text = code(entity);
      if (text.contains('package:url_launcher')) {
        users.add(entity.path);
      }
      expect(text, isNot(contains('canLaunchUrl')), reason: entity.path);
      expect(text, isNot(contains('canLaunch(')), reason: entity.path);
    }
    expect(users, <String>[
      'lib/features/settings/application/external_link_opener.dart',
    ]);

    final adapter = code(File(users.single));
    expect(adapter, contains('mode: LaunchMode.externalApplication'));
    expect(adapter, isNot(contains('LaunchMode.platformDefault')));
    expect(adapter, isNot(contains('LaunchMode.inApp')));
  });
}
