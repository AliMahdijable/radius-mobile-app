// أجهزة البثّ يوبيكويتي (وضع AP) — المالك ٢٦ نوفمبر: «لاتنسى اكو اجهزه بث ubntu هم لازم تصلح هلشي ولاتنسى الاصلاح لازم بالتنبيهات
// هم وفحص الشامل». جهاز البثّ لا إشارة له هو: wireless.signal فيه rx محطّته الوحيدة (وصلة PtP) أو أرضيّة الضجيج (−96) بعدّة محطّات —
// وكانت تُعرض في خانة القائمة/الجدول، ورقم اللوحة الكبير، ووقائع الحاسبة، والبرج (طرف PtP). الآن إشارته عند مشتركيه: كيف يستقبلوننا
// (tx أوّلاً، [PeerLink.agentSignal]) — والتنبيه («القراءات الحسّاسة») يرسل tx المحطّة الوحيدة في `sigtx` بصفّه بالخادم (2ea1098).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';
import 'package:rad_mysvcs/core/platform/desktop_layout.dart';
import 'package:rad_mysvcs/core/util/bidi.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_reading.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_big_card.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/ubnt_live_panel.dart';
import 'package:rad_mysvcs/services/vitals_reporter.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'visual_perm/visual_perm_harness.dart';

// مشتركان على السكتر: (كيف نستقبله rx، كيف يستقبلنا tx)
const _a = UbntStation(
    mac: 'AA:BB:CC:00:00:01', hostname: 'om.bayda', signal: -63, txSignal: -58, noise: -95, ccq: 95, txRate: 130, rxRate: 117, connTime: 600);
const _b = UbntStation(
    mac: 'AA:BB:CC:00:00:02', hostname: 'azez.abo', signal: -70, txSignal: -66, noise: -95, ccq: 88, txRate: 104, rxRate: 78, connTime: 900);
// محطّةٌ لا ترسل إشارتها (airOS قديم بلا remote) ⇒ rx وحده
const _c = UbntStation(mac: 'AA:BB:CC:00:00:03', hostname: 'old.cpe', signal: -67, noise: -95, ccq: 80, txRate: 65, rxRate: 65, connTime: 300);

UbntStats _stats({required String mode, required int own, List<UbntStation> stations = const []}) => UbntStats(
      host: const UbntHost(hostname: 'Sector', devmodel: 'Rocket M5', fwversion: 'XM.v6.3.6', uptime: 5000, cpuload: 9, temperature: 0),
      wireless: UbntWireless(
        essid: 'Sector-North',
        mode: mode,
        signal: own,
        noise: -95,
        ccq: 92,
        txRate: 130,
        rxRate: 117,
        channel: 0,
        frequency: 5745,
        distance: 0,
        chanbw: 20,
      ),
      interfaces: const [
        UbntInterface(ifname: 'eth0', hwaddr: 'F0:9F:C2:9C:36:24', enabled: true, plugged: true, rxBytes: 100, txBytes: 100),
        UbntInterface(ifname: 'ath0', hwaddr: 'F0:9F:C2:9C:36:25', enabled: true, plugged: true, rxBytes: 100, txBytes: 100),
      ],
      stations: stations,
      memTotalKb: 29616,
      memFreeKb: 10316,
      memBuffersKb: 2400,
    );

NetworkDevice _dev(int id, {String type = 'ap'}) => NetworkDevice(
      id: id,
      adminId: '1',
      name: 'سكتر الشمال',
      type: type,
      brand: 'ubnt',
      model: 'Rocket M5',
      ip: '10.9.2.${id % 250}',
      port: 22,
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime(2026, 11, 1),
    );

Future<ProbeResult> _read(NetworkDevice d, UbntStats s) async {
  NetworkDevicesApi.debugSeedCredentials(d.id, {'user': 'u', 'pass': 'p'}, DateTime.now());
  UbntApi.debugFetch = () async => s;
  return DeviceVitals.fetch(d, detailed: true);
}

