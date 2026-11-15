// راوتر TP-Link بواجهة «$.act» القديمة بلا تعمية وكوكي خام (TL-WR840N v6 فيرموير 0.9.1 4.16 Build 180614 · TL-WR845N) —
// قِيس حيّاً ١٥ نوفمبر (قراءةٌ وحدها). راوترٌ وهميّ محلّيّ بقواعد الجهاز المقيسة: صفحة دخولٍ تحمل عدّاد المحاولات والقفل ومديراً
// واحداً، كوكي `Authorization=Basic base64(user:pass)` مع كلّ طلب (بلاه `[error]71111`)، حارس Referer، وخروجٌ يحرّر خانة المدير.
// ثمّ الفحص الكامل عبر DeviceProbeApi. الأسماء والماكات وهميّة؛ بنية الردّ من الجهاز نفسه.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/core/net/tplink_cgi_plain_service.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _loginPage({required int authTimes, required int forbidTime, required bool forbid}) => '''
<html><head><script type="text/javascript">
var isLocked=false;deleteCookie("Authorization");
function Base64Encoding(input){return input}
function PCSubWin(){if(isLocked==true){return}var auth;var password=\$.id("pcPassword").value;var userName=\$.id("userName").value;auth="Basic "+Base64Encoding(userName+":"+password);document.cookie="Authorization="+auth;window.location.reload()}
</script></head><body onload="pageLoad()"><input id="userName"><input id="pcPassword" type="password">
<script type="text/javascript">var authTimes=$authTimes; var forbidTime=$forbidTime; var modelName="TL-WR840N"; var modelDesc="TP-Link Wireless N Router WR840N "; var forbidAdminLogin=${forbid ? 1 : 0}; var forbidUserLogin=0; var usernameIsAdmin=1;</script>
</body></html>''';

const _framePage = '<html><frameset><frame src="./frame/top.htm"><frame src="./MenuRpm.htm"><frame src="./mainFrame.htm"></frameset></html>';

String _readReply(int wifi) {
  final b = StringBuffer()
    ..write('[0,0,0,0,0,0]0\nmodelName=TL-WR840N\nhardwareVersion=TL-WR840N v6 00000007\n'
        'softwareVersion=0.9.1 4.16 v0001.0 Build 180614 Rel.40494n\nupTime=312769\n')
    ..write('[1,1,1,0,0,0]1\nenable=1\nconnectionStatus=Connected\nuptime=106700\nexternalIPAddress=10.9.8.7\n')
    ..write('[1,1,2,0,0,0]1\nenable=0\nconnectionStatus=Unconfigured\nuptime=0\nexternalIPAddress=0.0.0.0\n')
    ..write('[1,1,1,0,0,0]2\nenable=1\nconnectionStatus=Connected\nuptime=0\nexternalIPAddress=169.254.137.128\naddressingType=Static\n')
    ..write('[1,1,2,0,0,0]2\nenable=0\nconnectionStatus=Unconfigured\nuptime=0\nexternalIPAddress=0.0.0.0\naddressingType=DHCP\n');
  for (var i = 1; i <= 4; i++) {
    b.write('[$i,0,0,0,0,0]3\nIPAddress=192.168.0.10$i\nMACAddress=AA:BB:CC:00:00:0$i\nhostName=phone-$i\nleaseTimeRemaining=6000\n');
  }
  for (var i = 1; i <= wifi; i++) {
    b.write('[1,1,$i,0,0,0]4\nassociatedDeviceMACAddress=AA:BB:CC:00:00:0$i\n');
  }
  b.write('[error]0\n');
  return b.toString();
}

/// WR840N v6 وهميّ بقواعد الجهاز الحيّ.
class _FakeWr840 {
  late HttpServer _s;
  String user = 'admin', pass = 'r0uter-pw';
  int authTimes = 0, forbidTime = 0, wifi = 4;

  /// مديرٌ آخر داخل الآن (من عنوانٍ ثانٍ).
  bool otherAdmin = false;

  /// قراءةٌ يردّها الجهاز بخطأ بعد دخولٍ ناجح.
  bool readBroken = false;

  final paths = <String>[];
  final bodies = <String>[];

  /// كلّ `GET /` حمل كوكي اعتماد = محاولة دخول يراها الجهاز.
  final credSends = <String>[];
  int logouts = 0, reads = 0, noReferer = 0;

  String get host => '127.0.0.1:${_s.port}';
  String cookieOf(String u, String p) => 'Authorization=Basic ${base64.encode(utf8.encode('$u:$p'))}';

  Future<void> start() async {
    _s = await HttpServer.bind('127.0.0.1', 0);
    _s.listen(_handle);
  }

  Future<void> stop() => _s.close(force: true);

  /// انتظر حتى تسكت الطلبات (فروع الخلفيّة في سباق النوع).
  Future<void> settle() async {
    var seen = paths.length;
    for (var i = 0; i < 80; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (paths.length == seen) return;
      seen = paths.length;
    }
  }

  void _text(HttpRequest r, String body, {int status = 200, String type = 'text/html; charset=utf-8'}) {
    final bytes = utf8.encode(body);
    r.response
      ..statusCode = status
      ..headers.set(HttpHeaders.contentTypeHeader, type)
      ..contentLength = bytes.length
      ..add(bytes)
      ..close();
  }

  Future<void> _handle(HttpRequest r) async {
    final q = r.uri.hasQuery ? '?${r.uri.query}' : '';
    paths.add('${r.method} ${r.uri.path}$q');
    final cookie = r.headers.value(HttpHeaders.cookieHeader) ?? '';
    final body = await utf8.decodeStream(r);
    if (body.isNotEmpty) bodies.add(body);
    final good = cookie == cookieOf(user, pass);
    if (r.uri.path == '/' && r.method == 'GET') {
      if (cookie.isEmpty) return _text(r, _loginPage(authTimes: authTimes, forbidTime: forbidTime, forbid: false));
      credSends.add(cookie);
      if (authTimes >= 10) return _text(r, _loginPage(authTimes: authTimes, forbidTime: forbidTime, forbid: false));
      if (good) {
        if (otherAdmin) return _text(r, _loginPage(authTimes: authTimes, forbidTime: forbidTime, forbid: true));
        authTimes = 0;
        return _text(r, _framePage);
      }
      authTimes++;
      return _text(r, _loginPage(authTimes: authTimes, forbidTime: forbidTime, forbid: false));
    }
    if (r.uri.path == '/cgi' && r.method == 'POST') {
      if ((r.headers.value(HttpHeaders.refererHeader) ?? '').isEmpty) {
        noReferer++;
        return _text(r, '<html>403</html>', status: 403);
      }
      if (!good) return _text(r, '[error]71111\n', type: 'text/plain; charset=utf-8');
      if (r.uri.query == '8' && body.contains('/cgi/logout')) {
        logouts++;
        return _text(r, '[cgi]0\n[error]0', type: 'text/plain; charset=utf-8');
      }
      if (r.uri.query == '1&5&5&5&6') {
        reads++;
        return _text(r, readBroken ? '[error]9805\n' : _readReply(wifi), type: 'text/plain; charset=utf-8');
      }
      return _text(r, '[error]9805\n', type: 'text/plain; charset=utf-8');
    }
    return _text(r, '<html>404</html>', status: 404);
  }

  /// طلبات الكتابة والعمليّات (ACT_SET=2 · ADD=3 · DEL=4 · OP=7) — لا يجوز أن يظهر منها شيء.
  Iterable<String> get writes => paths.where((p) {
        final m = RegExp(r'^POST /cgi\?(.*)$').firstMatch(p);
        if (m == null) return false;
        return m.group(1)!.split('&').any((t) => const {'2', '3', '4', '7'}.contains(t.split('=').first));
      });
}

class _FakeApi implements HttpClientAdapter {
  Map<String, Object?> defaults = {};

  /// إعداد المشترك (`/api/subscribers/<u>/device`) — فارغ = بلا إعداد.
  Map<String, Object?> device = {};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final Object data = o.uri.path == '/api/admin/device-defaults'
        ? {'success': true, 'defaults': defaults}
        : (o.uri.path.endsWith('/device') ? {'success': true, 'device': device} : {'success': true});
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('صفحة الدخول (صرفة)', () {
    test('تقرأ عدّاد المحاولات والقفل والمدير الآخر والطراز — وصفحة غير هذه العائلة null', () {
      final h = CgiPlainHello.parse(_loginPage(authTimes: 3, forbidTime: 0, forbid: true))!;
      expect([h.authTimes, h.adminBusy, h.locked, h.model], [3, true, false, 'TL-WR840N']);
      final locked = CgiPlainHello.parse(_loginPage(authTimes: 10, forbidTime: 1200, forbid: false))!;
      expect([locked.locked, locked.lockLeft], [true, 6000], reason: '٧٢٠٠ ث ناقص ما مضى');
      expect(CgiPlainHello.parse(_framePage), isNull);
      expect(CgiPlainHello.parse('<html>httpAutErrorArray Authorization Base64Encoding pcPassword</html>'), isNull,
          reason: 'الكوكي-MD5 (WR940N) عائلةٌ أخرى');
    });
  });

  group('القارئ', () {
    late _FakeWr840 d;

    setUp(() async {
      TplinkCgiPlainService.reset();
      d = _FakeWr840();
      await d.start();
    });

    tearDown(() => d.stop());

    test('اعتمادٌ صحيح ⇒ صفحة الحالة بلا اعتماد، دخول، قراءةٌ واحدة، خروج — والقيم كما على الجهاز', () async {
      final s = await TplinkCgiPlainService.readOnce(d.host, d.user, d.pass);
      expect(s, isNotNull);
      expect([s!.vendor, s.isRouter, s.model, s.firmware], ['tp845', true, 'TL-WR840N v6', '0.9.1 4.16 v0001.0 Build 180614 Rel.40494n']);
      expect([s.uptimeSeconds, s.wanOnlineSeconds, s.wanType], [312769, 106700, 'PPPoE']);
      expect([s.peerCount, s.dhcpCount, s.clients.length, s.clients.first.name], [4, 4, 4, 'phone-1']);
      expect(d.paths, ['GET /', 'GET /', 'POST /cgi?1&5&5&5&6', 'POST /cgi?8']);
      expect([d.credSends.length, d.reads, d.logouts, d.noReferer], [1, 1, 1, 0]);
      expect(d.writes, isEmpty, reason: 'قراءةٌ وحدها — لا ضبط ولا إعادة تشغيل ولا ضبط مصنع');
      expect(d.bodies.join().toLowerCase(), isNot(anyOf(contains('password'), contains('presharedkey'), contains('reboot'), contains('reset'))),
          reason: 'لا تُطلب كلمة سرّ PPPoE ولا الواي فاي');
      expect(TplinkCgiPlainService.lastIssue(d.host), isNull);
    });

    test('تعرّفٌ قبل القراءة بثوانٍ ⇒ صفحة الحالة لا تُطلب مرّتين', () async {
      expect(await TplinkCgiPlainService.detect(d.host), isTrue);
      expect(await TplinkCgiPlainService.readOnce(d.host, d.user, d.pass), isNotNull);
      expect(d.paths, ['GET /', 'GET /', 'POST /cgi?1&5&5&5&6', 'POST /cgi?8'], reason: 'تعرّف + دخول + قراءة + خروج');
      expect(d.credSends.length, 1);
    });

    test('كلمة سرٍّ غلط ⇒ مرفوض، يُحسب على الجهاز مرّةً واحدة، ولا يُعاد حتى «حفظ وفحص»', () async {
      expect(await TplinkCgiPlainService.readOnce(d.host, 'admin', 'wrong'), isNull);
      expect(TplinkCgiPlainService.lastIssue(d.host)?.issue, CgiPlainIssue.rejected);
      expect([d.authTimes, d.credSends.length, d.logouts, d.reads], [1, 1, 0, 0], reason: 'لم ندخل ⇒ لا قراءة ولا خروج');
      // موجةٌ ثانية وثالثة: الزوج نفسه لا يُرسل
      await TplinkCgiPlainService.readOnce(d.host, 'admin', 'wrong');
      await TplinkCgiPlainService.readOnce(d.host, 'admin', 'wrong');
      expect([d.authTimes, d.credSends.length], [1, 1]);
      expect(TplinkCgiPlainService.lastIssue(d.host)?.issue, CgiPlainIssue.rejected);
      // زوجٌ آخر يُجرَّب عاديّاً
      expect(await TplinkCgiPlainService.readOnce(d.host, d.user, d.pass), isNotNull);
      // «حفظ وفحص الجهاز» ينسى المرفوض
      TplinkCgiPlainService.forget(d.host, manual: true);
      await TplinkCgiPlainService.readOnce(d.host, 'admin', 'wrong');
      expect(d.credSends.length, 3);
    });

    test('خمس محاولاتٍ غلط على الجهاز ⇒ لا نرسل (حتى لا ينقفل)؛ بعد «حفظ وفحص» حتى السابعة، ومن الثامنة لا أبداً', () async {
      d.authTimes = 5;
      expect(await TplinkCgiPlainService.readOnce(d.host, d.user, d.pass), isNull);
      expect(TplinkCgiPlainService.lastIssue(d.host)?.issue, CgiPlainIssue.tooManyFails);
      expect(d.credSends, isEmpty, reason: 'لا اعتماد يُرسل والعدّاد عند الخمسة');

      TplinkCgiPlainService.forget(d.host, manual: true);
      expect(await TplinkCgiPlainService.readOnce(d.host, d.user, d.pass), isNotNull, reason: 'المدير صحّح الاعتماد بيده');
      expect(d.credSends.length, 1);

      d.authTimes = 8;
      TplinkCgiPlainService.forget(d.host, manual: true);
      expect(await TplinkCgiPlainService.readOnce(d.host, d.user, d.pass), isNull);
      expect(TplinkCgiPlainService.lastIssue(d.host)?.issue, CgiPlainIssue.tooManyFails);
      expect(d.credSends.length, 1, reason: 'من الثامنة لا إرسال ولو يدويّاً — العاشرة تقفل ساعتين');
    });

    test('الجهاز مقفل ⇒ لا إرسال، والباقي من القفل معروف', () async {
      d
        ..authTimes = 10
        ..forbidTime = 1200;
      expect(await TplinkCgiPlainService.readOnce(d.host, d.user, d.pass), isNull);
      final why = TplinkCgiPlainService.lastIssue(d.host);
      expect(why?.issue, CgiPlainIssue.locked);
      expect(why?.lockLeft, inInclusiveRange(5990, 6000));
      expect(d.credSends, isEmpty);
    });

    test('مديرٌ آخر داخل ⇒ مشغول: لا يُحفظ مرفوضاً، ولا نطرقه ثانيةً خلال المهلة', () async {
      d.otherAdmin = true;
      expect(await TplinkCgiPlainService.readOnce(d.host, d.user, d.pass), isNull);
      expect(TplinkCgiPlainService.lastIssue(d.host)?.issue, CgiPlainIssue.busy);
      expect([d.credSends.length, d.authTimes, d.logouts], [1, 0, 0]);
      d.otherAdmin = false;
      expect(await TplinkCgiPlainService.readOnce(d.host, d.user, d.pass), isNull, reason: 'داخل المهلة — لا طرق');
      expect(d.credSends.length, 1);
      TplinkCgiPlainService.forget(d.host);
      expect(await TplinkCgiPlainService.readOnce(d.host, d.user, d.pass), isNotNull, reason: 'الاعتماد صحيح لم يُحفظ مرفوضاً');
    });

    test('دخلنا والقراءة رجعت بخطأ ⇒ «ما رجعت قراءاته»، والخروج يُرسل دائماً', () async {
      d.readBroken = true;
      expect(await TplinkCgiPlainService.readOnce(d.host, d.user, d.pass), isNull);
      expect(TplinkCgiPlainService.lastIssue(d.host)?.issue, CgiPlainIssue.readFailed);
      expect(d.logouts, 1);
    });

    test('لا ردّ ⇒ غير واصل', () async {
      final host = d.host;
      await d.stop();
      expect(await TplinkCgiPlainService.readOnce(host, 'admin', 'x'), isNull);
      expect(TplinkCgiPlainService.lastIssue(host)?.issue, CgiPlainIssue.unreachable);
      await d.start();
    });
  });

  group('فحص جهاز المشترك', () {
    late _FakeWr840 d;
    late _FakeApi api;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DeviceProbeApi.clearAllCaches();
      d = _FakeWr840();
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

    test('WR840N v6 باعتماد قسم TP-Link ⇒ يُقرأ من أوّل فحص، ولا دخول هواوي/airOS يطرقه، والتالي لفرعه وحده', () async {
      // اعتماد ONT موجودٌ عمداً (ليثبت أنّ هواوي لا يُرسَل)؛ وبلا اعتماد UBNT ⇒ يُجرَّب ubnt/ubnt لولا البوّابة.
      api.defaults = {'tplinkUsername': d.user, 'tplinkPassword': d.pass, 'ontUsername': 'o', 'ontPassword': 'o-p'};
      final huaweiHits = <String>[];
      DeviceProbeApi.debugOnHuaweiProbe = huaweiHits.add;
      addTearDown(() => DeviceProbeApi.debugOnHuaweiProbe = null);

      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      await d.settle();
      expect(snap?.kind, DeviceKind.ubiquiti, reason: 'نفس عائلة النانو ⇒ البطاقات والتنبيهات كما هي');
      final u = snap!.ubnt!;
      expect([u.vendor, u.isRouter, u.model, u.peerCount, u.wanOnlineSeconds, u.wanType, u.dhcpCount],
          ['tp845', true, 'TL-WR840N v6', 4, 106700, 'PPPoE', 4]);
      expect(u.lanHealth, 'unknown', reason: 'راوتر بلا منافذ مصدَّرة ⇒ لا «كيبل» أحمر كاذب');
      expect(DeviceProbeApi.issueFor(ip: d.host), isNull);
      expect(huaweiHits, isEmpty, reason: 'راوتر TP-Link معرّفٌ ⇒ دخول هواوي لا يطرقه');
      expect(d.paths.where((p) => p.contains('login.cgi') || p.contains('/api/auth')), isEmpty, reason: 'ولا دخول airOS');
      expect([d.credSends.length, d.authTimes, d.logouts], [1, 0, 1]);
      expect(d.writes, isEmpty);
      final creds = await DeviceProbeApi.resolveTplinkCreds(fallbackIp: d.host);
      expect([creds?.user, creds?.pass], [d.user, d.pass]);

      // الفحص التالي: فرعه وحده — صفحة الدخول والـcgi فقط
      d.paths.clear();
      d.wifi = 2;
      final again = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      await d.settle();
      expect(again?.ubnt?.peerCount, 2);
      expect(d.paths.every((p) => p == 'GET /' || p.startsWith('POST /cgi?')), isTrue, reason: '${d.paths}');
    });

    test('الأوّل مرفوض والإضافيّ صحيح ⇒ يدخل بالإضافيّ ويُحفظ فائزاً، والمرفوض لا يُعاد', () async {
      api.defaults = {
        'tplinkUsername': 'cpe',
        'tplinkPassword': 'cpe-pass',
        'tplinkExtra': [
          {'username': d.user, 'password': d.pass},
        ],
      };
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      await d.settle();
      expect(snap?.ubnt?.vendor, 'tp845');
      expect(d.credSends, [d.cookieOf('cpe', 'cpe-pass'), d.cookieOf(d.user, d.pass)]);
      d.credSends.clear();
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNotNull);
      await d.settle();
      expect(d.credSends, [d.cookieOf(d.user, d.pass)], reason: 'الفائز أوّلاً والمرفوض لا يُرسل ثانيةً');
    });

    test('كلّ الاعتمادات غلط ⇒ «بيانات الدخول مرفوضة»، كلٌّ يُرسل مرّةً واحدة ولا يُعاد في الموجات التالية', () async {
      api.defaults = {
        'tplinkUsername': 'a',
        'tplinkPassword': 'x1',
        'tplinkExtra': [
          {'username': 'b', 'password': 'x2'},
        ],
      };
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      await d.settle();
      final why = DeviceProbeApi.issueFor(ip: d.host);
      expect([why?.issue, why?.vendor], [ProbeIssue.loginRejected, 'tplink']);
      expect(d.authTimes, 2);
      for (var i = 0; i < 3; i++) {
        expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      }
      await d.settle();
      expect(d.authTimes, 2, reason: 'ثلاث موجاتٍ بعدها بلا أيّ محاولة — العدّاد لا يتحرّك نحو القفل');
      expect(d.paths.where((p) => p.contains('login.cgi') || p.contains('/api/auth')), isEmpty, reason: 'ولا يسقط لدخول airOS');
    });

    test('بلا اعتماد TP-Link ⇒ «يحتاج يوزر وباسورده» ولا شيء يُرسل', () async {
      api.defaults = {'ontUsername': 'o', 'ontPassword': 'o-p'};
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      await d.settle();
      final why = DeviceProbeApi.issueFor(ip: d.host);
      expect([why?.issue, why?.vendor], [ProbeIssue.needsCredentials, 'tplink']);
      expect(d.credSends, isEmpty);
    });

    test('الجهاز مقفل ⇒ الكرت يعرف الباقي من القفل ولا إرسال', () async {
      d
        ..authTimes = 10
        ..forbidTime = 6600;
      api.defaults = {'tplinkUsername': d.user, 'tplinkPassword': d.pass};
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      await d.settle();
      final why = DeviceProbeApi.issueFor(ip: d.host);
      expect(why?.issue, ProbeIssue.locked);
      expect(why?.lockLeft, inInclusiveRange(590, 600));
      expect(d.credSends, isEmpty);
    });

    test('النوع مثبَّت «Ubiquiti» لمشتركٍ جهازه هذا الراوتر ⇒ يُعرَّف ويُقرأ، لا دخول airOS عليه', () async {
      api
        ..defaults = {'tplinkUsername': d.user, 'tplinkPassword': d.pass, 'ubntUsername': 'ub', 'ubntPassword': 'ub-p'}
        ..device = {'deviceType': deviceKindToString(DeviceKind.ubiquiti)};
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, subscriberUsername: 'sub1', force: true);
      await d.settle();
      expect(snap?.ubnt?.vendor, 'tp845');
      expect(d.paths.where((p) => p.contains('login.cgi') || p.contains('/api/auth')), isEmpty);
    });
  });
}
