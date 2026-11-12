import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/device_health.dart';
import 'router_types.dart';

/// راوتر Tenda (واجهة GoAhead — F3 بفيرموير V12.01.01.42 وراوترٌ آخر بـV02.03.01.110، قِيسا حيّاً ١٢ نوفمبر على راوترَي مشتركَين):
///
/// * HTTP على 80 وحده. «/» ⇒ 302 إلى `/login.html` (`Server: GoAhead-Webs`)، وصفحة الدخول `<title>Tenda | LOGIN</title>` بنموذج
///   `POST /login/Auth` — التعرّف بطلب `/login.html` وحده (بلا اعتماد).
/// * **كلمة سرٍّ وحدها** (لا يوزر): `password=base64(utf8(pwd))` ⇒ 302 إلى `/index.html` + كوكي الجلسة (`ecos_pw`)؛ الرفض ⇒
///   `/login.html?1`، و«حتى ٤ مدراء» ⇒ `?2` (دخولنا لا يطرد أحداً)، و`?3` تجاوزٌ آخر. الخروج `POST goform/loginOut` (`action=loginout`).
/// * القراءة GET بالكوكي: `goform/getStatus?…&modules=internetStatus,deviceStatistics,systemInfo,wanAdvCfg` ⇒ `deviceStastics` (بخطئه
///   الإملائيّ) {statusOnlineNumber، statusUpSpeed/statusDownSpeed بالـKB/s} · `systemInfo` {wanConnectTime ثوانٍ، wanType،
///   softVersion} · `wanAdvCfg.wanSpeedCurrent` = **سرعة منفذ الإنترنت** بالميغابت؛ و`goform/getQos?…&modules=localhost,onlineList`
///   ⇒ المتّصلون الآن [{qosListHostname, qosListRemark, qosListIP, qosListConnectType wifi|wired, qosListMac, …}].
/// * ⛔ لا تُطلب وحدة `wifiBasicCfg` (فيها كلمة الوايفاي) ولا أيّ `set…`. كلمة سرٍّ رفضها الجهاز لا تُعاد تلقائيّاً.

enum TendaIssue { rejected, busy, unreachable, readFailed }

/// قارئاتٌ صرفة (بلا شبكة) — تُختبر بقوالب بنية الردود الحيّة.
class TendaParse {
  TendaParse._();

  static String _s(Object? v) => v == null ? '' : v.toString().trim();

  static int? _int(Object? v) {
    if (v is int) return v;
    final t = _s(v);
    return RegExp(r'^\d+$').hasMatch(t) ? int.parse(t) : null;
  }

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(_s(v));
  }

  static Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

  /// نوع الاتّصال كما تكتبه الواجهة.
  static String wanTypeName(String t) => switch (t.toLowerCase()) {
        'pppoe' => 'PPPoE',
        'dhcp' => 'Dynamic IP',
        'static' => 'Static IP',
        _ => t,
      };

  /// KB/s (كما تعرضها الواجهة: ١٠٢٤ فما فوق ⇒ MB/s) ⇒ بت/ثانية.
  static int? kbpsToBps(Object? kb) {
    final v = _num(kb);
    if (v == null || v < 0) return null;
    return (v * 1024 * 8).round();
  }

  /// الترافيك الحيّ لـWAN من ردّ getStatus ⇒ (تنزيل، رفع) بت/ثانية، وإلّا null.
  static ({int down, int up})? rates(Map<String, dynamic> status) {
    final d = _map(status['deviceStastics'] ?? status['deviceStatistics']);
    final down = kbpsToBps(d['statusDownSpeed']);
    final up = kbpsToBps(d['statusUpSpeed']);
    if (down == null || up == null) return null;
    return (down: down, up: up);
  }

  /// المتّصلون الآن من onlineList — الاسم = ملاحظة الوكيل إن وُجدت، وإلّا اسم الجهاز (لا «Unknown»).
  static List<RouterClient> clients(Map<String, dynamic>? qos) {
    final list = qos?['onlineList'];
    if (list is! List) return const [];
    final out = <RouterClient>[];
    for (final e in list) {
      if (e is! Map) continue;
      final mac = _s(e['qosListMac']);
      if (mac.isEmpty) continue;
      final remark = _s(e['qosListRemark']);
      final host = _s(e['qosListHostname']);
      final name = remark.isNotEmpty ? remark : (host.isEmpty || host.toLowerCase() == 'unknown' ? null : host);
      final ip = _s(e['qosListIP']);
      out.add(RouterClient(
        mac: mac.toUpperCase(),
        ip: ip.isEmpty ? null : ip,
        name: name,
        wired: _s(e['qosListConnectType']).toLowerCase() == 'wired',
      ));
    }
    return out;
  }

  /// ردّ getStatus (+ getQos إن قُرئ) ⇒ لقطة الجهاز. null حين لا يحمل الردّ بياناته.
  static UbiquitiStatus? status({required Map<String, dynamic> status, Map<String, dynamic>? qos, required String baseUrl}) {
    final sys = _map(status['systemInfo']);
    final dev = _map(status['deviceStastics'] ?? status['deviceStatistics']);
    if (sys.isEmpty && dev.isEmpty) return null;
    final wan = _map(status['wanAdvCfg']);
    final list = clients(qos);
    final online = _int(dev['statusOnlineNumber']);
    final wt = _s(sys['wanType']).isNotEmpty ? _s(sys['wanType']) : _s(wan['wanType']);
    return UbiquitiStatus(
      hostname: '',
      firmware: _s(sys['softVersion']),
      uptimeSeconds: null,
      ssid: '',
      mode: 'router',
      signalDbm: null,
      noiseFloorDbm: null,
      ccqPercent: null,
      distanceMeters: null,
      txRateKbps: null,
      rxRateKbps: null,
      lanPorts: const [],
      peerMac: null,
      peerCount: online ?? (qos == null ? null : list.length),
      baseUrl: baseUrl,
      vendor: 'tenda',
      model: '',
      wanOnlineSeconds: _int(sys['wanConnectTime']),
      wanType: wanTypeName(wt),
      clients: list,
      wanLinkMbps: _int(wan['wanSpeedCurrent']),
    );
  }
}

