import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/bdcom_epon.dart';
import 'package:rad_mysvcs/api/olt_fiber_reads.dart';
import 'package:rad_mysvcs/api/olt_profile.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/fiber_network.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/services/fiber/fiber_monitor.dart';
import 'package:rad_mysvcs/services/fiber/fiber_onu.dart';
import 'package:rad_mysvcs/services/fiber/fiber_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_snmp_agent.dart';

/// مراقب الأولت من أوّله لآخره: أولتٌ وهميّ (SNMP في الذاكرة) يسقط منه صندوقٌ كامل ثمّ يرجع، وخادمٌ وهميّ يسجّل ما بُلِّغ.
class _Server implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<Map<String, dynamic>> bodies = [];
  bool autoBack = false;
  int nextId = 40;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(o);
    final b = o.data is Map ? Map<String, dynamic>.from(o.data as Map) : <String, dynamic>{};
    bodies.add(b);
    final p = o.uri.path;
    Object data = {'success': true};
    if (p == '/api/v2/admin/devices/fiber/rx' && o.method == 'GET') data = {'success': true, 'rows': []};
    if (p == '/api/v2/admin/devices/fiber/events' && o.method == 'POST') {
      data = {
        'success': true,
        'pushed': true,
        'event': {...b, 'id': nextId++, 'auto_back': autoBack, 'ended_at': null},
      };
    }
    final end = RegExp(r'^/api/v2/admin/devices/fiber/events/(\d+)/end$').firstMatch(p);
    if (end != null) {
      final started = bodies.firstWhere((x) => x.containsKey('scope_key'), orElse: () => {})['started_at'];
      data = {
        'success': true,
        'event': {
          'id': int.parse(end.group(1)!),
          'olt_id': 9,
          'kind': 'cut',
          'scope': 'box',
          'scope_key': 'box:2',
          'pon': 'EPON0/3',
          'box_id': 2,
          'onus': [for (var i = 1; i <= 12; i++) 'EPON0/3:$i'],
          'started_at': started,
          'ended_at': b['ended_at'],
          'auto_back': autoBack,
        },
      };
    }
    if (p.endsWith('/back-claim')) data = {'success': true, 'claimed': true};
    if (p == '/api/whatsapp/broadcast') data = {'success': true, 'summary': {'queued': 2}};
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}

  List<RequestOptions> to(String path, [String method = 'POST']) =>
      requests.where((r) => r.uri.path == path && r.method == method).toList();
}

const _profile = OltProfile(vendor: OltVendor.bdcom, oltLikely: true, identified: true, model: 'P3600-04');

class _Olt {
  final Map<int, bool> online = {for (var i = 1; i <= 24; i++) i: true};
  final agent = FakeSnmpAgent({});
  int up = 50000000;

  int ifIndexOf(int id) => 300 + id;

  VsolOltStats stats() {
    final onus = [
      for (var i = 1; i <= 24; i++)
        VsolOnu(ifIndex: ifIndexOf(i), slot: 0, ponPort: 3, onuId: i, online: online[i]!, technology: VsolPonTechnology.epon),
    ];
    return VsolOltStats(
      sysDescr: 'BDCOM(tm) P3600-04',
      profile: _profile,
      ponPorts: [
        VsolPonPort(index: 43, slot: 0, port: 3, up: true, rxBytes: 0, txBytes: 0, onuTotal: 24, onuOnline: onus.where((o) => o.online).length),
      ],
      onus: onus,
    );
  }

  /// يُسقط [ids] الآن: ifLastChange قبل ثوانٍ وسبب «wire-down».
  void drop(Iterable<int> ids, {bool withTimes = true, int reason = 8}) {
    for (final i in ids) {
      online[i] = false;
      if (withTimes) agent.put('${OltFiberReads.ifLastChangeOid}.${ifIndexOf(i)}', snmpTicks('', up - 300 + i * 40));
      agent.put('${OltFiberReads.bdcomDeregReason}.${ifIndexOf(i)}', snmpInt('', reason));
    }
    agent.put(OltFiberReads.sysUpTimeOid, snmpTicks('', up));
  }

  void restore(Iterable<int> ids) {
    for (final i in ids) {
      online[i] = true;
      agent.put('${OltFiberReads.ifLastChangeOid}.${ifIndexOf(i)}', snmpTicks('', up));
    }
  }
}

class _Backend extends FiberBackend {
  _Backend(this.olt);
  final _Olt olt;
  @override
  Future<String?> community(NetworkDevice d) async => 'fixture';
  @override
  SnmpV2c snmp(NetworkDevice d, String community) => olt.agent;
  @override
  Future<VsolOltStats> structure(NetworkDevice d, String community, OltProfile p, {Map<int, String>? knownNames}) async => olt.stats();
  @override
  Future<VsolOltStats> hot(NetworkDevice d, String community, VsolOltStats prev) async => prev;
}

