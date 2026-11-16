// راوتر TP-Link الكلاسيكيّ بالفيرموير المعمّى (TL-WR940N أحدث — مشتركٌ بالإدارة عن بعد :8080، ١٦ نوفمبر). المالك بلقطة كرت المشترك
// «الجهاز يستجيب بس تعذّرت قراءته» وصفحة الراوتر: «ليش مجاي يفتح شوفلي شنو مشكله». السبب: صفحة الدخول ما زالت تحمل httpAutErrorArray
// فكان يُرسل له دخول الكوكي-MD5 القديم (LoginRpm.htm?Save=Save) ولا يدخل أبداً، وسكربتها في الحقيقة: getRsa.json ⇒ login.json بتعمية
// AES-128-CBC وتوقيع RSA PKCS#1 v1.5، والصفحات تحت /<sessionId>/userRpm/ وبياناتها نصوصٌ معمّاة بمفتاح الجلسة نفسه.
// المتّجهات من سكربت الجهاز نفسه (cryptoJS + dynaform_encrypt + tpEncrypt + encryptData في vm معزول) بمفتاح RSA اختباريّ — والجهاز
// الوهميّ هنا يفكّ ما نرسله بالمفتاح الخاصّ ويتحقّق منه كما يفعل الراوتر.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/core/net/router_types.dart';
import 'package:rad_mysvcs/core/net/tplink_agile_service.dart';
import 'package:rad_mysvcs/core/net/tplink_classic_service.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _realm = 'TP-Link Wireless N Router WR940N';

// مفتاح RSA اختباريّ (512 بتّاً، مولَّدٌ للاختبار وحده)
const _n = 'b79ddd418ac13a616664d882a55de44905e031e5d69ba4a322b2193a5f6f5fcf5f3cd1663d8527b80bbb57e13d3c5647b44335525725f95cd97e0f40c6ddf81b';
const _e = '10001';
const _d = '9730827db44dd4cf5c6b8f274c18da9f121a7f9b9bb13ec8210a7ae168b1a1360f2ed95fe2d56ad7f23878d009fb246e28f0448f14e52468bf60e374f7b2f049';
const _seq = 56630;

/// صفحة الدخول بشكلها الحيّ (مختصرة): الحالة، ونموذج LoginRpm، وسكربت getRsa/login.json.
String _loginPage(int state, String host) => '''
<SCRIPT language="javascript" type="text/javascript">
var httpAutErrorArray = new Array(
$state, 1, "http://$host", 0,0 );
</SCRIPT>
<script type="text/javascript">
function encrypt(username, password){ ajax({ url: "../login/getRsa.json", success: function(ret){ ajax({ url: "../login/login.json" }); } }); }
</script>
<form action="/userRpm/LoginRpm.htm" method="get" id="loginForm"></form>''';

const _status = 'var statusPara=new Array(1, 1, 22, 20000, 647566, "3.18.1 Build 171030 Rel.43957n ", "WR940N v6 00000000", 1, 0, 3, 0, 0 );'
    'var wanPara=new Array(4, "AA-BB-CC-00-00-03", "100.66.1.177", 3, "255.255.255.255", 0, 0, "100.66.0.1", 0, 1, 0, "8.8.8.8 , 1.1.1.1", '
    '"3 day(s) 06:35:55", 1, 0, "0.0.0.0", "0.0.0.0", 0, 0, 0, 0, 0, 0, 0 );'
    'wlanPara=new Array(1, "TestWiFi", 15, 6, "AA-BB-CC-00-00-02", "192.168.42.1", 2, 8, 83, 4, 6, "", "", "", 1, 0, 2, 0, "", 0 );'
    'var statistList=new Array("4,266,809,196", "3,856,716,550", "169,115,305", "65,240,934", 0, 0 );';
const _wlan = 'var wlanHostPara=new Array(1, 1, 8, 5000, 5, 0, 0, 1, 0, 0, 0 );var hostList=new Array("AA-BB-CC-00-01-01", 1, 1944002, 2040364, 2, 0,0 );';
const _dhcp = 'var DHCPDynList=new Array("Laptop-A", "AA-BB-CC-00-02-01", "192.168.42.109", "01:56:28", "Phone-C", "AA-BB-CC-00-01-01", '
    '"192.168.42.101", "01:49:35", 0,0 );var DHCPDynPara=new Array(2, 4, 0, 0 );';

/// صفحة بيانات كما يرسلها الفيرموير المعمّى: النصّ معمّى بمفتاح الجلسة في متغيّرٍ يسمّيه عنصر encryptedData.
String _encPage(String plain, String key, String iv) => '''
<span name="encryptedData" data-name="pageData"></span>
<script type="text/javascript">var pageData="${AgileCrypto.aesEncrypt(plain, key, iv)}";</script>
<script type="text/javascript">var connection=getElesByName(document, "encryptedData");</script>
<HTML><BODY>page</BODY></HTML>''';

