// عمليّات راوتر المشترك بحسب عائلته (١٢ نوفمبر — طلب المالك: «عرض كلمة سر واي فاي وإمكانيّة تبديله وعمل ريبوت»، و«الترافيك ماكو»):
// الكرت يسأل هنا بالمورّد ([UbiquitiStatus.vendor]) ولا يعرف بروتوكول أيّ عائلة. ما لم تُبنَ له عمليّةٌ بعد ⇒ [RouterFail.unsupported]
// (الكرت لا يُظهر زرّه أصلاً — [canWifi]/[canReboot]).
//
// ⛔ إعادة ضبط المصنع لا تمرّ من هنا أبداً: لكلّ عائلةٍ جارُ زرّ الإقلاع في صفحتها يمسح الجهاز (MER code=5 · Tenda action=restore ·
// CGI ACT_FACTORY_RESET) — اختباراتها تتأكّد أنّها لا تُطلب.

import 'router_types.dart';
import 'tenda_service.dart';
import 'tplink_agile_service.dart';
import 'tplink_classic_service.dart';
import 'tplink_mer_service.dart';

import '../../models/device_health.dart';

class RouterOps {
  RouterOps._();

  static const _wifi = {'tenda', 'tpmer', 'tpclassic', 'tpagile'};
  static const _reboot = {'tenda', 'tpmer', 'tpclassic', 'tpagile'};
  static const _live = {'tpmer'};

  /// عرض كلمة سرّ الواي فاي وتغييرها مبنيٌّ ومجرَّبٌ لهذه العائلة.
  static bool canWifi(String vendor) => _wifi.contains(vendor);

  /// إعادة التشغيل بأمر صفحة الراوتر نفسها.
  static bool canReboot(String vendor) => _reboot.contains(vendor);

  /// نبضةٌ حيّة بجلسةٍ مفتوحة (ترافيك WAN + المتّصلون + مدّة الاتّصال) — عائلاتٌ لا تعطي ترافيكاً بغير دخول.
  static bool hasLive(String vendor) => _live.contains(vendor);

  static Future<RouterResult<List<RouterWifi>>> readWifi(String vendor, String host, String user, String pass) => switch (vendor) {
        'tenda' => TendaService.readWifi(host, pass),
        'tpmer' => TplinkMerService.readWifi(host, pass),
        'tpclassic' => TplinkClassicService.readWifi(host, user, pass),
        'tpagile' => TplinkAgileService.readWifi(host, pass, username: user),
        _ => Future.value(const RouterResult<List<RouterWifi>>.fail(RouterFail.unsupported)),
      };

  /// [newPass] مقبولةٌ مسبقاً ([wifiPasswordProblem]) — هنا حارسٌ ثانٍ لا يرسل كلمةً مرفوضة.
  static Future<RouterResult<List<RouterWifi>>> setWifiPassword(String vendor, String host, String user, String pass, String newPass) {
    final bad = wifiPasswordProblem(newPass);
    if (bad != null) return Future.value(RouterResult<List<RouterWifi>>.fail(RouterFail.failed, bad));
    return switch (vendor) {
      'tenda' => TendaService.setWifiPassword(host, pass, newPass),
      'tpmer' => TplinkMerService.setWifiPassword(host, pass, newPass),
      'tpclassic' => TplinkClassicService.setWifiPassword(host, user, pass, newPass),
      'tpagile' => TplinkAgileService.setWifiPassword(host, pass, newPass, username: user),
      _ => Future.value(const RouterResult<List<RouterWifi>>.fail(RouterFail.unsupported)),
    };
  }

  static Future<RouterResult<RouterReboot>> reboot(String vendor, String host, String user, String pass) => switch (vendor) {
        'tenda' => TendaService.reboot(host, pass),
        'tpmer' => TplinkMerService.reboot(host, pass),
        'tpclassic' => TplinkClassicService.reboot(host, user, pass),
        'tpagile' => TplinkAgileService.reboot(host, pass, username: user),
        _ => Future.value(const RouterResult<RouterReboot>.fail(RouterFail.unsupported)),
      };

  static Future<RouterLive?> openLive(String vendor, String host, String user, String pass) => switch (vendor) {
        'tpmer' => TplinkMerService.openLive(host, pass),
        _ => Future.value(null),
      };
}
