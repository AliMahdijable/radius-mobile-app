import '../../api/network_devices_api.dart';
import '../../models/network_device.dart';

/// يحفظ الموديل الذي **يُبلّغ به الجهاز نفسه**.
///
/// ⚠️ سبب وجود هذا الملفّ: حقل `model` يُملأ يدويّاً، وفحص البيانات
/// الحيّة (2026-08-30) أظهر أنّه في الغالب فارغ أو عامّ — «AirMax»
/// خطّ منتجات لا موديلاً، و«RP5009» خطأ كتابة لـRB5009، و«912» جزء
/// من اسم. فصور الأجهزة لم تُطابَق ولم تظهر.
///
/// الجهاز يعرف طرازه بدقّة: Mikrotik يُرجع `board-name` من
/// `/system/resource`، وairOS يُرجع `devmodel`. فبدل مطالبة المدير
/// بكتابة 67 اسماً بلا خطأ إملائي، نأخذها من المصدر.
///
/// الكتابة تحدث **مرّةً واحدة** لكلّ جهاز — فقط حين يختلف المخزَّن عن
/// المُبلَّغ. وتفشل بصمت: تحديث حقل تجميلي لا يستحقّ إزعاج المستخدم
/// برسالة خطأ وهو ينظر إلى لوحة مراقبة.
class DetectedModel {
  DetectedModel._();

  /// الأجهزة التي حاولنا كتابتها في هذه الجلسة — يمنع تكرار الطلب مع
  /// كلّ نبضة تحديث للوحة الحيّة (كلّ 15 ثانية).
  static final _attempted = <int>{};

  static Future<NetworkDevice?> save(NetworkDevice device, String? reported) async {
    final r = reported?.trim();
    if (r == null || r.isEmpty) return null;
    if (_attempted.contains(device.id)) return null;
    // لا نكتب فوق قيمة مطابقة، ولا نكتب لو المخزَّن يحوي المُبلَّغ
    // أصلاً (المدير كتب «Mikrotik CCR2116-12G-4S+» مثلاً — أدقّ لا أقلّ).
    final cur = device.model?.trim() ?? '';
    if (cur.toLowerCase() == r.toLowerCase()) return null;
    if (cur.toLowerCase().contains(r.toLowerCase())) return null;
    _attempted.add(device.id);
    try {
      return await NetworkDevicesApi.update(device.id, {'model': r});
    } catch (_) {
      return null;
    }
  }
}
