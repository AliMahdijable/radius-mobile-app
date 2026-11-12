import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/device_health.dart';
import 'router_types.dart';

/// راوتر TP-Link المنزليّ القديم (واجهة `userRpm` — TL-WR741ND v4 بفيرموير 3.16.6، قِيس حيّاً ١١ نوفمبر على راوتر مشترك):
///
/// * **بروتوكولٌ واحد**: HTTP على 80 وحده (لا SSH/Telnet/HTTPS/TR-069/SNMP).
/// * **مصادقة HTTP Basic مع كلّ طلب** + `Referer` من الجهاز نفسه (حارس هذه الفيرموَيرات) — **لا جلسة ولا كوكي**: قراءتنا لا تطرد
///   من فتح صفحة الجهاز، وقراءتان معاً لا تتصادمان.
/// * التعرّف بطلبٍ واحد بلا اعتماد: `GET /` ⇒ 401 + `WWW-Authenticate: Basic realm="TP-LINK … WR741ND"`.
/// * البيانات مصفوفات JS داخل الصفحات (`var x = new Array(...)`):
///   `StatusRpm.htm`: `statusPara[4]` مدّة التشغيل بالثواني، `[5]` الفيرموير، `[6]` العتاد · `wanPara[2]` عنوان WAN، `[3]` نوعه،
///   `[12]` مدّة اتّصال PPPoE («0 day(s) 03:43:03») · `statistList[0]/[1]` بايتات WAN المستلمة/المرسلة · `wlanPara[1]` SSID.
///   `WlanStationRpm.htm`: `wlanHostPara[0]` أجهزة الوايرلس المتّصلة **الآن** (المالك: «الوايرلس… تلكاه المتصل الفعلي»).
///   `AssignedIpAddrListRpm.htm`: `DHCPDynPara[0]` الإيجارات (ثانويّ — تبقى بعد خروج الجهاز).
/// * ⛔ `PPPoECfgRpm.htm` تحمل يوزر PPPoE وكلمة سرّه نصّاً — لا تُطلب أبداً. ⛔ `RestoreDefaultCfgRpm` = ضبط مصنع، `SysRebootRpm` = إقلاع.
/// * سرعة ربط منفذ WAN (10/100) **لا يصدّرها** هذا الفيرموير — السرعة الحيّة = فرق عدّادات WAN ÷ الزمن.
/// * القفل بعد كلماتٍ غلط لم يُجرَّب (لا نرسل تخميناً) ⇒ اعتمادات الوكيل وحدها، لا افتراض مصنّع.
///
/// **الفيرموير الأحدث (TL-WR940N v6، 3.18.1 Build 171030 — قِيس حيّاً ١٢ نوفمبر):** «/» ⇒ 200 بصفحة دخولٍ فيها
/// `httpAutErrorArray = new Array(حالة, md5?, url)`: 3 جاهز · 2 الأخيرة خطأ · **1 مقفلٌ ساعتين (عشر محاولات)** · **0 مديرٌ آخر داخل
/// (واحدٌ فقط)**. الدخول: كوكي `Authorization=escape("Basic "+base64(user+":"+md5(pass)))` ثمّ `GET /userRpm/LoginRpm.htm?Save=Save` ⇒
/// التوكن في المسار (`/<16 حرفاً>/userRpm/Index.htm`)، والصفحات نفسها تحت `/<TOKEN>/userRpm/…` بالكوكي، والخروج
/// `/<TOKEN>/userRpm/LogoutRpm.htm` **دائماً** (مديرٌ واحد: جلسةٌ تبقى تحجب صاحب الراوتر). المصفوفات نفسها، لكنّ `statistList`
/// نصوصٌ بفواصل الآلاف («4,266,809,196») و`hostList` خمسة حقولٍ للمحطّة (`wlanHostPara[4]`).

/// تعرّفٌ ناجح: الراوتر يقول اسمه في realm المصادقة.
class TpClassicHello {
  const TpClassicHello({required this.realm, required this.model, this.cookieAuth = false, this.md5 = true});
  final String realm;

  /// من realm («WR741ND») — الطراز الكامل بإصداره يأتي من صفحة الحالة بعد الدخول.
  final String model;

  /// الفيرموير الأحدث: دخولٌ بالكوكي والتوكن (لا Basic مع كلّ طلب).
  final bool cookieAuth;

  /// كلمة السرّ تُرسل MD5 (`httpAutErrorArray[1] == 1`).
  final bool md5;
}

enum TpClassicIssue { rejected, unreachable, readFailed, busy, locked }

/// عيّنة حيّة واحدة (صفحة الحالة وحدها): عدّادات WAN + المدّتان.
class TpClassicLive {
  const TpClassicLive({
    required this.rxBytes,
    required this.txBytes,
    required this.at,
    this.uptimeSeconds,
    this.wanOnlineSeconds,
  });
  final int rxBytes;
  final int txBytes;
  final DateTime at;
  final int? uptimeSeconds;
  final int? wanOnlineSeconds;
}

/// قارئاتٌ صرفة (بلا شبكة) — تُختبر بقوالب بنية الصفحات الحيّة.
class TpClassicParse {
  TpClassicParse._();

  static final _tok = RegExp(r'"((?:[^"\\]|\\.)*)"|(-?\d+)');

