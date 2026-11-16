// جهاز المشترك من ميكروتك (١٦ نوفمبر — المالك: «اكو مشتركين عدهم نانوات نوع مايكروتك… لازم نضمنها ونضيفلها اعتمادات… وكذلك
// راوترات مايكروتك»): التحليل الخالص، ثمّ القارئ على جهاز RouterOS وهميّ (API ثنائيّ حقيقيّ على loopback)، ثمّ الفحص الكامل عبر
// DeviceProbeApi. الأسماء والماكات وهميّة؛ شكل الردود من الـAPI الرسميّ.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart' show MikrotikW60gLink;
import 'package:rad_mysvcs/api/mikrotik_binary_api.dart';
import 'package:rad_mysvcs/api/routeros_channel.dart';
import 'package:rad_mysvcs/core/net/mikrotik_cpe_service.dart';
import 'package:rad_mysvcs/core/net/router_ops.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_routeros.dart';

/// منفذٌ لا يسمعه أحد (يُحجز ثمّ يُغلق).
Future<int> _closedPort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}

class _FakeApi implements HttpClientAdapter {
  Map<String, Object?> defaults = {};
  Map<String, Object?> device = {};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final Object data = o.uri.path == '/api/admin/device-defaults'
        ? {'success': true, 'defaults': defaults}
        : (o.uri.path.endsWith('/device') ? {'success': true, 'device': device} : {'success': true});
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// قناة طريقٍ لا يُفتح (REST/SSH في الاختبار) — كأنّ المنفذ مقفول.
class _DeadChannel implements RouterOsChannel {
  @override
  String get via => 'x';
  @override
  Future<void> open() async => throw const SocketException('Connection refused');
  @override
  Future<List<Map<String, String>>> query(List<String> words, {bool debugLog = false}) async => const [];
  @override
  Future<void> close() async {}
}

MtCpeRows _rowsOf(FakeRouterOs f, {List<Map<String, String>> wifi = const [], List<Map<String, String>> wifiReg = const []}) {
  Map<String, String>? mon(String k) => f.monitors[k];
  return MtCpeRows(
    resource: f.rows['/system/resource/print']?.first ?? const {},
    identity: f.rows['/system/identity/print']?.first ?? const {},
    ifaces: f.rows['/interface/print'] ?? const [],
    wireless: f.rows['/interface/wireless/print'] ?? const [],
    wirelessReg: f.rows['/interface/wireless/registration-table/print'] ?? const [],
    wifi: wifi,
    wifiReg: wifiReg,
    ether: mon('/interface/ethernet/monitor|ether1') == null ? null : {...mon('/interface/ethernet/monitor|ether1')!},
    pppoe: mon('/interface/pppoe-client/monitor|pppoe-out1'),
    leases: f.rows['/ip/dhcp-server/lease/print'] ?? const [],
  );
}

void main() {
  group('التحليل (صرف)', () {
    test('نانو SXT بوضع station-bridge: الإشارة والضجيج (إشارة − SNR) وCCQ وسرعتا الربط والمسافة والكيبل وPPPoE', () {
      final f = FakeRouterOs()..sxtNano();
      final u = MikrotikCpeParse.status(host: '10.0.0.5', rows: _rowsOf(f));
      expect(u.vendor, 'mikrotik');
      expect(u.isMikrotik, isTrue);
      expect(u.isRouter, isFalse);
      expect(u.hostname, 'Ali-Home-SXT');
      expect(u.model, 'SXT Lite5');
      expect(u.firmware, 'RouterOS 6.48.6');
      expect(u.uptimeSeconds, 2 * 604800 + 3 * 86400 + 4 * 3600 + 5 * 60 + 6);
      expect(u.ssid, 'Tower-North');
      expect(u.mode, 'sta');
      expect(u.signalDbm, -63);
      expect(u.noiseFloorDbm, -63 - 38);
      expect(u.ccqPercent, 91, reason: 'tx-ccq أوّلاً كقسم الأجهزة');
      expect([u.txRateKbps, u.rxRateKbps], [130000, 117000]);
      expect(u.distanceMeters, 1200);
      expect(u.peerMac, '4C:5E:0C:11:22:33');
      expect(u.peerCount, 1);
      expect(u.lanPorts.single.speed, '100Mbps-Full');
      expect(u.lanHealth, 'good');
      expect(u.wanType, 'PPPoE');
      expect(u.wanOnlineSeconds, 5 * 3600 + 6 * 60 + 7);
    });

    test('نانو غير متّصل: لا إشارة ولا CCQ (لا أرقام مخترعة)، وكيبل غير موصول «Unplugged»', () {
      final f = FakeRouterOs()..sxtNano(connected: false);
      f.monitors['/interface/ethernet/monitor|ether1'] = {'name': 'ether1', 'status': 'no-link', 'rate': '', 'full-duplex': 'false'};
      final u = MikrotikCpeParse.status(host: 'h', rows: _rowsOf(f));
      expect([u.signalDbm, u.noiseFloorDbm, u.ccqPercent, u.txRateKbps], [null, null, null, null]);
      expect(u.peerCount, 0);
      expect(u.lanPorts.single.plugged, isFalse);
      expect(u.lanPorts.single.speed, isNull);
      expect(u.lanHealth, 'bad');
    });

    test('LHG 60G (w60g station): الإشارة من rssi، لا CCQ (الجودة ٪ ليست CCQ)، والسرعة والمسافة من monitor', () {
      final link = MikrotikW60gLink.fromMonitor('wlan60-1', {
        'connected': 'true',
        'rssi': '-58',
        'signal': '80',
        'phy-rate': '2.3Gbps',
        'distance': '481m',
        'frequency': '62640',
        'remote-address': '64:D1:54:00:00:01',
      });
      final u = MikrotikCpeParse.status(
        host: 'h',
        rows: MtCpeRows(
          resource: const {'board-name': 'LHG 60G', 'version': '6.49.10 (long-term)'},
          ifaces: const [
            {'name': 'ether1', 'type': 'ether'},
            {'name': 'wlan60-1', 'type': 'w60g'},
          ],
          w60g: [link],
          w60gRows: const [
            {'name': 'wlan60-1', 'mode': 'station-bridge'},
          ],
        ),
      );
      expect(u.vendor, 'mikrotik');
      expect(u.signalDbm, -58);
      expect(u.ccqPercent, isNull);
      expect(u.txRateKbps, 2300 * 1000);
      expect(u.distanceMeters, 481);
      expect(u.peerMac, '64:D1:54:00:00:01');
    });

    test('Cube 60Pro (٦٠ + راديو ٥ احتياطيّ station): وصلة الـ٦٠ هي الوصلة لا الاحتياطيّ', () {
      final f = FakeRouterOs()..sxtNano(signal: -84, snr: 12);
      final rows = _rowsOf(f);
      final link = MikrotikW60gLink.fromMonitor('wlan60-1', {'connected': 'true', 'rssi': '-55', 'phy-rate': '1540.0Mbps'});
      final u = MikrotikCpeParse.status(
        host: 'h',
        rows: MtCpeRows(
          resource: rows.resource,
          identity: rows.identity,
          ifaces: [
            ...rows.ifaces,
            {'name': 'wlan60-1', 'type': 'w60g'},
          ],
          wireless: rows.wireless,
          wirelessReg: rows.wirelessReg,
          w60g: [link],
          w60gRows: const [
            {'name': 'wlan60-1', 'mode': 'station-bridge'},
          ],
          ether: rows.ether,
        ),
      );
      expect(u.signalDbm, -55, reason: 'الاحتياطيّ ٥ إشارته ‎-84 — لا تُعرض إشارةً للوصلة');
      expect(u.txRateKbps, 1540 * 1000);
    });

    test('RouterOS 7 (wifi): وضع station من configuration.mode، والإشارة من `signal` بجدول تسجيله', () {
      final u = MikrotikCpeParse.status(
        host: 'h',
        rows: const MtCpeRows(
          resource: {'board-name': 'LHG XL 5 ax', 'version': '7.15.3 (stable)'},
          ifaces: [
            {'name': 'ether1', 'type': 'ether'},
            {'name': 'wifi1', 'type': 'wifi'},
          ],
          wifi: [
            {'name': 'wifi1', 'configuration.mode': 'station-bridge', 'configuration.ssid': 'North-AX', 'disabled': 'false'},
          ],
          wifiReg: [
            {'interface': 'wifi1', 'mac-address': 'D4:01:C3:00:00:09', 'signal': '-61', 'tx-rate': '573.5Mbps', 'rx-rate': '480Mbps'},
          ],
        ),
      );
      expect(u.vendor, 'mikrotik');
      expect(u.ssid, 'North-AX');
      expect(u.signalDbm, -61);
      expect(u.ccqPercent, isNull, reason: 'حزمة wifi لا CCQ فيها');
      expect(u.txRateKbps, 573000);
    });

    test('راوتر hAP: المتّصلون الآن من جدول التسجيل (بأسماء الإيجارات)، DHCP المربوطة، PPPoE، وسرعة منفذ الإنترنت', () {
      final f = FakeRouterOs()..hapRouter();
      final u = MikrotikCpeParse.status(host: 'h', rows: _rowsOf(f));
      expect(u.vendor, 'mtrouter');
      expect(u.isRouter, isTrue);
      expect(u.isMikrotik, isTrue);
      expect(u.peerCount, 3);
      expect([for (final c in u.clients) c.name], ['phone-1', 'phone-2', 'phone-3']);
      expect(u.clients.first.ip, '192.168.88.11');
      expect(u.dhcpCount, 4, reason: 'المربوطة وحدها');
      expect(u.wanType, 'PPPoE');
      expect(u.wanOnlineSeconds, 86400 + 3600);
      expect(u.wanLinkMbps, 1000);
      expect(u.signalDbm, isNull);
      expect(u.lanHealth, 'unknown', reason: 'الراوتر لا يُحكم كيبله');
    });

    test('راوتر بلا وايرلس (hEX): «المتّصلون الآن» مجهول لا صفر، وDHCP من عميله', () {
      final u = MikrotikCpeParse.status(
        host: 'h',
        rows: const MtCpeRows(
          resource: {'board-name': 'hEX', 'version': '7.12'},
          ifaces: [
            {'name': 'ether1', 'type': 'ether'},
            {'name': 'ether2', 'type': 'ether'},
          ],
          ether: {'name': 'ether1', 'status': 'link-ok', 'rate': '100Mbps', 'full-duplex': 'true'},
          leases: [
            {'mac-address': 'AA:00:00:00:00:01', 'status': 'bound'},
          ],
          dhcpClient: [
            {'interface': 'ether1', 'status': 'bound'},
          ],
        ),
      );
      expect(u.vendor, 'mtrouter');
      expect(u.peerCount, isNull);
      expect(u.dhcpCount, 1);
      expect(u.wanType, 'DHCP');
      expect(u.wanLinkMbps, 100);
    });

    test('المساعدات: سرعة المنفذ، والبرنامج، ونقطة النبضة الحيّة', () {
      expect([MikrotikCpeParse.linkMbps('100Mbps'), MikrotikCpeParse.linkMbps('1Gbps'), MikrotikCpeParse.linkMbps('2.5Gbps')],
          [100, 1000, 2500]);
      expect(MikrotikCpeParse.linkMbps(''), isNull);
      expect(MikrotikCpeParse.firmware('7.12.1 (stable)'), 'RouterOS 7.12.1');
      expect(MikrotikCpeParse.firmware(''), '');
      final f = FakeRouterOs()..sxtNano();
      final nano = MikrotikCpeParse.liveTarget(ifaces: f.rows['/interface/print']!, wireless: f.rows['/interface/wireless/print']!)!;
      expect([nano.iface, nano.pppoe, nano.station], ['wlan1', 'pppoe-out1', true]);
      final r = FakeRouterOs()..hapRouter();
      final router = MikrotikCpeParse.liveTarget(ifaces: r.rows['/interface/print']!, wireless: r.rows['/interface/wireless/print']!)!;
      expect([router.iface, router.station], ['pppoe-out1', false]);
      expect(MikrotikCpeService.hostOf('10.1.2.3:8080'), '10.1.2.3');
    });
  });

  group('القارئ على جهاز RouterOS وهميّ', () {
    late FakeRouterOs d;
    late int closed;

    setUp(() async {
      MikrotikCpeService.reset();
      MikrotikBinaryClient.trapDoneWait = const Duration(milliseconds: 300);
      d = FakeRouterOs()..sxtNano();
      final port = await d.start();
      closed = await _closedPort();
      MikrotikCpeService.apiPortOf = (_) => port;
      MikrotikCpeService.winboxPortOf = (_) => closed;
      MikrotikCpeService.detectTimeout = const Duration(milliseconds: 600);
      // REST وSSH «مقفولان» في الاختبار — لا شبكة حقيقيّة
      MikrotikCpeService.channelFactory = (host, route, user, pass) => route == MtRoute.api
          ? BinaryRouterOsChannel(MikrotikBinaryClient(host: host, port: port, user: user, pass: pass, timeout: const Duration(seconds: 3)))
          : _DeadChannel();
    });
    tearDown(() async {
      await d.stop();
      MikrotikCpeService.reset();
      MikrotikBinaryClient.trapDoneWait = const Duration(seconds: 2);
    });

    test('التعرّف: منفذ الـAPI مفتوح ⇒ ميكروتك، والمنفذان مقفولان ⇒ لا — بلا إرسال شيء', () async {
      expect(await MikrotikCpeService.detect('127.0.0.1'), isTrue);
      expect(d.logins + d.failedLogins, 0, reason: 'التعرّف اتّصالٌ يُغلق — لا دخول');
      MikrotikCpeService.apiPortOf = (_) => closed;
      expect(await MikrotikCpeService.detect('127.0.0.1'), isFalse);
    });

    test('قراءة نانو: دخولٌ واحد، أوامر قراءة وحدها (لا كتابة ولا pppoe-client print)، والاتّصال يُغلق', () async {
      final u = await MikrotikCpeService.readOnce('127.0.0.1', 'admin', 'mt-pass');
      expect(u, isNotNull);
      expect(u!.signalDbm, -63);
      expect(u.wanOnlineSeconds, isNotNull);
      expect(d.logins, 1);
      expect(d.forbidden, isEmpty, reason: '${d.asked}');
      expect(d.asked, isNot(contains('/interface/pppoe-client/print')));
      expect(d.asked, contains('/interface/pppoe-client/monitor'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(d.open, 0, reason: 'الجلسة تُغلق بعد القراءة');
      expect(MikrotikCpeService.lastIssue('127.0.0.1'), isNull);
    });

    test('🚨 رفض الاعتماد: لا يُعاد الزوج نفسه تلقائيّاً (قواعد الحظر)، و«حفظ وفحص» يعيده مرّة', () async {
      expect(await MikrotikCpeService.readOnce('127.0.0.1', 'admin', 'wrong'), isNull);
      expect(MikrotikCpeService.lastIssue('127.0.0.1')?.issue, MtCpeIssue.rejected);
      expect(d.failedLogins, 1);
      expect(await MikrotikCpeService.readOnce('127.0.0.1', 'admin', 'wrong'), isNull);
      expect(d.failedLogins, 1, reason: 'المرفوض محفوظ — لا دخول غلطٌ ثانٍ');
      // زوجٌ آخر يُجرَّب عادةً
      expect(await MikrotikCpeService.readOnce('127.0.0.1', 'admin', 'mt-pass'), isNotNull);
      MikrotikCpeService.forget('127.0.0.1');
      expect(await MikrotikCpeService.readOnce('127.0.0.1', 'admin', 'wrong'), isNull);
      expect(d.failedLogins, 2, reason: 'بعد «حفظ وفحص» يُعاد مرّة');
    });

    test('RouterOS قبل 6.43 (دخول التحدّي): يدخل ويقرأ — كان «دخولاً» ثمّ يُرفض كلّ أمر', () async {
      d.legacyLogin = true;
      final u = await MikrotikCpeService.readOnce('127.0.0.1', 'admin', 'mt-pass');
      expect(u, isNotNull);
      expect(d.logins, 1);
      expect(MikrotikBinaryClient.challengeResponse('x', List.filled(16, 0)), hasLength(34));
      d.legacyLogin = true;
      expect(await MikrotikCpeService.readOnce('127.0.0.1', 'admin', 'bad'), isNull);
      expect(MikrotikCpeService.lastIssue('127.0.0.1')?.issue, MtCpeIssue.rejected);
    });

    test('الـAPI مقفول وWinbox مفتوح ⇒ «الخدمة مقفولة» لا «لا يجاوب»؛ وكلّه مقفول ⇒ لا يجاوب', () async {
      final winbox = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      winbox.listen((s) => s.destroy());
      addTearDown(winbox.close);
      MikrotikCpeService.apiPortOf = (_) => closed;
      MikrotikCpeService.winboxPortOf = (_) => winbox.port;
      MikrotikCpeService.channelFactory = (host, route, user, pass) => _DeadChannel();
      expect(await MikrotikCpeService.detect('127.0.0.1'), isTrue);
      expect(await MikrotikCpeService.readOnce('127.0.0.1', 'admin', 'mt-pass'), isNull);
      expect(MikrotikCpeService.lastIssue('127.0.0.1')?.issue, MtCpeIssue.apiClosed);
      MikrotikCpeService.winboxPortOf = (_) => closed;
      MikrotikCpeService.forget('127.0.0.1');
      expect(await MikrotikCpeService.readOnce('127.0.0.1', 'admin', 'mt-pass'), isNull);
      expect(MikrotikCpeService.lastIssue('127.0.0.1')?.issue, MtCpeIssue.unreachable);
    });

    test('النبضة الحيّة للنانو: معدّلٌ جاهز من monitor-traffic على راديو المحطّة، والإشارة كلّ رابعة — بجلسةٍ واحدة', () async {
      final live = await RouterOps.openLive('mikrotik', '127.0.0.1', 'admin', 'mt-pass');
      expect(live, isNotNull);
      final s1 = (await live!.sample())!;
      expect([s1.downBps, s1.upBps], [23400000, 1850000]);
      expect(s1.signalDbm, -63);
      expect(s1.ccq, 91);
      expect(s1.wanOnlineSeconds, isNotNull);
      expect(s1.clients, isNull, reason: 'النانو لا «متّصلين»');
      final s2 = (await live.sample())!;
      expect(s2.signalDbm, isNull, reason: 'الإشارة كلّ رابعة — لا ثلاثة أوامر كلّ ثانيتين');
      expect(d.logins, 1, reason: 'جلسةٌ واحدة للنبضات كلّها');
      expect(d.forbidden, isEmpty);
      await live.close();
    });

    test('النبضة الحيّة للراوتر: ترافيك PPPoE والمتّصلون الآن', () async {
      final r = FakeRouterOs()..hapRouter();
      final port = await r.start();
      addTearDown(r.stop);
      MikrotikCpeService.channelFactory = (host, route, user, pass) => route == MtRoute.api
          ? BinaryRouterOsChannel(MikrotikBinaryClient(host: host, port: port, user: user, pass: pass, timeout: const Duration(seconds: 3)))
          : _DeadChannel();
      final live = (await RouterOps.openLive('mtrouter', '127.0.0.1', 'admin', 'mt-pass'))!;
      final s = (await live.sample())!;
      expect([s.downBps, s.upBps], [51000000, 4100000]);
      expect(s.clients, hasLength(3));
      expect(s.signalDbm, isNull);
      await live.close();
    });

    test('RouterOps: ميكروتك له نبضةٌ حيّة ولا واي فاي ولا إقلاع', () {
      for (final v in ['mikrotik', 'mtrouter']) {
        expect(RouterOps.hasLive(v), isTrue);
        expect(RouterOps.canWifi(v), isFalse);
        expect(RouterOps.canReboot(v), isFalse);
      }
    });
  });

  group('فحص جهاز المشترك (DeviceProbeApi)', () {
    late FakeRouterOs d;
    late _FakeApi api;
    late int closed;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DeviceProbeApi.clearAllCaches();
      MikrotikCpeService.reset();
      MikrotikBinaryClient.trapDoneWait = const Duration(milliseconds: 300);
      d = FakeRouterOs()..sxtNano();
      final port = await d.start();
      closed = await _closedPort();
      MikrotikCpeService.apiPortOf = (_) => port;
      MikrotikCpeService.winboxPortOf = (_) => closed;
      MikrotikCpeService.detectTimeout = const Duration(milliseconds: 600);
      MikrotikCpeService.channelFactory = (host, route, user, pass) => route == MtRoute.api
          ? BinaryRouterOsChannel(MikrotikBinaryClient(host: host, port: port, user: user, pass: pass, timeout: const Duration(seconds: 3)))
          : _DeadChannel();
      api = _FakeApi()
        ..defaults = {
          'mikrotikUsername': 'admin',
          'mikrotikPassword': 'mt-pass',
        };
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
    });
    tearDown(() async {
      await d.stop();
      MikrotikCpeService.reset();
      MikrotikBinaryClient.trapDoneWait = const Duration(seconds: 2);
      DeviceProbeApi.debugOnHuaweiProbe = null;
    });

    test('أوّل فحص: التعرّف يحسم ميكروتك ⇒ يُقرأ باعتماده — بلا دخول هواوي عليه، والنبضة تجد الفائز', () async {
      final huaweiHits = <String>[];
      DeviceProbeApi.debugOnHuaweiProbe = huaweiHits.add;
      // 🐛 بلا منفذ في العنوان يمرّ فحص «نانو على https؟» الحقيقيّ ([_airOsHttps]) — كان يعلق للأبد (قفلٌ ذاتيّ) فيقف كلّ أوّل
      // فحصٍ لراوتر عند سقف ١٥ث. لا حقن هنا عمداً.
      final sw = Stopwatch()..start();
      final snap = await DeviceProbeApi.probe(fallbackIp: '127.0.0.1', force: true);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)), reason: 'أوّل فحصٍ لا يعلق على فحص airOS');
      expect(snap, isNotNull);
      expect(snap!.kind, DeviceKind.ubiquiti);
      expect(snap.ubnt!.vendor, 'mikrotik');
      expect(snap.ubnt!.signalDbm, -63);
      expect(huaweiHits, isEmpty, reason: 'لا دخول هواوي على RouterOS');
      expect(DeviceProbeApi.issueFor(ip: '127.0.0.1'), isNull);
      final creds = await DeviceProbeApi.resolveTplinkCreds(fallbackIp: '127.0.0.1');
      expect([creds?.user, creds?.pass], ['admin', 'mt-pass'], reason: 'النبضة الحيّة باعتماد ميكروتك الفائز');
      expect(d.forbidden, isEmpty);
    });

