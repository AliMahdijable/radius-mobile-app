import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/vpn_now_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_card_v3.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/services/agent_net_presence.dart';
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
    VpnNow.guardProbe = null;
    VpnNow.now = DateTime.now;
    VpnNow.loopEvery = const Duration(seconds: 10);
    VpnNow.reset();
    AgentNetPresence.reset();
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

  test('«على شبكتك؟» المشتركة: الخاصّ وحده يقرّر؛ ردٌّ واحد ⇒ على الشبكة؛ ≥٣ بلا ردّ ⇒ خارجها فوراً؛ الجولة الجزئيّة لا تمسحها؛ تشيخ', () {
    var t = DateTime(2026, 11, 5, 20);
    AgentNetPresence.now = () => t;
    addTearDown(() {
      AgentNetPresence.now = DateTime.now;
      AgentNetPresence.reset();
    });
    AgentNetPresence.reset();
    for (final ip in ['10.1.2.3', '172.16.0.1', '172.31.255.1', '192.168.1.1', '100.64.0.1', '100.127.1.1']) {
      expect(AgentNetPresence.isPrivate(ip), isTrue, reason: ip);
    }
    for (final ip in ['8.8.8.8', '172.32.0.1', '100.128.0.1', '185.1.2.3', '', 'x', '10.1.2']) {
      expect(AgentNetPresence.isPrivate(ip), isFalse, reason: ip);
    }
    expect(AgentNetPresence.isPrivate('10.0.0.1:8291'), isTrue, reason: 'بمنفذه');
    expect(AgentNetPresence.current, NetPresence.unknown);
    expect(AgentNetPresence.report(attempted: 2, reached: 0), NetPresence.unknown, reason: 'عنوانان لا يكفيان');
    expect(AgentNetPresence.report(attempted: 3, reached: 0), NetPresence.off, reason: 'جولةٌ كاملة بلا ردّ ⇒ فوراً');
    t = t.add(const Duration(seconds: 20));
    expect(AgentNetPresence.report(attempted: 1, reached: 0), NetPresence.off, reason: 'جولة المؤقّت الجزئيّة لا تمسحها');
    expect(AgentNetPresence.report(attempted: 0, reached: 0), NetPresence.off);
    // الجولات الجزئيّة بلا ردّ تُبقي «خارج» حيّة: ٤ جولاتٍ متباعدة (دقيقتان) = ٨ دقائق ولا تشيخ
    for (var i = 0; i < 4; i++) {
      t = t.add(const Duration(minutes: 2));
      expect(AgentNetPresence.report(attempted: 1, reached: 0), NetPresence.off, reason: 'جولة $i');
    }
    AgentNetPresence.reset();
    expect(AgentNetPresence.report(attempted: 2, reached: 0), NetPresence.unknown, reason: 'الجزئيّة لا تقرّر «خارج» من «غير معروف»');
    expect(AgentNetPresence.report(attempted: 3, reached: 0), NetPresence.off);
    expect(AgentNetPresence.report(attempted: 5, reached: 1), NetPresence.on, reason: 'ردٌّ واحد من عنوانٍ خاصّ');
    t = t.add(const Duration(minutes: 4));
    expect(AgentNetPresence.current, NetPresence.unknown, reason: 'تشيخ بعد ٣ دقائق');
    expect(AgentNetPresence.isOff, isFalse);
  });

  Widget host(Widget child) => MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: child))),
      );

  testWidgets('الهنت: خارج الشبكة + مربوط ⇒ «تشغيل VPN» و×؛ × يخفيه؛ غير مربوط ⇒ «ربط VPN»؛ الميزة مغلقة ⇒ لا شيء؛ على الشبكة ⇒ لا شيء', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'own');
    var opened = 0;
    await t.pumpWidget(host(VpnNowBar(kind: VpnNowKind.subscribers, offNetwork: true, onOpenVpn: () => opened++)));
    await _drain(t);
    expect(find.text('أنت خارج شبكتك'), findsOneWidget);
    expect(find.text('افحص مشتركينك عبر الـVPN — يرجع مباشر وحده لمّا ترجع'), findsOneWidget);
    expect(find.text('تشغيل VPN'), findsOneWidget);
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
    final bar = t.getRect(find.text('تشغيل VPN'));
    final nav = t.getRect(find.byKey(navKey));
    expect(bar.bottom <= nav.top, isTrue, reason: 'الزرّ $bar فوق الشريط $nav');
    expect(t.hitTestOnBinding(t.getCenter(find.text('تشغيل VPN'))).path.isNotEmpty, isTrue);
  });

  testWidgets('«تشغيل VPN» ⇒ الوضع يشتغل ويفحص ⇒ النتيجة تبقى بالشريط مع إيقاعه و[إيقاف]؛ الكرت والحبّة بعلامة VPN؛ «إيقاف» يرجعه', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'own');
    final sub = Subscriber.fromJson({'idx': 1, 'username': 'u0', 'firstname': 'علي', 'expiration': '2026-12-01 00:00:00', 'remaining_days': 25});
    await t.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
      SubscriberNetworkMetrics(sub: sub),
      const VpnDevicePill(id: 11),
      VpnNowBar(kind: VpnNowKind.subscribers, offNetwork: true, onOpenVpn: () {}),
    ])));
    await _drain(t);
    expect(find.text('-61 dBm'), findsNothing);
    await t.tap(find.text('تشغيل VPN'));
    await _drain(t);
    expect(VpnNow.mode.value, isTrue);
    expect(find.text('فُحص عبر VPN ✓ — قُرئ 60 من 70 متّصلاً — 2 بمشكلة'), findsOneWidget);
    expect(find.textContaining('يتحدّث كلّ'), findsOneWidget, reason: 'الوضع يبقى ويتحدّث');
    expect(find.text('إيقاف'), findsOneWidget);
    expect(find.byTooltip('إخفاء'), findsNothing, reason: 'بالوضع لا ×: «إيقاف» وحده');
    expect(find.text('-61 dBm'), findsOneWidget);
    expect(find.text('CCQ 93%'), findsOneWidget);
    expect(find.text('VPN'), findsOneWidget, reason: 'كرت المشترك وحده (الأجهزة لم تُفحص بعد)');
    VpnNow.debugApply(VpnNowKind.devices, VpnNowResult.fromJson(_devDone('devices')));
    await t.pump();
    expect(find.textContaining('38 متّصل'), findsOneWidget);
    expect(find.text('VPN'), findsNWidgets(2));
    await t.tap(find.text('إيقاف'));
    await _drain(t);
    expect(VpnNow.mode.value, isFalse);
    expect(find.text('إيقاف'), findsNothing);
    expect(find.text('أنت خارج شبكتك'), findsOneWidget, reason: 'أُطفئ يدويّاً وهو خارج شبكته ⇒ العرض يرجع');
    VpnNow.reset();
  });

  testWidgets('الحارس أطفأ الوضع ⇒ «رجعت لشبكتك» بالشريط لحظات ثمّ يختفي', (t) async {
    VpnNow.routeSource = () async => (linked: true, via: 'company');
    await t.pumpWidget(host(VpnNowBar(kind: VpnNowKind.devices, offNetwork: false, onOpenVpn: () {})));
    await _drain(t);
    await t.runAsync(() => VpnNow.enterMode());
    VpnNow.exitMode(auto: true);
    await t.pump();
    expect(find.text('رجعت لشبكتك'), findsOneWidget);
    expect(find.text('الفحص صار مباشر من موبايلك'), findsOneWidget);
    await t.pump(const Duration(seconds: 9));
    expect(find.text('رجعت لشبكتك'), findsNothing);
    VpnNow.reset();
  });

  test('«المعلومات الحيّة» عبر الـVPN ⇒ خانات البطاقة نفسها: مايكروتك (معالج/ذاكرة/حرارة + PPP والفولتيّة والمنافذ)، يوبيكويتي (إشارة/معالج/حرارة + المحطّات)، أولت (المشتركون/منافذ PON)', () {
    final r = VpnDeviceResult.fromJson({'id': 9, 'alive': true, 'ms': 21,
      'v': {'kind': 'ros', 'cpu': 37, 'mem': 41, 'temp': 52, 'up': 90000, 'volt': 24.2, 'ppp': 120, 'ports': {'up': 5, 'total': 8}, 'model': 'CCR1036', 'fw': '7.15'}})!;
    final ros = DeviceVitals.fromVpn(r.vitals!);
    expect(ros.vitals!.map((v) => '${v.label}=${v.value}${v.unit ?? ''}'), ['المعالج=37٪', 'الذاكرة=41٪', 'الحرارة=52°']);
    expect(ros.detail!.ports.where((p) => p.up).length, 5);
    expect(ros.detail!.ports.length, 8);
    expect(ros.detail!.extras.map((e) => e.k), containsAll(['جلسات PPP', 'الفولتيّة', 'المصدر']));
    expect(ros.detail!.glance.voltage, 24.2);
    expect(ros.detail!.uptime, isNotNull);
    expect(ros.error, isNull);

    final ap = DeviceVitals.fromVpn({'kind': 'airos', 'cpu': 8, 'temp': null, 'ap': true,
      'peers': [{'n': 'cust1', 's': -61, 'q': 95}, {'n': 'c2', 's': -72, 'q': 80}]});
    expect(ap.vitals!.first.label, '—', reason: 'نقطة وصول: لا إشارة لها (عند محطّاتها)');
    expect(ap.vitals![1].value, '8');
    expect(ap.detail!.glance.isAp, isTrue);
    expect(ap.detail!.glance.peersKnown, isTrue);
    expect(ap.detail!.peers.map((p) => p.signal), [-61, -72]);
    final sta = DeviceVitals.fromVpn({'kind': 'airos', 'sig': -58, 'ccq': 96, 'ap': false, 'tx': 300, 'rx': 270});
    expect(sta.vitals!.first.value, '-58');
    expect([sta.detail!.glance.ccq, sta.detail!.glance.txRateMbps, sta.detail!.glance.isAp], [96, 300, false]);

    final olt = DeviceVitals.fromVpn({'kind': 'olt', 'total': 3, 'online': 2,
      'pons': [{'label': 'EPON0/1', 'online': 2, 'total': 2, 'up': true}, {'label': 'EPON0/2', 'online': 0, 'total': 1, 'up': false}]});
    expect(olt.vitals!.take(2).map((v) => '${v.label}=${v.value}${v.unit}'), ['المشتركون=2/3', 'منافذ PON=1/2']);
    expect(olt.detail!.glance.onusTotal, 3);
  });

  group('«وضع VPN» والحارس', () {
    late DateTime clock;
    bool? net;
    int posts() => server.asked.where((a) => a.startsWith('POST')).length;
    Future<void> settleJobs() async {
      for (var i = 0; i < 200 && (VpnNow.devices.busy || VpnNow.subscribers.busy); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }

    setUp(() {
      clock = DateTime(2026, 11, 5, 21);
      VpnNow.now = () => clock;
      VpnNow.loopEvery = const Duration(hours: 1); // النبضة يدويّة بالاختبار
      net = false;
      VpnNow.guardProbe = () async => net;
      VpnNow.routeSource = () async => (linked: true, via: 'company');
      AgentNetPresence.reset();
    });

    test('خارج الشبكة ⇒ الحارس يرى شبكتك ⇒ يطفئ الوضع وحده ويقول «رجعت لشبكتك»؛ قبل ٢٠ث لا يسأل', () async {
      await VpnNow.enterMode();
      expect(VpnNow.mode.value, isTrue);
      net = true;
      clock = clock.add(const Duration(seconds: 10));
      await VpnNow.tick();
      expect(VpnNow.mode.value, isTrue, reason: 'الحارس كلّ ٢٠ث — والضغطة نفسها قرار');
      clock = clock.add(const Duration(seconds: 15));
      await VpnNow.tick();
      expect(VpnNow.mode.value, isFalse);
      expect(VpnNow.notice.value, contains('رجعت لشبكتك'));
    });

    test('شغّله وهو على شبكته (ضغطةٌ صريحة) ⇒ لا يُطفأ حتى تغيب الشبكة مرّةً ثمّ تعود', () async {
      AgentNetPresence.debugSet(NetPresence.on);
      await VpnNow.enterMode();
      net = true;
      clock = clock.add(const Duration(seconds: 25));
      await VpnNow.tick();
      expect(VpnNow.mode.value, isTrue);
      net = false;
      clock = clock.add(const Duration(seconds: 25));
      await VpnNow.tick();
      expect(VpnNow.mode.value, isTrue);
      net = true;
      clock = clock.add(const Duration(seconds: 25));
      await VpnNow.tick();
      expect(VpnNow.mode.value, isFalse);
    });

    test('القسم الظاهر يُحدَّث بإيقاعه (الأجهزة كلّ دقيقة على نفق الشركة) والمختفي لا؛ «إيقاف» يترك الفحص الجاري', () async {
      server.done = _devDone;
      VpnNow.attach(VpnNowKind.devices);
      addTearDown(() => VpnNow.detach(VpnNowKind.devices));
      await VpnNow.enterMode();
      await settleJobs();
      expect(posts(), 1, reason: 'الدخول يفحص القسم الظاهر');
      expect(VpnNow.intervalOf(VpnNowKind.devices), const Duration(minutes: 1));
      clock = clock.add(const Duration(seconds: 30));
      await VpnNow.tick();
      await settleJobs();
      expect(posts(), 1, reason: 'قبل الدقيقة لا');
      clock = clock.add(const Duration(seconds: 35));
      server.polls = 0;
      await VpnNow.tick();
      await settleJobs();
      expect(posts(), 2, reason: 'بعد الدقيقة يُعاد');
      VpnNow.detach(VpnNowKind.devices);
      clock = clock.add(const Duration(minutes: 5));
      await VpnNow.tick();
      await settleJobs();
      expect(posts(), 2, reason: 'القسم مختفٍ ⇒ لا فحص');
      VpnNow.attach(VpnNowKind.devices);
      server.polls = 0;
      final run = VpnNow.devices.run();
      expect(VpnNow.devices.busy, isTrue);
      VpnNow.exitMode();
      await run;
      expect(VpnNow.devices.phase, VpnBarPhase.idle, reason: 'نتيجة فحصٍ بعد الإيقاف لا تُعرض');
    });

    test('٦ نوفمبر: الوطنيّ/فايبر اكس (الطريق subscribers=false) ⇒ الوضع يفحص الأجهزة وحدها — لا فحص للمشتركين ولو كان قسمهم ظاهراً أو الضغطة منه', () async {
      server.done = _devDone;
      VpnNowApi.lastSubscribers = false;
      addTearDown(() => VpnNowApi.lastSubscribers = true);
      expect(VpnNow.subscribersOk, isFalse);
      VpnNow.attach(VpnNowKind.subscribers);
      addTearDown(() => VpnNow.detach(VpnNowKind.subscribers));
      await VpnNow.enterMode(from: VpnNowKind.subscribers);
      await settleJobs();
      expect(posts(), 0, reason: 'لا check-now للمشتركين');
      expect(VpnNow.mode.value, isTrue, reason: 'الوضع نفسه يعمل (للأجهزة)');
      VpnNow.attach(VpnNowKind.devices);
      addTearDown(() => VpnNow.detach(VpnNowKind.devices));
      await VpnNow.tick();
      await settleJobs();
      expect(posts(), 1, reason: 'الأجهزة وحدها');
      expect(server.asked.where((a) => a.startsWith('POST')).length, 1);
      VpnNow.exitMode();
    });

    test('ملفّه أو قالب شركته (غرفةٌ مؤقّتة) ⇒ إيقاعٌ أبطأ', () async {
      VpnNow.routeSource = () async => (linked: true, via: 'own');
      await VpnNow.enterMode();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(VpnNow.intervalOf(VpnNowKind.devices), const Duration(minutes: 3));
      expect(VpnNow.intervalOf(VpnNowKind.subscribers), const Duration(minutes: 5));
    });
  });
}
