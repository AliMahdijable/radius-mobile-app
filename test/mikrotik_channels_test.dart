import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';
import 'package:rad_mysvcs/api/mikrotik_binary_api.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/api/routeros_channel.dart';

/// ٢٧ أكتوبر — المالك: «لازم نفعل ميزات ssh و snmp وويب للمايكروتيك اكو اجهزه هواي مقفول عليها».
/// منفذ الـAPI مقفول ⇒ الويب (REST) ثمّ SSH بالحساب نفسه، وكلّ طريقٍ يُرجع صفوف الـAPI نفسها.
class _Refused implements RouterOsChannel {
  _Refused(this.log, this.name, {this.auth = false});
  final List<String> log;
  final String name;
  final bool auth;
  @override
  String get via => name;
  @override
  Future<void> open() async {
    log.add('open:$name');
    if (auth) throw MikrotikBinaryException('invalid user name or password (6)', code: 'auth');
    throw const SocketException('Connection refused');
  }

  @override
  Future<List<Map<String, String>>> query(List<String> words, {bool debugLog = false}) async => const [];
  @override
  Future<void> close() async {}
}

/// LHG 60G (محطّة) كما يردّ REST في RouterOS 7 — القيم نصوصٌ دائماً (التوثيق الرسميّ).
const _lhgStation = <String, Object>{
  'GET /rest/system/identity': {'name': 'LHG-tower'},
  'GET /rest/system/resource': {
    'uptime': '2w3d4h5m6s',
    'version': '7.15.3 (stable)',
    'board-name': 'LHG 60G',
    'architecture-name': 'arm',
    'cpu-load': '4',
    'free-memory': '201326592',
    'total-memory': '268435456',
    'cpu-count': '4',
    'cpu-frequency': '716',
  },
  'GET /rest/interface': [
    {'name': 'ether1', 'type': 'ether', 'running': 'true', 'disabled': 'false', 'rx-byte': '1000', 'tx-byte': '2000'},
    {'name': 'wlan60-1', 'type': 'w60g', 'running': 'true', 'disabled': 'false', 'rx-byte': '5000', 'tx-byte': '6000'},
  ],
  'GET /rest/system/health': [
    {'name': 'cpu-temperature', 'value': '52', 'type': 'C'},
  ],
  'GET /rest/ppp/active': <Object>[],
  'POST /rest/interface/ethernet/monitor': [
    {'name': 'ether1', 'status': 'link-ok', 'rate': '1Gbps', 'full-duplex': 'true'},
  ],
  'GET /rest/interface/w60g': [
    {'name': 'wlan60-1', 'mode': 'station-bridge', 'ssid': 'tower-60', 'frequency': 'auto', 'disabled': 'false', 'running': 'true'},
  ],
  'GET /rest/interface/w60g/station': <Object>[],
  'POST /rest/interface/w60g/monitor': [
    {
      'connected': 'true',
      'frequency': '60480',
      'remote-address': '00:11:22:33:44:55',
      'mcs': '8',
      'phy-rate': '2.3Gbps',
      'signal': '80',
      'rssi': '-55',
      'tx-sector': '28',
      'tx-sector-info': 'center',
      'distance': '160.9m',
    },
  ],
  'GET /rest/ip/dhcp-server/lease': <Object>[],
  'GET /rest/ip/arp': <Object>[],
};

Future<(HttpServer, List<String>)> _restServer(Map<String, Object> routes, {String auth = 'admin:pw'}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final seen = <String>[];
  server.listen((req) async {
    final key = '${req.method} ${req.uri.path}';
    seen.add(req.uri.query.isEmpty ? key : '$key?${req.uri.query}');
    // كخادم RouterOS الحقيقيّ (netPower 16P، 7.19.6): جسمٌ مقطّع (chunked) لا يُقرأ ⇒ «missing =.id=».
    if (req.method == 'POST' && req.headers.contentLength < 0) {
      req.response.statusCode = 400;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'error': 400, 'message': 'Bad Request', 'detail': 'missing =.id='}));
      await req.response.close();
      return;
    }
    if (req.method == 'POST') seen.add('body:${await utf8.decoder.bind(req).join()}');
    final ok = req.headers.value(HttpHeaders.authorizationHeader) == 'Basic ${base64.encode(utf8.encode(auth))}';
    req.response.headers.contentType = ContentType.json;
    if (!ok) {
      req.response.statusCode = 401;
      req.response.write(jsonEncode({'error': 401, 'message': 'Unauthorized'}));
    } else if (routes.containsKey(key)) {
      req.response.write(jsonEncode(routes[key]));
    } else {
      req.response.statusCode = 404;
      req.response.write(jsonEncode({'error': 404, 'message': 'Not Found'}));
    }
    await req.response.close();
  });
  return (server, seen);
}