/// راوترٌ وهميّ بقواعد الفيرموير المعمّى المقروءة من سكربته.
class _FakeRsa {
  late HttpServer server;
  String pass = 'p@ss word';
  int state = 3; // 3 جاهز · 2 الأخيرة خطأ · 1 مقفل · 0 مديرٌ آخر
  String? sid;
  String? key;
  String? iv;
  int logins = 0;
  int logouts = 0;
  int wrong = 0;
  bool resetStateAfterWrong = false; // بعض الفيرموَيرات قد لا تقول «خطأ» في صفحة الدخول بعد الرفض
  final paths = <String>[];
  final bad = <String>[]; // ما يجب ألّا يصل أبداً
  final signs = <String>[]; // نصوص التوقيع بعد الفكّ (للتحقّق)

  String get host => '127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final path = req.uri.path;
      paths.add('${req.method} $path${req.uri.hasQuery ? '?${req.uri.query}' : ''}');
      final res = req.response..headers.set('Server', 'Router Webserver');
      if (path.contains('LoginRpm.htm') || path.contains('PPPoECfgRpm') || path.contains('SysRebootRpm') || path.contains('RestoreDefault')) {
        bad.add(path);
      }
      if (path == '/') {
        res.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Basic realm="$_realm"');
        res.write(_loginPage(state, host));
      } else if (path == '/login/getRsa.json') {
        res.write(jsonEncode({'rsa': {'nn': _n, 'mm': _e}, 'seq': _seq}));
      } else if (path == '/login/login.json' && req.method == 'POST') {
        logins++;
        final body = await utf8.decoder.bind(req).join();
        expect(body.startsWith('JSONDATA: ') && body.endsWith('\n'), isTrue, reason: 'شكل نصّ الدخول كصفحة الجهاز');
        expect(req.headers.value(HttpHeaders.contentTypeHeader), 'application/json; charset=UTF-8');
        final j = jsonDecode(body.substring('JSONDATA: '.length).trim()) as Map<String, dynamic>;
        final s = AgileCrypto.rsaDecrypt(j['sign'] as String, _n, _d);
        signs.add(s);
        final m = RegExp(r'^key=(\d{16})&iv=(\d{16})&h=([0-9a-f]{32})&s=(\d+)$').firstMatch(s);
        final data = j['data'] as String;
        var ok = false;
        if (m != null && int.parse(m.group(4)!) == _seq + data.length) {
          final cred = jsonDecode(AgileCrypto.aesDecrypt(data, m.group(1)!, m.group(2)!)) as Map<String, dynamic>;
          final h = crypto.md5.convert(utf8.encode('${cred['name']}${cred['password']}')).toString();
          ok = cred['name'] == 'admin' && cred['password'] == pass && h == m.group(3);
          if (ok) {
            key = m.group(1);
            iv = m.group(2);
          }
        }
        if (ok && state == 3 || ok && state == 2) {
          sid = 'S${logins}abcdef0123456789';
          state = 0; // مديرٌ واحد: داخلٌ الآن
          res.write(jsonEncode({'valid': true, 'sessionId': sid}));
        } else {
          wrong++;
          if (state == 3 && !resetStateAfterWrong) state = wrong >= 10 ? 1 : 2;
          res.write(jsonEncode({'valid': false}));
        }
      } else {
        final m = RegExp(r'^/([A-Za-z0-9]+)(/userRpm/\w+\.htm)$').firstMatch(path);
        final cookie = req.headers.value(HttpHeaders.cookieHeader) ?? '';
        if (m == null || sid == null || m.group(1) != sid || !cookie.contains('Authorization=$_seq')) {
          res.write(_loginPage(state, host));
        } else {
          final page = m.group(2)!;
          if (page == '/userRpm/LogoutRpm.htm') {
            logouts++;
            sid = null;
            state = 3;
            res.write('<script>document.cookie="Authorization=;path=/";</script>');
          } else {
            res.write(switch (page) {
              '/userRpm/StatusRpm.htm' => _encPage(_status, key!, iv!),
              '/userRpm/WlanStationRpm.htm' => _encPage(_wlan, key!, iv!),
              '/userRpm/AssignedIpAddrListRpm.htm' => _encPage(_dhcp, key!, iv!),
              _ => '<HTML><BODY>frames</BODY></HTML>',
            });
          }
        }
      }
      await res.close();
    });
  }

  Future<void> stop() => server.close(force: true);
}

