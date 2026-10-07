import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';
import 'package:self_improvement/core/health/platform/health_connect_steps_source.dart';

/// The Dart side of the channel to Health Connect, against a mocked channel
/// (BS-97, D-031). The native side and the real Health Connect are not
/// covered: no Android SDK in the development run, the CI only compiles it.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(HealthConnectStepsSource.channelName);

  late HealthConnectStepsSource source;
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

  setUp(() {
    source = HealthConnectStepsSource();
    calls = [];
  });
  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  group('availability (BS-97)', () {
    for (final (answerText, expected) in <(String, HealthAvailability)>[
      ('available', HealthAvailability.available),
      ('updateRequired', HealthAvailability.updateRequired),
      ('missing', HealthAvailability.missing),
    ]) {
      test('"$answerText" is ${expected.name}', () async {
        answer((call) async => answerText);
        expect(await source.availability(), expected);
        expect(calls.single.method, 'availability');
        expect(calls.single.arguments, isNull);
      });
    }

    test('an answer nobody knows is a failure, not a guess', () async {
      answer((call) async => 'maybe');
      await expectLater(
        source.availability(),
        throwsA(
          isA<HealthStepsException>().having(
            (error) => error.kind,
            'kind',
            HealthFailureKind.failed,
          ),
        ),
      );
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

    test('a failing native call is a failure, not "unsupported"', () async {
      answer((call) async => throw PlatformException(code: 'failed'));
      await expectLater(
        source.availability(),
        throwsA(isA<HealthStepsException>()),
      );
    });
  });

  group('access (BS-97)', () {
    test('hasAccess reads the state and shows no dialog', () async {
      answer((call) async => true);
      expect(await source.access(), HealthAccess.granted);
      expect(calls.single.method, 'hasAccess');
      answer((call) async => false);
      expect(await source.access(), HealthAccess.denied);
      answer((call) async => null);
      expect(await source.access(), HealthAccess.denied);
    });

    test('requestAccess is the call that shows the dialog and returns its '
        'result', () async {
      answer((call) async => true);
      expect(await source.requestAccess(), HealthAccess.granted);
      expect(calls.single.method, 'requestAccess');
      answer((call) async => false);
      expect(await source.requestAccess(), HealthAccess.denied);
    });

    test('a busy or missing activity is a failure', () async {
      for (final code in ['busy', 'no_activity', 'failed']) {
        answer((call) async => throw PlatformException(code: code));
        await expectLater(
          source.requestAccess(),
          throwsA(
            isA<HealthStepsException>().having(
              (error) => error.kind,
              code,
              HealthFailureKind.failed,
            ),
          ),
          reason: code,
        );
      }
    });
  });

  group('the total of a time range (BS-97, AT25)', () {
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

    test(
      'a taken-away access is "accessDenied", the rest is "failed"',
      () async {
        answer(
          (call) async =>
              throw PlatformException(code: 'access_denied', details: 'x'),
        );
        await expectLater(
          source.totalSteps(startUtc: start, endUtc: end),
          throwsA(
            isA<HealthStepsException>().having(
              (error) => error.kind,
              'kind',
              HealthFailureKind.accessDenied,
            ),
          ),
        );
        answer((call) async => throw PlatformException(code: 'failed'));
        await expectLater(
          source.totalSteps(startUtc: start, endUtc: end),
          throwsA(
            isA<HealthStepsException>().having(
              (error) => error.kind,
              'kind',
              HealthFailureKind.failed,
            ),
          ),
        );
      },
    );

    test('the text of a platform error never travels on, only the class '
        'name of the cause', () async {
      answer(
        (call) async => throw PlatformException(
          code: 'failed',
          message: 'secret 7450 steps for 2026-10-03',
          details: 'RemoteException',
        ),
      );
      try {
        await source.totalSteps(startUtc: start, endUtc: end);
        fail('expected a failure');
      } on HealthStepsException catch (error) {
        expect(error.causeType, 'RemoteException');
        expect(error.toString(), isNot(contains('secret')));
        expect(error.toString(), isNot(contains('7450')));
      }
    });

    test('without a native side the read is "unavailable"', () async {
      await expectLater(
        source.totalSteps(startUtc: start, endUtc: end),
        throwsA(
          isA<HealthStepsException>().having(
            (error) => error.kind,
            'kind',
            HealthFailureKind.unavailable,
          ),
        ),
      );
    });
  });

  group('the pages of the system (BS-97)', () {
    test(
      'install page and settings report whether a page was opened',
      () async {
        answer((call) async => true);
        expect(await source.openInstallPage(), isTrue);
        expect(await source.openAccessSettings(), isTrue);
        expect(calls.map((call) => call.method), [
          'openInstallPage',
          'openAccessSettings',
        ]);
        answer((call) async => false);
        expect(await source.openInstallPage(), isFalse);
        expect(await source.openAccessSettings(), isFalse);
        answer((call) async => null);
        expect(await source.openInstallPage(), isFalse);
      },
    );

    test('a failing or missing native side is "nothing opened", never an '
        'error', () async {
      expect(await source.openInstallPage(), isFalse);
      expect(await source.openAccessSettings(), isFalse);
      answer((call) async => throw PlatformException(code: 'failed'));
      expect(await source.openInstallPage(), isFalse);
      expect(await source.openAccessSettings(), isFalse);
    });
  });

  group('the contract with the native side (BS-97)', () {
    test(
      'the adapter only ever calls the six methods of the channel',
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
          HealthConnectStepsSource.methodAvailability,
          HealthConnectStepsSource.methodHasAccess,
          HealthConnectStepsSource.methodRequestAccess,
          HealthConnectStepsSource.methodTotalSteps,
          HealthConnectStepsSource.methodOpenInstallPage,
          HealthConnectStepsSource.methodOpenAccessSettings,
        });
      },
    );

    test('the native class knows the channel, every method, every answer and '
        'every error code of this file', () {
      final kotlin = File(
        'android/app/src/main/kotlin/de/lf10/selfimprovement/'
        'HealthStepsPlugin.kt',
      ).readAsStringSync();
      expect(
        kotlin,
        contains(
          'const val CHANNEL = "${HealthConnectStepsSource.channelName}"',
        ),
      );
      for (final method in [
        HealthConnectStepsSource.methodAvailability,
        HealthConnectStepsSource.methodHasAccess,
        HealthConnectStepsSource.methodRequestAccess,
        HealthConnectStepsSource.methodTotalSteps,
        HealthConnectStepsSource.methodOpenInstallPage,
        HealthConnectStepsSource.methodOpenAccessSettings,
      ]) {
        expect(kotlin, contains('"$method" ->'), reason: method);
      }
      for (final text in [
        HealthConnectStepsSource.answerAvailable,
        HealthConnectStepsSource.answerUpdateRequired,
        HealthConnectStepsSource.answerMissing,
      ]) {
        expect(kotlin, contains('-> "$text"'), reason: text);
      }
      expect(
        kotlin,
        contains(
          'const val ERROR_ACCESS_DENIED = '
          '"${HealthConnectStepsSource.errorAccessDenied}"',
        ),
      );
      expect(kotlin, contains('"startUtcMillis"'));
      expect(kotlin, contains('"endUtcMillis"'));
    });

    test('the display name is the one of Health Connect', () {
      expect(source.displayName, 'Health Connect');
    });
  });
}