  /// `var <name> = new Array(...);` ⇒ القيم (نصوصٌ بلا علامات التنصيص، وأعدادٌ صحيحة). غيابها ⇒ null.
  /// المصفوفات المقروءة هنا مسطّحة (لا `new Array` داخلها).
  static List<Object>? array(String html, String name) {
    final m = RegExp('var\\s+${RegExp.escape(name)}\\s*=\\s*new Array\\s*\\(([\\s\\S]*?)\\);').firstMatch(html);
    if (m == null) return null;
    final out = <Object>[];
    for (final t in _tok.allMatches(m.group(1)!)) {
      final s = t.group(1);
      if (s != null) {
        out.add(s.replaceAll(r'\"', '"').trim());
      } else {
        final n = int.tryParse(t.group(2)!);
        if (n != null) out.add(n);
      }
    }
    return out;
  }

  /// عددٌ صحيح من المصفوفة: عددٌ صريح، أو نصٌّ أرقامه بفواصل الآلاف («4,266,809,196» — الفيرموير الأحدث).
  static int? _int(List<Object>? a, int i) {
    if (a == null || i >= a.length) return null;
    final v = a[i];
    if (v is int) return v;
    if (v is String && RegExp(r'^\d{1,3}(,\d{3})*$|^\d+$').hasMatch(v.trim())) return int.tryParse(v.trim().replaceAll(',', ''));
    return null;
  }

  /// حالة صفحة الدخول (الفيرموير الأحدث): `httpAutErrorArray[0]` (3 جاهز · 2 خطأ · 1 مقفل · 0 مديرٌ آخر) و`[1]` (MD5). غيابها ⇒ null.
  static ({int code, bool md5})? loginState(String html) {
    final a = array(html, 'httpAutErrorArray');
    final code = _int(a, 0);
    if (code == null) return null;
    return (code: code, md5: _int(a, 1) == 1);
  }

  /// التوكن من ردّ الدخول (`…/<TOKEN>/userRpm/Index.htm`) — ستّة عشر حرفاً كبيراً؛ غيابه ⇒ null.
  static String? loginToken(String html) => RegExp(r'/([A-Z]{16})/userRpm/Index\.htm').firstMatch(html)?.group(1);
  static String _str(List<Object>? a, int i) => (a != null && i < a.length && a[i] is String) ? a[i] as String : '';

  /// «0 day(s) 03:43:03» · «3 days 14:31:49» · «03:43:03» ⇒ ثوانٍ؛ غير مفهوم ⇒ null (لا صفرٌ كاذب).
  static int? durationSeconds(String s) {
    final m = RegExp(r'(?:(\d+)\s*day[s()]*\s*)?(\d{1,3}):(\d{2}):(\d{2})').firstMatch(s);
    if (m == null) return null;
    final d = int.tryParse(m.group(1) ?? '0') ?? 0;
    return d * 86400 + int.parse(m.group(2)!) * 3600 + int.parse(m.group(3)!) * 60 + int.parse(m.group(4)!);
  }

  /// نوع WAN برمزه (`wanPara[3]`) كما يسمّيه الراوتر نفسه.
  static String wanTypeName(int? code) => switch (code) {
        1 => 'Dynamic IP',
        2 => 'Static IP',
        3 => 'PPPoE',
        4 => '802.1X + Dynamic IP',
        5 => '802.1X + Static IP',
        6 => 'BigPond Cable',
        7 => 'L2TP',
        8 => 'PPTP',
        _ => '',
      };

  /// realm «TP-LINK Wireless Lite N Router WR741ND» ⇒ «WR741ND» (آخر كلمةٍ فيها رقم)؛ لا شيء ⇒ ''.
  static String modelFromRealm(String realm) {
    final words = realm.split(RegExp(r'\s+')).where((w) => RegExp(r'\d').hasMatch(w)).toList();
    return words.isEmpty ? '' : words.last;
  }

  /// «WR741ND v4 00000000» ⇒ «TL-WR741ND v4» (يُسقط ذيل الأصفار/الهكس، ويضيف بادئة TP-Link المعتادة).
  static String modelFromHardware(String hw) {
    final parts = hw.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    while (parts.length > 1 && RegExp(r'^[0-9A-Fa-f]{6,}$').hasMatch(parts.last)) {
      parts.removeLast();
    }
    if (parts.isEmpty) return '';
    final m = parts.join(' ');
    return RegExp(r'^[A-Z]{2,3}\d').hasMatch(m) ? 'TL-$m' : m;
  }

  /// عدد أجهزة الوايرلس المتّصلة الآن (`wlanHostPara[0]`) — null إن لم تُقرأ.
  static int? wifiClients(String wlanHtml) => _int(array(wlanHtml, 'wlanHostPara'), 0);

  /// عدد إيجارات DHCP (`DHCPDynPara[0]`).
  static int? dhcpClients(String dhcpHtml) => _int(array(dhcpHtml, 'DHCPDynPara'), 0);

