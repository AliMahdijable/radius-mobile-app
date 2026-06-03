import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Kick off APNs registration as soon as the app launches so the device
    // token is ready by the time Dart's FcmService asks for it. Without this,
    // iOS only triggers registration when something explicitly calls
    // registerForRemoteNotifications — and on first launch that can add
    // seconds of latency before getAPNSToken() returns a value.
    // firebase_messaging's swizzling still owns the actual didRegister...
    // callback, so this does not interfere with token forwarding to Firebase.
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound]
    ) { _, _ in
      DispatchQueue.main.async {
        application.registerForRemoteNotifications()
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
