import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:rad_mysvcs/api/bdcom_epon.dart';
import 'package:rad_mysvcs/api/olt_fiber_reads.dart';
import 'package:rad_mysvcs/api/olt_profile.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/fiber_network.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/services/fiber/fiber_monitor.dart';

import 'fake_snmp_agent.dart';

/// أولت «شبكة الألياف» للاختبار: BDCOM وهميّ (SNMP في الذاكرة) بمنفذين وصناديق، وخادمٌ وهميّ يسجّل ما وصله.
/// تستعمله اختبارات الشاشات ولقطات المراجعة.
class FiberTestServer implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  int nextBox = 70;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(o);
    final p = o.uri.path;
    final b = o.data is Map ? Map<String, dynamic>.from(o.data as Map) : <String, dynamic>{};
    Object data = {'success': true};
    if (p == '/api/v2/admin/devices/fiber/rx' && o.method == 'GET') data = {'success': true, 'rows': []};
    if (p == '/api/v2/admin/devices/fiber/events' && o.method == 'POST') {
      data = {'success': true, 'pushed': true, 'event': {...b, 'id': 501, 'auto_back': false, 'ended_at': null}};
    }
    if (p == '/api/v2/admin/devices/fiber/onus') data = {'success': true, 'saved': (b['records'] as List?)?.length ?? 0};
    if (p.startsWith('/api/v2/admin/devices/fiber/boxes/') && o.method == 'PUT') {
      data = {'success': true, 'box': {...b, 'id': nextBox++}};
    }
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}

  List<RequestOptions> to(String path, [String method = 'POST']) =>
      requests.where((r) => r.uri.path == path && r.method == method).toList();
}

const fiberTestProfile = OltProfile(vendor: OltVendor.bdcom, oltLikely: true, identified: true, model: 'P3600-04');

/// أولتٌ بمنفذين: EPON0/3 (٢٤ جهازاً بثلاثة صناديق) وEPON0/1 (٦ أجهزة بلا صناديق).
class FiberTestOlt {
  final Map<int, bool> online = {
    for (var i = 1; i <= 24; i++) 300 + i: true,
    for (var i = 1; i <= 6; i++) 100 + i: true,
  };
  final agent = FakeSnmpAgent({});
  final int up = 50000000;

  FiberTestOlt() {
    for (final e in online.entries) {
      agent.put('${OltFiberReads.ifOperStatusOid}.${e.key}', snmpInt('', 1));
      // ضوءٌ متدرّج: الصندوق الأوّل جيّد، والثاني فيه حدّيّ وضعيف.
      final i = e.key % 100;
      final rx = e.key > 300 ? (i <= 12 ? -195 - i * 3 : (i == 15 ? -268 : (i == 16 ? -281 : -230))) : -210;
      agent.put('${BdcomEpon.rxOid}.${e.key}', snmpInt('', rx));
      agent.put('${BdcomEpon.txOid}.${e.key}', snmpInt('', 23));
      agent.put('${BdcomEpon.tempOid}.${e.key}', snmpInt('', 47 * 256));
      agent.put('${BdcomEpon.voltOid}.${e.key}', snmpInt('', 33000));
    }
    agent.put(OltFiberReads.sysUpTimeOid, snmpTicks('', up));
  }

  VsolOltStats stats() {
    VsolOnu onu(int ifIndex, int port, int id) =>
        VsolOnu(ifIndex: ifIndex, slot: 0, ponPort: port, onuId: id, online: online[ifIndex]!, technology: VsolPonTechnology.epon);
    final onus = [
      for (var i = 1; i <= 24; i++) onu(300 + i, 3, i),
      for (var i = 1; i <= 6; i++) onu(100 + i, 1, i),
    ];
    return VsolOltStats(
      sysDescr: 'BDCOM(tm) P3600-04',
      profile: fiberTestProfile,
      ponPorts: const [
        VsolPonPort(index: 41, slot: 0, port: 1, up: true, rxBytes: 0, txBytes: 0, onuTotal: 6, onuOnline: 6),
        VsolPonPort(index: 43, slot: 0, port: 3, up: true, rxBytes: 0, txBytes: 0, onuTotal: 24, onuOnline: 24),
      ],
      onus: onus,
    );
  }

  /// يُسقط الأجهزة الآن بقطع ليف (8) أو كهرباء (9)، بلحظةٍ قبل ثوانٍ.
  void drop(Iterable<int> ifIndexes, {int reason = 8}) {
    for (final i in ifIndexes) {
      online[i] = false;
      agent.put('${OltFiberReads.ifOperStatusOid}.$i', snmpInt('', 2));
      agent.put('${OltFiberReads.ifLastChangeOid}.$i', snmpTicks('', up - 500 + (i % 100) * 20));
      agent.put('${OltFiberReads.bdcomDeregReason}.$i', snmpInt('', reason));
    }
  }

  /// فصلٌ يراه عمود الحالة وحده (قبل أن يلحقه المسح) — «التقط بالفصل».
  void unplug(int ifIndex) => agent.put('${OltFiberReads.ifOperStatusOid}.$ifIndex', snmpInt('', 2));
}

class FiberTestBackend extends FiberBackend {
  FiberTestBackend(this.olt);
  final FiberTestOlt olt;
  @override
  Future<String?> community(NetworkDevice d) async => 'fixture';
  @override
  SnmpV2c snmp(NetworkDevice d, String community) => olt.agent;
  @override
  Future<VsolOltStats> structure(NetworkDevice d, String community, OltProfile p, {Map<int, String>? knownNames}) async => olt.stats();
  @override
  Future<VsolOltStats> hot(NetworkDevice d, String community, VsolOltStats prev) async => prev;
}

NetworkDevice fiberTestDevice() => NetworkDevice(
      id: 9,
      adminId: '2',
      name: 'أولت المركز',
      type: 'other',
      brand: 'bdcom',
      model: 'BDCOM P3600-04',
      ip: '10.0.0.9',
      port: 161,
      apiPort: 161,
      protocol: 'snmp',
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime.utc(2026),
    );

FiberLayout fiberTestLayout() {
  var l = FiberLayout.empty;
  for (final b in [
    const FiberBox(id: 1, oltId: 9, pon: 'EPON0/3', name: 'موزّع رئيسي', kind: FiberNodeKind.splitter, ratio: 4, location: 'عمود الساحة'),
    const FiberBox(id: 2, oltId: 9, pon: 'EPON0/3', name: 'صندوق 3-أ', parentId: 1, ratio: 16, lat: 33.3, lng: 44.4),
    const FiberBox(id: 3, oltId: 9, pon: 'EPON0/3', name: 'صندوق 3-ب', parentId: 1, ratio: 8),
    const FiberBox(id: 4, oltId: 9, pon: 'EPON0/3', name: 'صندوق 3-ج', parentId: 1, ratio: 8),
  ]) {
    l = l.withBox(b);
  }
  for (var i = 1; i <= 22; i++) {
    l = l.withRecord(FiberOnuRecord(
      oltId: 9,
      key: 'EPON0/3:$i',
      boxId: i <= 12 ? 2 : (i <= 17 ? 3 : 4),
      username: i <= 3 ? 'sub$i' : null,
      source: i <= 3 ? FiberLinkSource.manual : null,
    ));
  }
  return l.withSettings(const FiberOltSettings(oltId: 9, techName: 'أبو علي', techPhone: '07701234567'));
}

Subscriber fiberTestSub(String u, {String first = 'حيدر', String last = 'علي'}) =>
    Subscriber(username: u, firstname: first, lastname: last, phone: '07801112233', isOnlineFlag: true);

