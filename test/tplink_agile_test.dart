// TP-Link «Agile» الحديث (Archer AX10 & kin): تعمية الدخول (RSA PKCS#1v1.5 مقسَّمة + AES-CBC + MD5) تُختبر بجهازٍ وهميّ loopback
// يطبّق **عكس** السكيم (يولّد زوج RSA، يفكّ التوقيع والبيانات وكلمة السرّ، يتحقّق، ويردّ stok مُعمّى) — فيثبت أنّ عميلنا والخادم
// يتقابلان بالضبط. والقارئ الصرف للحالة. لا جهازٌ حقيقيّ ولا اعتماداتٌ حقيقيّة هنا (التحقّق الحيّ بإدخال باسورد الجهاز في التطبيق).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:rad_mysvcs/core/net/tplink_agile_service.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/device_probe_card.dart' show deviceCopyFields;

/// زوج RSA صغير (768 بت — يجبر توقيع الدخول على كتلتين، فيختبر التقسيم) يُولَّد مرّةً.
class _Rsa {
  late final String nHex, eHex, dHex;
  _Rsa() {
    final rng = SecureRandom('Fortuna')..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3) & 0xff))));
    final gen = RSAKeyGenerator()..init(ParametersWithRandom(RSAKeyGeneratorParameters(BigInt.parse('65537'), 768, 64), rng));
    final pair = gen.generateKeyPair();
    final pub = pair.publicKey;
    final prv = pair.privateKey;
    nHex = pub.modulus!.toRadixString(16);
    eHex = pub.exponent!.toRadixString(16);
    dHex = prv.privateExponent!.toRadixString(16);
  }
}

/// جهاز Agile وهميّ: ينفّذ keys/auth/login/status بعكس تعميتنا.
class _FakeAgile {
  _FakeAgile(this.rsa);
  final _Rsa rsa;
  late HttpServer server;
  String password = 'router-pass';
  int seq = 400000;
  final sessions = <String, ({String key, String iv})>{};
  final paths = <String>[];
  int loginTries = 0, rejected = 0;

  String get host => '127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      paths.add('${req.method} ${req.uri.path}?${req.uri.query}');
      final raw = await utf8.decoder.bind(req).join();
      final form = req.uri.queryParameters['form'];
      final res = req.response;
      Map<String, Object?> out;
      if (form == 'keys') {
        out = {'success': true, 'data': {'password': [rsa.nHex, rsa.eHex], 'mode': 'router', 'username': ''}};
      } else if (form == 'auth') {
        out = {'success': true, 'data': {'key': [rsa.nHex, rsa.eHex], 'seq': seq}};
      } else if (form == 'login') {
        loginTries++;
        out = _login(raw);
      } else if (req.uri.path.contains('/admin/status')) {
        out = _status(req.uri.path, raw);
      } else {
        out = {'success': false};
      }
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(out));
      await res.close();
    });
  }

  Future<void> stop() => server.close(force: true);

  Map<String, String> _body(String raw) => {
        for (final kv in raw.split('&'))
          if (kv.contains('=')) kv.substring(0, kv.indexOf('=')): Uri.decodeQueryComponent(kv.substring(kv.indexOf('=') + 1))
      };

  Map<String, Object?> _login(String raw) {
    final b = _body(raw);
    final sign = AgileCrypto.rsaDecrypt(b['sign']!, rsa.nHex, rsa.dHex); // key=..&iv=..&h=..&s=..
    final sp = {for (final kv in sign.split('&')) kv.substring(0, kv.indexOf('=')): kv.substring(kv.indexOf('=') + 1)};
    final key = sp['key']!, iv = sp['iv']!;
    final dataPlain = AgileCrypto.aesDecrypt(b['data']!, key, iv); // password=<rsa>
    final pwdEnc = dataPlain.substring('password='.length);
    final pwd = AgileCrypto.rsaDecrypt(pwdEnc, rsa.nHex, rsa.dHex);
    if (pwd != password || sp['h'] != AgileCrypto.md5Hex(pwd)) {
      rejected++;
      return {'success': false, 'errorcode': 'login failed'};
    }
    final stok = 'STOK${sessions.length}ABC';
    sessions[stok] = (key: key, iv: iv);
    return {'success': true, 'data': AgileCrypto.aesEncrypt(jsonEncode({'stok': stok}), key, iv)};
  }

  Map<String, Object?> _status(String path, String raw) {
    final m = RegExp(r';stok=([^/]+)/').firstMatch(path);
    final ss = m == null ? null : sessions[m.group(1)];
    if (ss == null) return {'success': false};
    final payload = {
      'data': {
        'device_model': 'Archer AX10',
        'firmware_version': '1.3.0',
        'sys_uptime': 123456,
        'wan_ipv4_conntype': 'pppoe',
        'wan_ipv4_uptime': 15660,
        'access_devices_wireless_host': [{'mac': 'a'}, {'mac': 'b'}, {'mac': 'c'}, {'mac': 'd'}, {'mac': 'e'}],
        'access_devices_wired': [{'mac': 'w'}],
        'wan_ipv4_totaldata_down': 987654321,
        'wan_ipv4_totaldata_up': 123456789,
        'ssid_2g': 'MyWiFi',
      }
    };
    return {'success': true, 'data': AgileCrypto.aesEncrypt(jsonEncode(payload), ss.key, ss.iv)};
  }
}