    test('بلا اعتماد ميكروتك ⇒ «يحتاج يوزر وباسورده» باسم ميكروتك — ولا يُجرَّب عليه اعتماد يوبيكويتي/TP-Link', () async {
      api.defaults = {
        'ubntUsername': 'ubnt',
        'ubntPassword': 'ubnt-pass',
        'tplinkUsername': 'admin',
        'tplinkPassword': 'tp-pass',
      };
      DeviceProbeApi.invalidateAdminDefaults();
      expect(await DeviceProbeApi.probe(fallbackIp: '127.0.0.1', force: true), isNull);
      final why = DeviceProbeApi.issueFor(ip: '127.0.0.1');
      expect(why?.issue, ProbeIssue.needsCredentials);
      expect(why?.vendor, 'mikrotik');
      expect(d.logins + d.failedLogins, 0, reason: 'لا افتراض ولا اعتماد علامةٍ أخرى');
    });

    test('🚨 رفضٌ ⇒ «رفض اليوزر أو الباسورد» باسم ميكروتك، ولا يُعاد في الموجة التالية، و«حفظ وفحص» يعيده', () async {
      api.defaults = {'mikrotikUsername': 'admin', 'mikrotikPassword': 'wrong'};
      DeviceProbeApi.invalidateAdminDefaults();
      expect(await DeviceProbeApi.probe(fallbackIp: '127.0.0.1', force: true), isNull);
      final why = DeviceProbeApi.issueFor(ip: '127.0.0.1');
      expect([why?.issue, why?.vendor], [ProbeIssue.loginRejected, 'mikrotik']);
      expect(d.failedLogins, 1);
      expect(await DeviceProbeApi.probe(fallbackIp: '127.0.0.1', force: true), isNull);
      expect(d.failedLogins, 1, reason: 'المرفوض لا يُعاد');
      expect(await DeviceProbeApi.probe(fallbackIp: '127.0.0.1', force: true, retryLogin: true), isNull);
      expect(d.failedLogins, 2);
    });

