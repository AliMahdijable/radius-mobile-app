// «الفحص الشامل» — أحكام الأجهزة اللاسلكيّة (مراجعة 180، findings_devwl): لا «سليم» ولا «لا أحد» ولا «بلا طرف»
// من قراءةٍ لم تكتمل، ولا «لم يُقرأ» لما قُرئ.
//   F1  سكتر ميموزا PtMP: مسح محطّاته انتهت مهلته ⇒ «قائمة مشتركيه ما انقرت» لا «سكتر · سليم» + «ما عليه أحد الآن».
//   F10 طرف وصلة ميموزا PtP المرسل (نقطة وصول) مسجّلٌ «وصلة» يقرأ إشارته ⇒ يُحكم بها لا «الوصلة بلا طرفٍ ثانٍ».
//   F19 وصلة RouterOS وضعها لم يُقرأ (الخادم بلا ap، حزمة wifi) بطرفٍ واحد ⇒ إشارة صفّه لا «إشارة الوصلة ما انقرت».
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';
import 'package:rad_mysvcs/api/mimosa_api.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/api/routeros_channel.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/api/vpn_now_api.dart';
import 'package:rad_mysvcs/core/net/device_net.dart';
import 'package:rad_mysvcs/core/net/vpn_pipe.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/services/devices_check.dart';
import 'package:rad_mysvcs/services/merged_devices_check.dart';

import 'support/fake_snmp_agent.dart';

NetworkDevice dev(int id, {String type = 'sector', String brand = 'mimosa', String protocol = 'snmp'}) => NetworkDevice(
      id: id,
      adminId: '2',
      name: 'جهاز $id',
      type: type,
      brand: brand,
      ip: '10.0.0.$id',
      port: brand == 'mikrotik' ? 8728 : 161,
      protocol: protocol,
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime(2026, 11, 1),
    );

List<String> texts(DeviceCheckReport r) => [for (final f in r.findings) f.text];

DeviceCheckReport judge(NetworkDevice d, ProbeResult p, {CheckMemo? prev}) =>
    DevicesCheck.evaluate(d: d, alive: true, detail: p.detail, raw: p.raw, prev: prev);

/// شركةٌ أخرى في «كل الشركات»: قراءة الخادم [v] كما تصل (summarizeDevices).
DeviceCheckReport remote(NetworkDevice d, Map<String, dynamic> v, {CheckMemo? prev}) =>
    MergedDevicesCheckRunner.remoteReport(
        d, VpnDeviceResult(id: d.id, alive: true, vitals: v), const CheckLimits(), prev, const {});

/// قراءة الخادم لجهاز RouterOS (prober.readRouterOsVitals): منفذ إيثر واحد شغّال، و[extra] فوقها.
Map<String, dynamic> ros(Map<String, dynamic> extra) => {
      'kind': 'ros',
      'cpu': 9,
      'mem': 40,
      'up': 864000,
      'ports': {'up': 1, 'total': 1},
      'pl': [
        {'n': 'ether1', 'r': true}
      ],
      ...extra,
    };

