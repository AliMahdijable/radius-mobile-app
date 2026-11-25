// «الاتّصال الواحد» لممرّ الـVPN + التباعد بعد الفشل (٢٥ نوفمبر — المالك: «اي ابدي بالاتصال الواحد والنقطة ٣ وياه»، و«رح يتاثر الفحص؟
// تقل جودته ويتاخر؟»). خادم WebSocket محلّيّ حقيقيّ بشكل server/connVpn/pipeWs.js (أوّل رسالةٍ ردّ open، ثمّ بايتاتٌ بالاتّجاهين، وإغلاق
// 1000 eof / 1012)، وناقلٌ وهميّ للطلبات العاديّة (الاحتياط) ولاختبارات التباعد بساعةٍ وهميّة.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/net/vpn_pipe.dart';

/// الطلبات العاديّة (الاحتياط) — تسجّل ما طُلب منها.
class FakeHttp implements VpnPipeTransport {
  int opens = 0;
  int udps = 0;
  int pings = 0;
  Object? Function(String host, int port)? openError;
  Object? Function(String host)? udpError;
  PipeRoute routeResult = const PipeRoute.ok('own');

  @override
  Future<({String id, int? ms})> open(String host, int port, Duration timeout) async {
    opens += 1;
    final e = openError?.call(host, port);
    if (e != null) throw e;
    return (id: opens.toRadixString(16).padLeft(24, '0'), ms: null);
  }

  @override
  Future<bool> write(String id, Uint8List data) async => true;

  @override
  Future<PipeRead?> read(String id, Duration wait) async => null;

  @override
  Future<void> close(String id) async {}

  @override
  Future<({Uint8List data, int? ms})> udp(String host, int port, Uint8List data, Duration timeout) async {
    udps += 1;
    final e = udpError?.call(host);
    if (e != null) throw e;
    return (data: Uint8List.fromList([1]), ms: 3);
  }

  @override
  Future<List<int>> ping(String host, int count, Duration timeout) async {
    pings += 1;
    final e = udpError?.call(host);
    if (e != null) throw e;
    return [5];
  }

  @override
  Future<PipeRoute> route() async => routeResult;

  @override
  Future<void> release() async {}
}

/// خادمٌ بشكل pipeWs.js: المنفذ يقرّر الحال (7001 النفق، 7002 رفض الجهاز، 7003 مشغولٌ مرّة)، و`x-test-reject: <حالة>:<رمز>` رفضٌ قبل المصافحة.
class WsServer {
  late HttpServer srv;
  int handshakes = 0;
  bool busyOnce = true;
  final sessions = <WebSocket>[];

  Future<void> start() async {
    srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((req) async {
      if (req.uri.path != WsPipeTransport.path) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      handshakes += 1;
      final rej = req.headers.value('x-test-reject');
      if (rej != null) {
        final p = rej.split(':');
        req.response.statusCode = int.parse(p[0]);
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'success': false, if (p.length > 1) 'code': p[1]}));
        await req.response.close();
        return;
      }
      if (!WebSocketTransformer.isUpgradeRequest(req) || req.headers.value('authorization') != 'Bearer T') {
        req.response.statusCode = 401;
        await req.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(req);
      sessions.add(ws);
      final port = int.parse(req.uri.queryParameters['port'] ?? '0');
      void fail(Map<String, Object> body) {
        ws.add(jsonEncode({'success': false, ...body}));
        unawaited(ws.close(1000, 'open_failed'));
      }

      if (port == 7001) return fail({'code': 'TUNNEL_FAILED', 'message': 'الـVPN ما اتّصل الآن — حاول بعد قليل', 'status': 503});
      if (port == 7002) return fail({'code': 'CONNECT_FAILED', 'error': 'ECONNREFUSED', 'message': 'الجهاز ما ردّ عبر الـVPN', 'status': 502});
      if (port == 7003 && busyOnce) {
        busyOnce = false;
        return fail({'code': 'PIPE_BUSY', 'message': 'اتّصالاتٌ كثيرة الآن — لحظات', 'status': 429});
      }
      ws.add(jsonEncode({'success': true, 'data': {'id': 'ab' * 12, 'via': 'own', 'ms': 9}}));
      ws.add(utf8.encode('HELLO\n'));
      ws.listen((m) {
        final b = m is String ? utf8.encode(m) : m as List<int>;
        final t = utf8.decode(b, allowMalformed: true);
        if (t == 'BYE') {
          ws.add(utf8.encode('LAST'));
          unawaited(ws.close(1000, 'eof'));
        } else if (t == 'KILL') {
          // الخادم الحقيقيّ يغلق بـ1012 عند النشر؛ dart:io لا يرسل 1012 (محجوز عنده) ⇒ 4012 بالمعنى نفسه: إغلاقٌ غير نظيف
          unawaited(ws.close(4012, 'restart'));
        } else {
          ws.add(b);
        }
      }, onError: (Object _) {});
    });
  }

  int get port => srv.port;
  Future<void> stop() async {
    for (final s in sessions) {
      try {
        await s.close();
      } catch (_) {}
    }
    await srv.close(force: true);
  }
}