    test('الاعتماد الثاني يُجرَّب بعد رفض الأوّل ويُحفظ فائزاً للعنوان', () async {
      api.defaults = {
        'mikrotikUsername': 'admin',
        'mikrotikPassword': 'old',
        'mikrotikExtra': [
          {'username': 'admin', 'password': 'mt-pass'},
        ],
      };
      DeviceProbeApi.invalidateAdminDefaults();
      final snap = await DeviceProbeApi.probe(fallbackIp: '127.0.0.1', force: true);
      expect(snap?.ubnt?.vendor, 'mikrotik');
      expect(d.failedLogins, 1);
      final again = await DeviceProbeApi.probe(fallbackIp: '127.0.0.1', force: true);
      expect(again, isNotNull);
      expect(d.failedLogins, 1, reason: 'الفائز أوّلاً — لا رفضٌ ثانٍ');
    });

    test('اعتماد المشترك («تلقائي») يُستعمل لميكروتك وحده بدل قائمة المدير', () async {
      api.device = {'username': 'admin', 'password': 'mt-pass'};
      api.defaults = {'mikrotikUsername': 'admin', 'mikrotikPassword': 'wrong'};
      DeviceProbeApi.invalidateAdminDefaults();
      final snap = await DeviceProbeApi.probe(fallbackIp: '127.0.0.1', subscriberUsername: 'sub1', force: true);
      expect(snap?.ubnt?.vendor, 'mikrotik');
      expect(d.failedLogins, 0);
    });

