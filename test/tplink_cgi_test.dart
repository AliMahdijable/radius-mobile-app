// راوتر TP-Link بواجهة CGI وتعمية GDPR (Archer C50 v4 — قِيس حيّاً ١٢ نوفمبر بدخولٍ واحدٍ لكلّ تجربة): RSA بلا حشو (قطعٌ ٦٤ حرفاً)،
// كوكي الجلسة ومسحه بـExpires 1970، وراوترٌ وهميّ محلّيّ بالقواعد المقيسة — أهمّها أنّ **الجهاز يربط الجلسة المعمّاة بالاتّصال**: قراءةٌ
// على اتّصالٍ غير اتّصال الدخول ⇒ 500 ومسح الكوكي (كان هذا سبب كلّ 500 قبل نقل الجلسة كلّها على اتّصالٍ محفوظ). قيمٌ وهميّة.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:rad_mysvcs/core/net/tplink_agile_service.dart' show AgileCrypto;
import 'package:rad_mysvcs/core/net/tplink_cgi_service.dart';

class _Rsa {
  late final String nHex, eHex;
  late final BigInt n, d;
  _Rsa() {
    final rng = SecureRandom('Fortuna')..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => (i * 11 + 5) & 0xff))));
    final gen = RSAKeyGenerator()..init(ParametersWithRandom(RSAKeyGeneratorParameters(BigInt.parse('65537'), 512, 64), rng));
    final pair = gen.generateKeyPair();
    final pub = pair.publicKey;
    final prv = pair.privateKey;
    n = pub.modulus!;
    d = prv.privateExponent!;
    nHex = n.toRadixString(16).toUpperCase();
    eHex = '010001';
  }

  /// فكّ RSA بلا حشو: كلّ قطعة ⇒ بايتاتها ⇒ تُسقط الأصفار الذيليّة.
  String decryptNoPad(String hex) {
    final keyLen = (n.bitLength + 7) >> 3;
    final out = StringBuffer();
    for (var i = 0; i + keyLen * 2 <= hex.length; i += keyLen * 2) {
      var m = BigInt.parse(hex.substring(i, i + keyLen * 2), radix: 16).modPow(d, n);
      final bytes = List<int>.filled(keyLen, 0);
      for (var j = keyLen - 1; j >= 0; j--) {
        bytes[j] = (m & BigInt.from(0xff)).toInt();
        m = m >> 8;
      }
      var end = bytes.length;
      while (end > 0 && bytes[end - 1] == 0) {
        end--;
      }
      out.write(utf8.decode(bytes.sublist(0, end)));
    }
    return out.toString();
  }
}

/// راوترٌ وهميّ بقواعد Archer C50 v4 المقيسة.
class _FakeC50 {
  _FakeC50(this.rsa);
  final _Rsa rsa;
  late HttpServer server;
  String user = 'admin';
  String pass = 'admin';
  final seq = 761011988;
  String? session; // الكوكي
  int? sessionPort; // اتّصال الدخول
  String? key, iv;
  int logins = 0, wrong = 0, logouts = 0, reads = 0, rejectedConn = 0;
  final ports = <int>{};