/// جهاز RouterOS بالـAPI بردودٍ مكتوبة — الأمر الغائب «no such command» (حزمةٌ غير مثبّتة)، والقيمة Exception تُرمى.
class RosReplies implements RouterOsChannel {
  RosReplies(this.replies);
  final Map<String, Object> replies;
  @override
  String get via => 'API';
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

const rosResource = {
  '/system/resource/print': [
    {
      'board-name': 'hAP ax2',
      'version': '7.16.1',
      'cpu-load': '4',
      'total-memory': '67108864',
      'free-memory': '40000000',
      'uptime': '3w',
    }
  ],
  '/system/health/print': <Map<String, String>>[],
  '/ppp/active/print': <Map<String, String>>[],
};

/// قراءة مايكروتك مفصّلة بالـAPI من [replies] ⇒ حكم الفحص.
Future<DeviceCheckReport> judgeRos(NetworkDevice d, Map<String, Object> replies, {CheckMemo? prev}) async {
  MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => RosReplies({...rosResource, ...replies});
  final s = await MikrotikApi.fetchStatsFor(ip: d.ip, protocol: 'api', creds: const {'user': 'admin', 'pass': 'x'});
  final p = DeviceVitals.mikrotikResult(d, s, null, detailed: true);
  return DevicesCheck.evaluate(d: d, alive: true, detail: p.detail, raw: p.raw, prev: prev);
}

// ── ميموزا: جدولا المحطّات الرسميّان (MIMOSA-NETWORKS-PTMP-MIB = mimosaWireless.9) والبديل القديم ──
const _bfive = '1.3.6.1.4.1.43356.2.1.2';
const _info = '$_bfive.9.5.1.1';
const _stats = '$_bfive.9.6.1.1';
const _legacy = '1.3.6.1.4.1.43356.2.2';

/// جهاز ميموزا: [rssi] محطّةٌ لكلٍّ (dBm) في الجدولين الرسميّين، وما قبلهما وبعدهما — المسح يقف بخروجه من شجرته
/// كجهازٍ حقيقيّ.
Map<String, Varbind> mimosaAgent({List<int> rssi = const []}) => {
      '1.3.6.1.2.1.1.5.0': snmpText('', 'TWR'),
      '$_bfive.1.1.0': snmpText('', 'TWR-A5c'),
      for (var i = 1; i <= rssi.length; i++) ...{
        '$_info.2.$i': snmpBytes('', [0x20, 0xb5, 0xc6, 0, 0, i]),
        '$_info.3.$i': snmpText('', 'محطّة $i'),
        '$_stats.2.$i': snmpBytes('', [0x20, 0xb5, 0xc6, 0, 0, i]),
        '$_stats.11.$i': snmpInt('', rssi[i - 1] * 10), // DecimalOne
      },
      '1.3.6.1.6.3.10.2.1.1.0': snmpText('', 'engine'),
    };

/// قراءة ميموزا مفصّلة كما يقرؤها الفحص عبر الـVPN: الإحصاءات من بديلها، والمحطّات بـSNMP حقيقيّ ([SnmpV2c.walk])
/// عبر [pipe].
Future<ProbeResult> readMimosa(NetworkDevice d, SnmpPipe pipe, {int mode = 1, double? rx = -58}) {
  MimosaApi.debugFetch = () async => MimosaStats(wirelessMode: mode, totalRxPowerDbm: rx, temperatureC: 41, ssid: 'BH');
  VpnPipe.transport = pipe;
  NetworkDevicesApi.debugSeedCredentials(d.id, {'community': 'public'}, DateTime.now());
  return DeviceNet.vpn(() => DeviceVitals.fetch(d, detailed: true));
}

/// جهاز SNMP يصله «وضع VPN» عبر ممرّ الخادم: يفكّ طلب [SnmpV2c] الحقيقيّ (GET/GETBULK) ويردّ بحزمةٍ حقيقيّة —
/// فيمرّ المسح وتحليل الردّ كما هما. [lose]: بادئات OID يُسقط الممرّ طلباتها (٥٠٤ ⇒ مهلة) كما عبر الـVPN.
class SnmpPipe implements VpnPipeTransport {
  SnmpPipe(Map<String, Varbind> data, {this.lose = const {}})
      : _data = data,
        _sorted = data.keys.toList()..sort(FakeSnmpAgent.compareOid);
  final Map<String, Varbind> _data;
  final List<String> _sorted;
  final Set<String> lose;

  @override
  Future<({Uint8List data, int? ms})> udp(String host, int port, Uint8List data, Duration timeout) async {
    final q = _Req.decode(data);
    if (q.oids.any((o) => lose.any((p) => o == p || o.startsWith('$p.')))) {
      throw TimeoutException('SNMP عبر الـVPN: الجهاز ما ردّ');
    }
    final out = <(String, int, List<int>)>[];
    for (final o in q.oids) {
      if (!q.bulk) {
        final v = _data[o];
        out.add(v == null ? (o, 0x81, const <int>[]) : (o, v.rawTag, v.rawBytes));
        continue;
      }
      final next = [for (final k in _sorted) if (FakeSnmpAgent.compareOid(k, o) > 0) k].take(q.max).toList();
      if (next.isEmpty) out.add((o, 0x82, const <int>[]));
      for (final k in next) {
        out.add((k, _data[k]!.rawTag, _data[k]!.rawBytes));
      }
    }
    return (data: q.reply(out), ms: 3);
  }

