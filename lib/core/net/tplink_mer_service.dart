import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/device_health.dart';
import 'tplink_agile_service.dart' show AgileCrypto;

/// راوتر TP-Link بواجهة «$.su» وبروتوكول MER (Archer C64 وأخواته — https على 8443 و«/» على 80 يحوّل إليه؛ قِيس من كود الجهاز
/// نفسه ١٢ نوفمبر عبر متصفّحٍ بلا واجهة، وقبل الدخول بطلباتٍ بلا اعتماد):
///
/// * كلّ طلب `POST /?code=<n>&asyn=<0|1>[&id=<الجلسة>]` بجسمٍ نصّيّ، والردّ أسطر CRLF أوّلها رمز الخطأ (`00000` نجاح).
/// * قبل الدخول (بلا اعتماد): `code=2&asyn=1` ⇒ «00007» ثمّ [حالة الدخول (4 طبيعيّ · 1 مقفل · 0 ممتلئ)، المحاولات الغلط، مفتاح، قاموس]؛
///   و`code=16&asyn=0` بجسم `get` ⇒ [ee، nn (RSA ‏512 بت)، seq].
/// * الدخول: `code=7&asyn=0&id=<encodeURIComponent(securityEncode(المفتاح، كلمة السرّ، القاموس))>` بلا جسم (لا تعمية) — والرمز نفسه هو
///   الجلسة (`id`) لكلّ طلبٍ بعده. الرفض ⇒ رمز خطأ ثمّ [3 كلمة سرٍّ غلط، المحاولات]؛ ١٠ ⇒ قفلٌ ساعتين.
/// * التعمية (GDPR): مفتاح AES وIV ستّة عشر رقماً لكلٍّ، يُسلَّمان `set <RSA(k=..&i=..)>` إلى code=16؛ ثمّ كلّ طلب
///   `sign=<RSA(k=..&i=..&s=<seq+طول المعمّى>) بقطع ٥٣>\r\ndata=<AES>` والردّ AES (base64).
/// * القراءة `code=2&asyn=0` بكتلٍ `<رقم>|<طبقات>` تفصلها «#»: الجهاز 0، الاتّصال 22، حالة WAN 23 (upTime، inRates/outRates)، إحصاءات
///   الوايرلس 113 (المتّصلون الآن)، إيجارات DHCP 9. ⛔ الكتلة 26 (PPPOE) فيها كلمة سرّ PPPoE — لا تُطلب أبداً.
/// * الخروج `code=11&asyn=0`.

enum MerIssue { rejected, busy, locked, unreachable, readFailed }

/// قارئاتٌ صرفة — رمز الدخول ونصّ الكتل.
class MerParse {
  MerParse._();

  /// `$.su.encrypt` في الجهاز (securityEncode القديم): لكلّ موضعٍ حتى الأطول (المفتاح أو كلمة السرّ) حرفٌ من القاموس بـ(أ ^ ب) % طوله،
  /// والناقص من الطرفين 187.
  static String securityEncode(String key, String pass, String dict) {
    final h = key.length;
    final a = pass.length;
    final p = dict.length;
    if (p == 0) return '';
    final c = a < h ? h : a;
    final b = StringBuffer();
    for (var y = 0; y < c; y++) {
      var i = 187;
      var s = 187;
      if (y >= h) {
        s = pass.codeUnitAt(y);
      } else if (y >= a) {
        i = key.codeUnitAt(y);
      } else {
        i = key.codeUnitAt(y);
        s = pass.codeUnitAt(y);
      }
      b.write(dict[(i ^ s) % p]);
    }
    return b.toString();
  }

  /// ردّ نصّيّ ⇒ (رمز الخطأ، الأسطر بعده). سطرٌ أوّل غير رقميّ ⇒ null.
  static ({int code, List<String> lines})? split(String body) {
    final all = body.split('\r\n');
    if (all.isEmpty) return null;
    final code = int.tryParse(all.first.trim());
    if (code == null) return null;
    final rest = all.sublist(1);
    while (rest.isNotEmpty && rest.last.isEmpty) {
      rest.removeLast();
    }
    return (code: code, lines: rest);
  }

