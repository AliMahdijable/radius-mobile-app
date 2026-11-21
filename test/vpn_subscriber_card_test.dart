// كرت جهاز المشترك بـ«وضع VPN» (٢٢ نوفمبر — المالك على صورة الكرت: «ليش يظهر لا يستجيب وهو بي معلومات اكو وكذلك ترفك وزر ريبوت
// ماكو؟ بوضع vpn داخل او vpn خارجي»).
//
// كان الكرت يقرأ الجهاز مباشرةً من الموبايل وهو خارج شبكته: لا قراءة ⇒ لا ترفك ولا زرّ إعادة تشغيل، وفوق قراءة الخادم «لا يستجيب» من
// بنگٍ لم يصل. الآن: الكرت المفتوح وحده (لا موجة القائمة) يقرأ الجهاز عبر ممرّ الخادم كقسم الأجهزة — البنگ والفحص والترفك والإقلاع؛
// وذاكرة «لم يردّ» المباشرة لا تُغلق القراءة عبر الممرّ؛ والحبّة تقول ما يعرضه الجسم.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/api/mikrotik_binary_api.dart';
import 'package:rad_mysvcs/core/net/device_net.dart';
import 'package:rad_mysvcs/core/net/mikrotik_cpe_service.dart';
import 'package:rad_mysvcs/core/net/tcp_reachability.dart';
import 'package:rad_mysvcs/core/net/vpn_pipe.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/device_probe_card.dart';
import 'package:rad_mysvcs/services/agent_net_presence.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_routeros.dart';
import 'visual_perm/visual_perm_harness.dart';

/// ممرٌّ وهميّ كـserver/connVpn/pipe.js يصل خوادم محلّيّة: [target] يقول أيّ منفذٍ محلّيّ «يصله النفق» لكلّ عنوانٍ ومنفذ
/// (null ⇒ الجهاز رفض المنفذ — CONNECT_FAILED كردّ الخادم).
class _Pipes implements VpnPipeTransport {
  _Pipes(this.target);

  int? Function(String host, int port) target;
  Map<String, Object?>? failOpen;
  final opened = <String>[];
  final _socks = <String, Socket>{};
  final _bufs = <String, BytesBuilder>{};
  final _ended = <String>{};
  final _waiters = <String, Completer<void>>{};
  var _n = 0;

  @override
  Future<({String id, int? ms})> open(String host, int port, Duration timeout) async {
    opened.add('$host:$port');
    final f = failOpen;
    if (f != null) throw VpnPipe.failure(f, port: port);
    final local = target(host, port);
    if (local == null) throw VpnPipe.failure({'code': 'CONNECT_FAILED', 'error': 'ECONNREFUSED'}, port: port);
    final id = (++_n).toRadixString(16).padLeft(24, '0');
    final s = await Socket.connect(InternetAddress.loopbackIPv4, local);
    _socks[id] = s;
    _bufs[id] = BytesBuilder();
    s.listen((d) {
      _bufs[id]!.add(d);
      _waiters.remove(id)?.complete();
    }, onDone: () {
      _ended.add(id);
      _waiters.remove(id)?.complete();
    }, onError: (Object _) {});
    return (id: id, ms: 41);
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
  Future<void> close(String id) async => _socks.remove(id)?.destroy();

  @override
  Future<({Uint8List data, int? ms})> udp(String host, int port, Uint8List data, Duration timeout) =>
      throw TimeoutException('لا UDP هنا');

  @override
  Future<List<int>> ping(String host, int count, Duration timeout) async => const [];

  @override
  Future<PipeRoute> route() async => const PipeRoute.ok('company');

  @override
  Future<void> release() async {}
}

/// موبايلٌ خارج شبكة الوكيل: كلّ اتّصالٍ مباشرٍ بغير loopback يفشل فوراً (لا شبكة حقيقيّة تُلمس) ويُسجَّل.
final class _OffNetIo extends IOOverrides {
  _OffNetIo(this.tried);
  final List<String> tried;

  static const _err = SocketException('خارج الشبكة (اختبار)', osError: OSError('No route to host', 65));

  bool _local(Object? host) {
    final h = host is InternetAddress ? host.address : '$host';
    return h == '127.0.0.1' || h == 'localhost';
  }