  /// قائمة المتّصلين الآن (محطّات الوايرلس من `hostList`، ماكٌ لكلٍّ) مُثراةً باسم/آيبي من إيجارات DHCP (`DHCPDynList`) بالربط بالماك.
  /// الوايرلس = المتّصل فعلاً (لا إيجار DHCP الباقي بعد الخروج). فارغةٌ حين لا تُقرأ صفحة الوايرلس.
  static List<RouterClient> clientList({String? wlanHtml, String? dhcpHtml}) {
    // خريطة DHCP بالماك (حرفٌ كبير) ⇒ (اسم، آيبي). كلّ إيجارٍ ٤ حقول: اسم، ماك، آيبي، مدّة.
    final dhcp = <String, ({String? name, String? ip})>{};
    if (dhcpHtml != null) {
      final a = array(dhcpHtml, 'DHCPDynList');
      if (a != null) {
        for (var i = 0; i + 2 < a.length; i += 4) {
          final mac = a[i + 1] is String ? a[i + 1] as String : '';
          if (!mac.contains('-') && !mac.contains(':')) continue; // الذيل 0,0
          final name = a[i] is String ? (a[i] as String).trim() : '';
          final ip = a[i + 2] is String ? (a[i + 2] as String).trim() : '';
          dhcp[mac.toUpperCase()] = (
            name: (name.isEmpty || name.toLowerCase() == 'unknown') ? null : name,
            ip: ip.isEmpty ? null : ip,
          );
        }
      }
    }
    final out = <RouterClient>[];
    if (wlanHtml != null) {
      final h = array(wlanHtml, 'hostList');
      // حقول المحطّة كما يقولها الراوتر (`wlanHostPara[4]`): ٤ في القديم (ماك، حالة، مستلَم، مُرسَل)، ٥ في WR940N v6.
      final f = _int(array(wlanHtml, 'wlanHostPara'), 4);
      final stride = f != null && f >= 4 && f <= 8 ? f : 4;
      if (h != null) {
        // الذيل 0,0 ليس نصّاً ⇒ يُتخطّى.
        for (var i = 0; i + 3 < h.length; i += stride) {
          final mac = h[i] is String ? h[i] as String : '';
          if (!mac.contains('-') && !mac.contains(':')) continue;
          final d = dhcp[mac.toUpperCase()];
          out.add(RouterClient(mac: mac, ip: d?.ip, name: d?.name, wired: false));
        }
      }
    }
    return out;
  }

  /// عيّنة حيّة من صفحة الحالة — null إن غابت العدّادات.
  static TpClassicLive? live(String statusHtml, DateTime at) {
    final stat = array(statusHtml, 'statistList');
    final rx = _int(stat, 0);
    final tx = _int(stat, 1);
    if (rx == null || tx == null) return null;
    return TpClassicLive(
      rxBytes: rx,
      txBytes: tx,
      at: at,
      uptimeSeconds: _int(array(statusHtml, 'statusPara'), 4),
      wanOnlineSeconds: durationSeconds(_str(array(statusHtml, 'wanPara'), 12)),
    );
  }

  /// صفحة الحالة (+ الوايرلس + DHCP إن قُرئتا) ⇒ لقطة الجهاز. null حين لا تحمل الصفحة بياناتها (ليست صفحة حالة).
  static UbiquitiStatus? status({
    required String statusHtml,
    String? wlanHtml,
    String? dhcpHtml,
    required String baseUrl,
    String realmModel = '',
  }) {
    final sp = array(statusHtml, 'statusPara');
    final wan = array(statusHtml, 'wanPara');
    if (sp == null || wan == null) return null;
    final stat = array(statusHtml, 'statistList');
    final wlan = array(statusHtml, 'wlanPara');
    final hw = modelFromHardware(_str(sp, 6));
    return UbiquitiStatus(
      hostname: '',
      firmware: _str(sp, 5),
      uptimeSeconds: _int(sp, 4),
      ssid: _str(wlan, 1),
      mode: 'router',
      signalDbm: null,
      noiseFloorDbm: null,
      ccqPercent: null,
      distanceMeters: null,
      txRateKbps: null,
      rxRateKbps: null,
      rxBytes: _int(stat, 0),
      txBytes: _int(stat, 1),
      lanPorts: const [],
      peerMac: null,
      peerCount: wlanHtml == null ? null : wifiClients(wlanHtml),
      baseUrl: baseUrl,
      vendor: 'tpclassic',
      model: hw.isNotEmpty ? hw : realmModel,
      wanOnlineSeconds: durationSeconds(_str(wan, 12)),
      dhcpCount: dhcpHtml == null ? null : dhcpClients(dhcpHtml),
      wanType: wanTypeName(_int(wan, 3)),
      clients: clientList(wlanHtml: wlanHtml, dhcpHtml: dhcpHtml),
    );
  }

  /// الواي فاي من صفحة WlanSecurityRpm (WR940N، ١٢ نوفمبر — من شيفرة الصفحة نفسها): wlanPara[2] نوع الأمان (قيمة الراديو:
  /// 3 WPA/WPA2-Personal · 2 Enterprise · 1 WEP · 0 مطفأ)، [3] خيارات WEP/WPA/PSK حرفاً حرفاً، [9] كلمة سرّ PSK، [16] 1 = تغييرٌ
  /// ينتظر إعادة التشغيل، والاسم ssidList[0]. null حين ليست الصفحة.
  static List<RouterWifi>? wifi(String html) {
    final p = array(html, 'wlanPara');
    if (p == null || p.length < 17) return null;
    final ssid = array(html, 'ssidList');
    final sec = _int(p, 2);
    final opt = '${p[3]}';
    final pskOpt = opt.length > 2 ? opt[2] : '';
    final label = switch (sec) {
      0 => 'مفتوحة',
      1 => 'WEP',
      2 => 'Enterprise',
      3 => switch (pskOpt) { '1' => 'WPA', '2' => 'WPA2', _ => 'WPA/WPA2' },
      _ => '',
    };
    return [
      RouterWifi(
        band: '',
        ssid: ssid != null && ssid.isNotEmpty ? '${ssid[0]}' : '',
        password: sec == 3 ? '${p[9]}' : null,
        enabled: true,
        security: label,
        ref: 'main',
      ),
    ];
  }

  /// الصفحة تقول «التغيير لا يسري حتى يُعاد تشغيل الجهاز» (wlanPara[16] == 1).
  static bool wifiNeedsReboot(String html) => _int(array(html, 'wlanPara'), 16) == 1;