  /// نصّ الكتل («id 23|1,0,0» ثمّ «اسم قيمة»، والقوائم «اسم[فهرس] قيمة» أو أسماءٌ تتكرّر) ⇒ {الكتلة: {الاسم: القيمة أو [قيم]}}.
  static Map<String, Map<String, Object>> blocks(String text) {
    final out = <String, Map<String, Object>>{};
    Map<String, Object>? cur;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trimRight();
      if (line.isEmpty || line.startsWith('#')) continue;
      final sp = line.indexOf(RegExp(r'[ \t]'));
      final name = sp < 0 ? line : line.substring(0, sp);
      final value = sp < 0 ? '' : line.substring(sp + 1).trim();
      if (name == 'id') {
        cur = out[value.split('|').first] = <String, Object>{};
        continue;
      }
      if (cur == null) continue;
      final m = RegExp(r'^([A-Za-z_]\w*)\[(\d+)\]$').firstMatch(name);
      final key = m != null ? m.group(1)! : name;
      final prev = cur[key];
      if (m != null || prev != null) {
        final list = prev is List<String> ? prev : <String>[if (prev is String) prev];
        list.add(value);
        cur[key] = list;
      } else {
        cur[key] = value;
      }
    }
    return out;
  }

  static String _s(Object? v) => v is String ? v : (v is List && v.isNotEmpty ? v.first.toString() : '');
  static List<String> _l(Object? v) => v is List<String> ? v : (v is String && v.isNotEmpty ? [v] : const []);
  static int? _i(Object? v) => int.tryParse(_s(v).trim());

  /// نوع الاتّصال من الكتلة 22 (linkType) أو رمز الحالة.
  static String wanTypeName(String t) => switch (t.toLowerCase()) {
        'pppoe' || '2' => 'PPPoE',
        'dhcp' || 'dynamic' || '0' => 'Dynamic IP',
        'static' || '1' => 'Static IP',
        _ => t,
      };

  /// الكتل ⇒ لقطة الراوتر. null حين لا تحمل كتلة الجهاز ولا حالة WAN شيئاً.
  static UbiquitiStatus? status(Map<String, Map<String, Object>> b, {required String baseUrl}) {
    final dev = b['0'] ?? const {};
    final link = b['22'] ?? const {};
    final st = b['23'] ?? const {};
    if (dev.isEmpty && st.isEmpty) return null;
    final wl = b['113'] ?? const {};
    final dh = b['9'] ?? const {};
    // إيجارات DHCP بالماك ⇒ اسمٌ وآيبي
    final leaseMacs = _l(dh['mac']);
    final leaseNames = _l(dh['hostName']);
    final leaseIps = _l(dh['ip']);
    final lease = <String, ({String? name, String? ip})>{};
    for (var i = 0; i < leaseMacs.length; i++) {
      final n = i < leaseNames.length ? leaseNames[i] : '';
      final ip = i < leaseIps.length ? leaseIps[i] : '';
      lease[leaseMacs[i].toUpperCase()] = (name: n.isEmpty || n == '--' ? null : n, ip: ip.isEmpty ? null : ip);
    }
    final macs = _l(wl['mac']);
    final names = _l(wl['name']);
    final clients = <RouterClient>[];
    for (var i = 0; i < macs.length; i++) {
      final mac = macs[i].toUpperCase();
      if (mac.isEmpty) continue;
      final l = lease[mac];
      final n = i < names.length && names[i].isNotEmpty && names[i] != '--' ? names[i] : l?.name;
      clients.add(RouterClient(mac: mac, ip: l?.ip, name: n, wired: false));
    }
    final model = _s(dev['modelName']);
    final ver = _s(dev['hardVer']);
    return UbiquitiStatus(
      hostname: '',
      firmware: _s(dev['softVer']),
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
      peerCount: wl.isEmpty ? null : clients.length,
      baseUrl: baseUrl,
      vendor: 'tpmer',
      model: model.isEmpty ? '' : (ver.isNotEmpty && !model.contains(ver) ? '$model ${ver.split(' ').last}' : model),
      wanOnlineSeconds: _i(st['upTime']),
      dhcpCount: dh.isEmpty ? null : leaseMacs.length,
      wanType: wanTypeName(_s(link['linkType'])),
      clients: clients,
    );
  }

  /// الترافيك الحيّ من الكتلة 23 (inRates/outRates بالبايت/ثانية) ⇒ (تنزيل، رفع) بت/ثانية، وإلّا null.
  static ({int down, int up})? rates(Map<String, Map<String, Object>> b) {
    final st = b['23'];
    if (st == null) return null;
    final down = _i(st['inRates']);
    final up = _i(st['outRates']);
    if (down == null || up == null) return null;
    return (down: down * 8, up: up * 8);
  }
}

