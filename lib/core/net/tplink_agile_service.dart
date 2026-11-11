import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show md5;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pointycastle/export.dart'
    show AESEngine, CBCBlockCipher, KeyParameter, PKCS7Padding, PaddedBlockCipherImpl, PaddedBlockCipherParameters, ParametersWithIV;

import '../../models/device_health.dart';

/// TP-Link «Agile» modern router (Archer AX10 & kin — واجهة الـSPA الحديثة، قِيست المصافحة حيّاً ١١ نوفمبر):
/// جهاز المشترك راوترٌ منزليّ (لا راديو)، بروتوكولٌ **مختلف عن userRpm الكلاسيكيّ** ([TplinkClassicService]):
///  * HTTPS ذاتيّ التوقيع على 443 (HTTP يحوّل إليه)، SPA على `/webpages/`، وAPI «Luci» على `/cgi-bin/luci/;stok=<stok>/<module>?form=<x>`.
///  * الدخول **بكلمة سرٍّ محلّيّة بلا يوزر** (`username:''`) بتعميةٍ RSA+AES مزدوجة — مؤكَّدة بلا اعتماد عبر المصافحتين العامّتين:
///      `form=keys` ⇒ `{password:[n,e]}` (RSA لكلمة السرّ) · `form=auth` ⇒ `{key:[n,e], seq}` (RSA لمفتاح الـAES والتوقيع).
///    ثمّ: مفتاح AES عشوائيّ (١٦ رقماً + ١٦ رقماً IV) ⇒ البيانات تُعمّى AES-CBC، والتوقيع `key=…&iv=…&h=md5(user+pass)&s=seq+len`
///    يُعمّى RSA، فـ`POST form=login {sign,data}` ⇒ ردٌّ مُعمّى AES فيه `stok`. القراءات بعده بنفس الغلاف وseq يتصاعد.
///  * متغيّرات المالك الثلاثة من `/admin/status?form=all`: المتّصلون (لاسلكيّ+سلكيّ)، مدّة اتّصال WAN، ونوع الإنترنت، + الترافيك.
///  * لا افتراض مصنّع (الراوتر الحديث يعدّ المحاولات) — اعتماد الوكيل وحده. الكتابة (إعادة تشغيل) غير مبنيّة.

/// جلسةٌ مفتوحة بعد الدخول — الـstok ومفتاح الـAES وseq المتصاعد.
class AgileSession {
  AgileSession({required this.host, required this.stok, required this.aesKey, required this.aesIv, required this.seq});
  final String host;
  final String stok;
  final String aesKey;
  final String aesIv;
  int seq;
}

enum AgileIssue { rejected, unreachable, busy, readFailed }