  /// استعلام زرّ «Save» في نموذج الصفحة (GET بحقوله بترتيبه): كلّ القيم كما قرأتها الصفحة (wlanPara/wlanList) وكلمة السرّ الجديدة
  /// وحدها تتغيّر. null حين ليس الأمان WPA/WPA2-Personal (لا كلمة سرٍّ شخصيّة تُغيَّر).
  static String? wifiSaveQuery(String html, String newPass) {
    final p = array(html, 'wlanPara');
    if (p == null || p.length < 18 || _int(p, 2) != 3) return null;
    final l = array(html, 'wlanList') ?? const <Object>[];
    String at(List<Object> a, int i) => i < a.length ? '${a[i]}' : '';
    final opt = at(p, 3);
    final vap = _int(p, 17);
    final q = <(String, String)>[
      ('vapIdx', vap != null && vap >= 1 && vap <= 4 ? '$vap' : ''),
      ('wepSecOpt', opt.isNotEmpty ? opt[0] : ''),
      ('keytype', at(p, 4)),
      ('keynum', at(p, 10)),
      ('key1', at(l, 0)),
      ('length1', at(l, 1)),
      ('key2', at(l, 2)),
      ('length2', at(l, 3)),
      ('key3', at(l, 4)),
      ('length3', at(l, 5)),
      ('key4', at(l, 6)),
      ('length4', at(l, 7)),
      ('wpaSecOpt', opt.length > 1 ? opt[1] : ''),
      ('wpaCipher', at(p, 13)),
      ('radiusIp', at(p, 6)),
      ('radiusPort', at(p, 7)),
      ('radiusSecret', at(p, 8)),
      ('intervalWpa', at(p, 15)),
      ('secType', '3'),
      ('pskSecOpt', opt.length > 2 ? opt[2] : ''),
      ('pskCipher', at(p, 14)),
      ('pskSecret', newPass),
      ('interval', at(p, 11)),
      ('Save', 'Save'),
    ];
    return q.map((e) => '${e.$1}=${Uri.encodeQueryComponent(e.$2)}').join('&');
  }
}

class TplinkClassicService {
  TplinkClassicService._();

  static const _connect = Duration(seconds: 4);
  static const _read = Duration(seconds: 8);

  /// للاختبار: أصل الجهاز (منفذٌ محلّيّ لجهازٍ وهميّ).
  @visibleForTesting
  static String Function(String host) baseFor = (h) => 'http://$h';

  static final _issues = <String, ({TpClassicIssue issue, String trace, DateTime at})>{};

  /// اعتمادٌ رفضه الجهاز (401) لا يُعاد عليه تلقائيّاً — كـZTE وPharos: قفله بعد الخطأ لم يُجرَّب، فلا نطرقه بالمرفوض كلّ موجة
  /// ولا كلّ نبضة. اعتمادٌ **آخر** يُجرَّب عادةً؛ والمرفوض نفسه يعود بـ[forget] وحده («حفظ وفحص الجهاز»). بالذاكرة فقط، لا يُحفظ.
  static final _rejected = <String, Set<String>>{};

  /// سبب آخر قراءةٍ فشلت لهذا العنوان (الكرت يصوغ جملته منه).
  static ({TpClassicIssue issue, String trace})? lastIssue(String host) {
    final i = _issues[host.trim()];
    return i == null ? null : (issue: i.issue, trace: i.trace);
  }

  static void forget(String host) {
    _issues.remove(host.trim());
    _rejected.remove(host.trim());
  }

  /// يُفرَّغ مع كاشات الفحص كلّها (تبديل الحساب/الشركة) — كـ[TplinkPharosService.reset].
  static void reset() {
    _issues.clear();
    _rejected.clear();
    _cookieHosts.clear();
  }

  static bool _wasRejected(String host, String auth) => _rejected[host]?.contains(auth) ?? false;
  static void _reject(String host, String auth) => (_rejected[host] ??= <String>{}).add(auth);

  static String _basic(String user, String pass) => 'Basic ${base64.encode(utf8.encode('$user:$pass'))}';

