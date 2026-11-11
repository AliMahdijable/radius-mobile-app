import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show Hmac, md5, sha256;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pointycastle/export.dart'
    show
        AESEngine,
        CBCBlockCipher,
        FortunaRandom,
        KeyParameter,
        OAEPEncoding,
        PKCS7Padding,
        PaddedBlockCipherImpl,
        PaddedBlockCipherParameters,
        ParametersWithIV,
        ParametersWithRandom,
        PublicKeyParameter,
        RSAEngine,
        RSAPublicKey,
        SecureRandom;

import '../../models/device_health.dart';

/// TP-Link «Agile» modern router (Archer AX10 & kin — واجهة الـSPA الحديثة):
/// جهاز المشترك راوترٌ منزليّ (لا راديو)، بروتوكولٌ **مختلف عن userRpm الكلاسيكيّ** ([TplinkClassicService]):
///  * HTTPS ذاتيّ التوقيع على 443 (HTTP يحوّل إليه)، SPA على `/webpages/`، وAPI «Luci» على `/cgi-bin/luci/;stok=<stok>/<module>?form=<x>`.
///  * السكيم **منقولٌ حرفاً من واجهة الجهاز نفسه** (`/webpages/js/update-store-*.js` + `index-*.js`، قُرئت من راوتر المشترك ١١ نوفمبر
///    ليلاً — قراءةٌ بلا دخول):
///      `form=keys` ⇒ `{password:[n,e]}` (RSA PKCS#1 v1.5 لكلمة السرّ) · `form=auth` ⇒ `{key:[n,e], seq}` (مفتاح التوقيع)
///      · `/device_config?form=config` ⇒ `certification` ⇒ [AgileFlags] (الوضع الصارم لشهادات EU CE RED / SG CLS L1 STAGE2).
///    الدخول: هاش = MD5 أو SHA256 لـ`"admin"+كلمة السرّ` · مفتاح AES ١٦ رقماً + IV ١٦ رقماً · البيانات = AES-CBC لـ
///    `password=<rsa>&operation=login` (العمليّة **داخل** المعمّى) · التوقيع = `k=<key>&i=<iv>&h=<hash>&s=<seq+len>` مقسَّماً ٥٣ محرفاً،
///    كلّ قطعةٍ RSA (OAEP أو PKCS#1 v1.5) · `POST form=login {sign,data}` ⇒ ردٌّ مُعمّى فيه `stok` (+ كوكي الجلسة).
///    ما بعد الدخول: seq ثابت، `h` = هاش الدخول أو SHA256(البيانات المعمّاة)، والتوقيع RSA أو HMAC-SHA256 بمفتاح «k=…&i=…».
///  * 🐛 (١١ نوفمبر، قبل نقل السكيم): كنّا نوقّع `key=…&iv=…` (الجهاز يريد `k=`/`i=`) ⇒ لا يفكّ البيانات ⇒ «no such callback»؛ ونقل
///    العمليّة إلى الجسم الخارجيّ «أصلحها» شكلاً فصار الردّ «login failed» لكلمة السرّ الصحيحة. وهاشنا كان MD5(كلمة السرّ) بلا "admin".
///  * متغيّرات المالك الثلاثة من `/admin/status?form=all`: المتّصلون (لاسلكيّ+سلكيّ)، مدّة اتّصال WAN، ونوع الإنترنت، + الترافيك.
///  * لا افتراض مصنّع: الجهاز يعدّ المحاولات (١٠ ثمّ قفل ساعتين — `failureCount`/`attemptsAllowed` في ردّ الرفض) ⇒ لا دخول حين يبلغ
///    العدّاد ٥ (تلقائيّاً) أو ٨ («حفظ وفحص»)، ولا «confirm» يطرد من يفتح صفحة الراوتر. الكتابة (إعادة تشغيل) غير مبنيّة.

/// ميزات الأمان كما يعلنها الجهاز نفسه (`/device_config?form=config` ⇒ `certification`) — مطابقةٌ لـ`FEATURE_MAP` في واجهته.
class AgileFlags {
  const AgileFlags({this.sha256 = false, this.oaep = false, this.gdpr = false, this.replaceHash = false});

