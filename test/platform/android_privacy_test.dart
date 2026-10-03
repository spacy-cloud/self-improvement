import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the local-only privacy concept of V1 (no network, no auto backup of
/// the sensitive database) at the manifest level.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('the main manifest requests no network permission', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, isNot(contains('android.permission.INTERNET')));
    expect(manifest, isNot(contains('ACCESS_NETWORK_STATE')));
  });

  test('only the debug and profile manifests may add INTERNET (tooling)', () {
    expect(
      read('android/app/src/debug/AndroidManifest.xml'),
      contains('android.permission.INTERNET'),
      reason: 'Flutter tooling needs it in debug builds only',
    );
    expect(
      read('android/app/src/profile/AndroidManifest.xml'),
      contains('android.permission.INTERNET'),
    );
  });

  test('Android auto backup and device transfer exclude the database', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    final rules = read(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    );
    for (final section in ['cloud-backup', 'device-transfer']) {
      final start = rules.indexOf('<$section>');
      final end = rules.indexOf('</$section>');
      expect(start, greaterThanOrEqualTo(0), reason: section);
      final body = rules.substring(start, end);
      for (final domain in [
        'root',
        'file',
        'database',
        'sharedpref',
        'external',
      ]) {
        expect(
          body,
          contains('<exclude domain="$domain" />'),
          reason: '$section/$domain',
        );
      }
      expect(body, isNot(contains('<include')), reason: 'nothing is included');
    }
  });

  test('the app declares no unrelated sensitive permissions', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    for (final forbidden in [
      'ACTIVITY_RECOGNITION',
      'BODY_SENSORS',
      'READ_EXTERNAL_STORAGE',
      'WRITE_EXTERNAL_STORAGE',
      'ACCESS_FINE_LOCATION',
      'SCHEDULE_EXACT_ALARM',
      'USE_EXACT_ALARM',
      'FOREGROUND_SERVICE',
    ]) {
      expect(manifest, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
