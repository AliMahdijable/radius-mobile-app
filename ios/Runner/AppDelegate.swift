import Flutter
import UIKit
import UserNotifications

// ⚠️ **دورة حياة UIScene — شرطٌ لا خيار.**
//
// 🐛 iOS 27 يرفض إقلاع أيّ تطبيق UIKit مبنيٍّ بـSDK 27 ولا يعتمد
// UIScene: يظهر شعار الإقلاع ثمّ يُنهى التطبيق فوراً بـSIGTRAP
// ورسالة «UIScene life cycle is required for apps built with this SDK».
// والبوّابة تُفتح بـ**البناء** على SDK الجديد لا بنسخة الجهاز — ولذلك
// كان يعمل على ٢٦.٦ ويسقط على ٢٧.
//
// وFlutter يهاجر `AppDelegate` تلقائيّاً — لكن **للمُعدَّل لا يهاجر**،
// وهذا الملفّ مُعدَّل بشيفرة الإشعارات أدناه. فتخطّته الهجرة بصمت
// بينما ظلّ التحذير يتكرّر في كلّ بناء.
//
// وتسجيل الإضافات انتقل إلى `didInitializeImplicitFlutterEngine`:
// مع المشاهد لم يعُد `AppDelegate` هو سجلّ الإضافات، فتسجيلها عليه
// يترك الإضافات بلا قناة.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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
