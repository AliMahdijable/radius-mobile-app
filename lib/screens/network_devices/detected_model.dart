import '../../api/network_devices_api.dart';
import '../../models/network_device.dart';
import 'widgets/device_image.dart';

/// يحفظ الطراز الذي **يُبلّغ به الجهاز نفسه**.
///
/// ⚠️ سبب وجوده: حقل `model` يُملأ يدويّاً، وفحص قاعدة الإنتاج أظهر
/// أنّه فارغ في 55% من الأسطول، وعامٌّ فيما بقي — «AirMax» خطّ منتجات
/// لا طرازاً، و«RP5009» خطأ كتابة لـRB5009. فصور الأجهزة لا تُطابَق.
///
/// الجهاز يعرف طرازه بدقّة: Mikrotik يُرجع `board-name`، وairOS
/// `devmodel`. فبدل مطالبة المدير بكتابة 67 اسماً بلا خطأ إملائي،
/// نأخذها من المصدر.
class DetectedModel {
  DetectedModel._();

  /// الأجهزة التي **نجحت** كتابتها في هذه الجلسة.
  ///
  /// ⚠️ تُملأ بعد النجاح لا قبل الطلب: كانت تُملأ قبله، فأوّل فشل
  /// عابر يُقفل الجهاز حتّى إعادة تشغيل التطبيق.
  static final _done = <int>{};

  static bool needsDetection(NetworkDevice d) {
    if (_done.contains(d.id)) return false;
    final m = d.model?.trim() ?? '';
    // فارغ، أو مكتوب لكنّه لا يُطابق أيّ صورة — كلاهما يستحقّ الكشف.
    return m.isEmpty || DeviceImage.assetFor(m, brand: d.brand) == null;
  }

  static Future<NetworkDevice?> save(
      NetworkDevice device, String? reported) async {
    final r = reported?.trim();
    if (r == null || r.isEmpty) return null;
    if (_done.contains(device.id)) return null;
    final cur = device.model?.trim() ?? '';
    if (cur.toLowerCase() == r.toLowerCase()) {
      _done.add(device.id);
      return null;
    }
    // لا نكتب فوق قيمة أدقّ: «Mikrotik CCR2116-12G-4S+» تحوي المُبلَّغ.
    if (cur.toLowerCase().contains(r.toLowerCase())) {
      _done.add(device.id);
      return null;
    }
    try {
      // ⚠️ **صفّ كامل لا حقل واحد**: نقطة PUT على الخادم استبدالٌ كامل
      // يمرّ على مُنقٍّ يشترط name وtype وbrand وip، فجسم `{model}` وحده
      // يُردّ بـ400 — و`validateStatus` يمنع الرمي فيُبتلع صامتاً.
      // كان هذا يعني أنّ الكشف **لا يكتب شيئاً إطلاقاً**.
      //
      // ولا نُدرج مفتاح الاعتماديّات: الخادم يُبقيها حين يغيب المفتاح،
      // وإدراجه فارغاً يمحوها.
      final updated = await NetworkDevicesApi.update(device.id, {
        'name': device.name,
        'type': device.type,
        'brand': device.brand,
        'ip': device.ip,
        'port': device.port,
        'api_port': device.apiPort,
        'protocol': device.protocol,
        'mac': device.mac,
        'location': device.location,
        'notes': device.notes,
        'region_id': device.regionId,
        'model': r,
      });
      _done.add(device.id);
      return updated;
    } catch (_) {
      // فشل صامت مقصود: تحديث حقل تجميلي لا يستحقّ إزعاج المستخدم وهو
      // ينظر إلى لوحة مراقبة. ولا نُسجّله في `_done` فتُعاد المحاولة.
      return null;
    }
  }
}