/// جلسة MER مفتوحة: الرمز ومفاتيح التعمية.
class MerSession {
  MerSession({required this.base, required this.id, required this.aesKey, required this.aesIv, required this.nn, required this.ee, required this.seq, required this.client});
  final HttpClient client;
  final String base;
  final String id;
  final String aesKey;
  final String aesIv;
  final String nn;
  final String ee;
  final int seq;
  String get keyString => 'k=$aesKey&i=$aesIv';
}

class TplinkMerService {
  TplinkMerService._();

  static const _connect = Duration(seconds: 5);
  static const _read = Duration(seconds: 12);
  static const readBlocks = '0|1,0,0#22|1,0,0#23|1,0,0#113|1,0,0#9|1,0,0';

  /// أصل الواجهة لكلّ عنوان (https://ip:8443 حين يحوّل «/» إليه، وإلّا http://ip) — من التعرّف.
  static final _bases = <String, String>{};
  static final _issues = <String, ({MerIssue issue, String trace, DateTime at})>{};
  static final _rejected = <String, Set<String>>{};

  @visibleForTesting
  static String? Function(String host)? baseOverride;

  static ({MerIssue issue, String trace})? lastIssue(String host) {
    final i = _issues[host.trim()];
    return i == null ? null : (issue: i.issue, trace: i.trace);
  }

  static void forget(String host) {
    _issues.remove(host.trim());
    _rejected.remove(host.trim());
  }

  static void reset() {
    _issues.clear();
    _rejected.clear();
    _bases.clear();
  }

  static void _note(String host, MerIssue issue, String trace) => _issues[host] = (issue: issue, trace: trace, at: DateTime.now());

  static HttpClient _client() => HttpClient()
    ..connectionTimeout = _connect
    ..idleTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (_, __, ___) => true;

