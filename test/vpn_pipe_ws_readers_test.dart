// كلّ قارئٍ للأجهزة فوق «الخطّ المفتوح» من أوّله لآخره (٢٥ نوفمبر — المالك: «تاكدت من كلشي يخص فحص vpn بمجيمع المواقع بالتطبيق؟»).
// خادمٌ محلّيّ بشكل server/connVpn/pipeWs.js (WebSocket لكلّ اتّصال + خطٌّ واحد ?mux=1 لـSNMP والبنك) أمام أجهزةٍ وهميّة حقيقيّة البروتوكول:
// مايكروتك RouterOS API (FakeRouterOs)، الويب (HttpServer: REST مايكروتك، airOS، EdgeSwitch، صفحة أولت HSGQ…)، Telnet/TCP (صدى)، SNMP
// (ردٌّ بالبايتات). والطلبات العاديّة ممنوعة هنا (ناقلٌ يرمي): قارئٌ يتسرّب للطريق القديم أو يفتح اتّصاله مباشرةً يُسقط الاختبار.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/mikrotik_binary_api.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/core/net/device_net.dart';
import 'package:rad_mysvcs/core/net/vpn_pipe.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_routeros.dart';

/// الطلبات العاديّة ممنوعة — «الطريق» وحده يقول ws.
class NoHttp implements VpnPipeTransport {
  final used = <String>[];
  Never _no(String what) {
    used.add(what);
    throw StateError('الطلب العاديّ استُعمل: $what');
  }

  @override
  Future<({String id, int? ms})> open(String host, int port, Duration timeout) async => _no('open $host:$port');
  @override
  Future<bool> write(String id, Uint8List data) async => _no('write');
  @override
  Future<PipeRead?> read(String id, Duration wait) async => _no('read');
  @override
  Future<void> close(String id) async => _no('close');
  @override
  Future<({Uint8List data, int? ms})> udp(String host, int port, Uint8List data, Duration timeout) async => _no('udp $host:$port');
  @override
  Future<List<int>> ping(String host, int count, Duration timeout) async => _no('ping $host');
  @override
  Future<PipeRoute> route() async => const PipeRoute.ok('own', ws: true);
  @override
  Future<void> release() async {}
}

/// خادم الممرّ المحلّيّ: كلّ اتّصالٍ إلى [target]؛ SNMP بـ[udpReply] (null ⇒ مهلة 504)؛ البنك [5].
class Relay {
  late HttpServer srv;
  int tcp = 0;
  int mux = 0;
  int muxReq = 0;
  final opened = <String>[];
  int Function(String host, int port) target = (h, p) => 0;
  Uint8List? Function(Uint8List req)? udpReply;