  @override
  Future<({String id, int? ms})> open(String host, int port, Duration timeout) =>
      Future.error(SocketException('لا TCP في هذا الجهاز', port: port));
  @override
  Future<bool> write(String id, Uint8List data) async => false;
  @override
  Future<PipeRead?> read(String id, Duration wait) async => null;
  @override
  Future<void> close(String id) async {}
  @override
  Future<List<int>> ping(String host, int count, Duration timeout) async => const [3];
  @override
  Future<PipeRoute> route() async => const PipeRoute.ok('company');
  @override
  Future<void> release() async {}
}

/// طلب SNMP v2c (BER) وردّه — بقدر ما يرسله [SnmpV2c].
class _Req {
  _Req(this.community, this.rid, this.bulk, this.max, this.oids);
  final List<int> community, rid;
  final bool bulk;
  final int max;
  final List<String> oids;

  static _Req decode(Uint8List b) {
    var p = 0;
    int len() {
      var l = b[p++];
      if (l & 0x80 != 0) {
        final n = l & 0x7f;
        l = 0;
        for (var i = 0; i < n; i++) {
          l = (l << 8) | b[p++];
        }
      }
      return l;
    }

    List<int> value() {
      p++;
      final l = len();
      return b.sublist(p, p += l);
    }

    void open() {
      p++;
      len();
    }

    open(); // الرسالة
    value(); // الإصدار
    final community = value();
    final bulk = b[p] == 0xA5;
    open(); // PDU
    final rid = value();
    value(); // non-repeaters
    final max = value().fold<int>(0, (a, x) => (a << 8) | x);
    open(); // القائمة
    final oids = <String>[];
    while (p < b.length) {
      open(); // varbind
      final o = value();
      final parts = <int>[o[0] ~/ 40, o[0] % 40];
      for (var i = 1, v = 0; i < o.length; i++) {
        v = (v << 7) | (o[i] & 0x7f);
        if (o[i] & 0x80 == 0) {
          parts.add(v);
          v = 0;
        }
      }
      oids.add(parts.join('.'));
      value(); // NULL
    }
    return _Req(community, rid, bulk, max, oids);
  }

  static List<int> _tlv(int tag, List<int> v) {
    final n = <int>[];
    for (var x = v.length; x > 0; x >>= 8) {
      n.insert(0, x & 0xff);
    }
    return [tag, if (v.length < 128) v.length else ...[0x80 | n.length, ...n], ...v];
  }

  static List<int> _oid(String oid) {
    final parts = oid.split('.').map(int.parse).toList();
    final out = [parts[0] * 40 + parts[1]];
    for (final x in parts.skip(2)) {
      final g = <int>[x & 0x7f];
      for (var v = x >> 7; v > 0; v >>= 7) {
        g.insert(0, 0x80 | (v & 0x7f));
      }
      out.addAll(g);
    }
    return out;
  }

