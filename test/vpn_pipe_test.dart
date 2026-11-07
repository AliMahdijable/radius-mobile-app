// ممرّ التطبيق عبر الـVPN (٧ نوفمبر — المالك: «بمجرد نقر الوكيل ع وضع vpn كل الفحصوات تمر من vpn»): قرّاء الأجهزة نفسها تتّصل عبر
// خادمنا. هنا خادم ممرٍّ وهميّ (كـserver/connVpn/pipe.js: فتح، كتابة، قراءةٌ تنتظر، إغلاق، UDP) يصل خوادم محلّيّة حقيقيّة.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/device_reach.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/core/net/device_net.dart';
import 'package:rad_mysvcs/core/net/vpn_pipe.dart';

class FakePipes implements VpnPipeTransport {
  FakePipes(this.target);

  /// العنوان المطلوب ⇒ منفذ الخادم المحلّيّ الذي «يصله النفق».
  int Function(String host, int port) target;
  final opened = <String>[];
  final closed = <String>[];
  final _socks = <String, Socket>{};
  final _bufs = <String, BytesBuilder>{};
  final _ended = <String>{};
  final _waiters = <String, Completer<void>>{};
  Map<String, Object?>? failOpen;
  Uint8List Function(Uint8List)? udpReply;
  final udpSeen = <String>[];
  var releases = 0;
  var _n = 0;

  @override
  Future<String> open(String host, int port, Duration timeout) async {
    final f = failOpen;
    if (f != null) throw VpnPipe.failure(f, port: port);
    final id = (++_n).toRadixString(16).padLeft(24, '0');
    final s = await Socket.connect(InternetAddress.loopbackIPv4, target(host, port));
    opened.add('$host:$port');
    _socks[id] = s;
    _bufs[id] = BytesBuilder();
    s.listen((d) {
      _bufs[id]!.add(d);
      _waiters.remove(id)?.complete();
    }, onDone: () {
      _ended.add(id);
      _waiters.remove(id)?.complete();
    }, onError: (Object _) {});
    return id;
  }

  @override
  Future<bool> write(String id, Uint8List data) async {
    final s = _socks[id];
    if (s == null) return false;
    s.add(data);
    return true;
  }

  @override
  Future<PipeRead?> read(String id, Duration wait) async {
    if (!_socks.containsKey(id)) return null;
    if (_bufs[id]!.isEmpty && !_ended.contains(id)) {
      final c = _waiters[id] = Completer<void>();
      await c.future.timeout(const Duration(milliseconds: 200), onTimeout: () {});
    }
    final data = _bufs[id]!.takeBytes();
    final end = _ended.contains(id);
    if (end) _socks.remove(id)?.destroy();
    return PipeRead(data, end);
  }

  @override
  Future<void> close(String id) async {
    closed.add(id);
    _socks.remove(id)?.destroy();
  }

  @override
  Future<Uint8List> udp(String host, int port, Uint8List data, Duration timeout) async {
    udpSeen.add('$host:$port');
    final f = udpReply;
    if (f == null) throw TimeoutException('لا ردّ');
    return f(data);
  }

  @override
  Future<void> release() async => releases++;
}

/// طلب SNMP ⇒ «ردّه» (الوسم A0 ⇒ A2 والمتغيّرات كما هي) — يكفي لتمرّ رسالةٌ ذهاباً وإياباً عبر الممرّ.
Uint8List asResponse(Uint8List req) {
  final b = Uint8List.fromList(req);
  var i = (b[1] & 0x80) != 0 ? 2 + (b[1] & 0x7f) : 2;
  i += 2 + b[i + 1]; // version
  i += 2 + b[i + 1]; // community
  expect(b[i], 0xA0, reason: 'GetRequest');
  b[i] = 0xA2;
  return b;
}

