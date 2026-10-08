import 'package:flutter/services.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';

/// [HealthStepsSource] on top of HealthKit (iOS), through the small channel
/// `HealthStepsPlugin` in `ios/Runner/` (BS-122, decision D-034; the app does
/// not use the `health` package).
///
/// The channel has the name and the method names of the Android channel
/// (`HealthConnectStepsSource`), so both native sides answer the same
/// calls.
/// This file stays apart from the Android adapter on purpose: that adapter has
/// run on a real phone, and the two differ in what the system lets the app
/// know (see below).
///
/// ## What the native side does
///
/// It reads the aggregated step total of a time range from HealthKit, asks for
/// exactly one permission (reading `stepCount`) and opens the Health app. It
/// has no method that writes, none for another kind of data, and it never
/// reads single samples: HealthKit merges its sources (iPhone, Apple Watch,
/// apps) in its own statistics, so the same step is not counted twice.
///
/// ## What HealthKit hides from the app
///
/// HealthKit never tells an app whether READING was allowed, because a refusal
/// must not be visible (it looks like "no data"). Therefore:
///
/// - [access] says [HealthAccess.granted] once the user has been asked (the
///   native side answers `true` then), not that the user agreed. Before the
///   first question it says [HealthAccess.denied], so the explanation and the
///   system dialog come first.
/// - [requestAccess] says [HealthAccess.granted] when the request was
///   processed, whatever the user chose. The system shows its dialog only once
///   per type; asking again does nothing.
/// - A refused access shows up as `null` from [totalSteps] (no data), the same
///   as a day without steps. The app cannot tell the two apart.
///
/// ## Honest limits
///
/// This file is covered on the host with a mocked channel. The native side is
/// not: there is no macOS in the development run, the CI only compiles it, and
/// whether the entitlement survives the signing of SideStore with a free Apple
/// ID is the open question of BS-122. A build without the entitlement does not
/// crash: the native side answers `unsupported` for [availability], so the
/// switch stays hidden, as it did before this adapter existed.
///
/// A device without the native side (host tests, other platforms) answers the
/// channel with a missing plugin; that is reported as
/// [HealthAvailability.unsupported], too.
final class HealthKitStepsSource implements HealthStepsSource {
  HealthKitStepsSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Name of the channel; the same string as `HealthStepsPlugin.channelName`
  /// (Swift) and as the channel of the Android plugin.
  static const String channelName = 'de.lf10.selfimprovement/health_steps';

  // The method names of the channel (`HealthStepsPlugin.handle`). There is no
  // call for an install page: the Health app is part of iOS.
  static const String methodAvailability = 'availability';
  static const String methodHasAccess = 'hasAccess';
  static const String methodRequestAccess = 'requestAccess';
  static const String methodTotalSteps = 'totalSteps';
  static const String methodOpenAccessSettings = 'openAccessSettings';

  // The answers of `availability`.
  static const String answerAvailable = 'available';
  static const String answerUnsupported = 'unsupported';

  // The error codes of the native side.
  static const String errorAccessDenied = 'access_denied';
  static const String errorEntitlementMissing = 'entitlement_missing';

  final MethodChannel _channel;

  @override
  String get displayName => 'Apple Health';

  @override
  Future<HealthAvailability> availability() async {
    try {
      final answer = await _invoke<String>(methodAvailability);
      return switch (answer) {
        answerAvailable => HealthAvailability.available,
        answerUnsupported => HealthAvailability.unsupported,
        _ => throw const HealthStepsException(HealthFailureKind.failed),
      };
    } on HealthStepsException catch (error) {
      if (error.kind == HealthFailureKind.unavailable) {
        // No native side behind the channel, or a build without the HealthKit
        // entitlement: this device has no interface the app may use.
        return HealthAvailability.unsupported;
      }
      rethrow;
    }
  }

  @override
  Future<HealthAccess> access() async =>
      _access(await _invoke<bool>(methodHasAccess));

  @override
  Future<HealthAccess> requestAccess() async =>
      _access(await _invoke<bool>(methodRequestAccess));

  @override
  Future<int?> totalSteps({
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {
    final total = await _invoke<int>(methodTotalSteps, <String, Object?>{
      'startUtcMillis': startUtc.millisecondsSinceEpoch,
      'endUtcMillis': endUtc.millisecondsSinceEpoch,
    });
    if (total != null && total < 0) {
      throw const HealthStepsException(HealthFailureKind.failed);
    }
    return total;
  }

  /// There is nothing to install: the Health app is part of iOS.
  @override
  Future<bool> openInstallPage() async => false;

  @override
  Future<bool> openAccessSettings() async {
    try {
      return (await _invoke<bool>(methodOpenAccessSettings)) ?? false;
    } on HealthStepsException {
      return false;
    }
  }

  HealthAccess _access(bool? granted) =>
      granted == true ? HealthAccess.granted : HealthAccess.denied;

  /// One call of the channel with the failures mapped to
  /// [HealthStepsException]: a missing native side and a missing entitlement
  /// are `unavailable`, the code `access_denied` is `accessDenied`, everything
  /// else is `failed`. The text of a platform error is never passed on (it can
  /// contain values); only the class name of the cause the native side sends
  /// as details is kept.
  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const HealthStepsException(HealthFailureKind.unavailable);
    } on PlatformException catch (error) {
      final details = error.details;
      throw HealthStepsException(switch (error.code) {
        errorAccessDenied => HealthFailureKind.accessDenied,
        errorEntitlementMissing => HealthFailureKind.unavailable,
        _ => HealthFailureKind.failed,
      }, causeType: details is String ? details : null);
    }
  }
}
