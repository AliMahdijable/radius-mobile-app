// TP-Link «Agile» الحديث (Archer AX10 & kin) — السكيم منقولٌ من واجهة الجهاز نفسه (١١ نوفمبر ليلاً): جهازٌ وهميّ loopback بأوضاعه
// الثلاثة كما في `update-store-*.js`: قديم (PKCS#1 v1.5 + MD5)، صارمٌ عبر HTTP (شهادات EU CE RED/SG ⇒ OAEP + SHA256 + HMAC بعد
// الدخول + هاشٌ بديل)، وصارمٌ عبر HTTPS (GDPR ⇒ نموذجٌ صريح بلا AES ولا توقيع — هكذا راوتر المشترك). يفكّ ما نرسله فعلاً ويتحقّق
// منه، ويعدّ الرفض كالجهاز (failureCount/attemptsAllowed، ١٠ ثمّ قفل). لا جهازٌ حقيقيّ ولا اعتماداتٌ حقيقيّة هنا.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:rad_mysvcs/core/net/tplink_agile_service.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/device_probe_card.dart' show deviceCopyFields;

/// زوج RSA صغير (768 بت: ٩٦ بايتاً — يسع قطعة توقيعٍ ٥٣ محرفاً بـOAEP، حدّها ٥٤) يُولَّد مرّةً.
class _Rsa {
  late final String nHex, eHex, dHex;
  late final RSAPrivateKey prv;
  _Rsa() {
    final rng = SecureRandom('Fortuna')..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3) & 0xff))));
    final gen = RSAKeyGenerator()..init(ParametersWithRandom(RSAKeyGeneratorParameters(BigInt.parse('65537'), 768, 64), rng));
    final pair = gen.generateKeyPair();
    final pub = pair.publicKey;
    prv = pair.privateKey;
    nHex = pub.modulus!.toRadixString(16);
    eHex = pub.exponent!.toRadixString(16);
    dHex = prv.privateExponent!.toRadixString(16);
  }

  int get keyLen => (BigInt.parse(nHex, radix: 16).bitLength + 7) >> 3;

  /// فكّ كتل OAEP (SHA-1) — كما يفعل الجهاز بقطع التوقيع.
  String oaepDecrypt(String hex) {
    final c = OAEPEncoding(RSAEngine())..init(false, PrivateKeyParameter<RSAPrivateKey>(prv));
    final out = <int>[];
    for (var i = 0; i < hex.length; i += keyLen * 2) {
      final block = hex.substring(i, i + keyLen * 2);
      final bytes = Uint8List.fromList([for (var j = 0; j < block.length; j += 2) int.parse(block.substring(j, j + 2), radix: 16)]);
      out.addAll(c.process(bytes));
    }
    return utf8.decode(out);
  }
}

enum _Mode { legacy, strictHttp, strictHttps }

/// جهاز Agile وهميّ بقواعد الجهاز الحقيقيّ.
class _FakeAgile {
  _FakeAgile(this.rsa, {this.mode = _Mode.legacy});
  final _Rsa rsa;
  final _Mode mode;
  late HttpServer server;
  String password = 'router-pass';
  int seq = 400000;
  int failureCount = 0;
  bool userConflict = false;
  final sessions = <String, ({String key, String iv, String hash, String cookie})>{};
  final paths = <String>[];
  int loginTries = 0, rejected = 0;
  String lastLoginBody = '';
  String lastReadBody = '';