void main() {
  late FakePipes pipes;
  var vpn = true;
  late ServerSocket echo;
  late HttpServer web;
  final hosts = <String>[];

  setUp(() async {
    vpn = true;
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
    pipes = FakePipes((host, port) => port == 80 || port == 443 ? web.port : echo.port);
    VpnPipe.transport = pipes;
    VpnPipe.wait = const Duration(milliseconds: 200);
    DeviceNet.vpnOn = () => vpn;
  });

  tearDown(() async {
    await echo.close();
    await web.close(force: true);
  });

  test('«وضع VPN» ⇒ العناوين الخاصّة عبر الممرّ وحدها؛ العامّ مباشر؛ الحارس مباشرٌ دائماً؛ «الفحص الشامل» عبر الممرّ بلا الوضع', () async {
    expect(DeviceNet.viaPipe('10.72.1.1'), isTrue);
    expect(DeviceNet.viaPipe('192.168.88.1'), isTrue);
    expect(DeviceNet.viaPipe('100.66.3.4'), isTrue);
    expect(DeviceNet.viaPipe('172.20.0.1'), isTrue);
    expect(DeviceNet.viaPipe('8.8.8.8'), isFalse, reason: 'العامّ يصله الموبايل من أيّ مكان');
    expect(DeviceNet.viaPipe('172.32.0.1'), isFalse);
    expect(DeviceNet.viaPipe('router.local'), isFalse);
    expect(await DeviceNet.direct(() async => DeviceNet.viaPipe('10.72.1.1')), isFalse, reason: 'حارس «رجعت لشبكتك؟»');
    vpn = false;
    expect(DeviceNet.viaPipe('10.72.1.1'), isFalse, reason: 'خارج الوضع كما كان');
    expect(await DeviceNet.vpn(() async => DeviceNet.viaPipe('10.72.1.1')), isTrue);
  });

  test('TCP عبر الممرّ: البايتات بالاتّجاهين كما هي (RouterOS API/Telnet)، وإغلاق القارئ يغلق الممرّ', () async {
    final s = await DeviceNet.connect('10.72.1.1', 8728, timeout: const Duration(seconds: 2));
    expect(pipes.opened, ['10.72.1.1:8728']);
    final got = <int>[];
    final sub = s.listen(got.addAll);
    s.add(utf8.encode('/system/resource/print'));
    for (var i = 0; i < 40 && got.length < 22; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(utf8.decode(got), '/system/resource/print');
    await s.close();
    for (var i = 0; i < 40 && pipes.closed.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(pipes.closed, hasLength(1));
    await sub.cancel();
  });

  test('الجهاز يُغلق ⇒ آخر البايتات ثمّ نهاية القراءة عند القارئ', () async {
    final s = await DeviceNet.connect('10.72.1.1', 23);
    final got = <int>[];
    final done = Completer<void>();
    s.listen(got.addAll, onDone: done.complete);
    s.add(utf8.encode('bye'));
    await done.future.timeout(const Duration(seconds: 3));
    expect(utf8.decode(got), 'ok-bye');
    s.destroy();
  });

  test('رفض الجهاز عبر الممرّ = رفضٌ كالمباشر (القارئ يجرّب طريقه التالي)؛ وغيره بكلمة الخادم', () async {
    pipes.failOpen = {'success': false, 'code': 'CONNECT_FAILED', 'error': 'ECONNREFUSED'};
    try {
      await DeviceNet.connect('10.72.1.1', 8728);
      fail('يرمي');
    } on SocketException catch (e) {
      expect(DeviceReach.isRefused(e), isTrue, reason: '${e.osError}');
    }
    pipes.failOpen = {'success': false, 'code': 'CONNECT_FAILED', 'error': 'ETIMEDOUT'};
    try {
      await DeviceNet.connect('10.72.1.1', 8728);
      fail('يرمي');
    } on SocketException catch (e) {
      expect(DeviceReach.isRefused(e), isFalse);
      expect(e.message, 'Connection timed out');
    }
    pipes.failOpen = {'success': false, 'code': 'NOT_YOURS', 'message': 'هذا العنوان ليس من أجهزتك'};
    await expectLater(DeviceNet.connect('10.72.9.9', 22), throwsA(isA<SocketException>().having((e) => e.message, 'message', 'هذا العنوان ليس من أجهزتك')));
  });

  test('الويب (REST مايكروتك، airOS، EdgeSwitch…) عبر الممرّ: HttpClient نفسه، وعنوان الجهاز في الطلب كما هو', () async {
    final c = DeviceNet.adopt(HttpClient());
    final rq = await c.getUrl(Uri.parse('http://10.72.1.1/rest/system/resource'));
    final rs = await rq.close();
    expect(await rs.transform(utf8.decoder).join(), 'ok:/rest/system/resource');
    expect(pipes.opened, ['10.72.1.1:80']);
    expect(hosts.single, '10.72.1.1');
    c.close(force: true);
    // عنوانٌ عامّ ⇒ مباشر (لا ممرّ)
    final c2 = DeviceNet.adopt(HttpClient());
    final rs2 = await (await c2.getUrl(Uri.parse('http://127.0.0.1:${web.port}/x'))).close();
    expect(await rs2.transform(utf8.decoder).join(), 'ok:/x');
    expect(pipes.opened, hasLength(1));
    c2.close(force: true);
    // خارج الوضع ⇒ العميل لا يُلمس
    vpn = false;
    final c3 = HttpClient();
    expect(identical(DeviceNet.adopt(c3), c3), isTrue);
    c3.close(force: true);
  });

  test('SNMP (ميموزا، روجي، الأولت، مايكروتك SNMP) عبر الممرّ: الرسالة وردّها؛ لا ردّ ⇒ مهلة SNMP كالمباشر', () async {
    pipes.udpReply = asResponse;
    final snmp = SnmpV2c(host: '10.72.1.5', community: 'public', timeout: const Duration(seconds: 2));
    final r = await snmp.get(['1.3.6.1.2.1.1.3.0']);
    expect(r.single.oid, '1.3.6.1.2.1.1.3.0');
    expect(pipes.udpSeen, ['10.72.1.5:161']);
    pipes.udpReply = null;
    await expectLater(snmp.get(['1.3.6.1.2.1.1.5.0']), throwsA(isA<SnmpTimeoutException>()));
  });

  test('ترك «وضع VPN» يُطلق الممرّ وغرفته بالخادم — مرّةً، ولمن استعمله وحده', () async {
    VpnPipe.used = false;
    final s = await DeviceNet.connect('10.72.1.1', 8728);
    expect(VpnPipe.used, isTrue);
    s.destroy();
    VpnPipe.release();
    await Future<void>.delayed(Duration.zero);
    expect(pipes.releases, 1);
    expect(VpnPipe.used, isFalse);
  });
}
