import 'package:shared_preferences/shared_preferences.dart';

import 'auth_storage.dart';

/// اختيارات «إرسال واتساب / إشعار داخل التطبيق / تلغرام» في نوافذ المدير الفرعيّ (شحن، سحب، نقاط، تسديد دين) — المالك
/// ٢٨ أكتوبر: «الاسهم الافتراضيه… تكدر يخلي المدير يحفظهن مره وحده ويبقن ثابتات؟».
///
/// آخر اختيارٍ نجحت به عمليّة يُحفظ ويُفتح به التالي — لكلّ حسابٍ على هذا الجهاز (المعرّف من الجلسة). بلا حفظٍ سابق ⇒ الافتراضيّ
/// القديم (واتساب ✓، التطبيق ✓، تلغرام ✗). القناة المعطّلة لمديرٍ بعينه (بلا رقم/غير مربوط بتلغرام) لا تُكتب فوق الاختيار.
class ManagerNoticePrefs {
  ManagerNoticePrefs._();

  static const defaults = (whatsApp: true, push: true, telegram: false);

  static String _key(String admin) => 'mgr.notice.v1.$admin';

  /// الاختيار المحفوظ، أو [defaults].
  static Future<({bool whatsApp, bool push, bool telegram})> load() async {
    try {
      final admin = await AuthStorage.readAdminId() ?? '';
      final raw = (await SharedPreferences.getInstance()).getString(_key(admin));
      if (raw == null || raw.length != 3 || raw.replaceAll(RegExp('[01]'), '').isNotEmpty) return defaults;
      return (whatsApp: raw[0] == '1', push: raw[1] == '1', telegram: raw[2] == '1');
    } catch (_) {
      return defaults;
    }
  }

  static Future<void> save({required bool whatsApp, required bool push, required bool telegram}) async {
    try {
      final admin = await AuthStorage.readAdminId() ?? '';
      await (await SharedPreferences.getInstance())
          .setString(_key(admin), '${whatsApp ? 1 : 0}${push ? 1 : 0}${telegram ? 1 : 0}');
    } catch (_) {
      // صامت — الاختيار الحاليّ يعمل لهذه العمليّة، ويُعاد الحفظ مع التالية.
    }
  }
}