  /// هاش الدخول SHA256("admin"+كلمة السرّ) بدل MD5 («2_login_SHA256»).
  final bool sha256;

  /// قطع التوقيع RSA-OAEP (SHA-1، كـforge) بدل PKCS#1 v1.5 («13_rsa_pad_with_pkcs1_oaep»).
  final bool oaep;

  /// توقيع ما بعد الدخول HMAC-SHA256 بمفتاح «k=…&i=…» بدل RSA («5_gdpr»).
  final bool gdpr;

  /// هاش ما بعد الدخول = SHA256(البيانات المعمّاة) لكلّ طلب («12_replace_hash»).
  final bool replaceHash;

  static const legacy = AgileFlags();

  static const _rg = 'IMDA TS RG-SEC', _sg = 'SG CLS L1 STAGE2', _red = 'EU CE RED', _ato = 'Brazil ANATEL';

  factory AgileFlags.fromCertification(List<String> c) {
    bool any(List<String> xs) => c.any(xs.contains);
    return AgileFlags(
      sha256: any(const [_rg, _sg, _red, _ato]),
      gdpr: any(const [_sg, _red, _ato]),
      replaceHash: any(const [_sg]),
      oaep: any(const [_sg]),
    );
  }

  @override
  String toString() {
    final on = [if (sha256) 'sha256', if (oaep) 'oaep', if (gdpr) 'gdpr', if (replaceHash) 'replaceHash'];
    return on.isEmpty ? 'legacy' : on.join('+');
  }
}

/// جلسةٌ مفتوحة بعد الدخول — الـstok ومفتاح الـAES وseq (ثابتٌ للجلسة) وهاش الدخول ومفتاح التوقيع وكوكي الجلسة.
class AgileSession {
  AgileSession({
    required this.host,
    required this.stok,
    required this.aesKey,
    required this.aesIv,
    required this.seq,
    required this.hash,
    required this.flags,
    required this.signN,
    required this.signE,
    this.cookie = '',
    this.plain = false,
    this.model = '',
  });
  final String host;
  final String stok;
  final String aesKey;
  final String aesIv;
  final int seq;
  final String hash;
  final AgileFlags flags;
  final String signN;
  final String signE;
  final String cookie;

  /// جهاز GDPR عبر HTTPS: الطلبات نموذجٌ صريح بلا AES ولا توقيع (TLS يكفي) — `needSerialize` في واجهته.
  final bool plain;

  /// الموديل من `/login?form=get_deviceInfo` العامّ (فيرموير status بلا device_model — Archer AX10 حيّاً).
  final String model;
}

enum AgileIssue { rejected, unreachable, busy, locked, readFailed }

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

