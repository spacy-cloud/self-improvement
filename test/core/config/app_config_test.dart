import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/config/app_config.dart';

import '../../../tool/sync_app_name.dart' as sync;

void main() {
  test('native display names are synced with AppConfig.appName', () {
    final root = Directory.current.path;
    final strings = File('$root/android/app/src/main/res/values/strings.xml')
        .readAsStringSync();
    final plist = File('$root/ios/Runner/Info.plist').readAsStringSync();

    expect(strings, sync.androidStringsXml(AppConfig.appName));
    expect(
      plist,
      sync.iosInfoPlist(plist, AppConfig.appName),
      reason:
          'CFBundleDisplayName must equal AppConfig.appName; '
          'run: dart run tool/sync_app_name.dart',
    );
    expect(sync.readAppName(root), AppConfig.appName);
  });

  test('technical identifiers match native project files', () {
    final root = Directory.current.path;
    final gradle = File('$root/android/app/build.gradle.kts')
        .readAsStringSync();
    expect(gradle, contains('namespace = "${AppConfig.applicationId}"'));
    expect(gradle, contains('applicationId = "${AppConfig.applicationId}"'));
    final pbxproj = File('$root/ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    expect(
      pbxproj,
      contains('PRODUCT_BUNDLE_IDENTIFIER = ${AppConfig.applicationId};'),
    );
    expect(
      File(
        '$root/android/app/src/main/kotlin/'
        '${AppConfig.applicationId.replaceAll('.', '/')}/MainActivity.kt',
      ).existsSync(),
      isTrue,
    );
  });

  test('appVersion equals pubspec version without build number', () {
    final pubspec = File('${Directory.current.path}/pubspec.yaml')
        .readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(match!.group(1), AppConfig.appVersion);
  });

  test('backup format contract stays stable', () {
    expect(AppConfig.backupFormat, 'levelup_life_backup');
    expect(AppConfig.backupSchemaVersion, 2);
  });
}