/// عيّنة النبضة الحيّة: الترافيك + العدّ + مدّة الاتّصال.
/// الواي فاي في Tenda (وحدة wifiBasicCfg من `goform/getWifi` — F3 بواجهتيه، ١٢ نوفمبر).
class TendaWifi {
  TendaWifi._();

  static bool _open(Object? mode) => '${mode ?? ''}'.trim().toLowerCase() == 'none';

  static String _label(Object? mode) {
    final m = '${mode ?? ''}'.trim();
    if (m.isEmpty) return '';
    if (_open(m)) return 'مفتوحة';
    final u = m.toUpperCase().replaceAll(RegExp(r'[/-](AES|TKIP|TKIPAES|AESTKIP|PSK)$'), '').replaceAll('-PSK', '');
    return switch (u) { 'WPAWPA2' || 'WPA&WPA2' || 'WPA/WPA2' => 'WPA/WPA2', _ => u };
  }

  /// الوحدة ⇒ الشبكات. «توحيد النطاقين» مفعّل ⇒ شبكةٌ واحدة للنطاقين.
  static List<RouterWifi> parse(Map<String, dynamic> w) {
    final unity = '${w['HasDoubleBandUnity']}' == 'true' && '${w['doubleBandUnityEnable']}' == 'true';
    final has5 = w.containsKey('wifiSSID_5G') && '${w['wifiSSID_5G'] ?? ''}'.isNotEmpty;
    final out = <RouterWifi>[
      RouterWifi(
        band: unity ? '2.4G/5G' : (has5 ? '2.4G' : ''),
        ssid: '${w['wifiSSID'] ?? ''}',
        password: _open(w['wifiSecurityMode']) ? null : '${w['wifiPwd'] ?? ''}',
        enabled: '${w['wifiEn'] ?? 'true'}' != 'false' && (!unity || '${w['wifiTotalEn'] ?? 'true'}' != 'false'),
        security: _label(w['wifiSecurityMode']),
        ref: '24',
      ),
    ];
    if (has5 && !unity) {
      out.add(RouterWifi(
        band: '5G',
        ssid: '${w['wifiSSID_5G'] ?? ''}',
        password: _open(w['wifiSecurityMode_5G']) ? null : '${w['wifiPwd_5G'] ?? ''}',
        enabled: '${w['wifiEn_5G'] ?? 'true'}' != 'false',
        security: _label(w['wifiSecurityMode_5G']),
        ref: '5',
      ));
    }
    return out;
  }

  /// حقول وحدة wifiBasicCfg كما ترسلها الصفحة (`getSubmitData`) — بقيمها المقروءة إلّا كلمة السرّ.
  static const fields = [
    'doubleBandUnityEnable', 'wifiTotalEn', 'wifiEn', 'wifiSSID', 'wifiSecurityMode', 'wifiPwd', 'wifiHideSSID', //
    'wifiEn_5G', 'wifiSSID_5G', 'wifiSecurityMode_5G', 'wifiPwd_5G', 'wifiHideSSID_5G',
  ];