/// تعمية سكيم TP-Link (RSA PKCS#1 v1.5 / OAEP + AES-CBC + MD5/SHA256/HMAC) — صرفة، تُختبر بجهازٍ وهميّ loopback.
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

  static String _bytesHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  /// RSA PKCS#1 v1.5 (type 2) تعميةٌ مقسَّمة إلى كتل (keyLen−11 بايت)، الناتج هكس متّصل. [testPad] يثبّت الحشو للاختبار.
  /// (كـ`jsbn RSAKey.encrypt` في واجهة الجهاز: كلمة السرّ دائماً، وقطع التوقيع حين لا OAEP.)
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

  static SecureRandom _secure() {
    final s = FortunaRandom();
    s.seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => _rnd.nextInt(256)))));
    return s;
  }

  /// RSA-OAEP (SHA-1 للهاش وMGF1 — افتراض forge `publicKey.encrypt(…, 'RSA-OAEP')` في واجهة الجهاز)، كتلٌ بحدّ keyLen−42، هكس كلّ كتلة
  /// بطول المفتاح.
  static String rsaOaepEncrypt(String data, String nHex, String eHex) {
    final pub = RSAPublicKey(_hex(nHex), _hex(eHex));
    final keyLen = (pub.modulus!.bitLength + 7) >> 3;
    final cipher = OAEPEncoding(RSAEngine())..init(true, ParametersWithRandom(PublicKeyParameter<RSAPublicKey>(pub), _secure()));
    final msg = Uint8List.fromList(utf8.encode(data));
    final maxChunk = keyLen - 42;
    final sb = StringBuffer();
    for (var i = 0; i < msg.length; i += maxChunk) {
      final out = cipher.process(Uint8List.sublistView(msg, i, min(i + maxChunk, msg.length)));
      sb.write(_bytesHex(out).padLeft(keyLen * 2, '0'));
    }
    return sb.toString();
  }

  static PaddedBlockCipherImpl _aes(bool forEncrypt, String key, String iv) {
    final c = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
    c.init(forEncrypt, PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(ascii.encode(key)), ascii.encode(iv)), null));
    return c;
  }

  /// AES-128-CBC (المفتاح والـIV = بايتات نصّي الـ١٦ رقماً) ⇒ base64.
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

  static String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

  static String hmacSha256Hex(String msg, String key) => Hmac(sha256, utf8.encode(key)).convert(utf8.encode(msg)).toString();

  /// هاش الدخول كواجهة الجهاز (`Sn`): `"admin"+كلمة السرّ` بـSHA256 أو MD5 (اسم الدخول المحلّيّ ثابتٌ «admin» في الواجهة).
  static String loginHash(String password, AgileFlags flags) => flags.sha256 ? sha256Hex('admin$password') : md5Hex('admin$password');

  /// توقيع الطلب كواجهة الجهاز (`generateSignature`/`_getEncryptedSignature`): النصّ يُقسَّم ٥٣ محرفاً، وكلّ قطعة: RSA (OAEP أو
  /// PKCS#1 v1.5 حسب الجهاز) للدخول أو حين لا GDPR، وإلّا HMAC-SHA256 بمفتاح «k=…&i=…». القطع متّصلة هكساً.
  static String signature(
    String plain, {
    required bool login,
    required AgileFlags flags,
    required String nHex,
    required String eHex,
    required String aesKey,
    required String aesIv,
  }) {
    final sb = StringBuffer();
    for (var i = 0; i < plain.length; i += 53) {
      final part = plain.substring(i, min(i + 53, plain.length));
      if (login || !flags.gdpr) {
        sb.write(flags.oaep ? rsaOaepEncrypt(part, nHex, eHex) : rsaEncrypt(part, nHex, eHex));
      } else {
        sb.write(hmacSha256Hex(part, 'k=$aesKey&i=$aesIv'));
      }
    }
    return sb.toString();
  }
}

class TplinkAgileService {
  TplinkAgileService._();

  static const _connect = Duration(seconds: 5);
  static const _readTimeout = Duration(seconds: 12);

  /// عتبة عدّاد الرفض عند الجهاز (١٠ ثمّ قفل ساعتين): لا دخول تلقائيّاً من ٥، ولا بعد «حفظ وفحص» من ٨ — يبقى للإنسان ما يدخل به.
  static const autoFailLimit = 5;
  static const manualFailLimit = 8;

  /// للاختبار: أصل الجهاز (منفذٌ محلّيّ لجهازٍ وهميّ، بروتوكولٌ http هناك).
  @visibleForTesting
  static String Function(String host) baseFor = (h) => 'https://$h';

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// أصلٌ مشفَّرٌ بـTLS؟ (واجهة الجهاز: `location.protocol === "https:"`) — جهاز GDPR عبر HTTPS لا يعمّي ولا يوقّع (`needEncrypt` false،
  /// `needSerialize` true). للاختبار: يُجبر المسار الصريح على جهازٍ وهميّ http.
  @visibleForTesting
  static bool Function(String base) isHttps = (b) => b.startsWith('https:');

  static final _issues = <String, ({AgileIssue issue, String trace, DateTime at})>{};
  static final _rejected = <String, Set<String>>{};
  static final _flagsByHost = <String, AgileFlags>{};
  static final _fails = <String, ({int failed, int? left})>{};
  static final _lockedUntil = <String, DateTime>{};
  static final _manualAt = <String, DateTime>{};
  static final _modelByHost = <String, String>{};

  static ({AgileIssue issue, String trace})? lastIssue(String host) {
    final i = _issues[host.trim()];
    return i == null ? null : (issue: i.issue, trace: i.trace);
  }