void main() {
  group('تعمية السكيم (صرفة)', () {
    late _Rsa rsa;
    setUpAll(() => rsa = _Rsa());

    test('RSA PKCS#1v1.5 مقسَّمة: نصٌّ أطول من كتلة ⇒ كتلٌ متعدّدة تُعمّى وتُفكّ صحيحاً (حشوٌ عشوائيّ مختلف كلّ مرّة)', () {
      final keyLen = (rsa.nHex.length / 2).ceil(); // 96 بايت لـ768 بت
      final long = 'X' * (keyLen * 2); // ضعف الكتلة ⇒ ثلاث كتلٍ (maxChunk = keyLen−11)
      final a = AgileCrypto.rsaEncrypt(long, rsa.nHex, rsa.eHex);
      final b = AgileCrypto.rsaEncrypt(long, rsa.nHex, rsa.eHex);
      expect(a, isNot(b), reason: 'الحشو عشوائيّ');
      expect(AgileCrypto.rsaDecrypt(a, rsa.nHex, rsa.dHex), long);
      expect(a.length ~/ (keyLen * 2), 3, reason: 'ثلاث كتلٍ (maxChunk=${keyLen - 11})');
      // النصّ القصير (توقيع الدخول الفعليّ ~٨٤ محرفاً) = كتلةٌ واحدة
      final short = AgileCrypto.rsaEncrypt('key=1&iv=2&h=3&s=4', rsa.nHex, rsa.eHex);
      expect(short.length, keyLen * 2);
      expect(AgileCrypto.rsaDecrypt(short, rsa.nHex, rsa.dHex), 'key=1&iv=2&h=3&s=4');
    });

    test('AES-CBC round-trip بمفتاح/IV نصّيّين (١٦ رقماً)', () {
      final k = AgileCrypto.digits(16), iv = AgileCrypto.digits(16);
      expect(k.length, 16);
      final enc = AgileCrypto.aesEncrypt('password=deadbeef', k, iv);
      expect(AgileCrypto.aesDecrypt(enc, k, iv), 'password=deadbeef');
    });
  });

  group('الدخول عبر جهازٍ وهميّ (round-trip كامل)', () {
    late _Rsa rsa;
    late _FakeAgile d;
    setUpAll(() => rsa = _Rsa());
    setUp(() async {
      TplinkAgileService.reset();
      TplinkAgileService.baseFor = (h) => 'http://$h';
      d = _FakeAgile(rsa);
      await d.start();
    });
    tearDown(() async {
      TplinkAgileService.baseFor = (h) => 'https://$h';
      await d.stop();
    });

    test('التعرّف: مصافحة keys العامّة ⇒ هو (بلا اعتماد)', () async {
      expect(await TplinkAgileService.detect(d.host), isTrue);
      expect(d.loginTries, 0);
    });

    test('دخولٌ بكلمة السرّ الصحيحة ⇒ جلسة، ثمّ status ⇒ لقطة الراوتر (المتّصلون/مدّة الاتصال/النوع)', () async {
      final ss = await TplinkAgileService.login(d.host, 'router-pass');
      expect(ss, isNotNull);
      expect(ss!.stok, startsWith('STOK'));
      final u = await TplinkAgileService.readStatus(ss);
      expect([u?.vendor, u?.isRouter, u?.isTpClassic], ['tpagile', true, false]);
      expect(u?.peerCount, 6, reason: '٥ لاسلكيّ + ١ سلكيّ');
      expect(u?.wanOnlineSeconds, 15660);
      expect(u?.wanType, 'PPPoE');
      expect(u?.model, 'Archer AX10');
      expect([u?.rxBytes, u?.txBytes], [987654321, 123456789]);
      expect(u?.lanHealth, 'unknown', reason: 'راوترٌ بلا منافذ ⇒ لا إنذار أحمر');
    });

    test('readOnce = دخول + قراءة بخطوة', () async {
      final u = await TplinkAgileService.readOnce(d.host, 'router-pass');
      expect(u?.peerCount, 6);
    });

    test('كلمة سرٍّ غلط ⇒ null + rejected محفوظ (لا يُعاد)، واعتمادٌ آخر يُجرَّب، و«نسيان» يعيده', () async {
      expect(await TplinkAgileService.login(d.host, 'wrong'), isNull);
      expect(TplinkAgileService.lastIssue(d.host)?.issue, AgileIssue.rejected);
      expect(d.rejected, 1);
      expect(await TplinkAgileService.login(d.host, 'wrong'), isNull);
      expect(d.loginTries, 1, reason: 'المرفوض لا يُرسل ثانيةً');
      expect(await TplinkAgileService.login(d.host, 'router-pass'), isNotNull, reason: 'اعتمادٌ آخر يُجرَّب');
      TplinkAgileService.forget(d.host);
      expect(await TplinkAgileService.login(d.host, 'wrong'), isNull);
      expect(d.rejected, 2, reason: '«حفظ وفحص» يعيد المرفوض مرّة');
    });

    test('جهازٌ لا يجاوب ⇒ unreachable', () async {
      final host = d.host;
      await d.stop();
      expect(await TplinkAgileService.login(host, 'router-pass'), isNull);
      expect(TplinkAgileService.lastIssue(host)?.issue, AgileIssue.unreachable);
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
