// «الفحص الشامل» — المراجعة الثانية (٩ نوفمبر، stage2_recheck.json): لا «سليم» كاذب ولا رقمٌ كاذب من قراءةٍ ناقصة.
//   ١ جدول منافذ لم يُقرأ (SNMP ميكروتك وSwOS، سسكو) ⇒ «المنافذ ما انقرت» لا «سويج · سليم» ولا «0/N».
//   ٢ سكتر يوبيكويتي wstalist فشل ⇒ «قائمة مشتركيه ما انقرت» لا «ما عليه أحد الآن».
//   ٣ الوصلة: مقطوعة (محطّة بلا اتّصال، إشارة 0)، طرفها المرسل بلا طرف، 60GHz بلا monitor، وبلا إشارةٍ أصلاً ⇒ ليست «سليم».
//   ٤ «كل الشركات»: قراءة الخادم بعمرها (وملخّص الأولت «حتى 30 د»)، وضوؤه الجزئيّ «الضوء n من N».
//   ٥ قراءة الخادم بقواعد «لم يُقرأ» نفسها (لا «راوتر · سليم» لنقطة وصول، ولا «ما عليه أحد» لجدولٍ فشل).
//   ٦ راديو بحزمةٍ لا يسألها القارئ (wifiwave2، CAPsMAN) ⇒ مجهول لا «راوتر · سليم».
//   ٧ عمر قراءة الخادم بساعةٍ واحدة (هاتفٌ ساعته متأخّرة).
//   ٨ زمن القراءة المعادة من بدئها هي.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';
import 'package:rad_mysvcs/api/mikrotik_snmp.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/api/routeros_channel.dart';
import 'package:rad_mysvcs/api/ruijie_api.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/services/devices_check.dart';
import 'package:rad_mysvcs/services/devices_check_runner.dart';
import 'package:rad_mysvcs/services/merged_devices_check.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_snmp_agent.dart';

NetworkDevice dev(int id,
        {String type = 'router', String brand = 'mikrotik', String protocol = 'api', String ip = '', int? apiPort}) =>
    NetworkDevice(
      id: id,
      adminId: '2',
      name: 'جهاز $id',
      type: type,
      brand: brand,
      ip: ip.isEmpty ? '10.0.0.$id' : ip,
      port: 8728,
      apiPort: apiPort,
      protocol: protocol,
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime(2026, 11, 1),
    );

List<String> texts(DeviceCheckReport r) => [for (final f in r.findings) f.text];

DeviceCheckReport judge(NetworkDevice d, ProbeResult p, {CheckMemo? prev}) =>
    DevicesCheck.evaluate(d: d, alive: true, detail: p.detail, raw: p.raw, prev: prev);

/// وكيل SNMP يُسقط مسوحاً بعينها كما يُسقطها ممرّ الـVPN (٥٠٤ ⇒ مهلة)، ويرفض الأعمدة المتوازية إن طُلب.
class _Lossy extends FakeSnmpAgent {
  _Lossy(super.data, {this.lose = const {}, this.noPaired = false});
  final Set<String> lose;
  final bool noPaired;

  @override
  Future<List<Varbind>> walk(String baseOid, {int chunkSize = 25, int maxIterations = 100}) async {
    if (lose.contains(baseOid)) throw SnmpTimeoutException('SNMP عبر الـVPN: الجهاز ما ردّ');
    return super.walk(baseOid, chunkSize: chunkSize, maxIterations: maxIterations);
  }

  @override
  Future<List<Varbind>> getBulkColumns(List<String> cursors, {int maxRepetitions = 25}) async {
    if (noPaired) throw SnmpTimeoutException('SNMP عبر الـVPN: الجهاز ما ردّ');
    return super.getBulkColumns(cursors, maxRepetitions: maxRepetitions);
  }
}

/// سويج ميكروتك عبر SNMP: [ports] منفذاً، الخمسة الأولى شغّالة.
Map<String, Varbind> _ifTable(String descr, {int ports = 8}) => {
      MikrotikSnmp.sysDescr: snmpText('', descr),
      MikrotikSnmp.sysUpTime: snmpTicks('', 3 * 86400 * 100),
      for (var k = 1; k <= ports; k++) ...{
        '${MikrotikSnmp.ifName}.$k': snmpText('', 'ether$k'),
        '${MikrotikSnmp.ifType}.$k': snmpInt('', 6),
        '${MikrotikSnmp.ifAdmin}.$k': snmpInt('', 1),
        '${MikrotikSnmp.ifOper}.$k': snmpInt('', k <= 5 ? 1 : 2),
        '${MikrotikSnmp.ifHighSpeed}.$k': snmpGauge('', 1000),
      },
    };