NetworkDevice _dev() => NetworkDevice(
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

FiberLayout _layout() {
  var l = FiberLayout.empty;
  for (final b in [
    const FiberBox(id: 1, oltId: 9, pon: 'EPON0/3', name: 'موزّع رئيسي', kind: FiberNodeKind.splitter, ratio: 4),
    const FiberBox(id: 2, oltId: 9, pon: 'EPON0/3', name: 'صندوق 3-أ', parentId: 1, ratio: 16),
    const FiberBox(id: 3, oltId: 9, pon: 'EPON0/3', name: 'صندوق 3-ب', parentId: 1),
    const FiberBox(id: 4, oltId: 9, pon: 'EPON0/3', name: 'صندوق 3-ج', parentId: 1),
  ]) {
    l = l.withBox(b);
  }
  for (var i = 1; i <= 24; i++) {
    l = l.withRecord(FiberOnuRecord(
      oltId: 9,
      key: 'EPON0/3:$i',
      boxId: i <= 12 ? 2 : (i <= 19 ? 3 : 4),
      username: i <= 2 ? 'sub$i' : null,
    ));
  }
  return l;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Server server;
  late _Olt olt;
  var now = DateTime.utc(2026, 10, 27, 11, 32);

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth.token': 't', 'auth.admin_id': '2'});
    SharedPreferences.setMockInitialValues({});
    server = _Server();
    ApiClient.dio.httpClientAdapter = server;
    olt = _Olt();
    FiberMonitor.debugReset();
    FiberMonitor.backend = _Backend(olt);
    now = DateTime.utc(2026, 10, 27, 11, 32);
    FiberMonitor.clock = () => now;
    FiberStore.reset();
    FiberStore.debugSet(_layout());
  });

  tearDown(FiberMonitor.debugReset);

  test('صندوقٌ يسقط كلّه ⇒ عطلٌ واحد يُبلَّغ مرّةً بمكانه وسببه، ورجوعه ⇒ «رجع» مرّةً واحدة', () async {
    final m = FiberMonitor.of(_dev());
    await m.tick();
    expect(m.error, isNull);
    expect(m.onus.length, 24);
    expect(m.outages, isEmpty);
    expect(server.to('/api/v2/admin/devices/fiber/events'), isEmpty);

    now = now.add(const Duration(seconds: 15));
    olt.drop([for (var i = 1; i <= 12; i++) i]);
    await m.tick();
    expect(m.outages.single.scopeKey, 'box:2');
    final posts = server.to('/api/v2/admin/devices/fiber/events');
    expect(posts.length, 1);
    final body = posts.single.data as Map;
    expect(body['kind'], 'cut');
    expect(body['scope'], 'box');
    expect(body['box_id'], 2);
    expect((body['onus'] as List).length, 12);
    expect(body['title'], contains('صندوق 3-أ'));
    expect(body['body'], contains('قطع بالليف'));
    final drop = m.onus.firstWhere((o) => o.key == 'EPON0/3:1');
    expect(drop.reason, FiberDropReason.fiber);
    expect(drop.changedAt, isNotNull);

    // دورةٌ أخرى والعطل قائم ⇒ لا تبليغ ثانٍ
    now = now.add(const Duration(seconds: 15));
    await m.tick();
    expect(server.to('/api/v2/admin/devices/fiber/events').length, 1);

    // رجعت ⇒ «انتهى» مرّةً واحدة، والسبب يُمسح
    now = now.add(const Duration(minutes: 20));
    olt.restore([for (var i = 1; i <= 12; i++) i]);
    await m.tick();
    expect(m.outages, isEmpty);
    expect(server.to('/api/v2/admin/devices/fiber/events/40/end').length, 1);
    expect(m.onus.firstWhere((o) => o.key == 'EPON0/3:1').reason, isNull);
    await m.tick();
    expect(server.to('/api/v2/admin/devices/fiber/events/40/end').length, 1);
    expect(server.to('/api/whatsapp/broadcast'), isEmpty, reason: 'بلا «أرسل لهم لمّا يرجع» لا رسالة');
  });

  test('«لمّا يرجع النت أرسل لهم» ⇒ حجزٌ واحد من الخادم ثمّ رسالةٌ للمشتركين المربوطين وحدهم', () async {
    server.autoBack = true;
    final m = FiberMonitor.of(_dev());
    await m.tick();
    olt.drop([for (var i = 1; i <= 12; i++) i]);
    now = now.add(const Duration(seconds: 15));
    await m.tick();
    olt.restore([for (var i = 1; i <= 12; i++) i]);
    now = now.add(const Duration(minutes: 5));
    await m.tick();
    expect(server.to('/api/v2/admin/devices/fiber/events/40/back-claim').length, 1);
    final b = server.to('/api/whatsapp/broadcast').single.data as Map;
    expect(b['targetUsernames'], ['sub1', 'sub2']);
    expect(b['message'], FiberOltSettings.defaultBackMessage);
  });

  test('أولتٌ لا يعطي ifLastChange: سقوط الدورة الواحدة يتجمّع بلحظة رصدنا فيُكشف العطل نفسه', () async {
    final m = FiberMonitor.of(_dev());
    await m.tick();
    now = now.add(const Duration(seconds: 15));
    olt.drop([for (var i = 13; i <= 19; i++) i], withTimes: false, reason: 9);
    await m.tick();
    expect(m.outages.single.scopeKey, 'box:3');
    expect(m.outages.single.kind, FiberEventKind.power);
    expect(m.outages.single.startedAt, now);
  });

  test('جهازٌ واحد يسقط ليس عطلاً جماعيّاً — لكنّه يحمل سببه ولحظته للتشخيص', () async {
    final m = FiberMonitor.of(_dev());
    await m.tick();
    now = now.add(const Duration(seconds: 15));
    olt.drop([20], reason: 9);
    await m.tick();
    expect(m.outages, isEmpty);
    final o = m.onus.firstWhere((x) => x.key == 'EPON0/3:20');
    expect(o.online, isFalse);
    expect(o.reason, FiberDropReason.power);
    expect(server.to('/api/v2/admin/devices/fiber/events'), isEmpty);
  });

  test('الضوء يُسجَّل في الدفتر من قراءات الأولت، ولا community ⇒ رسالةٌ واضحة بلا قراءة', () async {
    olt.agent.put('${BdcomEpon.rxOid}.301', snmpInt('', -215));
    final m = FiberMonitor.of(_dev());
    await m.tick();
    expect(m.onus.firstWhere((o) => o.key == 'EPON0/3:1').rx, -21.5);
    expect(FiberStore.bookOf(9).data['EPON0/3:1'], isNotNull);

    FiberMonitor.backend = _NoCommunity(olt);
    final m2 = FiberMonitor.of(NetworkDevice(
      id: 10,
      adminId: '2',
      name: 'x',
      type: 'other',
      brand: 'bdcom',
      ip: '10.0.0.10',
      port: 161,
      lastStatus: 'online',
      createdAt: DateTime.utc(2026),
    ));
    await m2.tick();
    expect(m2.error, contains('community'));
    expect(m2.onus, isEmpty);
  });

  test('وضع الفنّي: حالة جهازٍ واحد من ifOperStatus ثمّ ضوؤه — والمفصول بلا قراءة', () async {
    final m = FiberMonitor.of(_dev());
    await m.tick();
    final o = m.onus.firstWhere((x) => x.key == 'EPON0/3:5').onu;
    olt.agent.put('${OltFiberReads.ifOperStatusOid}.305', snmpInt('', 1));
    olt.agent.put('${BdcomEpon.rxOid}.305', snmpInt('', -232));
    var r = await m.probeOne(o);
    expect(r.online, isTrue);
    expect(r.reading?.rxDbm, -23.2);
    olt.agent.put('${OltFiberReads.ifOperStatusOid}.305', snmpInt('', 2));
    r = await m.probeOne(o);
    expect(r.online, isFalse);
    expect(r.reading, isNull);
  });

  test('«التقط بالفصل»: أوّل جهازٍ ينفصل بعد البدء يُرجع، والذي لا يتغيّر فيه شيء ينتهي فارغاً', () async {
    for (var i = 1; i <= 24; i++) {
      olt.agent.put('${OltFiberReads.ifOperStatusOid}.${olt.ifIndexOf(i)}', snmpInt('', 1));
    }
    final m = FiberMonitor.of(_dev());
    await m.tick();
    final got = await m.catchChange(
      every: Duration.zero,
      onStart: (n) {
        expect(n, 24);
        olt.agent.put('${OltFiberReads.ifOperStatusOid}.${olt.ifIndexOf(7)}', snmpInt('', 2));
      },
    );
    expect(got.map((g) => g.onu.label), ['EPON0/3:7']);
    expect(got.single.nowOnline, isFalse);

    // لا تغيير ⇒ تنتهي النافذة فارغة (الساعة تتقدّم ثانيةً كلّ سؤال)
    olt.agent.put('${OltFiberReads.ifOperStatusOid}.${olt.ifIndexOf(7)}', snmpInt('', 2));
    FiberMonitor.clock = () => now = now.add(const Duration(seconds: 1));
    final none = await m.catchChange(window: const Duration(seconds: 6), every: Duration.zero);
    expect(none, isEmpty);
  });

  test('«التقط بالفصل» يُلغى بإغلاق النافذة', () async {
    final m = FiberMonitor.of(_dev());
    await m.tick();
    var calls = 0;
    final got = await m.catchChange(every: Duration.zero, cancelled: () => ++calls > 3);
    expect(got, isEmpty);
  });
}

class _NoCommunity extends _Backend {
  _NoCommunity(super.olt);
  @override
  Future<String?> community(NetworkDevice d) async => null;
}
