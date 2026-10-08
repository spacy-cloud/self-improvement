import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required by flutter_local_notifications so that local reminders can be
    // presented while the app is in the foreground (iOS preparation, not
    // verified without macOS/Xcode).
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The app's own channel for the steps from Apple Health (BS-122, D-034);
    // not a pub package. Not verified without macOS/Xcode and a device.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HealthStepsPlugin") {
      HealthStepsPlugin.register(with: registrar)
    }
  }
}