/// قناةٌ بصفوفٍ ثابتة لكلّ أمر — لا شبكة.
class _Canned implements RouterOsChannel {
  _Canned(this.rows, {this.name = 'API'});
  final Map<String, List<Map<String, String>>> rows;
  final String name;
  @override
  String get via => name;
  @override
  Future<void> open() async {}
  @override
  Future<List<Map<String, String>>> query(List<String> words, {bool debugLog = false}) async {
    final r = rows[words.first];
    if (r == null) throw MikrotikBinaryException('no such command');
    return r;
  }

  @override
  Future<void> close() async {}
}

void main() {
  tearDown(() {
    MikrotikApi.resetRoutesForTest();
    MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => throw UnimplementedError(route);
    MikrotikApi.portProbe = (ip, port) async => false;
  });

  group('ترتيب الطرق', () {
    test('API أوّلاً ثمّ الويب ثمّ SSH — ومنفذٌ خاصّ للـAPI يبقى له (جهاز نقله إلى 8080)', () {
      expect(MikrotikApi.routeOrder().map((r) => '${r.route}:${r.port}'),
          ['api:8728', 'rest-https:443', 'rest-http:80', 'ssh:22']);
      expect(MikrotikApi.routeOrder(protocol: 'api', apiPort: 8080).first, (route: 'api', port: 8080));
    });
    test('منفذ 443/80 مسجَّلٌ للـAPI يعني الويب', () {
      expect(MikrotikApi.routeOrder(protocol: 'api', apiPort: 443).first.route, 'rest-https');
      expect(MikrotikApi.routeOrder(protocol: 'api', apiPort: 80).first.route, 'rest-http');
    });
    test('SSH مختاراً: SSH بمنفذه أوّلاً', () {
      expect(MikrotikApi.routeOrder(protocol: 'ssh', apiPort: 2222).first, (route: 'ssh', port: 2222));
    });
  });

  group('REST — ترجمة الأوامر', () {
    test('print ⇒ GET بالمسار و.proplist', () {
      final r = RestRouterOsChannel.requestFor(['/system/resource/print', '=.proplist=board-name']);
      expect(r.method, 'GET');
      expect(r.path, '/rest/system/resource');
      expect(r.query, {'.proplist': 'board-name'});
    });
    test('monitor ⇒ POST بجسمٍ من الكلمات (once فارغ كالتوثيق)', () {
      final r = RestRouterOsChannel.requestFor(['/interface/w60g/monitor', '=numbers=wlan60-1', '=once=']);
      expect(r.method, 'POST');
      expect(r.path, '/rest/interface/w60g/monitor');
      expect(r.body, {'numbers': 'wlan60-1', 'once': ''});
    });
    test('الكائن المفرد صفٌّ واحد، والقيم نصوص', () {
      expect(RestRouterOsChannel.rowsFrom({'cpu-load': '4', 'x': 5}), [
        {'cpu-load': '4', 'x': '5'}
      ]);
      expect(RestRouterOsChannel.rowsFrom([]), isEmpty);
    });
    test('الأخطاء: 401 دخول، 404 «no such command» كالـAPI', () {
      expect(RestRouterOsChannel.errorFor(401, '').code, 'auth');
      expect(RestRouterOsChannel.errorFor(404, '{"error":404,"message":"Not Found"}').message, contains('no such command'));
      expect(RestRouterOsChannel.errorFor(406, '{"error":406,"message":"Not Acceptable","detail":"no such command or directory (remove)"}').message,
          'no such command or directory (remove)');
    });
  });

  group('API مقفول ⇒ الويب', () {
    test('🚨 LHG 60G: يُقرأ كاملاً عبر REST — الوصلة والتردّد الفعليّ والسرعة', () async {
      final (server, seen) = await _restServer(_lhgStation);
      addTearDown(() => server.close(force: true));
      final log = <String>[];
      MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => switch (route) {
            'rest-http' => RestRouterOsChannel(host: ip, port: server.port, https: false, user: user, pass: pass),
            _ => _Refused(log, route),
          };
      MikrotikApi.portProbe = (ip, port) async => port == 80;

      final s = await MikrotikApi.fetchStatsFor(
          ip: '127.0.0.1', protocol: 'api', creds: {'user': 'admin', 'pass': 'pw'});

      expect(log, ['open:api'], reason: 'الـAPI جُرّب أوّلاً فرُفض');
      expect(s.via, 'الويب');
      expect(s.boardName, 'LHG 60G');
      expect(s.temperature, 52);
      expect(s.memUsedPercent, 25);
      expect(s.interfaces.firstWhere((i) => i.name == 'ether1').linkSpeed, '1Gbps');
      final w = s.wirelessInterfaces.single;
      expect(w.is60g, isTrue);
      expect(w.frequency, 60480, reason: 'الإعداد auto — والفعليّ من monitor');
      final l = s.w60gLinks.single;
      expect(l.connected, isTrue);
      expect(l.rssi, -55);
      expect(l.signalPercent, 80);
      expect(l.phyRateMbps, 2300);
      expect(l.mcs, 8);
      expect(l.distanceMeters, 160.9);
      expect(l.sectorText, '28 · center');
      expect(l.remoteMac, '00:11:22:33:44:55');
      expect(s.wirelessClients, isEmpty, reason: 'لا «عملاء» بإشارة 0 من جدول المحطّات');
      expect(s.isAccessPoint, isFalse);
      expect(seen, contains('body:{"numbers":"wlan60-1","once":""}'));
      expect(seen.where((x) => x.startsWith('GET /rest/interface/wireless/registration-table')), isEmpty,
          reason: 'لا راديو 5 GHz ⇒ لا جدول تسجيل');
    });

    test('النبضة التالية تبدأ بالويب مباشرةً (الطريق محفوظ)', () async {
      final (server, _) = await _restServer(_lhgStation);
      addTearDown(() => server.close(force: true));
      final log = <String>[];
      MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) {
        log.add('make:$route');
        return route == 'rest-http'
            ? RestRouterOsChannel(host: ip, port: server.port, https: false, user: user, pass: pass)
            : _Refused(log, route);
      };
      MikrotikApi.portProbe = (ip, port) async => port == 80;
      await MikrotikApi.fetchStatsFor(ip: '127.0.0.1', creds: {'user': 'admin', 'pass': 'pw'}, vitalsOnly: true);
      log.clear();
      await MikrotikApi.fetchStatsFor(ip: '127.0.0.1', creds: {'user': 'admin', 'pass': 'pw'}, vitalsOnly: true);
      expect(log, ['make:rest-http']);
    });

    test('كلمة مرورٍ خاطئة لا تُجرَّب على طريقٍ آخر', () async {
      final log = <String>[];
      MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => _Refused(log, route, auth: route == 'api');
      MikrotikApi.portProbe = (ip, port) async => true;
      await expectLater(
        MikrotikApi.fetchStatsFor(ip: '127.0.0.1', creds: {'user': 'admin', 'pass': 'x'}),
        throwsA(isA<MikrotikBinaryException>().having((e) => e.code, 'code', 'auth')),
      );
      expect(log, ['open:api']);
    });

    test('كلّ الطرق مقفولة والمضيف حيّ ⇒ رسالة تقول ماذا يُفتح', () async {
      final log = <String>[];
      MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => _Refused(log, route);
      MikrotikApi.portProbe = (ip, port) async => false;
      await expectLater(
        MikrotikApi.fetchStatsFor(ip: '127.0.0.1', creds: {'user': 'admin', 'pass': 'pw'}),
        throwsA(isA<MikrotikBinaryException>().having((e) => e.message, 'message', contains('IP ← Services'))),
      );
      expect(log, ['open:api'], reason: 'منافذ البدائل مقفولة ⇒ لا مهلة لكلّ طريق');
    });

    test('بيانات REST خاطئة ⇒ رسالة دخول لا «تعذّر الوصول»', () async {
      final (server, _) = await _restServer(_lhgStation, auth: 'admin:other');
      addTearDown(() => server.close(force: true));
      final log = <String>[];
      MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => route == 'rest-http'
          ? RestRouterOsChannel(host: ip, port: server.port, https: false, user: user, pass: pass)
          : _Refused(log, route);
      MikrotikApi.portProbe = (ip, port) async => port == 80;
      await expectLater(
        MikrotikApi.fetchStatsFor(ip: '127.0.0.1', creds: {'user': 'admin', 'pass': 'pw'}),
        throwsA(isA<MikrotikBinaryException>().having((e) => e.code, 'code', 'auth')),
      );
    });
  });

  group('الصحّة (حيّاً من netPower 16P بـ7.19.6)', () {
    test('🚨 psu1 25.3V وpsu2 0V (غير موصول) ⇒ الفولتيّة 25.3 لا «0.0 غير طبيعيّة»، والتيّار واستهلاك PoE', () async {
      final ch = _Canned({
        '/system/resource/print': [
          {'board-name': 'netPower 16P', 'version': '7.19.6 (stable)', 'cpu-load': '6', 'total-memory': '268435456', 'free-memory': '193064960'}
        ],
        '/interface/print': const [],
        '/system/health/print': [
          {'name': 'poe-out-consumption', 'value': '47.3', 'type': 'W'},
          {'name': 'cpu-temperature', 'value': '42', 'type': 'C'},
          {'name': 'psu1-voltage', 'value': '25.3', 'type': 'V'},
          {'name': 'psu2-voltage', 'value': '0', 'type': 'V'},
          {'name': 'psu1-current', 'value': '2', 'type': 'A'},
          {'name': 'psu2-current', 'value': '0', 'type': 'A'},
        ],
      });
      MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => ch;
      final s = await MikrotikApi.fetchStatsFor(ip: '127.0.0.1', creds: {'user': 'admin', 'pass': 'pw'}, vitalsOnly: true);
      expect(s.voltage, 25.3);
      expect(s.currentAmps, 2);
      expect(s.powerWatts, 47.3);
      expect(s.temperature, 42);
    });

    test('كلّ المداخل صفر ⇒ لا قراءة (شرطة) لا 0.0', () async {
      MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => _Canned({
            '/system/resource/print': [
              {'board-name': 'x', 'cpu-load': '1', 'total-memory': '100', 'free-memory': '50'}
            ],
            '/interface/print': const [],
            '/system/health/print': [
              {'name': 'psu1-voltage', 'value': '0', 'type': 'V'},
            ],
          });
      final s = await MikrotikApi.fetchStatsFor(ip: '127.0.0.1', creds: {'user': 'admin', 'pass': 'pw'}, vitalsOnly: true);
      expect(s.voltage, isNull);
    });
  });

  group('فولتيّة RouterOS 6 بأعشار الفولت (٣٠ أكتوبر — BaseBox 5 بـ6.34.3 ظهر «239.0 V» بالأحمر)', () {
    Future<MikrotikStats> read(String via, String version, Map<String, String> health) {
      MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => _Canned({
            '/system/resource/print': [
              {'board-name': 'BaseBox 5', 'version': version, 'cpu-load': '31', 'total-memory': '67108864', 'free-memory': '44040192'}
            ],
            '/interface/print': const [],
            '/system/health/print': [health],
          }, name: via);
      return MikrotikApi.fetchStatsFor(ip: '127.0.0.1', creds: {'user': 'admin', 'pass': 'pw'}, vitalsOnly: true);
    }

    test('🚨 سكربت 6.x عبر SSH: «239» ⇒ 23.9V، و«50» ⇒ 5.0V؛ الحرارة كما هي', () async {
      final s = await read('SSH', '6.34.3 (stable)', {'voltage': '239', 'temperature': '36'});
      expect(s.voltage, 23.9);
      expect(s.temperature, 36);
      expect((await read('SSH', '6.49.10 (long-term)', {'voltage': '50'})).voltage, 5.0);
    });

    test('الـAPI: ما فوق 60 أعشارٌ حتماً والعشريّ فولتٌ كما هو؛ وRouterOS 7 بلا قسمة', () async {
      expect((await read('API', '6.34.3 (stable)', {'voltage': '239'})).voltage, 23.9);
      expect((await read('API', '6.48.6 (long-term)', {'voltage': '24.1'})).voltage, 24.1);
      expect((await read('API', '6.48.6 (long-term)', {'voltage': '24'})).voltage, 24.0);
      expect((await read('SSH', '7.15.3 (stable)', {'voltage': '24'})).voltage, 24.0, reason: 'v7 ليس أعشاراً');
    });

    test('healthVolts: صفرٌ/سالبٌ/غير مقروءٍ/خارج المعقول ⇒ null (شرطة لا رقمٌ كاذب)', () {
      expect(MikrotikApi.healthVolts('23.9V'), 23.9);
      expect(MikrotikApi.healthVolts('0'), isNull);
      expect(MikrotikApi.healthVolts('-5'), isNull);
      expect(MikrotikApi.healthVolts('x'), isNull);
      expect(MikrotikApi.healthVolts('2390'), isNull, reason: '239V بعد القسمة — لا يُعقل');
      expect(MikrotikApi.healthVolts('239', decivoltInts: true), 23.9);
      expect(MikrotikApi.healthVolts('24.1', decivoltInts: true), 24.1, reason: 'العشريّ فولتٌ دائماً');
    });
  });

  group('فحص «حيّ؟» لمايكروتك (٣٠ أكتوبر — «فقدان الحزم 100%» وهو يُقرأ حيّاً عبر SSH)', () {
    setUp(NetworkDevicesApi.resetAltReachForTest);

    Future<(ServerSocket, List<int>)> listening() async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = <int>[];
      s.listen((c) {
        accepted.add(1);
        c.destroy();
      });
      addTearDown(s.close);
      return (s, accepted);
    }

    Future<int> closedPort() async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final p = s.port;
      await s.close();
      return p;
    }

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));

    test('المنافذ البديلة: بقيّة طرق القراءة بلا 80 (وسيط الموبايل يقبل أيّ عنوانٍ عليه)', () {
      expect(MikrotikApi.fallbackPorts(), [443, 22]);
      expect(MikrotikApi.fallbackPorts(apiPort: 8080), [443, 22]);
      expect(MikrotikApi.fallbackPorts(apiPort: 443), [8728, 22]);
      expect(MikrotikApi.fallbackPorts(protocol: 'ssh', apiPort: 2222), [8728, 443]);
    });

    test('🚨 المنفذ المسجَّل مرفوض (أقفل الـAPI) وSSH مفتوح ⇒ حيّ — والتثبيت مرّةً كلّ ٥ دقائق لا مع كلّ فحص', () async {
      final api = await closedPort();
      final (ssh, accepted) = await listening();
      var r = await NetworkDevicesApi.mikrotikProbe('127.0.0.1', api, [ssh.port]);
      expect([r.status, r.packetLoss], ['online', 0.0]);
      expect(r.responseMs, isNotNull);
      await settle();
      expect(accepted.length, 1);
      for (var i = 0; i < 3; i++) {
        r = await NetworkDevicesApi.mikrotikProbe('127.0.0.1', api, [ssh.port]);
        expect(r.status, 'online');
      }
      await settle();
      expect(accepted.length, 1, reason: 'لا طرق 22 مع كلّ فحصٍ دوريّ (قواعد حماية التخمين تحظر عنوان المدير)');
    });

    test('المنفذ المسجَّل مفتوح ⇒ حيّ بلا طرق البدائل؛ الرفض وحده لا يكفي؛ المهلة = مفصول بلا بدائل', () async {
      final (api, _) = await listening();
      final (alt, altAccepted) = await listening();
      var r = await NetworkDevicesApi.mikrotikProbe('127.0.0.1', api.port, [alt.port]);
      expect(r.status, 'online');
      await settle();
      expect(altAccepted, isEmpty);
      final closed = await closedPort();
      r = await NetworkDevicesApi.mikrotikProbe('127.0.0.1', closed, const []);
      expect([r.status, r.packetLoss, r.responseMs], ['offline', 100.0, null], reason: 'رفضٌ بلا اتّصالٍ يُثبت شيئاً (قد يردّه وسيط)');
      final another = await closedPort();
      r = await NetworkDevicesApi.mikrotikProbe('127.0.0.1', closed, [another]);
      expect(r.status, 'offline', reason: 'كلّ طرقه مقفولة');
      final sw = Stopwatch()..start();
      r = await NetworkDevicesApi.mikrotikProbe('192.0.2.1', 8728, const [], timeout: const Duration(milliseconds: 400));
      expect(r.status, 'offline');
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });

    test('probeDevice: مايكروتك بفحصه، وSNMP (١٦١) قبله كما كان', () {
      final api = File('lib/api/network_devices_api.dart').readAsStringSync();
      final iMtk = api.indexOf("if (d.brand == 'mikrotik' && port != 161) {");
      expect(iMtk, greaterThan(0));
      expect(api.contains('mikrotikProbe(d.ip, port, MikrotikApi.fallbackPorts(protocol: d.protocol, apiPort: d.apiPort))'), isTrue);
      expect(api.indexOf('if (port == 161) {'), lessThan(iMtk), reason: 'الـcommunity تُقرأ قبل أيّ فرع');
    });
  });

  group('SSH — سكربت ومخرجات', () {
    test('print ⇒ مسحٌ عامّ مع بديل القائمة المفردة', () {
      final s = SshRouterOsChannel.scriptFor(['/interface/w60g/print'])!;
      expect(s, contains('[/interface w60g find]'));
      expect(s, contains(r'[/interface w60g get $i]'));
      expect(s, contains('[/interface w60g get]'), reason: 'system resource مفردة: get بلا رقم');
      expect(s, contains(':foreach k,v in='));
    });
    test('monitor ⇒ أمر طرفيّة لكلّ واجهة (مقتبسة)، وأكثر من 10 ⇒ لا', () {
      expect(SshRouterOsChannel.scriptFor(['/interface/ethernet/monitor', '=numbers=ether1,ether2', '=once=']),
          '/interface ethernet monitor "ether1" once; /interface ethernet monitor "ether2" once');
      final many = List.generate(11, (i) => 'ether${i + 1}').join(',');
      expect(SshRouterOsChannel.scriptFor(['/interface/ethernet/monitor', '=numbers=$many']), isNull);
      expect(SshRouterOsChannel.scriptFor(['/system/reboot']), '/system reboot');
    });
    test('الصفوف: تعليقٌ فيه «|» لا يُفسد السطر، والزمن بصيغة الـAPI', () {
      final rows = SshRouterOsChannel.parseRows('START|.id=*1|name=ether1|running=true|rx-byte=123|comment=a|b\r\n'
          'START|uptime=1w2d03:04:05|cpu-load=7\r\n');
      expect(rows[0], {'.id': '*1', 'name': 'ether1', 'running': 'true', 'rx-byte': '123', 'comment': 'a|b'});
      expect(rows[1]['uptime'], '1w2d3h4m5s');
      expect(SshRouterOsChannel.normalizeValue('00:00:07'), '7s');
      expect(SshRouterOsChannel.normalizeValue('3d00:00:00'), '3d');
      expect(SshRouterOsChannel.normalizeValue('1Gbps'), '1Gbps');
    });
    test('monitor بالطرفيّة (RouterOS 6): yes/no ⇒ true/false، وصفٌّ لكلّ واجهة', () {
      const out = '            connected: yes\r\n'
          '            frequency: 58320\r\n'
          '       remote-address: 00:11:22:33:44:55\r\n'
          '               tx-mcs: 8\r\n'
          '          tx-phy-rate: 1540.0Mbps\r\n'
          '               signal: 74\r\n'
          '                 rssi: -61\r\n'
          '             distance: 3.65m\r\n';
      final r = SshRouterOsChannel.parseMonitor(out).single;
      expect(r['connected'], 'true');
      final l = MikrotikW60gLink.fromMonitor('wlan60-1', r);
      expect(l.phyRateMbps, 1540);
      expect(l.mcs, 8);
      expect(l.rssi, -61);
      expect(l.distanceMeters, 3.65);
      final two = SshRouterOsChannel.parseMonitor('name: ether1\nrate: 1Gbps\nfull-duplex: yes\nname: ether2\nrate: 100Mbps\n');
      expect(two.map((e) => e['rate']), ['1Gbps', '100Mbps']);
      expect(two.first['full-duplex'], 'true');
    });
  });
}