/// جهاز RouterOS بالـAPI بردودٍ مكتوبة — الأمر الغائب «no such command» (حزمةٌ غير مثبّتة)، والقيمة Exception تُرمى.
class _Ros implements RouterOsChannel {
  _Ros(this.replies);
  final Map<String, Object> replies;
  @override
  String get via => 'SSH';
  @override
  Future<void> open() async {}
  @override
  Future<List<Map<String, String>>> query(List<String> words, {bool debugLog = false}) async {
    final r = replies[words.first];
    if (r == null) throw MikrotikException('no such command prefix');
    if (r is Exception) throw r;
    return (r as List).cast<Map<String, String>>();
  }

  @override
  Future<void> close() async {}
}

const _resource = {
  '/system/resource/print': [
    {'board-name': 'SXTsq 5 ac', 'version': '6.49.10', 'cpu-load': '4', 'total-memory': '67108864', 'free-memory': '40000000', 'uptime': '3w'}
  ],
  '/system/health/print': <Map<String, String>>[],
  '/ppp/active/print': <Map<String, String>>[],
};

/// جهاز سسكو بالتلنت على المضيف المحلّيّ: الهويّة تُقرأ، وأمرا المنافذ (وما بعدهما) «% Invalid input» — كجلسةٍ سقطت بعد show version.
Future<ServerSocket> _ciscoTelnet() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    var phase = 0;
    var iac = 0;
    var line = '';
    socket.add([255, 251, 1]);
    socket.write('\r\nUsername: ');
    socket.listen((bytes) {
      for (final b in bytes) {
        if (iac > 0) {
          iac--;
          continue;
        }
        if (b == 255) {
          iac = 2;
          continue;
        }
        if (b == 10 || b == 13) {
          if (line.isEmpty) continue;
          final input = line;
          line = '';
          if (phase == 0) {
            phase++;
            socket.write('Password: ');
          } else if (phase == 1) {
            phase++;
            socket.write('\r\nswitch#');
          } else if (input == 'show version') {
            socket.write('show version\r\nCisco IOS Software, C2960 Software (C2960-LANBASEK9-M), Version 15.0(2)SE11, '
                'RELEASE SOFTWARE (fc3)\r\nswitch uptime is 3 weeks, 2 days, 4 hours, 10 minutes\r\n'
                'Model number                    : WS-C2960-24TT-L\r\nswitch#');
          } else if (input.startsWith('show')) {
            socket.write("$input\r\n                 ^\r\n% Invalid input detected at '^' marker.\r\n\r\nswitch#");
          } else if (input == 'exit' || input == 'quit') {
            socket.destroy();
          } else {
            socket.write('$input\r\nswitch#');
          }
        } else if (b >= 32 && b < 127) {
          line += ascii.decode([b]);
        }
      }
    }, onError: (Object _) {});
  });
  return server;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MikrotikSnmp.resetForTest();
  });
  tearDown(() {
    MikrotikSnmp.snmpFor =
        (host, port, community, timeout) => SnmpV2c(host: host, port: port, community: community, timeout: timeout);
    MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => throw UnimplementedError(route);
    MikrotikApi.resetRoutesForTest();
    UbntApi.debugFetch = null;
    RuijieApi.debugFetch = null;
    NetworkDevicesApi.invalidateCredentialsCache();
  });

  group('١ جدول منافذ لم يُقرأ ⇒ «المنافذ ما انقرت» لا «سويج · سليم»', () {
    test('🚨 SwOS: مسح أسماء المنافذ انتهت مهلته (٥٠٤ الممرّ) ⇒ «لم يُقرأ» بلا منافذ، واللقطة بمنافذها؛ والمقروء كاملاً «سليم» 5/8',
        () async {
      final d = dev(9, type: 'switch', protocol: 'snmp');
      final prev = CheckMemo(ports: {for (var k = 1; k <= 8; k++) 'ether$k': PortMemo(up: k <= 5, mbps: 1000)});
      MikrotikSnmp.snmpFor = (h, p, c, t) => _Lossy(_ifTable('CSS610-8G-2S+ SwOS v2.13'), lose: {MikrotikSnmp.ifName});
      final lost = await MikrotikSnmp.fetch(host: '10.0.0.9', community: 'public');
      final r = judge(d, DeviceVitals.mikrotikResult(d, lost, null, detailed: true), prev: prev);
      expect(r.state, CheckState.unread);
      expect(texts(r), contains('المنافذ ما انقرت'));
      expect(r.portsTotal, isNull);
      expect(r.memo!.ports.keys, prev.ports.keys, reason: 'اللقطة بمنافذها — «طفى» التالية تبقى ممكنة');
      // SwOS لا لاسلكيّ له أصلاً — جدولٌ ضائع لا يجعله «راديو مجهولاً»
      final g = DeviceVitals.mikrotikResult(d, lost, null, detailed: true).detail.glance;
      expect([g.hasRadio, g.radioUnread, g.portsUnread], [false, false, true]);
      // وأوّل فحصٍ له (بلا لقطة): القارئ نفسه يقول إنّ الجدول لم يُقرأ
      final first = judge(d, DeviceVitals.mikrotikResult(d, lost, null, detailed: true));
      expect(first.state, CheckState.unread);
      expect(texts(first), ['المنافذ ما انقرت']);

      MikrotikSnmp.snmpFor = (h, p, c, t) => _Lossy(_ifTable('CSS610-8G-2S+ SwOS v2.13'));
      final ok = await MikrotikSnmp.fetch(host: '10.0.0.9', community: 'public');
      final r2 = judge(d, DeviceVitals.mikrotikResult(d, ok, null, detailed: true), prev: prev);
      expect(r2.state, CheckState.ok);
      expect(r2.vitals.firstWhere((v) => v.k == 'المنافذ').v, '5/8');
    });

    test('حال الواجهات (ifOper) ضاع بعد رفض الأعمدة المتوازية ⇒ لا «المنافذ 0/N»؛ ورفضٌ عابر واحد لا يحوّل الوكيل لمسوحٍ منفردة',
        () async {
      final d = dev(8, type: 'switch', protocol: 'snmp');
      MikrotikSnmp.snmpFor =
          (h, p, c, t) => _Lossy(_ifTable('RouterOS CRS326-24G-2S+'), lose: {MikrotikSnmp.ifOper}, noPaired: true);
      final s = await MikrotikSnmp.fetch(host: '10.0.0.8', community: 'public');
      expect(MikrotikSnmp.singleColumnFor('10.0.0.8', 161), isFalse, reason: 'رفضٌ واحد قد يكون ٥٠٤ عابراً');
      final r = judge(d, DeviceVitals.mikrotikResult(d, s, null, detailed: true));
      expect(r.vitals.where((v) => v.k == 'المنافذ'), isEmpty, reason: 'لا «0/8» من حالٍ لم يُقرأ');
      expect(r.state, CheckState.unread);
      await MikrotikSnmp.fetch(host: '10.0.0.8', community: 'public');
      expect(MikrotikSnmp.singleColumnFor('10.0.0.8', 161), isTrue, reason: 'الثاني المتتالي يحفظه');
    });

    test('🚨 سسكو: أمرا المنافذ لم يعيدا شيئاً بعد الهويّة ⇒ «المنافذ ما انقرت» و«لم يُقرأ»، لا «سويج · سليم» بلا منافذ', () async {
      final server = await _ciscoTelnet();
      addTearDown(server.close);
      final d = dev(31, type: 'switch', brand: 'cisco', protocol: 'telnet', ip: '127.0.0.1', apiPort: server.port);
      NetworkDevicesApi.debugSeedCredentials(31, {'user': 'u', 'pass': 'p'}, DateTime.now());
      final p = await DeviceVitals.fetch(d, detailed: true);
      expect(p.detail.model, 'WS-C2960-24TT-L', reason: 'الهويّة قُرئت');
      final r = judge(d, p);
      expect(r.state, CheckState.unread);
      expect(texts(r), contains('المنافذ ما انقرت'));
    });
  });

  group('٢ سكتر يوبيكويتي: قائمة محطّاته لم تُقرأ ⇒ لا «ما عليه أحد الآن»', () {
    test('🚨 wstalist فشل والعدّاد يقول 6 ⇒ «قائمة مشتركيه ما انقرت» و«لم يُقرأ»، واللقطة تبقى 5', () async {
      UbntApi.debugFetch = () async => UbntStats.fromMcaStatus(const {
            'deviceName': 'Rocket M5',
            'wlanMode': 'master',
            'wlanEssid': 'SEC',
            'wlanConnections': '6',
            'cpuload': '7',
            'uptime': '864000',
          }, stationsRead: false);
      final d = dev(21, type: 'sector', brand: 'ubnt', protocol: 'ssh');
      NetworkDevicesApi.debugSeedCredentials(21, {'user': 'ubnt', 'pass': 'x'}, DateTime.now());
      final p = await DeviceVitals.fetch(d, detailed: true);
      expect(p.detail.glance.peersKnown, isFalse);
      final r = judge(d, p, prev: const CheckMemo(peers: 5));
      expect(r.state, CheckState.unread);
      expect(texts(r), ['قائمة مشتركيه ما انقرت']);
      expect(r.memo!.peers, 5, reason: 'لا صفرٌ يُخفي السقوط التالي');
    });

    test('«مقروءة» حين تقولها القراءة: العدّاد صفر، أو قائمة mca-dump ولو فارغة — لا حين فشل wstalist وحده', () {
      Map<String, String> ap({String? conns}) =>
          {'wlanMode': 'master', 'wlanEssid': 'S', if (conns != null) 'wlanConnections': conns};
      expect(UbntStats.fromMcaStatus(ap(conns: '6'), stationsRead: false).stationsRead, isFalse);
      expect(UbntStats.fromMcaStatus(ap(conns: '0'), stationsRead: false).stationsRead, isTrue, reason: 'الجهاز يقول لا أحد');
      expect(UbntStats.fromMcaStatus(ap(), stationsRead: true).stationsRead, isTrue, reason: 'wstalist قائمةٌ صالحة');
      final dumped = UbntApi.flattenMcaDumpForTest('{"host":{"hostname":"AP"},"wireless":{"mode":"ap-ptmp","essid":"S","sta":[]}}');
      expect(UbntStats.fromMcaStatus(dumped, stationsRead: false).stationsRead, isTrue, reason: 'mca-dump أعاد قائمته فارغة');
    });
  });

  group('٣ الوصلة: مقطوعةٌ أو بلا إشارةٍ مقروءة ليست «سليم»', () {
    test('🚨 SXT محطّةٌ مسجّلة «وصلة»: الراديو مفعّلٌ ولا يعمل والجدول فارغ ⇒ «الوصلة مقطوعة — لا إشارة»', () async {
      MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => _Ros({
            ..._resource,
            '/interface/print': [
              {'name': 'ether1', 'type': 'ether', 'running': 'true', 'disabled': 'false'},
              {'name': 'wlan1', 'type': 'wlan', 'running': 'false', 'disabled': 'false'},
            ],
            '/interface/wireless/print': [
              {'name': 'wlan1', 'mode': 'station', 'band': '5ghz-a/n/ac', 'ssid': 'BH', 'running': 'false', 'disabled': 'false'}
            ],
            '/interface/wireless/registration-table/print': <Map<String, String>>[],
          });
      final s = await MikrotikApi.fetchStatsFor(ip: '10.0.0.41', protocol: 'api', creds: const {'user': 'admin', 'pass': 'x'});
      final d = dev(41, type: 'link');
      final r = judge(d, DeviceVitals.mikrotikResult(d, s, null, detailed: true));
      expect(r.state, CheckState.warn);
      expect(texts(r), contains('الوصلة مقطوعة — لا إشارة'));
    });

    test('🚨 محطّة يوبيكويتي إشارتها 0 بلا طرفٍ ولا سرعة ⇒ «الوصلة مقطوعة» لا «وصلة · سليم»', () async {
      UbntApi.debugFetch = () async => UbntStats.fromMcaStatus(const {
            'deviceName': 'NanoBeam',
            'wlanMode': 'managed',
            'wlanEssid': 'BH',
            'wlanSignal': '0',
            'wlanTxRate': '0',
            'wlanRxRate': '0',
            'cpuload': '5',
            'uptime': '86400',
          });
      final d = dev(42, type: 'link', brand: 'ubnt', protocol: 'ssh');
      NetworkDevicesApi.debugSeedCredentials(42, {'user': 'ubnt', 'pass': 'x'}, DateTime.now());
      final r = judge(d, await DeviceVitals.fetch(d, detailed: true));
      expect(r.state, CheckState.warn);
      expect(texts(r), contains('الوصلة مقطوعة — لا إشارة'));
      expect(r.signal, isNull, reason: 'لا «0 dBm»');
    });

    test('🚨 طرف الـPtP المرسل مسجّلٌ «وصلة» (نقطة وصول): طرفه الثاني سقط ⇒ «الوصلة بلا طرفٍ ثانٍ» لا «سكتر · سليم»', () {
      final d = dev(43, type: 'link', brand: 'ubnt');
      final r = DevicesCheck.evaluate(
          d: d,
          alive: true,
          detail: const DeviceDetail(glance: DeviceGlance(isAp: true, peersKnown: true, cpu: 6, uptimeSec: 864000)),
          prev: const CheckMemo(peers: 1));
      expect(r.role, CheckRole.link);
      expect(r.state, CheckState.warn);
      expect(texts(r), contains('الوصلة بلا طرفٍ ثانٍ'));
      // وطرفه الثاني حاضرٌ ⇒ يُحكم بإشارته (كيف يستقبلنا) على حدّ الوصلة لا حدّ المشترك
      final up = DevicesCheck.evaluate(
          d: d,
          alive: true,
          detail: const DeviceDetail(
              glance: DeviceGlance(isAp: true, peersKnown: true, cpu: 6, uptimeSec: 864000),
              peers: [PeerLink(name: 'الطرف الثاني', signal: -64, txSignal: -66)]));
      expect(up.role, CheckRole.link);
      expect(up.remoteSignal, -66);
      expect(up.state, CheckState.ok);
    });

    test('🚨 LHG 60G: monitor انتهت مهلته ⇒ إشارتها «لم تُقرأ» لا «وصلة · سليم»؛ وطرفها المرسل (سكتر) لا «ما عليه أحد الآن»', () async {
      Future<MikrotikStats> lhg(String mode) {
        MikrotikApi.resetRoutesForTest();
        MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => _Ros({
              ..._resource,
              '/interface/print': [
                {'name': 'ether1', 'type': 'ether', 'running': 'true', 'disabled': 'false'},
                {'name': 'wlan60-1', 'type': 'w60g', 'running': 'true', 'disabled': 'false'},
              ],
              '/interface/w60g/print': [
                {'name': 'wlan60-1', 'mode': mode, 'frequency': '58320', 'running': 'true', 'disabled': 'false'}
              ],
              '/interface/w60g/station/print': <Map<String, String>>[],
              '/interface/w60g/monitor': TimeoutException('monitor'),
            });
        return MikrotikApi.fetchStatsFor(ip: '10.0.0.44', protocol: 'api', creds: const {'user': 'admin', 'pass': 'x'});
      }

      final d = dev(44, type: 'link');
      final r = judge(d, DeviceVitals.mikrotikResult(d, await lhg('station-bridge'), null, detailed: true));
      expect(r.state, CheckState.unread);
      expect(texts(r), contains('إشارة الوصلة ما انقرت'));
      // طرفها المرسل مسجّلٌ «سكتر»: الوصلة لم تُقرأ ⇒ لا «ما عليه أحد الآن» بحالٍ «سليم»
      final ap = dev(47, type: 'sector');
      final r2 = judge(ap, DeviceVitals.mikrotikResult(ap, await lhg('ap-bridge'), null, detailed: true),
          prev: const CheckMemo(peers: 1));
      expect(texts(r2).where((t) => t.contains('ما عليه أحد')), isEmpty);
      expect(r2.state, CheckState.unread);
    });

    test('وصلةٌ بلا إشارةٍ ولا طرفٍ مقروء ⇒ «لم يُقرأ» ولو لم يُعلَم القارئ بنقص — والوصلة السلكيّة (لا راديو) تُحكم بلا إشارة', () {
      final link = dev(45, type: 'link', brand: 'mimosa');
      final r = DevicesCheck.evaluate(
          d: link, alive: true, detail: const DeviceDetail(glance: DeviceGlance(isAp: false, cpu: 4, uptimeSec: 864000)));
      expect(r.state, CheckState.unread);
      expect(texts(r), ['إشارة الوصلة ما انقرت']);
      final wired = DevicesCheck.evaluate(
          d: dev(46, type: 'link'),
          alive: true,
          detail: const DeviceDetail(glance: DeviceGlance(cpu: 4, uptimeSec: 864000, hasRadio: false)));
      expect(wired.state, CheckState.ok);
    });
  });

  group('٣ب روجي: جدول الجسر انتهت مهلته', () {
    test('جسر روجي مسجّلٌ «راوتر» وجدول جسره لم يُقرأ ⇒ «وضعه اللاسلكيّ ومشتركوه ما انقرأوا» لا «راوتر · سليم»؛ والسويج بمنافذه', () async {
      RuijieApi.debugFetch = () async => const RuijieStats(sysName: 'EST310', cpuPercent: 4, memPercent: 30, linkRead: false);
      final d = dev(48, brand: 'ruijie', protocol: 'snmp');
      NetworkDevicesApi.debugSeedCredentials(48, {'community': 'public'}, DateTime.now());
      final r = judge(d, await DeviceVitals.fetch(d, detailed: true));
      expect(r.state, CheckState.unread);
      expect(texts(r), contains('وضعه اللاسلكيّ ومشتركوه ما انقرأوا'));
      // روجي سويج: لا لاسلكيّ يُطالَب به
      final sw = dev(49, type: 'switch', brand: 'ruijie', protocol: 'snmp');
      NetworkDevicesApi.debugSeedCredentials(49, {'community': 'public'}, DateTime.now());
      final r2 = judge(sw, await DeviceVitals.fetch(sw, detailed: true));
      expect(texts(r2).where((t) => t.contains('اللاسلكيّ')), isEmpty);
    });
  });

  group('٤ «كل الشركات»: قراءة الخادم بعمرها وضوؤه الجزئيّ', () {
    final olt = NetworkDevice(
        id: 51, adminId: '9', name: 'أولت الحيّ', type: 'other', brand: 'vsol', model: 'V1600D8', ip: '10.9.0.51', port: 161,
        protocol: 'snmp', hasCredentials: true, lastStatus: 'online', createdAt: DateTime(2026, 11, 1));
    Map<String, dynamic> summary() => {
          'kind': 'olt',
          'total': 1000,
          'online': 950,
          'pons': [
            {'label': 'PON1', 'up': true, 'online': 950, 'total': 1000}
          ],
          'onus': [
            for (var i = 0; i < 300; i++) {'n': 'ONU $i', 'k': 'PON1:$i', 'rx': -20.0 - (i % 5)}
          ],
        };

    test('🚨 ملخّص أولت الخادم بلا لحظته (حتى 30 د) و300 ضوءٍ من 950 ⇒ «آخر قراءة · حتى 30 د» و«الضوء 300 من 950» لا «كلّه جيّد» طازجاً',
        () {
      final now = DateTime(2026, 11, 9, 23);
      final r = MergedDevicesCheckRunner.remoteReport(
          olt, VpnDeviceResult(id: 51, alive: true, vitals: summary()), const CheckLimits(), null, const {},
          serverAtMs: now.millisecondsSinceEpoch, now: now);
      expect(r.bucket, CheckBucket.stale, reason: 'لا يُعدّ «سليماً» الآن');
      expect(r.stateLabel, 'سليم · حتى 30 د');
      expect(r.lightsWanted, 950);
      expect(r.subs.length, 300);
      expect(texts(r), contains('الضوء: قُرئ 300 من 950 — الباقي لم يقرأه الخادم'));
    });

    test('قراءة جهازٍ أقدم من نافذة إعادة الاستعمال ⇒ بعمرها بساعة الخادم وحدها؛ وضمنها قراءة هذا الفحص', () {
      final now = DateTime(2026, 11, 9, 23);
      // ساعة الخادم متقدّمة ٨ د على الهاتف: العمر من الفرق بين لحظتيه هو، لا من ساعة الهاتف
      final serverAt = now.add(const Duration(minutes: 8)).millisecondsSinceEpoch;
      VpnDeviceResult res(Duration age) => VpnDeviceResult(
          id: 52,
          alive: true,
          vitals: const {
            'kind': 'ros',
            'cpu': 12,
            'up': 864000,
            'ports': {'up': 1, 'total': 1},
            'pl': [
              {'n': 'ether1', 'r': true}
            ],
            'ap': null,
            'peers': [],
          },
          readAtMs: serverAt - age.inMilliseconds);
      final d = dev(52);
      final old = MergedDevicesCheckRunner.remoteReport(d, res(const Duration(minutes: 6)), const CheckLimits(), null, const {},
          serverAtMs: serverAt, now: now);
      expect(old.bucket, CheckBucket.stale);
      expect(old.staleAge, 'قبل 6 د');
      final fresh = MergedDevicesCheckRunner.remoteReport(d, res(const Duration(seconds: 100)), const CheckLimits(), null, const {},
          serverAtMs: serverAt, now: now);
      expect(fresh.staleAt, isNull);
      expect(fresh.bucket, CheckBucket.ok);
    });
  });

  group('٥ قراءة الخادم بقواعد «لم يُقرأ» نفسها', () {
    DeviceCheckReport remote(NetworkDevice d, Map<String, dynamic> v, {CheckMemo? prev}) => MergedDevicesCheckRunner.remoteReport(
        d, VpnDeviceResult(id: d.id, alive: true, vitals: v), const CheckLimits(), prev, const {});
    Map<String, dynamic> ros({Object? ap, Object? peers = const [], int ports = 2, bool? radio}) => {
          'kind': 'ros',
          'cpu': 9,
          'up': 864000,
          'ports': {'up': ports, 'total': ports},
          'pl': [
            for (var k = 1; k <= ports; k++) {'n': 'ether$k', 'r': true}
          ],
          'ap': ap,
          if (radio != null) 'radio': radio,
          'peers': peers,
        };
    const peer = {'n': 'ali.home', 's': -62, 'ts': -60, 'q': 90};

    test('🚨 نقطة وصولٍ محفوظة «راوتر» وحزمة wifi (ap فارغ) بعملائها ⇒ لا «راوتر · سليم»', () {
      final r = remote(dev(61), ros(ap: null, radio: true, peers: [peer]));
      expect(r.state, isNot(CheckState.ok));
      expect(r.bucket, isNot(CheckBucket.ok));
    });

    test('🚨 سكتر والخادم ما قرأ جدول التسجيل (peers فارغة بلا reg_ok) ⇒ «قائمة مشتركيه ما انقرت» لا «ما عليه أحد الآن»', () {
      final r = remote(dev(62, type: 'sector'), ros(ap: true), prev: const CheckMemo(peers: 7));
      expect(r.state, CheckState.unread);
      expect(texts(r), contains('قائمة مشتركيه ما انقرت'));
      expect(r.memo!.peers, 7);
      // والخادم يقول إنّه قرأه فارغاً ⇒ «ما عليه أحد الآن — كانوا 7»
      final read = remote(dev(62, type: 'sector'), {...ros(ap: true), 'reg_ok': true}, prev: const CheckMemo(peers: 7));
      expect(texts(read), contains('ما عليه أحد الآن — كانوا 7 بالفحص السابق'));
    });

    test('ap فارغ ودوره من آخر قراءةٍ قُرئ فيها «سكتر» ⇒ سكتر «لم يُقرأ» لا «راوتر · سليم»؛ وراوترٌ بلا راديو يبقى «سليم»', () {
      final r = remote(dev(63), ros(ap: null), prev: const CheckMemo(role: CheckRole.sector, peers: 4));
      expect(r.role, CheckRole.sector);
      expect(r.state, CheckState.unread);
      final ccr = remote(dev(64), ros(ap: null, ports: 4));
      expect(ccr.role, CheckRole.router);
      expect(ccr.state, CheckState.ok);
    });

    test('محطّة airOS إشارتها 0 ⇒ «الوصلة مقطوعة» لا «0 dBm»؛ وجلسة الخادم بلا منفذٍ واحد ⇒ «المنافذ ما انقرت»', () {
      final sta = remote(dev(65, type: 'link', brand: 'ubnt'),
          {'kind': 'airos', 'cpu': 5, 'up': 864000, 'ap': false, 'mode': 'sta-ptp', 'sig': 0, 'peers': null});
      expect(sta.signal, isNull);
      expect(texts(sta), contains('الوصلة مقطوعة — لا إشارة'));
      final cut = remote(dev(66, type: 'switch'), {...ros(ap: null, ports: 0), 'pl': const []},
          prev: const CheckMemo(ports: {'ether1': PortMemo(up: true, mbps: 1000)}));
      expect(cut.state, CheckState.unread);
      expect(texts(cut), contains('المنافذ ما انقرت'));
      // وبلا لقطةٍ سابقة: عدّ الخادم صفرٌ بلا منفذ ⇒ الجلسة انقطعت، لا «سليم»
      final first = remote(dev(67, type: 'switch'), {...ros(ap: null, ports: 0), 'pl': const []});
      expect(first.state, CheckState.unread);
      expect(texts(first), ['المنافذ ما انقرت']);
    });
  });

  group('٦ راديو بحزمةٍ لا يسألها القارئ', () {
    test('🚨 wifiwave2 (7.1–7.12) أو CAPsMAN «cap» بالطبقة الأولى بلا صفٍّ مقروء ⇒ «وضعه اللاسلكيّ ومشتركوه ما انقرأوا» لا «راوتر · سليم»',
        () {
      for (final type in ['wifiwave2', 'cap']) {
        final s = MikrotikStats(
            cpuLoad: 3, memUsedPercent: 20, memTotalBytes: 64, memFreeBytes: 50, uptime: '3w', version: '7.10',
            boardName: 'hAP ac^2', architectureName: 'arm', cpuCount: 4, cpuFrequencyMhz: 716,
            interfaces: [
              const MikrotikInterface(name: 'ether1', type: 'ether', running: true, disabled: false),
              MikrotikInterface(name: 'wifi1', type: type, running: true, disabled: false),
            ],
            pppActiveCount: 0);
        final d = dev(71);
        final r = judge(d, DeviceVitals.mikrotikResult(d, s, null, detailed: true));
        expect(r.state, CheckState.unread, reason: type);
        expect(texts(r), contains('وضعه اللاسلكيّ ومشتركوه ما انقرأوا'), reason: type);
      }
    });
  });

  group('٧ عمر قراءة الخادم بساعةٍ واحدة (هاتفٌ ساعته متأخّرة ٨ د)', () {
    tearDown(VpnNow.reset);

    test('🚨 قراءةٌ عمرها ٧ د بساعة الخادم لا تمرّ بوّابة الخمس دقائق «قبل لحظات»؛ وبلا لحظتها عمرها من وصولها لا من المستقبل', () {
      final run = DevicesCheckRunner([dev(81)], viaVpn: true);
      final serverNow = DateTime.now().add(const Duration(minutes: 8));
      VpnNow.debugApply(
          VpnNowKind.devices,
          VpnNowResult(ok: true, message: 'تم', atMs: serverNow.millisecondsSinceEpoch, devices: [
            VpnDeviceResult(
                id: 81,
                alive: true,
                vitals: const {'kind': 'ros', 'cpu': 17, 'up': 3600},
                readAtMs: serverNow.subtract(const Duration(minutes: 7)).millisecondsSinceEpoch),
            const VpnDeviceResult(id: 82, alive: true, vitals: {'kind': 'ros', 'cpu': 18, 'up': 3600}),
          ]));
      expect(run.lastReadingFor(dev(81)), isNull, reason: 'عمرها ٧ د — أقدم من البوّابة');
      final last = run.lastReadingFor(dev(82))!;
      expect(last.at.isAfter(DateTime.now()), isFalse, reason: 'لا لحظة في المستقبل');
      expect(DevicesCheck.ago(last.at, DateTime.now()), 'قبل 2 د', reason: 'نافذة إعادة الاستعمال (١٥٠ث) من وصولها');
      run.dispose();
    });
  });

  group('٨ زمن القراءة', () {
    setUp(() {
      DevicesCheckRunner.debugLimits = () async => const CheckLimits();
      DevicesCheckRunner.debugSubscribers = () async => const [];
      DevicesCheckRunner.debugProbe = (d) async => (status: 'online', responseMs: 4, packetLoss: 0.0, serviceOk: true);
      DevicesCheckRunner.debugTimes = (soft: const Duration(milliseconds: 50), hard: const Duration(milliseconds: 150));
    });
    tearDown(() {
      DevicesCheckRunner.debugLimits = null;
      DevicesCheckRunner.debugSubscribers = null;
      DevicesCheckRunner.debugProbe = null;
      DevicesCheckRunner.debugFetch = null;
      DevicesCheckRunner.debugTimes = null;
    });

    test('🚨 «أعد قراءة غير المقروء» ينتظر قراءةً جارية ⇒ زمنها من بدئها هي لا من الإعادة', () async {
      final late = Completer<ProbeResult>();
      final since = Stopwatch();
      DevicesCheckRunner.debugFetch = (d) {
        since.start();
        return late.future;
      };
      final run = DevicesCheckRunner([dev(91)], viaVpn: false);
      await run.run();
      expect(run.unreadCount, 1, reason: 'بلغ السقف');
      final again = run.rerunUnread();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final took = since.elapsedMilliseconds;
      late.complete(const ProbeResult(vitals: [], counters: {}, detail: DeviceDetail(glance: DeviceGlance(cpu: 3, uptimeSec: 86400))));
      await again;
      expect(run.reports[91]!.readMs, greaterThanOrEqualTo(took), reason: 'من بدء القراءة الجارية (≥ ${took}ms)');
      run.dispose();
    });
  });
}
