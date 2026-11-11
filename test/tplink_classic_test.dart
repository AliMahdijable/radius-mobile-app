// راوتر TP-Link الكلاسيكيّ (TL-WR741ND v4، فيرموير 3.16.6 — قِيس حيّاً ١١ نوفمبر، قراءةٌ وحدها): المحلّل بقوالب بنية الصفحات الحيّة
// (أسماء وماكات وهميّة)، وراوترٌ وهميّ محلّيّ بالقواعد المقيسة (Basic مع كلّ طلب بلا جلسة، 401 + realm للتعرّف، حارس Referer،
// صفحة PPPoE فيها كلمة سرّ المشترك ⇒ لا تُطلب أبداً)، ثمّ الفحص الكامل عبر DeviceProbeApi.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/core/net/tplink_classic_service.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/device_probe_card.dart' show deviceCopyFields;
import 'package:shared_preferences/shared_preferences.dart';

const _realm = 'TP-LINK Wireless Lite N Router WR741ND';

String _statusPage({int rx = 825263676, int tx = 242439653, int uptime = 13425, String online = '0 day(s) 03:43:03'}) => '''
<SCRIPT language="javascript" type="text/javascript">
var statusPara = new Array(
1,
1,
22,
20000,
$uptime,
"3.16.6 Build 130524 Rel.58577n ",
"WR741ND v4 00000000",
0,
0,
3,
0,
0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var lanPara = new Array(
"AA-BB-CC-00-00-01",
"192.168.6.1",
"255.255.255.0",
0,0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var wlanPara = new Array(
1,
"TestWiFi",
15,
5,
"AA-BB-CC-00-00-01",
"192.168.6.1",
1,8,53,1,6,"","","",0,0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var wanPara = new Array(
4,
"AA-BB-CC-00-00-02",
"10.3.30.88",
3,
"255.255.255.255",
0,0,
"10.3.30.88",
0,1,0,
"8.8.8.8 , 8.8.4.4",
"$online",
1,0,"0.0.0.0","0.0.0.0",0,0,0,2,0,0,0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var statistList = new Array(
$rx,
$tx,
3917483,
1693366,
0,0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var wanLinkModeStringArray = new Array(new Array(0), new Array(1), new Array(2), new Array(" ", "(Connect on Demand)", "(Connect Automatically)") );
</SCRIPT>
<HTML><HEAD><TITLE>TL-WR741ND</TITLE></HEAD><BODY>status</BODY></HTML>''';

String _wlanPage(int n) {
  final rows = [for (var i = 0; i < n; i++) '"AA-BB-CC-00-01-${(10 + i).toString().padLeft(2, '0')}", 1, ${1000 + i}, ${2000 + i},'];
  return '''
<SCRIPT language="javascript" type="text/javascript">
var wlanHostPara = new Array(
$n,1,8,5000,4,0,0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var hostList = new Array(
${rows.join('\n')}
0,0 );
</SCRIPT>
<HTML><BODY>stations</BODY></HTML>''';
}

const _dhcpPage = '''
<SCRIPT language="javascript" type="text/javascript">
var DHCPDynList = new Array(
"Phone-A", "AA-BB-CC-00-02-01", "192.168.6.100", "01:19:06",
"Unknown", "AA-BB-CC-00-02-02", "192.168.6.101", "01:33:15",
"Phone-B", "AA-BB-CC-00-02-03", "192.168.6.102", "01:18:56",
0,0 );
</SCRIPT>
<SCRIPT language="javascript" type="text/javascript">
var DHCPDynPara = new Array(
3,
4,
0,0 );
</SCRIPT>''';

/// راوترٌ وهميّ بقواعد TL-WR741ND المقيسة.
class _FakeClassic {
  late HttpServer server;
  String user = 'admin';
  String pass = '0000';
  String realm = _realm;
  int rx = 825263676;
  int tx = 242439653;
  int clients = 7;
  String online = '0 day(s) 03:43:03';
  final paths = <String>[];
  final referers = <String?>[];

  /// كلّ طلبٍ حمل ترويسة Authorization (صحيحةً أو غلطاً).
  int authTries = 0;
  int rejected = 0;

