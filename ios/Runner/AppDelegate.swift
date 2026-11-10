import AVFoundation
import Flutter
import UIKit
import UserNotifications

/// «صفّارة وضع الفنّي» (شبكة الألياف، ١٠ نوفمبر): نغمةٌ قصيرة بمشغّل الوسائط — تُسمع والهاتف على «صامت». كانت «صوت اللمس»
/// للنظام (SystemSound.click) ولا يُسمع بآيفون إلّا مع نقرات لوحة المفاتيح. lib/services/tech_beep.dart.
final class TechBeep {
  static let shared = TechBeep()
  private var players: [Int: AVAudioPlayer] = [:]

  /// ⇒ true مسموعة، false صوت الجهاز على الصفر، nil تعذّرت.
  func play(ms: Int) -> Bool? {
    let length = max(20, min(ms, 500))
    let session = AVAudioSession.sharedInstance()
    do {
      // «تشغيل» مع ما يشتغل بالهاتف (لا يوقف شيئاً) وبلا كتمٍ بمفتاح الصامت. والمايك شغّال (أمرٌ صوتيّ فوق الشاشة) ⇒ فئته
      // تشغّل الصوت أصلاً فلا تُمسّ — تبديلها يقطع التسجيل.
      if session.category != .playback && session.category != .playAndRecord && session.category != .record {
        try session.setCategory(.playback, options: [.mixWithOthers])
        try session.setActive(true)
      }
      let player: AVAudioPlayer
      if let ready = players[length] {
        player = ready
      } else {
        player = try AVAudioPlayer(data: TechBeep.wave(hz: 2600, ms: length))
        player.prepareToPlay()
        players[length] = player
      }
      player.currentTime = 0
      player.play()
      return session.outputVolume > 0
    } catch {
      players.removeAll()
      return nil
    }
  }

  /// موجةٌ جيبيّة PCM16 أحاديّة 22.05k بترويسة WAV — أوّلها وآخرها أملسان (٥ مث) فلا «طقّة».
  static func wave(hz: Double, ms: Int) -> Data {
    let rate = 22050.0
    let count = Int(rate * Double(ms) / 1000.0)
    let fade = rate * 0.005
    var pcm = Data(capacity: count * 2)
    for i in 0..<count {
      let edge = min(Double(i), Double(count - 1 - i))
      let level = min(1.0, edge / fade)
      let sample = Int16(sin(2.0 * Double.pi * hz * Double(i) / rate) * 0.85 * level * Double(Int16.max))
      withUnsafeBytes(of: sample.littleEndian) { pcm.append(contentsOf: $0) }
    }
    var out = Data(capacity: 44 + pcm.count)
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
    out.append(contentsOf: Array("RIFF".utf8))
    u32(UInt32(36 + pcm.count))
    out.append(contentsOf: Array("WAVEfmt ".utf8))
    u32(16)
    u16(1)
    u16(1)
    u32(UInt32(rate))
    u32(UInt32(rate) * 2)
    u16(2)
    u16(16)
    out.append(contentsOf: Array("data".utf8))
    u32(UInt32(pcm.count))
    out.append(pcm)
    return out
  }
}

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
    // «طابعة الوصولات» (٩ نوفمبر): طابعات الكاشير BLE — القناة نفسها التي يكلّمها أندرويد. مدير البلوتوث لا يُنشأ
    // هنا: يُنشأ أوّل مرّةٍ يختار المدير «طابعة بلوتوث» (فسؤال الإذن حينها لا عند فتح التطبيق).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ReceiptPrinterBle") {
      ReceiptPrinterBle.register(with: registrar)
    }
    // «صفّارة وضع الفنّي»: القناة نفسها التي يكلّمها أندرويد (النغمة بصوت الوسائط).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TechBeep") {
      let beep = FlutterMethodChannel(name: "com.mysvcs.rad_mysvcs/beep", binaryMessenger: registrar.messenger())
      beep.setMethodCallHandler { call, result in
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "beep":
          result(TechBeep.shared.play(ms: (args?["ms"] as? Int) ?? 90))
        case "keepAwake":
          // الصفّارة شغّالة ⇒ الشاشة لا تنطفئ (القفل يعلّق التطبيق فتقف القراءة والصفّارة)؛ تُرفع بإطفائها أو الخروج
          UIApplication.shared.isIdleTimerDisabled = (args?["on"] as? Bool) ?? false
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
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
