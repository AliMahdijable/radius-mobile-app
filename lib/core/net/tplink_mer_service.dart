import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/device_health.dart';
import 'router_types.dart';
import 'tplink_agile_service.dart' show AgileCrypto;

/// راوتر TP-Link بواجهة «$.su» وبروتوكول MER (Archer C64 وأخواته — https على 8443 و«/» على 80 يحوّل إليه؛ قِيس من كود الجهاز
/// نفسه ١٢ نوفمبر عبر متصفّحٍ بلا واجهة، وقبل الدخول بطلباتٍ بلا اعتماد):
///
/// * كلّ طلب `POST /?code=<n>&asyn=<0|1>[&id=<الجلسة>]` بجسمٍ نصّيّ، والردّ أسطر CRLF أوّلها رمز الخطأ (`00000` نجاح).
/// * قبل الدخول (بلا اعتماد): `code=2&asyn=1` ⇒ «00007» ثمّ [حالة الدخول (4 طبيعيّ · 1 مقفل · 0 ممتلئ)، المحاولات الغلط، مفتاح، قاموس]؛
///   و`code=16&asyn=0` بجسم `get` ⇒ [ee، nn (RSA ‏512 بت)، seq].
/// * الدخول: `code=7&asyn=0&id=<encodeURIComponent(loginToken)>` بلا جسم (لا تعمية) — والرمز نفسه هو الجلسة (`id`) لكلّ طلبٍ بعده.
///   [MerParse.loginToken] = `$.su.encrypt(المفتاح، $.su.encrypt(كلمة السرّ)، القاموس)`: حقل كلمة السرّ في الصفحة يمرّ بـ`doEncrypt()`
///   (المفتاح والقاموس الافتراضيّان) قبل طبقة الجلسة — فاتتنا أوّلاً فرُفضت كلمة سرٍّ صحيحة (رمز 3) على C64 وC80 (١٢ نوفمبر، والمالك
///   داخلٌ بها من الصفحة). الرفض ⇒ رمز خطأ ثمّ [3 كلمة سرٍّ غلط، المحاولات]؛ ١٠ ⇒ قفلٌ ساعتين، والدخول الناجح يصفّر العدّاد.
/// * التعمية (GDPR): مفتاح AES وIV ستّة عشر رقماً لكلٍّ، يُسلَّمان `set <RSA(k=..&i=..)>` إلى code=16؛ ثمّ كلّ طلب
///   `sign=<RSA(k=..&i=..&s=<seq+طول المعمّى>) بقطع ٥٣>\r\ndata=<AES>` والردّ AES (base64).
/// * القراءة `code=2&asyn=1` (كما تقرأ الصفحة — `urlAsyn: 1`) بكتلٍ `<رقم>|<طبقات>` تفصلها «#»: الجهاز 0، الاتّصال 22، حالة WAN 23
///   (upTime، inRates/outRates)، إحصاءات الوايرلس 113 (المتّصلون الآن)، إيجارات DHCP 9، الواي فاي 33 (`|1,1,0` 2.4G · `|2,1,0` 5G:
///   cSsid · cPskSecret · SecurityType). ⛔ الكتلة 26 (PPPOE) فيها كلمة سرّ PPPoE — لا تُطلب أبداً.
/// * الكتابة `code=1&asyn=0` بنصّ «id <كتلة>|<طبقات>» ثمّ «اسم قيمة(encodeURIComponent)» — تغيير كلمة سرّ الواي فاي.
/// * إعادة التشغيل `code=6&asyn=1` (زرّ الصفحة نفسه). ⛔ `code=5` إعادة ضبط المصنع — لا تُرسل أبداً.
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

  /// مفتاح `$.su.encrypt` وقاموسه حين يُنادى بلا وسيطين (tpEncrypt.new.js في الجهاز).
  static const defaultKey = 'RDpbLfCPsJZ7fiv';
  static const defaultDict =
      'yLwVl0zKqws7LgKPRQ84Mdt708T1qQ3Ha7xv3H7NyU84p21BriUWBU43odz3iP4rBL3cD02KZciXTysVXiV8ngg6vL48rPJyAUw0HurW20xqxv9aYb4M9wK1Ae0wlro510qXeU07kV57fQMc8L6aLgMLwygtc0F10a0Dg70TOoouyFhdysuRMO51yY5ZlOZZLEal1h0t9YQW0Ko7oBwmCAHoic4HYbUyVeU3sfQ1xtXcPcf1aT303wAQhv66qzW';

  /// رمز الدخول كما تبنيه صفحة الجهاز (`doLogin`: `password.doEncrypt()` ثمّ `localLoginProxy.auth`).
  static String loginToken(String key, String dict, String pass) =>
      securityEncode(key, securityEncode(pass, defaultKey, defaultDict), dict);

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

  /// `decodeURI` كما تطبّقه الصفحة على كلّ قيمة (محلّل MERProxy): %XX يُفكّ إلّا ما يكون حرفاً محجوزاً (; / ? : @ & = + $ , #)،
  /// وتسلسلٌ معطوب يبقى كما هو.
  static String decodeUri(String v) {
    if (!v.contains('%')) return v;
    final bytes = <int>[];
    final out = StringBuffer();
    void flush() {
      if (bytes.isEmpty) return;
      out.write(utf8.decode(bytes, allowMalformed: true));
      bytes.clear();
    }

    var i = 0;
    while (i < v.length) {
      final c = v[i];
      if (c == '%' && i + 2 < v.length) {
        final h = int.tryParse(v.substring(i + 1, i + 3), radix: 16);
        if (h != null) {
          if (h < 0x80 && ';/?:@&=+\$,#'.contains(String.fromCharCode(h))) {
            flush();
            out.write(v.substring(i, i + 3));
          } else {
            bytes.add(h);
          }
          i += 3;
          continue;
        }
      }
      flush();
      out.write(c);
      i++;
    }
    flush();
    return out.toString();
  }

  /// نصّ الكتل ⇒ {«رقم|طبقات»: {الاسم: القيمة أو [قيم بفهارسها]}} — كمحلّل الصفحة: «id 13|1,0,0» يفتح كتلة، و«اسم قيمة» حقل، والقوائم
  /// «اسم فهرس قيمة» (قِيس حيّاً على C64: `ip 0 192.168.0.100`، والقيمة الفارغة «اسم فهرس» وحده). الاسم مفهرسٌ حين يتكرّر أو
  /// يأتي بفهرسٍ وقيمة — الصفحة تعرفه من مخطّط الكتلة، ونحن من شكله. يُقبل أيضاً «اسم[فهرس] قيمة».
  static Map<String, Map<String, Object>> blocks(String text) {
    final groups = <String, List<String>>{};
    String? cur;
    for (final raw in text.split('\n')) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final sp = line.indexOf(' ');
      final name = sp < 0 ? line.trim() : line.substring(0, sp);
      if (name == 'id') {
        cur = (sp < 0 ? '' : line.substring(sp + 1)).trim();
        groups.putIfAbsent(cur, () => <String>[]);
        continue;
      }
      if (cur == null) continue;
      groups[cur]!.add(line);
    }
    final out = <String, Map<String, Object>>{};
    final bracket = RegExp(r'^([A-Za-z_]\w*)\[(\d+)\]$');
    final digits = RegExp(r'^\d+$');
    for (final g in groups.entries) {
      final seen = <String, int>{};
      final indexed = <String>{};
      for (final l in g.value) {
        final parts = l.split(' ');
        final b = bracket.firstMatch(parts.first);
        final name = b?.group(1) ?? parts.first;
        seen[name] = (seen[name] ?? 0) + 1;
        if (b != null || (parts.length >= 3 && digits.hasMatch(parts[1]))) indexed.add(name);
      }
      final m = <String, Object>{};
      for (final l in g.value) {
        final sp = l.indexOf(' ');
        final head = sp < 0 ? l : l.substring(0, sp);
        var rest = sp < 0 ? '' : l.substring(sp + 1);
        final b = bracket.firstMatch(head);
        final name = b?.group(1) ?? head;
        if (b == null && !indexed.contains(name) && (seen[name] ?? 0) <= 1) {
          m[name] = decodeUri(rest.trim());
          continue;
        }
        int? idx;
        if (b != null) {
          idx = int.parse(b.group(2)!);
        } else {
          final sp2 = rest.indexOf(' ');
          final first = sp2 < 0 ? rest : rest.substring(0, sp2);
          if (digits.hasMatch(first)) {
            idx = int.parse(first);
            rest = sp2 < 0 ? '' : rest.substring(sp2 + 1);
          }
        }
        final list = (m[name] as List<String>?) ?? <String>[];
        if (idx == null) {
          list.add(decodeUri(rest.trim()));
        } else {
          while (list.length <= idx) {
            list.add('');
          }
          list[idx] = decodeUri(rest.trim());
        }
        m[name] = list;
      }
      out[g.key] = m;
    }
    return out;
  }

  /// كتلة برقمها: «رقم|طبقات» بعينها أو أوّل ما يبدأ بالرقم.
  static Map<String, Object> block(Map<String, Map<String, Object>> b, String id) =>
      b[id] ?? b.entries.where((e) => e.key == id || e.key.startsWith('$id|')).map((e) => e.value).firstOrNull ?? const {};

  static String _s(Object? v) => v is String ? v : (v is List && v.isNotEmpty ? v.first.toString() : '');
  static List<String> _l(Object? v) => v is List<String> ? v : (v is String && v.isNotEmpty ? [v] : const []);
  static int? _i(Object? v) => int.tryParse(_s(v).trim());
  static String _at(List<String> l, int i) => i < l.length ? l[i] : '';

  /// مدّة الاتّصال بالثواني من upTime (الكتلة 23). قِيس على C64 (١٢ نوفمبر): العدّاد يزيد ~٦٠ كلّ ثانية وكلّ قيمه مضاعفات ٦٠، وقسمته
  /// على ٦٠ تطابق مدّة الجلسة في الساس (80.5 ساعة مقابل 80) ⇒ ÷٦٠. [plain] = جهازٌ رُئي يعدّ بالثواني (قيمةٌ ليست مضاعف ٦٠) ⇒ كما هي.
  static int? upSeconds(Object? raw, {bool plain = false}) {
    final v = int.tryParse(_s(raw).trim());
    if (v == null) return null;
    if (plain || v % 60 != 0) return v;
    return v ~/ 60;
  }

  /// نوع الاتّصال من الكتلة 22 (linkType) أو رمز الحالة.
  static String wanTypeName(String t) => switch (t.toLowerCase()) {
        'pppoe' || '2' => 'PPPoE',
        'dhcp' || 'dynamic' || '0' => 'Dynamic IP',
        'static' || '1' => 'Static IP',
        _ => t,
      };

  /// جدول المحطّات (الكتلة 13 — قائمة «الأجهزة» في الصفحة): حتى أوّل خانةٍ بلا ماك (الجدول ثابت الطول ~٧٠KB أغلبه فارغ)، بلا
  /// المحجوبين، و«online» = متّصلٌ الآن. type 0 = سلكيّ. null حين لا جدول.
  static List<RouterClient>? stations(Map<String, Object> st) {
    final macs = _l(st['mac']);
    if (st.isEmpty) return null;
    final ips = _l(st['ip']);
    final names = _l(st['name']);
    final types = _l(st['type']);
    final online = _l(st['online']);
    final blocked = _l(st['blocked']);
    final out = <RouterClient>[];
    for (var i = 0; i < macs.length; i++) {
      final mac = macs[i].trim().toUpperCase();
      if (mac.isEmpty || mac == '00-00-00-00-00-00') break;
      if (_at(blocked, i) == '1' || _at(online, i) != '1') continue;
      final n = _at(names, i).trim();
      final ip = _at(ips, i).trim();
      out.add(RouterClient(mac: mac, ip: ip.isEmpty || ip == '0.0.0.0' ? null : ip, name: n.isEmpty || n == '--' ? null : n, wired: _at(types, i) == '0'));
    }
    return out;
  }

  /// الكتل ⇒ لقطة الراوتر. null حين لا تحمل كتلة الجهاز ولا حالة WAN شيئاً.
  static UbiquitiStatus? status(Map<String, Map<String, Object>> b, {required String baseUrl, bool plainUptime = false}) {
    final dev = block(b, '0');
    final link = block(b, '22');
    final st = block(b, '23');
    if (dev.isEmpty && st.isEmpty) return null;
    final clients = stations(block(b, '13'));
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
      peerCount: clients?.length,
      baseUrl: baseUrl,
      vendor: 'tpmer',
      model: model.isEmpty ? '' : (ver.isNotEmpty && !model.contains(ver) ? '$model ${ver.split(' ').last}' : model),
      wanOnlineSeconds: upSeconds(st['upTime'], plain: plainUptime),
      dhcpCount: null,
      wanType: wanTypeName(_s(link['linkType'])),
      clients: clients ?? const [],
    );
  }

  /// عدّادات WAN التراكميّة (الكتلة 23: inOctets/outOctets بايت) — المعدّل فرق عيّنتين، كالكلاسيكيّ.
  static ({int rx, int tx})? counters(Map<String, Map<String, Object>> b) {
    final st = block(b, '23');
    final rx = int.tryParse(_s(st['inOctets']).trim());
    final tx = int.tryParse(_s(st['outOctets']).trim());
    if (rx == null || tx == null) return null;
    return (rx: rx, tx: tx);
  }

  /// شبكات الواي فاي الرئيسيّة (الكتلة 33: «1,1,0» = 2.4G · «2,1,0» = 5G). كلمة السرّ لأنماط PSK وحدها (SecurityType 2–5)، والمفتوحة
  /// (1) بلا كلمة، وEnterprise (6–7) بلا كلمةٍ تُعرض (سرّ RADIUS ليس كلمة الواي فاي). SecurityType غائب ⇒ bSecurityEnable/uAuthType
  /// (خريطة الشبكة في الصفحة: 3 PSK/PSK2 · 5 PSK2/SAE ⇒ cPskSecret).
  static List<RouterWifi> wifi(Map<String, Map<String, Object>> b) {
    final out = <RouterWifi>[];
    for (final (layers, band) in const [('1,1,0', '2.4G'), ('2,1,0', '5G')]) {
      final w = b['33|$layers'];
      if (w == null || w.isEmpty) continue;
      final sec = _i(w['SecurityType']);
      final auth = _s(w['bSecurityEnable']) == '0' ? 0 : _i(w['uAuthType']);
      final psk = sec != null ? (sec >= 2 && sec <= 5) : (auth == 3 || auth == 5);
      final open = sec != null ? sec == 1 : auth == 0;
      final label = switch (sec) {
        1 => 'مفتوحة',
        2 => 'WPA2',
        3 => 'WPA/WPA2',
        4 => 'WPA3',
        5 => 'WPA2/WPA3',
        6 || 7 => 'Enterprise',
        _ => open ? 'مفتوحة' : (psk ? 'WPA2' : ''),
      };
      out.add(RouterWifi(
        band: band,
        ssid: _s(w['cSsid']),
        password: psk ? _s(w['cPskSecret']) : null,
        enabled: _s(w['bEnable']) == '1',
        security: label,
        ref: layers,
      ));
    }
    return out;
  }

  /// نصّ الكتابة: كلمة السرّ الجديدة لشبكات [refs] («id 33|طبقات» ثمّ «cPskSecret قيمة» مرمّزةً كـ`toText` في الصفحة).
  static String wifiPasswordWrite(List<String> refs, String newPass) {
    final b = StringBuffer();
    for (final r in refs) {
      b.write('id 33|$r\r\ncPskSecret ${Uri.encodeComponent(newPass)}\r\n');
    }
    return b.toString();
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
  /// الكتل في الفحص: الجهاز 0، الاتّصال 22، حالة WAN 23، جدول المحطّات 13 (المتّصلون). ⚠️ 113 (إحصاءات الوايرلس) **ممنوعةٌ** على C64
  /// (EFORBID 6 — وكتلةٌ ممنوعة تُفشل الطلب كلّه، قِيس ١٢ نوفمبر)، و9 (إيجارات DHCP ~٢٥KB) لا تلزم.
  static const readBlocks = '0|1,0,0#22|1,0,0#23|1,0,0#13|1,0,0';

  /// كلّ كم نبضة يُقرأ جدول المحطّات (~٧٠KB) في الجلسة الحيّة — النبضة الأخرى حالة WAN وحدها (~٤٠٠ بايت).
  static const liveClientsEvery = 5;

  /// أصل الواجهة لكلّ عنوان (https://ip:8443 حين يحوّل «/» إليه، وإلّا http://ip) — من التعرّف.
  static final _bases = <String, String>{};
  static final _issues = <String, ({MerIssue issue, String trace, DateTime at})>{};
  static final _rejected = <String, Set<String>>{};

  /// أجهزةٌ رُئي upTime عندها ليس مضاعف ٦٠ ⇒ تعدّ بالثواني (انظر [MerParse.upSeconds]).
  static final _plainUptime = <String>{};

  static bool _plain(String h, Object? raw) {
    final v = int.tryParse('${raw is List ? (raw.isEmpty ? '' : raw.first) : (raw ?? '')}'.trim());
    if (v != null && v % 60 != 0) _plainUptime.add(h);
    return _plainUptime.contains(h);
  }

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
      // عنوانٌ بمنفذ (راوترٌ خلف النانو ببورت فورورد — «الجهاز الثاني»): المنفذ المحوَّل قد يكون منفذ https الراوتر نفسه.
      final explicitPort = RegExp(r':\d{1,5}$').hasMatch(h);
      final r = await _http('http://$h/');
      if (r == null) {
        if (!explicitPort) return false;
        candidates.add('https://$h');
      } else {
        final loc = r.headers.value(HttpHeaders.locationHeader) ?? '';
        if ((r.status == 301 || r.status == 302 || r.status == 307) && loc.startsWith('https://')) {
          candidates.add(loc.replaceAll(RegExp(r'/+$'), ''));
          if (explicitPort) candidates.add('https://$h');
        } else if (r.status == 200 && _isMerPage(r.body)) {
          _bases[h] = 'http://$h';
          return true;
        } else {
          return false;
        }
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
    final token = MerParse.loginToken(key, dict, pass);
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

  /// للأدوات الحيّة: دخولٌ واحد ثمّ طلباتٌ معمّاة [queries] (كلٌّ «استعلام URL» ⇒ جسم) — يُرجع لكلٍّ الحالة ورمز الخطأ ومفكوكٌ أم لا
  /// وأسماء الحقول وحدها (لا قيم: قد تحمل كلمة سرّ الواي فاي).
  @visibleForTesting
  static Future<List<String>> debugTrace(String host, String pass, List<(String, String)> queries) async {
    final h = host.trim();
    final out = <String>[];
    final s = await _login(h, pass);
    out.add('login ${s == null ? 'FAIL ${lastIssue(h)}' : 'ok'}');
    if (s == null) return out;
    try {
      for (final (q, body) in queries) {
        final data = AgileCrypto.aesEncrypt(body, s.aesKey, s.aesIv);
        final sigPlain = '${s.keyString}&s=${s.seq + data.length}';
        final sign = StringBuffer();
        for (var i = 0; i < sigPlain.length; i += 53) {
          sign.write(AgileCrypto.rsaEncrypt(sigPlain.substring(i, i + 53 > sigPlain.length ? sigPlain.length : i + 53), s.nn, s.ee));
        }
        final r = await _http('${s.base}/?$q&id=${s.id}', method: 'POST', body: 'sign=$sign\r\ndata=$data', client: s.client);
        if (r == null) {
          out.add('$q [$body] no-reply');
          continue;
        }
        var dec = false;
        var text = r.body.trim();
        try {
          text = AgileCrypto.aesDecrypt(text, s.aesKey, s.aesIv);
          dec = true;
        } catch (_) {}
        final sp = MerParse.split(text);
        final names = MerParse.blocks(sp?.lines.join('\r\n') ?? '').map((k, v) => MapEntry(k, v.keys.take(12).join(',')));
        out.add('$q [$body] http=${r.status} dec=$dec code=${sp?.code} len=${text.length} fields=$names');
        // شكل الأسطر بلا قيم: الاسم، وهل الرمز الثاني فهرسٌ رقميّ، وطول الباقي (أوّل ١٤ سطراً).
        for (final l in (sp?.lines ?? const <String>[]).take(14)) {
          final parts = l.split(' ');
          final idx = parts.length > 2 && RegExp(r'^\d+$').hasMatch(parts[1]) ? parts[1] : '-';
          final rest = parts.length > 1 ? parts.sublist(idx == '-' ? 1 : 2).join(' ') : '';
          final shown = parts.first == 'id' || RegExp(r'^(online|blocked|type|SecurityType|bEnable|bSecurityEnable|uAuthType|status|linkType)$').hasMatch(parts.first)
              ? rest
              : 'len${rest.length}';
          out.add('   ${parts.first} idx=$idx $shown');
        }
      }
    } finally {
      await _logout(s);
    }
    return out;
  }

  /// للأدوات الحيّة: النصّ المفكوك لكتلٍ بعينها (بلا طباعةٍ لشيءٍ حسّاس — المنادي يختار الكتل).
  @visibleForTesting
  static Future<String?> debugRead(String host, String pass, String blocksQuery) async {
    final h = host.trim();
    final s = await _login(h, pass);
    if (s == null) return null;
    try {
      return await _secure(s, 'code=2&asyn=1', blocksQuery);
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
      final text = await _secure(s, 'code=2&asyn=1', readBlocks);
      final sp = text == null ? null : MerParse.split(text);
      if (sp == null || sp.code != 0) {
        _note(h, MerIssue.readFailed, 'read ${sp?.code}');
        return null;
      }
      final b = MerParse.blocks(sp.lines.join('\r\n'));
      final snap = MerParse.status(b, baseUrl: s.base, plainUptime: _plain(h, MerParse.block(b, '23')['upTime']));
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

  /// السبب الأخير مترجماً لعائلة العمليّات.
  static RouterFail _fail(String h) => switch (_issues[h]?.issue) {
        MerIssue.rejected => RouterFail.rejected,
        MerIssue.busy => RouterFail.busy,
        MerIssue.locked => RouterFail.locked,
        MerIssue.unreachable => RouterFail.unreachable,
        _ => RouterFail.failed,
      };

  /// جلسة الكرت الحيّة: دخولٌ مرّة، ثمّ كلّ نبضةٍ حالة WAN (عدّادات + مدّة الاتّصال) وكلّ [liveClientsEvery] جدول المحطّات.
  static Future<RouterLive?> openLive(String host, String pass) async {
    final h = host.trim();
    final s = await _login(h, pass);
    return s == null ? null : _MerLive(s, h);
  }

  /// شبكات الواي فاي بكلمات سرّها: دخول ⇒ الكتلة 33 للنطاقين ⇒ خروج.
  static Future<RouterResult<List<RouterWifi>>> readWifi(String host, String pass) async {
    final h = host.trim();
    final s = await _login(h, pass);
    if (s == null) return RouterResult.fail(_fail(h), _issues[h]?.trace);
    try {
      final w = await _readWifiIn(s);
      return w == null ? const RouterResult.fail(RouterFail.failed, 'wifi read') : RouterResult.ok(w);
    } finally {
      await _logout(s);
    }
  }

  /// راوترٌ بنطاقٍ واحد يرفض «2,1,0» ⇒ يُعاد السؤال عن 2.4G وحده.
  static Future<List<RouterWifi>?> _readWifiIn(MerSession s) async {
    var text = await _secure(s, 'code=2&asyn=1', '33|1,1,0#33|2,1,0');
    var sp = text == null ? null : MerParse.split(text);
    if (sp != null && sp.code != 0) {
      text = await _secure(s, 'code=2&asyn=1', '33|1,1,0');
      sp = text == null ? null : MerParse.split(text);
    }
    if (sp == null || sp.code != 0) return null;
    final w = MerParse.wifi(MerParse.blocks(sp.lines.join('\r\n')));
    return w.isEmpty ? null : w;
  }

  /// كلمة سرّ الواي فاي الجديدة لكلّ شبكةٍ رئيسيّة مفعّلة بـPSK (الكتلة 33 «cPskSecret» — الحقل الذي تحفظه صفحة الجهاز)، ثمّ قراءةٌ
  /// ثانية تؤكّد أنّ الراوتر حفظها فعلاً (لا «تمّ» على ردٍّ وحده). الردّ الضائع بعد الإرسال ⇒ القراءة الثانية تحسم.
  static Future<RouterResult<List<RouterWifi>>> setWifiPassword(String host, String pass, String newPass) async {
    final h = host.trim();
    final s = await _login(h, pass);
    if (s == null) return RouterResult.fail(_fail(h), _issues[h]?.trace);
    try {
      final before = await _readWifiIn(s);
      if (before == null) return const RouterResult.fail(RouterFail.failed, 'wifi read');
      final refs = [for (final w in before) if (w.enabled && w.canChange && w.ref != null) w.ref!];
      if (refs.isEmpty) return const RouterResult.fail(RouterFail.noPsk);
      final text = await _secure(s, 'code=1&asyn=0', MerParse.wifiPasswordWrite(refs, newPass));
      final sp = text == null ? null : MerParse.split(text);
      if (sp != null && sp.code != 0) return RouterResult.fail(RouterFail.failed, 'write ${sp.code}');
      final after = await _readWifiIn(s);
      if (after == null) return const RouterResult.fail(RouterFail.failed, 'verify read');
      final saved = after.where((w) => w.ref != null && refs.contains(w.ref)).every((w) => w.password == newPass);
      return saved ? RouterResult.ok(after) : const RouterResult.fail(RouterFail.failed, 'not saved');
    } finally {
      await _logout(s);
    }
  }

  /// إعادة التشغيل بأمر زرّ الصفحة نفسه (`rebootProxy`: `code=6&asyn=1`). ⛔ `code=5` إعادة ضبط المصنع — لا تُرسل.
  static Future<RouterResult<RouterReboot>> reboot(String host, String pass) async {
    final h = host.trim();
    final s = await _login(h, pass);
    if (s == null) return RouterResult.fail(_fail(h), _issues[h]?.trace);
    var rebooting = false;
    try {
      final text = await _secure(s, 'code=6&asyn=1', '');
      if (text == null) {
        rebooting = true;
        return const RouterResult.ok(RouterReboot(confirmed: false));
      }
      final sp = MerParse.split(text);
      if (sp != null && sp.code == 0) {
        rebooting = true;
        return const RouterResult.ok(RouterReboot(confirmed: true));
      }
      return RouterResult.fail(RouterFail.failed, 'reboot ${sp?.code}');
    } finally {
      if (rebooting) {
        s.client.close(force: true); // يقلع — لا خروج
      } else {
        await _logout(s);
      }
    }
  }
}

class _MerLive implements RouterLive {
  _MerLive(this._s, this._h);
  final MerSession _s;
  final String _h;
  int _n = 0;
  int _misses = 0;
  bool _closed = false;

  @override
  bool get lost => _closed || _misses >= 2;

  @override
  Future<RouterSample?> sample() async {
    if (_closed) return null;
    final withClients = _n % TplinkMerService.liveClientsEvery == 0;
    _n++;
    final text = await TplinkMerService._secure(_s, 'code=2&asyn=1', withClients ? '23|1,0,0#13|1,0,0' : '23|1,0,0');
    final sp = text == null ? null : MerParse.split(text);
    if (sp == null || sp.code != 0) {
      _misses++;
      return null;
    }
    _misses = 0;
    final b = MerParse.blocks(sp.lines.join('\r\n'));
    final c = MerParse.counters(b);
    return RouterSample(
      rxBytes: c?.rx,
      txBytes: c?.tx,
      clients: withClients ? MerParse.stations(MerParse.block(b, '13')) : null,
      wanOnlineSeconds: MerParse.upSeconds(MerParse.block(b, '23')['upTime'], plain: TplinkMerService._plain(_h, MerParse.block(b, '23')['upTime'])),
      at: DateTime.now(),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await TplinkMerService._logout(_s);
  }
}