/// قارئاتٌ صرفة (بلا شبكة) لردّ `/admin/status?form=all` ⇒ لقطة الراوتر. الأسماء من الواجهة الحديثة القياسيّة.
class TpAgileParse {
  TpAgileParse._();

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v.trim());
    if (v is double) return v.round();
    return null;
  }

  static String _str(Object? v) => v == null ? '' : v.toString().trim();

  /// عدد المتّصلين: طول قائمتَي الأجهزة اللاسلكيّة والسلكيّة إن وُجدتا، وإلّا عدّادٌ جاهز.
  static int? clients(Map<String, dynamic> d) {
    int? n;
    for (final k in ['access_devices_wireless_host', 'access_devices_wireless_guest', 'access_devices_wired']) {
      final v = d[k];
      if (v is List) n = (n ?? 0) + v.length;
    }
    if (n != null) return n;
    for (final k in ['online_devices', 'client_num', 'wireless_host_count']) {
      final c = _int(d[k]);
      if (c != null) return c;
    }
    return null;
  }

  /// قائمة الأجهزة المتّصلة من قوائم الواجهة (لاسلكيّ مضيف/ضيف + سلكيّ). أسماء الحقول تختلف بالفيرموير ⇒ نقرأ عدّة بدائل.
  static List<RouterClient> clientList(Map<String, dynamic> d) {
    final out = <RouterClient>[];
    const macK = ['mac', 'macaddr', 'MAC', 'mac_addr'];
    const ipK = ['ipaddr', 'ip', 'ipv4', 'ip_addr'];
    const nameK = ['hostname', 'name', 'host_name', 'devicename', 'device_name'];
    String pick(Map m, List<String> keys) {
      for (final k in keys) {
        final v = _str(m[k]);
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    for (final entry in [
      ('access_devices_wireless_host', false),
      ('access_devices_wireless_guest', false),
      ('access_devices_wired', true),
    ]) {
      final v = d[entry.$1];
      if (v is! List) continue;
      for (final e in v) {
        if (e is! Map) continue;
        final mac = pick(e, macK);
        if (mac.isEmpty) continue;
        final ip = pick(e, ipK);
        final name = pick(e, nameK);
        out.add(RouterClient(mac: mac, ip: ip.isEmpty ? null : ip, name: name.isEmpty ? null : name, wired: entry.$2));
      }
    }
    return out;
  }

  /// نوع اتّصال الإنترنت كما تسمّيه الواجهة («pppoe» ⇒ PPPoE).
  static String wanType(Map<String, dynamic> d) {
    final t = _str(d['wan_ipv4_conntype']).isNotEmpty
        ? _str(d['wan_ipv4_conntype'])
        : _str(d['conn_type']).isNotEmpty
            ? _str(d['conn_type'])
            : _str(d['wan_type']);
    return switch (t.toLowerCase()) {
      'pppoe' || 'pppoe_dynamic' => 'PPPoE',
      'dynamic_ip' || 'dhcp' || 'dynamic' => 'Dynamic IP',
      'static_ip' || 'static' => 'Static IP',
      'l2tp' => 'L2TP',
      'pptp' => 'PPTP',
      '' => '',
      _ => t,
    };
  }

  /// مدّة اتّصال WAN بالثواني (uptime)، وإلّا null.
  static int? wanOnline(Map<String, dynamic> d) {
    for (final k in ['wan_ipv4_uptime', 'wan_uptime', 'uptime', 'conn_uptime']) {
      final s = _int(d[k]);
      if (s != null && s >= 0) return s;
    }
    return null;
  }

  static int? _bytes(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = _int(d[k]);
      if (v != null && v >= 0) return v;
    }
    return null;
  }

  /// ردّ status ⇒ لقطةٌ بمورّد `tpagile` (عائلة الراوتر — نفس بطاقة [TplinkClassicService] بلا إشارة ولا منافذ).
  static UbiquitiStatus? status(Map<String, dynamic> body, {required String host, String model = ''}) {
    final d = body['data'];
    if (d is! Map) return null;
    final m = Map<String, dynamic>.from(d);
    final fw = _str(m['firmware_version']).isNotEmpty ? _str(m['firmware_version']) : _str(m['software_version']);
    final hw = _str(m['hardware_version']);
    final name = _str(m['device_model']).isNotEmpty ? _str(m['device_model']) : (model.isNotEmpty ? model : hw);
    return UbiquitiStatus(
      hostname: '',
      firmware: fw,
      uptimeSeconds: _int(m['sys_uptime']) ?? _int(m['device_uptime']),
      ssid: _str(m['ssid_2g']).isNotEmpty ? _str(m['ssid_2g']) : _str(m['wireless_2g_ssid']),
      mode: 'router',
      signalDbm: null,
      noiseFloorDbm: null,
      ccqPercent: null,
      distanceMeters: null,
      txRateKbps: null,
      rxRateKbps: null,
      rxBytes: _bytes(m, ['wan_ipv4_totaldata_down', 'total_bytes_received', 'wan_recv_bytes']),
      txBytes: _bytes(m, ['wan_ipv4_totaldata_up', 'total_bytes_sent', 'wan_sent_bytes']),
      lanPorts: const [],
      peerMac: null,
      peerCount: clients(m),
      baseUrl: 'https://$host',
      vendor: 'tpagile',
      model: name,
      wanOnlineSeconds: wanOnline(m),
      dhcpCount: null,
      wanType: wanType(m),
      clients: clientList(m),
    );
  }
}

/// تعمية سكيم TP-Link (RSA PKCS#1 v1.5 مقسَّمة + AES-CBC + MD5) — صرفة، تُختبر بجهازٍ وهميّ loopback.
class AgileCrypto {
  static final _rnd = Random.secure();

  static BigInt _hex(String h) => BigInt.parse(h, radix: 16);