class _FakeApi implements HttpClientAdapter {
  Map<String, Object?> defaults = {};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final Object data = o.uri.path == '/api/admin/device-defaults' ? {'success': true, 'defaults': defaults} : {'success': true};
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('التعمية كسكربت الجهاز نفسه (متّجهاتٌ منه)', () {
    test('AES-128-CBC/PKCS7 بمفتاحٍ نصّيّ ⇒ نصّ cryptoJS نفسه، وJSON الدخول كـJSON.stringify', () {
      const plain = '{"name":"admin","password":"p@ss word"}';
      expect(jsonEncode({'name': 'admin', 'password': 'p@ss word'}), plain);
      expect(AgileCrypto.aesEncrypt(plain, '1234567890123456', '6543210987654321'), 'NSJqzRxl6x9f6rFBDUK53HhlHZdgZuaDqifkPGNJNPQbdsmeDwOVV3rsB+w4mpMl');
      // encryptData بالمفتاح والـIV 1111…/5555… وseq 56630: البيانات ونصّ التوقيع بعد فكّه بالمفتاح الخاصّ
      expect(AgileCrypto.aesEncrypt(plain, '1111222233334444', '5555666677778888'), 'Fn4lAwxxXgFKkoK+ZtjTnthaRDnE4EBJpdKgsadB0u1+vi9vxHLHGWW95nS0dGAw');
      expect(AgileCrypto.md5Hex('adminp@ss word'), '6fafe5c33f6f877d83d39d89c67a0666');
      final sign = AgileCrypto.rsaEncrypt('key=1111222233334444&iv=5555666677778888&h=6fafe5c33f6f877d83d39d89c67a0666&s=56694', _n, _e);
      expect(sign.length, 256, reason: 'كتلتان (٥٣ حرفاً لكلّ كتلة) بطول المفتاح هكساً — كتوقيع الجهاز');
      expect(AgileCrypto.rsaDecrypt(sign, _n, _d), 'key=1111222233334444&iv=5555666677778888&h=6fafe5c33f6f877d83d39d89c67a0666&s=56694');
    });

    test('صفحةٌ معمّاة ⇒ مصفوفاتها مقروءة (ومعها ما لا «var» قبله)؛ مفتاحٌ آخر ⇒ الصفحة كما هي', () {
      final page = _encPage(_status, '1111222233334444', '5555666677778888');
      final x = TpClassicParse.expandEncrypted(page, '1111222233334444', '5555666677778888');
      expect(TpClassicParse.array(x, 'statusPara')?[4], 647566);
      expect(TpClassicParse.array(x, 'wlanPara')?[1], 'TestWiFi', reason: 'wlanPara بلا var في النصّ المفكوك');
      expect(TpClassicParse.expandEncrypted(page, '9999999999999999', '9999999999999999'), page);
      expect(TpClassicParse.isRsaLogin(_loginPage(3, 'h')), isTrue);
    });
  });