  String get host => '127.0.0.1:${server.port}';
  bool get strict => mode != _Mode.legacy;

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      paths.add('${req.method} ${req.uri.path}?${req.uri.query}');
      final raw = await utf8.decoder.bind(req).join();
      final form = req.uri.queryParameters['form'];
      final res = req.response;
      Map<String, Object?> out;
      if (form == 'keys') {
        out = {
          'success': true,
          'data': {
            'password': [rsa.nHex, rsa.eHex],
            'mode': 'router',
            'username': ''
          }
        };
      } else if (form == 'auth') {
        out = {
          'success': true,
          'data': {
            'key': [rsa.nHex, rsa.eHex],
            'seq': seq
          }
        };
      } else if (form == 'get_deviceInfo') {
        out = {
          'success': true,
          'data': {'model': 'Archer AX10'}
        };
      } else if (req.uri.path.contains('/device_config')) {
        out = strict
            ? {
                'success': true,
                'data': {
                  'certification': ['EU CE', 'EU CE RED', 'SG CLS L1 STAGE2']
                }
              }
            : {'success': false, 'errorcode': 'no such callback'}; // فيرموير أقدم بلا هذا المسار
      } else if (form == 'login') {
        loginTries++;
        lastLoginBody = raw;
        out = _login(raw, res);
      } else if (req.uri.path.contains('/admin/status')) {
        lastReadBody = raw;
        out = _status(req.uri.path, raw, req.headers.value(HttpHeaders.cookieHeader) ?? '');
      } else {
        out = {'success': false, 'errorcode': 'no such callback'};
      }
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(out));
      await res.close();
    });
  }

  Future<void> stop() => server.close(force: true);

  Map<String, String> _form(String raw) => {
        for (final kv in raw.split('&'))
          if (kv.contains('=')) kv.substring(0, kv.indexOf('=')): Uri.decodeQueryComponent(kv.substring(kv.indexOf('=') + 1))
      };

  String _hash(String pwd) => strict ? AgileCrypto.sha256Hex('admin$pwd') : AgileCrypto.md5Hex('admin$pwd');

  Map<String, Object?> _fail() {
    failureCount++;
    rejected++;
    if (failureCount >= 10) return {'success': false, 'errorcode': 'exceeded max attempts', 'data': {}};
    return {
      'success': false,
      'errorcode': 'login failed',
      'data': {'failureCount': failureCount, 'attemptsAllowed': 10 - failureCount, 'remainTime': 2}
    };
  }

  Map<String, Object?> _login(String raw, HttpResponse res) {
    if (failureCount >= 10) return {'success': false, 'errorcode': 'exceeded max attempts', 'data': {}};
    final b = _form(raw);
    String? pwdEnc;
    ({String key, String iv})? aes;
    if (mode == _Mode.strictHttps) {
      // GDPR عبر HTTPS: حقولٌ صريحة — لا operation ⇒ «no such callback»، ولا password ⇒ رفض (هكذا ردّ الراوتر الحقيقيّ قبل الإصلاح)
      if (b['operation'] != 'login') return {'success': false, 'errorcode': 'no such callback'};
      pwdEnc = b['password'];
    } else {
      final signHex = b['sign'] ?? '';
      final sign = strict ? rsa.oaepDecrypt(signHex) : AgileCrypto.rsaDecrypt(signHex, rsa.nHex, rsa.dHex);
      final sp = {
        for (final kv in sign.split('&'))
          if (kv.contains('=')) kv.substring(0, kv.indexOf('=')): kv.substring(kv.indexOf('=') + 1)
      };
      final k = sp['k'], i = sp['i'];
      if (k == null || i == null) return {'success': false, 'errorcode': 'no such callback'}; // لا مفتاح ⇒ لا فكّ ⇒ لا توجيه
      final dataB64 = b['data'] ?? '';
      if (sp['s'] != '${seq + dataB64.length}') return {'success': false, 'errorcode': 'no such callback'};
      final inner = _form(AgileCrypto.aesDecrypt(dataB64, k, i));
      if (inner['operation'] != 'login') return {'success': false, 'errorcode': 'no such callback'};
      pwdEnc = inner['password'];
      aes = (key: k, iv: i);
      if (pwdEnc != null && sp['h'] != _hash(AgileCrypto.rsaDecrypt(pwdEnc, rsa.nHex, rsa.dHex))) return _fail();
    }
    if (pwdEnc == null || AgileCrypto.rsaDecrypt(pwdEnc, rsa.nHex, rsa.dHex) != password) return _fail();
    if (userConflict) return {'success': false, 'errorcode': 'user conflict', 'data': {}};
    failureCount = 0;
    final stok = 'STOK${sessions.length}ABC';
    final cookie = 'sysauth=SA${sessions.length}';
    res.headers.add(HttpHeaders.setCookieHeader, '$cookie; path=/cgi-bin/luci; HttpOnly');
    sessions[stok] = (key: aes?.key ?? '', iv: aes?.iv ?? '', hash: _hash(password), cookie: cookie);
    if (mode == _Mode.strictHttps) {
      return {
        'success': true,
        'data': {'stok': stok}
      };
    }
    return {
      'success': true,
      'data': AgileCrypto.aesEncrypt(jsonEncode({'stok': stok}), aes!.key, aes.iv)
    };
  }

  static const _payload = {
    'device_model': 'Archer AX10',
    'firmware_version': '1.3.0',
    'sys_uptime': 123456,
    'wan_ipv4_conntype': 'pppoe',
    'wan_ipv4_uptime': 15660,
    'access_devices_wireless_host': [
      {'mac': 'AA-01', 'ipaddr': '192.168.0.11', 'hostname': 'Galaxy'},
      {'mac': 'AA-02', 'ip': '192.168.0.12', 'name': 'iPhone'},
      {'mac': 'AA-03'},
      {'mac': 'AA-04'},
      {'mac': 'AA-05'},
    ],
    'access_devices_wired': [
      {'macaddr': 'WW-01', 'ipaddr': '192.168.0.20', 'hostname': 'PC'}
    ],
    'wan_ipv4_totaldata_down': 987654321,
    'wan_ipv4_totaldata_up': 123456789,
    'ssid_2g': 'MyWiFi',
  };

  Map<String, Object?> _status(String path, String raw, String cookie) {
    final m = RegExp(r';stok=([^/]+)/').firstMatch(path);
    final ss = m == null ? null : sessions[m.group(1)];
    if (ss == null || !cookie.contains(ss.cookie)) return {'success': false, 'errorcode': 'timeout'};
    if (mode == _Mode.strictHttps) {
      if (raw != 'operation=read') return {'success': false, 'errorcode': 'no such callback'};
      // كفيرموير راوتر المشترك: بلا device_model ولا عدّادات wan (الموديل من get_deviceInfo، والترافيك غير معروف لا صفر)
      final real = Map<String, Object?>.from(_payload)
        ..remove('device_model')
        ..remove('firmware_version')
        ..remove('wan_ipv4_totaldata_down')
        ..remove('wan_ipv4_totaldata_up');
      return {'success': true, 'data': real};
    }
    final b = _form(raw);
    final dataB64 = b['data'] ?? '';
    final signHex = b['sign'] ?? '';
    if (strict) {
      // GDPR: HMAC-SHA256 لقطع «h=SHA256(المعمّى)&s=…» بمفتاح «k=…&i=…»
      final plain = 'h=${AgileCrypto.sha256Hex(dataB64)}&s=${seq + dataB64.length}';
      final want = StringBuffer();
      for (var i = 0; i < plain.length; i += 53) {
        want.write(AgileCrypto.hmacSha256Hex(plain.substring(i, i + 53 > plain.length ? plain.length : i + 53), 'k=${ss.key}&i=${ss.iv}'));
      }
      if (signHex != want.toString()) return {'success': false, 'errorcode': 'timeout'};
    } else {
      final sign = AgileCrypto.rsaDecrypt(signHex, rsa.nHex, rsa.dHex);
      if (sign != 'h=${ss.hash}&s=${seq + dataB64.length}') return {'success': false, 'errorcode': 'timeout'};
    }
    if (AgileCrypto.aesDecrypt(dataB64, ss.key, ss.iv) != 'operation=read') return {'success': false, 'errorcode': 'no such callback'};
    return {
      'success': true,
      'data': AgileCrypto.aesEncrypt(jsonEncode({'success': true, 'data': _payload}), ss.key, ss.iv)
    };
  }
}

