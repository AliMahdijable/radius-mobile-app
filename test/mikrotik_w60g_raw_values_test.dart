import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';
import 'package:rad_mysvcs/api/mikrotik_binary_api.dart';
import 'package:rad_mysvcs/api/routeros_channel.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_big_card.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'support/app_fonts.dart';

/// ١٦ نوفمبر — المالك (لقطتا «الأجهزة» بحساب alawaliq:2): «lhg60 سرعة الربط ماكو» + «كذالك ب لنك مايكروتك nray».
/// LHG 60G ‏(MASTER/SLAVE_ZAA3) وnRAY 60G ‏(MASTER/SLAVE_CENTER KNKLY) طريقهما الـAPI ‏8728: الإشارة −56 والجودة 80٪ والتردّد
/// ظهرت، و«سرعة الربط —» والمسافة غائبة. السبب: الـAPI والـREST يُرجعان `tx-phy-rate` و`distance` رقماً مجرّداً (نوعهما num في
/// مرجع RouterOS ‏7.26، كـrx-bits-per-second) والمحلّل كان يشترط الوحدة التي تكتبها الطرفيّة وحدها («2.3Gbps» · «160.9m»).
class _Scripted implements RouterOsChannel {
  _Scripted(this.replies);
  final Map<String, Object> replies;
  final asked = <String>[];
  @override
  String get via => 'API';
  @override
  Future<void> open() async {}
  @override
  Future<List<Map<String, String>>> query(List<String> words, {bool debugLog = false}) async {
    asked.add(words.first);
    final r = replies[words.first];
    // كالجهاز: أمرٌ لا حزمة له ⇒ «no such command» (لا فشل)
    if (r == null) throw MikrotikBinaryException('no such command prefix');
    return [for (final m in r as List) Map<String, String>.from(m as Map)];
  }

  @override
  Future<void> close() async {}
}

/// ردّ monitor عبر الـAPI كما يصفه مرجع 7.26: أرقامٌ مجرّدة — السرعة بالـbps والمسافة بالسنتيمتر (481 م).
const _apiMonitor = <String, String>{
  'connected': 'true',
  'frequency': '60480',
  'remote-address': 'F4:1E:57:36:0E:AC',
  'tx-mcs': '8',
  'tx-phy-rate': '2310000000',
  'signal': '80',
  'rssi': '-56',
  'tx-sector': '28',
  'tx-sector-info': 'center',
  'distance': '48100',
  'tx-packet-error-rate': '1',
};

/// لنك 60 كاملٌ عبر الـAPI (اللوح والواجهات والـw60g) — [mode] طرفا الوصلة: master ‏bridge/ap-bridge، slave ‏station-bridge.
Map<String, Object> _link60({String board = 'LHG 60G', String mode = 'station-bridge', Map<String, String> monitor = _apiMonitor}) => {
      '/system/resource/print': [
        {'board-name': board, 'version': '7.15.3 (stable)', 'cpu-load': '3', 'total-memory': '268435456', 'free-memory': '201326592', 'uptime': '13w2d4h5m6s'}
      ],
      '/interface/print': [
        {'name': 'ether1', 'type': 'ether', 'running': 'true', 'disabled': 'false', 'rx-byte': '1000', 'tx-byte': '2000'},
        {'name': 'wlan60-1', 'type': 'w60g', 'running': 'true', 'disabled': 'false', 'rx-byte': '5000', 'tx-byte': '6000'},
      ],
      '/system/health/print': const <Map<String, String>>[],
      '/ppp/active/print': const <Map<String, String>>[],
      '/interface/ethernet/monitor': [
        {'name': 'ether1', 'rate': '1Gbps'}
      ],
      '/interface/w60g/print': [
        {'name': 'wlan60-1', 'mode': mode, 'ssid': 'ZAA3', 'frequency': 'auto', 'disabled': 'false', 'running': 'true'}
      ],
      '/interface/w60g/station/print': const <Map<String, String>>[],
      '/interface/w60g/monitor': [monitor],
      '/ip/dhcp-server/lease/print': const <Map<String, String>>[],
      '/ip/arp/print': const <Map<String, String>>[],
    };