  @override
  Future<Socket> socketConnect(host, int port, {sourceAddress, int sourcePort = 0, Duration? timeout}) {
    if (_local(host)) return super.socketConnect(host, port, sourceAddress: sourceAddress, sourcePort: sourcePort, timeout: timeout);
    tried.add('$host:$port');
    return Future.error(_err);
  }

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(host, int port, {sourceAddress, int sourcePort = 0}) {
    if (_local(host)) return super.socketStartConnect(host, port, sourceAddress: sourceAddress, sourcePort: sourcePort);
    tried.add('$host:$port');
    return Future.error(_err);
  }
}

/// عملاء HTTP المباشرون (ومنهم https) لا يصلون شيئاً خارج loopback.
class _OffNetHttp extends HttpOverrides {
  _OffNetHttp(this.tried);
  final List<String> tried;

  @override
  HttpClient createHttpClient(SecurityContext? context) => super.createHttpClient(context)
    ..connectionFactory = (uri, _, __) {
      if (uri.host == '127.0.0.1') return Socket.startConnect(uri.host, uri.port);
      tried.add('${uri.scheme}://${uri.host}:${uri.port}');
      return Future.error(const SocketException('خارج الشبكة (اختبار)', osError: OSError('No route to host', 65)));
    };
}

Future<T> _offNetwork<T>(List<String> tried, Future<T> Function() fn) =>
    HttpOverrides.runWithHttpOverrides(() => IOOverrides.runWithIOOverrides(fn, _OffNetIo(tried)), _OffNetHttp(tried));

/// عملاء HTTP حقيقيّون (حزمةٌ فيها testWidgets تجعل كلّ HttpClient وهميّاً يردّ 400) — ما يمرّ عبر الممرّ الوهميّ يصل خوادمه المحلّيّة.
final class _RealHttp extends HttpOverrides {}

Future<T> _realHttp<T>(Future<T> Function() fn) => HttpOverrides.runWithHttpOverrides(fn, _RealHttp());

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

const _ip = '10.66.1.5';

void main() {
  group('الطريق: الكرت المفتوح بـ«وضع VPN» عبر الممرّ، وغيره مباشر', () {
    late _Pipes pipes;
    late HttpServer web;
    var vpn = true;

    setUp(() async {
      vpn = true;
      web = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      web.listen((r) {
        r.response.write('ok:${r.uri.path}');
        r.response.close();
      });
      pipes = _Pipes((host, port) => port == 80 ? web.port : null);
      VpnPipe.transport = pipes;
      VpnPipe.wait = const Duration(milliseconds: 200);
      DeviceNet.vpnOn = () => vpn;
    });

    tearDown(() async {
      VpnPipe.debugResetGate();
      DeviceNet.vpnOn = () => VpnNow.devicesMode;
      await web.close(force: true);
    });

    test('النطاق: داخل الكرت بالوضع عبر الممرّ؛ خارجه (الموجة) أو بلا الوضع أو بنطاق «مباشر» لا — والأعمق يغلب', () async {
      expect(DeviceNet.cpePiped, isFalse, reason: 'خارج الكرت: مباشر وإن كان الوضع شغّالاً');
      expect(DeviceNet.cpeZone(true, () => DeviceNet.cpePiped), isTrue);
      expect(DeviceNet.cpeZone(false, () => DeviceNet.cpePiped), isFalse);
      expect(DeviceNet.cpeZone(true, () => DeviceNet.cpeZone(false, () => DeviceNet.cpePiped)), isFalse);
      expect(DeviceNet.cpeZone(false, () => DeviceNet.cpeZone(true, () => DeviceNet.cpePiped)), isTrue,
          reason: 'مؤقّتٌ أُنشئ مباشراً ثمّ نادى بعد تشغيل الوضع ⇒ الطريق الجديد');
      expect(DeviceNet.cpeZone(false, () => DeviceNet.viaPipe(_ip)), isFalse, reason: 'كرتٌ بلا الوضع: لا ممرّ ولو لـSSH قسم الأجهزة');
      vpn = false;
      expect(DeviceNet.cpeZone(true, () => DeviceNet.cpePiped), isFalse, reason: 'الوضع أُطفئ ⇒ مباشر');
    });

    test('HTTP وTCP لجهاز المشترك: داخل الكرت يصلان الجهاز عبر الممرّ؛ خارجه لا يُفتح ممرّ (الموجة لا تُغرقه)', () async {
      final body = await _realHttp(() => DeviceNet.cpeZone(true, () async {
        final c = DeviceNet.cpeHttp(HttpClient()..connectionTimeout = const Duration(seconds: 2));
        try {
          final res = await (await c.getUrl(Uri.parse('http://$_ip/status'))).close();
          return utf8.decode(await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b)));
        } finally {
          c.close(force: true);
        }
      }));
      expect(body, 'ok:/status');
      expect(pipes.opened, ['$_ip:80']);

      final tried = <String>[];
      await _offNetwork(tried, () async {
        final c = DeviceNet.cpeHttp(HttpClient());
        await expectLater(c.getUrl(Uri.parse('http://$_ip/status')), throwsA(isA<SocketException>()));
        c.close(force: true);
        await expectLater(DeviceNet.cpeConnect(_ip, 8728), throwsA(isA<SocketException>()));
      });
      expect(pipes.opened, ['$_ip:80'], reason: 'خارج الكرت لا ممرّ وإن كان «وضع VPN» شغّالاً');
      expect(tried, containsAll(['http://$_ip:80', '$_ip:8728']), reason: 'حاول مباشرةً كما كان');
    });

    test('البنگ عبر الممرّ بحكمٍ ثالث: الجهاز ردّ ⇒ نعم · مهلته ⇒ لا · الممرّ نفسه رفض العنوان ⇒ لا حكم (لا «لا يستجيب»)', () async {
      SharedPreferences.setMockInitialValues({});
      await DeviceProbeApi.clearAllCaches();
      Future<bool?> reach() => DeviceNet.cpeZone(true, () => DeviceProbeApi.reachable(fallbackIp: _ip, force: true));
      expect(await reach(), isTrue);
      pipes.failOpen = {'success': false, 'code': 'NOT_YOURS', 'message': 'هذا العنوان ليس من أجهزتك ولا مشتركيك'};
      expect(await reach(), isNull, reason: 'رفض الممرّ ليس جواب الجهاز');
      pipes.failOpen = {'success': false, 'code': 'CONNECT_FAILED', 'error': 'ETIMEDOUT'};
      expect(await reach(), isFalse, reason: 'الجهاز ما ردّ من داخل النفق');
      pipes.failOpen = null;
      expect(await DeviceNet.cpeZone(true, () => TcpReachability.verdict(_ip)), isTrue);
      final tried = <String>[];
      expect(await _offNetwork(tried, () => TcpReachability.verdict(_ip)), isFalse, reason: 'المباشر كما كان: لا يصل ⇒ لا');
    });
  });

  group('الفحص الكامل عبر الممرّ (جهاز ميكروتك وهميّ خلف النفق)', () {
    late FakeRouterOs d;
    late _Pipes pipes;
    late _FakeApi api;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      MikrotikBinaryClient.trapDoneWait = const Duration(milliseconds: 300);
      MikrotikCpeService.reset();
      d = FakeRouterOs()..sxtNano();
      final port = await d.start();
      // 8728 (الـAPI) يصله النفق، وكلّ منفذٍ آخر مرفوض (لا ويب ولا Winbox)
      pipes = _Pipes((host, p) => host == _ip && p == 8728 ? port : null);
      VpnPipe.transport = pipes;
      VpnPipe.wait = const Duration(milliseconds: 200);
      DeviceNet.vpnOn = () => true;
      await DeviceProbeApi.clearAllCaches();
      api = _FakeApi()..defaults = {'mikrotikUsername': 'admin', 'mikrotikPassword': 'mt-pass'};
      final adapter = ApiClient.dio.httpClientAdapter;
      final interceptors = List<Interceptor>.of(ApiClient.dio.interceptors);
      ApiClient.dio.httpClientAdapter = api;
      ApiClient.dio.interceptors.clear(keepImplyContentTypeInterceptor: false);
      addTearDown(() {
        ApiClient.dio.httpClientAdapter = adapter;
        ApiClient.dio.interceptors
          ..clear(keepImplyContentTypeInterceptor: false)
          ..addAll(interceptors);
      });
      DeviceProbeApi.invalidateAdminDefaults();
      DeviceProbeApi.debugCaps(probe: const Duration(seconds: 8), zteExtra: const Duration(seconds: 1));
    });

    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await d.stop();
      MikrotikCpeService.reset();
      MikrotikBinaryClient.trapDoneWait = const Duration(seconds: 2);
      VpnPipe.debugResetGate();
      DeviceNet.vpnOn = () => VpnNow.devicesMode;
      DeviceProbeApi.debugCaps(probe: const Duration(seconds: 15), zteExtra: const Duration(seconds: 15));
    });

    test('فحصٌ مباشرٌ فشل للتوّ (موبايلٌ خارج شبكته، الوضع شغّال) لا يُغلق فحص الكرت عبر الممرّ — والكرت يقرأ الجهاز كاملاً', () async {
      final tried = <String>[];
      final direct = await _offNetwork(tried, () => DeviceProbeApi.probe(fallbackIp: _ip));
      expect(direct, isNull);
      expect(tried, isNotEmpty, reason: 'الفحص خارج الكرت حاول مباشرةً');
      expect(pipes.opened, isEmpty, reason: 'خارج الكرت (الموجة وغيرها) لا ممرّ ولو بالوضع');

      // بلا force: «ميّت» دقيقتين، وفشلٌ محفوظ خمساً، و«ليس ميكروتك» نصف دقيقة — كلّها من الطريق المباشر ولا تمسّ الممرّ.
      final snap = await _realHttp(() => DeviceNet.cpeZone(true, () => DeviceProbeApi.probe(fallbackIp: _ip)));
      expect(snap, isNotNull, reason: 'كان يعيد الفشل المباشر المحفوظ فلا قراءة ولا ترفك ولا زرّ');
      expect(snap!.ubnt?.vendor, 'mikrotik');
      expect(snap.ubnt?.signalDbm, -63);
      expect(pipes.opened, contains('$_ip:8728'), reason: 'القراءة نفسها عبر الممرّ');
      expect(pipes.opened, contains('$_ip:80'), reason: 'وتعرّف الويب (TP-Link وغيره) عبر الممرّ أيضاً — لا شيء مباشر');
      expect(d.forbidden, isEmpty, reason: 'قراءةٌ وحدها');

      // والعكس: فشلٌ عبر الممرّ لا يُغلق المباشر — والنجاح حقيقةٌ عن الجهاز يراها الجميع (شريحة القائمة)
      expect(DeviceProbeApi.cached(_ip)?.ubnt?.vendor, 'mikrotik');
    });
  });

  group('الكرت بصفحة المشترك', () {
    setUpAll(visualSetUpAll);
    late _Pipes pipes;

    setUp(() {
      pipes = _Pipes((_, __) => null); // كلّ اتّصالٍ عبر الممرّ يُسجَّل ثمّ يُرفض — لا شبكة
      VpnPipe.transport = pipes;
    });

    tearDown(() async {
      VpnNow.reset();
      AgentNetPresence.reset();
      DeviceProbeApi.debugRunProbe = null;
      DeviceProbeApi.debugReach = null;
      DeviceNet.vpnOn = () => VpnNow.devicesMode;
      VpnPipe.debugResetGate();
      await DeviceProbeApi.clearAllCaches();
    });

    VpnNowResult readings({bool dead = false}) => VpnNowResult.fromJson({
          'ok': true,
          'readings': [
            dead ? {'u': 'ali@popq', 'src': 'dead'} : {'u': 'ali@popq', 'src': 'cpe', 'sig': -66, 'ccq': 93, 'lan': 'ok'},
          ],
        });

    Future<void> pumpCard(WidgetTester t) async {
      await pumpVisual(t, phone,
          home: (_) => Scaffold(body: ListView(children: const [DeviceProbeCard(username: 'ali@popq', ip: '10.66.7.9')])));
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> closeCard(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 20));
      await visualTearDown();
    }

    testWidgets('خارج شبكتك بلا ممرّ: الجسم قراءة الـVPN من جهازه ⇒ الحبّة «يستجيب» لا «لا يستجيب» (صورة المالك)', (t) async {
      await visualSetUp(s1bSasOwner);
      SharedPreferences.setMockInitialValues({});
      AgentNetPresence.debugSet(NetPresence.off);
      VpnNow.debugApply(VpnNowKind.subscribers, readings());
      DeviceNet.vpnOn = () => false;
      DeviceProbeApi.debugReach = (_) async => false; // البنگ المباشر من موبايلٍ خارج شبكته
      DeviceProbeApi.debugRunProbe = (_) async => null;
      await pumpCard(t);
      expect(find.byKey(const ValueKey('device-card-vpn')), findsOneWidget);
      expect(find.text('-66 dBm'), findsOneWidget);
      expect(find.text('يستجيب'), findsOneWidget);
      expect(find.text('لا يستجيب'), findsNothing, reason: 'كانت الحبّة تكذّب القراءة تحتها');
      expect(find.text('القراءة الكاملة وحركة البيانات من هاتفك لمّا ترجع لشبكتك'), findsOneWidget, reason: 'بلا ممرٍّ للكرت');
      await closeCard(t);
    });

    testWidgets('قراءة الـVPN تقول ما ردّ ⇒ الحبّة «لا يستجيب» كما الجسم', (t) async {
      await visualSetUp(s1bSasOwner);
      SharedPreferences.setMockInitialValues({});
      AgentNetPresence.debugSet(NetPresence.off);
      VpnNow.debugApply(VpnNowKind.subscribers, readings(dead: true));
      DeviceNet.vpnOn = () => false;
      DeviceProbeApi.debugReach = (_) async => false;
      DeviceProbeApi.debugRunProbe = (_) async => null;
      await pumpCard(t);
      expect(find.text('لا يستجيب عبر الـVPN'), findsOneWidget);
      expect(find.text('لا يستجيب'), findsOneWidget);
      await closeCard(t);
    });

    testWidgets('«وضع VPN»: الكرت يقرأ جهازه عبر الممرّ ⇒ نوعه، والترفك وزرّ إعادة التشغيل عبر الممرّ أيضاً', (t) async {
      await visualSetUp(s1bSasOwner);
      SharedPreferences.setMockInitialValues({});
      VpnNow.mode.value = true;
      VpnNow.debugApply(VpnNowKind.subscribers, readings());
      DeviceNet.vpnOn = () => true;
      final probedVia = <bool>[];
      DeviceProbeApi.debugReach = (_) async => DeviceNet.cpePiped; // يصل عبر الممرّ وحده (خارج شبكته)
      DeviceProbeApi.debugRunProbe = (ip) async {
        probedVia.add(DeviceNet.cpePiped);
        if (!DeviceNet.cpePiped) return null;
        return DeviceHealthSnapshot(
          kind: DeviceKind.ubiquiti,
          ip: ip,
          ubnt: UbiquitiStatus.fromJson({'sig': -66, 'ccq': 93, 'hn': 'nano-ali'}),
        );
      };
      await pumpCard(t);
      expect(probedVia, isNotEmpty);
      expect(probedVia.every((v) => v), isTrue, reason: 'كلّ فحصٍ من الكرت بالوضع عبر الممرّ');
      expect(find.text('UBNT'), findsOneWidget, reason: 'قراءته هو لا قراءة الخادم');
      expect(find.byKey(const ValueKey('device-card-vpn')), findsNothing);
      expect(find.text('لا يستجيب'), findsNothing);
      expect(find.byIcon(LucideIcons.power), findsOneWidget, reason: 'زرّ إعادة التشغيل');

      // الترفك: جلسة SSH النانو تُفتح عبر الممرّ (هنا يرفضها الممرّ الوهميّ — المهمّ طريقها)
      for (var i = 0; i < 40 && !pipes.opened.contains('10.66.7.9:22'); i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(pipes.opened, contains('10.66.7.9:22'), reason: 'الترفك عبر الممرّ');

      // إعادة التشغيل: أمر SSH عبر الممرّ
      final before = pipes.opened.where((o) => o == '10.66.7.9:22').length;
      await t.tap(find.byIcon(LucideIcons.power));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('إعادة تشغيل'));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(pipes.opened.where((o) => o == '10.66.7.9:22').length, greaterThan(before), reason: 'الإقلاع عبر الممرّ');
      expect(find.textContaining('تعذّرت إعادة التشغيل'), findsOneWidget, reason: 'الممرّ الوهميّ رفضه — والنصّ يقول ذلك');
      await closeCard(t);
    });

    testWidgets('«وضع VPN» والقراءة الكاملة تعذّرت عبر الممرّ ⇒ قراءة الخادم تبقى، والذيل يقول ذلك بدل «لمّا ترجع لشبكتك»', (t) async {
      await visualSetUp(s1bSasOwner);
      SharedPreferences.setMockInitialValues({});
      VpnNow.mode.value = true;
      VpnNow.debugApply(VpnNowKind.subscribers, readings());
      DeviceNet.vpnOn = () => true;
      DeviceProbeApi.debugReach = (_) async => null; // الممرّ نفسه رفض العنوان
      DeviceProbeApi.debugRunProbe = (_) async => null;
      await pumpCard(t);
      expect(find.byKey(const ValueKey('device-card-vpn')), findsOneWidget);
      expect(find.text('يستجيب'), findsOneWidget, reason: 'قراءة الخادم من جهازه — لا حكم من ممرٍّ رُفض');
      expect(find.text('تعذّرت القراءة الكاملة عبر الـVPN الآن — اسحب للتحديث'), findsOneWidget);
      expect(find.text('القراءة الكاملة وحركة البيانات من هاتفك لمّا ترجع لشبكتك'), findsNothing);
      await closeCard(t);
    });

    testWidgets('فتح الكرت بعد فشلٍ محفوظ (الموجة فشلت مباشرةً) بـ«وضع VPN»: الذيل «جارٍ» ما دام الفحص عبر الممرّ، ثمّ السبب', (t) async {
      await visualSetUp(s1bSasOwner);
      SharedPreferences.setMockInitialValues({});
      VpnNow.mode.value = true;
      VpnNow.debugApply(VpnNowKind.subscribers, readings());
      // فشلٌ مباشرٌ محفوظ لهذا المشترك (peek يجده ⇒ الكرت يفتح بلا دوّارة ويحدّث صامتاً)
      DeviceNet.vpnOn = () => false;
      DeviceProbeApi.debugRunProbe = (_) async => null;
      await t.runAsync(() => DeviceProbeApi.probe(fallbackIp: '10.66.7.9', subscriberUsername: 'ali@popq', force: true));
      expect(DeviceProbeApi.peek(username: 'ali@popq', ip: '10.66.7.9')?.snap, isNull, reason: 'فشلٌ محفوظ');
      expect(DeviceProbeApi.peek(username: 'ali@popq', ip: '10.66.7.9'), isNotNull);
      DeviceNet.vpnOn = () => true;
      final gate = Completer<DeviceHealthSnapshot?>();
      DeviceProbeApi.debugReach = (_) async => null;
      DeviceProbeApi.debugRunProbe = (_) => gate.future;
      await pumpCard(t);
      expect(find.text('جارٍ قراءة جهازه كاملاً عبر الـVPN…'), findsOneWidget, reason: 'لا «تعذّرت» والفحص عبر الممرّ لم ينتهِ');
      gate.complete(null);
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('تعذّرت القراءة الكاملة عبر الـVPN الآن — اسحب للتحديث'), findsOneWidget);
      await closeCard(t);
    });

    testWidgets('تشغيل «وضع VPN» والكرت مفتوح ⇒ يُعاد فحصه عبر الممرّ (لا يبقى على فشل المباشر)', (t) async {
      await visualSetUp(s1bSasOwner);
      SharedPreferences.setMockInitialValues({});
      var vpn = false;
      DeviceNet.vpnOn = () => vpn;
      DeviceProbeApi.debugReach = (_) async => DeviceNet.cpePiped;
      DeviceProbeApi.debugRunProbe = (ip) async => DeviceNet.cpePiped
          ? DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: ip, ubnt: UbiquitiStatus.fromJson({'sig': -61, 'ccq': 97, 'hn': 'nano-ali'}))
          : null;
      await pumpCard(t);
      expect(find.text('UBNT'), findsNothing);
      vpn = true;
      VpnNow.mode.value = true; // الوكيل نقر الدرع
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('UBNT'), findsOneWidget);
      await closeCard(t);
    });
  });
}