void _expectSnapshot(UbiquitiStatus? u, {bool realFirmware = false}) {
  expect([u?.vendor, u?.isRouter, u?.isTpClassic], ['tpagile', true, false]);
  expect(u?.peerCount, 6, reason: '٥ لاسلكيّ + ١ سلكيّ');
  expect(u?.clients.length, 6);
  expect([u?.clients[0].mac, u?.clients[0].ip, u?.clients[0].name, u?.clients[0].wired], ['AA-01', '192.168.0.11', 'Galaxy', false]);
  expect([u?.clients[1].ip, u?.clients[1].name], ['192.168.0.12', 'iPhone'], reason: 'حقول ip/name البديلة');
  expect([u?.clients[2].ip, u?.clients[2].name], [null, null], reason: 'ماك وحده ⇒ بلا آيبي/اسم (لا قيمٌ كاذبة)');
  expect([u?.clients[5].mac, u?.clients[5].wired], ['WW-01', true], reason: 'السلكيّ');
  expect(u?.wanOnlineSeconds, 15660);
  expect(u?.wanType, 'PPPoE');
  expect(u?.model, 'Archer AX10');
  expect([u?.rxBytes, u?.txBytes], realFirmware ? [null, null] : [987654321, 123456789], reason: 'بلا عدّادٍ ⇒ غير معروف لا صفر');
  expect(u?.lanHealth, 'unknown', reason: 'راوترٌ بلا منافذ ⇒ لا إنذار أحمر');
}

