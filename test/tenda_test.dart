// راوتر Tenda (GoAhead — F3 V12.01.01.42 وأخوه V02.03.01.110، قِيسا حيّاً ١٢ نوفمبر بدخولٍ واحد لكلٍّ): قارئٌ بقوالب بنية الردود
// الحيّة (أسماءٌ وماكاتٌ وهميّة)، وراوترٌ وهميّ محلّيّ بالقواعد المقيسة (كلمة سرٍّ وحدها base64، كوكي ecos_pw، ?1 رفض، ?2 أربع
// جلسات، goform/getStatus وgetQos، الخروج loginOut)، ثمّ الفحص الكامل عبر DeviceProbeApi.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/core/net/tenda_service.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _status({String up = '8', String down = '294', String online = '9', String conn = '282886'}) => {
      'internetStatus': {'wanConnectStatus': '13103060', 'newLanIP': '255.255.255.255', 'lanWanIPConflict': 'false'},
      'deviceStastics': {'statusOnlineNumber': online, 'statusBlackNum': '0', 'statusUpSpeed': up, 'statusDownSpeed': down, 'wifiRate': '-59', 'routerName': 'Test.', 'extendName': ''},
      'systemInfo': {'wanConnectTime': conn, 'wanType': 'pppoe', 'statusWanMAC': 'AA:BB:CC:00:00:01', 'lanIP': '192.168.44.1', 'statusWanIP': '100.66.1.197', 'softVersion': 'V12.01.01.42_multi'},
      'wanAdvCfg': {'wanType': 'pppoe', 'wanMTU': '1480', 'wanSpeed': 'Auto', 'wanSpeedCurrent': '100', 'macClone': 'default'},
    };

Map<String, dynamic> _qos() => {
      'localhost': {'localhost': '100.66.0.1', 'lanMask': '255.255.255.0'},
      'onlineList': [
        {'qosListHostname': 'Phone-A', 'qosListRemark': '', 'qosListIP': '192.168.44.165', 'qosListConnectType': 'wifi', 'qosListMac': 'aa:bb:cc:00:01:01', 'qosListDownSpeed': '0.00', 'qosListUpSpeed': '0.00'},
        {'qosListHostname': 'Unknown', 'qosListRemark': 'غرفة الضيوف', 'qosListIP': '192.168.44.107', 'qosListConnectType': 'wifi', 'qosListMac': 'aa:bb:cc:00:01:02', 'qosListDownSpeed': '1148.00', 'qosListUpSpeed': '11.00'},
        {'qosListHostname': 'Unknown', 'qosListRemark': '', 'qosListIP': '192.168.44.157', 'qosListConnectType': 'wired', 'qosListMac': 'aa:bb:cc:00:01:03', 'qosListDownSpeed': '0.00', 'qosListUpSpeed': '0.00'},
      ],
    };

/// راوترٌ وهميّ بقواعد Tenda المقيسة.
class _FakeTenda {
  late HttpServer server;
  String pass = '521993';
  final sessions = <String>{};
  int maxSessions = 4;
  int logins = 0;
  int wrong = 0;
  int logouts = 0;
  String down = '294';
  final paths = <String>[];
  final modules = <String>[];
  final passwordsSeen = <String>[];
  int _n = 0;

