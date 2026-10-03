import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/platform/flutter_local_notifications_reminder_platform.dart';

/// Guards the layering of the reminder engine and the Android set-up it
/// depends on, by reading the sources (the tests run in the package root).
void main() {
  final root = Directory('lib/core/notifications');

  List<File> files(String subdirectory) =>
      Directory('${root.path}/$subdirectory')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();

  List<String> imports(File file) => file
      .readAsLinesSync()
      .where((line) => line.startsWith('import '))
      .toList();

  /// The two files that may talk to platform packages.
  bool isAdapter(File file) =>
      file.path.endsWith(
        'platform/flutter_local_notifications_reminder_platform.dart',
      ) ||
      file.path.endsWith('platform/device_time_zone.dart');

  group('layering', () {
    test('the sources exist', () {
      expect(files('domain'), isNotEmpty);
      expect(files('data'), isNotEmpty);
      expect(files('platform'), isNotEmpty);
      expect(files('application'), isNotEmpty);
    });

    test('only the adapter files import platform packages', () {
      const forbidden = [
        'package:flutter_local_notifications',
        'package:flutter_timezone',
        'package:timezone/',
        'package:flutter/services.dart',
        'dart:io',
        'dart:ui',
      ];
      final offenders = <String>[];
      for (final file in files('.')) {
        if (isAdapter(file)) {
          continue;
        }
        for (final line in imports(file)) {
          if (forbidden.any(line.contains)) {
            offenders.add('${file.path}: $line');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('the adapter files are the only ones that do', () {
      final adapters = files('.').where(isAdapter).toList();
      expect(adapters, hasLength(2));
      for (final adapter in adapters) {
        expect(
          imports(adapter).any(
            (line) =>
                line.contains('package:flutter_local_notifications') ||
                line.contains('package:flutter_timezone'),
          ),
          isTrue,
          reason: adapter.path,
        );
      }
    });

    test('the domain knows no database, no state management, no platform', () {
      const forbidden = [
        'package:drift',
        'package:flutter_riverpod',
        'package:flutter/material.dart',
        'package:flutter/widgets.dart',
        'core/database/app_database.dart',
        'core/providers/',
        'core/notifications/data/',
        'core/notifications/platform/',
        'core/notifications/application/',
      ];
      final offenders = <String>[];
      for (final file in files('domain')) {
        for (final line in imports(file)) {
          if (forbidden.any(line.contains)) {
            offenders.add('${file.path}: $line');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('the platform interface knows only the domain', () {
      final offenders = <String>[];
      for (final file in files('platform')) {
        if (isAdapter(file) ||
            file.path.endsWith('fake_reminder_platform.dart')) {
          continue;
        }
        for (final line in imports(file)) {
          if (line.contains('core/notifications/data/') ||
              line.contains('core/notifications/application/') ||
              line.contains('package:drift')) {
            offenders.add('${file.path}: $line');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('no widgets and no riverpod outside the application layer', () {
      final offenders = <String>[];
      for (final subdirectory in ['domain', 'data', 'platform']) {
        for (final file in files(subdirectory)) {
          for (final line in imports(file)) {
            if (line.contains('package:flutter_riverpod') ||
                line.contains('package:flutter/material.dart') ||
                line.contains('package:flutter/widgets.dart')) {
              offenders.add('${file.path}: $line');
            }
          }
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('project rules', () {
    String strip(String source) => source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    test('time comes from the clock, never from DateTime.now', () {
      for (final file in files('.')) {
        expect(
          strip(file.readAsStringSync()),
          isNot(contains('DateTime.now')),
          reason: file.path,
        );
      }
    });

    test('calendar days are never advanced by fixed 24 hour durations', () {
      for (final file in files('.')) {
        final source = strip(file.readAsStringSync());
        expect(
          source,
          isNot(contains('Duration(hours: 24)')),
          reason: file.path,
        );
        expect(source, isNot(contains('Duration(days:')), reason: file.path);
      }
    });

    test('integer ids are never derived from hash codes', () {
      for (final file in files('.')) {
        final source = strip(file.readAsStringSync());
        // Overriding hashCode for value equality is fine; reading it is not.
        expect(
          RegExp(r'[A-Za-z_)\]]\.hashCode').hasMatch(source),
          isFalse,
          reason: file.path,
        );
      }
    });

    test('nothing prints and nothing reads a network', () {
      for (final file in files('.')) {
        final source = strip(file.readAsStringSync());
        expect(
          RegExp(r'\bprint\(').hasMatch(source),
          isFalse,
          reason: file.path,
        );
        expect(source, isNot(contains('dart:io')), reason: file.path);
        expect(source, isNot(contains('http')), reason: file.path);
      }
    });
  });

  group('android set-up', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml');

    test('the manifest has what scheduled notifications and reboots need', () {
      final xml = manifest.readAsStringSync();
      expect(xml, contains('android.permission.POST_NOTIFICATIONS'));
      expect(xml, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
      expect(
        xml,
        contains(
          'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver',
        ),
      );
      expect(
        xml,
        contains(
          'com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver',
        ),
      );
      for (final action in [
        'android.intent.action.BOOT_COMPLETED',
        'android.intent.action.MY_PACKAGE_REPLACED',
      ]) {
        expect(xml, contains(action));
      }
    });

    test('the receivers are not exported', () {
      final xml = manifest.readAsStringSync();
      final receivers = RegExp(r'<receiver[^>]*>').allMatches(xml).toList();
      expect(receivers, hasLength(2));
      for (final receiver in receivers) {
        expect(receiver.group(0), contains('android:exported="false"'));
      }
    });

    test(
      'there is no exact alarm permission, no foreground service, no network',
      () {
        final xml = manifest.readAsStringSync();
        for (final forbidden in [
          'SCHEDULE_EXACT_ALARM',
          'USE_EXACT_ALARM',
          'FOREGROUND_SERVICE',
          'ForegroundService',
          'android.permission.INTERNET',
          'USE_FULL_SCREEN_INTENT',
        ]) {
          expect(xml, isNot(contains(forbidden)), reason: forbidden);
        }
      },
    );

    test('the status bar icon exists and survives resource shrinking', () {
      final name = FlutterLocalNotificationsReminderPlatform.androidIconName;
      expect(
        File('android/app/src/main/res/drawable/$name.xml').existsSync(),
        isTrue,
      );
      final keep = File('android/app/src/main/res/raw/keep.xml')
          .readAsStringSync();
      expect(keep, contains('@drawable/$name'));
    });
  });
}