  /// GET واحد ⇒ (الحالة، الترويسات، النصّ). شبكةٌ/مهلة ⇒ null. لا إعادة أبداً.
  static Future<({int status, HttpHeaders headers, String body})?> _get(
    String host,
    String path, {
    String? auth,
    String? cookie,
    String? referer,
    Duration? timeout,
  }) async {
    final base = baseFor(host);
    final client = HttpClient()..connectionTimeout = _connect;
    try {
      final req = await client.getUrl(Uri.parse('$base$path')).timeout(_connect);
      req.followRedirects = false;
      if (auth != null) req.headers.set(HttpHeaders.authorizationHeader, auth);
      if (cookie != null) req.headers.set(HttpHeaders.cookieHeader, cookie);
      // حارس هذه الفيرموَيرات: طلبٌ بلا Referer من الجهاز نفسه يُجاب بصفحة «لا صلاحيّة».
      req.headers.set(HttpHeaders.refererHeader, referer ?? '$base/');
      final res = await req.close().timeout(timeout ?? _read);
      lastSetCookieNames = (res.headers[HttpHeaders.setCookieHeader] ?? const <String>[]).map((c) => c.split('=').first).join(',');
      final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(timeout ?? _read);
      // الصفحات iso-8859-1 لكنّ الـSSID/الأسماء قد تكون UTF-8 ⇒ UTF-8 متسامح (ما يخصّنا كلّه ASCII أو UTF-8 سليم).
      return (status: res.statusCode, headers: res.headers, body: utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// الفيرموير الأحدث لكلّ عنوان (عُرف بالتعرّف أو بقراءة): MD5 كلمة السرّ؟ — النبضة الحيّة تدخل بالكوكي بلا طلب الحالة أوّلاً.
  static final _cookieHosts = <String, bool>{};

  /// أهو راوتر TP-Link كلاسيكيّ؟ طلبٌ واحد بلا اعتماد: 401 + realm فيه «TP-LINK» (القديم)، أو 200 بصفحة دخولٍ فيها
  /// `httpAutErrorArray` (الأحدث — realm في الترويسة إن وُجد). غيره (أو لا ردّ) ⇒ null.
  static Future<TpClassicHello?> detect(String host) async {
    final h0 = host.trim();
    final r = await _get(h0, '/', timeout: const Duration(seconds: 5));
    if (r == null) return null;
    final h = r.headers.value(HttpHeaders.wwwAuthenticateHeader) ?? '';
    final m = RegExp(r'Basic\s+realm="([^"]*)"', caseSensitive: false).firstMatch(h);
    final realm = m?.group(1) ?? '';
    if (r.status == 401) {
      if (m == null || !realm.toUpperCase().contains('TP-LINK')) return null;
      return TpClassicHello(realm: realm, model: TpClassicParse.modelFromRealm(realm));
    }
    if (r.status == 200) {
      final st = TpClassicParse.loginState(r.body);
      if (st == null) return null;
      if (realm.isNotEmpty && !realm.toUpperCase().contains('TP-LINK')) return null;
      if (realm.isEmpty && !r.body.contains('/userRpm/LoginRpm.htm')) return null;
      _cookieHosts[h0] = st.md5;
      return TpClassicHello(realm: realm, model: TpClassicParse.modelFromRealm(realm), cookieAuth: true, md5: st.md5);
    }
    return null;
  }

  /// `escape()` في JavaScript (ما يفعله الجهاز نفسه بالكوكي): تبقى الحروف والأرقام و`@*_+-./`، وغيرها `%XX`.
  @visibleForTesting
  static String jsEscape(String s) {
    final b = StringBuffer();
    for (final c in s.codeUnits) {
      final ok = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || '@*_+-./'.codeUnits.contains(c);
      if (ok) {
        b.writeCharCode(c);
      } else if (c < 0x100) {
        b.write('%${c.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      } else {
        b.write('%u${c.toRadixString(16).toUpperCase().padLeft(4, '0')}');
      }
    }
    return b.toString();
  }

  /// كوكي الدخول كما تبنيه صفحة الجهاز (MD5 كلمة السرّ حين يطلبه).
  @visibleForTesting
  static String cookieAuth(String user, String pass, {required bool md5}) {
    final p = md5 ? crypto.md5.convert(utf8.encode(pass)).toString() : pass;
    return 'Authorization=${jsEscape('Basic ${base64.encode(utf8.encode('$user:$p'))}')}';
  }

  /// جلسة الفيرموير الأحدث: الحالة بلا اعتماد ([checkFront] — مقفل/مديرٌ آخر ⇒ لا إرسال) ⇒ الدخول ⇒ التوكن ⇒ [fn] ⇒ **الخروج دائماً**
  /// (مديرٌ واحد: جلسةٌ تبقى تحجب صاحب الراوتر). كلمة سرٍّ مرفوضة لا تُرسل ثانيةً. null ⇒ السبب في [lastIssue].
  static Future<T?> _withCookie<T>(
    String h,
    String user,
    String pass,
    Future<T?> Function(String tok, String cookie, String ref) fn, {
    bool checkFront = true,
  }) async {
    var md5 = _cookieHosts[h] ?? true;
    if (checkFront) {
      final front = await _get(h, '/');
      if (front == null) {
        _note(h, TpClassicIssue.unreachable, 'front no-reply');
        return null;
      }
      final st = TpClassicParse.loginState(front.body);
      if (st == null) {
        _note(h, TpClassicIssue.readFailed, 'front without login state');
        return null;
      }
      if (st.code == 1) {
        _note(h, TpClassicIssue.locked, 'locked (ten wrong tries — two hours)');
        return null;
      }
      if (st.code == 0) {
        _note(h, TpClassicIssue.busy, 'another admin is logged in');
        return null;
      }
      md5 = st.md5;
      _cookieHosts[h] = md5;
    }
    final cookie = cookieAuth(user, pass, md5: md5);
    if (_wasRejected(h, cookie)) {
      _note(h, TpClassicIssue.rejected, 'remembered');
      return null;
    }
    final r = await _get(h, '/userRpm/LoginRpm.htm?Save=Save', cookie: cookie);
    if (r == null) {
      _note(h, TpClassicIssue.unreachable, 'login no-reply');
      return null;
    }
    final tok = TpClassicParse.loginToken(r.body);
    if (tok == null) {
      var st = TpClassicParse.loginState(r.body);
      if (st == null) {
        final f = await _get(h, '/');
        st = f == null ? null : TpClassicParse.loginState(f.body);
      }
      switch (st?.code) {
        case 2:
          _reject(h, cookie);
          _note(h, TpClassicIssue.rejected, 'login rejected');
        case 1:
          _note(h, TpClassicIssue.locked, 'locked');
        case 0:
          _note(h, TpClassicIssue.busy, 'another admin is logged in');
        default:
          _note(h, TpClassicIssue.readFailed, 'login without token');
      }
      return null;
    }
    final ref = '${baseFor(h)}/$tok/userRpm/MenuRpm.htm';
    try {
      return await fn(tok, cookie, ref);
    } finally {
      await _get(h, '/$tok/userRpm/LogoutRpm.htm', cookie: cookie, referer: ref, timeout: const Duration(seconds: 4));
    }
  }

  /// للأدوات الحيّة: صفحاتٌ بعينها في جلسةٍ واحدة (الفيرموير الأحدث) ⇒ نصوصها — الأداة تقرر ما تطبع.
  @visibleForTesting
  static Future<Map<String, String>?> debugPages(String host, String user, String pass, List<String> paths) =>
      _withCookie<Map<String, String>>(host.trim(), user, pass, (tok, cookie, ref) async {
        final out = <String, String>{};
        for (final p in paths) {
          final r = await _get(host.trim(), '/$tok/userRpm/$p', cookie: cookie, referer: ref);
          out[p] = r == null ? '<no-reply>' : 'HTTP ${r.status}\n${r.body}';
        }
        return out;
      });

  /// قراءةٌ كاملة بالفيرموير الأحدث (جلسةٌ واحدة: الحالة ثمّ الوايرلس وDHCP).
  static Future<UbiquitiStatus?> _readOnceCookie(String h, String user, String pass, String realmModel) =>
      _withCookie<UbiquitiStatus>(h, user, pass, (tok, cookie, ref) async {
        final st = await _get(h, '/$tok/userRpm/StatusRpm.htm', cookie: cookie, referer: ref);
        if (st == null) {
          _note(h, TpClassicIssue.unreachable, 'status no-reply');
          return null;
        }
        if (st.status != 200) {
          _note(h, TpClassicIssue.readFailed, 'status http ${st.status}');
          return null;
        }
        final more = await Future.wait([
          _get(h, '/$tok/userRpm/WlanStationRpm.htm', cookie: cookie, referer: ref),
          _get(h, '/$tok/userRpm/AssignedIpAddrListRpm.htm', cookie: cookie, referer: ref),
        ]);
        String? ok(({int status, HttpHeaders headers, String body})? r) => r != null && r.status == 200 ? r.body : null;
        final snap = TpClassicParse.status(
          statusHtml: st.body,
          wlanHtml: ok(more[0]),
          dhcpHtml: ok(more[1]),
          baseUrl: baseFor(h),
          realmModel: realmModel,
        );
        if (snap == null) {
          _note(h, TpClassicIssue.readFailed, 'status page without data');
          return null;
        }
        _issues.remove(h);
        return snap;
      });

  /// نبضة الكرت الحيّة: عيّنة الحالة (+ عدّ الوايرلس حين [clients]) — للقديم طلبٌ أو اثنان بـBasic، وللأحدث جلسةٌ واحدة («/» ثمّ
  /// دخول، صفحة أو اثنتان، خروج). حيّاً على WR940N: دخولٌ بلا طلب «/» قبله لا يعطي توكناً (صفحة الدخول تُهيّئه) — فـ«/» دائماً،
  /// وهو نفسه يقول «مديرٌ آخر داخل» قبل أيّ اعتماد.
  static Future<({TpClassicLive? live, int? clients})> pulse(String host, String user, String pass, {bool clients = false}) async {
    final h = host.trim();
    if (_cookieHosts.containsKey(h)) {
      final r = await _withCookie<({TpClassicLive? live, int? clients})>(h, user, pass, (tok, cookie, ref) async {
        final st = await _get(h, '/$tok/userRpm/StatusRpm.htm', cookie: cookie, referer: ref);
        final live = st != null && st.status == 200 ? TpClassicParse.live(st.body, DateTime.now()) : null;
        int? n;
        if (clients && live != null) {
          final w = await _get(h, '/$tok/userRpm/WlanStationRpm.htm', cookie: cookie, referer: ref);
          n = w != null && w.status == 200 ? TpClassicParse.wifiClients(w.body) : null;
        }
        return (live: live, clients: n);
      });
      return r ?? (live: null, clients: null);
    }
    final live = await sample(h, user, pass);
    final n = clients && live != null ? await sampleClients(h, user, pass) : null;
    return (live: live, clients: n);
  }

  static void _note(String host, TpClassicIssue issue, String trace) =>
      _issues[host] = (issue: issue, trace: trace, at: DateTime.now());

  /// قراءةٌ كاملة: صفحة الحالة أوّلاً (تحسم الاعتماد: 401 = رفض)، ثمّ الوايرلس وDHCP معاً. null ⇒ السبب في [lastIssue].
  static Future<UbiquitiStatus?> readOnce(String host, String user, String pass, {String realmModel = '', TpClassicHello? hello}) async {
    final h = host.trim();
    if (hello != null && hello.cookieAuth) _cookieHosts[h] ??= hello.md5;
    if (_cookieHosts.containsKey(h)) return _readOnceCookie(h, user, pass, realmModel);
    final auth = _basic(user, pass);
    if (_wasRejected(h, auth)) {
      _note(h, TpClassicIssue.rejected, 'remembered');
      return null;
    }
    final st = await _get(h, '/userRpm/StatusRpm.htm', auth: auth);
    if (st == null) {
      _note(h, TpClassicIssue.unreachable, 'status no-reply');
      return null;
    }
    if (st.status == 401) {
      _reject(h, auth);
      _note(h, TpClassicIssue.rejected, 'status 401');
      return null;
    }
    if (st.status != 200) {
      _note(h, TpClassicIssue.readFailed, 'status http ${st.status}');
      return null;
    }
    // صفحة دخول الفيرموير الأحدث بدل الحالة (لم يُعرف نوعه — كاش التعرّف بعد إعادة الضبط) ⇒ جلسة الكوكي
    final ls = TpClassicParse.loginState(st.body);
    if (ls != null && TpClassicParse.array(st.body, 'statusPara') == null) {
      _cookieHosts[h] = ls.md5;
      return _readOnceCookie(h, user, pass, realmModel);
    }
    final more = await Future.wait([
      _get(h, '/userRpm/WlanStationRpm.htm', auth: auth),
      _get(h, '/userRpm/AssignedIpAddrListRpm.htm', auth: auth),
    ]);
    String? ok(({int status, HttpHeaders headers, String body})? r) => r != null && r.status == 200 ? r.body : null;
    final snap = TpClassicParse.status(
      statusHtml: st.body,
      wlanHtml: ok(more[0]),
      dhcpHtml: ok(more[1]),
      baseUrl: baseFor(h),
      realmModel: realmModel,
    );
    if (snap == null) {
      _note(h, TpClassicIssue.readFailed, 'status page without data');
      return null;
    }
    _issues.remove(h);
    return snap;
  }

  /// عيّنة حيّة (صفحة الحالة وحدها، ~0.7ث) للترافيك ومدّتَي التشغيل والاتّصال. رفضٌ/شبكة ⇒ null.
  static Future<TpClassicLive?> sample(String host, String user, String pass) async {
    final r = await _authedGet(host.trim(), '/userRpm/StatusRpm.htm', _basic(user, pass));
    return r == null ? null : TpClassicParse.live(r, DateTime.now());
  }

  /// أجهزة الوايرلس المتّصلة الآن (صفحتها وحدها، ~0.6ث).
  static Future<int?> sampleClients(String host, String user, String pass) async {
    final r = await _authedGet(host.trim(), '/userRpm/WlanStationRpm.htm', _basic(user, pass));
    return r == null ? null : TpClassicParse.wifiClients(r);
  }

  /// للأدوات الحيّة: أسماء الكوكي في آخر Set-Cookie (بلا قيم).
  @visibleForTesting
  static String? lastSetCookieNames;

  /// للأدوات الحيّة: أثر خطوات الحفظ (حالةٌ وأطوال — بلا قيم).
  @visibleForTesting
  static List<String>? trace;

  static RouterFail _fail(String h) => switch (_issues[h]?.issue) {
        TpClassicIssue.rejected => RouterFail.rejected,
        TpClassicIssue.busy => RouterFail.busy,
        TpClassicIssue.locked => RouterFail.locked,
        TpClassicIssue.unreachable => RouterFail.unreachable,
        _ => RouterFail.failed,
      };

  /// صفحةٌ في جلسة الراوتر (الفيرموير الأحدث بالكوكي والتوكن، والقديم بـBasic) — [fn] تتلقّى جالب الصفحات ومرجع الصفحة.
  static Future<T?> _inSession<T>(String h, String user, String pass,
      Future<T?> Function(Future<({int status, String body})?> Function(String page, {String? query, String? refPage}) get) fn) async {
    if (!_cookieHosts.containsKey(h)) await detect(h);
    if (_cookieHosts.containsKey(h)) {
      return _withCookie<T>(h, user, pass, (tok, cookie, ref) => fn((page, {query, refPage}) async {
            final r = await _get(h, '/$tok/userRpm/$page${query == null ? '' : '?$query'}',
                cookie: cookie, referer: refPage == null ? ref : '${baseFor(h)}/$tok/userRpm/$refPage', timeout: const Duration(seconds: 15));
            return r == null ? null : (status: r.status, body: r.body);
          }));
    }
    final auth = _basic(user, pass);
    if (_wasRejected(h, auth)) {
      _note(h, TpClassicIssue.rejected, 'remembered');
      return null;
    }
    return fn((page, {query, refPage}) async {
      final r = await _get(h, '/userRpm/$page${query == null ? '' : '?$query'}',
          auth: auth, referer: refPage == null ? null : '${baseFor(h)}/userRpm/$refPage', timeout: const Duration(seconds: 15));
      if (r != null && r.status == 401) {
        _reject(h, auth);
        _note(h, TpClassicIssue.rejected, '$page 401');
        return null;
      }
      return r == null ? null : (status: r.status, body: r.body);
    });
  }

  /// كلمة سرّ الواي فاي من صفحة الأمان (قراءةٌ وحدها).
  static Future<RouterResult<List<RouterWifi>>> readWifi(String host, String user, String pass) async {
    final h = host.trim();
    final got = await _inSession<RouterResult<List<RouterWifi>>>(h, user, pass, (get) async {
      final r = await get('WlanSecurityRpm.htm');
      final w = r == null || r.status != 200 ? null : TpClassicParse.wifi(r.body);
      return w == null ? const RouterResult.fail(RouterFail.failed, 'security page') : RouterResult.ok(w);
    });
    return got ?? RouterResult.fail(_fail(h), _issues[h]?.trace);
  }

  /// كلمة سرّ جديدة بزرّ «Save» في صفحة الأمان (حقول النموذج بقيمها المقروءة — [TpClassicParse.wifiSaveQuery])، والصفحة التي تعود
  /// تؤكّد الحفظ. هذه الفيرموَيرات تقول «لا يسري حتى يُعاد التشغيل» ⇒ detail = `needs-reboot` (الكرت يعرض الإقلاع).
  static Future<RouterResult<List<RouterWifi>>> setWifiPassword(String host, String user, String pass, String newPass) async {
    // مديرٌ واحد على الراوتر: دخولٌ من هاتفٍ آخر (نبضة كرتٍ مفتوح) يُسقط جلستنا وسط الحفظ ⇒ الصفحة تعود «خروجاً». الحفظ نفسه يُعاد
    // مرّةً بعد لحظة (كلمة السرّ نفسها — إعادةٌ لا تضرّ).
    final first = await _setWifiOnce(host, user, pass, newPass);
    if (first.ok || first.detail != 'session lost') return first;
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    return _setWifiOnce(host, user, pass, newPass);
  }

  static Future<RouterResult<List<RouterWifi>>> _setWifiOnce(String host, String user, String pass, String newPass) async {
    final h = host.trim();
    final got = await _inSession<RouterResult<List<RouterWifi>>>(h, user, pass, (get) async {
      final page = await get('WlanSecurityRpm.htm');
      trace?.add('page http=${page?.status} len=${page?.body.length} setCookie=${lastSetCookieNames ?? '-'}');
      if (page == null || page.status != 200 || TpClassicParse.wifi(page.body) == null) {
        return const RouterResult.fail(RouterFail.failed, 'security page');
      }
      final q = TpClassicParse.wifiSaveQuery(page.body, newPass);
      if (q == null) return const RouterResult.fail(RouterFail.noPsk);
      final saved = await get('WlanSecurityRpm.htm', query: q, refPage: 'WlanSecurityRpm.htm');
      trace?.add('save http=${saved?.status} len=${saved?.body.length} sec=${saved != null && TpClassicParse.wifi(saved.body) != null} '
          'logout=${saved?.body.contains('Authorization=;path=/') ?? false}');
      // الردّ نفسه صفحة الأمان بعد الحفظ — وإن ضاع: قراءةٌ ثانية تحسم
      var body = saved != null && saved.status == 200 && TpClassicParse.wifi(saved.body) != null ? saved.body : null;
      if (body == null) {
        final again = await get('WlanSecurityRpm.htm');
        trace?.add('again http=${again?.status} len=${again?.body.length} logout=${again?.body.contains('Authorization=;path=/') ?? false}');
        body = again != null && again.status == 200 ? again.body : null;
      }
      final w = body == null ? null : TpClassicParse.wifi(body);
      if (w == null) {
        final lost = (saved?.body.contains('Authorization=;path=/') ?? false);
        return RouterResult.fail(RouterFail.failed, lost ? 'session lost' : 'verify read');
      }
      if (w.first.password != newPass) return const RouterResult.fail(RouterFail.failed, 'not saved');
      return RouterResult.ok(w, TpClassicParse.wifiNeedsReboot(body!) ? RouterResult.needsRebootTag : null);
    });
    return got ?? RouterResult.fail(_fail(h), _issues[h]?.trace);
  }

  /// بعد [setWifiPassword]: أتنتظر الصفحة إعادة التشغيل؟ (wlanPara[16]) — قراءةٌ وحدها.
  static Future<bool?> wifiPendingReboot(String host, String user, String pass) async {
    final h = host.trim();
    return _inSession<bool>(h, user, pass, (get) async {
      final r = await get('WlanSecurityRpm.htm');
      return r == null || r.status != 200 ? null : TpClassicParse.wifiNeedsReboot(r.body);
    });
  }

  /// إعادة التشغيل بزرّ صفحة «Reboot» نفسها (GET `SysRebootRpm.htm?Reboot=Reboot` — النموذج في الجهاز، ١٢ نوفمبر).
  /// ⛔ جارتها RestoreDefaultCfgRpm.htm إعادة ضبط المصنع — لا تُطلب أبداً.
  static Future<RouterResult<RouterReboot>> reboot(String host, String user, String pass) async {
    final h = host.trim();
    final got = await _inSession<RouterResult<RouterReboot>>(h, user, pass, (get) async {
      final r = await get('SysRebootRpm.htm', query: 'Reboot=Reboot', refPage: 'SysRebootRpm.htm');
      if (r == null) return const RouterResult.ok(RouterReboot(confirmed: false));
      return r.status == 200 ? const RouterResult.ok(RouterReboot(confirmed: true)) : RouterResult.fail(RouterFail.failed, 'reboot ${r.status}');
    });
    return got ?? RouterResult.fail(_fail(h), _issues[h]?.trace);
  }

  /// قراءةٌ بالاعتماد للنبضة الحيّة: المرفوض لا يُرسل، و401 يُحفظ رفضاً (كلمة السرّ تبدّلت ⇒ لا طرقٌ كلّ ثلاث ثوانٍ).
  static Future<String?> _authedGet(String host, String path, String auth) async {
    if (_wasRejected(host, auth)) return null;
    final r = await _get(host, path, auth: auth);
    if (r == null) return null;
    if (r.status == 401) {
      _reject(host, auth);
      _note(host, TpClassicIssue.rejected, '$path 401');
      return null;
    }
    return r.status == 200 ? r.body : null;
  }
}

/// معدّل الترافيك من عيّنتين متتاليتين: (تنزيل، رفع) بالبت/ثانية — null عند عدّادٍ رجع للصفر (إقلاع/انقطاع) أو فاصلٍ غير صالح.
({int down, int up})? tpClassicRate(TpClassicLive a, TpClassicLive b) {
  final ms = b.at.difference(a.at).inMilliseconds;
  if (ms < 500) return null;
  final drx = b.rxBytes - a.rxBytes;
  final dtx = b.txBytes - a.txBytes;
  if (drx < 0 || dtx < 0) return null;
  return (down: (drx * 8 * 1000 / ms).round(), up: (dtx * 8 * 1000 / ms).round());
}