  Uint8List reply(List<(String, int, List<int>)> vbs) {
    final list = [for (final v in vbs) ..._tlv(0x30, [..._tlv(0x06, _oid(v.$1)), ..._tlv(v.$2, v.$3)])];
    final pdu = _tlv(0xA2, [..._tlv(0x02, rid), ..._tlv(0x02, [0]), ..._tlv(0x02, [0]), ..._tlv(0x30, list)]);
    return Uint8List.fromList(_tlv(0x30, [..._tlv(0x02, [1]), ..._tlv(0x04, community), ...pdu]));
  }
}

void main() {
  late VpnPipeTransport savedPipe;
  setUp(() => savedPipe = VpnPipe.transport);
  tearDown(() {
    VpnPipe.transport = savedPipe;
    MimosaApi.debugFetch = null;
    MimosaApi.debugClients = null;
    MikrotikApi.channelFactory = (route, ip, port, user, pass, timeout) => throw UnimplementedError(route);
    MikrotikApi.resetRoutesForTest();
    NetworkDevicesApi.invalidateCredentialsCache();
  });

  group('F1 سكتر ميموزا: مسح محطّاته لم يكتمل ⇒ لا «سكتر · سليم» ولا «ما عليه أحد الآن»', () {
    test('🚨 جدول الإحصاء الرسميّ انتهت مهلته (٥٠٤ الممرّ) والبديل غائب ⇒ «قائمة مشتركيه ما انقرت»، واللقطة 20',
        () async {
      final d = dev(11);
      final p = await readMimosa(d, SnmpPipe(mimosaAgent(rssi: [-52, -55, -58]), lose: {_stats}));
      expect(p.detail.glance.peersKnown, isFalse);
      final r = judge(d, p, prev: const CheckMemo(peers: 20));
      expect(r.role, CheckRole.sector);
      expect(r.state, CheckState.unread);
      expect(texts(r), ['قائمة مشتركيه ما انقرت']);
      expect(r.memo!.peers, 20, reason: 'لا صفرٌ يجعل كلّ فشلٍ بعده «سليم»');
      // وأوّل فحصٍ له (بلا لقطة): لا «ما عليه أحد الآن» بحالٍ «سليم»
      expect(judge(d, p).state, CheckState.unread);
    });

    test('🚨 الرسميّان أجابا فارغين والبديل القديم انتهت مهلته ⇒ «لم يُقرأ» — برنامجٌ قديم محطّاته في البديل وحده',
        () async {
      final d = dev(12);
      final p = await readMimosa(d, SnmpPipe(mimosaAgent(), lose: {_legacy}));
      expect(p.detail.glance.peersKnown, isFalse);
      final r = judge(d, p, prev: const CheckMemo(peers: 6));
      expect(r.state, CheckState.unread);
      expect(texts(r), ['قائمة مشتركيه ما انقرت']);
      expect(r.memo!.peers, 6);
    });

    test('🚨 نقطة وصولٍ مسجّلة «وصلة» بلا إشارةٍ ومسح محطّاتها فشل ⇒ «إشارة الوصلة ما انقرت» لا «الوصلة بلا طرفٍ ثانٍ»',
        () async {
      final d = dev(13, type: 'link');
      final r = judge(d, await readMimosa(d, SnmpPipe(mimosaAgent(rssi: [-60]), lose: {_stats}), rx: null));
      expect(r.role, CheckRole.link);
      expect(texts(r), isNot(contains('الوصلة بلا طرفٍ ثانٍ')));
      expect(texts(r), ['إشارة الوصلة ما انقرت']);
      expect(r.state, CheckState.unread);
    });

    test('ما قُرئ يُحكم به: ثلاث محطّات ⇒ «سليم» بإشاراتها، وجدولان فارغان ⇒ «ما عليه أحد الآن»؛ واللوحة بقائمتها',
        () async {
      final d = dev(14);
      final ok = judge(d, await readMimosa(d, SnmpPipe(mimosaAgent(rssi: [-52, -55, -58]))));
      expect(ok.state, CheckState.ok);
      expect([for (final s in ok.subs) s.signal], [-58, -55, -52]);
      final empty = judge(d, await readMimosa(d, SnmpPipe(mimosaAgent())), prev: const CheckMemo(peers: 1));
      expect(texts(empty), ['ما عليه أحد الآن']);
      expect(empty.state, CheckState.ok);
      expect(empty.memo!.peers, 0);
      // لوحة ميموزا: القائمة نفسها، والفشل قائمةٌ فارغة لا exception
      VpnPipe.transport = SnmpPipe(mimosaAgent(rssi: [-52, -55]));
      final list = await DeviceNet.vpn(() => MimosaApi.fetchClients(host: '10.0.0.14', community: 'public'));
      expect(list.length, 2);
      VpnPipe.transport = SnmpPipe(mimosaAgent(rssi: [-52]), lose: {_stats, _legacy});
      expect(await DeviceNet.vpn(() => MimosaApi.fetchClients(host: '10.0.0.14', community: 'public')), isEmpty);
    });
  });

  group('F10 طرف وصلة ميموزا PtP المرسل مسجّلٌ «وصلة»: يُحكم بإشارته لا «الوصلة بلا طرفٍ ثانٍ»', () {
    test('🚨 B5c بوضع AP (wirelessMode 1) استقباله −58 ولا جدول محطّاتٍ في PtP ⇒ «وصلة · سليم»؛ و−85 ⇒ «ضعيفة»',
        () async {
      final d = dev(21, type: 'link');
      final r = judge(d, await readMimosa(d, SnmpPipe(mimosaAgent())));
      expect(r.role, CheckRole.link);
      expect(texts(r), isNot(contains('الوصلة بلا طرفٍ ثانٍ')));
      expect(r.state, CheckState.ok);
      expect(r.signal, -58);
      final weak = judge(d, await readMimosa(d, SnmpPipe(mimosaAgent()), rx: -85));
      expect(weak.state, CheckState.warn);
      expect(texts(weak), ['إشارة الوصلة -85 dBm — ضعيفة']);
    });

    test('🚨 نقطة وصولٍ «وصلة» جدولها فارغ وإشارتها مقروءة ⇒ تُحكم بها؛ وبلا إشارةٍ ولا طرف ⇒ «الوصلة بلا طرفٍ ثانٍ»',
        () {
      DeviceCheckReport link(DeviceGlance g) =>
          DevicesCheck.evaluate(d: dev(22, type: 'link'), alive: true, detail: DeviceDetail(glance: g));
      final own = link(const DeviceGlance(isAp: true, peersKnown: true, signal: -61, uptimeSec: 864000));
      expect(own.role, CheckRole.link);
      expect(own.state, CheckState.ok);
      expect(own.signal, -61);
      final none = link(const DeviceGlance(isAp: true, peersKnown: true, uptimeSec: 864000));
      expect(none.state, CheckState.warn);
      expect(texts(none), ['الوصلة بلا طرفٍ ثانٍ']);
    });
  });

  group('F19 وصلة RouterOS وضعها لم يُقرأ بطرفٍ واحد: إشارة صفّه مقروءة', () {
    test('🚨 «كل الشركات»: الخادم بلا ap (حزمة wifi) وصفّ طرفها الوحيد −63 ⇒ «وصلة · سليم» بها، و−85 ⇒ «ضعيفة»', () {
      final d = dev(31, type: 'link', brand: 'mikrotik', protocol: 'api');
      Map<String, dynamic> v(Map<String, dynamic> peer) =>
          ros({'ap': null, 'radio': true, 'reg_ok': true, 'sig': null, 'peers': [peer]});
      final r = remote(d, v({'n': 'TWR-AP', 's': -63, 'm': 'aa:bb:cc:00:00:01'}));
      expect(r.role, CheckRole.link);
      expect(texts(r), isNot(contains('إشارة الوصلة ما انقرت')));
      expect(r.state, CheckState.ok);
      expect(r.signal, -63);
      expect(r.remoteSignal, isNull, reason: 'ما يستقبله هذا الجهاز «الإشارة» لا «الطرف الثاني»');
      final weak = remote(d, v({'n': 'TWR-AP', 's': -85}));
      expect(texts(weak), ['إشارة الوصلة -85 dBm — ضعيفة']);
      // وكيف يستقبلنا الطرف الثاني (tx) إن قاله الجدول ⇒ «الطرف الثاني» ويُحكم بالأضعف
      final far = remote(d, v({'n': 'TWR-AP', 's': -63, 'ts': -84}));
      expect([far.signal, far.remoteSignal], [-63, -84]);
      expect(texts(far), ['إشارة الوصلة -84 dBm — ضعيفة (عند الطرف الثاني)']);
    });

    test('🚨 محطّة حزمة wifi (قائمتها بلا running) «وصلة» وجدولها صفٌّ واحد −61 ⇒ «وصلة · سليم» لا «لم يُقرأ»',
        () async {
      final r = await judgeRos(dev(32, type: 'link', brand: 'mikrotik', protocol: 'api'), {
        '/interface/print': [
          {'name': 'ether1', 'type': 'ether', 'running': 'true', 'disabled': 'false'},
          {'name': 'wifi1', 'type': 'wifi', 'running': 'true', 'disabled': 'false'},
        ],
        '/interface/wifi/print': [
          {'name': 'wifi1', 'configuration': 'BH', 'mode': 'station'}
        ],
        '/interface/wifi/registration-table/print': [
          {'mac-address': 'AA:BB:CC:00:00:02', 'signal': '-61', 'interface': 'wifi1'},
        ],
      });
      expect(r.role, CheckRole.link);
      expect(r.state, CheckState.ok);
      expect(r.signal, -61);
    });

    test('بلا صفٍّ أو بإشارةٍ غير مقروءة (0) ⇒ «إشارة الوصلة ما انقرت» كما هي — لا «0 dBm»', () {
      final d = dev(33, type: 'link', brand: 'mikrotik', protocol: 'api');
      final none = remote(d, ros({'ap': null, 'radio': true, 'reg_ok': true, 'peers': const []}));
      expect(texts(none), ['إشارة الوصلة ما انقرت']);
      final zero = remote(d, ros({'ap': null, 'radio': true, 'reg_ok': true, 'peers': [
        {'n': 'TWR-AP', 's': 0}
      ]}));
      expect(zero.signal, isNull);
      expect(texts(zero), ['إشارة الوصلة ما انقرت']);
    });
  });
}