  Future<void> start() async {
    srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((req) async {
      if (req.uri.path != WsPipeTransport.path || !WebSocketTransformer.isUpgradeRequest(req)) {
        req.response.statusCode = 426;
        await req.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(req);
      final q = req.uri.queryParameters;
      if (q['mux'] == '1') {
        mux += 1;
        ws.add(jsonEncode({'success': true, 'data': {'mux': true}}));
        ws.listen((m) {
          final o = jsonDecode(m as String) as Map<String, dynamic>;
          muxReq += 1;
          final rid = o['rid'];
          if (o['op'] == 'udp') {
            final r = udpReply?.call(base64Decode('${o['d']}'));
            ws.add(jsonEncode(r == null
                ? {'rid': rid, 'ok': false, 'status': 504, 'body': {'success': false, 'code': 'UDP_TIMEOUT', 'message': 'الجهاز ما ردّ'}}
                : {'rid': rid, 'ok': true, 'data': {'d': base64Encode(r), 'ms': 4}}));
          } else {
            ws.add(jsonEncode({'rid': rid, 'ok': true, 'data': {'times': [5], 'sent': 1}}));
          }
        }, onError: (Object _) {});
        return;
      }
      tcp += 1;
      final ip = q['ip'] ?? '';
      final port = int.parse(q['port'] ?? '0');
      opened.add('$ip:$port');
      final Socket s;
      try {
        s = await Socket.connect(InternetAddress.loopbackIPv4, target(ip, port));
      } catch (_) {
        ws.add(jsonEncode({'success': false, 'code': 'CONNECT_FAILED', 'error': 'ECONNREFUSED', 'message': 'الجهاز ما ردّ عبر الـVPN', 'status': 502}));
        unawaited(ws.close(1000, 'open_failed'));
        return;
      }
      ws.add(jsonEncode({'success': true, 'data': {'id': (tcp.toRadixString(16)).padLeft(24, '0'), 'via': 'own', 'ms': 3}}));
      s.listen((d) => ws.add(d), onDone: () => unawaited(ws.close(1000, 'eof')), onError: (Object _) => unawaited(ws.close(1000, 'eof')));
      ws.listen((m) {
        try {
          s.add(m is String ? utf8.encode(m) : m as List<int>);
        } catch (_) {}
      }, onDone: s.destroy, onError: (Object _) => s.destroy());
    });
  }
}

/// طلب SNMP ⇒ «ردّه» (A0 ⇒ A2 والمتغيّرات كما هي).
Uint8List asResponse(Uint8List req) {
  final b = Uint8List.fromList(req);
  var i = (b[1] & 0x80) != 0 ? 2 + (b[1] & 0x7f) : 2;
  i += 2 + b[i + 1];
  i += 2 + b[i + 1];
  b[i] = 0xA2;
  return b;
}

void main() {
  late Relay relay;
  late NoHttp noHttp;
  late ServerSocket echo;
  late HttpServer web;
  late FakeRouterOs ros;
  final hosts = <String>[];
  final realOn = DeviceNet.vpnOn;
  final realWait = VpnPipe.wait;

  setUp(() async {
    hosts.clear();
    echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    echo.listen((c) => c.listen((d) {
          if (utf8.decode(d) == 'bye') {
            c.add(utf8.encode('ok-bye'));
            c.close();
          } else {
            c.add(d);
          }
        }, onError: (Object _) {}));
    web = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    web.listen((r) {
      hosts.add(r.headers.host ?? '');
      r.response.write('ok:${r.uri.path}');
      r.response.close();
    });
    ros = FakeRouterOs()..sxtNano();
    final rosPort = await ros.start();
    relay = Relay()
      ..target = (h, p) => p == 8728 ? rosPort : (p == 80 || p == 443 ? web.port : (p == 9 ? 1 : echo.port));
    await relay.start();
    noHttp = NoHttp();
    VpnPipe.transport = WsPipeTransport(noHttp,
        base: () => Uri.parse('http://127.0.0.1:${relay.srv.port}'), headers: (_) async => {'Authorization': 'Bearer T'});
    SharedPreferences.setMockInitialValues({});
    VpnPipe.debugResetWsMemory();
    await VpnPipe.route(); // «الطريق» يقول ws
    VpnPipe.wait = const Duration(seconds: 2);
    DeviceNet.vpnOn = () => true;
  });

  tearDown(() async {
    DeviceNet.vpnOn = realOn;
    VpnPipe.wait = realWait;
    VpnPipe.resetBackoff();
    await echo.close();
    await web.close(force: true);
    await relay.srv.close(force: true);
  });

  test('الويب (REST مايكروتك، airOS، EdgeSwitch، صفحة أولت HSGQ…) فوق الخطّ المفتوح: HttpClient نفسه وعنوان الجهاز في الطلب', () async {
    final c = DeviceNet.adopt(HttpClient());
    try {
      final rq = await c.getUrl(Uri.parse('http://10.66.7.9/status'));
      final rs = await rq.close();
      expect(await rs.transform(utf8.decoder).join(), 'ok:/status');
    } finally {
      c.close(force: true);
    }
    expect(hosts, ['10.66.7.9'], reason: 'عنوان الجهاز في الطلب كما هو');
    expect(relay.opened, ['10.66.7.9:80']);
    expect(noHttp.used, isEmpty);
  });

  test('TCP (Telnet سسكو، منافذ الفحص) فوق الخطّ المفتوح: البايتات بالاتّجاهين، وإغلاق الجهاز ⇒ آخر البايتات ثمّ النهاية', () async {
    final s = await DeviceNet.connect('10.66.7.9', 23);
    final got = BytesBuilder();
    var done = false;
    s.listen(got.add, onDone: () => done = true, onError: (Object _) => done = true);
    s.add(utf8.encode('ping1'));
    await s.flush();
    final t0 = DateTime.now();
    while (utf8.decode(got.toBytes()) != 'ping1' && DateTime.now().difference(t0) < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(utf8.decode(got.toBytes()), 'ping1');
    s.add(utf8.encode('bye'));
    await s.flush();
    final t1 = DateTime.now();
    while (!done && DateTime.now().difference(t1) < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done, isTrue);
    expect(utf8.decode(got.toBytes()), 'ping1ok-bye');
    expect(noHttp.used, isEmpty);
  });

  test('مايكروتك RouterOS API (8728) فوق الخطّ المفتوح: الدخول والاستعلام كما على شبكته', () async {
    final api = MikrotikBinaryClient(host: '10.66.7.9', user: 'admin', pass: 'mt-pass');
    try {
      await api.connect();
      await api.login();
      final rows = await api.query(['/system/identity/print']);
      expect(rows, isNotEmpty);
      expect(rows.first['name'], isNotNull);
    } finally {
      await api.close();
    }
    expect(relay.opened, contains('10.66.7.9:8728'));
    expect(ros.logins, 1);
    expect(noHttp.used, isEmpty);
  });

  test('SNMP (الأولت، ميموزا، روجي) والبنك على الخطّ الواحد: الرسالة وردّها، ولا ردّ ⇒ مهلة SNMP كالمباشر', () async {
    relay.udpReply = asResponse;
    final snmp = SnmpV2c(host: '10.72.1.5', community: 'public', timeout: const Duration(seconds: 2));
    final r = await snmp.get(['1.3.6.1.2.1.1.3.0']);
    expect(r.single.oid, '1.3.6.1.2.1.1.3.0');
    expect(await VpnPipe.ping('10.72.1.5'), [5]);
    expect([relay.mux, relay.muxReq], [1, 2], reason: 'خطٌّ واحد للرسالتين');
    relay.udpReply = null;
    await expectLater(snmp.get(['1.3.6.1.2.1.1.5.0']), throwsA(isA<SnmpTimeoutException>()));
    expect(noHttp.used, isEmpty);
  });

  test('رفض الجهاز فوق الخطّ المفتوح = رفضٌ كالمباشر (القارئ يجرّب طريقه التالي)', () async {
    Object? e;
    try {
      await DeviceNet.connect('10.66.7.9', 9);
    } catch (x) {
      e = x;
    }
    expect(e, isA<SocketException>());
    expect((e as SocketException).osError?.message, 'Connection refused');
    expect(noHttp.used, isEmpty);
  });
}
