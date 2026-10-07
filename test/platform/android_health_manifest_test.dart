import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the Android project says about the health data (BS-97, D-031): one
/// read permission for the steps, the explanation Health Connect asks for, and
/// a native side that can only read. These tests read the files; they do not
/// run Android (the CI compiles it, a device is needed for everything else).
void main() {
  String read(String path) => File(path).readAsStringSync();

  final manifest = read('android/app/src/main/AndroidManifest.xml');
  const kotlinDir = 'android/app/src/main/kotlin/de/lf10/selfimprovement';

  /// The names of all `<uses-permission>` entries of [xml].
  List<String> permissions(String xml) => [
    for (final match in RegExp(
      r'<uses-permission\s+android:name="([^"]+)"',
    ).allMatches(xml))
      match.group(1)!,
  ];

  group('permissions', () {
    test('the app asks for exactly three permissions, one of them for '
        'reading steps (BS-97)', () {
      expect(
        permissions(manifest),
        unorderedEquals([
          'android.permission.POST_NOTIFICATIONS',
          'android.permission.RECEIVE_BOOT_COMPLETED',
          'android.permission.health.READ_STEPS',
        ]),
      );
    });

    test('no write permission, no background reading, no extended history '
        'and no other kind of health data (BS-97)', () {
      final health = permissions(manifest)
          .where((name) => name.startsWith('android.permission.health.'))
          .toList();
      expect(health, ['android.permission.health.READ_STEPS']);
      final all = permissions(manifest);
      for (final forbidden in [
        'WRITE_',
        'READ_HEALTH_DATA_IN_BACKGROUND',
        'READ_HEALTH_DATA_HISTORY',
        'READ_HEART_RATE',
        'READ_SLEEP',
        'READ_WEIGHT',
        'READ_EXERCISE',
        'READ_DISTANCE',
        'READ_MEDICAL_DATA',
        'ACTIVITY_RECOGNITION',
        'BODY_SENSORS',
      ]) {
        expect(
          all.where((name) => name.contains(forbidden)),
          isEmpty,
          reason: forbidden,
        );
      }
    });

    test('there is still no network permission in any manifest of the app '
        'itself (BS-97)', () {
      expect(manifest, isNot(contains('android.permission.INTERNET')));
      expect(manifest, isNot(contains('ACCESS_NETWORK_STATE')));
    });

    test('the debug and profile manifests add nothing but the tooling '
        'permission (BS-97)', () {
      for (final flavour in ['debug', 'profile']) {
        expect(
          permissions(read('android/app/src/$flavour/AndroidManifest.xml')),
          ['android.permission.INTERNET'],
          reason: flavour,
        );
      }
    });
  });

  group('the privacy explanation of Health Connect', () {
    test('an activity answers the intent up to Android 13 (BS-97)', () {
      expect(manifest, contains('android:name=".HealthRationaleActivity"'));
      expect(
        manifest,
        contains('androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE'),
      );
      final activity = _element(
        manifest,
        '<activity\n            android:name=".HealthRationaleActivity"',
      );
      expect(activity, contains('android:exported="true"'));
    });

    test('an alias answers VIEW_PERMISSION_USAGE from Android 14 on, behind '
        'the system permission only Health Connect holds (BS-97)', () {
      final alias = _element(manifest, '<activity-alias');
      expect(
        alias,
        contains('android:targetActivity=".HealthRationaleActivity"'),
      );
      expect(alias, contains('android:exported="true"'));
      expect(
        alias,
        contains(
          'android:permission="android.permission.START_VIEW_PERMISSION_USAGE"',
        ),
      );
      expect(alias, contains('android.intent.action.VIEW_PERMISSION_USAGE'));
      expect(alias, contains('android.intent.category.HEALTH_PERMISSIONS'));
    });

    test('the activity is a class of the app and uses no Flutter engine '
        '(BS-97)', () {
      final source = read('$kotlinDir/HealthRationaleActivity.kt');
      expect(source, contains('class HealthRationaleActivity : Activity()'));
      expect(source, isNot(contains('io.flutter')));
      expect(source, contains('R.string.health_rationale_text'));
    });

    test('the explanation says what the app reads and what it never does '
        '(BS-97)', () {
      final strings = read(
        'android/app/src/main/res/values/health_rationale.xml',
      );
      expect(strings, contains('name="health_rationale_title"'));
      expect(strings, contains('nur die Zahl deiner Schritte'));
      expect(strings, contains('keine Herzfrequenz'));
      expect(strings, contains('schreibt nichts in Health Connect'));
      expect(strings, contains('hat keine Internet-Berechtigung'));
      expect(strings, contains('Schalter in den Einstellungen'));
    });

    test('the strings are not in strings.xml: that file is generated and '
        'holds only the app name (BS-97)', () {
      final generated = read('android/app/src/main/res/values/strings.xml');
      expect(generated, isNot(contains('health_rationale')));
      expect(generated, contains('name="app_name"'));
    });

    test('the theme exists for light and dark (BS-97)', () {
      for (final folder in ['values', 'values-night']) {
        expect(
          read('android/app/src/main/res/$folder/styles.xml'),
          contains('name="HealthRationaleTheme"'),
          reason: folder,
        );
      }
      expect(manifest, contains('android:theme="@style/HealthRationaleTheme"'));
    });
  });

  group('package visibility', () {
    test('the app may see Health Connect, and no other app (BS-97)', () {
      final queries = _element(manifest, '<queries>', closing: '</queries>');
      final packages = [
        for (final match in RegExp(
          r'<package\s+android:name="([^"]+)"',
        ).allMatches(queries))
          match.group(1)!,
      ];
      expect(packages, ['com.google.android.apps.healthdata']);
    });
  });

  group('the native side (BS-97)', () {
    final plugin = read('$kotlinDir/HealthStepsPlugin.kt');

    test('it can only read steps: no write, no delete, no single records, no '
        'other record type', () {
      for (final forbidden in [
        'insertRecords',
        'updateRecords',
        'deleteRecords',
        'readRecords',
        'readRecord(',
        'getWritePermission',
        'WRITE_',
        'getChanges',
        'revokeAllPermissions',
      ]) {
        expect(plugin, isNot(contains(forbidden)), reason: forbidden);
      }
      final records = [
        for (final line in plugin.split('\n'))
          if (line.startsWith('import androidx.health.connect.client.records.'))
            line,
      ];
      expect(records, [
        'import androidx.health.connect.client.records.StepsRecord',
      ]);
      expect(
        plugin,
        contains('HealthPermission.getReadPermission(StepsRecord::class)'),
      );
      expect(plugin, contains('StepsRecord.COUNT_TOTAL'));
    });

    test('it asks for exactly one permission and starts the dialog only on '
        'request (BS-97)', () {
      expect(plugin, contains('setOf(STEPS_PERMISSION)'));
      // The dialog is started in one place only.
      expect('startActivityForResult'.allMatches(plugin).length, 1);
    });

    test('the totals come from the aggregation of Health Connect, which '
        'merges the sources (BS-97)', () {
      expect(plugin, contains('client.aggregate('));
      expect(plugin, contains('AggregateRequest('));
    });

    test('an error carries a code and a class name, never a message '
        '(BS-97)', () {
      expect(plugin, isNot(contains('error.message')));
      expect(plugin, isNot(contains('.localizedMessage')));
      expect(plugin, isNot(contains('printStackTrace')));
    });

    test('the activity registers the plugin in the engine (BS-97)', () {
      final main = read('$kotlinDir/MainActivity.kt');
      expect(main, contains('flutterEngine.plugins.add(HealthStepsPlugin())'));
    });
  });

  group('dependencies', () {
    final gradle = read('android/app/build.gradle.kts');

    test('the stable Health Connect client library and the coroutines it '
        'needs, nothing else for health (BS-97, D-031)', () {
      final dependencies = [
        for (final match in RegExp(
          r'implementation\("([^"]+)"\)',
        ).allMatches(gradle))
          match.group(1)!,
      ];
      expect(dependencies, [
        'androidx.health.connect:connect-client:1.1.0',
        'org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0',
      ]);
      expect(gradle, isNot(contains('alpha')));
      expect(gradle, isNot(contains('beta')));
    });

    test('the pub package "health" is not used: the app has its own '
        'channel and no iOS HealthKit code (BS-97, D-031)', () {
      final pubspec = read('pubspec.yaml');
      expect(pubspec, isNot(matches(RegExp(r'^\s+health:', multiLine: true))));
      expect(read('pubspec.lock'), isNot(contains('name: health\n')));
    });
  });
}

/// The element of [xml] that starts with [opening] up to its end tag
/// ([closing] or `</activity-alias>` / `</activity>`).
String _element(String xml, String opening, {String? closing}) {
  final start = xml.indexOf(opening);
  expect(start, greaterThanOrEqualTo(0), reason: opening);
  final end =
      closing ??
      (opening.startsWith('<activity-alias')
          ? '</activity-alias>'
          : '</activity>');
  final stop = xml.indexOf(end, start);
  expect(stop, greaterThan(start), reason: end);
  return xml.substring(start, stop + end.length);
}