  /// الرفض المحفوظ يُنسى (اعتماداتٌ جديدة/«حفظ وفحص»). [manual] = «حفظ وفحص» ⇒ عتبة العدّاد ٨ لدقيقة. عدّاد الجهاز نفسه لا يُنسى.
  static void forget(String host, {bool manual = false}) {
    final h = host.trim();
    _issues.remove(h);
    _rejected.remove(h);
    if (manual) _manualAt[h] = clock();
  }

  static void reset() {
    _issues.clear();
    _rejected.clear();
    _flagsByHost.clear();
    _fails.clear();
    _lockedUntil.clear();
    _manualAt.clear();
    _modelByHost.clear();
  }

  static void _note(String host, AgileIssue issue, String trace) => _issues[host] = (issue: issue, trace: trace, at: DateTime.now());

  /* ───────────────────────── الطلب ───────────────────────── */

  static Future<({int status, String body, String cookie})?> _post(String base, String path, String body,
      {Map<String, String>? headers, Duration? timeout}) async {
    final client = HttpClient()
      ..connectionTimeout = _connect
      ..badCertificateCallback = (_, __, ___) => true; // شهادة ذاتيّة التوقيع
    try {
      final req = await client.postUrl(Uri.parse('$base$path')).timeout(_connect);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
      req.headers.set(HttpHeaders.refererHeader, '$base/webpages/index.html');
      headers?.forEach(req.headers.set);
      // بلا Content-Length يرسل Dart الجسم chunked، وخادم TP-Link المضمَّن لا يقرأ جسماً chunked. الطول صراحةً = إرسالٌ عاديّ.
      final payload = utf8.encode(body);
      req.contentLength = payload.length;
      req.add(payload);
      final res = await req.close().timeout(timeout ?? _readTimeout);
      final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(timeout ?? _readTimeout);
      final cookies = <String>[
        for (final c in res.headers[HttpHeaders.setCookieHeader] ?? const <String>[])
          if (c.split(';').first.trim().contains('=')) c.split(';').first.trim(),
      ];
      return (status: res.statusCode, body: utf8.decode(bytes, allowMalformed: true), cookie: cookies.join('; '));
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

  /// ميزات الجهاز (مرّةً لكلّ عنوان): قراءةٌ عامّة بلا دخول. لا ردّ أصلاً ⇒ null (لا محاولة دخولٍ بسكيمٍ مخمَّن — العدّاد يُحسب)؛
  /// ردٌّ بلا `certification` (فيرموير أقدم بلا هذا المسار) ⇒ السكيم القديم.
  static Future<AgileFlags?> _flagsFor(String host, String base) async {
    final c = _flagsByHost[host];
    if (c != null) return c;
    final r = await _post(base, '/cgi-bin/luci/;stok=/device_config?form=config', 'operation=read', timeout: const Duration(seconds: 8));
    if (r == null) return null;
    final d = _json(r.body)?['data'];
    final cert = d is Map && d['certification'] is List ? [for (final x in d['certification'] as List) '$x'] : null;
    final f = cert == null ? AgileFlags.legacy : AgileFlags.fromCertification(cert);
    _flagsByHost[host] = f;
    return f;
  }

  /// موديل الجهاز من المسار العامّ `/login?form=get_deviceInfo` (مرّةً لكلّ عنوان). تعذّر ⇒ ''.
  static Future<String> _modelFor(String host, String base) async {
    final c = _modelByHost[host];
    if (c != null) return c;
    final r = await _post(base, '/cgi-bin/luci/;stok=/login?form=get_deviceInfo', 'operation=read', timeout: const Duration(seconds: 6));
    final d = r == null ? null : _json(r.body)?['data'];
    final m = d is Map ? '${d['model'] ?? ''}'.trim() : '';
    if (r != null) _modelByHost[host] = m;
    return m;
  }

  /// ميزات الجهاز المعروفة (للاختبار والتشخيص).
  static AgileFlags? flagsOf(String host) => _flagsByHost[host.trim()];

  /// عدّاد الرفض كما ردّه الجهاز آخر مرّة (للاختبار والتشخيص).
  static ({int failed, int? left})? failsOf(String host) => _fails[host.trim()];

  /// أهو راوتر TP-Link حديث؟ مصافحة keys العامّة تؤكّده (RSA لكلمة السرّ). null ⇒ لا.
  static Future<bool> detect(String host) async {
    final d = await _handshake(baseFor(host.trim()), 'keys');
    return d != null && d['password'] is List;
  }

  /* ───────────────────────── الدخول ───────────────────────── */

  static String _basic(String user, String pass) => '$user\u0000$pass';

  /// دخولٌ واحد بكلمة السرّ المحلّيّة ⇒ جلسة أو null (السبب في [lastIssue]). المرفوض لا يُعاد تلقائيّاً، ولا دخول قرب حدّ العدّاد.
  /// [username] لا يدخل السكيم (واجهة الجهاز تهاش «admin» ثابتاً) — يبقى مفتاحاً لذاكرة الرفض وحدها.
  static Future<AgileSession?> login(String host, String password, {String username = ''}) async {
    final h = host.trim();
    final base = baseFor(h);
    final tag = _basic(username, password);
    if (_rejected[h]?.contains(tag) ?? false) {
      _note(h, AgileIssue.rejected, 'remembered');
      return null;
    }
    final lock = _lockedUntil[h];
    if (lock != null && clock().isBefore(lock)) {
      _note(h, AgileIssue.locked, 'locked');
      return null;
    }
    final m = _manualAt[h];
    final manual = m != null && clock().difference(m) < const Duration(minutes: 1);
    final f = _fails[h];
    if (f != null && f.failed >= (manual ? manualFailLimit : autoFailLimit)) {
      _note(h, AgileIssue.locked, 'guard failed=${f.failed}${f.left == null ? '' : ' left=${f.left}'}');
      return null;
    }
    final keys = await _handshake(base, 'keys');
    if (keys == null) {
      _note(h, AgileIssue.unreachable, 'keys no-handshake');
      return null;
    }
    final flags = await _flagsFor(h, base);
    if (flags == null) {
      _note(h, AgileIssue.unreachable, 'device_config no-reply');
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
    final hash = AgileCrypto.loginHash(password, flags);
    // كلمة السرّ تُعمّى RSA بمفتاح keys دائماً (`me()` في الواجهة)، والنموذج `password=…&operation=login` بلا confirm (لا نطرد من يفتح
    // صفحة الراوتر — «user conflict» ⇒ مشغول).
    final pwdEnc = AgileCrypto.rsaEncrypt(password, '${pwdKey[0]}', '${pwdKey[1]}');
    final form = 'password=$pwdEnc&operation=login';
    final signN = '${signKey[0]}', signE = '${signKey[1]}';
    final plain = flags.gdpr && isHttps(base);
    final String body;
    if (plain) {
      body = form; // GDPR عبر HTTPS: نموذجٌ صريح
    } else {
      final dataEnc = AgileCrypto.aesEncrypt(form, aesKey, aesIv); // العمليّة داخل المعمّى
      final sign = AgileCrypto.signature('k=$aesKey&i=$aesIv&h=$hash&s=${seq + dataEnc.length}',
          login: true, flags: flags, nHex: signN, eHex: signE, aesKey: aesKey, aesIv: aesIv);
      body = 'sign=$sign&data=${Uri.encodeQueryComponent(dataEnc)}';
    }
    final r = await _post(base, '/cgi-bin/luci/;stok=/login?form=login', body);
    if (r == null) {
      _note(h, AgileIssue.unreachable, 'login no-reply');
      return null;
    }
    final j = _json(r.body);
    final data = j?['data'];
    if (j?['success'] == true && (plain ? data is Map : data is String)) {
      try {
        final dec = plain ? <String, dynamic>{'stok': (data as Map)['stok']} : _json(AgileCrypto.aesDecrypt(data as String, aesKey, aesIv));
        final stok = dec?['stok'] ?? (dec?['data'] is Map ? (dec!['data'] as Map)['stok'] : null);
        if (stok is String && stok.isNotEmpty) {
          _rejected[h]?.remove(tag);
          _issues.remove(h);
          _fails.remove(h);
          _lockedUntil.remove(h);
          return AgileSession(
            host: h,
            stok: stok,
            aesKey: aesKey,
            aesIv: aesIv,
            seq: seq,
            hash: hash,
            flags: flags,
            signN: signN,
            signE: signE,
            cookie: r.cookie,
            plain: plain,
            model: await _modelFor(h, base),
          );
        }
      } catch (_) {/* فكّ فاشل ⇒ أسفل */}
      _note(h, AgileIssue.readFailed, 'login decrypt');
      return null;
    }
    // رمز الخطأ كما تطبّعه الواجهة (`Yl`): errorCode || error || error_code || errorcode، أو داخل data.
    String code(Object? m) => m is Map ? '${m['errorCode'] ?? m['error'] ?? m['error_code'] ?? m['errorcode'] ?? ''}' : '';
    final err = code(j).isNotEmpty ? code(j) : code(data);
    final dd = data is Map ? data : const <String, Object?>{};
    switch (err) {
      case 'login failed':
        (_rejected[h] ??= <String>{}).add(tag);
        final failed = TpAgileParse._int(dd['failureCount']);
        final left = TpAgileParse._int(dd['attemptsAllowed']);
        if (failed != null) _fails[h] = (failed: failed, left: left);
        _note(h, AgileIssue.rejected, 'login failed ${failed ?? '?'}/${left == null ? '?' : (failed ?? 0) + left}');
      case 'exceeded max attempts':
        _lockedUntil[h] = clock().add(const Duration(hours: 2)); // واجهة الجهاز: قفلٌ ساعتان
        _note(h, AgileIssue.locked, 'exceeded max attempts');
      case 'user conflict' || 'multiple login':
        _note(h, AgileIssue.busy, err); // أحدٌ داخل صفحة الراوتر — لا نطرده
      default:
        _note(h, AgileIssue.readFailed, err.isEmpty ? 'login status=${r.status}' : 'login $err [$flags]');
    }
    return null;
  }

  /// قراءةٌ مُعمّاة بجلسة كواجهة الجهاز: البيانات `operation=read`، seq ثابت، `h` = هاش الدخول أو SHA256(المعمّى)، والتوقيع RSA أو
  /// HMAC حسب [AgileFlags]، وكوكي الجلسة. ⇒ JSON (المفكوك) أو null.
  static Future<Map<String, dynamic>?> _read(AgileSession ss, String module, String form) async {
    final base = baseFor(ss.host);
    final cookie = ss.cookie.isEmpty ? null : {HttpHeaders.cookieHeader: ss.cookie};
    if (ss.plain) {
      final r = await _post(base, '/cgi-bin/luci/;stok=${ss.stok}/admin/$module?form=$form', 'operation=read', headers: cookie);
      if (r == null || r.status != 200) return null;
      return _json(r.body);
    }
    final dataEnc = AgileCrypto.aesEncrypt('operation=read', ss.aesKey, ss.aesIv);
    final hash = ss.flags.replaceHash ? AgileCrypto.sha256Hex(dataEnc) : ss.hash;
    final sign = AgileCrypto.signature('h=$hash&s=${ss.seq + dataEnc.length}',
        login: false, flags: ss.flags, nHex: ss.signN, eHex: ss.signE, aesKey: ss.aesKey, aesIv: ss.aesIv);
    final r = await _post(base, '/cgi-bin/luci/;stok=${ss.stok}/admin/$module?form=$form', 'sign=$sign&data=${Uri.encodeQueryComponent(dataEnc)}',
        headers: ss.cookie.isEmpty ? null : {HttpHeaders.cookieHeader: ss.cookie});
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

  /// قراءةٌ خام (لأدوات الفحص الحيّ وحدها).
  @visibleForTesting
  static Future<Map<String, dynamic>?> debugRead(AgileSession ss, String module, String form) => _read(ss, module, form);

  /// لقطة الراوتر: `/admin/status?form=all`. null ⇒ تعذّرت القراءة.
  static Future<UbiquitiStatus?> readStatus(AgileSession ss, {String model = ''}) async {
    final body = await _read(ss, 'status', 'all');
    if (body == null) {
      _note(ss.host, AgileIssue.readFailed, 'status');
      return null;
    }
    final snap = TpAgileParse.status(body, host: ss.host, model: model.isNotEmpty ? model : ss.model);
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