  static Uint8List _biToBytes(BigInt v, int len) {
    final out = Uint8List(len);
    var x = v;
    for (var i = len - 1; i >= 0 && x > BigInt.zero; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }

  static BigInt _bytesToBi(List<int> b) {
    var v = BigInt.zero;
    for (final x in b) {
      v = (v << 8) | BigInt.from(x);
    }
    return v;
  }

  /// RSA PKCS#1 v1.5 (type 2) تعميةٌ مقسَّمة إلى كتل (keyLen−11 بايت)، الناتج هكس متّصل. [testPad] يثبّت الحشو للاختبار.
  static String rsaEncrypt(String data, String nHex, String eHex, {List<int>? Function(int n)? testPad}) {
    final n = _hex(nHex);
    final e = _hex(eHex);
    final keyLen = (n.bitLength + 7) >> 3;
    final msg = utf8.encode(data);
    final maxChunk = keyLen - 11;
    final sb = StringBuffer();
    for (var i = 0; i < msg.length; i += maxChunk) {
      final chunk = msg.sublist(i, min(i + maxChunk, msg.length));
      final psLen = keyLen - chunk.length - 3;
      final padded = Uint8List(keyLen);
      padded[0] = 0x00;
      padded[1] = 0x02;
      final ps = testPad != null ? testPad(psLen) : null;
      for (var j = 0; j < psLen; j++) {
        padded[2 + j] = ps != null ? ps[j] : (_rnd.nextInt(255) + 1);
      }
      padded[2 + psLen] = 0x00;
      padded.setRange(3 + psLen, keyLen, chunk);
      final c = _bytesToBi(padded).modPow(e, n);
      final hex = c.toRadixString(16).padLeft(keyLen * 2, '0');
      sb.write(hex);
    }
    return sb.toString();
  }

  /// RSA فكٌّ (للجهاز الوهميّ وحده — الاختبار): يفكّ كتل الهكس ويزيل حشو PKCS#1 v1.5.
  @visibleForTesting
  static String rsaDecrypt(String hexData, String nHex, String dHex) {
    final n = _hex(nHex);
    final d = _hex(dHex);
    final keyLen = (n.bitLength + 7) >> 3;
    final out = <int>[];
    for (var i = 0; i < hexData.length; i += keyLen * 2) {
      final block = hexData.substring(i, min(i + keyLen * 2, hexData.length));
      final m = _biToBytes(_hex(block).modPow(d, n), keyLen);
      var k = 2;
      while (k < keyLen && m[k] != 0) {
        k++;
      }
      out.addAll(m.sublist(k + 1));
    }
    return utf8.decode(out);
  }

  static PaddedBlockCipherImpl _aes(bool forEncrypt, String key, String iv) {
    final c = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
    c.init(forEncrypt, PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(ascii.encode(key)), ascii.encode(iv)), null));
    return c;
  }

  /// AES-128-CBC (المفتاح والـIV = بايتات ASCII لنصّي الـ١٦ رقماً) ⇒ base64.
  static String aesEncrypt(String plain, String key, String iv) => base64.encode(_aes(true, key, iv).process(Uint8List.fromList(utf8.encode(plain))));

  static String aesDecrypt(String b64, String key, String iv) => utf8.decode(_aes(false, key, iv).process(base64.decode(b64)));

  /// نصّ عشوائيّ من [n] رقماً (مفتاح/IV الـAES كما يولّده التطبيق الأصليّ).
  static String digits(int n) {
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      sb.write(_rnd.nextInt(10));
    }
    return sb.toString();
  }

  static String md5Hex(String s) => md5.convert(utf8.encode(s)).toString();
}

class TplinkAgileService {
  TplinkAgileService._();

  static const _connect = Duration(seconds: 5);
  static const _readTimeout = Duration(seconds: 12);

  /// للاختبار: أصل الجهاز (منفذٌ محلّيّ لجهازٍ وهميّ، بروتوكولٌ http هناك).
  @visibleForTesting
  static String Function(String host) baseFor = (h) => 'https://$h';

  static final _issues = <String, ({AgileIssue issue, String trace, DateTime at})>{};
  static final _rejected = <String, Set<String>>{};

  static ({AgileIssue issue, String trace})? lastIssue(String host) {
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
  }

  static void _note(String host, AgileIssue issue, String trace) => _issues[host] = (issue: issue, trace: trace, at: DateTime.now());

  /* ───────────────────────── الطلب ───────────────────────── */