NetworkDevice _dev(String model) => NetworkDevice(
      id: 8227,
      adminId: '1',
      name: 'MASTER_ZAA3',
      type: 'link',
      brand: 'mikrotik',
      model: model,
      ip: '10.50.53.2',
      port: 8728,
      protocol: 'api',
      hasCredentials: true,
      lastStatus: 'online',
      lastResponseMs: 75,
      createdAt: DateTime(2026, 11, 10),
    );

void main() {
  tearDown(() {
    MikrotikApi.resetRoutesForTest();
    MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => throw UnimplementedError(route);
    MikrotikApi.portProbe = (ip, port) async => false;
  });

  Future<MikrotikStats> read(Map<String, Object> replies) {
    MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => _Scripted(replies);
    MikrotikApi.portProbe = (ip, port) async => false;
    return MikrotikApi.fetchStatsFor(ip: '127.0.0.1', protocol: 'api', apiPort: 8728, creds: {'user': 'admin', 'pass': 'pw'});
  }

  group('سرعة الربط: الرقم المجرّد تُعرف وحدته من مقداره', () {
    test('🚨 الـAPI/REST: bps ‏(2310000000) ⇒ 2310 Mbps — كان null فتظهر «سرعة الربط —»', () {
      expect(MikrotikW60gLink.rateMbps('2310000000'), 2310);
      expect(MikrotikW60gLink.rateMbps('1540000000'), 1540);
      expect(MikrotikW60gLink.rateMbps('385000000'), 385, reason: 'MCS1');
      expect(MikrotikW60gLink.rateMbps('27500000'), 28, reason: 'MCS0 ‏27.5 — أدنى سرعة 802.11ad');
      expect(MikrotikW60gLink.rateMbps('4620000000'), 4620, reason: 'MCS12');
      expect(MikrotikW60gLink.rateMbps('8400000000'), 8400, reason: '802.11ay ‏(nRAY edmg)');
    });

    test('kbps وMbps المجرّدان يُعرفان أيضاً (مجالاتٌ لا تتداخل)', () {
      expect(MikrotikW60gLink.rateMbps('2310000'), 2310, reason: 'kbps');
      expect(MikrotikW60gLink.rateMbps('27500'), 28, reason: 'kbps — أدنى سرعة');
      expect(MikrotikW60gLink.rateMbps('2310'), 2310, reason: 'Mbps كـSNMP');
      expect(MikrotikW60gLink.rateMbps('1540.0'), 1540);
      expect(MikrotikW60gLink.rateMbps(' 2310000000 '), 2310, reason: 'مسافاتٌ حولها');
    });

    test('الطرفيّة (SSH) بوحدتها كما كانت', () {
      expect(MikrotikW60gLink.rateMbps('2.3Gbps'), 2300);
      expect(MikrotikW60gLink.rateMbps('1540.0Mbps'), 1540);
      expect(MikrotikW60gLink.rateMbps('1540.0 Mbps'), 1540);
      expect(MikrotikW60gLink.rateMbps('962000kbps'), 962);
      expect(MikrotikW60gLink.rateMbps('2310000000bps'), 2310);
    });

    test('قيمةٌ متعدّدة (محطّاتٌ على الواجهة) ⇒ الأولى', () {
      expect(MikrotikW60gLink.rateMbps('2310000000,1540000000'), 2310);
      expect(MikrotikW60gLink.rateMbps('2.3Gbps,1540.0Mbps'), 2300);
    });

    test('لا رقم كاذب: الصفر والفارغ والنصّ والسالب وما يخرج عن أيّ سرعة ⇒ null', () {
      for (final raw in [null, '', '0', '0bps', '0.0Mbps', 'auto', '-5', '0=2310000000', '1e9', '0.5']) {
        expect(MikrotikW60gLink.rateMbps(raw), isNull, reason: '«$raw»');
      }
      expect(MikrotikW60gLink.rateMbps('999999999999999'), isNull, reason: 'فوق 100 Gbps');
    });
  });

  group('المسافة: المجرّد بالسنتيمتر، والكسر العشريّ أمتار', () {
    test('🚨 الـAPI/REST: 48100 ⇒ 481 م (كانت غائبة)', () {
      expect(MikrotikW60gLink.monitorMeters('48100'), 481.0);
      expect(MikrotikW60gLink.monitorMeters('16090'), 160.9, reason: 'الطرفيّة «160.9m»');
      expect(MikrotikW60gLink.monitorMeters('22088'), 220.88, reason: 'الطرفيّة «220.88m» بمنزلتين = سنتيمتر');
      expect(MikrotikW60gLink.monitorMeters('386'), 3.86, reason: 'وصلة طاولة «3.86m»');
      expect(MikrotikW60gLink.monitorMeters('150000'), 1500.0, reason: '1.5 كم — أبعد LHG 60G');
    });

    test('الكسر بلا وحدة أمتار (السنتيمتر لا كسر له)، والوحدة كما كانت', () {
      expect(MikrotikW60gLink.monitorMeters('160.9'), 160.9);
      expect(MikrotikW60gLink.monitorMeters('160.9m'), 160.9);
      expect(MikrotikW60gLink.monitorMeters('3.65m'), 3.65);
      expect(MikrotikW60gLink.monitorMeters('1.2km'), 1200.0);
      expect(MikrotikW60gLink.monitorMeters('48100,22088'), 481.0, reason: 'متعدّدة ⇒ الأولى');
    });

    test('لا رقم كاذب: الصفر والفارغ والنصّ وما فوق 20 كم ⇒ null', () {
      for (final raw in [null, '', '0', '0m', 'auto', '-100', '0=48100']) {
        expect(MikrotikW60gLink.monitorMeters(raw), isNull, reason: '«$raw»');
      }
      expect(MikrotikW60gLink.monitorMeters('2500000'), isNull, reason: '25 كم — لا وصلة 60 بهذا الطول');
      expect(MikrotikW60gLink.monitorMeters('30km'), isNull);
    });

    test('meters (جدول التسجيل) لم يتغيّر: بوحدته وحدها', () {
      expect(MikrotikW60gLink.meters('1.2km'), 1200.0);
      expect(MikrotikW60gLink.meters('48100'), isNull, reason: 'وحدة المجرّد معروفة في monitor وحده');
    });
  });

  group('fromMonitor بالأشكال الثلاثة', () {
    test('🚨 الـAPI ‏(7.x): tx-mcs/tx-phy-rate/distance أرقامٌ مجرّدة', () {
      final l = MikrotikW60gLink.fromMonitor('wlan60-1', _apiMonitor);
      expect(l.connected, isTrue);
      expect(l.phyRateMbps, 2310);
      expect(l.distanceMeters, 481.0);
      expect(l.mcs, 8);
      expect(l.rssi, -56);
      expect(l.signalPercent, 80);
      expect(l.frequency, 60480);
      expect(l.remoteMac, 'F4:1E:57:36:0E:AC');
      expect(l.packetErrorRate, 1);
      expect(MikrotikW60gLink.rateText(l.phyRateMbps!), '2.31 Gbps');
      expect(MikrotikW60gLink.distanceText(l.distanceMeters!), '481 m');
    });

    test('الشكل المنسَّق (الطرفيّة، أو إصدارٌ يُرجعه هكذا) والأسماء القديمة mcs/phy-rate', () {
      final l = MikrotikW60gLink.fromMonitor('wlan60-1', const {
        'connected': 'yes',
        'mcs': '6',
        'phy-rate': '1540.0Mbps',
        'rssi': '-62',
        'signal': '70',
        'distance': '220.88m',
      });
      expect(l.phyRateMbps, 1540);
      expect(l.mcs, 6);
      expect(l.distanceMeters, 220.88);
    });

    test('غير متّصل ⇒ لا سرعة ولا مسافة (بقايا آخر اتّصال)', () {
      final l = MikrotikW60gLink.fromMonitor('wlan60-1', {..._apiMonitor, 'connected': 'false'});
      expect(l.connected, isFalse);
      expect(l.phyRateMbps, isNull);
      expect(l.distanceMeters, isNull);
      expect(l.rssi, isNull);
    });
  });

  group('من ردّ الجهاز إلى البطاقة (طريق الـAPI ‏8728 كأجهزة المالك)', () {
    test('🚨 LHG 60G slave: الوصلة بسرعتها ومسافتها في الخانات والتفصيل', () async {
      final s = await read(_link60());
      expect(s.via, 'API');
      final l = s.w60gLinks.single;
      expect(l.phyRateMbps, 2310);
      expect(l.distanceMeters, 481.0);

      final r = DeviceVitals.mikrotikResult(_dev('LHG 60G'), s, null, detailed: true);
      final g = r.detail.glance;
      expect(g.txRateMbps, 2310, reason: 'سرعة الربط باتّجاه الإرسال (monitor)');
      expect(g.rxRateMbps, isNull, reason: 'لا رقم للاستقبال — لا نسخه');
      expect(g.distanceM, 481);
      expect(g.signal, -56);
      expect(g.signalPct, 80);
      expect(g.freqMhz, 60480);
      expect(r.detail.link, containsAll([(k: 'سرعة الربط', v: '2.31 Gbps'), (k: 'المسافة', v: '481 m'), (k: 'MCS', v: '8')]));
      expect(r.detail.peers.single.txRate, 2310, reason: 'الطرف الآخر بسرعته (الترابط ولوحة الجهاز)');
    });

    test('🚨 nRAY master ‏(bridge): السرعة نفسها', () async {
      final s = await read(_link60(board: 'nRAY 60G', mode: 'bridge'));
      final g = DeviceVitals.mikrotikResult(_dev('nRAY 60G'), s, null, detailed: true).detail.glance;
      expect(g.txRateMbps, 2310);
      expect(g.distanceM, 481);
    });

    group('البطاقة الكبيرة', () {
      setUpAll(loadAppFonts);
      tearDown(() => AppColors.setDarkMode(false));

      Future<void> pump(WidgetTester t, VitalsState st, NetworkDevice d, {double width = 390, bool dark = false}) async {
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
                child: DeviceBigCard(device: d, state: st, medianMs: 12, now: DateTime(2026, 11, 16, 5), rows: 4),
              ),
            ),
          ),
        ));
        await t.pump();
      }

      testWidgets('🚨 «سرعة الربط 2310 Mbps» و«المسافة 481 م» بدل «—» — على 320 و390 و480، فاتحاً وداكناً، بلا فيضان', (t) async {
        final d = _dev('LHG 60G');
        final s = await t.runAsync(() => read(_link60()));
        final r = DeviceVitals.mikrotikResult(d, s!, null, detailed: true);
        final st = VitalsState(vitals: r.vitals, detail: r.detail, at: DateTime(2026, 11, 16, 5));
        for (final width in [320.0, 390.0, 480.0]) {
          for (final dark in [false, true]) {
            await pump(t, st, d, width: width, dark: dark);
            expect(t.takeException(), isNull, reason: 'فيضان على $width ${dark ? 'داكن' : 'فاتح'}');
            expect(find.textContaining('سرعة الربط', findRichText: true), findsWidgets);
            expect(find.textContaining('2310', findRichText: true), findsWidgets, reason: 'رقم السرعة على $width');
            expect(find.textContaining('481', findRichText: true), findsWidgets, reason: 'المسافة على $width');
          }
        }
      });
    });
  });
}