void main() {
  tearDown(() => UbntApi.debugFetch = null);

  group('الخانة والتنبيه والبرج', () {
    test('بمحطّتين (ap-ptmp، «إشارته» −96 أرضيّة الضجيج): الخانة متوسّط كيف يستقبلوننا، لا −96؛ والتنبيه null للمقياسين', () async {
      final d = _dev(951);
      final r = await _read(d, _stats(mode: 'ap-ptmp', own: -96, stations: const [_a, _b]));
      final sig = r.vitals.first;
      expect([sig.label, sig.value, sig.unit], ['الإشارة', '-62', 'dBm'], reason: '(−58 −66)/2 — كان «-96»');
      expect(r.vitals.where((v) => v.value == '-96'), isEmpty);
      expect(r.detail.glance.signal, isNull, reason: 'نقطة وصول: لا إشارة لها هي (كمايكروتك)');
      expect(r.detail.glance.isAp, isTrue);
      expect(VitalsReporter.readingOf(d.id, r.detail.glance, peers: r.detail.peers),
          {'id': d.id, 'cpu': 9, 'signal': null, 'sigtx': null, 'ccq': 92});
      expect(TowerReading.fromProbe(r).signal, -62, reason: 'البرج والقائمة الرقم نفسه');
    });

    test('بمحطّةٍ واحدة (طرف PtP المرسل، «إشارته» rx المحطّة −63): كيف تستقبلنا هي (−58) في الخانة والبرج والتنبيه (sigtx)', () async {
      final d = _dev(952, type: 'link');
      final r = await _read(d, _stats(mode: 'ap-ptp', own: -63, stations: const [_a]));
      expect(r.vitals.first.value, '-58');
      expect(VitalsReporter.readingOf(d.id, r.detail.glance, peers: r.detail.peers),
          {'id': d.id, 'cpu': 9, 'sigtx': -58, 'signal': null, 'ccq': 92});
      expect(TowerReading.fromProbe(r).signal, -58, reason: 'كان −63 (rx) — ومايكروتك كان tx');
    });

    test('محطّةٌ لا ترسل إشارتها ⇒ rx كما كان (الخانة والتنبيه بـsignal)؛ وبلا محطّات ⇒ «—» لا −96', () async {
      final d = _dev(953, type: 'link');
      final r = await _read(d, _stats(mode: 'ap-ptp', own: -67, stations: const [_c]));
      expect(r.vitals.first.value, '-67');
      expect(VitalsReporter.readingOf(d.id, r.detail.glance, peers: r.detail.peers), {'id': d.id, 'cpu': 9, 'signal': -67, 'ccq': 92});
      final e = await _read(_dev(954), _stats(mode: 'ap-ptmp', own: -96));
      expect(e.vitals.first.label, '—');
      expect(e.detail.glance.signal, isNull);
      expect(TowerReading.fromProbe(e).signal, isNull, reason: 'لا أرضيّة الضجيج مكان الإشارة');
    });

    test('المحطّة (جهاز المشترك أو طرف الوصلة المستقبل) كما كانت: إشارتها هي', () async {
      final d = _dev(955, type: 'station');
      // جدول المحطّة فيه نقطة الوصول: signal = ما تستقبله المحطّة، txSignal = ما تستقبله نقطة الوصول منها
      const apEntry = UbntStation(mac: 'F0:9F:C2:00:00:09', signal: -61, txSignal: -64, noise: -95, ccq: 97, txRate: 130, rxRate: 130, connTime: 60);
      final r = await _read(d, _stats(mode: 'sta-ptmp', own: -61, stations: const [apEntry]));
      expect(r.vitals.first.value, '-61');
      expect(r.detail.glance.signal, -61);
      expect(VitalsReporter.readingOf(d.id, r.detail.glance, peers: r.detail.peers), {'id': d.id, 'cpu': 9, 'signal': -61, 'ccq': 92});
      expect(TowerReading.fromProbe(r).signal, -61);
    });

    test('عبر الـVPN: جهاز البثّ يُعرض بمتوسّط محطّاته (tx أوّلاً) ولا تُصدَّق «sig» الخادم (أرضيّة الضجيج)', () {
      final ap = DeviceVitals.fromVpn({
        'kind': 'airos', 'cpu': 8, 'ap': true, 'sig': -96,
        'peers': [{'n': 'cust1', 's': -61, 'ts': -56, 'q': 95}, {'n': 'c2', 's': -72, 'q': 80}],
      });
      expect([ap.vitals!.first.label, ap.vitals!.first.value], ['الإشارة', '-64'], reason: '(−56 tx + −72 rx وحده)/2');
      expect(ap.detail!.glance.signal, isNull);
      final empty = DeviceVitals.fromVpn({'kind': 'airos', 'cpu': 8, 'ap': true, 'sig': -96, 'peers': []});
      expect(empty.vitals!.first.label, '—');
    });
  });

  group('البطاقة الكبيرة: طرف الوصلة المرسل', () {
    testWidgets('كيف تستقبلنا المحطّة (−58) رقماً كبيراً و«rx −63» تحته — 320 و390 فاتحاً وداكناً', (t) async {
      await visualSetUpAll();
      final d = _dev(956, type: 'link');
      final r = await t.runAsync(() => _read(d, _stats(mode: 'ap-ptp', own: -63, stations: const [_a])));
      final st = VitalsState(at: DateTime(2026, 11, 26, 9), vitals: r!.vitals, detail: r.detail);
      for (final w in [320.0, 390.0]) {
        for (final dark in [false, true]) {
          AppColors.setDarkMode(dark);
          t.view.physicalSize = Size(w, 1200);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(MaterialApp(
            theme: ThemeData(fontFamily: 'IBMPlexSansArabic'),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                backgroundColor: AppColors.bg,
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: DeviceBigCard(device: d, state: st, medianMs: 12, now: DateTime(2026, 11, 26, 9, 1)),
                ),
              ),
            ),
          ));
          await t.pump();
          expect(find.textContaining('-58', findRichText: true), findsWidgets, reason: '@$w — الرقم الكبير (TextSpan)');
          expect(find.textContaining('-63 ', findRichText: true), findsNothing, reason: '@$w — rx ليس الرقم الكبير');
          expect(find.text(iso('rx -63')), findsOneWidget, reason: '@$w');
          expect(t.takeException(), isNull, reason: 'لا تجاوز @$w dark=$dark');
        }
      }
      AppColors.setDarkMode(false);
    });
  });

  group('لوحة الجهاز', () {
    setUpAll(visualSetUpAll);

    Future<void> pumpPanel(WidgetTester t, NetworkDevice d, UbntStats s, {required bool desk, double width = 430}) async {
      await visualSetUp(s1bSasOwner);
      NetworkDevicesApi.debugSeedCredentials(d.id, {'user': 'u', 'pass': 'p'}, DateTime.now());
      UbntApi.debugFetch = () async => s;
      Widget panel = Scaffold(body: SingleChildScrollView(child: UbntLivePanel(device: d)));
      if (desk) panel = DesktopScope(child: panel);
      await pumpVisual(t, desk ? const VisualDevice('_desk', Size(1260, 860), 1) : VisualDevice('_w', Size(width, 932), 3),
          home: (_) => panel);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> done(WidgetTester t) async {
      UbntApi.debugFetch = null;
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 30));
      await visualTearDown();
    }

    bool shows(String s) => find.text(s).evaluate().isNotEmpty || find.text(iso(s)).evaluate().isNotEmpty;
    bool anyContains(String s) => find.textContaining(s).evaluate().isNotEmpty;

    for (final width in [320.0, 430.0]) {
      testWidgets('الهاتف @$width: بمحطّتين — الرقم الكبير متوسّط المشتركين (−62) وأضعفهم (−66)، لا −96', (t) async {
        await pumpPanel(t, _dev(961 + width.toInt()), _stats(mode: 'ap-ptmp', own: -96, stations: const [_a, _b]), desk: false, width: width);
        try {
          expect(shows('-62'), isTrue);
          expect(shows('متوسّط المشتركين'), isTrue);
          expect(shows('الأضعف'), isTrue);
          expect(anyContains('-96'), isFalse, reason: 'أرضيّة الضجيج ليست إشارة');
          expect(t.takeException(), isNull);
        } finally {
          await done(t);
        }
      });
    }

    testWidgets('الهاتف: بمحطّةٍ واحدة — كيف تستقبلنا (−58) و«rx −63» بجانبه، لا −63 رقماً كبيراً', (t) async {
      await pumpPanel(t, _dev(971, type: 'link'), _stats(mode: 'ap-ptp', own: -63, stations: const [_a]), desk: false);
      try {
        expect(shows('-58'), isTrue);
        expect(shows('rx'), isTrue);
        expect(t.takeException(), isNull);
      } finally {
        await done(t);
      }
    });

    testWidgets('الهاتف: بلا مشتركين — «—» و«لا عملاء الآن»، لا −96', (t) async {
      await pumpPanel(t, _dev(972), _stats(mode: 'ap-ptmp', own: -96), desk: false);
      try {
        expect(shows('لا عملاء الآن'), isTrue);
        expect(anyContains('-96'), isFalse);
        expect(t.takeException(), isNull);
      } finally {
        await done(t);
      }
    });

    testWidgets('الحاسبة: بمحطّتين — «العملاء 2 · أضعفهم −66»، ووقائع اللاسلكيّ بلا «الإشارة −96»', (t) async {
      await pumpPanel(t, _dev(973), _stats(mode: 'ap-ptmp', own: -96, stations: const [_a, _b]), desk: true);
      try {
        expect(anyContains('أضعفهم'), isTrue);
        expect(anyContains('-66'), isTrue);
        expect(anyContains('-96'), isFalse);
        expect(t.takeException(), isNull);
      } finally {
        await done(t);
      }
    });

    testWidgets('الحاسبة: بمحطّةٍ واحدة — خانة الإشارة −58 و«rx −63» تحتها', (t) async {
      await pumpPanel(t, _dev(974, type: 'link'), _stats(mode: 'ap-ptp', own: -63, stations: const [_a]), desk: true);
      try {
        expect(shows('-58'), isTrue);
        expect(anyContains('rx -63'), isTrue);
        expect(t.takeException(), isNull);
      } finally {
        await done(t);
      }
    });

    testWidgets('الحاسبة: المحطّة كما كانت — إشارتها هي (−61)', (t) async {
      const apEntry = UbntStation(mac: 'F0:9F:C2:00:00:09', signal: -61, txSignal: -64, noise: -95, ccq: 97, txRate: 130, rxRate: 130, connTime: 60);
      await pumpPanel(t, _dev(975, type: 'station'), _stats(mode: 'sta-ptmp', own: -61, stations: const [apEntry]), desk: true);
      try {
        expect(shows('-61'), isTrue);
        expect(t.takeException(), isNull);
      } finally {
        await done(t);
      }
    });
  });
}