  String get host => '127.0.0.1:${server.port}';
  String get _hash => crypto.md5.convert(utf8.encode('$user$pass')).toString();

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final res = req.response;
      final body = await utf8.decoder.bind(req).join();
      final port = req.connectionInfo!.remotePort;
      String reply = '';
      if (req.method == 'GET' && req.uri.path == '/') {
        reply = '<html><script>var INCLUDE_LOGIN_GDPR_ENCRYPT=1;function PCSubWin(){\$.act(ACT_CGI,"/cgi/getParm");}</script></html>';
      } else if (req.uri.path == '/cgi' && body.contains('/cgi/getParm')) {
        reply = '[cgi]0\nvar ee="${rsa.eHex}";\nvar nn="${rsa.nHex}";\nvar seq="$seq";\n\$.ret=0;\n[error]0';
      } else if (req.uri.path == '/cgi_gdpr') {
        final m = RegExp(r'^sign=([0-9a-fA-F]+)\r\ndata=([^\r\n]+)\r\n$').firstMatch(body);
        if (m == null) {
          res.statusCode = 500;
        } else {
          final sig = rsa.decryptNoPad(m.group(1)!);
          final data = m.group(2)!;
          final sp = Uri.splitQueryString(sig);
          if (sp.containsKey('key')) {
            // دخول
            logins++;
            final k = sp['key']!, v = sp['iv']!;
            final plain = AgileCrypto.aesDecrypt(data, k, v);
            final ok = sp['h'] == _hash && sp['s'] == '${seq + data.length}' && plain.contains('[/cgi/login#') && plain.contains('username=$user\r\npassword=$pass\r\n');
            if (ok) {
              key = k;
              iv = v;
              session = 'S${Random().nextInt(1 << 30)}';
              sessionPort = port;
              ports.add(port);
              res.headers.add(HttpHeaders.setCookieHeader, 'JSESSIONID=$session; Path=/; HttpOnly');
              reply = AgileCrypto.aesEncrypt('[cgi]0\n\$.ret=0;\n[error]0', k, v);
            } else {
              wrong++;
              reply = AgileCrypto.aesEncrypt('[cgi]0\n\$.ret=71233;\n[error]71233', k, v);
            }
          } else {
            final cookie = RegExp(r'JSESSIONID=([^;]+)').firstMatch(req.headers.value(HttpHeaders.cookieHeader) ?? '')?.group(1);
            ports.add(port);
            if (session == null || cookie != session || port != sessionPort || sp['h'] != _hash || sp['s'] != '${seq + data.length}') {
              // كالجهاز: الجلسة مربوطةٌ بالاتّصال ⇒ 500 ومسح الكوكي
              rejectedConn++;
              session = null;
              res.statusCode = 500;
              res.headers.add(HttpHeaders.setCookieHeader, 'JSESSIONID=deleted; Expires=Thu, 01 Jan 1970 00:00:01 GMT; Path=/');
              reply = '<html><head><title>500 Internal Server Error</title></head></html>';
            } else {
              final plain = AgileCrypto.aesDecrypt(data, key!, iv!);
              if (plain.contains('/cgi/logout')) {
                logouts++;
                session = null;
                reply = AgileCrypto.aesEncrypt('[cgi]0\n\$.ret=0;\n[error]0', key!, iv!);
              } else {
                reads++;
                reply = AgileCrypto.aesEncrypt(
                    '[0,0,0,0,0,0]0\nmodelName=Archer C50\nhardwareVersion=Archer C50 v4 00000002\nsoftwareVersion=0.9.1 Build 190125\nupTime=2961394\n'
                    '[1,1,1,0,0,0]1\nenable=1\nconnectionStatus=Connected\nuptime=286037\nexternalIPAddress=100.66.1.221\n'
                    '[1,1,2,0,0,0]1\nenable=0\nconnectionStatus=Disconnected\nuptime=0\nexternalIPAddress=0.0.0.0\n'
                    '[1,1,1,0,0,0]2\nenable=1\nconnectionStatus=Connected\nuptime=0\nexternalIPAddress=169.254.1.2\naddressingType=Static\n'
                    '[1,0,0,0,0,0]3\nIPAddress=192.168.0.10\nMACAddress=AA:BB:CC:00:01:01\nhostName=Phone-A\nleaseTimeRemaining=600\n'
                    '[2,0,0,0,0,0]3\nIPAddress=192.168.0.11\nMACAddress=AA:BB:CC:00:01:02\nhostName=Laptop-B\nleaseTimeRemaining=600\n'
                    '[3,0,0,0,0,0]3\nIPAddress=192.168.0.12\nMACAddress=AA:BB:CC:00:01:03\nhostName=Wired-C\nleaseTimeRemaining=600\n'
                    '[1,1,1,0,0,0]4\nassociatedDeviceMACAddress=AA:BB:CC:00:01:01\n'
                    '[1,1,2,0,0,0]4\nassociatedDeviceMACAddress=AA:BB:CC:00:01:02\n'
                    '[error]0',
                    key!,
                    iv!);
              }
            }
          }
        }
      } else {
        res.statusCode = 404;
      }
      final bytes = utf8.encode(reply);
      res.headers.contentLength = bytes.length;
      res.add(bytes);
      await res.close();
    });
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  late _Rsa rsa;
  setUpAll(() => rsa = _Rsa());

  test('RSA بلا حشو كصفحة الجهاز: قطعٌ ٦٤ حرفاً، كلّ قطعةٍ هكسٌ بطول المفتاح، والفكّ يعيد النصّ', () {
    final text = 'key=1794444076123456&iv=1794444076654321&h=${'a' * 32}&s=761012140';
    final hex = TplinkCgiService.rsaNoPad(text, rsa.nHex, rsa.eHex);
    expect(hex.length, 2 * 128, reason: 'قطعتان (٩٠ حرفاً) × ١٢٨ هكس');
    expect(rsa.decryptNoPad(hex), text);
  });

  test('جرّة الكوكي: Set-Cookie منتهٍ (1970) يمسح الجلسة، وغيره يضعها ويستبدل القديم', () {
    expect(TplinkCgiService.mergeCookies('', ['JSESSIONID=abc; Path=/; HttpOnly']), 'JSESSIONID=abc');
    expect(TplinkCgiService.mergeCookies('JSESSIONID=abc', ['JSESSIONID=deleted; Expires=Thu, 01 Jan 1970 00:00:01 GMT; Path=/']), '');
    expect(TplinkCgiService.mergeCookies('JSESSIONID=abc; x=1', ['JSESSIONID=new']), 'JSESSIONID=new; x=1');
  });

  test('القراءة: PPP المتّصل يُفضَّل على اتّصال IP المحلّيّ، والمتّصلون من الوايرلس مُثرَون بـDHCP، والطراز بلا ذيله', () {
    final o = CgiParse.objects('[0,0,0,0,0,0]0\nmodelName=Archer C50\nhardwareVersion=Archer C50 v4 00000002\nupTime=5\n'
        '[1,1,1,0,0,0]1\nconnectionStatus=Connected\nuptime=99\n[1,0,0,0,0,0]3\nIPAddress=1.2.3.4\nMACAddress=aa:bb:cc:00:00:01\nhostName=X\n'
        '[1,1,1,0,0,0]4\nassociatedDeviceMACAddress=AA:BB:CC:00:00:01\n[error]0');
    final s = CgiParse.status(o, baseUrl: 'http://h')!;
    expect([s.vendor, s.model, s.wanOnlineSeconds, s.wanType, s.peerCount, s.dhcpCount, s.uptimeSeconds], ['tpcgi', 'Archer C50 v4', 99, 'PPPoE', 1, 1, 5]);
    expect(s.clients.single.name, 'X');
    expect(CgiParse.errorCode('[cgi]0\n[error]71233'), 71233);
    expect(CgiParse.vars('var nn="AB";\nvar seq="12";'), {'nn': 'AB', 'seq': '12'});
  });

  group('الراوتر الوهميّ (الجلسة مربوطةٌ بالاتّصال)', () {
    late _FakeC50 d;
    setUp(() async {
      TplinkCgiService.reset();
      d = _FakeC50(rsa);
      await d.start();
    });
    tearDown(() => d.stop());

    test('قراءةٌ كاملة على اتّصالٍ واحد: الدخول ثمّ القراءة ثمّ الخروج — والجهاز لا يردّ أيّاً بـ500', () async {
      expect(await TplinkCgiService.detect(d.host), isTrue);
      final u = await TplinkCgiService.readOnce(d.host, 'admin', 'admin');
      expect([u?.vendor, u?.model, u?.peerCount, u?.dhcpCount, u?.wanOnlineSeconds, u?.wanType], ['tpcgi', 'Archer C50 v4', 2, 3, 286037, 'PPPoE']);
      expect(u!.clients.map((c) => c.name).toList(), ['Phone-A', 'Laptop-B']);
      expect([d.logins, d.reads, d.logouts, d.rejectedConn], [1, 1, 1, 0]);
      expect(d.ports.length, 1, reason: 'كلّ طلبات الجلسة على اتّصالٍ واحد — اتّصالٌ جديدٌ لكلّ طلب ⇒ 500');
      expect(d.session, isNull, reason: 'الخروج دائماً');
    });

    test('كلمة سرٍّ غلط ⇒ رفضٌ يُحفظ (لا يُعاد)، و«نسيان» يعيده مرّة', () async {
      expect(await TplinkCgiService.readOnce(d.host, 'admin', 'wrong'), isNull);
      expect(TplinkCgiService.lastIssue(d.host)?.issue, CgiIssue.rejected);
      expect(await TplinkCgiService.readOnce(d.host, 'admin', 'wrong'), isNull);
      expect(d.wrong, 1, reason: 'عشرٌ غلط تقفل الصفحة ساعتين');
      TplinkCgiService.forget(d.host);
      expect(await TplinkCgiService.readOnce(d.host, 'admin', 'wrong'), isNull);
      expect(d.wrong, 2);
    });

    test('لا يجاوب ⇒ «غير واصل»', () async {
      final host = d.host;
      await d.stop();
      expect(await TplinkCgiService.readOnce(host, 'admin', 'admin'), isNull);
      expect(TplinkCgiService.lastIssue(host)?.issue, CgiIssue.unreachable);
    });
  });
}