  String get host => '127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final path = req.uri.path;
      paths.add(path);
      final res = req.response..headers.set('Server', 'GoAhead-Webs');
      final cookie = RegExp(r'ecos_pw=([^;]+)').firstMatch(req.headers.value(HttpHeaders.cookieHeader) ?? '')?.group(1);
      final authed = cookie != null && sessions.contains(cookie);
      if (path == '/') {
        res.statusCode = 302;
        res.headers.set(HttpHeaders.locationHeader, 'http://$host/login.html');
      } else if (path == '/login.html') {
        res.write('<html><head><title>Tenda | LOGIN</title></head><body><form name="Login" method="post" action="/login/Auth">'
            '<input type="hidden" name="password" id="password"></form></body></html>');
      } else if (path == '/login/Auth' && req.method == 'POST') {
        logins++;
        final body = await utf8.decoder.bind(req).join();
        final pw = Uri.splitQueryString(body)['password'] ?? '';
        passwordsSeen.add(pw);
        res.statusCode = 302;
        if (pw != base64.encode(utf8.encode(pass))) {
          wrong++;
          res.headers.set(HttpHeaders.locationHeader, 'http://$host/login.html?1');
        } else if (sessions.length >= maxSessions) {
          res.headers.set(HttpHeaders.locationHeader, 'http://$host/login.html?2');
        } else {
          final s = 'S${_n++}';
          sessions.add(s);
          res.headers.set(HttpHeaders.locationHeader, 'http://$host/index.html');
          res.headers.add(HttpHeaders.setCookieHeader, 'ecos_pw=$s; path=/');
        }
      } else if (path.startsWith('/goform/')) {
        if (!authed) {
          res.statusCode = 302;
          res.headers.set(HttpHeaders.locationHeader, 'http://$host/login.html');
        } else if (path == '/goform/loginOut' && req.method == 'POST') {
          await utf8.decoder.bind(req).join();
          logouts++;
          sessions.remove(cookie);
          res.write('{"errCode":"0"}');
        } else {
          final mods = req.uri.queryParameters['modules'] ?? '';
          modules.add(mods);
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode(path == '/goform/getStatus' ? _status(down: down) : _qos()));
        }
      } else {
        res.statusCode = 404;
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
  group('قراءة ردود Tenda (صرفة)', () {
    test('الحالة + المتّصلون ⇒ لقطة الراوتر: العدّ، مدّة الاتّصال، PPPoE، الإصدار، سرعة منفذ الإنترنت', () {
      final s = TendaParse.status(status: _status(), qos: _qos(), baseUrl: 'http://h')!;
      expect([s.vendor, s.isRouter, s.isTenda, s.peerCount, s.wanOnlineSeconds, s.wanType, s.firmware, s.wanLinkMbps],
          ['tenda', true, true, 9, 282886, 'PPPoE', 'V12.01.01.42_multi', 100]);
      expect(s.clients.map((c) => [c.mac, c.ip, c.name, c.wired]).toList(), [
        ['AA:BB:CC:00:01:01', '192.168.44.165', 'Phone-A', false],
        ['AA:BB:CC:00:01:02', '192.168.44.107', 'غرفة الضيوف', false],
        ['AA:BB:CC:00:01:03', '192.168.44.157', null, true],
      ]);
      expect(s.lanHealth, 'unknown', reason: 'راوترٌ بلا منافذ ⇒ لا أحمر كاذب');
      final round = UbiquitiStatus.fromJson(s.toJson());
      expect([round.vendor, round.wanLinkMbps, round.clients.length], ['tenda', 100, 3]);
    });

    test('الترافيك KB/s ⇒ بت/ثانية؛ قيمةٌ غير مقروءة ⇒ null لا صفر', () {
      expect(TendaParse.rates(_status(up: '8', down: '294')), (down: 294 * 1024 * 8, up: 8 * 1024 * 8));
      expect(TendaParse.rates(_status(down: '')), isNull);
      expect(TendaParse.status(status: const {}, baseUrl: 'h'), isNull);
    });
  });

  group('الراوتر الوهميّ', () {
    late _FakeTenda d;
    setUp(() async {
      TendaService.reset();
      d = _FakeTenda();
      await d.start();
    });
    tearDown(() => d.stop());

    test('التعرّف: صفحة الدخول وحدها بلا اعتماد', () async {
      expect(await TendaService.detect(d.host), isTrue);
      expect(d.paths, ['/login.html']);
      expect(d.logins, 0);
    });

    test('قراءةٌ كاملة: دخولٌ واحد بكلمة السرّ base64، الحالة والمتّصلون، خروجٌ دائماً — ولا وحدة كلمة الوايفاي', () async {
      final u = await TendaService.readOnce(d.host, '521993');
      expect([u?.vendor, u?.peerCount, u?.clients.length, u?.wanLinkMbps], ['tenda', 9, 3, 100]);
      expect([d.logins, d.logouts, d.sessions.length], [1, 1, 0]);
      expect(d.modules.any((m) => m.contains('wifiBasicCfg')), isFalse, reason: 'فيها كلمة الوايفاي');
      expect(d.modules.toSet(), {TendaService.statusModules, TendaService.qosModules});
      expect(TendaService.lastIssue(d.host), isNull);
    });

    test('كلمة سرٍّ فيها «+» و«=» في base64 تصل كما هي (ترميز النموذج)', () async {
      d.pass = '>>>a';
      expect(await TendaService.readOnce(d.host, '>>>a'), isNotNull);
      expect(d.passwordsSeen.single, base64.encode(utf8.encode('>>>a')));
    });

    test('كلمة سرٍّ غلط ⇒ رفضٌ يُحفظ (لا يُعاد ولا من النبضة)، و«نسيان» يعيده مرّة', () async {
      expect(await TendaService.readOnce(d.host, 'wrong'), isNull);
      expect(TendaService.lastIssue(d.host)?.issue, TendaIssue.rejected);
      expect(await TendaService.readOnce(d.host, 'wrong'), isNull);
      expect(await TendaService.sample(d.host, 'wrong'), isNull);
      expect(d.wrong, 1);
      TendaService.forget(d.host);
      expect(await TendaService.readOnce(d.host, 'wrong'), isNull);
      expect(d.wrong, 2);
    });

    test('أربع جلساتٍ مفتوحة ⇒ «مشغول» (لا طرد ولا إعادة)', () async {
      d.sessions.addAll(['a', 'b', 'c', 'd']);
      expect(await TendaService.readOnce(d.host, '521993'), isNull);
      expect(TendaService.lastIssue(d.host)?.issue, TendaIssue.busy);
      expect(d.sessions.length, 4);
    });

    test('النبضة: دخول ⇒ الحالة وحدها ⇒ خروج؛ الترافيك والعدّ ومدّة الاتّصال', () async {
      final a = await TendaService.sample(d.host, '521993');
      expect([a?.downBps, a?.upBps, a?.online, a?.wanOnlineSeconds], [294 * 8192, 8 * 8192, 9, 282886]);
      expect(d.paths.where((p) => p == '/goform/getQos'), isEmpty);
      expect([d.logins, d.logouts, d.sessions.length], [1, 1, 0]);
    });
  });

  group('فحص جهاز المشترك (Tenda)', () {
    late _FakeTenda d;
    late _FakeApi api;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DeviceProbeApi.clearAllCaches();
      d = _FakeTenda();
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

    test('راوتر Tenda ⇒ لقطته من فرعه بقائمة «باسورد فقط»، والفائز للنبضة، ولا دخول يوبيكويتي عليه', () async {
      api.defaults = {'tprouterPassword': '521993', 'ubntUsername': 'ub', 'ubntPassword': 'ub-p'};
      final snap = await DeviceProbeApi.probe(fallbackIp: d.host, force: true);
      expect([snap?.kind, snap?.ubnt?.vendor, snap?.ubnt?.peerCount, snap?.ubnt?.wanLinkMbps], [DeviceKind.ubiquiti, 'tenda', 9, 100]);
      await d.settle();
      expect([d.logins, d.logouts], [1, 1]);
      expect(d.paths.where((p) => p.contains('login.cgi') || p.contains('/api/auth')), isEmpty);
      final creds = await DeviceProbeApi.resolveTplinkCreds(fallbackIp: d.host);
      expect(creds?.pass, '521993');
    });

    test('بلا كلمة سرّ ⇒ لا تخمين، والسبب باسم Tenda', () async {
      api.defaults = {'ubntUsername': 'ub', 'ubntPassword': 'ub-p'};
      expect(await DeviceProbeApi.probe(fallbackIp: d.host, force: true), isNull);
      await d.settle();
      expect(d.logins, 0);
      final why = DeviceProbeApi.issueFor(ip: d.host);
      expect([why?.issue, why?.vendor], [ProbeIssue.needsCredentials, 'tenda']);
    });
  });

  test('كلمة سرّ المشترك وحدها (بلا يوزر) تدخل قائمة «باسورد فقط» أوّلاً — كما حفظها المالك لمشتركَي Tenda', () {
    final c = DeviceProbeApi.candidatesFor(
      const DeviceConfig(password: 'sub-pass'),
      const AdminDeviceDefaults(tprouterPassword: 'admin-pass'),
    );
    expect(c.tprouter.map((e) => e.password).toList(), ['sub-pass', 'admin-pass']);
    expect(c.tprouter.every((e) => e.username.isEmpty), isTrue);
  });
}
