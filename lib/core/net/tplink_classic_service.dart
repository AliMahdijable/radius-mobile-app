import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/device_health.dart';

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

/// تعرّفٌ ناجح: الراوتر يقول اسمه في realm المصادقة.
class TpClassicHello {
  const TpClassicHello({required this.realm, required this.model});
  final String realm;

  /// من realm («WR741ND») — الطراز الكامل بإصداره يأتي من صفحة الحالة بعد الدخول.
  final String model;
}

enum TpClassicIssue { rejected, unreachable, readFailed }

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

  static int? _int(List<Object>? a, int i) => (a != null && i < a.length && a[i] is int) ? a[i] as int : null;
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
    );
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
  }

  static bool _wasRejected(String host, String auth) => _rejected[host]?.contains(auth) ?? false;
  static void _reject(String host, String auth) => (_rejected[host] ??= <String>{}).add(auth);

  static String _basic(String user, String pass) => 'Basic ${base64.encode(utf8.encode('$user:$pass'))}';

  /// GET واحد ⇒ (الحالة، الترويسات، النصّ). شبكةٌ/مهلة ⇒ null. لا إعادة أبداً.
  static Future<({int status, HttpHeaders headers, String body})?> _get(
    String host,
    String path, {
    String? auth,
    Duration? timeout,
  }) async {
    final base = baseFor(host);
    final client = HttpClient()..connectionTimeout = _connect;
    try {
      final req = await client.getUrl(Uri.parse('$base$path')).timeout(_connect);
      req.followRedirects = false;
      if (auth != null) req.headers.set(HttpHeaders.authorizationHeader, auth);
      // حارس هذه الفيرموَيرات: طلبٌ بلا Referer من الجهاز نفسه يُجاب بصفحة «لا صلاحيّة».
      req.headers.set(HttpHeaders.refererHeader, '$base/');
      final res = await req.close().timeout(timeout ?? _read);
      final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(timeout ?? _read);
      // الصفحات iso-8859-1 لكنّ الـSSID/الأسماء قد تكون UTF-8 ⇒ UTF-8 متسامح (ما يخصّنا كلّه ASCII أو UTF-8 سليم).
      return (status: res.statusCode, headers: res.headers, body: utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// أهو راوتر TP-Link كلاسيكيّ؟ طلبٌ واحد بلا اعتماد: 401 + realm فيه «TP-LINK». غيره (أو لا ردّ) ⇒ null.
  static Future<TpClassicHello?> detect(String host) async {
    final r = await _get(host.trim(), '/', timeout: const Duration(seconds: 5));
    if (r == null || r.status != 401) return null;
    final h = r.headers.value(HttpHeaders.wwwAuthenticateHeader) ?? '';
    final m = RegExp(r'Basic\s+realm="([^"]*)"', caseSensitive: false).firstMatch(h);
    if (m == null) return null;
    final realm = m.group(1)!;
    if (!realm.toUpperCase().contains('TP-LINK')) return null;
    return TpClassicHello(realm: realm, model: TpClassicParse.modelFromRealm(realm));
  }

  static void _note(String host, TpClassicIssue issue, String trace) =>
      _issues[host] = (issue: issue, trace: trace, at: DateTime.now());

  /// قراءةٌ كاملة: صفحة الحالة أوّلاً (تحسم الاعتماد: 401 = رفض)، ثمّ الوايرلس وDHCP معاً. null ⇒ السبب في [lastIssue].
  static Future<UbiquitiStatus?> readOnce(String host, String user, String pass, {String realmModel = ''}) async {
    final h = host.trim();
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