  /// جسم `goform/setWifi`: `module1=wifiBasicCfg` ثمّ الحقول الموجودة في القراءة (encodeURIComponent كـobjToString)، وكلمة السرّ
  /// الجديدة لكلّ نطاقٍ غير مفتوح. «توحيد النطاقين» ⇒ 5G نسخة 2.4G (كما تفعل الصفحة). null ⇒ لا نطاق بكلمة سرّ.
  static String? submit(Map<String, dynamic> w, String newPass) {
    final unityCap = '${w['HasDoubleBandUnity']}' == 'true';
    final unity = unityCap && '${w['doubleBandUnityEnable']}' == 'true';
    final v = <String, String>{};
    for (final f in fields) {
      if ((f == 'doubleBandUnityEnable' || f == 'wifiTotalEn') && !unityCap) continue;
      if (!w.containsKey(f) || w[f] == null) continue;
      v[f] = '${w[f]}';
    }
    var any = false;
    if (v.containsKey('wifiPwd') && !_open(v['wifiSecurityMode'])) {
      v['wifiPwd'] = newPass;
      any = true;
    }
    if (unity) {
      for (final f in ['wifiEn', 'wifiSSID', 'wifiSecurityMode', 'wifiPwd', 'wifiHideSSID']) {
        if (v.containsKey(f)) v['${f}_5G'] = v[f]!;
      }
      if (v.containsKey('wifiTotalEn')) {
        v['wifiEn'] = v['wifiTotalEn']!;
        v['wifiEn_5G'] = v['wifiTotalEn']!;
      }
    } else if (v.containsKey('wifiPwd_5G') && !_open(v['wifiSecurityMode_5G'])) {
      v['wifiPwd_5G'] = newPass;
      any = true;
    }
    if (!any) return null;
    return ['module1=wifiBasicCfg', for (final e in v.entries) '${e.key}=${Uri.encodeComponent(e.value)}'].join('&');
  }
}

class TendaLive {
  const TendaLive({this.downBps, this.upBps, this.online, this.wanOnlineSeconds});
  final int? downBps;
  final int? upBps;
  final int? online;
  final int? wanOnlineSeconds;
}

class TendaService {
  TendaService._();

  static const _connect = Duration(seconds: 4);
  static const _read = Duration(seconds: 8);
  static const statusModules = 'internetStatus,deviceStatistics,systemInfo,wanAdvCfg';
  static const qosModules = 'localhost,onlineList';

  /// للاختبار: أصل الجهاز (منفذٌ محلّيّ لجهازٍ وهميّ).
  @visibleForTesting
  static String Function(String host) baseFor = (h) => 'http://$h';

  static final _issues = <String, ({TendaIssue issue, String trace, DateTime at})>{};
  static final _rejected = <String, Set<String>>{};
  static final _rnd = Random();

  static ({TendaIssue issue, String trace})? lastIssue(String host) {
    final i = _issues[host.trim()];
    return i == null ? null : (issue: i.issue, trace: i.trace);
  }

  /// «حفظ وفحص الجهاز»: كلمة السرّ المرفوضة تُجرَّب ثانيةً.
  static void forget(String host) {
    _issues.remove(host.trim());
    _rejected.remove(host.trim());
  }

  static void reset() {
    _issues.clear();
    _rejected.clear();
  }

  static void _note(String host, TendaIssue issue, String trace) => _issues[host] = (issue: issue, trace: trace, at: DateTime.now());

