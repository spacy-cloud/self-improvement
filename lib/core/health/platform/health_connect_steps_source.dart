import 'package:flutter/services.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';

/// [HealthStepsSource] on top of Health Connect (Android), through the small
/// channel `HealthStepsPlugin` in `android/app/src/main/kotlin/` (decision
/// D-031; the app does not use the `health` package).
///
/// ## What the native side does
///
/// It reads the aggregated step total of a time range from Health Connect,
/// asks for exactly one permission (`android.permission.health.READ_STEPS`)
/// and opens the store page and the settings of Health Connect. It has no
/// method that writes, none for another kind of data, and it never reads
/// single records: Health Connect merges its sources (phone, watch, apps) in
/// its own aggregation, so the same step is not counted twice.
///
/// ## Honest limits
///
/// This file is covered on the host with a mocked channel; the native side and
/// the real Health Connect are not: there is no Android SDK in the development
/// run, the CI only compiles it, and an emulator has no step data. Whether the
/// totals equal the numbers of the Health Connect app, whether several sources
/// are merged as expected and how the permission dialog behaves on a real
/// phone is checked with the checklist in `docs/screens/body-weight-steps.md`
/// and is not tested.
///
/// A device without the native side (host tests, other platforms) answers the
/// channel with a missing plugin; that is reported as
/// [HealthAvailability.unsupported], so the switch stays hidden.
final class HealthConnectStepsSource implements HealthStepsSource {
  HealthConnectStepsSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Name of the channel; the same string as `HealthStepsPlugin.CHANNEL`.
  static const String channelName = 'de.lf10.selfimprovement/health_steps';

  // The method names of the channel (`HealthStepsPlugin.onMethodCall`).
  static const String methodAvailability = 'availability';
  static const String methodHasAccess = 'hasAccess';
  static const String methodRequestAccess = 'requestAccess';
  static const String methodTotalSteps = 'totalSteps';
  static const String methodOpenInstallPage = 'openInstallPage';
  static const String methodOpenAccessSettings = 'openAccessSettings';

  // The answers of `availability`.
  static const String answerAvailable = 'available';
  static const String answerUpdateRequired = 'updateRequired';
  static const String answerMissing = 'missing';

  // The error codes of the native side.
  static const String errorAccessDenied = 'access_denied';

  final MethodChannel _channel;

  @override
  String get displayName => 'Health Connect';

  @override
  Future<HealthAvailability> availability() async {
    try {
      final answer = await _invoke<String>(methodAvailability);
      return switch (answer) {
        answerAvailable => HealthAvailability.available,
        answerUpdateRequired => HealthAvailability.updateRequired,
        answerMissing => HealthAvailability.missing,
        _ => throw const HealthStepsException(HealthFailureKind.failed),
      };
    } on HealthStepsException catch (error) {
      if (error.kind == HealthFailureKind.unavailable) {
        // No native side behind the channel: this device has no interface.
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

  @override
  Future<bool> openInstallPage() async =>
      (await _openedPage(methodOpenInstallPage));

  @override
  Future<bool> openAccessSettings() async =>
      (await _openedPage(methodOpenAccessSettings));

  HealthAccess _access(bool? granted) =>
      granted == true ? HealthAccess.granted : HealthAccess.denied;

  Future<bool> _openedPage(String method) async {
    try {
      return (await _invoke<bool>(method)) ?? false;
    } on HealthStepsException {
      return false;
    }
  }

  /// One call of the channel with the failures mapped to
  /// [HealthStepsException]: a missing native side is `unavailable`, the code
  /// `access_denied` is `accessDenied`, everything else is `failed`. The text
  /// of a platform error is never passed on (it can contain values); only the
  /// class name of the cause the native side sends as details is kept.
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
      throw HealthStepsException(
        error.code == errorAccessDenied
            ? HealthFailureKind.accessDenied
            : HealthFailureKind.failed,
        causeType: details is String ? details : null,
      );
    }
  }
}