  static Future<({int status, String body})?> _post(String base, String path, String body, {Map<String, String>? headers, Duration? timeout}) async {
    final client = HttpClient()
      ..connectionTimeout = _connect
      ..badCertificateCallback = (_, __, ___) => true; // شهادة ذاتيّة التوقيع
    try {
      final req = await client.postUrl(Uri.parse('$base$path')).timeout(_connect);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
      req.headers.set(HttpHeaders.refererHeader, '$base/');
      headers?.forEach(req.headers.set);
      // 🐛 (١١ نوفمبر، حيّاً على Archer AX10): بلا Content-Length يرسل Dart الجسم **chunked**، وخادم TP-Link المضمَّن لا يقرأ
      // جسماً chunked ⇒ يردّ «no such callback» (لا يرى form/operation). ضبط الطول صراحةً = إرسالٌ عاديّ يقبله الجهاز.
      final payload = utf8.encode(body);
      req.contentLength = payload.length;
      req.add(payload);
      final res = await req.close().timeout(timeout ?? _readTimeout);
      final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(timeout ?? _readTimeout);
      return (status: res.statusCode, body: utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic>? _json(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final j = jsonDecode(s);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// مصافحةٌ عامّة (بلا اعتماد): form=keys أو form=auth ⇒ data. null ⇒ ليس من هذه العائلة/لا يجاوب.
  static Future<Map<String, dynamic>?> _handshake(String base, String form) async {
    final r = await _post(base, '/cgi-bin/luci/;stok=/login?form=$form', 'operation=read', timeout: const Duration(seconds: 6));
    if (r == null || r.status != 200) return null;
    final j = _json(r.body);
    final d = j?['data'];
    return (j?['success'] == true && d is Map<String, dynamic>) ? d : null;
  }

  /// أهو راوتر TP-Link حديث؟ مصافحة keys العامّة تؤكّده (RSA لكلمة السرّ، username فارغ). null ⇒ لا.
  static Future<bool> detect(String host) async {
    final d = await _handshake(baseFor(host.trim()), 'keys');
    return d != null && d['password'] is List;
  }

  /* ───────────────────────── الدخول ───────────────────────── */

  static String _basic(String user, String pass) => '$user\u0000$pass';

  /// دخولٌ واحد بكلمة السرّ المحلّيّة ⇒ جلسة أو null (السبب في [lastIssue]). المرفوض لا يُعاد تلقائيّاً.
  static Future<AgileSession?> login(String host, String password, {String username = ''}) async {
    final h = host.trim();
    final base = baseFor(h);
    final tag = _basic(username, password);
    if (_rejected[h]?.contains(tag) ?? false) {
      _note(h, AgileIssue.rejected, 'remembered');
      return null;
    }
    final keys = await _handshake(base, 'keys');
    if (keys == null) {
      _note(h, AgileIssue.unreachable, 'keys no-handshake');
      return null;
    }
    final auth = await _handshake(base, 'auth');
    final pwdKey = keys['password'];
    final signKey = auth?['key'];
    final seq = TpAgileParse._int(auth?['seq']);
    if (pwdKey is! List || pwdKey.length < 2 || signKey is! List || signKey.length < 2 || seq == null) {
      _note(h, AgileIssue.readFailed, 'handshake shape');
      return null;
    }
    final aesKey = AgileCrypto.digits(16);
    final aesIv = AgileCrypto.digits(16);
    final hashed = AgileCrypto.md5Hex('$username$password');
    final pwdEnc = AgileCrypto.rsaEncrypt(password, '${pwdKey[0]}', '${pwdKey[1]}');
    final dataEnc = AgileCrypto.aesEncrypt('password=$pwdEnc', aesKey, aesIv);
    final s = seq + dataEnc.length;
    final signEnc = AgileCrypto.rsaEncrypt('key=$aesKey&iv=$aesIv&h=$hashed&s=$s', '${signKey[0]}', '${signKey[1]}');
    // 🐛 (١١ نوفمبر، حيّاً على Archer AX10): operation=login يجب أن يكون في الجسم **الخارجيّ** نصّاً. عند `;stok=/login`
    // لا جلسةَ بعدُ، فلا يفكّ الجهاز الحمولة المعمّاة ليوجّه ⇒ لا بدّ من العمليّة ظاهرة. داخل data ⇒ «no such callback».
    // (القراءات بعد الدخول تُفكّ بجلسة الـstok، فعمليّتها `operation=read` تبقى **داخل** الحمولة — سليمة في `_read`.)
    final body = 'sign=$signEnc&data=${Uri.encodeQueryComponent(dataEnc)}&operation=login';
    final r = await _post(base, '/cgi-bin/luci/;stok=/login?form=login', body);
    if (r == null) {
      _note(h, AgileIssue.unreachable, 'login no-reply');
      return null;
    }
    final j = _json(r.body);
    final data = j?['data'];
    if (j?['success'] == true && data is String) {
      try {
        final dec = _json(AgileCrypto.aesDecrypt(data, aesKey, aesIv));
        final stok = dec?['stok'];
        if (stok is String && stok.isNotEmpty) {
          _rejected[h]?.remove(tag);
          _issues.remove(h);
          return AgileSession(host: h, stok: stok, aesKey: aesKey, aesIv: aesIv, seq: s);
        }
      } catch (_) {/* فكّ فاشل ⇒ أسفل */}
      _note(h, AgileIssue.readFailed, 'login decrypt');
      return null;
    }
    // رمز خطأ: كلمة سرٍّ غلط (نحفظها فلا تُعاد)، أو مشغول، أو شكلٌ غير متوقَّع.
    final err = TpAgileParse._int(j?['errorcode']) ?? TpAgileParse._int((data is Map ? data['errorcode'] : null));
    if (err == null && (j?['success'] != true)) {
      // أكثر أخطاء الدخول = اعتمادٌ غلط.
      (_rejected[h] ??= <String>{}).add(tag);
      _note(h, AgileIssue.rejected, 'login code=${j?['errorcode'] ?? '?'}');
    } else {
      _note(h, AgileIssue.readFailed, 'login err=$err');
    }
    return null;
  }

  /// قراءةٌ مُعمّاة بجلسة (seq يتصاعد): module/form ⇒ JSON (المفكوك)، أو null.
  static Future<Map<String, dynamic>?> _read(AgileSession ss, String module, String form) async {
    final base = baseFor(ss.host);
    ss.seq += 1;
    const plain = 'operation=read';
    final dataEnc = AgileCrypto.aesEncrypt(plain, ss.aesKey, ss.aesIv);
    final s = ss.seq + dataEnc.length;
    // بعد الدخول: التوقيع = md5 الجلسة (stok) لا كلمة السرّ — نضع stok كـhash الطلب.
    final hashed = AgileCrypto.md5Hex(ss.stok);
    // مفتاح التوقيع بعد الدخول هو نفسه auth؛ نعيد المصافحة لأخذه (الجهاز يسمح بها بلا دخول) — خفيفة.
    final auth = await _handshake(base, 'auth');
    final signKey = auth?['key'];
    if (signKey is! List || signKey.length < 2) return null;
    final signEnc = AgileCrypto.rsaEncrypt('h=$hashed&s=$s', '${signKey[0]}', '${signKey[1]}');
    final body = 'sign=$signEnc&data=${Uri.encodeQueryComponent(dataEnc)}';
    final r = await _post(base, '/cgi-bin/luci/;stok=${ss.stok}/admin/$module?form=$form', body);
    if (r == null || r.status != 200) return null;
    final j = _json(r.body);
    final data = j?['data'];
    if (data is String) {
      try {
        return _json(AgileCrypto.aesDecrypt(data, ss.aesKey, ss.aesIv));
      } catch (_) {
        return null;
      }
    }
    return j;
  }

  /// لقطة الراوتر: `/admin/status?form=all`. null ⇒ تعذّرت القراءة.
  static Future<UbiquitiStatus?> readStatus(AgileSession ss, {String model = ''}) async {
    final body = await _read(ss, 'status', 'all');
    if (body == null) {
      _note(ss.host, AgileIssue.readFailed, 'status');
      return null;
    }
    final snap = TpAgileParse.status(body, host: ss.host, model: model);
    if (snap == null) _note(ss.host, AgileIssue.readFailed, 'status shape');
    return snap;
  }

  /// دخولٌ ثمّ قراءةٌ واحدة (لفحص الكرت) ⇒ لقطة أو null.
  static Future<UbiquitiStatus?> readOnce(String host, String password, {String username = '', String model = ''}) async {
    final ss = await login(host, password, username: username);
    if (ss == null) return null;
    return readStatus(ss, model: model);
  }
}
