// راوتر TP-Link الكلاسيكيّ بالفيرموير الأحدث (TL-WR940N v6، 3.18.1 Build 171030 — قِيس حيّاً ١٢ نوفمبر بدخولٍ واحد): صفحة دخولٍ
// 200 بـhttpAutErrorArray (3 جاهز · 2 خطأ · 1 مقفل · 0 مديرٌ آخر)، كوكي Authorization (MD5)، التوكن في المسار، مديرٌ واحد ⇒ خروجٌ
// دائماً، statistList نصوصٌ بفواصل، وhostList خمسة حقول. راوترٌ وهميّ محلّيّ بهذه القواعد (أسماءٌ وماكاتٌ وهميّة).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/core/net/router_types.dart';
import 'package:rad_mysvcs/core/net/tplink_classic_service.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _realm = 'TP-Link Wireless N Router WR940N';

String _loginPage(int state, String host) => '''
<SCRIPT language="javascript" type="text/javascript">
var httpAutErrorArray = new Array(
$state, 1, "http://$host", 0,0 );
</SCRIPT>
<HTML><BODY><form action="/userRpm/LoginRpm.htm" method="get" id="loginForm"></form></BODY></HTML>''';

String _statusPage(String rx, String tx) => '''
<SCRIPT language="javascript" type="text/javascript">
var statusPara = new Array(
1, 1, 22, 20000, 647566, "3.18.1 Build 171030 Rel.43957n ", "WR940N v6 00000000", 1, 0, 3, 0, 0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var wlanPara = new Array(
1, "TestWiFi", 15, 6, "AA-BB-CC-00-00-02", "192.168.42.1", 2, 8, 83, 4, 6, "", "", "", 1, 0, 2, 0, "", 0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var wanPara = new Array(
4, "AA-BB-CC-00-00-03", "100.66.1.177", 3, "255.255.255.255", 0, 0, "100.66.0.1", 0, 1, 0, "8.8.8.8 , 1.1.1.1", "3 day(s) 06:35:55", 1, 0, "0.0.0.0", "0.0.0.0", 0, 0, 0, 0, 0, 0, 0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var statistList = new Array(
"$rx", "$tx", "169,115,305", "65,240,934", 0, 0 );
</SCRIPT>
<HTML><BODY>status</BODY></HTML>''';

const _wlanPage = '''
<SCRIPT language="javascript" type="text/javascript">
var wlanHostPara = new Array(
1, 1, 8, 5000, 5, 0, 0, 1, 0, 0, 0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var hostList = new Array(
"AA-BB-CC-00-01-01", 1, 1944002, 2040364, 2,
0,0 );
</SCRIPT>''';

const _dhcpPage = '''
<SCRIPT language="javascript" type="text/javascript">
var DHCPDynList = new Array(
"Laptop-A", "AA-BB-CC-00-02-01", "192.168.42.109", "01:56:28",
"Phone-B", "AA-BB-CC-00-02-02", "192.168.42.100", "00:05:14",
"Phone-C", "AA-BB-CC-00-01-01", "192.168.42.101", "01:49:35",
0,0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var DHCPDynPara = new Array(
3, 4, 0, 0 );
</SCRIPT>''';

// صفحة WlanSecurityRpm بشكلها الحيّ (قيمٌ وهميّة).
const _secPage = '''<SCRIPT language="javascript" type="text/javascript">
var wlanPara = new Array(
8, 1, 3, "332", 1, 0, "", 1812, "", "fake-pass-1", 1, 0, 0, 1, 3, 0, 0, 0, 6, 0, 1, "", 0, 0, 0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var wlanList = new Array(
"", 0, "", 0, "", 0, "", 0, 0, 0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var ssidList = new Array(
"Fake-WR940", 0, 0 );
</SCRIPT>''';

/// راوترٌ وهميّ بقواعد WR940N v6 المقيسة.
class _FakeWr940 {
  late HttpServer server;
  String user = 'admin';
  String pass = '9999';
  String rx = '4,266,809,196';
  String tx = '3,856,716,550';
  String? token; // جلسة المدير الوحيدة
  bool otherAdmin = false; // مديرٌ آخر داخل من متصفّحه
  bool lastWrong = false;
  int wrong = 0;
  int logins = 0;
  int logouts = 0;
  bool failStatus = false;
  Duration delay = Duration.zero; // بطء الردّ — يجعل عمليّتين متزامنتين تتداخلان كما على الشبكة
  bool noTokenOnce = false; // الدخول التالي يعود بلا توكن ولا سبب (حيّاً: دخولٌ سريع بعد خروج)
  bool kickNextSecurity = false; // صفحة الأمان التالية: الجلسة سقطت (سكربت الخروج)
  int refused = 0; // دخولٌ رُدّ لأنّ جلسةً مفتوحة
  int reboots = 0;
  final paths = <String>[];
  final referers = <String?>[];
  final _rnd = Random(7);

