import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_card_v3.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';
import 'package:rad_mysvcs/widgets/vpn_now_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// خادم «فحص الآن» الوهميّ: الأوّل يبدأ، والاستطلاع يردّ «جارٍ» بتقدّمه مرّةً ثمّ النتيجة.
class _NowServer implements HttpClientAdapter {
  final asked = <String>[];
  int polls = 0;
  Map<String, dynamic> startReply = {'success': true, 'data': {'check_id': 'c1', 'state': 'running'}};
  int startStatus = 200;
  Map<String, dynamic> Function(String what)? done;
  String what = 'subscribers';

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    asked.add('${o.method} ${o.path}');
    if (o.method == 'POST' && o.path.endsWith('/check-now')) {
      final d = o.data;
      what = d is Map && d['what'] == 'devices' ? 'devices' : 'subscribers';
      return _json(startStatus, startReply);
    }
    if (o.method == 'GET' && o.path.contains('/check-now/')) {
      polls += 1;
      if (polls == 1) {
        return _json(200, {
          'success': true,
          'data': {'state': 'running', 'progress': {'phase': 'probing', 'done': 32, 'total': 70}},
        });
      }
      return _json(200, {'success': true, 'data': {'state': 'done', 'result': done!(what)}});
    }
    return _json(404, {'success': false});
  }

  static ResponseBody _json(int s, Object b) => ResponseBody.fromString(jsonEncode(b), s,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _subsDone(String _) => {
      'ok': true,
      'message': 'فُحص عبر VPN ✓ — قُرئ 60 من 70 متّصلاً — 2 بمشكلة',
      'detail': '2 بمشكلة (إشارة ضعيفة أو كيبل)',
      'readings': [
        {'u': 'U0', 'src': 'cpe', 'sig': -61, 'ccq': 93, 'lan': 'ok'},
        {'u': 'u8', 'src': 'ping', 'ms': 31},
        {'u': 'u9', 'src': 'dead'},
        {'u': 'u7', 'src': 'olt', 'rx': -21.4, 't': 46},
      ],
    };

Map<String, dynamic> _devDone(String _) => {
      'ok': true,
      'message': 'فُحصت أجهزتك ✓ — 1 من 2 واصل',
      'detail': '«سكتر الجنوب» لا يستجيب',
      'devices': [
        {'id': 11, 'name': 'سكتر الشمال', 'alive': true, 'ms': 41, 'stations': 38},
        {'id': 13, 'name': 'سكتر الجنوب', 'alive': false, 'ms': null},
      ],
    };

Future<void> _drain(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await t.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  late _NowServer server;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    server = _NowServer()..done = _subsDone;
    ApiClient.dio.httpClientAdapter = server;
    VpnNow.pollEvery = const Duration(milliseconds: 1);
    VpnNow.reset();
  });
  tearDown(() {
    VpnNow.routeSource = () async => null;
    VpnNow.reset();
  });

  test('المشتركون: يبدأ ⇒ «يفحص مشتركينك… 32 من 70» بالتقدّم ⇒ النتيجة وسطرها الثاني، وقراءة كلّ مشترك للكروت (باليوزر صغيراً)', () async {
    final job = VpnNow.subscribers;
    final seen = <String>[];
    void l() => seen.add('${job.phase.name}|${job.line}|${job.value?.toStringAsFixed(2)}');
    job.addListener(l);
    await job.run();
    job.removeListener(l);
    expect(server.asked.first, 'POST /api/v2/conn-vpn/check-now');
    expect(server.what, 'subscribers');
    expect(seen.first, 'running|يتّصل بالـVPN…|null');
    expect(seen, contains('running|يفحص مشتركينك… 32 من 70|0.46'));
    expect(job.phase, VpnBarPhase.done);
    expect(job.line, 'فُحص عبر VPN ✓ — قُرئ 60 من 70 متّصلاً — 2 بمشكلة');
    expect(job.sub, '2 بمشكلة (إشارة ضعيفة أو كيبل)');
    expect(VpnNow.readingFor('u0')?.sig, -61);
    expect(VpnNow.readingFor('U8')?.ms, 31);
    expect(VpnNow.readingFor('u9')?.dead, isTrue);
    expect(VpnNow.readingFor('u7')?.rx, -21.4);
    expect(VpnNow.readingFor('nobody'), isNull);
  });

  test('الأجهزة: فحصٌ منفصل (what=devices) ⇒ حال كلّ جهاز برقمه؛ والمشتركون لا يتأثّرون', () async {
    server.done = _devDone;
    await VpnNow.devices.run();
    expect(server.what, 'devices');
    expect(VpnNow.devices.line, 'فُحصت أجهزتك ✓ — 1 من 2 واصل');
    expect(VpnNow.deviceFor(11)?.stations, 38);
    expect(VpnNow.deviceFor(13)?.alive, isFalse);
    expect(VpnNow.subscribers.phase, VpnBarPhase.idle);
    expect(VpnNow.readingFor('u0'), isNull);
  });

  test('الفشل: الخادم يرفض البدء ⇒ رسالته؛ النتيجة tunnel_failed ⇒ فشلٌ بسببه (زرّ صفحة VPN)؛ reset ينسى كلّ شيء', () async {
    server.startStatus = 409;
    server.startReply = {'success': false, 'code': 'CONN_VPN_OFF', 'message': '«تنبيه المشترك» غير مفعّل لحسابك بعد'};
    await VpnNow.subscribers.run();
    expect(VpnNow.subscribers.phase, VpnBarPhase.failed);
    expect(VpnNow.subscribers.line, '«تنبيه المشترك» غير مفعّل لحسابك بعد');
    server.startStatus = 200;
    server.startReply = {'success': true, 'data': {'check_id': 'c2'}};
    server.done = (_) => {'ok': false, 'reason': 'tunnel_failed', 'message': 'ما اتّصل الـVPN — تأكّد من الملفّ أو اليوزر والباسورد'};
    await VpnNow.devices.run();
    expect(VpnNow.devices.phase, VpnBarPhase.failed);
    expect(VpnNow.devices.reason, 'tunnel_failed');
    VpnNow.debugApply(VpnNowKind.devices, VpnNowResult.fromJson(_devDone('devices')));
    expect(VpnNow.deviceFor(11), isNotNull);
    VpnNow.reset();
    expect(VpnNow.deviceFor(11), isNull);
    expect(VpnNow.devices.phase, VpnBarPhase.idle);
  });

  test('الإخفاء لباقي اليوم: لكلّ قسمٍ وحده، ويُعاد من القائمة', () async {
    expect(await VpnNow.dismissedToday(VpnNowKind.subscribers), isFalse);
    await VpnNow.dismiss(VpnNowKind.subscribers);
    expect(await VpnNow.dismissedToday(VpnNowKind.subscribers), isTrue);
    expect(await VpnNow.dismissedToday(VpnNowKind.devices), isFalse);
    await VpnNow.undismiss(VpnNowKind.subscribers);
    expect(await VpnNow.dismissedToday(VpnNowKind.subscribers), isFalse);
  });

  Widget host(Widget child) => MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: child))),
      );

  testWidgets('الهنت: خارج الشبكة + مربوط ⇒ «فحص الآن» و×؛ × يخفيه؛ غير مربوط ⇒ «ربط VPN»؛ الميزة مغلقة ⇒ لا شيء؛ على الشبكة ⇒ لا شيء', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'own');
    var opened = 0;
    await t.pumpWidget(host(VpnNowBar(kind: VpnNowKind.subscribers, offNetwork: true, onOpenVpn: () => opened++)));
    await _drain(t);
    expect(find.text('أنت خارج شبكتك'), findsOneWidget);
    expect(find.text('تقدر تفحص مشتركينك عبر الـVPN'), findsOneWidget);
    expect(find.text('فحص الآن'), findsOneWidget);
    await t.tap(find.byTooltip('إخفاء'));
    await _drain(t);
    expect(find.text('أنت خارج شبكتك'), findsNothing, reason: 'مخفيٌّ لباقي اليوم');

    SharedPreferences.setMockInitialValues({});
    VpnNow.reset();
    VpnNow.routeSource = () async => (linked: false, via: null);
    await t.pumpWidget(host(VpnNowBar(key: UniqueKey(), kind: VpnNowKind.devices, offNetwork: true, onOpenVpn: () => opened++)));
    await _drain(t);
    expect(find.text('اربط VPN مرّة وحدة حتى تفحص من بعيد'), findsOneWidget);
    await t.tap(find.text('ربط VPN'));
    expect(opened, 1);

    VpnNow.reset();
    VpnNow.routeSource = () async => null;
    await t.pumpWidget(host(VpnNowBar(key: UniqueKey(), kind: VpnNowKind.devices, offNetwork: true, onOpenVpn: () {})));
    await _drain(t);
    expect(find.text('أنت خارج شبكتك'), findsNothing, reason: 'الميزة غير مفتوحة لحسابه');

    VpnNow.routeSource = () async => (linked: true, via: 'company');
    await t.pumpWidget(host(VpnNowBar(key: UniqueKey(), kind: VpnNowKind.devices, offNetwork: false, onOpenVpn: () {})));
    await _drain(t);
    expect(find.text('أنت خارج شبكتك'), findsNothing, reason: 'على الشبكة');
  });

  testWidgets('الهنت فوق شريط التنقّل العائم (extendBody كالغلاف) لا تحته — بلاغ المالك ٥ نوفمبر: «لحد هسه مظاهرلي شي»', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    const navKey = ValueKey('nav');
    await t.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          extendBody: true,
          bottomNavigationBar: const SizedBox(key: navKey, height: 80, child: ColoredBox(color: Colors.white)),
          body: Builder(
            builder: (ctx) => Stack(children: [
              const Positioned.fill(child: ColoredBox(color: Colors.grey)),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(ctx).bottom,
                child: VpnNowBar(kind: VpnNowKind.subscribers, offNetwork: true, onOpenVpn: () {}),
              ),
            ]),
          ),
        ),
      ),
    ));
    await _drain(t);
    final bar = t.getRect(find.text('فحص الآن'));
    final nav = t.getRect(find.byKey(navKey));
    expect(bar.bottom <= nav.top, isTrue, reason: 'الزرّ $bar فوق الشريط $nav');
    expect(t.hitTestOnBinding(t.getCenter(find.text('فحص الآن'))).path.isNotEmpty, isTrue);
  });

  testWidgets('الضغط على «فحص الآن» ⇒ الفحص ثمّ النتيجة بالشريط، وحبّة الجهاز وكرت المشترك بعلامة VPN', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'own');
    final sub = Subscriber.fromJson({'idx': 1, 'username': 'u0', 'firstname': 'علي', 'expiration': '2026-12-01 00:00:00', 'remaining_days': 25});
    await t.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
      SubscriberNetworkMetrics(sub: sub),
      const VpnDevicePill(id: 11),
      VpnNowBar(kind: VpnNowKind.subscribers, offNetwork: true, onOpenVpn: () {}),
    ])));
    await _drain(t);
    expect(find.text('-61 dBm'), findsNothing);
    await t.tap(find.text('فحص الآن'));
    await _drain(t);
    expect(find.text('فُحص عبر VPN ✓ — قُرئ 60 من 70 متّصلاً — 2 بمشكلة'), findsOneWidget);
    expect(find.text('-61 dBm'), findsOneWidget);
    expect(find.text('CCQ 93%'), findsOneWidget);
    expect(find.text('VPN'), findsOneWidget, reason: 'كرت المشترك وحده (الأجهزة لم تُفحص بعد)');
    VpnNow.debugApply(VpnNowKind.devices, VpnNowResult.fromJson(_devDone('devices')));
    await t.pump();
    expect(find.textContaining('38 متّصل'), findsOneWidget);
    expect(find.text('VPN'), findsNWidgets(2));
  });
}
