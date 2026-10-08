import Flutter
import HealthKit
import UIKit

/// The iOS side of `lib/core/health/platform/health_kit_steps_source.dart`
/// (BS-122, decision D-034). The app has its own small channel instead of the
/// pub package `health`, like on Android (`HealthStepsPlugin.kt`, D-031).
///
/// What it does: it reads the aggregated step total of a time range from
/// HealthKit, asks for exactly one permission (reading `stepCount`) and opens
/// the Health app. What it does not do: it has no method that writes (the set
/// of types to share is always empty), none for another kind of data, and it
/// never reads single samples. HealthKit merges its sources (iPhone, Apple
/// Watch, apps) in its own statistics, so the same step is not counted twice.
///
/// ## Not verified
///
/// Nothing here has run on an iPhone or in a simulator: there is no macOS in
/// the development run, and the CI only compiles it. Whether the entitlement
/// survives the signing of SideStore with a free Apple ID is the question of
/// BS-122. A build without the entitlement does not crash: HealthKit raises an
/// Objective-C exception there, which `HealthExceptionGuard` catches.
///
/// ## What HealthKit hides
///
/// HealthKit never tells an app whether READING was allowed (a refusal looks
/// like "no data"). So `hasAccess` answers only whether the user has been
/// asked already, and `requestAccess` answers only whether the request was
/// processed. A refused access shows up as a total of `nil` (no data).
final class HealthStepsPlugin: NSObject, FlutterPlugin {
  /// The same string as `HealthKitStepsSource.channelName` (and as the channel
  /// of the Android plugin).
  static let channelName = "de.lf10.selfimprovement/health_steps"

  private let store = HKHealthStore()
  private let stepType = HKQuantityType(.stepCount)

  /// The only type the app asks to read.
  private var readTypes: Set<HKObjectType> { [stepType] }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(HealthStepsPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "availability": availability(result)
    case "hasAccess": hasAccess(result)
    case "requestAccess": requestAccess(result)
    case "totalSteps": totalSteps(call, result)
    case "openAccessSettings": openHealthApp(result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Methods of the channel

  /// "available" when HealthKit exists on this device and the build may use
  /// it, otherwise "unsupported" (so the switch stays hidden). The request
  /// status is read only to find out whether the build has the entitlement:
  /// HealthKit raises an exception when it does not. Nothing is shown.
  private func availability(_ result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      reply(result, "unsupported")
      return
    }
    let raised = HealthExceptionGuard.runAndCatch {
      store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { _, _ in
        reply(result, "available")
      }
    }
    if raised != nil {
      reply(result, "unsupported")
    }
  }

  /// Whether the user has been asked for the steps already (see the note
  /// about what HealthKit hides). Shows no dialog.
  private func hasAccess(_ result: @escaping FlutterResult) {
    let raised = HealthExceptionGuard.runAndCatch {
      store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
        if let error = error {
          replyError(result, error)
        } else {
          reply(result, status == .unnecessary)
        }
      }
    }
    if let raised = raised {
      replyRaised(result, raised)
    }
  }

  /// Shows the system dialog (HealthKit skips it when the user answered it
  /// before) and answers whether the request was processed, not whether the
  /// access was given.
  private func requestAccess(_ result: @escaping FlutterResult) {
    let raised = HealthExceptionGuard.runAndCatch {
      store.requestAuthorization(toShare: [], read: readTypes) { success, error in
        if let error = error {
          replyError(result, error)
        } else {
          reply(result, success)
        }
      }
    }
    if let raised = raised {
      replyRaised(result, raised)
    }
  }

  /// The total of the steps from `startUtcMillis` (inclusive) to
  /// `endUtcMillis` (exclusive), or `nil` when HealthKit has no data in the
  /// range. A sample counts for the day it STARTS in (`strictStartDate`), so
  /// no sample is counted on two days. The cumulative statistics merge the
  /// sources of HealthKit; the total can differ from the number in the Health
  /// app by the samples around midnight.
  private func totalSteps(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let startMillis = arguments["startUtcMillis"] as? Int,
      let endMillis = arguments["endUtcMillis"] as? Int,
      endMillis > startMillis
    else {
      reply(
        result,
        FlutterError(code: errorBadArguments, message: nil, details: nil)
      )
      return
    }
    let start = Date(timeIntervalSince1970: Double(startMillis) / 1000)
    let end = Date(timeIntervalSince1970: Double(endMillis) / 1000)
    let predicate = HKQuery.predicateForSamples(
      withStart: start,
      end: end,
      options: .strictStartDate
    )
    let query = HKStatisticsQuery(
      quantityType: stepType,
      quantitySamplePredicate: predicate,
      options: .cumulativeSum
    ) { _, statistics, error in
      if let error = error {
        // "No data" is not a failure: HealthKit reports it as an error code.
        if let healthError = error as? HKError, healthError.code == .errorNoData {
          reply(result, nil)
        } else {
          replyError(result, error)
        }
        return
      }
      guard let sum = statistics?.sumQuantity() else {
        reply(result, nil)
        return
      }
      reply(result, Int(sum.doubleValue(for: HKUnit.count()).rounded()))
    }
    let raised = HealthExceptionGuard.runAndCatch {
      store.execute(query)
    }
    if let raised = raised {
      replyRaised(result, raised)
    }
  }

  /// Opens the Health app: that is where the user changes which apps may read
  /// the steps. iOS has no page for it in the Settings app that an app can
  /// open. Answers whether something was opened.
  private func openHealthApp(_ result: @escaping FlutterResult) {
    guard let url = URL(string: "x-apple-health://") else {
      reply(result, false)
      return
    }
    DispatchQueue.main.async {
      UIApplication.shared.open(url, options: [:]) { opened in
        result(opened)
      }
    }
  }
}

// MARK: - Answers

// The error codes the Dart side knows (`HealthKitStepsSource`).
private let errorAccessDenied = "access_denied"
private let errorEntitlementMissing = "entitlement_missing"
private let errorFailed = "failed"
private let errorBadArguments = "bad_arguments"

/// Answers on the main thread, once. HealthKit calls its handlers on a queue
/// of its own.
private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
  DispatchQueue.main.async {
    result(value)
  }
}

/// An error of HealthKit as a code the Dart side knows. The text of the error
/// is never passed on (it can contain values); only the class of the cause is.
private func replyError(_ result: @escaping FlutterResult, _ error: Error) {
  var code = errorFailed
  if let healthError = error as? HKError {
    switch healthError.code {
    case .errorAuthorizationDenied, .errorAuthorizationNotDetermined:
      code = errorAccessDenied
    default:
      break
    }
  }
  reply(
    result,
    FlutterError(code: code, message: nil, details: String(describing: type(of: error)))
  )
}

/// An exception HealthKit raised and `HealthExceptionGuard` caught. A missing
/// entitlement gets its own code; the text of the exception is not passed on.
private func replyRaised(_ result: @escaping FlutterResult, _ reason: String) {
  let code = reason.localizedCaseInsensitiveContains("entitlement")
    ? errorEntitlementMissing
    : errorFailed
  reply(result, FlutterError(code: code, message: nil, details: "NSException"))
}