  group('الراوتر الوهميّ المعمّى', () {
    late _FakeRsa d;
    setUp(() async {
      TplinkClassicService.reset();
      d = _FakeRsa();
      await d.start();
    });
    tearDown(() => d.stop());

    test('دخولٌ واحد بسكربته ⇒ لقطة الراوتر كاملة، والخروج دائماً، ولا دخول الكوكي القديم أبداً', () async {
      final hello = await TplinkClassicService.detect(d.host);
      expect([hello?.cookieAuth, hello?.model], [true, 'WR940N']);
      final snap = await TplinkClassicService.readOnce(d.host, 'ignored-user', 'p@ss word', hello: hello);
      expect(snap, isNotNull, reason: '${TplinkClassicService.lastIssue(d.host)}');
      expect([snap!.vendor, snap.model, snap.wanType, snap.wanOnlineSeconds, snap.peerCount, snap.dhcpCount],
          ['tpclassic', 'TL-WR940N v6', 'PPPoE', 3 * 86400 + 6 * 3600 + 35 * 60 + 55, 1, 2]);
      expect(snap.clients.map((c) => c.name), contains('Phone-C'));
      expect([d.logins, d.logouts, d.sid], [1, 1, null]);
      expect(d.bad, isEmpty, reason: 'لا LoginRpm.htm ولا صفحة مال/إقلاع/ضبط مصنع');
      expect(d.signs.single, matches(RegExp(r'^key=\d{16}&iv=\d{16}&h=[0-9a-f]{32}&s=\d+$')));
    });

    test('كلمة سرٍّ غلط ⇒ «رفض» تُحفظ فلا تُرسل ثانيةً (العدّاد عدّةٌ واحدة)، و«حفظ وفحص» يسمح بمحاولة', () async {
      d.pass = 'right-one';
      expect(await TplinkClassicService.readOnce(d.host, 'admin', 'wrong-one'), isNull);
      expect(TplinkClassicService.lastIssue(d.host)?.issue, TpClassicIssue.rejected);
      expect(await TplinkClassicService.readOnce(d.host, 'admin', 'wrong-one'), isNull);
      expect(d.logins, 1, reason: 'المرفوض لا يُرسل ثانيةً');
      TplinkClassicService.forget(d.host);
      expect(await TplinkClassicService.readOnce(d.host, 'admin', 'right-one'), isNotNull);
      expect(d.logins, 2);
    });

    test('رفضٌ بلا حالٍ تفسّره (الصفحة بعده «جاهز») ⇒ يُحفظ كالرفض فلا يُطرق ثانيةً تلقائيّاً', () async {
      d.pass = 'right-one';
      d.resetStateAfterWrong = true;
      expect(await TplinkClassicService.readOnce(d.host, 'admin', 'wrong-one'), isNull);
      expect(TplinkClassicService.lastIssue(d.host)?.issue, TpClassicIssue.rejected);
      expect(await TplinkClassicService.readOnce(d.host, 'admin', 'wrong-one'), isNull);
      expect(d.logins, 1);
    });

    test('مقفل أو مديرٌ آخر داخل ⇒ لا دخول أصلاً', () async {
      d.state = 1;
      expect(await TplinkClassicService.readOnce(d.host, 'admin', 'p@ss word'), isNull);
      expect(TplinkClassicService.lastIssue(d.host)?.issue, TpClassicIssue.locked);
      d.state = 0;
      expect(await TplinkClassicService.readOnce(d.host, 'admin', 'p@ss word'), isNull);
      expect(TplinkClassicService.lastIssue(d.host)?.issue, TpClassicIssue.busy);
      expect(d.logins, 0);
      expect(d.paths.where((p) => p.contains('getRsa')), isEmpty, reason: 'ولا طلب مفتاح');
    });

    test('النبضة الحيّة (عدّادات WAN والمتّصلون) بجلسةٍ تُغلق، والكتابات (واي فاي/إقلاع) لا تُرسل لهذا الفيرموير', () async {
      await TplinkClassicService.detect(d.host); // الكرت ينبض بعد فحصٍ عرف نوعه
      final p = await TplinkClassicService.pulse(d.host, 'admin', 'p@ss word', clients: true);
      expect([p.live?.rxBytes, p.live?.txBytes, p.clients], [4266809196, 3856716550, 1]);
      expect([d.logins, d.logouts], [1, 1]);
      final w = await TplinkClassicService.setWifiPassword(d.host, 'admin', 'p@ss word', 'new-pass-123');
      final r = await TplinkClassicService.reboot(d.host, 'admin', 'p@ss word');
      expect([w.fail, r.fail], [RouterFail.unsupported, RouterFail.unsupported]);
      expect(d.logins, 1, reason: 'لا دخول للكتابة');
      expect(d.bad, isEmpty);
    });
  });

  group('فحص جهاز المشترك (الإدارة عن بعد IP:منفذ)', () {
    late _FakeRsa d;
    late _FakeApi api;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DeviceProbeApi.clearAllCaches();
      d = _FakeRsa();
      await d.start();
      api = _FakeApi();
      final adapter = ApiClient.dio.httpClientAdapter;
      final interceptors = List<Interceptor>.of(ApiClient.dio.interceptors);
      ApiClient.dio.httpClientAdapter = api;
      ApiClient.dio.interceptors.clear();
      addTearDown(() {
        ApiClient.dio.httpClientAdapter = adapter;
        ApiClient.dio.interceptors
          ..clear(keepImplyContentTypeInterceptor: false)
          ..addAll(interceptors);
      });
      DeviceProbeApi.invalidateAdminDefaults();
    });

    tearDown(() => d.stop());

    test('الراوتر المعمّى بكلمة سرّ قسم TP-Link ⇒ لقطته من فرعه، جلسةٌ واحدة تُغلق، ولا دخول يوبيكويتي/هواوي عليه', () async {
      api.defaults = {'tplinkUsername': 'admin', 'tplinkPassword': 'p@ss word', 'ubntUsername': 'ub', 'ubntPassword': 'ub-p'};
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect([snap?.kind, snap?.ubnt?.vendor, snap?.ubnt?.model, snap?.ubnt?.peerCount], [DeviceKind.ubiquiti, 'tpclassic', 'TL-WR940N v6', 1]);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect([d.logins, d.logouts, d.sid], [1, 1, null]);
      expect(d.paths.where((p) => p.contains('login.cgi') || p.contains('/api/auth') || p.contains('/api/system/user/login')), isEmpty);
      expect(d.bad, isEmpty);
    });
  });
}
