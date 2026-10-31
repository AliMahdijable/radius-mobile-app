import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/bdcom_epon.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/core/util/bidi.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_big_card.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'support/app_fonts.dart';
import 'support/device_cards_fixture.dart';

/// «البطاقات الكبيرة» بقسم الأجهزة (المالك ٣١ أكتوبر: «نظرة عامه ع الاجهز نلغيها ونستبدل بدالها تغير نوع العرض… كارتات كبار
/// بيها المعلومات المهمّة وملوّنة… بدقّة»): أرقام البطاقة من مسارات القراءة الحقيقيّة (ميكروتك سكتراً ومحطّةً، والأولت)، دور
/// كلّ جهاز ولونه، وما تعرضه البطاقة لكلّ دور وحالة — على ٣٢٠–٤٣٠ والحاسبة، فاتحاً وداكناً، بلا فيضان.
void main() {
  group('الأرقام من مسار القراءة الحقيقيّ', () {
    late _CredsServer server;
    setUp(() {
      server = _CredsServer();
      ApiClient.dio.httpClientAdapter = server;
      NetworkDevicesApi.invalidateCredentialsCache();
    });
    tearDown(() {
      MikrotikApi.debugFetch = null;
      VsolOltApi.debugFetch = null;
    });

    NetworkDevice dev(int id, String type, String brand) => NetworkDevice(
          id: id,
          adminId: '1',
          name: 'd$id',
          type: type,
          brand: brand,
          ip: '10.0.0.$id',
          port: 8728,
          protocol: 'api',
          hasCredentials: true,
          lastStatus: 'online',
          createdAt: DateTime(2026),
        );

    test('سكتر ميكروتك (ap-bridge): نقطة وصول، عملاؤه مقروءون، التردّد والعرض والمدّة — والخفيفة لا تدّعي «0 متّصل»', () async {
      MikrotikApi.debugFetch = () async => _mtk(mode: 'ap-bridge', clients: 5);
      final r = await DeviceVitals.fetch(dev(11, 'sector', 'mikrotik'), detailed: true);
      final g = r.detail.glance;
      expect(g.isAp, isTrue);
      expect(g.peersKnown, isTrue);
      expect(r.detail.peers, hasLength(5));
      expect([g.freqMhz, g.widthMhz, g.ssid], [5535, 20, 'S1']);
      expect(g.signal, isNull, reason: 'نقطة الوصول لا إشارة لها — إشاراتها عند عملائها');
      expect(g.uptimeSec, 9 * 604800 + 4 * 86400 + 3 * 3600 + 12 * 60 + 5);
      expect([g.cpu, g.mem, g.temp], [5, 37, 38]);
      // المنافذ الفعليّة بنوع الواجهة (ether)، والجلسات/الأنفاق/الجسر ليست منافذ؛ واسم العميل: DHCP ثمّ تعليقه.
      expect({for (final p in r.detail.ports) p.name: p.physical},
          {'ether1': true, 'sfp-sfpplus1': true, 'bridge1': false, 'wlan1': false, '<pppoe-ali>': false, 'Tunn-Hassan': false});
      expect(r.detail.peers.first.name, 'c1', reason: 'تعليق جدول التسجيل حين لا اسم DHCP');
      final light = await DeviceVitals.fetch(dev(11, 'sector', 'mikrotik'));
      expect(light.detail.glance.peersKnown, isFalse, reason: 'القراءة الخفيفة بلا جدول التسجيل');
    });

    test('محطّة ميكروتك (لنك): إشارة الوصلة وجودتها وسرعتها من الطرف الآخر وحده', () async {
      MikrotikApi.debugFetch = () async => _mtk(mode: 'station-bridge', clients: 1);
      final r = await DeviceVitals.fetch(dev(12, 'link', 'mikrotik'), detailed: true);
      final g = r.detail.glance;
      expect(g.isAp, isFalse);
      expect([g.signal, g.ccq, g.snr, g.rxRateMbps, g.txRateMbps], [-36, 100, 40, 78, 86]);
    });

    test('ميكروتك بلا مجسّ حرارة ولا SwOS معالج: «—» لا صفر', () async {
      MikrotikApi.debugFetch = () async => _mtk(mode: 'ap-bridge', clients: 0, temp: false, cpuKnown: false);
      final g = (await DeviceVitals.fetch(dev(13, 'sector', 'mikrotik'), detailed: true)).detail.glance;
      expect([g.temp, g.cpu], [null, null]);
      expect(g.peersKnown, isTrue, reason: 'قائمةٌ مقروءةٌ فارغة = «لا متّصلين الآن» صادقة');
    });

    test('الأولت: المشتركون ومنافذ PON (بحالتها) والربط والمعالج والحرارة من اللقطة نفسها', () {
      const s = VsolOltStats(
        uptime: Duration(days: 27),
        chassis: BdcomChassis(cpuPct: 18, boxTempC: 44),
        uplinks: [
          VsolUplink(index: 1, name: 'GE0/1', up: true, speedMbps: 1000, rxBytes: 0, txBytes: 0),
          VsolUplink(index: 2, name: 'GE0/2', up: false, speedMbps: 0, rxBytes: 0, txBytes: 0),
        ],
        ponPorts: [
          VsolPonPort(index: 3, slot: 0, port: 1, up: true, rxBytes: 0, txBytes: 0, onuTotal: 3, onuOnline: 2),
          VsolPonPort(index: 4, slot: 0, port: 2, up: false, rxBytes: 0, txBytes: 0),
        ],
        onus: [
          VsolOnu(ifIndex: 10, slot: 0, ponPort: 1, onuId: 1, online: true),
          VsolOnu(ifIndex: 11, slot: 0, ponPort: 1, onuId: 2, online: true),
          VsolOnu(ifIndex: 12, slot: 0, ponPort: 1, onuId: 3, online: false),
        ],
      );
      final g = oltProbeResult(s).detail.glance;
      expect([g.onusOnline, g.onusTotal, g.uplinksUp, g.uplinksTotal, g.cpu, g.temp], [2, 3, 1, 2, 18, 44]);
      expect(g.pons.map((p) => '${p.label}:${p.up}:${p.online}/${p.total}'), ['EPON0/1:true:2/3', 'EPON0/2:false:0/0']);
      expect(g.uptimeSec, 27 * 86400);
      expect(oltProbeResult(const VsolOltStats()).detail.glance.onusTotal, isNull, reason: 'لقطةٌ فارغة لا «0/0»');
    });

    test('مدّة RouterOS بكلّ صيغها، وغير المقروء null', () {
      expect(routerOsSeconds('1w2d03:04:05'), 604800 + 2 * 86400 + 3 * 3600 + 4 * 60 + 5);
      expect(routerOsSeconds('5h3m2s'), 5 * 3600 + 3 * 60 + 2);
      expect(routerOsSeconds('03:04:05'), 3 * 3600 + 4 * 60 + 5);
      expect(routerOsSeconds(''), isNull);
      expect(routerOsSeconds('500ms'), isNull);
    });
  });

  group('دور الجهاز ولونه', () {
    NetworkDevice d(String type, String brand, {String? model}) => NetworkDevice(
          id: 1, adminId: '1', name: 'x', type: type, brand: brand, model: model, ip: '1.1.1.1', port: 1, lastStatus: 'online',
          createdAt: DateTime(2026));

    test('الأولت بملفّه لا بنوعه، والبقيّة بالنوع', () {
      expect(DeviceRole.of(d('other', 'bdcom', model: 'BDCOM P3600-04')), DeviceRole.olt);
      expect(DeviceRole.of(d('other', 'vsol', model: 'V1600D')), DeviceRole.olt);
      expect(DeviceRole.of(d('sector', 'ubnt')), DeviceRole.sector);
      expect(DeviceRole.of(d('ap', 'ubnt')), DeviceRole.sector, reason: 'سجلٌّ قديم بنوع ap');
      expect(DeviceRole.of(d('link', 'mimosa')), DeviceRole.link);
      expect(DeviceRole.of(d('switch', 'mikrotik')), DeviceRole.switchRole);
      expect(DeviceRole.of(d('router', 'mikrotik')), DeviceRole.router);
      expect(DeviceRole.of(d('other', 'cisco')), DeviceRole.switchRole);
      expect(DeviceRole.of(d('other', 'mikrotik')), DeviceRole.other);
    });

    test('🚨 بلا ألوان أدوار (المالك: «الالوان الكارتات الغيها لان صايره نشاز») — الدور اسمٌ وأيقونة', () {
      final src = File('lib/screens/network_devices/widgets/device_big_card.dart').readAsStringSync();
      expect(src.contains('deviceRole('), isFalse);
      expect(src.contains('color: down ? null : AppColors.surfaceSunken,'), isTrue);
      expect(src.contains('Text(role.label, style: AppType.pillBold(color: AppColors.textMid))'), isTrue);
      expect(File('lib/theme/colors.dart').readAsStringSync().contains('deviceRole'), isFalse);
    });

    test('جهاز بثٍّ AP عليه أكثر من لاسلكيّ = سكتر أيّاً كان نوعه المسجّل؛ وبواحدٍ أو بلا AP يبقى نوعه', () {
      const ap3 = DeviceDetail(
          peers: [PeerLink(name: 'a'), PeerLink(name: 'b'), PeerLink(name: 'c')], glance: DeviceGlance(isAp: true, peersKnown: true));
      const ap1 = DeviceDetail(peers: [PeerLink(name: 'a')], glance: DeviceGlance(isAp: true, peersKnown: true));
      const sta = DeviceDetail(peers: [PeerLink(name: 'a'), PeerLink(name: 'b')], glance: DeviceGlance(isAp: false));
      final router = d('router', 'mikrotik');
      expect(DeviceRole.live(router, ap3), DeviceRole.sector, reason: '«سكتر 1» مسجّلٌ راوتراً');
      expect(DeviceRole.live(router, ap1), DeviceRole.router);
      expect(DeviceRole.live(router, sta), DeviceRole.router);
      expect(DeviceRole.live(router, null), DeviceRole.router);
      expect(DeviceRole.live(d('other', 'bdcom', model: 'BDCOM P3600-04'), ap3), DeviceRole.olt);
    });
  });

  group('البطاقة تعرض', () {
    final now = DateTime(2026, 10, 31, 9);
    final fx = DeviceCardsFixture(now);
    setUpAll(loadAppFonts);
    tearDown(() => AppColors.setDarkMode(false));

    Future<void> pump(WidgetTester t, NetworkDevice d, {double width = 390, bool dark = false, int rows = 4}) async {
      AppColors.setDarkMode(dark);
      t.view.physicalSize = Size(width, 1400);
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
              child: DeviceBigCard(device: d, state: fx.stateOf(d), medianMs: 12, now: now, rows: rows),
            ),
          ),
        ),
      ));
      await t.pump();
    }

    bool shows(String s) => find.text(s).evaluate().isNotEmpty || find.text(iso(s)).evaluate().isNotEmpty;

    testWidgets('السكتر: عدد المتّصلين ومتوسّط إشاراتهم وأضعفها، والأضعف أوّلاً بأربعة أسطر ثمّ «و7 آخرون»', (t) async {
      await pump(t, fx.sector);
      expect(find.text('سكتر'), findsOneWidget);
      expect(find.textContaining('11'), findsWidgets);
      expect(find.textContaining('-64'), findsOneWidget, reason: 'متوسّط الإشارات −64.45 ⇒ −64');
      expect(find.textContaining('-79'), findsWidgets, reason: 'أضعف إشارة (الخانة + سطر صاحبها)');
      expect(shows('ali-home'), isTrue, reason: 'الأضعف أوّلاً');
      expect(shows('m.jawad'), isFalse, reason: 'الأقوى خارج الثمانية');
      expect(find.text('و3 آخرون'), findsOneWidget, reason: 'أربعة أسطر × خليّتين = ٨ من ١١');
      expect(shows('-79'), isTrue);
      expect(shows('CCQ 61%'), isFalse, reason: 'باختصار: الاسم وإشارته');
    });

    testWidgets('«سكتر 1» المسجّل راوتراً (AP بمتّصلين): يُعرض سكتراً بمتّصليه', (t) async {
      final asRouter = NetworkDevice(
        id: 21, adminId: '1', name: 'سكتر 1', type: 'router', brand: 'mikrotik', model: 'BaseBox 5', ip: '10.70.241.2', port: 8728,
        protocol: 'api', hasCredentials: true, lastStatus: 'online', lastResponseMs: 7, createdAt: DateTime(2026));
      AppColors.setDarkMode(false);
      t.view.physicalSize = const Size(390, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
              body: SingleChildScrollView(child: DeviceBigCard(device: asRouter, state: fx.stateOf(fx.sector), now: now))),
        ),
      ));
      await t.pump();
      expect(find.text('سكتر'), findsOneWidget);
      expect(find.text('راوتر'), findsNothing);
      expect(shows('ali-home'), isTrue);
    });

    testWidgets('اللنك (ميموزا): الإشارة، SNR مكان CCQ (لا يقرؤه)، سرعة الربط وإرساله، وأرقام الوصلة', (t) async {
      await pump(t, fx.link);
      expect(find.text('لنك'), findsOneWidget);
      expect(find.textContaining('-52'), findsOneWidget);
      expect(find.text('SNR'), findsOneWidget);
      expect(find.textContaining('520'), findsOneWidget);
      expect(shows('إرسال 433'), isTrue);
      for (final v in ['-88 dBm', '5745 MHz', '80 MHz', 'Haidariya-PTP']) {
        expect(shows(v), isTrue, reason: v);
      }
      expect(find.textContaining('الوصلة منذ'), findsOneWidget, reason: 'ميموزا: مدّة الوصلة لا عمر وكيل SNMP');
    });

    testWidgets('لنك 60GHz: جودة الإشارة ٪ (لا CCQ لها) والمسافة', (t) async {
      await pump(t, fx.link60);
      expect(find.text('جودة الإشارة'), findsOneWidget);
      expect(find.textContaining('87'), findsOneWidget);
      expect(shows('412 م'), isTrue);
      expect(find.textContaining('1540'), findsOneWidget, reason: 'سرعة الإرسال وحدها — لا تُنسخ «إرسال 1540» تحتها');
    });

    testWidgets('السويتش: المتّصلة من الكلّ، خريطة المنافذ، الأعلى حِملاً، واستهلاك PoE', (t) async {
      await pump(t, fx.switchDev);
      expect(find.text('سويتش'), findsOneWidget);
      expect(find.textContaining('13'), findsWidgets);
      expect(shows('13 متّصل من 18'), isTrue);
      expect(find.text('استهلاك PoE'), findsOneWidget);
      expect(find.textContaining('47.3'), findsOneWidget);
      expect(shows('ether1-uplink'), isTrue, reason: 'الأعلى حِملاً');
      final ports = {'ether1-uplink', for (var i = 2; i <= 16; i++) 'ether$i', 'sfp17', 'sfp18'};
      expect(find.byWidgetPredicate((w) => w is Tooltip && ports.contains(w.message)), findsNWidgets(18),
          reason: 'مربّعٌ لكلّ منفذ');
    });

    testWidgets('🚨 السويتش/السيرفر: الإيثرات وحدها — جلسات PPP والأنفاق لا تُعدّ منافذ ولا تدخل «الأعلى حِملاً»', (t) async {
      final st = fx.stateOf(fx.switchDev);
      final ports = [
        ...st.detail!.ports,
        for (var i = 0; i < 120; i++) PortTraffic(name: '<pppoe-u$i>', up: true, rxBps: 900000000, txBps: 900000000, physical: false),
        const PortTraffic(name: 'Tunn-Hassan', up: true, rxBps: 950000000, txBps: 1, physical: false),
      ];
      final withPpp = VitalsState(
        vitals: st.vitals,
        at: st.at,
        detail: DeviceDetail(ports: ports, glance: st.detail!.glance),
      );
      AppColors.setDarkMode(false);
      t.view.physicalSize = const Size(390, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SingleChildScrollView(child: DeviceBigCard(device: fx.switchDev, state: withPpp, now: now))),
        ),
      ));
      await t.pump();
      expect(shows('13 متّصل من 18'), isTrue, reason: 'لا ١٣٣ من ١٣٩');
      expect(shows('Tunn-Hassan'), isFalse);
      expect(shows('<pppoe-u0>'), isFalse);
      expect(find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith('<pppoe')), findsNothing);
    });

    testWidgets('الأولت: منافذ PON — المطفأ أوّلاً ثمّ الأقلّ نسبةً، وغير المتّصلين والربط في العنوان', (t) async {
      await pump(t, fx.olt);
      expect(find.text('أولت'), findsOneWidget);
      expect(find.text('مطفأ'), findsOneWidget);
      final y = {
        for (final l in ['EPON0/4', 'EPON0/2', 'EPON0/3', 'EPON0/1']) l: t.getTopLeft(find.text(iso(l))).dy,
      };
      expect(y['EPON0/4']!, lessThan(y['EPON0/2']!));
      expect(y['EPON0/2']!, lessThan(y['EPON0/3']!));
      expect(y['EPON0/3']!, lessThan(y['EPON0/1']!));
      expect(shows('17 غير متّصل · الربط 2/3'), isTrue);
    });

    testWidgets('الراوتر: المعالج والذاكرة والحرارة، جلسات PPP والفولتيّة، والواجهات الأعلى حِملاً', (t) async {
      await pump(t, fx.router);
      expect(find.text('راوتر'), findsOneWidget);
      expect(find.text('جلسات PPP '), findsOneWidget);
      expect(shows('1284'), isTrue);
      expect(shows('24.1 V'), isTrue);
      expect(shows('sfp-sfpplus1-WAN'), isTrue);
      expect(find.text('المنافذ الأعلى حِملاً'), findsOneWidget);
    });

    testWidgets('المعطّل: سطر «آخر ظهور» وحده بلا خانات؛ وبلا بيانات دخول: سببٌ صريح؛ وقبل القراءة: «…»', (t) async {
      await pump(t, fx.down);
      expect(find.text('آخر ظهور منذ 3 ساعات'), findsOneWidget);
      expect(find.textContaining('غير متّصل'), findsOneWidget);
      expect(find.text('المتّصلون'), findsNothing);
      await pump(t, fx.noCreds);
      expect(find.textContaining('أضف بيانات الدخول'), findsOneWidget);
      await pump(t, fx.pending);
      expect(find.text('…'), findsNWidgets(3));
      expect(find.text('يقرأ الجهاز…'), findsOneWidget);
    });

    testWidgets('🚨 كلّ بطاقة على ٣٢٠–٤٣٠ والحاسبة، فاتحاً وداكناً: بلا فيضان ولا استثناء', (t) async {
      for (final d in fx.all) {
        for (final w in [320.0, 360.0, 390.0, 430.0, 520.0]) {
          for (final dark in [false, true]) {
            await pump(t, d, width: w, dark: dark, rows: w >= 520 ? 5 : 4);
            expect(t.takeException(), isNull, reason: '${d.name} @$w ${dark ? 'داكن' : 'فاتح'}');
          }
        }
      }
    });
  });
}