  String get host => '127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      paths.add(req.uri.path);
      referers.add(req.headers.value(HttpHeaders.refererHeader));
      final auth = req.headers.value(HttpHeaders.authorizationHeader);
      if (auth != null) authTries++;
      final good = 'Basic ${base64.encode(utf8.encode('$user:$pass'))}';
      final res = req.response..headers.set('Server', 'Router Webserver');
      if (auth != good) {
        if (auth != null) rejected++;
        res.statusCode = 401;
        res.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Basic realm="$realm"');
        res.write('<HTML><BODY>401 Unauthorized</BODY></HTML>');
        await res.close();
        return;
      }
      // حارس الفيرموَير: بلا Referer صفحة «لا صلاحيّة» بلا بيانات.
      if (req.headers.value(HttpHeaders.refererHeader) == null) {
        res.write('<HTML><BODY>You have no authority to access this router!</BODY></HTML>');
        await res.close();
        return;
      }
      res.write(switch (req.uri.path) {
        '/userRpm/StatusRpm.htm' => _statusPage(rx: rx, tx: tx, online: online),
        '/userRpm/WlanStationRpm.htm' => _wlanPage(clients),
        '/userRpm/AssignedIpAddrListRpm.htm' => _dhcpPage,
        '/userRpm/PPPoECfgRpm.htm' => 'var pppoeInf = new Array(1,0,"SUB-USER","SECRET-PPPOE-PASS");',
        _ => '<HTML><BODY>frames</BODY></HTML>',
      });
      await res.close();
    });
  }

  Future<void> stop() => server.close(force: true);

  /// ينتظر حتى تسكت الطلبات (فروع السباق الأخرى تنتهي بالخلفيّة).
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
  group('قراءة صفحات الراوتر (صرفة)', () {
    test('new Array: نصوصٌ وأعداد بترتيبها، ومصفوفةٌ متداخلة جارةٌ لا تُربك', () {
      final sp = TpClassicParse.array(_statusPage(), 'statusPara')!;
      expect(sp[4], 13425);
      expect(sp[5], '3.16.6 Build 130524 Rel.58577n');
      expect(TpClassicParse.array(_statusPage(), 'wanPara')![12], '0 day(s) 03:43:03');
      expect(TpClassicParse.array(_statusPage(), 'statistList')!.take(2), [825263676, 242439653]);
      expect(TpClassicParse.array(_statusPage(), 'notThere'), isNull);
    });

    test('مدّة الاتّصال بصيغها، وغير المفهوم null لا صفر', () {
      expect(TpClassicParse.durationSeconds('0 day(s) 03:43:03'), 3 * 3600 + 43 * 60 + 3);
      expect(TpClassicParse.durationSeconds('3 days 14:31:49'), 3 * 86400 + 14 * 3600 + 31 * 60 + 49);
      expect(TpClassicParse.durationSeconds('02:00:05'), 7205);
      expect(TpClassicParse.durationSeconds('0 day(s) 00:00:00'), 0);
      expect(TpClassicParse.durationSeconds('Disconnected'), isNull);
    });

    test('الطراز: من العتاد «WR741ND v4 00000000» ⇒ «TL-WR741ND v4»، ومن realm ⇒ «WR741ND»', () {
      expect(TpClassicParse.modelFromHardware('WR741ND v4 00000000'), 'TL-WR741ND v4');
      expect(TpClassicParse.modelFromRealm(_realm), 'WR741ND');
      expect(TpClassicParse.modelFromRealm('Router'), '');
    });

    test('اللقطة: المتّصلون من الوايرلس لا من DHCP، والمدّتان، وWAN، بلا إشارة ولا منافذ ولا إنذار LAN', () {
      final u = TpClassicParse.status(statusHtml: _statusPage(), wlanHtml: _wlanPage(7), dhcpHtml: _dhcpPage, baseUrl: 'http://r')!;
      expect([u.vendor, u.model, u.isRouter, u.isTpClassic, u.isTplink], ['tpclassic', 'TL-WR741ND v4', true, true, false]);
      expect(u.peerCount, 7, reason: 'المتّصل الفعليّ = صفحة الوايرلس');
      expect(u.dhcpCount, 3, reason: 'إيجارات DHCP منفصلة (ثانويّة)');
      expect(u.uptimeSeconds, 13425);
      expect(u.wanOnlineSeconds, 13383);
      expect(u.wanType, 'PPPoE');
      expect(u.ssid, 'TestWiFi');
      expect([u.rxBytes, u.txBytes], [825263676, 242439653]);
      expect([u.signalDbm, u.ccqPercent, u.peerMac], [null, null, null]);
      expect(u.lanPorts, isEmpty);
      expect(u.lanHealth, 'unknown', reason: 'لا حالة منافذ ⇒ مجهول لا «مفصول» أحمر');
    });

    test('بلا صفحتي الوايرلس وDHCP ⇒ العددان null لا صفر؛ وصفحةٌ ليست صفحة حالة ⇒ لا لقطة', () {
      final u = TpClassicParse.status(statusHtml: _statusPage(), baseUrl: 'http://r')!;
      expect([u.peerCount, u.dhcpCount], [null, null]);
      expect(TpClassicParse.status(statusHtml: '<html>You have no authority</html>', baseUrl: 'http://r'), isNull);
    });

    test('العيّنة الحيّة والمعدّل: فرق عيّنتين بالبت/ث؛ عدّادٌ رجع للصفر أو فاصلٌ قصير ⇒ لا معدّل', () {
      final t0 = DateTime(2026, 11, 11, 12);
      final a = TpClassicParse.live(_statusPage(rx: 1000000, tx: 500000), t0)!;
      final b = TpClassicParse.live(_statusPage(rx: 1250000, tx: 550000), t0.add(const Duration(seconds: 2)))!;
      expect([a.uptimeSeconds, a.wanOnlineSeconds], [13425, 13383]);
      expect(tpClassicRate(a, b), (down: 1000000, up: 200000)); // 250000 B·8 / 2s
      final reset = TpClassicParse.live(_statusPage(rx: 10, tx: 10), t0.add(const Duration(seconds: 4)))!;
      expect(tpClassicRate(b, reset), isNull, reason: 'إقلاعٌ صفّر العدّاد — لا معدّلٌ سالب');
      final quick = TpClassicParse.live(_statusPage(rx: 1250100, tx: 550000), t0.add(const Duration(milliseconds: 2100)))!;
      expect(tpClassicRate(b, quick), isNull);
    });

    test('الحفظ والاسترجاع (كاش اللقطة): المورّد والحقول الجديدة تبقى؛ والقديم بلاها كما كان', () {
      final u = TpClassicParse.status(statusHtml: _statusPage(), wlanHtml: _wlanPage(7), dhcpHtml: _dhcpPage, baseUrl: 'http://r')!;
      final back = UbiquitiStatus.fromJson(jsonDecode(jsonEncode(u.toJson())) as Map<String, dynamic>);
      expect([back.vendor, back.peerCount, back.dhcpCount, back.wanOnlineSeconds, back.wanType], ['tpclassic', 7, 3, 13383, 'PPPoE']);
      final old = UbiquitiStatus.fromJson({'h': 'nano', 'f': 'XW', 'ssid': '', 'm': '', 'lan': [], 'b': ''});
      expect([old.vendor, old.isRouter, old.wanOnlineSeconds, old.dhcpCount, old.wanType], ['ubnt', false, null, null, '']);
    });

    test('النبضة تحدّث المتّصلين والمدّتين وتُبقي الباقي', () {
      final u = TpClassicParse.status(statusHtml: _statusPage(), wlanHtml: _wlanPage(7), dhcpHtml: _dhcpPage, baseUrl: 'http://r')!;
      final l = u.withLive(peerCount: 5, wanOnlineSeconds: 20000, uptimeSeconds: 20100);
      expect([l.peerCount, l.wanOnlineSeconds, l.uptimeSeconds, l.dhcpCount, l.wanType, l.vendor], [5, 20000, 20100, 3, 'PPPoE', 'tpclassic']);
      expect(u.withLive().peerCount, 7, reason: 'نبضةٌ بلا عيّنة متّصلين لا تمسح العدد');
    });

    test('حقول «نسخ كلّ المعلومات»: المتّصلون، مدّة الاتصال، الإنترنت، DHCP — بلا إشارة', () {
      final u = TpClassicParse.status(statusHtml: _statusPage(), wlanHtml: _wlanPage(7), dhcpHtml: _dhcpPage, baseUrl: 'http://r')!;
      final f = deviceCopyFields(DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.3.30.88', ubnt: u));
      final m = {for (final x in f) x.label: x.value};
      expect(m['نوع الجهاز'], 'راوتر TP-Link TL-WR741ND v4');
      expect(m['المتّصلون الآن'], '7');
      expect(m['مدّة الاتصال'], isNot(isEmpty));
      expect(m['الإنترنت'], 'PPPoE');
      expect(m['أجهزة DHCP'], '3');
      expect(m.containsKey('الإشارة'), isFalse);
      final down = deviceCopyFields(DeviceHealthSnapshot(
          kind: DeviceKind.ubiquiti,
          ip: '10.3.30.88',
          ubnt: TpClassicParse.status(statusHtml: _statusPage(online: '0 day(s) 00:00:00'), baseUrl: 'http://r')!));
      expect({for (final x in down) x.label: x.value}['مدّة الاتصال'], 'غير متّصل بالإنترنت');
    });
  });

  group('الراوتر الوهميّ (Basic بلا جلسة)', () {
    late _FakeClassic d;
    setUp(() async {
      TplinkClassicService.reset();
      d = _FakeClassic();
      await d.start();
    });
    tearDown(() => d.stop());

    test('التعرّف: طلبٌ واحد بلا اعتماد ⇒ realm وطرازه', () async {
      final h = await TplinkClassicService.detect(d.host);
      expect([h?.model, h?.realm], ['WR741ND', _realm]);
      expect(d.authTries, 0, reason: 'التعرّف لا يرسل اعتماداً');
      expect(d.paths, ['/']);
    });

    test('401 بـrealm لغير TP-LINK ⇒ ليس هو؛ وجهازٌ لا يجاوب ⇒ null', () async {
      d.realm = 'NETGEAR R6220';
      expect(await TplinkClassicService.detect(d.host), isNull);
      final host = d.host;
      await d.stop();
      expect(await TplinkClassicService.detect(host), isNull);
    });

    test('قراءةٌ بالاعتماد الصحيح: الحالة ثمّ الوايرلس وDHCP — بـReferer كلّها، وصفحة PPPoE لا تُطلب أبداً', () async {
      final u = await TplinkClassicService.readOnce(d.host, 'admin', '0000');
      expect([u?.peerCount, u?.dhcpCount, u?.wanOnlineSeconds, u?.model], [7, 3, 13383, 'TL-WR741ND v4']);
      expect(d.paths.toSet(), {'/userRpm/StatusRpm.htm', '/userRpm/WlanStationRpm.htm', '/userRpm/AssignedIpAddrListRpm.htm'});
      expect(d.referers.every((r) => r != null && r.startsWith('http://${d.host}')), isTrue, reason: 'حارس الفيرموَير');
      expect(d.paths.any((p) => p.contains('PPPoE')), isFalse, reason: 'فيها كلمة سرّ PPPoE المشترك');
      expect(TplinkClassicService.lastIssue(d.host), isNull);
    });

    test('قراءتان معاً بلا تصادم (لا جلسة يطرد بعضها بعضاً)', () async {
      final r = await Future.wait([
        TplinkClassicService.readOnce(d.host, 'admin', '0000'),
        TplinkClassicService.readOnce(d.host, 'admin', '0000'),
      ]);
      expect(r.map((u) => u?.peerCount), [7, 7]);
    });

    test('اعتمادٌ غلط ⇒ رفضٌ بعد صفحة الحالة وحدها، والمرفوض لا يُعاد تلقائيّاً، و«نسيان» يعيده مرّة', () async {
      expect(await TplinkClassicService.readOnce(d.host, 'admin', 'wrong'), isNull);
      expect(TplinkClassicService.lastIssue(d.host)?.issue, TpClassicIssue.rejected);
      expect(d.paths, ['/userRpm/StatusRpm.htm'], reason: 'لا صفحات بعد الرفض');
      expect(await TplinkClassicService.readOnce(d.host, 'admin', 'wrong'), isNull);
      expect(d.rejected, 1, reason: 'المرفوض محفوظ — لا يُرسل ثانيةً');
      expect(await TplinkClassicService.sample(d.host, 'admin', 'wrong'), isNull);
      expect(d.rejected, 1, reason: 'ولا من النبضة الحيّة');
      expect(await TplinkClassicService.readOnce(d.host, 'admin', '0000'), isNotNull, reason: 'اعتمادٌ آخر يُجرَّب عادةً');
      TplinkClassicService.forget(d.host);
      expect(await TplinkClassicService.readOnce(d.host, 'admin', 'wrong'), isNull);
      expect(d.rejected, 2, reason: '«حفظ وفحص» يعيد المرفوض مرّةً واحدة');
    });

    test('لا يجاوب ⇒ «غير واصل»', () async {
      final host = d.host;
      await d.stop();
      expect(await TplinkClassicService.readOnce(host, 'admin', '0000'), isNull);
      expect(TplinkClassicService.lastIssue(host)?.issue, TpClassicIssue.unreachable);
    });

    test('النبضة الحيّة: صفحة الحالة وحدها للعدّادات، والوايرلس وحدها للمتّصلين', () async {
      final a = await TplinkClassicService.sample(d.host, 'admin', '0000');
      d.rx += 500000;
      d.clients = 4;
      final b = await TplinkClassicService.sample(d.host, 'admin', '0000');
      expect(b!.rxBytes - a!.rxBytes, 500000);
      expect(await TplinkClassicService.sampleClients(d.host, 'admin', '0000'), 4);
      expect(d.paths, ['/userRpm/StatusRpm.htm', '/userRpm/StatusRpm.htm', '/userRpm/WlanStationRpm.htm']);
    });
  });

  group('فحص جهاز المشترك', () {
    late _FakeClassic d;
    late _FakeApi api;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DeviceProbeApi.clearAllCaches();
      d = _FakeClassic();
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

    test('راوتر كلاسيكيّ ⇒ لقطته من فرعه باعتماد قسم TP-Link، ودخول يوبيكويتي/هواوي لا يُرسل عليه', () async {
      api.defaults = {'tplinkUsername': 'admin', 'tplinkPassword': '0000', 'ubntUsername': 'ub', 'ubntPassword': 'ub-p'};
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(snap?.kind, DeviceKind.ubiquiti, reason: 'نفس عائلة النانو ⇒ البطاقات والتنبيهات كما هي');
      expect([snap?.ubnt?.vendor, snap?.ubnt?.peerCount, snap?.ubnt?.wanOnlineSeconds], ['tpclassic', 7, 13383]);
      await d.settle();
      expect(d.paths.where((p) => p.contains('login.cgi') || p.contains('/api/auth')), isEmpty);
      expect(d.paths.any((p) => p.contains('PPPoE')), isFalse);
      expect(DeviceProbeApi.issueFor(ip: d.host), isNull);
      final creds = await DeviceProbeApi.resolveTplinkCreds(fallbackIp: d.host);
      expect([creds?.user, creds?.pass], ['admin', '0000'], reason: 'النبضة الحيّة تقرأ بالفائز');
    });

    test('الفحص التالي يذهب لفرعه وحده — صفحات userRpm فقط', () async {
      api.defaults = {'tplinkUsername': 'admin', 'tplinkPassword': '0000'};
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNotNull);
      await d.settle();
      d.paths.clear();
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNotNull);
      await d.settle();
      expect(d.paths.where((p) => !p.startsWith('/userRpm/')), isEmpty);
    });

    test('بلا اعتماد TP-Link ⇒ لا اعتماد من عندنا عليه، والسبب «يحتاج يوزر وباسورد» باسم TP-Link', () async {
      api.defaults = {'ubntUsername': 'ub', 'ubntPassword': 'ub-p', 'ontUsername': 'o', 'ontPassword': 'o-p'};
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      await d.settle();
      expect(d.authTries, 0, reason: 'اعتماد يوبيكويتي والـONT لا يُرسلان عليه بـBasic');
      final why = DeviceProbeApi.issueFor(ip: d.host);
      expect([why?.issue, why?.vendor], [ProbeIssue.needsCredentials, 'tplink']);
    });

    test('الأوّل مرفوض والإضافيّ صحيح ⇒ يدخل بالإضافيّ ويُحفظ فائزاً، والمرفوض لا يُعاد', () async {
      api.defaults = {
        'tplinkUsername': 'cpe',
        'tplinkPassword': 'cpe-pass',
        'tplinkExtra': [
          {'username': 'admin', 'password': '0000'},
        ],
      };
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(snap?.ubnt?.vendor, 'tpclassic');
      expect(d.rejected, 1);
      expect((await DeviceProbeApi.resolveTplinkCreds(fallbackIp: d.host))?.pass, '0000');
      await d.settle();
      await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(d.rejected, 1, reason: 'يبدأ بالفائز — المرفوض لا يُرسل ثانيةً');
    });

    test('اعتمادٌ مرفوض ⇒ السبب «رُفض»، والتحديث العاديّ لا يعيده، و«حفظ وفحص» يعيده مرّة', () async {
      api.defaults = {'tplinkUsername': 'admin', 'tplinkPassword': 'wrong'};
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      expect(DeviceProbeApi.issueFor(ip: d.host)?.issue, ProbeIssue.loginRejected);
      await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect(d.rejected, 1);
      await DeviceProbeApi.probe(fallbackIp: d.host, force: true, retryLogin: true);
      expect(d.rejected, 2);
    });
  });
}