  /// [client] = عميل الجلسة (اتّصالٌ محفوظ يُعاد استعماله كالمتصفّح — جهاز CGI من العائلة نفسها يربط الجلسة المعمّاة بالاتّصال)؛ بلا عميل ⇒ طلبٌ مستقلّ.
  static Future<({int status, HttpHeaders headers, String body})?> _http(String url, {String method = 'GET', String? body, String? referer, HttpClient? client}) async {
    final own = client == null;
    final c = client ?? _client();
    try {
      final req = await c.openUrl(method, Uri.parse(url)).timeout(_connect);
      req.followRedirects = false;
      final u = Uri.parse(url);
      req.headers.set(HttpHeaders.refererHeader, referer ?? '${u.scheme}://${u.authority}/');
      if (body != null) {
        final bytes = utf8.encode(body);
        req.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
        req.contentLength = bytes.length;
        req.add(bytes);
      } else if (method == 'POST') {
        req.contentLength = 0;
      }
      final res = await req.close().timeout(_read);
      final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(_read);
      return (status: res.statusCode, headers: res.headers, body: utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return null;
    } finally {
      if (own) c.close(force: true);
    }
  }

  /// أهو MER؟ «/» على 80: تحويلٌ إلى https:<منفذ> أو صفحةٌ فيها `tpEncrypt.new.js` و`js/su/` — ثمّ صفحة الأصل نفسها تؤكّد.
  static Future<bool> detect(String host) async {
    final h = host.trim();
    final over = baseOverride?.call(h);
    final candidates = <String>[];
    if (over != null) {
      candidates.add(over);
    } else {
      final r = await _http('http://$h/');
      if (r == null) return false;
      final loc = r.headers.value(HttpHeaders.locationHeader) ?? '';
      if ((r.status == 301 || r.status == 302 || r.status == 307) && loc.startsWith('https://')) {
        candidates.add(loc.replaceAll(RegExp(r'/+$'), ''));
      } else if (r.status == 200 && _isMerPage(r.body)) {
        _bases[h] = 'http://$h';
        return true;
      } else {
        return false;
      }
    }
    for (final base in candidates) {
      final p = await _http('$base/');
      if (p != null && p.status == 200 && _isMerPage(p.body)) {
        _bases[h] = base;
        return true;
      }
    }
    return false;
  }

  static bool _isMerPage(String body) => body.contains('tpEncrypt.new.js') && body.contains('js/su/');

  static String _baseOf(String h) => baseOverride?.call(h) ?? _bases[h] ?? 'https://$h:8443';

  /// الحالة في الجسم لا في HTTP (حيّاً: معطيات الدخول قبله تأتي **401** وجسمها «00007…» بالمفتاح والقاموس) ⇒ يُقرأ الجسم أيّاً كانت الحالة.
  static Future<({int code, List<String> lines})?> _post(String base, String query, {String? body, HttpClient? client}) async {
    final r = await _http('$base/?$query', method: 'POST', body: body, client: client);
    if (r == null) return null;
    return MerParse.split(r.body);
  }

  /// دخولٌ واحد ⇒ جلسة، وإلّا null والسبب في [lastIssue]. حالة الدخول تُقرأ أوّلاً بلا اعتماد: مقفل/ممتلئ ⇒ لا إرسال، والمحاولات الغلط
  /// ٥ فأكثر ⇒ لا إرسال تلقائيّاً (العدّاد لكلّ العملاء — ١٠ تقفل ساعتين). كلمة سرٍّ مرفوضة لا تُرسل ثانيةً.
  static Future<MerSession?> _login(String h, String pass) async {
    final client = _client();
    final s = await _loginWith(h, pass, client);
    if (s == null) client.close(force: true);
    return s;
  }

  static Future<MerSession?> _loginWith(String h, String pass, HttpClient client) async {
    final base = _baseOf(h);
    final pre = await _post(base, 'code=2&asyn=1', client: client);
    if (pre == null) {
      _note(h, MerIssue.unreachable, 'login-params no-reply');
      return null;
    }
    if (pre.lines.length < 4) {
      _note(h, MerIssue.readFailed, 'login-params ${pre.code} short');
      return null;
    }
    final state = int.tryParse(pre.lines[0]) ?? -1;
    final fails = int.tryParse(pre.lines[1]) ?? 0;
    if (state == 1) {
      _note(h, MerIssue.locked, 'locked (ten wrong tries — two hours)');
      return null;
    }
    if (state == 0) {
      _note(h, MerIssue.busy, 'sessions full');
      return null;
    }
    if (fails >= 5) {
      _note(h, MerIssue.locked, 'too many failed tries ($fails) — not sending');
      return null;
    }
    final key = pre.lines[2];
    final dict = pre.lines[3];
    final token = MerParse.securityEncode(key, pass, dict);
    final remembered = '${pass.hashCode}';
    if (_rejected[h]?.contains(remembered) ?? false) {
      _note(h, MerIssue.rejected, 'remembered');
      return null;
    }
    final gp = await _post(base, 'code=16&asyn=0', body: 'get', client: client);
    if (gp == null || gp.code != 0 || gp.lines.length < 3) {
      _note(h, gp == null ? MerIssue.unreachable : MerIssue.readFailed, 'gdpr params');
      return null;
    }
    final ee = gp.lines[0];
    final nn = gp.lines[1];
    final seq = int.tryParse(gp.lines[2]);
    if (seq == null) {
      _note(h, MerIssue.readFailed, 'gdpr seq');
      return null;
    }
    final id = Uri.encodeComponent(token);
    final auth = await _post(base, 'code=7&asyn=0&id=$id', client: client);
    if (auth == null) {
      _note(h, MerIssue.unreachable, 'auth no-reply');
      return null;
    }
    if (auth.code != 0) {
      final st = auth.lines.isNotEmpty ? int.tryParse(auth.lines[0]) : null;
      if (st == 3 || st == 5 || st == 6) {
        (_rejected[h] ??= <String>{}).add(remembered);
        _note(h, MerIssue.rejected, 'auth rejected ${auth.code}/$st');
      } else if (st == 1) {
        _note(h, MerIssue.locked, 'auth locked');
      } else if (st == 0) {
        _note(h, MerIssue.busy, 'auth full');
      } else {
        _note(h, MerIssue.readFailed, 'auth ${auth.code}/$st');
      }
      return null;
    }
    final s = MerSession(base: base, id: id, aesKey: AgileCrypto.digits(16), aesIv: AgileCrypto.digits(16), nn: nn, ee: ee, seq: seq, client: client);
    final set = await _post(base, 'code=16&asyn=0&id=$id', body: 'set ${AgileCrypto.rsaEncrypt(s.keyString, nn, ee)}', client: client);
    if (set == null || set.code != 0) {
      _note(h, MerIssue.readFailed, 'gdpr set ${set?.code}');
      await _logout(s);
      return null;
    }
    return s;
  }

  /// طلبٌ معمّى بالجلسة ⇒ النصّ المفكوك (أوّله رمز الخطأ)، وإلّا null.
  static Future<String?> _secure(MerSession s, String query, String plain) async {
    final data = AgileCrypto.aesEncrypt(plain, s.aesKey, s.aesIv);
    final sigPlain = '${s.keyString}&s=${s.seq + data.length}';
    final sign = StringBuffer();
    for (var i = 0; i < sigPlain.length; i += 53) {
      sign.write(AgileCrypto.rsaEncrypt(sigPlain.substring(i, i + 53 > sigPlain.length ? sigPlain.length : i + 53), s.nn, s.ee));
    }
    final r = await _http('${s.base}/?$query&id=${s.id}', method: 'POST', body: 'sign=$sign\r\ndata=$data', client: s.client);
    if (r == null) return null;
    final body = r.body.trim();
    try {
      return AgileCrypto.aesDecrypt(body, s.aesKey, s.aesIv);
    } catch (_) {
      return body; // ردٌّ غير معمّى (رمز خطأ صريح)
    }
  }

  static Future<void> _logout(MerSession s) async {
    try {
      await _secure(s, 'code=11&asyn=0', '');
    } catch (_) {
      // أفضل جهد — الجلسة تنتهي عند الجهاز وحدها
    } finally {
      s.client.close(force: true);
    }
  }

  /// للأدوات الحيّة: النصّ المفكوك لكتلٍ بعينها (بلا طباعةٍ لشيءٍ حسّاس — المنادي يختار الكتل).
  @visibleForTesting
  static Future<String?> debugRead(String host, String pass, String blocksQuery) async {
    final h = host.trim();
    final s = await _login(h, pass);
    if (s == null) return null;
    try {
      return await _secure(s, 'code=2&asyn=0', blocksQuery);
    } finally {
      await _logout(s);
    }
  }

  /// قراءةٌ كاملة: دخول ⇒ الكتل ⇒ خروج. null ⇒ السبب في [lastIssue].
  static Future<UbiquitiStatus?> readOnce(String host, String password) async {
    final h = host.trim();
    final s = await _login(h, password);
    if (s == null) return null;
    try {
      final text = await _secure(s, 'code=2&asyn=0', readBlocks);
      final sp = text == null ? null : MerParse.split(text);
      if (sp == null || sp.code != 0) {
        _note(h, MerIssue.readFailed, 'read ${sp?.code}');
        return null;
      }
      final snap = MerParse.status(MerParse.blocks(sp.lines.join('\r\n')), baseUrl: s.base);
      if (snap == null) {
        _note(h, MerIssue.readFailed, 'read without data');
        return null;
      }
      _issues.remove(h);
      return snap;
    } finally {
      await _logout(s);
    }
  }

  /// عيّنة النبضة الحيّة: دخول ⇒ حالة WAN والوايرلس ⇒ خروج.
  static Future<({int? down, int? up, int? clients, int? wanOnlineSeconds})?> sample(String host, String password) async {
    final h = host.trim();
    final s = await _login(h, password);
    if (s == null) return null;
    try {
      final text = await _secure(s, 'code=2&asyn=0', '23|1,0,0#113|1,0,0');
      final sp = text == null ? null : MerParse.split(text);
      if (sp == null || sp.code != 0) return null;
      final b = MerParse.blocks(sp.lines.join('\r\n'));
      final r = MerParse.rates(b);
      final wl = b['113'];
      return (
        down: r?.down,
        up: r?.up,
        clients: wl == null ? null : MerParse._l(wl['mac']).length,
        wanOnlineSeconds: MerParse._i(b['23']?['upTime']),
      );
    } finally {
      await _logout(s);
    }
  }
}