    test('المرشّحون: المشترك وحده، وإلّا الأوّل ثمّ الإضافيّان بلا تكرار — ولا افتراض مصنّع', () {
      const defaults = AdminDeviceDefaults(
        mikrotikUsername: 'admin',
        mikrotikPassword: 'a',
        mikrotikExtra: [DeviceCred('admin', 'a'), DeviceCred('noc', 'b')],
      );
      expect(DeviceProbeApi.candidatesFor(null, defaults).mikrotik, const [DeviceCred('admin', 'a'), DeviceCred('noc', 'b')]);
      expect(DeviceProbeApi.candidatesFor(null, AdminDeviceDefaults.empty).mikrotik, isEmpty);
      expect(
        DeviceProbeApi.candidatesFor(const DeviceConfig(username: 'me', password: 'x'), defaults).mikrotik,
        const [DeviceCred('me', 'x')],
      );
      // كلمة سرٍّ فارغة لاعتمادٍ بيوزر (admin بلا كلمة سرّ) تُرسل فارغة
      expect(DeviceProbeApi.candidatesFor(null, const AdminDeviceDefaults(mikrotikUsername: 'admin')).mikrotik,
          const [DeviceCred('admin', '')]);
    });
  });

  group('الاعتمادات (النموذج)', () {
    test('JSON ذهاباً وإياباً، وكلمة السرّ كما هي بلا قصّ', () {
      final d = AdminDeviceDefaults.fromJson({
        'mikrotikUsername': ' admin ',
        'mikrotikPassword': ' p ',
        'mikrotikExtra': [
          {'username': 'noc', 'password': 'q'},
          {'username': '', 'password': 'dropped'},
        ],
      });
      expect(d.mikrotikUsername, 'admin');
      expect(d.mikrotikPassword, ' p ');
      expect(d.mikrotikExtra, const [DeviceCred('noc', 'q')]);
      final j = d.toJson();
      expect(j['mikrotikUsername'], 'admin');
      expect(j['mikrotikExtra'], [
        {'username': 'noc', 'password': 'q'},
      ]);
    });
  });
}
