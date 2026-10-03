// Synchronises the native display names with `AppConfig.appName`.
//
// Usage (from the repository root):
//   dart run tool/sync_app_name.dart          # rewrite native files
//   dart run tool/sync_app_name.dart --check  # exit 1 if files are out of sync
import 'dart:io';

final RegExp _appNamePattern = RegExp(
  r"static const String appName = '([^']*)';",
);

String readAppName(String root) {
  final source = File('$root/lib/core/config/app_config.dart')
      .readAsStringSync();
  final match = _appNamePattern.firstMatch(source);
  if (match == null) {
    throw StateError('AppConfig.appName not found in app_config.dart');
  }
  return match.group(1)!;
}

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String androidStringsXml(String appName) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Synced from lib/core/config/app_config.dart by tool/sync_app_name.dart. -->
    <string name="app_name">${_escapeXml(appName)}</string>
</resources>
''';

final RegExp _displayNamePattern = RegExp(
  r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)',
);

String iosInfoPlist(String current, String appName) =>
    current.replaceFirstMapped(
      _displayNamePattern,
      (m) => '${m.group(1)}${_escapeXml(appName)}${m.group(2)}',
    );

void main(List<String> args) {
  final check = args.contains('--check');
  final root = Directory.current.path;
  final appName = readAppName(root);

  final androidFile = File('$root/android/app/src/main/res/values/strings.xml');
  final plistFile = File('$root/ios/Runner/Info.plist');

  final androidWanted = androidStringsXml(appName);
  final plistWanted = iosInfoPlist(plistFile.readAsStringSync(), appName);

  final inSync =
      androidFile.existsSync() &&
      androidFile.readAsStringSync() == androidWanted &&
      plistFile.readAsStringSync() == plistWanted;

  if (check) {
    if (!inSync) {
      stderr.writeln(
        'Native display names are out of sync with AppConfig.appName.',
      );
      exit(1);
    }
    stdout.writeln('Native display names are in sync ("$appName").');
    return;
  }

  androidFile.writeAsStringSync(androidWanted);
  plistFile.writeAsStringSync(plistWanted);
  stdout.writeln('Synced native display names to "$appName".');
}