  static Future<({int status, HttpHeaders headers, String body})?> _send(
    String host,
    String method,
    String path, {
    String? cookie,
    String? form,
    String referer = '/index.html',
    Duration? timeout,
  }) async {
    final base = baseFor(host);
    final client = HttpClient()..connectionTimeout = _connect;
    try {
      final req = await client.openUrl(method, Uri.parse('$base$path')).timeout(_connect);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.refererHeader, '$base$referer');
      if (cookie != null && cookie.isNotEmpty) req.headers.set(HttpHeaders.cookieHeader, cookie);
      if (form != null) {
        final bytes = utf8.encode(form);
        req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
        // GoAhead لا يقرأ الجسم المقطَّع — طولٌ صريح
        req.contentLength = bytes.length;
        req.add(bytes);
      } else {
        req.headers.set('X-Requested-With', 'XMLHttpRequest');
      }
      final res = await req.close().timeout(timeout ?? _read);
      final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(timeout ?? _read);
      return (status: res.statusCode, headers: res.headers, body: utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// أهو Tenda؟ صفحة الدخول وحدها (بلا اعتماد): نموذج `/login/Auth` واسم Tenda.
  static Future<bool> detect(String host) async {
    final r = await _send(host.trim(), 'GET', '/login.html', referer: '/', timeout: const Duration(seconds: 5));
    if (r == null || r.status != 200) return false;
    return r.body.contains('/login/Auth') && r.body.toLowerCase().contains('tenda');
  }

  /// كوكي الجلسة من Set-Cookie (أسماءٌ وقيمها، بلا السمات).
  static String _cookieFrom(HttpHeaders h) {
    final out = <String>[];
    for (final c in h[HttpHeaders.setCookieHeader] ?? const <String>[]) {
      final kv = c.split(';').first.trim();
      if (kv.contains('=')) out.add(kv);
    }
    return out.join('; ');
  }

  /// دخولٌ واحد ⇒ كوكي الجلسة، وإلّا null والسبب في [lastIssue]. كلمة سرٍّ مرفوضة لا تُرسل ثانيةً.
  static Future<String?> _login(String h, String pass) async {
    final enc = base64.encode(utf8.encode(pass));
    if (_rejected[h]?.contains(enc) ?? false) {
      _note(h, TendaIssue.rejected, 'remembered');
      return null;
    }
    final r = await _send(h, 'POST', '/login/Auth', form: 'password=${Uri.encodeQueryComponent(enc)}', referer: '/login.html');
    if (r == null) {
      _note(h, TendaIssue.unreachable, 'login no-reply');
      return null;
    }
    final loc = r.headers.value(HttpHeaders.locationHeader) ?? '';
    if ((r.status == 302 || r.status == 301) && loc.contains('index.html')) {
      final cookie = _cookieFrom(r.headers);
      if (cookie.isEmpty) {
        _note(h, TendaIssue.readFailed, 'login without cookie');
        return null;
      }
      return cookie;
    }
    if (loc.contains('login.html?1')) {
      (_rejected[h] ??= <String>{}).add(enc);
      _note(h, TendaIssue.rejected, 'login rejected');
      return null;
    }
    if (loc.contains('login.html?2') || loc.contains('login.html?3')) {
      _note(h, TendaIssue.busy, 'admins full ${loc.split('?').last}');
      return null;
    }
    _note(h, TendaIssue.readFailed, 'login http ${r.status}');
    return null;
  }

  static Future<void> _logout(String h, String cookie) async {
    await _send(h, 'POST', '/goform/loginOut', cookie: cookie, form: 'action=loginout', timeout: const Duration(seconds: 4));
  }

  static String _r() => _rnd.nextDouble().toString();

  static Future<Map<String, dynamic>?> _json(String h, String path, String cookie) async {
    final r = await _send(h, 'GET', path, cookie: cookie);
    if (r == null || r.status != 200) return null;
    try {
      final j = jsonDecode(r.body);
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null; // صفحة دخولٍ بدل JSON = الجلسة سقطت
    }
  }

  /// قراءةٌ كاملة: دخول ⇒ الحالة والمتّصلون معاً ⇒ خروجٌ دائماً. null ⇒ السبب في [lastIssue].
  static Future<UbiquitiStatus?> readOnce(String host, String password) async {
    final h = host.trim();
    final cookie = await _login(h, password);
    if (cookie == null) return null;
    try {
      final got = await Future.wait([
        _json(h, '/goform/getStatus?${_r()}&modules=${Uri.encodeQueryComponent(statusModules)}', cookie),
        _json(h, '/goform/getQos?${_r()}&modules=${Uri.encodeQueryComponent(qosModules)}', cookie),
      ]);
      final st = got[0];
      if (st == null) {
        _note(h, TendaIssue.readFailed, 'status unreadable');
        return null;
      }
      final snap = TendaParse.status(status: st, qos: got[1], baseUrl: baseFor(h));
      if (snap == null) {
        _note(h, TendaIssue.readFailed, 'status without data');
        return null;
      }
      _issues.remove(h);
      return snap;
    } finally {
      await _logout(h, cookie);
    }
  }

  /// عيّنة النبضة الحيّة (دخول ⇒ الحالة ⇒ خروج): الترافيك جاهزٌ من الراوتر (لا فرق عدّادات). رفضٌ/شبكة ⇒ null.
  static Future<TendaLive?> sample(String host, String password) async {
    final h = host.trim();
    final cookie = await _login(h, password);
    if (cookie == null) return null;
    try {
      final st = await _json(h, '/goform/getStatus?${_r()}&modules=${Uri.encodeQueryComponent(statusModules)}', cookie);
      if (st == null) return null;
      final rate = TendaParse.rates(st);
      final dev = st['deviceStastics'] ?? st['deviceStatistics'];
      final sys = st['systemInfo'];
      return TendaLive(
        downBps: rate?.down,
        upBps: rate?.up,
        online: dev is Map ? TendaParse._int(dev['statusOnlineNumber']) : null,
        wanOnlineSeconds: sys is Map ? TendaParse._int(sys['wanConnectTime']) : null,
      );
    } finally {
      await _logout(h, cookie);
    }
  }

  static RouterFail _fail(String h) => switch (_issues[h]?.issue) {
        TendaIssue.rejected => RouterFail.rejected,
        TendaIssue.busy => RouterFail.busy,
        TendaIssue.unreachable => RouterFail.unreachable,
        _ => RouterFail.failed,
      };

  static Future<Map<String, dynamic>?> _wifiCfg(String h, String cookie) async {
    final j = await _json(h, '/goform/getWifi?random=${_r()}&modules=wifiBasicCfg', cookie);
    final w = j?['wifiBasicCfg'];
    return w is Map ? Map<String, dynamic>.from(w) : null;
  }

  /// شبكات الواي فاي بكلمات سرّها: دخول ⇒ وحدة wifiBasicCfg ⇒ خروج.
  static Future<RouterResult<List<RouterWifi>>> readWifi(String host, String password) async {
    final h = host.trim();
    final cookie = await _login(h, password);
    if (cookie == null) return RouterResult.fail(_fail(h), _issues[h]?.trace);
    try {
      final w = await _wifiCfg(h, cookie);
      return w == null ? const RouterResult.fail(RouterFail.failed, 'wifi read') : RouterResult.ok(TendaWifi.parse(w));
    } finally {
      await _logout(h, cookie);
    }
  }

  /// كلمة سرّ الواي فاي الجديدة بحفظ الصفحة نفسه (`goform/setWifi` بوحدة wifiBasicCfg وحقولها المقروءة)، ثمّ قراءةٌ تؤكّد.
  static Future<RouterResult<List<RouterWifi>>> setWifiPassword(String host, String password, String newPass) async {
    final h = host.trim();
    final cookie = await _login(h, password);
    if (cookie == null) return RouterResult.fail(_fail(h), _issues[h]?.trace);
    try {
      final w = await _wifiCfg(h, cookie);
      if (w == null) return const RouterResult.fail(RouterFail.failed, 'wifi read');
      final body = TendaWifi.submit(w, newPass);
      if (body == null) return const RouterResult.fail(RouterFail.noPsk);
      final r = await _send(h, 'POST', '/goform/setWifi', cookie: cookie, form: body, timeout: const Duration(seconds: 15));
      if (r != null) {
        final code = _errCode(r.body);
        if (code != null && code != 0 && code != 100) return RouterResult.fail(RouterFail.failed, 'setWifi $code');
      }
      // الحفظ يعيد تشغيل الواي فاي — مهلةٌ قصيرة ثمّ قراءةٌ تحسم (ردٌّ ضائع لا يُحكم عليه)
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final after = await _wifiCfg(h, cookie);
      if (after == null) return const RouterResult.fail(RouterFail.failed, 'verify read');
      final list = TendaWifi.parse(after);
      final saved = list.where((e) => e.password != null).every((e) => e.password == newPass);
      return saved ? RouterResult.ok(list) : const RouterResult.fail(RouterFail.failed, 'not saved');
    } finally {
      await _logout(h, cookie);
    }
  }

  static int? _errCode(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) return int.tryParse('${j['errCode']}');
    } catch (_) {}
    return null;
  }

  /// إعادة التشغيل بأمر زرّ الصفحة (`goform/sysReboot` «module1=sysOperate&action=reboot» ⇒ errCode 100).
  /// ⛔ جاره «action=restore» إعادة ضبط المصنع — لا يُرسل أبداً.
  static Future<RouterResult<RouterReboot>> reboot(String host, String password) async {
    final h = host.trim();
    final cookie = await _login(h, password);
    if (cookie == null) return RouterResult.fail(_fail(h), _issues[h]?.trace);
    final r = await _send(h, 'POST', '/goform/sysReboot', cookie: cookie, form: 'module1=sysOperate&action=reboot', timeout: const Duration(seconds: 10));
    if (r == null) return const RouterResult.ok(RouterReboot(confirmed: false));
    final code = _errCode(r.body);
    if (code == 100 || code == 0) return const RouterResult.ok(RouterReboot(confirmed: true));
    await _logout(h, cookie);
    return RouterResult.fail(RouterFail.failed, 'sysReboot $code');
  }
}
