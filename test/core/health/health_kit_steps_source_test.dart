import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';
import 'package:self_improvement/core/health/platform/health_connect_steps_source.dart';
import 'package:self_improvement/core/health/platform/health_kit_steps_source.dart';

/// The Dart side of the channel to HealthKit, against a mocked channel (BS-122,
/// D-034). The native side and the real HealthKit are not covered: there is no
/// macOS in the development run, the CI only compiles it, and whether the
/// entitlement survives the signing of SideStore is the open question of
/// BS-122.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(HealthKitStepsSource.channelName);

  late HealthKitStepsSource source;
  late List<MethodCall> calls;

  /// Answers the channel with [handler] and records every call.
  void answer(Future<Object?> Function(MethodCall call) handler) {
    calls = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return handler(call);
    });
  }

  Matcher failure(HealthFailureKind kind) => throwsA(
    isA<HealthStepsException>().having((error) => error.kind, 'kind', kind),
  );

  setUp(() {
    source = HealthKitStepsSource();
    calls = [];
  });
  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  group('availability (BS-122)', () {
    for (final (answerText, expected) in <(String, HealthAvailability)>[
      ('available', HealthAvailability.available),
      ('unsupported', HealthAvailability.unsupported),
    ]) {
      test('"$answerText" is ${expected.name}', () async {
        answer((call) async => answerText);
        expect(await source.availability(), expected);
        expect(calls.single.method, 'availability');
        expect(calls.single.arguments, isNull);
      });
    }

    test('the Health app is part of iOS: "missing" and "updateRequired" do '
        'not exist, so those answers are a failure, not a guess', () async {
      for (final text in ['missing', 'updateRequired', 'maybe']) {
        answer((call) async => text);
        await expectLater(
          source.availability(),
          failure(HealthFailureKind.failed),
          reason: text,
        );
      }
      answer((call) async => null);
      await expectLater(
        source.availability(),
        throwsA(isA<HealthStepsException>()),
      );
    });

    test('no native side behind the channel means no interface on this '
        'device', () async {
      // No handler at all: the channel answers with a missing plugin.
      expect(await source.availability(), HealthAvailability.unsupported);
    });

    test('a build without the HealthKit entitlement is "unsupported", so the '
        'switch stays hidden instead of the app failing (BS-122)', () async {
      answer(
        (call) async => throw PlatformException(code: 'entitlement_missing'),
      );
      expect(await source.availability(), HealthAvailability.unsupported);
    });

    test('a failing native call is a failure, not "unsupported"', () async {
      answer((call) async => throw PlatformException(code: 'failed'));
      await expectLater(
        source.availability(),
        throwsA(isA<HealthStepsException>()),
      );
    });
  });

  group('access (BS-122)', () {
    test('hasAccess reads whether the user was asked and shows no dialog; '
        'it cannot say whether reading was allowed', () async {
      answer((call) async => true);
      expect(await source.access(), HealthAccess.granted);
      expect(calls.single.method, 'hasAccess');
      answer((call) async => false);
      expect(await source.access(), HealthAccess.denied);
      answer((call) async => null);
      expect(await source.access(), HealthAccess.denied);
    });

    test('requestAccess is the call that shows the dialog and returns '
        'whether the request was processed', () async {
      answer((call) async => true);
      expect(await source.requestAccess(), HealthAccess.granted);
      expect(calls.single.method, 'requestAccess');
      answer((call) async => false);
      expect(await source.requestAccess(), HealthAccess.denied);
    });

    test('an error of HealthKit is a failure; a missing entitlement is '
        '"unavailable"', () async {
      answer((call) async => throw PlatformException(code: 'failed'));
      await expectLater(
        source.requestAccess(),
        failure(HealthFailureKind.failed),
      );
      await expectLater(source.access(), failure(HealthFailureKind.failed));
      answer(
        (call) async => throw PlatformException(code: 'entitlement_missing'),
      );
      await expectLater(
        source.requestAccess(),
        failure(HealthFailureKind.unavailable),
      );
      await expectLater(
        source.access(),
        failure(HealthFailureKind.unavailable),
      );
    });
  });

  group('the total of a time range (BS-122)', () {
    final start = DateTime.utc(2026, 10, 2, 22);
    final end = DateTime.utc(2026, 10, 3, 22);

    test('sends the range as UTC milliseconds and returns the total', () async {
      answer((call) async => 7450);
      expect(await source.totalSteps(startUtc: start, endUtc: end), 7450);
      final call = calls.single;
      expect(call.method, 'totalSteps');
      expect(call.arguments, {
        'startUtcMillis': start.millisecondsSinceEpoch,
        'endUtcMillis': end.millisecondsSinceEpoch,
      });
    });

    test('no data is null and a recorded 0 is 0', () async {
      answer((call) async => null);
      expect(await source.totalSteps(startUtc: start, endUtc: end), isNull);
      answer((call) async => 0);
      expect(await source.totalSteps(startUtc: start, endUtc: end), 0);
    });

    test('a negative total is refused', () async {
      answer((call) async => -1);
      await expectLater(
        source.totalSteps(startUtc: start, endUtc: end),
        throwsA(isA<HealthStepsException>()),
      );
    });

    test('a refused or not yet asked access is "accessDenied", the rest is '
        '"failed"', () async {
      answer(
        (call) async =>
            throw PlatformException(code: 'access_denied', details: 'x'),
      );
      await expectLater(
        source.totalSteps(startUtc: start, endUtc: end),
        failure(HealthFailureKind.accessDenied),
      );
      for (final code in ['failed', 'bad_arguments']) {
        answer((call) async => throw PlatformException(code: code));
        await expectLater(
          source.totalSteps(startUtc: start, endUtc: end),
          failure(HealthFailureKind.failed),
          reason: code,
        );
      }
    });

    test('the text of a platform error never travels on, only the class '
        'name of the cause', () async {
      answer(
        (call) async => throw PlatformException(
          code: 'failed',
          message: 'secret 7450 steps for 2026-10-03',
          details: 'HKError',
        ),
      );
      try {
        await source.totalSteps(startUtc: start, endUtc: end);
        fail('expected a failure');
      } on HealthStepsException catch (error) {
        expect(error.causeType, 'HKError');
        expect(error.toString(), isNot(contains('secret')));
        expect(error.toString(), isNot(contains('7450')));
      }
    });

    test('without a native side the read is "unavailable"', () async {
      await expectLater(
        source.totalSteps(startUtc: start, endUtc: end),
        failure(HealthFailureKind.unavailable),
      );
    });
  });

  group('the pages of the system (BS-122)', () {
    test('there is no install page: the Health app is part of iOS, and the '
        'channel is not asked', () async {
      answer((call) async => true);
      expect(await source.openInstallPage(), isFalse);
      expect(calls, isEmpty);
    });

    test('the access settings open the Health app and report whether a page '
        'was opened', () async {
      answer((call) async => true);
      expect(await source.openAccessSettings(), isTrue);
      expect(calls.single.method, 'openAccessSettings');
      answer((call) async => false);
      expect(await source.openAccessSettings(), isFalse);
      answer((call) async => null);
      expect(await source.openAccessSettings(), isFalse);
    });

    test('a failing or missing native side is "nothing opened", never an '
        'error', () async {
      expect(await source.openAccessSettings(), isFalse);
      answer((call) async => throw PlatformException(code: 'failed'));
      expect(await source.openAccessSettings(), isFalse);
    });
  });

  group('the contract with the native side (BS-122)', () {
    test(
      'the adapter only ever calls the five methods of the channel',
      () async {
        answer((call) async {
          return switch (call.method) {
            'availability' => 'available',
            'totalSteps' => 1,
            _ => true,
          };
        });
        await source.availability();
        await source.access();
        await source.requestAccess();
        await source.totalSteps(
          startUtc: DateTime.utc(2026, 10, 2),
          endUtc: DateTime.utc(2026, 10, 3),
        );
        await source.openInstallPage();
        await source.openAccessSettings();
        expect(calls.map((call) => call.method).toSet(), {
          HealthKitStepsSource.methodAvailability,
          HealthKitStepsSource.methodHasAccess,
          HealthKitStepsSource.methodRequestAccess,
          HealthKitStepsSource.methodTotalSteps,
          HealthKitStepsSource.methodOpenAccessSettings,
        });
      },
    );

    test('both platforms speak one channel with the same names, so the steps '
        'feature cannot tell them apart (BS-97, BS-122)', () {
      expect(
        HealthKitStepsSource.channelName,
        HealthConnectStepsSource.channelName,
      );
      expect(
        HealthKitStepsSource.methodAvailability,
        HealthConnectStepsSource.methodAvailability,
      );
      expect(
        HealthKitStepsSource.methodHasAccess,
        HealthConnectStepsSource.methodHasAccess,
      );
      expect(
        HealthKitStepsSource.methodRequestAccess,
        HealthConnectStepsSource.methodRequestAccess,
      );
      expect(
        HealthKitStepsSource.methodTotalSteps,
        HealthConnectStepsSource.methodTotalSteps,
      );
      expect(
        HealthKitStepsSource.methodOpenAccessSettings,
        HealthConnectStepsSource.methodOpenAccessSettings,
      );
      expect(
        HealthKitStepsSource.answerAvailable,
        HealthConnectStepsSource.answerAvailable,
      );
      expect(
        HealthKitStepsSource.errorAccessDenied,
        HealthConnectStepsSource.errorAccessDenied,
      );
    });

    test('the native class knows the channel, every method, every answer and '
        'every error code of this file', () {
      final swift = File('ios/Runner/HealthStepsPlugin.swift')
          .readAsStringSync();
      expect(
        swift,
        contains(
          'static let channelName = "${HealthKitStepsSource.channelName}"',
        ),
      );
      for (final method in [
        HealthKitStepsSource.methodAvailability,
        HealthKitStepsSource.methodHasAccess,
        HealthKitStepsSource.methodRequestAccess,
        HealthKitStepsSource.methodTotalSteps,
        HealthKitStepsSource.methodOpenAccessSettings,
      ]) {
        expect(swift, contains('case "$method":'), reason: method);
      }
      for (final text in [
        HealthKitStepsSource.answerAvailable,
        HealthKitStepsSource.answerUnsupported,
      ]) {
        expect(swift, contains('reply(result, "$text")'), reason: text);
      }
      for (final code in [
        HealthKitStepsSource.errorAccessDenied,
        HealthKitStepsSource.errorEntitlementMissing,
      ]) {
        expect(swift, contains('= "$code"'), reason: code);
      }
      expect(swift, contains('"startUtcMillis"'));
      expect(swift, contains('"endUtcMillis"'));
    });

    test('the display name is the one of the Health app', () {
      expect(source.displayName, 'Apple Health');
    });
  });
}