/// يردّ على بيانات الدخول وحدها (DeviceVitals.fetch يسأل عنها قبل الجلسة).
class _CredsServer implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final ok = RegExp(r'^/api/v2/admin/devices/\d+/credentials$').hasMatch(o.uri.path);
    final data = ok
        ? {'success': true, 'credentials': {'user': 'admin', 'pass': 'x', 'community': 'public'}}
        : {'success': false};
    return ResponseBody.fromString(jsonEncode(data), ok ? 200 : 404, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

MikrotikStats _mtk({required String mode, required int clients, bool temp = true, bool cpuKnown = true}) {
  MikrotikWirelessClient c(int i, int sig) => MikrotikWirelessClient(
      mac: 'AA:BB:CC:00:00:0$i', iface: 'wlan1', signalStrength: sig, txSignalStrength: sig - 9, signalToNoise: 40,
      txCcq: 100, rxCcq: 99, txRate: 86, rxRate: 78, uptime: 3600 * i, comment: 'c$i');
  return MikrotikStats(
    cpuLoad: 5,
    memUsedPercent: 37,
    memTotalBytes: 64 << 20,
    memFreeBytes: 40 << 20,
    uptime: '9w4d3h12m5s',
    version: '6.49.19',
    boardName: 'BaseBox 5',
    architectureName: 'mipsbe',
    cpuCount: 1,
    cpuFrequencyMhz: 600,
    temperature: temp ? 38 : null,
    voltage: 22.6,
    interfaces: const [
      MikrotikInterface(name: 'ether1', type: 'ether', running: true, disabled: false, rxBytes: 1, txBytes: 1),
      MikrotikInterface(name: 'sfp-sfpplus1', type: 'ether', running: true, disabled: false, rxBytes: 1, txBytes: 1),
      MikrotikInterface(name: 'bridge1', type: 'bridge', running: true, disabled: false, rxBytes: 1, txBytes: 1),
      MikrotikInterface(name: 'wlan1', type: 'wlan', running: true, disabled: false, rxBytes: 1, txBytes: 1),
      MikrotikInterface(name: '<pppoe-ali>', type: 'pppoe-in', running: true, disabled: false, rxBytes: 1, txBytes: 1),
      MikrotikInterface(name: 'Tunn-Hassan', type: 'eoip-tunnel', running: true, disabled: false, rxBytes: 1, txBytes: 1),
    ],
    pppActiveCount: 0,
    cpuKnown: cpuKnown,
    wirelessInterfaces: [
      MikrotikWireless(name: 'wlan1', ssid: 'S1', mode: mode, band: '5ghz-a/n', frequency: 5535, channelWidth: 20, txPower: 24, disabled: false, running: true),
    ],
    wirelessClients: [for (var i = 1; i <= clients; i++) c(i, -36 - i + 1)],
  );
}