void main() {
  group('تعمية السكيم (صرفة)', () {
    late _Rsa rsa;
    setUpAll(() => rsa = _Rsa());

    test('RSA PKCS#1v1.5 مقسَّمة: نصٌّ أطول من كتلة ⇒ كتلٌ متعدّدة تُعمّى وتُفكّ صحيحاً (حشوٌ عشوائيّ مختلف كلّ مرّة)', () {
      final keyLen = rsa.keyLen;
      final long = 'X' * (keyLen * 2);
      final a = AgileCrypto.rsaEncrypt(long, rsa.nHex, rsa.eHex);
      final b = AgileCrypto.rsaEncrypt(long, rsa.nHex, rsa.eHex);
      expect(a, isNot(b), reason: 'الحشو عشوائيّ');
      expect(AgileCrypto.rsaDecrypt(a, rsa.nHex, rsa.dHex), long);
      expect(a.length ~/ (keyLen * 2), 3, reason: 'ثلاث كتلٍ (maxChunk=${keyLen - 11})');
    });

    test('RSA-OAEP (SHA-1) ⇒ يفكّه الطرف الآخر بـOAEP، وحشوٌ عشوائيّ', () {
      final a = AgileCrypto.rsaOaepEncrypt('k=1&i=2&h=3&s=4', rsa.nHex, rsa.eHex);
      expect(a, isNot(AgileCrypto.rsaOaepEncrypt('k=1&i=2&h=3&s=4', rsa.nHex, rsa.eHex)));
      expect(a.length, rsa.keyLen * 2);
      expect(rsa.oaepDecrypt(a), 'k=1&i=2&h=3&s=4');
    });

    test('التوقيع كواجهة الجهاز: قطعٌ من ٥٣ محرفاً — RSA للدخول، وHMAC-SHA256 بعده في GDPR', () {
      const flags = AgileFlags(sha256: true, oaep: true, gdpr: true, replaceHash: true);
      final plain = 'k=1234567890123456&i=6543210987654321&h=${'a' * 64}&s=400123'; // ١١٨ محرفاً ⇒ ٣ قطع
      final sig = AgileCrypto.signature(plain, login: true, flags: flags, nHex: rsa.nHex, eHex: rsa.eHex, aesKey: 'x', aesIv: 'y');
      expect(sig.length, 3 * rsa.keyLen * 2);
      expect(rsa.oaepDecrypt(sig), plain);
      final after = AgileCrypto.signature('h=${'b' * 64}&s=1', login: false, flags: flags, nHex: rsa.nHex, eHex: rsa.eHex, aesKey: 'K', aesIv: 'I');
      expect(after, AgileCrypto.hmacSha256Hex('h=${'b' * 51}', 'k=K&i=I') + AgileCrypto.hmacSha256Hex('${'b' * 13}&s=1', 'k=K&i=I'));
      // القديم: PKCS#1 v1.5 للقطعتين
      final legacy = AgileCrypto.signature(plain, login: true, flags: AgileFlags.legacy, nHex: rsa.nHex, eHex: rsa.eHex, aesKey: 'x', aesIv: 'y');
      expect(AgileCrypto.rsaDecrypt(legacy, rsa.nHex, rsa.dHex), plain);
    });

    test('هاش الدخول = "admin"+كلمة السرّ (SHA256 أو MD5)، والميزات من شهادات الجهاز كـFEATURE_MAP', () {
      expect(AgileCrypto.loginHash('p', AgileFlags.legacy), AgileCrypto.md5Hex('adminp'));
      expect(AgileCrypto.loginHash('p', const AgileFlags(sha256: true)), AgileCrypto.sha256Hex('adminp'));
      final sub = AgileFlags.fromCertification(['EU CE', 'EU CE RED', 'SG CLS L1 STAGE2']); // راوتر المشترك 10.5.50.24
      expect([sub.sha256, sub.oaep, sub.gdpr, sub.replaceHash], [true, true, true, true]);
      final red = AgileFlags.fromCertification(['EU CE RED']);
      expect([red.sha256, red.oaep, red.gdpr, red.replaceHash], [true, false, true, false]);
      final rg = AgileFlags.fromCertification(['IMDA TS RG-SEC']);
      expect([rg.sha256, rg.oaep, rg.gdpr, rg.replaceHash], [true, false, false, false]);
      expect(AgileFlags.fromCertification(['EU CE', 'US FCC']).toString(), 'legacy');
    });

    test('AES-CBC round-trip بمفتاح/IV نصّيّين (١٦ رقماً)', () {
      final k = AgileCrypto.digits(16), iv = AgileCrypto.digits(16);
      expect(k.length, 16);
      final enc = AgileCrypto.aesEncrypt('password=deadbeef', k, iv);
      expect(AgileCrypto.aesDecrypt(enc, k, iv), 'password=deadbeef');
    });
  });

  group('الدخول عبر جهازٍ وهميّ (round-trip كامل بالأوضاع الثلاثة)', () {
    late _Rsa rsa;
    late _FakeAgile d;
    setUpAll(() => rsa = _Rsa());
    Future<void> boot(_Mode mode) async {
      TplinkAgileService.reset();
      TplinkAgileService.baseFor = (h) => 'http://$h';
      TplinkAgileService.isHttps = (_) => mode == _Mode.strictHttps;
      d = _FakeAgile(rsa, mode: mode);
      await d.start();
    }

    tearDown(() async {
      TplinkAgileService.baseFor = (h) => 'https://$h';
      TplinkAgileService.isHttps = (b) => b.startsWith('https:');
      TplinkAgileService.clock = DateTime.now;
      await d.stop();
    });

    test('التعرّف: مصافحة keys العامّة ⇒ هو (بلا اعتماد)', () async {
      await boot(_Mode.legacy);
      expect(await TplinkAgileService.detect(d.host), isTrue);
      expect(d.loginTries, 0);
    });

    test('قديم (بلا شهادات): k/i + MD5("admin"+…) + PKCS#1، العمليّة داخل المعمّى ⇒ جلسة ثمّ لقطة', () async {
      await boot(_Mode.legacy);
      final ss = await TplinkAgileService.login(d.host, 'router-pass');
      expect(ss, isNotNull, reason: '${TplinkAgileService.lastIssue(d.host)}');
      expect(TplinkAgileService.flagsOf(d.host).toString(), 'legacy');
      expect(d.lastLoginBody, startsWith('sign='));
      expect(d.lastLoginBody, isNot(contains('operation=')), reason: 'العمليّة داخل المعمّى لا ظاهرة');
      _expectSnapshot(await TplinkAgileService.readStatus(ss!));
    });

    test('صارمٌ عبر HTTP (EU CE RED + SG): OAEP + SHA256 للدخول، ثمّ HMAC + هاشٌ بديل للقراءة', () async {
      await boot(_Mode.strictHttp);
      final ss = await TplinkAgileService.login(d.host, 'router-pass');
      expect(ss, isNotNull, reason: '${TplinkAgileService.lastIssue(d.host)}');
      expect(TplinkAgileService.flagsOf(d.host).toString(), 'sha256+oaep+gdpr+replaceHash');
      _expectSnapshot(await TplinkAgileService.readStatus(ss!));
      expect(d.lastReadBody, startsWith('sign='));
    });

    test('صارمٌ عبر HTTPS (راوتر المشترك): نموذجٌ صريح password=<RSA>&operation=login بلا AES ولا توقيع، وكوكي الجلسة للقراءة', () async {
      await boot(_Mode.strictHttps);
      final u = await TplinkAgileService.readOnce(d.host, 'router-pass');
      expect(d.lastLoginBody, matches(RegExp(r'^password=[0-9a-f]+&operation=login$')), reason: 'بلا confirm ولا sign/data');
      expect(d.lastReadBody, 'operation=read');
      _expectSnapshot(u, realFirmware: true); // الموديل «Archer AX10» من get_deviceInfo
    });

    test('كلمة سرٍّ غلط ⇒ rejected محفوظ بعدّاد الجهاز (لا يُعاد)، واعتمادٌ آخر يُجرَّب، و«نسيان» يعيده', () async {
      await boot(_Mode.strictHttps);
      expect(await TplinkAgileService.login(d.host, 'wrong'), isNull);
      expect(TplinkAgileService.lastIssue(d.host)?.issue, AgileIssue.rejected);
      expect(TplinkAgileService.lastIssue(d.host)?.trace, 'login failed 1/10');
      expect(TplinkAgileService.failsOf(d.host)?.failed, 1);
      expect(await TplinkAgileService.login(d.host, 'wrong'), isNull);
      expect(d.loginTries, 1, reason: 'المرفوض لا يُرسل ثانيةً');
      expect(await TplinkAgileService.login(d.host, 'router-pass'), isNotNull, reason: 'اعتمادٌ آخر يُجرَّب');
      expect(TplinkAgileService.failsOf(d.host), isNull, reason: 'النجاح يصفّر العدّاد');
      TplinkAgileService.forget(d.host);
      expect(await TplinkAgileService.login(d.host, 'wrong'), isNull);
      expect(d.rejected, 2, reason: '«حفظ وفحص» يعيد المرفوض مرّة');
    });

    test('حارس العدّاد: عند ٥ رفضات لا دخول تلقائيّ (بلا طلب)، و«حفظ وفحص» يسمح حتى ٨', () async {
      await boot(_Mode.strictHttps);
      d.failureCount = 4;
      expect(await TplinkAgileService.login(d.host, 'wrong1'), isNull); // ⇒ ٥
      expect(TplinkAgileService.failsOf(d.host)?.failed, 5);
      final tries = d.loginTries;
      expect(await TplinkAgileService.login(d.host, 'router-pass'), isNull);
      expect(TplinkAgileService.lastIssue(d.host)?.issue, AgileIssue.locked);
      expect(d.loginTries, tries, reason: 'لا طلب دخول — يبقى للإنسان ما يدخل به');
      TplinkAgileService.forget(d.host, manual: true);
      expect(await TplinkAgileService.login(d.host, 'router-pass'), isNotNull, reason: '«حفظ وفحص» ⇒ العتبة ٨');
    });

    test('«user conflict» (أحدٌ في صفحة الراوتر) ⇒ busy، لا يُحفظ رفضاً ولا confirm يطرده', () async {
      await boot(_Mode.strictHttps);
      d.userConflict = true;
      expect(await TplinkAgileService.login(d.host, 'router-pass'), isNull);
      expect(TplinkAgileService.lastIssue(d.host)?.issue, AgileIssue.busy);
      expect(d.lastLoginBody, isNot(contains('confirm')));
      d.userConflict = false;
      expect(await TplinkAgileService.login(d.host, 'router-pass'), isNotNull, reason: 'لم يُحفظ رفضاً');
    });

    test('«exceeded max attempts» ⇒ locked ساعتين بلا أيّ طلب، ثمّ يُسمح', () async {
      await boot(_Mode.strictHttps);
      var now = DateTime(2026, 11, 11, 22);
      TplinkAgileService.clock = () => now;
      d.failureCount = 10;
      expect(await TplinkAgileService.login(d.host, 'router-pass'), isNull);
      expect(TplinkAgileService.lastIssue(d.host)?.issue, AgileIssue.locked);
      final tries = d.loginTries;
      now = now.add(const Duration(minutes: 90));
      expect(await TplinkAgileService.login(d.host, 'router-pass'), isNull);
      expect(d.loginTries, tries, reason: 'داخل الساعتين لا طلب');
      now = now.add(const Duration(minutes: 31));
      d.failureCount = 0;
      expect(await TplinkAgileService.login(d.host, 'router-pass'), isNotNull);
    });

    test('جهازٌ لا يجاوب ⇒ unreachable', () async {
      await boot(_Mode.legacy);
      final host = d.host;
      await d.stop();
      expect(await TplinkAgileService.login(host, 'router-pass'), isNull);
      expect(TplinkAgileService.lastIssue(host)?.issue, AgileIssue.unreachable);
      d = _FakeAgile(rsa);
      await d.start();
    });
  });

  group('قراءة الحالة (صرفة)', () {
    test('status ⇒ المتّصلون من القوائم، النوع، المدّة؛ وحقول «نسخ» بلا إشارة', () {
      final body = {
        'data': {
          'device_model': 'Archer AX10',
          'wan_ipv4_conntype': 'pppoe',
          'wan_ipv4_uptime': 3600,
          'access_devices_wireless_host': [{}, {}],
          'access_devices_wired': [{}],
        }
      };
      final u = TpAgileParse.status(body, host: '10.5.50.24')!;
      expect([u.vendor, u.isRouter, u.peerCount, u.wanOnlineSeconds, u.wanType], ['tpagile', true, 3, 3600, 'PPPoE']);
      final f = deviceCopyFields(DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.5.50.24', ubnt: u));
      final map = {for (final x in f) x.label: x.value};
      expect(map['نوع الجهاز'], 'راوتر TP-Link Archer AX10');
      expect(map['المتّصلون الآن'], '3');
      expect(map.containsKey('الإشارة'), isFalse);
    });

    test('بلا data ⇒ null (لا لقطةٌ كاذبة)', () {
      expect(TpAgileParse.status({'success': false}, host: 'x'), isNull);
    });
  });
}
