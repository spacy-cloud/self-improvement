import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android manifests of the plugins end up in the manifest of the app when
/// it is built. `url_launcher` opens the website of the page "Über die App" in
/// the browser of the system, so the app needs no network permission of its own
/// (BS-118). These tests read what the plugin adds from the packages that
/// `flutter pub get` resolved, so a later version that adds a permission or a
/// `<queries>` entry shows up here by name.
///
/// They read the manifest of the plugin itself. The merged manifest of a build
/// (which also holds what the AndroidX libraries of the plugin declare) can
/// only be read after a real Android build.
Directory packageRoot(String name) {
  final configFile = File('.dart_tool/package_config.json');
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
  final packages = (config['packages']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final entry = packages.firstWhere((package) => package['name'] == name);
  return Directory.fromUri(
    configFile.absolute.uri.resolve(entry['rootUri']! as String),
  );
}

void main() {
  late String pluginManifest;

  setUpAll(() {
    final root = packageRoot('url_launcher_android');
    pluginManifest = File('${root.path}/android/src/main/AndroidManifest.xml')
        .readAsStringSync();
  });

  test('the package and its Android and iOS parts are locked (BS-118)', () {
    final lock = File('pubspec.lock').readAsStringSync();
    for (final name in <String>[
      'url_launcher',
      'url_launcher_android',
      'url_launcher_ios',
    ]) {
      expect(lock, contains('\n  $name:\n'), reason: '$name in pubspec.lock');
    }
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('\n  url_launcher: '),
      reason: 'a direct dependency, because the app calls it',
    );
  });

  test('the plugin manifest adds no permission, in particular no INTERNET', () {
    expect(pluginManifest, isNot(contains('uses-permission')));
    expect(pluginManifest, isNot(contains('INTERNET')));
  });

  test('the plugin manifest declares no <queries>: none is needed because the '
      'app launches without canLaunchUrl', () {
    expect(pluginManifest, isNot(contains('<queries')));
  });

  test('the plugin declares only its own web view activity, not exported', () {
    final activities = RegExp(r'<activity\b[^>]*>')
        .allMatches(pluginManifest)
        .map((match) => match.group(0)!)
        .toList();
    expect(activities, hasLength(1));
    expect(activities.single, contains('WebViewActivity'));
    expect(activities.single, contains('android:exported="false"'));
  });
}