Future<bool> until(bool Function() f, {Duration within = const Duration(seconds: 5)}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < within) {
    if (f()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return f();
}

/// يقرأ كلّ ما يصل من المقبس ويقول متى انتهى.
class Reader {
  Reader(this.s) {
    s.listen((d) => buf.add(d), onDone: () => done = true, onError: (Object _) => done = true);
  }
  final Socket s;
  final buf = BytesBuilder();
  bool done = false;
  String get text => utf8.decode(buf.toBytes(), allowMalformed: true);
}

void main() {
  late WsServer server;
  late FakeHttp http;
  late WsPipeTransport ws;
  Map<String, String> extra = {};
  final realWait = VpnPipe.wait;
  final realBusy = VpnPipe.busyBackoffMs;

  setUp(() async {
    server = WsServer();
    await server.start();
    http = FakeHttp();
    extra = {};
    ws = WsPipeTransport(http,
        base: () => Uri.parse('http://127.0.0.1:${server.port}'),
        headers: (_) async => {'Authorization': 'Bearer T', 'x-app-build': '196', ...extra});
    VpnPipe.transport = ws;
    VpnPipe.wsAllowed = true;
    VpnPipe.now = DateTime.now;
    VpnPipe.resetBackoff();
    VpnPipe.debugResetGate();
    VpnPipe.wait = const Duration(seconds: 2);
    VpnPipe.busyBackoffMs = const [20, 20];
  });

  tearDown(() async {
    VpnPipe.wait = realWait;
    VpnPipe.busyBackoffMs = realBusy;
    VpnPipe.now = DateTime.now;
    VpnPipe.resetBackoff();
    await server.stop();
  });

  test('١ الممرّ على WebSocket: الترحيب، والصدى بالترتيب، وإغلاق الجهاز ⇒ آخر البايتات ثمّ نهايةٌ نظيفة — بلا أيّ طلبٍ عاديّ', () async {
    final s = await VpnPipe.connect('10.0.0.5', 22);
    final r = Reader(s);
    expect(VpnPipe.connectMsOf(s), 9, reason: 'زمن الجهاز من الخادم');
    expect(await until(() => r.text == 'HELLO\n'), isTrue);
    s.add(utf8.encode('a1'));
    await s.flush();
    expect(await until(() => r.text == 'HELLO\na1'), isTrue, reason: r.text);
    s.add(utf8.encode('BYE'));
    await s.flush();
    expect(await until(() => r.done), isTrue);
    expect(r.text, 'HELLO\na1LAST');
    expect(http.opens, 0, reason: 'لا طلب عاديّ');
    expect(server.handshakes, 1);
    expect(await until(() => ws.wsOpen == 0), isTrue);
  });

  test('٢ أوّل رسالةٍ خطأ ⇒ الشكل نفسه كالطلب العاديّ: النفق ⇒ PipeTunnelDown بكلمته، ورفض الجهاز ⇒ errno «refused»', () async {
    Object? e1;
    try {
      await VpnPipe.connect('10.0.0.5', 7001);
    } catch (e) {
      e1 = e;
    }
    expect(e1, isA<PipeTunnelDown>());
    expect((e1 as SocketException).message, 'الـVPN ما اتّصل الآن — حاول بعد قليل');
    VpnPipe.resetBackoff();
    Object? e2;
    try {
      await VpnPipe.connect('10.0.0.5', 7002);
    } catch (e) {
      e2 = e;
    }
    expect(e2, isA<SocketException>());
    expect((e2 as SocketException).osError?.message, 'Connection refused');
    expect(http.opens, 0);
  });

  test('٣ «مشغول» ⇒ إعادةٌ بعد لحظة كما في الطلبات العاديّة', () async {
    final s = await VpnPipe.connect('10.0.0.5', 7003);
    final r = Reader(s);
    expect(await until(() => r.text == 'HELLO\n'), isTrue);
    expect(server.handshakes, 2);
    s.destroy();
  });

  test('٤ المفتاح مطفأ بالخادم (409 PIPE_WS_OFF) ⇒ الطلب العاديّ فوراً، ولا WebSocket حتى يقول «الطريق» ws من جديد', () async {
    extra = {'x-test-reject': '409:PIPE_WS_OFF'};
    final s = await VpnPipe.connect('10.0.0.5', 22);
    s.destroy();
    expect(http.opens, 1);
    expect(VpnPipe.wsAllowed, isFalse);
    final s2 = await VpnPipe.connect('10.0.0.5', 22);
    s2.destroy();
    expect([http.opens, server.handshakes], [2, 1], reason: 'الثاني لم يحاول المصافحة');
    http.routeResult = const PipeRoute.ok('own', ws: true);
    await VpnPipe.route();
    expect(VpnPipe.wsAllowed, isTrue);
  });

  test('٥ وسيطٌ حذف الترقية (426) ⇒ الطلب العاديّ و٣٠ دقيقة بلا محاولة؛ 401 ⇒ الطلب العاديّ مرّةً ثمّ يُجرَّب من جديد', () async {
    extra = {'x-test-reject': '426'};
    (await VpnPipe.connect('10.0.0.5', 22)).destroy();
    (await VpnPipe.connect('10.0.0.5', 22)).destroy();
    expect([http.opens, server.handshakes], [2, 1]);
    final t0 = DateTime.now();
    VpnPipe.now = () => t0.add(const Duration(minutes: 31));
    extra = {'x-test-reject': '401'};
    (await VpnPipe.connect('10.0.0.5', 22)).destroy();
    expect([http.opens, server.handshakes], [3, 2], reason: 'بعد ٣٠ د يُجرَّب');
    extra = {};
    final s = await VpnPipe.connect('10.0.0.5', 22);
    expect([http.opens, server.handshakes], [3, 3], reason: '401 لا يوقف الاتّصال المفتوح');
    s.destroy();
  });

  test('٦ الخادم لا يصل (لا أحد على المنفذ) ⇒ الطلب العاديّ و٥ دقائق بلا محاولة', () async {
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = dead.port;
    await dead.close();
    VpnPipe.transport = WsPipeTransport(http, base: () => Uri.parse('http://127.0.0.1:$p'), headers: (_) async => {'Authorization': 'Bearer T'});
    (await VpnPipe.connect('10.0.0.5', 22)).destroy();
    expect(http.opens, 1);
    expect(VpnPipe.wsUsable, isFalse);
  });

  test('٧ إغلاقٌ غير نظيف (إعادة تشغيل الخادم 1012/4012) ⇒ القارئ يُقطع كما حين يسقط الممرّ العاديّ', () async {
    final s = await VpnPipe.connect('10.0.0.5', 22);
    final r = Reader(s);
    expect(await until(() => r.text == 'HELLO\n'), isTrue);
    s.add(utf8.encode('KILL'));
    await s.flush();
    expect(await until(() => r.done), isTrue);
    expect(await until(() => ws.wsOpen == 0), isTrue);
  });

  test('٨ «الطريق» يقرّر: ws:true ⇒ WebSocket، وبدونه ⇒ الطلبات العاديّة', () async {
    http.routeResult = const PipeRoute.ok('own');
    await VpnPipe.route();
    expect(VpnPipe.wsAllowed, isFalse);
    (await VpnPipe.connect('10.0.0.5', 22)).destroy();
    expect([http.opens, server.handshakes], [1, 0]);
    http.routeResult = const PipeRoute.ok('own', ws: true);
    await VpnPipe.route();
    final s = await VpnPipe.connect('10.0.0.5', 22);
    expect([http.opens, server.handshakes], [1, 1]);
    s.destroy();
  });

  test('١٣ النقل نفسه: إغلاق الجهاز النظيف ⇒ آخر البايتات بنهايةٍ صريحة (end) لا بقطع، ثمّ null', () async {
    final o = await ws.open('10.0.0.5', 22, const Duration(seconds: 3));
    final got = BytesBuilder();
    var r = await ws.read(o.id, const Duration(seconds: 2));
    got.add(r!.data);
    expect(await ws.write(o.id, Uint8List.fromList(utf8.encode('BYE'))), isTrue);
    var ended = false;
    for (var i = 0; i < 20 && !ended; i++) {
      r = await ws.read(o.id, const Duration(seconds: 2));
      if (r == null) break;
      got.add(r.data);
      ended = r.end;
    }
    expect(ended, isTrue, reason: 'نهايةٌ صريحة');
    expect(utf8.decode(got.toBytes()), 'HELLO\nLAST');
    expect(await ws.read(o.id, const Duration(milliseconds: 50)), isNull, reason: 'بعد النهاية');
    expect(ws.wsOpen, 0);
  });

  group('التباعد بعد الفشل (النقطة ٣)', () {
    late FakeHttp t;
    late DateTime clock;
    setUp(() {
      t = FakeHttp();
      VpnPipe.transport = t;
      clock = DateTime(2026, 11, 25, 10);
      VpnPipe.now = () => clock;
      VpnPipe.resetBackoff();
    });

    Future<Object?> tryConnect(String host, [int port = 22]) async {
      try {
        (await VpnPipe.connect(host, port)).destroy();
        return null;
      } catch (e) {
        return e;
      }
    }

    test('٩ النفق لم يقم ⇒ لا سؤال للخادم ٥ث (±٢٠٪) ثمّ ١٠ ثمّ ٢٠ ثمّ ٣٠ سقفاً؛ والقرّاء تأخذ الخطأ نفسه فوراً؛ النجاح يصفّر', () async {
      t.openError = (h, p) => VpnPipe.failure({'code': 'TUNNEL_FAILED', 'message': 'الـVPN ما اتّصل الآن — حاول بعد قليل'}, port: p);
      expect(await tryConnect('10.0.0.5'), isA<PipeTunnelDown>());
      expect(t.opens, 1);
      clock = clock.add(const Duration(seconds: 3));
      expect(await tryConnect('10.0.0.9'), isA<PipeTunnelDown>(), reason: 'أيّ جهازٍ: النفق نفسه');
      expect(t.opens, 1, reason: 'لم يُسأل الخادم');
      clock = clock.add(const Duration(seconds: 3)); // ٦ث > ٥×١٫٢
      await tryConnect('10.0.0.5');
      expect(t.opens, 2);
      clock = clock.add(const Duration(seconds: 7)); // < ١٠×٠٫٨
      await tryConnect('10.0.0.5');
      expect(t.opens, 2, reason: 'الخطوة الثانية ~١٠ث');
      clock = clock.add(const Duration(seconds: 6)); // ١٣ث > ١٢
      await tryConnect('10.0.0.5');
      expect(t.opens, 3);
      for (var i = 0; i < 4; i++) {
        clock = clock.add(const Duration(seconds: 37));
        await tryConnect('10.0.0.5');
      }
      expect(t.opens, 7, reason: 'السقف ٣٠ث: كلّ ٣٧ث محاولة');
      expect(VpnPipe.tunnelBackedOff, isTrue);
      t.openError = null;
      clock = clock.add(const Duration(seconds: 37));
      expect(await tryConnect('10.0.0.5'), isNull);
      expect(VpnPipe.tunnelBackedOff, isFalse, reason: 'النجاح يصفّر');
    });

    test('١٠ منفذ جهازٍ لا يجيب ٣ مرّاتٍ متتالية ⇒ هو وحده يتباعد (لا منافذه الأخرى ولا غيره)؛ الرفض جوابٌ يصفّر؛ والسليم بلا انتظار', () async {
      t.openError = (h, p) => h == '10.0.0.7' ? VpnPipe.failure({'code': 'CONNECT_FAILED', 'error': 'ETIMEDOUT'}, port: p) : null;
      for (var i = 0; i < 3; i++) {
        expect(await tryConnect('10.0.0.7'), isA<SocketException>());
      }
      expect(t.opens, 3);
      expect(VpnPipe.hostBackedOff('10.0.0.7', 22), isTrue);
      final e = await tryConnect('10.0.0.7');
      expect((e as SocketException).osError?.message, 'Connection timed out', reason: 'الخطأ نفسه فوراً');
      expect(t.opens, 3);
      expect(await tryConnect('10.0.0.8'), isNull, reason: 'غيره طبيعيّ');
      expect(t.opens, 4);
      await tryConnect('10.0.0.7', 80);
      expect(t.opens, 5, reason: 'منفذٌ آخر للجهاز نفسه يُجرَّب (فحصٌ يجرّب منافذ عدّة لا يُطفئ الجهاز)');
      // رفضٌ = الجهاز حيّ ⇒ يصفّر عدّاده
      t.openError = (h, p) => VpnPipe.failure({'code': 'CONNECT_FAILED', 'error': 'ECONNREFUSED'}, port: p);
      clock = clock.add(const Duration(seconds: 7));
      await tryConnect('10.0.0.7');
      expect(VpnPipe.hostBackedOff('10.0.0.7', 22), isFalse);
      t.openError = (h, p) => VpnPipe.failure({'code': 'CONNECT_FAILED', 'error': 'ETIMEDOUT'}, port: p);
      await tryConnect('10.0.0.7');
      await tryConnect('10.0.0.7');
      expect(VpnPipe.hostBackedOff('10.0.0.7', 22), isFalse, reason: 'مرّتان فقط بعد التصفير');
    });

    test('١١ الضغطة الصريحة (الفحص الشامل — urgentKey) تحاول فوراً؛ «الطريق» السليم ودخول الوضع يصفّران', () async {
      t.openError = (h, p) => VpnPipe.failure({'code': 'TUNNEL_FAILED'}, port: p);
      await tryConnect('10.0.0.5');
      await tryConnect('10.0.0.5');
      expect(t.opens, 1);
      await runZoned(() => tryConnect('10.0.0.5'), zoneValues: {VpnPipe.urgentKey: true});
      expect(t.opens, 2, reason: 'الصريح يتجاوز');
      t.routeResult = const PipeRoute.ok('company');
      await VpnPipe.route();
      expect(VpnPipe.tunnelBackedOff, isFalse);
      await tryConnect('10.0.0.5');
      expect(t.opens, 3);
      VpnPipe.resetBackoff();
      await tryConnect('10.0.0.5');
      expect(t.opens, 4);
    });

    test('١٢ UDP بلا ردّ ٣ مرّات ⇒ الجهاز يتباعد؛ البنك يتباعد بالنفق وحده (سؤالٌ رخيص يكشف عودة الجهاز)', () async {
      t.udpError = (h) => TimeoutException('SNMP عبر الـVPN: الجهاز ما ردّ');
      for (var i = 0; i < 3; i++) {
        await expectLater(VpnPipe.udp('10.0.0.6', 161, Uint8List(1), const Duration(seconds: 1)), throwsA(isA<TimeoutException>()));
      }
      await expectLater(VpnPipe.udp('10.0.0.6', 161, Uint8List(1), const Duration(seconds: 1)), throwsA(isA<TimeoutException>()));
      expect(t.udps, 3);
      t.udpError = null;
      expect(await VpnPipe.ping('10.0.0.6'), [5], reason: 'البنك لا يأخذ تباعد الجهاز');
      // ولا تباعد أيّ منفذٍ TCP للجهاز نفسه
      t.openError = (h, p) => VpnPipe.failure({'code': 'CONNECT_FAILED', 'error': 'ETIMEDOUT'}, port: p);
      for (var i = 0; i < 3; i++) {
        await tryConnect('10.0.0.6', 22);
      }
      expect(VpnPipe.hostBackedOff('10.0.0.6', 22), isTrue);
      expect(await VpnPipe.ping('10.0.0.6'), [5]);
      expect(t.pings, 2);
      t.udpError = (h) => VpnPipe.failure({'code': 'TUNNEL_FAILED'});
      await expectLater(VpnPipe.ping('10.0.0.6'), throwsA(isA<PipeTunnelDown>()));
      await expectLater(VpnPipe.ping('10.0.0.6'), throwsA(isA<PipeTunnelDown>()));
      expect(t.pings, 3, reason: 'النفق يتباعد للبنك أيضاً');
    });

    test('١٤ ناقلٌ جديد (عالمٌ جديد) لا يرث تباعد سابقه', () async {
      t.openError = (h, p) => VpnPipe.failure({'code': 'TUNNEL_FAILED'}, port: p);
      await tryConnect('10.0.0.5');
      expect(VpnPipe.tunnelBackedOff, isTrue);
      VpnPipe.transport = FakeHttp();
      expect(VpnPipe.tunnelBackedOff, isFalse);
    });
  });
}
