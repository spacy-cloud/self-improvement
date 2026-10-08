import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/platform_names.dart';

/// What the iOS project says about the health data (BS-122, D-034): one read
/// permission for the steps, one entitlement, and a native side that can only
/// read. These tests read the files; they do not run iOS. The CI only compiles
/// the project, and nothing here has run on an iPhone: whether the entitlement
/// survives the signing of SideStore with a free Apple ID is the open question
/// of BS-122.
void main() {
  String read(String path) => File(path).readAsStringSync();

  final plist = read('ios/Runner/Info.plist');
  final entitlements = read('ios/Runner/Runner.entitlements');
  final pbxproj = read('ios/Runner.xcodeproj/project.pbxproj');
  final swift = read('ios/Runner/HealthStepsPlugin.swift');
  final guardSource = read('ios/Runner/HealthExceptionGuard.m');

  /// The keys of the top-level dictionary of a plist, in order.
  List<String> keysOf(String xml) => [
    for (final match in RegExp(r'<key>([^<]+)</key>').allMatches(xml))
      match.group(1)!,
  ];

  group('the permission', () {
    test('the Info.plist explains the read access: only reading, only '
        'steps, and no platform name (BS-122)', () {
      final match = RegExp(
        r'<key>NSHealthShareUsageDescription</key>\s*<string>([^<]+)</string>',
      ).firstMatch(plist);
      expect(match, isNotNull, reason: 'the usage description');
      final text = match!.group(1)!;
      expect(text, contains('Apple Health'));
      expect(text, contains('nur lesend'));
      expect(text, contains('nur Schritte'));
      expect(text, contains('nur auf diesem Gerät'));
      expect(platformNameIn(text), isNull);
    });

    test('no writing, no health records, and no required device capability: '
        'the app also runs where HealthKit does not exist (BS-122)', () {
      for (final forbidden in [
        'NSHealthUpdateUsageDescription',
        'NSHealthClinicalHealthRecordsShareUsageDescription',
        'UIRequiredDeviceCapabilities',
        'healthkit',
      ]) {
        expect(plist, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });

  group('the entitlement', () {
    test('it is exactly one: HealthKit, without health records and without '
        'background delivery (BS-122)', () {
      expect(keysOf(entitlements), ['com.apple.developer.healthkit']);
      expect(
        RegExp(r'<key>com\.apple\.developer\.healthkit</key>\s*<true/>')
            .hasMatch(entitlements),
        isTrue,
      );
    });

    test('the Runner target uses the file in all three configurations '
        '(BS-122)', () {
      expect(
        'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
            .allMatches(pbxproj)
            .length,
        3,
      );
      expect(pbxproj, contains('path = Runner.entitlements;'));
    });

    test('the project compiles the plugin and the exception guard, and Swift '
        'sees the guard through the bridging header (BS-122)', () {
      expect(pbxproj, contains('HealthStepsPlugin.swift in Sources'));
      expect(pbxproj, contains('HealthExceptionGuard.m in Sources'));
      expect(
        read('ios/Runner/Runner-Bridging-Header.h'),
        contains('#import "HealthExceptionGuard.h"'),
      );
    });

    test('the plugin is registered in the engine of the app (BS-122)', () {
      final delegate = read('ios/Runner/AppDelegate.swift');
      expect(delegate, contains('registrar(forPlugin: "HealthStepsPlugin")'));
      expect(delegate, contains('HealthStepsPlugin.register(with: registrar)'));
    });
  });

  group('the native side (BS-122)', () {
    test('it can only read steps: nothing is shared, nothing is saved, '
        'deleted or observed, and no other type is named', () {
      for (final forbidden in [
        'HKSampleQuery',
        'HKAnchoredObjectQuery',
        'HKObserverQuery',
        'HKStatisticsCollectionQuery',
        'HKWorkout',
        'HKCategoryType',
        'HKCharacteristicType',
        'HKCorrelationType',
        'HKClinicalType',
        'enableBackgroundDelivery',
        'store.save(',
        'store.delete(',
        '.save(',
        '.delete(',
        'healthRecords',
      ]) {
        expect(swift, isNot(contains(forbidden)), reason: forbidden);
      }
      final identifiers = [
        for (final match in RegExp(
          r'HKQuantityType\(\.(\w+)\)',
        ).allMatches(swift))
          match.group(1)!,
      ];
      expect(identifiers, ['stepCount']);
      // Every set of types to share is empty.
      final shares = RegExp(r'toShare:\s*(\S+)').allMatches(swift).toList();
      expect(shares, isNotEmpty);
      for (final match in shares) {
        expect(match.group(1), startsWith('[]'), reason: match.group(0));
      }
    });

    test('it asks for exactly one permission and starts the dialog in one '
        'place (BS-122)', () {
      expect('requestAuthorization('.allMatches(swift).length, 1);
      expect(
        swift,
        contains('private var readTypes: Set<HKObjectType> { [stepType] }'),
      );
    });

    test('the totals come from the statistics of HealthKit, which merge the '
        'sources, and a sample counts on the day it starts (BS-122)', () {
      expect(swift, contains('HKStatisticsQuery('));
      expect(swift, contains('options: .cumulativeSum'));
      expect(swift, contains('options: .strictStartDate'));
    });

    test('every call that can raise runs inside the exception guard, which '
        'catches the exception and hands on only a reason (BS-122)', () {
      final calls =
          'requestAuthorization('.allMatches(swift).length +
          'getRequestStatusForAuthorization('.allMatches(swift).length +
          'store.execute('.allMatches(swift).length;
      expect(
        'HealthExceptionGuard.runAndCatch'.allMatches(swift).length,
        calls,
      );
      expect(guardSource, contains('@try'));
      expect(guardSource, contains('@catch (NSException *exception)'));
      expect(guardSource, contains('exception.reason'));
    });

    test('an error carries a code and a class name, never a message '
        '(BS-122)', () {
      expect(swift, isNot(contains('localizedDescription')));
      expect(swift, isNot(contains('error.userInfo')));
      expect(swift, isNot(contains('print(')));
      expect(swift, isNot(contains('NSLog(')));
      expect(swift, contains('details: String(describing: type(of: error))'));
    });

    test('the totals are never logged and never sent anywhere: the file has '
        'no network call (BS-122)', () {
      for (final forbidden in ['URLSession', 'URLRequest', 'Network']) {
        expect(swift, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });

  group('the build of the IPA (BS-122)', () {
    final workflow = read('.github/workflows/ios-ipa.yml');

    test('the workflow carries the entitlements in an ad-hoc signature and '
        'checks that they are in the binary (BS-122)', () {
      final flat = workflow.replaceAll(RegExp(r'\s*\\\n\s*'), ' ');
      expect(
        flat,
        contains(
          'codesign --force --sign - --identifier de.lf10.selfimprovement '
          '--entitlements ios/Runner/Runner.entitlements "\$exe"',
        ),
      );
      expect(workflow, contains('grep -q "com.apple.developer.healthkit"'));
    });

    test('still no certificate, no profile and no secret (BS-95, BS-122)', () {
      for (final forbidden in [
        'secrets.',
        'p12',
        'security import',
        'mobileprovision',
        'CODE_SIGN_IDENTITY',
        'APPLE_',
      ]) {
        expect(workflow, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });
}
