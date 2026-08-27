import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 2026-08-26: تخزين تفضيل "الوضع اليدوي للواتساب" للمدير.
///
/// عند التفعيل، إرسالات WA الفرديّة تفتح واتساب المدير الشخصي بدل
/// جلسة السيرفر — يحمي الجلسة المشتركة من مخاطر tctoken/reachoutTimelock
/// (المدير يضغط "إرسال" بيده فتبدو الرسالة organic تماماً لـWhatsApp).
///
/// التخزين محلّي لكل جهاز (SecureStorage). لا مزامنة مع السيرفر — لو
/// المدير غيّر جهاز يعيد التفعيل. مستقبلاً ممكن مزامنة عبر admin_settings.
class ManualWaPrefs {
  ManualWaPrefs._();

  static const _storage = FlutterSecureStorage();
  static const _kEnabled = 'wa.manual_mode.enabled';

  /// ValueNotifier مركزي — كل الـUI يستمع له فيتحدّث فوراً عند التبديل
  /// بلا reload كامل. القيمة تُهيَّأ من الـstorage في `init()`.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// يُستدعى مرّة في `main()` بعد `AuthStorage.init()`. يقرأ القيمة
  /// من الـstorage ويعيّن الـnotifier. صامت لو الـstorage فشل.
  static Future<void> init() async {
    try {
      final raw = await _storage.read(key: _kEnabled);
      enabled.value = raw == '1';
    } catch (_) {
      enabled.value = false;
    }
  }

  static Future<void> setEnabled(bool v) async {
    enabled.value = v;
    try {
      await _storage.write(key: _kEnabled, value: v ? '1' : '0');
    } catch (_) {
      // silent — القيمة في الذاكرة تعمل خلال الجلسة الحاليّة.
    }
  }
}