  String get host => '127.0.0.1:${server.port}';
  bool get locked => wrong >= 10;

  int get state => locked ? 1 : ((otherAdmin || token != null) ? 0 : (lastWrong ? 2 : 3));

  String _expectedCookie() {
    final p = crypto.md5.convert(utf8.encode(pass)).toString();
    return 'Basic ${base64.encode(utf8.encode('$user:$p'))}';
  }

  String? _cookieAuth(HttpRequest req) {
    final c = req.headers.value(HttpHeaders.cookieHeader) ?? '';
    final m = RegExp(r'Authorization=([^;]*)').firstMatch(c);
    return m == null ? null : Uri.decodeComponent(m.group(1)!);
  }

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final path = req.uri.path;
      paths.add(path);
      referers.add(req.headers.value(HttpHeaders.refererHeader));
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final res = req.response..headers.set('Server', 'Router Webserver');
      if (path == '/') {
        res.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Basic realm="$_realm"');
        res.write(_loginPage(state, host));
      } else if (path == '/userRpm/LoginRpm.htm') {
        logins++;
        if (locked || otherAdmin || token != null) {
          if (token != null) refused++;
          res.write(_loginPage(state, host));
        } else if (_cookieAuth(req) != _expectedCookie()) {
          wrong++;
          lastWrong = true;
          res.write(_loginPage(locked ? 1 : 2, host));
        } else if (noTokenOnce) {
          noTokenOnce = false;
          res.write('<HTML><BODY>login</BODY></HTML>');
        } else {
          lastWrong = false;
          token = String.fromCharCodes(List.generate(16, (_) => 65 + _rnd.nextInt(26)));
          res.write('<body><script language="javaScript">window.parent.location.href = "http://$host/$token/userRpm/Index.htm";</script></body>');
        }
      } else {
        final m = RegExp(r'^/([A-Z]{16})(/userRpm/\w+\.htm)$').firstMatch(path);
        if (m == null || m.group(1) != token || _cookieAuth(req) != _expectedCookie()) {
          res.write(_loginPage(state, host));
        } else if (req.headers.value(HttpHeaders.refererHeader) == null) {
          res.write('<HTML><BODY>You have no authority to access this router!</BODY></HTML>');
        } else {
          final page = m.group(2)!;
          if (page == '/userRpm/LogoutRpm.htm') {
            logouts++;
            token = null;
            res.write('<HTML><BODY>bye</BODY></HTML>');
          } else if (page == '/userRpm/StatusRpm.htm' && failStatus) {
            res.statusCode = 500;
          } else if (page == '/userRpm/WlanSecurityRpm.htm' && kickNextSecurity) {
            kickNextSecurity = false;
            token = null;
            res.write('<script language="javaScript">document.cookie="Authorization=;path=/";</script>');
          } else if (page == '/userRpm/SysRebootRpm.htm' && req.uri.queryParameters['Reboot'] == 'Reboot') {
            reboots++;
            token = null;
            // ردّ صفحة الإقلاع غير مقيس — قد يمسح الكوكي: لا يُحكم منه بـ«لم يُنفَّذ»
            res.write('<script language="javaScript">document.cookie="Authorization=;path=/";</script>Restarting');
          } else {
            res.write(switch (page) {
              '/userRpm/WlanSecurityRpm.htm' => _secPage,
              '/userRpm/StatusRpm.htm' => _statusPage(rx, tx),
              '/userRpm/WlanStationRpm.htm' => _wlanPage,
              '/userRpm/AssignedIpAddrListRpm.htm' => _dhcpPage,
              '/userRpm/PPPoECfgRpm.htm' => 'var pppoeInf = new Array(1,0,"SUB-USER","SECRET-PPPOE-PASS");',
              _ => '<HTML><BODY>frames</BODY></HTML>',
            });
          }
        }
      }
      await res.close();
    });
  }

  Future<void> stop() => server.close(force: true);

  Future<void> settle() async {
    final sw = Stopwatch()..start();
    var seen = paths.length;
    var quietSince = sw.elapsedMilliseconds;
    while (sw.elapsedMilliseconds < 5000) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (paths.length != seen) {
        seen = paths.length;
        quietSince = sw.elapsedMilliseconds;
      } else if (sw.elapsedMilliseconds - quietSince >= 250) {
        return;
      }
    }
  }
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
  group('قراءاتٌ صرفة للفيرموير الأحدث', () {
    test('حالة صفحة الدخول والتوكن', () {
      expect(TpClassicParse.loginState(_loginPage(3, 'h')), (code: 3, md5: true));
      expect(TpClassicParse.loginState(_loginPage(0, 'h'))?.code, 0);
      expect(TpClassicParse.loginState('<html>no</html>'), isNull);
      expect(TpClassicParse.loginToken('href = "http://h/ABCDEFGHIJKLMNOP/userRpm/Index.htm";'), 'ABCDEFGHIJKLMNOP');
      expect(TpClassicParse.loginToken(_loginPage(2, 'h')), isNull);
    });

    test('العدّادات نصوصٌ بفواصل الآلاف ⇒ أعداد؛ والمحطّة خمسة حقول (wlanHostPara[4]) ⇒ لا محطّاتٌ وهميّة', () {
      final s = TpClassicParse.status(statusHtml: _statusPage('4,266,809,196', '3,856,716,550'), wlanHtml: _wlanPage, dhcpHtml: _dhcpPage, baseUrl: 'http://h');
      expect([s?.rxBytes, s?.txBytes, s?.peerCount, s?.dhcpCount, s?.model, s?.wanType], [4266809196, 3856716550, 1, 3, 'TL-WR940N v6', 'PPPoE']);
      expect(s?.wanOnlineSeconds, 3 * 86400 + 6 * 3600 + 35 * 60 + 55);
      expect(s!.clients.map((c) => [c.mac, c.name, c.ip]).toList(), [
        ['AA-BB-CC-00-01-01', 'Phone-C', '192.168.42.101'],
      ]);
      final live = TpClassicParse.live(_statusPage('1,000', '2,000'), DateTime(2026));
      expect([live?.rxBytes, live?.txBytes], [1000, 2000]);
    });

    test('الكوكي كما تبنيه صفحة الجهاز: escape() لـ"Basic "+base64(user:md5(pass))', () {
      final md5 = crypto.md5.convert(utf8.encode('9999')).toString();
      final b64 = base64.encode(utf8.encode('admin:$md5'));
      expect(TplinkClassicService.cookieAuth('admin', '9999', md5: true), 'Authorization=Basic%20${b64.replaceAll('=', '%3D')}');
      expect(TplinkClassicService.jsEscape('a b=c+/@*_-.'), 'a%20b%3Dc+/@*_-.');
    });
  });

  group('الراوتر الوهميّ (كوكي + توكن، مديرٌ واحد)', () {
    late _FakeWr940 d;
    setUp(() async {
      TplinkClassicService.reset();
      d = _FakeWr940();
      await d.start();
    });
    tearDown(() => d.stop());

    test('التعرّف: «/» وحده بلا اعتماد ⇒ الفيرموير الأحدث بطرازه', () async {
      final h = await TplinkClassicService.detect(d.host);
      expect([h?.cookieAuth, h?.md5, h?.model], [true, true, 'WR940N']);
      expect(d.paths, ['/']);
      expect(d.logins, 0);
    });

    test('قراءةٌ كاملة بجلسةٍ واحدة ثمّ خروج — الصفحات بـReferer، وPPPoE لا تُطلب، والراوتر جاهزٌ بعدها لصاحبه', () async {
      await TplinkClassicService.detect(d.host);
      final u = await TplinkClassicService.readOnce(d.host, 'admin', '9999');
      expect([u?.vendor, u?.peerCount, u?.dhcpCount, u?.model, u?.rxBytes], ['tpclassic', 1, 3, 'TL-WR940N v6', 4266809196]);
      expect([d.logins, d.logouts], [1, 1]);
      expect(d.token, isNull, reason: 'الخروج دائماً — مديرٌ واحد');
      expect(d.state, 3);
      expect(d.paths.any((p) => p.contains('PPPoE')), isFalse);
      final tokenPaths = [for (var i = 0; i < d.paths.length; i++) if (RegExp(r'^/[A-Z]{16}/').hasMatch(d.paths[i])) i];
      expect(tokenPaths.every((i) => d.referers[i]?.startsWith('http://${d.host}/') ?? false), isTrue);
      expect(TplinkClassicService.lastIssue(d.host), isNull);
    });

    test('مديرٌ آخر داخل ⇒ «مشغول» بلا إرسال اعتماد؛ ومقفل ⇒ «مقفل» بلا إرسال', () async {
      await TplinkClassicService.detect(d.host);
      d.otherAdmin = true;
      expect(await TplinkClassicService.readOnce(d.host, 'admin', '9999'), isNull);
      expect(TplinkClassicService.lastIssue(d.host)?.issue, TpClassicIssue.busy);
      expect(d.logins, 0, reason: 'لا نحاول ولا نطرده');
      d.otherAdmin = false;
      d.wrong = 10;
      expect(await TplinkClassicService.readOnce(d.host, 'admin', '9999'), isNull);
      expect(TplinkClassicService.lastIssue(d.host)?.issue, TpClassicIssue.locked);
      expect(d.logins, 0);
    });

    test('كلمة سرٍّ غلط ⇒ رفضٌ يُحفظ (لا يُعاد تلقائيّاً ولا من النبضة)، و«نسيان» يعيده مرّة', () async {
      await TplinkClassicService.detect(d.host);
      expect(await TplinkClassicService.readOnce(d.host, 'admin', 'wrong'), isNull);
      expect(TplinkClassicService.lastIssue(d.host)?.issue, TpClassicIssue.rejected);
      expect(d.wrong, 1);
      expect(await TplinkClassicService.readOnce(d.host, 'admin', 'wrong'), isNull);
      expect((await TplinkClassicService.pulse(d.host, 'admin', 'wrong')).live, isNull);
      expect(d.wrong, 1, reason: 'المرفوض لا يُرسل ثانيةً — القفل بعد عشر');
      TplinkClassicService.forget(d.host);
      expect(await TplinkClassicService.readOnce(d.host, 'admin', 'wrong'), isNull);
      expect(d.wrong, 2);
    });

    test('النبضة الحيّة: جلسةٌ واحدة لكلّ نبضة («/»، دخول، الحالة [+الوايرلس]، خروج)، والمعدّل من فرق العدّادات', () async {
      await TplinkClassicService.detect(d.host);
      d.paths.clear();
      final a = await TplinkClassicService.pulse(d.host, 'admin', '9999', clients: true);
      d.rx = '4,267,309,196';
      final b = await TplinkClassicService.pulse(d.host, 'admin', '9999');
      expect([a.clients, b.clients], [1, null]);
      expect(b.live!.rxBytes - a.live!.rxBytes, 500000);
      expect(d.paths.where((p) => p == '/').length, 2, reason: 'صفحة الدخول تُهيّئ الدخول (حيّاً) وتقول «مديرٌ آخر»');
      expect([d.logins, d.logouts, d.token], [2, 2, null]);
      d.otherAdmin = true;
      expect((await TplinkClassicService.pulse(d.host, 'admin', '9999')).live, isNull);
      expect(d.logins, 2, reason: 'مديرٌ آخر داخل ⇒ لا دخول من النبضة');
    });

    test('تعثّر صفحة الحالة ⇒ لا لقطة، والخروج يحدث رغم ذلك', () async {
      await TplinkClassicService.detect(d.host);
      d.failStatus = true;
      expect(await TplinkClassicService.readOnce(d.host, 'admin', '9999'), isNull);
      expect([d.logins, d.logouts, d.token], [1, 1, null]);
    });
  });

  // حيّاً ١٢ نوفمبر (WR940N saidnaser، هاتف المالك): «كلمة سرّ الواي فاي» ⇒ «الراوتر ما قبل الأمر» ونبضة الترافيك تدور — نبضةٌ
  // بدأت قبل القراءة خرجت وسطها فأسقطت جلستها (مديرٌ واحد).
  group('مديرٌ واحد: العمليّات بالدور وإعادةٌ مرّة', () {
    late _FakeWr940 d;
    setUp(() async {
      TplinkClassicService.reset();
      final pause = TplinkClassicService.retryPause;
      final relogin = TplinkClassicService.reloginPause;
      TplinkClassicService.retryPause = () => const Duration(milliseconds: 80);
      TplinkClassicService.reloginPause = () => Duration.zero;
      addTearDown(() {
        TplinkClassicService.retryPause = pause;
        TplinkClassicService.reloginPause = relogin;
      });
      d = _FakeWr940()..delay = const Duration(milliseconds: 15);
      await d.start();
      await TplinkClassicService.detect(d.host);
    });
    tearDown(() => d.stop());

    test('نبضة الكرت وقراءة الواي فاي باللحظة نفسها ⇒ كلتاهما تنجح، جلسةً بعد جلسة (لا دخول يُردّ)', () async {
      final both = await Future.wait<Object?>([
        TplinkClassicService.pulse(d.host, 'admin', '9999', clients: true),
        TplinkClassicService.readWifi(d.host, 'admin', '9999'),
        TplinkClassicService.pulse(d.host, 'admin', '9999'),
      ]);
      final p1 = both[0] as ({TpClassicLive? live, int? clients});
      final w = both[1] as RouterResult<List<RouterWifi>>;
      final p2 = both[2] as ({TpClassicLive? live, int? clients});
      expect([p1.live != null, p1.clients, p2.live != null], [true, 1, true]);
      expect(w.ok, isTrue);
      expect(w.value!.single.ssid, 'Fake-WR940');
      expect(d.refused, 0, reason: 'لا دخول وجلسةٌ مفتوحة');
      expect([d.logins, d.logouts, d.token], [3, 3, null]);
    });

    test('دخولٌ بلا توكن ولا سبب ⇒ دخولٌ ثانٍ مرّة فينجح، وعدّاد القفل لا يزيد', () async {
      d.noTokenOnce = true;
      final w = await TplinkClassicService.readWifi(d.host, 'admin', '9999');
      expect(w.ok, isTrue);
      expect([d.logins, d.logouts, d.wrong], [2, 1, 0]);
    });

    test('مديرٌ آخر داخل لحظتها ⇒ لا دخول، ثمّ إعادةٌ بعد مهلةٍ تنجح حين خرج؛ وإن بقي ⇒ «مشغول» بلا دخول', () async {
      d.otherAdmin = true;
      Timer(const Duration(milliseconds: 40), () => d.otherAdmin = false);
      final w = await TplinkClassicService.readWifi(d.host, 'admin', '9999');
      expect(w.ok, isTrue);
      expect(d.logins, 1);
      d.otherAdmin = true;
      final busy = await TplinkClassicService.readWifi(d.host, 'admin', '9999');
      expect(busy.fail, RouterFail.busy);
      expect(d.logins, 1, reason: 'لا نطرد من يعمل على الراوتر');
    });

    test('جلسةٌ سقطت وسط القراءة (سكربت الخروج) ⇒ إعادةٌ مرّة تنجح', () async {
      d.kickNextSecurity = true;
      final w = await TplinkClassicService.readWifi(d.host, 'admin', '9999');
      expect(w.ok, isTrue);
      expect(d.logins, 2);
    });

    test('إعادة التشغيل: «مشغول» قبل الدخول ⇒ تُعاد؛ وما بعد الإرسال لا يُعاد أبداً ولو مسح الردّ الكوكي', () async {
      d.otherAdmin = true;
      Timer(const Duration(milliseconds: 40), () => d.otherAdmin = false);
      final r = await TplinkClassicService.reboot(d.host, 'admin', '9999');
      expect(r.ok, isTrue);
      expect(d.reboots, 1);
      final again = await TplinkClassicService.reboot(d.host, 'admin', '9999');
      expect(again.ok, isTrue);
      expect(d.reboots, 2, reason: 'كلّ طلبٍ إقلاعٌ واحد — لا إعادة بعد الإرسال');
    });
  });

  group('فحص جهاز المشترك (WR940N)', () {
    late _FakeWr940 d;
    late _FakeApi api;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DeviceProbeApi.clearAllCaches();
      d = _FakeWr940();
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

    test('راوتر بالفيرموير الأحدث ⇒ لقطته من فرعه بقسم TP-Link، جلسةٌ واحدة تُغلق، ولا دخول يوبيكويتي عليه', () async {
      api.defaults = {'tplinkUsername': 'admin', 'tplinkPassword': '9999', 'ubntUsername': 'ub', 'ubntPassword': 'ub-p'};
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect([snap?.kind, snap?.ubnt?.vendor, snap?.ubnt?.peerCount, snap?.ubnt?.model], [DeviceKind.ubiquiti, 'tpclassic', 1, 'TL-WR940N v6']);
      await d.settle();
      expect([d.logins, d.logouts, d.token], [1, 1, null]);
      expect(d.paths.where((p) => p.contains('login.cgi') || p.contains('/api/auth')), isEmpty);
      final creds = await DeviceProbeApi.resolveTplinkCreds(fallbackIp: d.host);
      expect([creds?.user, creds?.pass], ['admin', '9999']);
    });

    test('مديرٌ آخر داخل ⇒ السبب «مشغول» ولا محاولة دخول', () async {
      api.defaults = {'tplinkUsername': 'admin', 'tplinkPassword': '9999'};
      d.otherAdmin = true;
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      await d.settle();
      expect(DeviceProbeApi.issueFor(ip: d.host)?.issue, ProbeIssue.busy);
      expect(d.logins, 0);
    });
  });
}
