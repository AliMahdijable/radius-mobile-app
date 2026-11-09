// شاشة «الفحص الشامل» (٦ نوفمبر): تقريرٌ منفصل لكلّ جهاز — الطافي أوّلاً، والسكتر بمشتركيه، والسويج بمنافذه، والأعداد فلاتر،
// والنقر يفتح الكلّ؛ واللقطة تُحفظ للفحص التالي. الشبكة بدائل (debugProbe/debugFetch/debugLimits).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/network_devices/check/devices_check_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/services/device_sweep_coordinator.dart';
import 'package:rad_mysvcs/services/devices_check.dart';
import 'package:rad_mysvcs/services/devices_check_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim_el/sim_harness.dart';

NetworkDevice _d(int id, String name, String type, {String brand = 'mikrotik', bool creds = true}) => NetworkDevice(
      id: id,
      adminId: '2',
      name: name,
      type: type,
      brand: brand,
      ip: '10.9.0.$id',
      port: 8728,
      protocol: 'api',
      hasCredentials: creds,
      lastStatus: 'online',
      createdAt: DateTime(2026, 11, 1),
    );

ProbeResult _r(DeviceDetail detail) => ProbeResult(vitals: const [], detail: detail, counters: const {});

void main() {
  setUpAll(simSetUpAll);

  final devices = [
    _d(1, 'راوتر التوزيع', 'router'),
    _d(2, 'سكتر الشمال', 'sector', brand: 'ubnt'),
    _d(3, 'سويج الكابينة', 'switch'),
    _d(4, 'لنك القرية', 'link', brand: 'ubnt'),
    _d(5, 'كاميرا', 'camera', brand: 'other', creds: false),
    _d(6, 'سيرفر', 'router'),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DevicesCheckRunner.debugLimits = () async => const CheckLimits(subSignal: -70, subCcq: 50);
    DevicesCheckRunner.debugSubscribers = () async => [
          Subscriber.fromJson(const {'idx': '7', 'username': 'weak.user@popq', 'last_mac': 'AA:BB:CC:00:00:01'}),
        ];
    DevicesCheckRunner.debugProbe = (d) async => (
          status: d.id == 4 ? 'offline' : 'online',
          responseMs: d.id == 4 ? null : 3,
          packetLoss: d.id == 6 ? 33.0 : 0.0,
          serviceOk: true,
        );
    DevicesCheckRunner.debugFetch = (d) async => switch (d.id) {
          1 => _r(const DeviceDetail(glance: DeviceGlance(cpu: 96, mem: 40, temp: 50, uptimeSec: 86400 * 9, ppp: 340))),
          2 => _r(const DeviceDetail(glance: DeviceGlance(isAp: true, cpu: 20), peers: [
              PeerLink(name: 'ali.home', signal: -61, ccq: 95, txRate: 130, rxRate: 117),
              PeerLink(name: 'omar.weak', signal: -79, ccq: 80),
              PeerLink(name: 'zaid.ccq', signal: -66, ccq: 35),
              PeerLink(name: 'sami', signal: -58, ccq: 90),
              PeerLink(name: 'huda', signal: -60, ccq: 92),
            ])),
          3 => _r(const DeviceDetail(glance: DeviceGlance(uptimeSec: 86400 * 3), ports: [
              PortTraffic(name: 'ether1', up: true, linkSpeed: '1Gbps'),
              PortTraffic(name: 'ether2', up: true, linkSpeed: '10Mbps'),
              PortTraffic(name: 'ether3', up: false),
            ])),
          6 => _r(const DeviceDetail(glance: DeviceGlance(cpu: 5, uptimeSec: 86400))),
          _ => throw StateError('no'),
        };
  });

  tearDown(() {
    DevicesCheckRunner.debugLimits = null;
    DevicesCheckRunner.debugProbe = null;
    DevicesCheckRunner.debugFetch = null;
    DevicesCheckRunner.debugSubscribers = null;
  });

  /// القائمة كسولة: يُرجَع لأعلاها ثمّ يُنزَل حتّى يظهر المطلوب.
  Future<void> see(WidgetTester t, Finder f) async {
    final list = find.byType(Scrollable).first;
    await t.scrollUntilVisible(find.byKey(const ValueKey('check-head')), -300, scrollable: list);
    await t.scrollUntilVisible(f, 300, scrollable: list);
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('تقريرٌ لكلّ جهاز: الطافي أوّلاً، والسكتر بمشتركيه المشكلة، والسويج بمنفذه — والأعداد فلاتر', (t) async {
    await pumpSim(t, const SimVariant(390, dark: false), settle: false,
        home: (_) => DevicesCheckScreen(devices: devices, viaVpn: false));
    await settle(t);
    expect(t.takeException(), isNull);
    expect(find.text('فُحصت 6 أجهزة'), findsOneWidget);
    // الترتيب: طافي ⇒ ملاحظات ⇒ لم يُقرأ ⇒ سليم
    final ys = {for (final id in [4, 1]) id: t.getTopLeft(find.byKey(ValueKey('check-card-$id'))).dy};
    expect(ys[4]!, lessThan(ys[1]!), reason: 'الطافي فوق ذي الملاحظات (والترتيب كلّه باختبار المقيِّم)');
    expect(find.text('لا يستجيب'), findsOneWidget);
    await see(t, find.text('المعالج 96٪ — عالي'));
    await see(t, find.text('فقدان حزم 33٪ — الطريق إليه متقطّع'));
    await see(t, find.textContaining('بلا بيانات دخول'));
    // السكتر: المشكلة ظاهرة والسليم مطويّ
    await see(t, find.text('المشتركون 5 — 2 فيهم مشكلة'));
    expect(find.text('omar.weak'), findsOneWidget);
    expect(find.text('zaid.ccq'), findsOneWidget);
    expect(find.text('ali.home'), findsNothing);
    await see(t, find.text('عرض كلّ المشتركين (3)'));
    await t.tap(find.text('عرض كلّ المشتركين (3)'));
    await settle(t);
    await see(t, find.text('ali.home'));
    // السويج: المنفذ ذو الملاحظة ظاهر
    await see(t, find.text('يشتغل 10Mbps — كيبل أو كونكتر'));
    // فلتر «طافي»
    await see(t, find.byKey(const ValueKey('check-count-down')));
    await t.tap(find.byKey(const ValueKey('check-count-down')));
    await settle(t);
    expect(find.byKey(const ValueKey('check-card-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('check-card-1')), findsNothing);
    // اللقطة حُفظت للفحص التالي
    final memo = await DevicesCheckMemoStore.load();
    expect(memo[3]!.ports['ether2']!.mbps, 10);
    expect(memo[2]!.peers, 5);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('٦ نوفمبر: كلّ قسمٍ يُفتح وحده (المشتركون لا يفتحون المنافذ)، والسرعة بـMbps', (t) async {
    final mt = _d(7, 'سكتر مايكروتك', 'sector');
    DevicesCheckRunner.debugFetch = (d) async => _r(const DeviceDetail(glance: DeviceGlance(isAp: true), peers: [
          PeerLink(name: 'weak.one', signal: -80, txSignal: -79, ccq: 90, txRate: 86, rxRate: 13, mac: 'aa:bb:cc:00:00:01'),
          PeerLink(name: 'good.one', signal: -55, txSignal: -57, ccq: 99, txRate: 130, rxRate: 117),
        ], ports: [
          PortTraffic(name: 'ether1', up: true, linkSpeed: '1Gbps'),
          PortTraffic(name: 'ether2', up: true, linkSpeed: '10Mbps'),
          PortTraffic(name: 'ether3', up: true, linkSpeed: '1Gbps'),
        ]));
    await pumpSim(t, const SimVariant(390, dark: false), settle: false, home: (_) => DevicesCheckScreen(devices: [mt], viaVpn: false));
    await settle(t);
    // ماك المحطّة طابق ماك جلسة مشترك ⇒ يوزره بدل الاسم، والماك تحته (للنسخ)
    expect(find.text('weak.user@popq'), findsOneWidget);
    expect(find.text('\u2066AA:BB:CC:00:00:01\u2069'), findsOneWidget);
    expect(find.text('good.one'), findsNothing);
    expect(find.text('ether3'), findsNothing, reason: 'المنفذ السليم مطويّ');
    expect(find.text(' Mbps'), findsOneWidget, reason: 'السرعة بوحدتها');
    await see(t, find.byKey(const ValueKey('check-more-7:subs')));
    await t.tap(find.byKey(const ValueKey('check-more-7:subs')));
    await settle(t);
    await see(t, find.text('good.one'));
    expect(find.text('ether3'), findsNothing, reason: 'فتح المشتركين لا يفتح المنافذ');
    await see(t, find.byKey(const ValueKey('check-more-7:ports')));
    await t.tap(find.byKey(const ValueKey('check-more-7:ports')));
    await settle(t);
    await see(t, find.text('ether3'));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('٣٢٠ داكن وخطّ ١٫٢: بلا فيضان', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSim(t, const SimVariant(320, dark: true), settle: false,
        home: (_) => DevicesCheckScreen(devices: devices, viaVpn: false));
    await settle(t);
    expect(t.takeException(), isNull);
    final sector = find.byKey(const ValueKey('check-card-2'));
    await t.scrollUntilVisible(sector, 300, scrollable: find.byType(Scrollable).first);
    await t.tap(sector);
    await settle(t);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('٩ نوفمبر: الفحص يمسك قسم الأجهزة ما دام مفتوحاً، ويفلته بالخروج (لا تزاحم على الجهاز نفسه)', (t) async {
    expect(DeviceSweep.suspended, isFalse);
    await pumpSim(t, const SimVariant(390, dark: false), settle: false,
        home: (_) => DevicesCheckScreen(devices: devices, viaVpn: false));
    await settle(t);
    expect(DeviceSweep.suspended, isTrue, reason: 'جولة الحال والبطاقات والتسخين تقف');
    await t.pumpWidget(const SizedBox());
    expect(DeviceSweep.suspended, isFalse, reason: 'تعود فور الخروج');
    // وقسم الأجهزة يقف بإمساكه ويعود فور فلته (جولةٌ فوريّة لا انتظار ٢٠ث) — حارس المصدر
    final screen = File('lib/screens/network_devices/network_devices_screen.dart').readAsStringSync();
    expect(screen, contains('DeviceSweep.holders.addListener(_onActiveChanged)'));
    expect(screen, contains('DeviceSweep.holders.removeListener(_onActiveChanged)'));
    expect(screen, contains('!DeviceSweep.suspended'));
  });
}
