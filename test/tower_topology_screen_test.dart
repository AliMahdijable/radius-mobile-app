// «أبراجي» و«الترابط» — محاكاةٌ كاملة بلا شبكة (١١ نوفمبر). المالك: «واحد سوه ٤ مناطق كل منطقة بيها اجهزه خاصه بيها…
// النظرة ع البرج رح تصير ٤ ابراج القسم ينتقل بينهم… الترابط… برج a منطي ٣ لنكات ماستر والابراج الفرعي سليف وياه بحيث يظهر
// رسم البرج بشكل مصغر حتى يكفي للهاتف ان اكو برج رئيسي وموزع ويبين سير الترفك من الرئيسي للفرعيات».
//
// الخادم وهميّ بحالة (أجهزة · مناطق · لنكات، بقواعد server/towerRoutes.js)، وقراءات أطراف اللنكات تُحقن بقارئٍ مزيّف
// ([TowerTopologyScreen.debugProbe]). بـ`VISUAL_OUT=<مجلّد>` تُحفظ لقطة كلّ مشهد للنظر.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/device_reach.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';
import 'package:rad_mysvcs/core/platform/desktop_layout.dart';
import 'package:rad_mysvcs/models/device_region.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_assign_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_link_editor.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_link_probe.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_reading.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_topology_logic.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_topology_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/towers_screen.dart';
import 'package:rad_mysvcs/services/deep_probe_scheduler.dart';
import 'package:rad_mysvcs/services/device_read_health.dart';
import 'package:rad_mysvcs/services/device_stats_cache.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'visual_perm/visual_perm_harness.dart';

// ═══════════════════════════ البيانات ═══════════════════════════

Map<String, Object?> _d(int id, String name, int? region, {String type = 'sector', String brand = 'mikrotik', String? model, String? mac, String status = 'online'}) => {
      'id': id,
      'admin_id': 'supernet:12',
      'region_id': region,
      'name': name,
      'type': type,
      'brand': brand,
      'model': model ?? (type == 'link' ? 'LHG 5 ac' : (type == 'sector' ? 'BaseBox 5' : (type == 'switch' ? 'CRS326-24G-2S+' : 'CCR1009-7G-1C-1S+'))),
      'ip': '10.${region ?? 0}.0.${id % 250}',
      'port': 80,
      'api_port': 8728,
      'protocol': 'api',
      'mac': mac,
      'has_credentials': 1,
      'last_status': status,
      'last_probed_at': DateTime.now().toUtc().toIso8601String(),
      'created_at': '2026-10-01T00:00:00.000Z',
    };

Map<String, Object?> _r(int id, String name, String? color) =>
    {'id': id, 'name': name, 'color': color, 'sort_order': 0, 'device_count': 0, 'created_at': '2026-10-01T00:00:00.000Z'};

/// أربع مناطق كما وصف المالك: الرئيسيّ بثلاثة لنكات ماستر، وثلاثة فرعيّة بطرف سليف وسكاترها.
List<Map<String, Object?>> fourRegions() => [
      _r(1, 'البرج الرئيسي', '#2563EB'),
      _r(2, 'برج الحي الصناعي', '#16A34A'),
      _r(3, 'برج المعامل', '#EA580C'),
      _r(4, 'برج الجامعة', '#7C3AED'),
    ];

List<Map<String, Object?>> fourTowersDevices() => [
      _d(101, 'CCR الرئيسي', 1, type: 'router'),
      _d(102, 'سويج الرئيسي', 1, type: 'switch'),
      _d(111, 'لنك الحي (ماستر)', 1, type: 'link', brand: 'ubnt', model: 'airFiber 60 LR', mac: '78:8A:20:00:01:11'),
      _d(112, 'لنك المعامل (ماستر)', 1, type: 'link', mac: '48:8F:5A:00:01:12'),
      _d(113, 'لنك الجامعة (ماستر)', 1, type: 'link', mac: '48:8F:5A:00:01:13'),
      _d(121, 'سكتر 1 شمال', 1),
      _d(122, 'سكتر 2 جنوب', 1),
      _d(211, 'لنك الحي (سليف)', 2, type: 'link', brand: 'ubnt', model: 'airFiber 60 LR', mac: '78:8A:20:00:02:11'),
      _d(201, 'سويج الحي', 2, type: 'switch'),
      _d(221, 'سكتر الحي 1', 2),
      _d(222, 'سكتر الحي 2', 2),
      _d(311, 'لنك المعامل (سليف)', 3, type: 'link', mac: '48:8F:5A:00:03:11'),
      _d(301, 'راوتر المعامل', 3, type: 'router'),
      _d(321, 'سكتر المعامل', 3),
      _d(411, 'لنك الجامعة (سليف)', 4, type: 'link', mac: '48:8F:5A:00:04:11'),
      _d(401, 'سويج الجامعة', 4, type: 'switch'),
      _d(421, 'سكتر الجامعة 1', 4),
      _d(422, 'سكتر الجامعة 2', 4),
      _d(423, 'سكتر الجامعة 3', 4),
    ];

Map<String, Object?> _l(int id, int a, int b, {String kind = 'radio', String? aPort, String? bPort}) => {
      'id': id,
      'a_device_id': a,
      'b_device_id': b,
      'label': null,
      'kind': kind,
      'a_port': aPort,
      'b_port': bPort,
      'updated_at': '2026-11-10T22:00:00.000Z',
    };

/// كيبلٌ ضوئيّ بين سويجين بمنفذيه.
Map<String, Object?> _f(int id, int a, int b, {String? aPort, String? bPort}) => _l(id, a, b, kind: 'fiber', aPort: aPort, bPort: bPort);

List<Map<String, Object?>> starLinks() => [_l(1, 111, 211), _l(2, 112, 311), _l(3, 113, 411)];

/// قراءة سويج: منافذه بحالها وما يعبرها (rx ما يستقبله المنفذ، tx ما يرسله) وسرعتها وضوء الـSFP.
TowerReading _sw(List<PortTraffic> ports) => TowerReading(at: DateTime.now(), ports: ports);

PortTraffic _port(String name, {bool up = true, int? rx, int? tx, String? speed, double? light}) =>
    PortTraffic(name: name, up: up, rxBps: rx, txBps: tx, linkSpeed: speed, sfpRx: light);

TowerReading _rd({String? mode, int? rx, int? tx, int? signal, int? ccq, int? freq, List<PeerLink> peers = const []}) => TowerReading(
      at: DateTime.now(),
      wireless: true,
      mode: mode,
      clients: peers.isEmpty ? 1 : peers.length,
      radioRxBps: rx,
      radioTxBps: tx,
      downBps: rx,
      upBps: tx,
      signal: signal,
      quality: ccq,
      frequency: freq,
      channelWidth: 40,
      peers: peers,
    );

/// قراءات الأطراف: الحي ممتاز، المعامل متوسّط، الجامعة ضعيف.
Map<int, TowerReading> starReadings() => {
      111: _rd(mode: 'ap', tx: 186000000, rx: 21500000, signal: -51, ccq: 99),
      211: _rd(mode: 'sta', rx: 184000000, tx: 21000000, signal: -52, ccq: 98),
      112: _rd(mode: 'ap-bridge', tx: 47000000, rx: 6400000, signal: -71, ccq: 84),
      311: _rd(mode: 'station', rx: 46200000, tx: 6200000, signal: -73, ccq: 81),
      113: _rd(mode: 'ap-bridge', tx: 12600000, rx: 1200000, signal: -83, ccq: 52),
      411: _rd(mode: 'station', rx: 12400000, tx: 1100000, signal: -84, ccq: 47),
    };

// ═══════════════════════════ الخادم الوهميّ ═══════════════════════════

class FakeTowersApi implements HttpClientAdapter {
  FakeTowersApi({required this.devices, required this.regions, List<Map<String, Object?>>? links}) : links = links ?? [];

  final List<Map<String, Object?>> devices;
  final List<Map<String, Object?>> regions;
  final List<Map<String, Object?>> links;
  bool linksReady = true;

  /// الخادم بعد الهجرة 087 (الكيبل الضوئيّ ومنفذاه) — false: خادمٌ قبلها.
  bool fiberReady = true;
  bool towersFail = false;
  int _nextLink = 50;
  int _nextRegion = 20;

  /// «METHOD path» لكلّ طلب، وأجسام الكتابة.
  final calls = <String>[];
  final bodies = <String, List<Map<String, dynamic>>>{};

  List<String> writes() => [for (final c in calls) if (!c.startsWith('GET ')) c];

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  int? _region(int deviceId) => devices.firstWhere((d) => d['id'] == deviceId, orElse: () => const {})['region_id'] as int?;
  bool _has(int id) => devices.any((d) => d['id'] == id);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final p = o.uri.path;
    final m = o.method.toUpperCase();
    calls.add('$m $p');
    final data = o.data is Map ? Map<String, dynamic>.from(o.data as Map) : <String, dynamic>{};
    if (m != 'GET') bodies.putIfAbsent('$m $p', () => []).add(data);
    const base = '/api/v2/admin/devices';

    if (p.endsWith('/credentials')) return _json(200, {'success': true, 'credentials': {'user': 'admin', 'pass': 'x'}});
    if (m == 'GET' && p == base) return _json(200, {'success': true, 'data': devices});
    if (m == 'GET' && p == '$base/regions') return _json(200, {'success': true, 'data': regions});
    if (m == 'POST' && p == '$base/regions') {
      final r = _r(_nextRegion++, '${data['name']}', data['color'] as String?);
      regions.add(r);
      return _json(200, {'success': true, 'data': r});
    }
    if (m == 'GET' && p == '$base/towers') {
      if (towersFail) return _json(500, {'success': false, 'message': 'تعذّر جلب ترتيب البرج'});
      return _json(200, {
        'success': true,
        'towers': [],
        'placements': [],
        'links': linksReady ? links : [],
        'links_ready': linksReady,
        'fiber_ready': linksReady && fiberReady,
      });
    }
    // خانة فرادة الطرف الفرعيّ — كالخادم (server/towerRoutes.js slotOf)
    String slot(Map<String, Object?> l) =>
        l['kind'] != 'fiber' ? '' : (l['b_port'] != null ? 'p:${'${l['b_port']}'.toLowerCase()}' : 'a:${l['a_device_id']}');
    String? port(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    if (m == 'POST' && p == '$base/towers/links') {
      final a = data['a_device_id'] as int;
      final b = data['b_device_id'] as int;
      final kind = (data['kind'] ?? 'radio') as String;
      final fiber = kind == 'fiber';
      if (!_has(a) || !_has(b)) return _json(404, {'success': false, 'message': 'الجهاز غير موجود'});
      if ((_region(a) ?? 0) == (_region(b) ?? 0)) {
        return _json(400, {'success': false, 'message': fiber ? 'الجهازان في البرج نفسه — الكيبل يربط برجين' : 'الجهازان في البرج نفسه — اللنك يربط برجين'});
      }
      if (fiber && !fiberReady) return _json(409, {'success': false, 'message': 'الربط بالكيبل الضوئيّ غير متاح الآن — حاول بعد قليل'});
      final next = _l(_nextLink, a, b, kind: kind, aPort: fiber ? port(data['a_port']) : null, bPort: fiber ? port(data['b_port']) : null);
      if (links.any((l) => l['a_device_id'] == b && l['b_device_id'] == a)) {
        return _json(409, {'success': false, 'message': 'هذا اللنك مربوطٌ بالاتّجاه المعاكس — اقلب اتّجاهه'});
      }
      final pair = links.where((l) => l['a_device_id'] == a && l['b_device_id'] == b).toList();
      if (pair.any((l) => l['kind'] != kind)) return _json(409, {'success': false, 'message': 'هذان الجهازان مربوطان — غيّر نوع الربط من تفاصيله'});
      final same = pair.where((l) => !fiber || next['b_port'] == null || l['b_port'] == null || slot(l) == slot(next)).firstOrNull;
      if (same != null) return _json(200, {'success': true, 'link': same, 'existed': true});
      if (links.any((l) => l['b_device_id'] == b && slot(l) == slot(next))) {
        return _json(409, {
          'success': false,
          'message': fiber ? 'منفذ الطرف الفرعيّ مربوطٌ بكيبلٍ آخر — اختر منفذاً غيره' : 'الطرف الفرعيّ مربوطٌ بلنكٍ آخر — احذف ربطه أوّلاً',
        });
      }
      _nextLink++;
      links.add(next);
      return _json(200, {'success': true, 'link': next});
    }
    final linkId = RegExp('^$base/towers/links/(\\d+)\$').firstMatch(p)?.group(1);
    if (linkId != null) {
      final i = links.indexWhere((l) => l['id'] == int.parse(linkId));
      if (i < 0) return _json(404, {'success': false, 'message': 'الربط غير موجود'});
      if (m == 'DELETE') {
        links.removeAt(i);
        return _json(200, {'success': true});
      }
      if (m == 'PUT') {
        final l = links[i];
        final wantsFiber = data['kind'] == 'fiber' || port(data['a_port']) != null || port(data['b_port']) != null;
        if (wantsFiber && !fiberReady) return _json(409, {'success': false, 'message': 'الربط بالكيبل الضوئيّ غير متاح الآن — حاول بعد قليل'});
        var next = {...l};
        if (data.containsKey('kind')) next['kind'] = data['kind'];
        if (data.containsKey('a_port')) next['a_port'] = port(data['a_port']);
        if (data.containsKey('b_port')) next['b_port'] = port(data['b_port']);
        if (data['flip'] == true) {
          next = {...next, 'a_device_id': next['b_device_id'], 'b_device_id': next['a_device_id'], 'a_port': next['b_port'], 'b_port': next['a_port']};
        }
        if (next['kind'] != 'fiber') next = {...next, 'a_port': null, 'b_port': null};
        if (links.any((x) => x['id'] != l['id'] && x['b_device_id'] == next['b_device_id'] && slot(x) == slot(next))) {
          return _json(409, {
            'success': false,
            'message': next['kind'] == 'fiber' ? 'منفذ الطرف الفرعيّ مربوطٌ بكيبلٍ آخر — اختر منفذاً غيره' : 'الطرف الفرعيّ مربوطٌ بلنكٍ آخر — احذف ربطه أوّلاً',
          });
        }
        links[i] = next;
        return _json(200, {'success': true, 'link': next});
      }
    }
    final assign = RegExp('^$base/regions/(\\d+)/assign\$').firstMatch(p)?.group(1);
    if (m == 'POST' && assign != null) {
      final region = int.parse(assign);
      final ids = [for (final x in data['device_ids'] as List) x as int];
      var moved = 0;
      for (final d in devices) {
        if (!ids.contains(d['id'])) continue;
        final to = region == 0 ? null : region;
        if (d['region_id'] != to) moved++;
        d['region_id'] = to;
      }
      return _json(200, {'success': true, 'region_id': region, 'devices': ids.length, 'moved': moved});
    }
    return _json(200, {'success': true, 'data': []});
  }

  @override
  void close({bool force = false}) {}
}

/// ما يراه القارئ المزيّف — يبقى بين شاشةٍ وأخرى (القارئ نفسه يُتلف مع شاشته ويُنشأ غيره).
class ProbeData {
  ProbeData(this.readings);

  final Map<int, TowerReading> readings;
  final Set<int> down = {};
  final Set<int> settings = {};
  bool off = false;
  Set<int> ends = {};
  final List<int> readOnceCalls = [];
  FakeProbe? live;

  /// كأنّ دورة قراءةٍ انتهت.
  void poke() => live?.poke();
}

/// قارئٌ مزيّف: القراءات كما تُحقن، و«لا يردّ» لمن في [ProbeData.down].
class FakeProbe extends TowerLinkProbe {
  FakeProbe(this.data) {
    data.live = this;
  }

  final ProbeData data;

  void poke() => notifyListeners();

  @override
  void start() {}
  @override
  void stop() {}
  @override
  void refreshNow({int? only}) {}
  @override
  void setDevices({required Iterable<NetworkDevice> ends, Iterable<NetworkDevice> others = const [], Iterable<NetworkDevice> scanOnce = const []}) =>
      data.ends = {for (final d in ends) d.id};
  @override
  bool get offNetwork => data.off;
  @override
  TowerReading? readingOf(int id) => data.off || data.down.contains(id) || data.settings.contains(id) ? null : data.readings[id];
  @override
  Map<int, TowerReading> get known => Map.unmodifiable(data.readings);
  @override
  bool isDown(int id) => !data.off && data.down.contains(id);
  @override
  bool needsSettings(int id) => data.settings.contains(id);
  @override
  String? skipReasonOf(int id) => null;

  /// منتقي منفذ الكيبل يقرأ الجهاز الآن — هنا ما حُقن له (أو لا شيء: «تعذّرت قراءته»).
  @override
  Future<TowerReading?> readOnce(NetworkDevice d) async {
    data.readOnceCalls.add(d.id);
    return data.off ? null : data.readings[d.id];
  }

  @override
  void dispose() {
    if (identical(data.live, this)) data.live = null;
    super.dispose();
  }
}

// ═══════════════════════════ العدّة ═══════════════════════════

const p360 = VisualDevice('_360', Size(360, 780), 3);
const p390 = VisualDevice('_390', Size(390, 844), 3);
const p430 = VisualDevice('_430', Size(430, 932), 3);
const p390dark = VisualDevice('_390_dark', Size(390, 844), 3, dark: true);
const p320 = VisualDevice('_320', Size(320, 700), 3);
const tablet = VisualDevice('_tablet', Size(820, 1180), 2);

/// كلّ الصفحة في صورةٍ واحدة (الطول يكفي) بالعرض نفسه.
VisualDevice tall(VisualDevice d, [double h = 1500]) => VisualDevice('${d.tag}_full', Size(d.size.width, h), 2, dark: d.dark);

Future<void> snap(WidgetTester t, String name, VisualDevice d) async {
  final ex = t.takeException();
  expect(ex, isNull, reason: 'استثناء قبل لقطة $name:\n$ex');
  final out = Platform.environment['VISUAL_OUT'] ?? '';
  if (out.isEmpty) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(visualRootKey));
  final png = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: d.dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final f = File('$out/$name${d.tag}.png');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(png!, flush: true);
}

/// النصّ بلا أحرف العزل الاتّجاهيّ (الشاشة تعزل المقاطع اللاتينيّة — `iso`/`isoJoin`) — للمطابقة بما يقرؤه الوكيل.
String _strip(String s) => s.replaceAll(RegExp(r'[\u2066-\u2069\u200e\u200f\u202a-\u202e]'), '');
Finder plain(String s) =>
    find.byWidgetPredicate((w) => w is Text && w.data != null && _strip(w.data!) == s, description: 'نصّ «$s»');
Finder plainHas(String s) =>
    find.byWidgetPredicate((w) => w is Text && w.data != null && _strip(w.data!).contains(s), description: 'نصّ فيه «$s»');

List<NetworkDevice> devicesOf(FakeTowersApi api) => [for (final d in api.devices) NetworkDevice.fromJson(Map<String, dynamic>.from(d))];
List<DeviceRegion> regionsOf(FakeTowersApi api) => [for (final r in api.regions) DeviceRegion.fromJson(Map<String, dynamic>.from(r))];

void main() {
  setUpAll(visualSetUpAll);

  late FakeTowersApi api;
  late ProbeData probe;

  Future<void> boot(
    WidgetTester t, {
    List<Map<String, Object?>>? devices,
    List<Map<String, Object?>>? regions,
    List<Map<String, Object?>>? links,
    Map<int, TowerReading>? readings,
    Scenario scenario = s1bSasOwner,
  }) async {
    await visualSetUp(scenario);
    api = FakeTowersApi(devices: devices ?? fourTowersDevices(), regions: regions ?? fourRegions(), links: links ?? starLinks());
    ApiClient.dio.httpClientAdapter = api;
    probe = ProbeData(readings ?? starReadings());
    TowerTopologyScreen.debugProbe = () => FakeProbe(probe);
    TowersScreen.debugResetLast();
    NetworkDevicesApi.invalidateCredentialsCache();
    DeviceStatsCache.instance.clear();
    DeepProbeScheduler.instance.resetForTest();
    DeviceReach.resetForTest();
    DeviceReadHealth.instance.debugReset();
    // شاشة البرج نفسها (حين يُفتح برج) تقرأ أجهزته: كلّها تردّ وقراءتها تفشل — لا شبكة حقيقيّة
    NetworkDevicesApi.debugIcmpUsable = true;
    NetworkDevicesApi.debugService = (_) async => (status: 'online', responseMs: 4, packetLoss: 0.0);
    NetworkDevicesApi.icmpProbe = (ip, n) async => (status: 'online', responseMs: 4, packetLoss: 0.0);
    DeviceReach.debugConnect = (host, port, timeout) async => (port: port, reply: PortReply.silent, ms: null);
    MikrotikApi.debugFetch = () async => throw MikrotikException('انتهت مهلة الاتّصال بالجهاز', code: 'timeout');
    UbntApi.debugFetch = () async => throw Exception('timeout');
    addTearDown(() async {
      TowerTopologyScreen.debugProbe = null;
      MikrotikApi.debugFetch = null;
      UbntApi.debugFetch = null;
      NetworkDevicesApi.debugIcmpUsable = null;
      NetworkDevicesApi.debugService = null;
      DeviceReach.resetForTest();
      DeviceReadHealth.instance.debugReset();
      DeepProbeScheduler.instance.resetForTest();
      DeviceStatsCache.instance.clear();
      await visualTearDown();
    });
  }

  Future<void> openHub(WidgetTester t, VisualDevice d, {int? openRegionId}) async {
    await pumpVisual(t, d, home: (_) => TowersScreen(devices: devicesOf(api), regions: regionsOf(api), openRegionId: openRegionId));
    await settle(t, seconds: 2);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 35));
  }

  String canvasOrder(WidgetTester t, List<int> towers) {
    // أماكن الأبراج على الرسم: «id@x,y» بالترتيب المعطى
    return [
      for (final id in towers)
        () {
          final c = t.getCenter(find.byKey(ValueKey('topo-node-$id')));
          return '$id@${c.dx.round()},${c.dy.round()}';
        }(),
    ].join(' ');
  }

  group('الترابط — الرسم', () {
    testWidgets('٤ مناطق ⇒ ٤ أبراج: الرئيسيّ أعلى وحده والثلاثة تحته، وفوق كلّ فرعيّ ما ينزل له، بكلّ عرض هاتف', (t) async {
      for (final d in [p360, p390, p430, p320]) {
        await boot(t);
        await openHub(t, d);
        expect(find.text('ترابط الأبراج'), findsOneWidget);
        expect(find.text('4 أبراج · 3 لنكات'), findsOneWidget);
        expect(find.text('مباشر'), findsOneWidget);
        // النقل بالجهتين (المالك: «لازم تظهر النقل بالجهتين rx/tx»): الملخّص ما ينزل (243) وتحته ما يصعد (21 + 6.2 + 1.1)
        expect(plain('28 Mbps'), findsOneWidget, reason: '${d.tag}: ما يصعد للرئيسي في الملخّص');
        expect(find.text('إلى 3 أبراج'), findsNothing);
        // الرئيسيّ فوق الفرعيّات، والثلاثة على صفٍّ واحد داخل الشاشة
        final main = t.getRect(find.byKey(const ValueKey('topo-node-1')));
        final subs = [for (final id in [2, 3, 4]) t.getRect(find.byKey(ValueKey('topo-node-$id')))];
        for (final s in subs) {
          expect(s.top > main.bottom, isTrue, reason: '${d.tag}: الفرعيّ تحت الرئيسيّ');
          expect(s.left >= 0 && s.right <= d.size.width, isTrue, reason: '${d.tag}: داخل الشاشة $s');
          expect(s.top, subs.first.top, reason: '${d.tag}: صفٌّ واحد');
        }
        for (var i = 0; i < subs.length; i++) {
          for (var j = i + 1; j < subs.length; j++) {
            expect(subs[i].overlaps(subs[j]), isFalse, reason: '${d.tag}: لا تراكب');
          }
        }
        expect((main.center.dx - d.size.width / 2).abs() < 1, isTrue, reason: 'الرئيسيّ في الوسط');
        // الأدوار وما ينزل لكلّ فرعيّ
        expect(find.text('رئيسي'), findsOneWidget);
        expect(find.text('فرعي'), findsNWidgets(3));
        for (final v in ['184 Mbps', '46 Mbps', '12 Mbps']) {
          expect(find.textContaining(v), findsWidgets, reason: '${d.tag}: $v');
        }
        // حبّة كلّ وصلةٍ فوق برجها الفرعيّ مباشرةً ولا تخرج عن الشاشة
        for (final id in [2, 3, 4]) {
          final pill = t.getRect(find.byKey(ValueKey('topo-pill-1-$id')));
          final node = t.getRect(find.byKey(ValueKey('topo-node-$id')));
          expect((pill.center.dx - node.center.dx).abs() < 1, isTrue);
          expect(pill.bottom <= node.top + 1 && pill.top > main.bottom, isTrue, reason: '${d.tag}: الحبّة بين الصفّين');
          expect(pill.left >= 0 && pill.right <= d.size.width, isTrue);
        }
        // كلّ حبّةٍ بسطرين: ما ينزل للفرعيّ وتحته ما يصعد منه — والنازل فوق الصاعد
        for (final (id, downText, upText) in [(2, '184 Mbps', '21 Mbps'), (3, '46 Mbps', '6.2 Mbps'), (4, '12 Mbps', '1.1 Mbps')]) {
          final pill = find.byKey(ValueKey('topo-pill-1-$id'));
          final dn = find.descendant(of: pill, matching: plain(downText));
          final up = find.descendant(of: pill, matching: plain(upText));
          expect(dn, findsOneWidget, reason: '${d.tag}: ينزل لـ$id');
          expect(up, findsOneWidget, reason: '${d.tag}: يصعد من $id');
          expect(t.getCenter(dn).dy < t.getCenter(up).dy, isTrue);
          final box = t.getRect(pill);
          for (final f in [dn, up]) {
            final r = t.getRect(f);
            expect(r.left >= box.left - 0.5 && r.right <= box.right + 0.5, isTrue, reason: '${d.tag}: الرقم داخل الحبّة $r ⊂ $box');
          }
        }
        expect(find.text('يصعد للرئيسي'), findsOneWidget, reason: 'مفتاح الرسم يسمّي الجهتين');
        // الملخّص: مجموع ما يوزّعه الرئيسيّ، واللنكات الشغّالة
        expect(find.text('يوزّع الرئيسي'), findsOneWidget);
        expect(find.textContaining('243 Mbps'), findsOneWidget, reason: '184 + 46.2 + 12.4');
        expect(find.textContaining('3/3'), findsOneWidget);
        expect(find.text('1 ضعيف'), findsOneWidget);
        expect(probe.ends, {111, 211, 112, 311, 113, 411}, reason: 'أطراف اللنكات وحدها تُقرأ');
        await snap(t, 'star4', d);
        await close(t);
      }
    });

    testWidgets('لقطات الصفحة كاملةً — فاتح وداكن ولوح', (t) async {
      for (final d in [tall(p390), tall(p390dark), tall(p360), tall(tablet, 1180)]) {
        await boot(t);
        await openHub(t, d);
        expect(find.text('اللنكات · 3'), findsOneWidget);
        expect(find.textContaining('القراءات من طرفَي كلّ وصلة'), findsOneWidget);
        await snap(t, 'star4_page', d);
        await close(t);
      }
    });

    testWidgets('🚨 لنكٌ واقع: حبّته «واقع» والباقي يسير — و«واقع» بحكم «لا يردّ» وحده', (t) async {
      await boot(t);
      probe.down.add(411);
      await openHub(t, tall(p390));
      expect(find.text('واقع'), findsWidgets);
      expect(find.text('1 واقع'), findsOneWidget);
      expect(find.textContaining('2/3'), findsOneWidget);
      expect(find.text('طرف الفرعي لا يردّ'), findsOneWidget);
      expect(find.textContaining('230 Mbps'), findsOneWidget, reason: 'الواقع لا يُحسب في ما يوزّعه الرئيسيّ');
      expect(plain('27 Mbps'), findsOneWidget, reason: 'ما يصعد من البرجين الشغّالين (21 + 6.2) — الواقع لا يُعدّ');
      // الحبّة الواقعة سطرٌ واحد «واقع»، والشغّالتان بسطرين
      expect(t.getSize(find.byKey(const ValueKey('topo-pill-1-4'))).height, 22);
      expect(t.getSize(find.byKey(const ValueKey('topo-pill-1-2'))).height, 36);
      await snap(t, 'link_down', tall(p390));
      // عاد يردّ ⇒ يعود بلا إعادة فتح
      probe.down.clear();
      probe.poke();
      await settle(t, seconds: 1);
      expect(find.text('1 واقع'), findsNothing);
      expect(find.textContaining('3/3'), findsOneWidget);
      expect(plain('28 Mbps'), findsOneWidget);
      // الثلاثة واقعة ⇒ لا رقم ولا «إلى»
      probe.down.addAll([211, 311, 411]);
      probe.poke();
      await settle(t, seconds: 1);
      expect(find.text('لا وصلة تعمل'), findsOneWidget);
      expect(find.text('3 واقع'), findsOneWidget);
      await close(t);
    });

    testWidgets('النقل بالجهتين: جهةٌ لم تُقرأ «—» لا صفر، والملخّص لا يجمع صاعداً ناقصاً', (t) async {
      // سليف المعامل قُرئ ما يستقبله ولم يُقرأ ما يرسله (عدّادٌ ارتدّ)
      final readings = starReadings();
      readings[311] = _rd(mode: 'station', rx: 46200000, signal: -73, ccq: 81);
      readings[112] = _rd(mode: 'ap-bridge', signal: -71, ccq: 84);
      await boot(t, readings: readings);
      await openHub(t, tall(p390));
      final pill = find.byKey(const ValueKey('topo-pill-1-3'));
      expect(find.descendant(of: pill, matching: plain('46 Mbps')), findsOneWidget);
      expect(find.descendant(of: pill, matching: plain('—')), findsOneWidget, reason: 'ما يصعد لم يُقرأ');
      expect(t.getSize(pill).height, 36);
      // ما ينزل كاملٌ (243) لكنّ الصاعد ناقص ⇒ لا رقم صاعدٍ في الملخّص، بل «إلى 3 أبراج»
      expect(find.textContaining('243 Mbps'), findsOneWidget);
      expect(find.text('إلى 3 أبراج'), findsOneWidget);
      expect(plain('22 Mbps'), findsNothing, reason: 'لا مجموع صاعدٍ ناقص (21 + 1.1)');
      await snap(t, 'one_way_unread', tall(p390));
      await close(t);
    });

    testWidgets('خارج شبكة الأجهزة: لا «واقع» ولا أرقام — سطرٌ يقولها', (t) async {
      await boot(t);
      probe
        ..off = true
        ..down.addAll([211, 311, 411]);
      await openHub(t, tall(p390));
      expect(find.textContaining('أنت خارج شبكة أجهزتك'), findsOneWidget);
      expect(find.text('واقع'), findsOneWidget, reason: 'مفتاح الألوان وحده');
      expect(find.text('مباشر'), findsNothing);
      expect(find.text('خارج شبكتك'), findsNWidgets(3));
      await snap(t, 'off_network', tall(p390));
      await close(t);
    });

    testWidgets('فرعيٌّ يغذّي برجاً بعده «موزّع»، وبرجٌ بلا لنك تحت «غير مربوطة»، ولنكان لبرجٍ واحد حبّةٌ واحدة ×2', (t) async {
      await boot(
        t,
        regions: [...fourRegions(), _r(5, 'برج القرية', '#0891B2'), _r(6, 'برج المخزن', null)],
        devices: [
          ...fourTowersDevices(),
          _d(212, 'لنك القرية (ماستر)', 2, type: 'link'),
          _d(511, 'لنك القرية (سليف)', 5, type: 'link'),
          _d(521, 'سكتر القرية', 5),
          _d(611, 'لنك المخزن', 6, type: 'link'),
          _d(114, 'لنك الحي الاحتياطي (ماستر)', 1, type: 'link'),
          _d(213, 'لنك الحي الاحتياطي (سليف)', 2, type: 'link'),
        ],
        links: [...starLinks(), _l(4, 212, 511), _l(5, 114, 213)],
        readings: {
          ...starReadings(),
          511: _rd(mode: 'station', rx: 38000000, tx: 4000000, signal: -61, ccq: 93),
          213: _rd(mode: 'station', rx: 20000000, tx: 2000000, signal: -58, ccq: 96),
        },
      );
      await openHub(t, tall(p390));
      expect(find.text('6 أبراج · 5 لنكات'), findsOneWidget);
      expect(find.text('موزّع'), findsOneWidget);
      expect(find.text('غير مربوطة'), findsOneWidget);
      expect(find.text('1 غير مربوط'), findsOneWidget);
      // الموزّع (2) تحت الرئيسيّ (1) وفوق القرية (5)، والمخزن (6) آخراً
      final y = {for (final id in [1, 2, 5, 6]) id: t.getCenter(find.byKey(ValueKey('topo-node-$id'))).dy};
      expect(y[1]! < y[2]! && y[2]! < y[5]! && y[5]! < y[6]!, isTrue, reason: canvasOrder(t, [1, 2, 5, 6]));
      // اللنكان للحيّ: المجموع 204 Mbps وعلامة ×2
      expect(find.text('×2'), findsOneWidget);
      expect(find.textContaining('204 Mbps'), findsOneWidget);
      await snap(t, 'relay_loose', tall(p390));
      await close(t);
    });

    testWidgets('ماستر واحد بثلاثة سليفات: ما يعبر واجهته مجموعُها — لا يُنسب للنكٍ لم يُقرأ سليفه', (t) async {
      // كلام المالك: «برج a منطي ٣ لنكات ماستر» — وقد يكون الماستر جهازاً واحداً
      await boot(
        t,
        links: [_l(1, 111, 211), _l(2, 111, 311), _l(3, 111, 411)],
        readings: {
          111: _rd(mode: 'ap', tx: 240000000, rx: 30000000, signal: -55, ccq: 95),
          211: _rd(mode: 'sta', rx: 184000000, tx: 21000000, signal: -52, ccq: 98),
          311: _rd(mode: 'station', rx: 46200000, tx: 6200000, signal: -60, ccq: 92),
          // 411 لم يُقرأ
        },
      );
      await openHub(t, tall(p390));
      expect(find.textContaining('230 Mbps'), findsOneWidget, reason: 'مجموع ما قُرئ من السليفات — لا 240 مكرّرة');
      expect(find.textContaining('240 Mbps'), findsNothing);
      expect(find.textContaining('2/3'), findsOneWidget);
      expect(find.text('1 لم يُقرأ'), findsOneWidget);
      expect(find.text('المقروء 2 من 3'), findsOneWidget, reason: 'مجموعٌ ناقص لا يُقال «إلى 3 أبراج»');
      expect(find.text('إلى 3 أبراج'), findsNothing);
      expect(probe.ends, {111, 211, 311, 411});
      await close(t);
    });

    testWidgets('ستّة فرعيّات على هاتف ٣٦٠: تُلفّ صفّين ولا شيء يخرج عن الشاشة', (t) async {
      final regions = [_r(1, 'الرئيسي', '#2563EB'), for (var i = 2; i <= 7; i++) _r(i, 'برج ${i - 1}', null)];
      final devices = [
        _d(100, 'راوتر', 1, type: 'router'),
        for (var i = 2; i <= 7; i++) ...[
          _d(100 + i, 'ماستر ${i - 1}', 1, type: 'link'),
          _d(200 + i, 'سليف ${i - 1}', i, type: 'link'),
        ],
      ];
      await boot(
        t,
        regions: regions,
        devices: devices,
        links: [for (var i = 2; i <= 7; i++) _l(i, 100 + i, 200 + i)],
        readings: {for (var i = 2; i <= 7; i++) 200 + i: _rd(mode: 'station', rx: i * 11000000, tx: i * 1000000, signal: -50 - i * 2, ccq: 95)},
      );
      await openHub(t, tall(p360));
      final rects = [for (var i = 1; i <= 7; i++) t.getRect(find.byKey(ValueKey('topo-node-$i')))];
      for (final r in rects) {
        expect(r.left >= 0 && r.right <= 360, isTrue, reason: '$r');
      }
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
      expect(rects.skip(1).map((r) => r.top).toSet().length, 2, reason: 'صفّان للفرعيّات');
      await snap(t, 'six_subs', tall(p360));
      await close(t);
    });

    testWidgets('أبراجٌ بلا لنكات بعد: دعوةٌ للربط ومقترحاتٌ ممّا تراه الأجهزة — «اربط» يحفظ ويرسم', (t) async {
      await boot(
        t,
        links: [],
        readings: {
          // طرف الحيّ يرى ماستره بعنوانه، وطرف المعامل وماستره وحدهما على تردّدهما
          211: _rd(mode: 'sta', rx: 5, tx: 5, signal: -52, peers: const [PeerLink(name: 'af-main', mac: '78:8A:20:00:01:11')]),
          112: _rd(mode: 'ap-bridge', rx: 5, tx: 5, freq: 5745),
          311: _rd(mode: 'station', rx: 5, tx: 5, freq: 5745),
        },
      );
      await openHub(t, tall(p390));
      expect(find.text('4 أبراج · لا لنكات'), findsOneWidget);
      expect(find.text('اربط أبراجك'), findsOneWidget);
      expect(find.text('غير مربوطة'), findsNothing, reason: 'لا شيء مربوط ليُقال عن الباقي «غير مربوط»');
      expect(find.text('لنكات مقترحة · 2'), findsOneWidget);
      expect(find.textContaining('يراه بعنوانه'), findsOneWidget);
      expect(find.textContaining('التردّد نفسه'), findsOneWidget);
      await snap(t, 'no_links_suggest', tall(p390));

      await t.tap(find.descendant(of: find.byKey(const ValueKey('topo-suggest-111-211')), matching: find.text('اربط')));
      await settle(t, seconds: 4);
      expect(api.bodies['POST /api/v2/admin/devices/towers/links'], [
        {'a_device_id': 111, 'b_device_id': 211},
      ]);
      expect(find.text('4 أبراج · لنك واحد'), findsOneWidget);
      expect(find.text('رئيسي'), findsOneWidget);
      expect(find.text('لنكات مقترحة · 1'), findsOneWidget);
      expect(probe.ends, {111, 211});
      await close(t);
    });

    testWidgets('برجٌ واحد: يُفتح مباشرةً، والترابط يشرح ويعرض «برج جديد»', (t) async {
      await boot(t, regions: [_r(1, 'البرج الرئيسي', null)], devices: [_d(101, 'CCR', 1, type: 'router'), _d(121, 'سكتر 1', 1)], links: []);
      await openHub(t, p390);
      expect(find.byType(TowerScreen), findsOneWidget, reason: 'برجٌ وحيد ⇒ هو المعروض');
      await t.tap(find.byKey(const ValueKey('towers-chip-${TowersScreen.topology}')));
      await settle(t, seconds: 2);
      expect(find.text('برجٌ واحد حتى الآن'), findsOneWidget);
      expect(find.text('برج جديد'), findsOneWidget);
      await snap(t, 'single_tower', p390);
      await close(t);
    });
  });

  group('أبراجي — التنقّل', () {
    testWidgets('نقرة برجٍ على الرسم تفتحه في مكانه والشريط يعلّمه، و«الترابط» يرجع — بلا رجوعٍ لقائمة', (t) async {
      await boot(t);
      await openHub(t, p390);
      for (final label in ['الترابط', 'البرج الرئيسي', 'برج الحي الصناعي', 'برج المعامل', 'برج الجامعة']) {
        expect(find.descendant(of: find.byType(TowerSwitcher), matching: find.text(label)), findsOneWidget);
      }
      await t.tap(find.byKey(const ValueKey('topo-node-3')));
      await settle(t, seconds: 2);
      final tower = t.widget<TowerScreen>(find.byType(TowerScreen));
      expect([tower.regionId, tower.regionName, tower.devices.map((d) => d.id).toSet()], [3, 'برج المعامل', {311, 301, 321}]);
      expect(find.byType(TowerTopologyScreen), findsNothing);
      expect(find.byType(TowerSwitcher), findsOneWidget, reason: 'الشريط نفسه فوق البرج');
      await snap(t, 'hub_tower', p390);

      await t.ensureVisible(find.byKey(const ValueKey('towers-chip-2')));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const ValueKey('towers-chip-2')));
      await settle(t, seconds: 2);
      expect(t.widget<TowerScreen>(find.byType(TowerScreen)).regionId, 2);

      await t.tap(find.byKey(const ValueKey('towers-chip-${TowersScreen.topology}')));
      await settle(t, seconds: 2);
      expect(find.byType(TowerTopologyScreen), findsOneWidget);
      await close(t);

      // العودة للقسم تُكمل من حيث تُرك (آخر ما فُتح) — والمنطقة المصفّاة في القائمة تتقدّم
      await pumpVisual(t, p390, home: (_) => TowersScreen(devices: devicesOf(api), regions: regionsOf(api)));
      await settle(t, seconds: 2);
      expect(find.byType(TowerTopologyScreen), findsOneWidget);
      await close(t);
      await pumpVisual(t, p390, home: (_) => TowersScreen(devices: devicesOf(api), regions: regionsOf(api), openRegionId: 4));
      await settle(t, seconds: 2);
      expect(t.widget<TowerScreen>(find.byType(TowerScreen)).regionId, 4);
      await close(t);
    });

    testWidgets('القائمتان تُجدَّدان من الخادم عند الفتح: منطقة شركةٍ أخرى سُلِّمت مع الفتح («كل الشركات») لا تبقى برجاً', (t) async {
      await boot(t);
      await pumpVisual(
        t,
        p390,
        home: (_) => TowersScreen(
          devices: devicesOf(api),
          regions: [...regionsOf(api), DeviceRegion(id: 77, name: 'منطقة شركة أخرى', createdAt: DateTime(2026))],
        ),
      );
      await t.pump();
      expect(find.byKey(const ValueKey('towers-chip-77')), findsOneWidget, reason: 'قبل ردّ الخادم: ما سُلِّم');
      await settle(t, seconds: 2);
      expect(find.byKey(const ValueKey('towers-chip-77')), findsNothing);
      expect(find.byKey(const ValueKey('towers-chip-4')), findsOneWidget);
      expect(find.text('4 أبراج · 3 لنكات'), findsOneWidget);
      await close(t);
    });

    testWidgets('الحاسبة: الشريط تحت رأس الصفحة، والرسم بعرضه الأقصى في الوسط، والتنقّل نفسه', (t) async {
      await boot(t);
      const desk = VisualDevice('_desk', Size(1280, 860), 1.5);
      await pumpVisual(t, desk, home: (_) => DesktopScope(child: TowersScreen(devices: devicesOf(api), regions: regionsOf(api))));
      await settle(t, seconds: 2);
      expect(find.text('4 أبراج · 3 لنكات'), findsOneWidget);
      expect(find.byType(TowerSwitcher), findsOneWidget);
      expect(t.getSize(find.byKey(const ValueKey('topo-canvas'))).width, TopoLayout.maxWidth);
      await snap(t, 'desktop', desk);
      await t.tap(find.byKey(const ValueKey('towers-chip-3')));
      await settle(t, seconds: 2);
      expect(t.widget<TowerScreen>(find.byType(TowerScreen)).regionId, 3);
      expect(find.byType(TowerSwitcher), findsOneWidget);
      await snap(t, 'desktop_tower', desk);
      await close(t);
    });

    testWidgets('أجهزةٌ بلا منطقة: ليست برجاً على الرسم — سطرٌ بعددها يفتحها، وحبّتها في الشريط بلا «أجهزة البرج»', (t) async {
      await boot(t, devices: [...fourTowersDevices(), _d(901, 'جهاز بلا برج', null, type: 'router'), _d(902, 'سكتر بلا برج', null)]);
      await openHub(t, tall(p390));
      expect(find.text('4 أبراج · 3 لنكات'), findsOneWidget, reason: '«بلا منطقة» لا تُعدّ برجاً');
      expect(find.byKey(const ValueKey('topo-node-0')), findsNothing);
      expect(find.textContaining('جهازان بلا منطقة'), findsOneWidget);
      await snap(t, 'orphans_line', tall(p390));
      await t.tap(find.byKey(const ValueKey('topo-orphans')));
      await settle(t, seconds: 2);
      final tower = t.widget<TowerScreen>(find.byType(TowerScreen));
      expect([tower.regionId, tower.regionName, tower.onAssign, tower.devices.length], [0, 'بلا منطقة', null, 2]);
      expect(find.byTooltip('أجهزة هذا البرج'), findsNothing);
      await close(t);
    });

    testWidgets('وكيلٌ لم يقسّم أجهزته بعد: «بلا منطقة» تُفتح كما كانت، والترابط يدعوه لأوّل برج', (t) async {
      await boot(t, regions: [], devices: [_d(1, 'CCR', null, type: 'router'), _d(2, 'سكتر 1', null), _d(3, 'لنك', null, type: 'link')], links: []);
      await openHub(t, p390);
      expect(t.widget<TowerScreen>(find.byType(TowerScreen)).regionId, 0);
      await t.tap(find.byKey(const ValueKey('towers-chip-${TowersScreen.topology}')));
      await settle(t, seconds: 2);
      expect(find.text('أجهزتك بلا أبراج بعد'), findsOneWidget);
      expect(find.text('برج جديد'), findsOneWidget);
      expect(find.byTooltip('ربط برجين — لنك أو كيبل'), findsNothing, reason: 'لا برجين ليُربطا');
      await snap(t, 'no_zones', p390);
      await close(t);
    });
  });

  group('الربط', () {
    testWidgets('حبّة الوصلة ⇒ تفاصيل اللنك (ما ينزل وما يصعد والإشارة والطرفان)؛ «اقلب» يعكس الرئيسيّ والفرعيّ، و«احذف» يزيله', (t) async {
      await boot(t);
      await openHub(t, p390);
      await t.tap(find.byKey(const ValueKey('topo-pill-1-2')));
      await settle(t, seconds: 1);
      expect(find.text('البرج الرئيسي ← برج الحي الصناعي'), findsWidgets);
      expect(find.text('ينزل للفرعي'), findsNWidgets(2), reason: 'مفتاح الرسم + خانة الورقة');
      expect(find.text('يصعد للرئيسي'), findsNWidgets(2), reason: 'مفتاح الرسم + خانة الورقة');
      for (final s in ['الإشارة', 'CCQ', 'طرف البرج الرئيسي (الماستر)', 'طرف البرج الفرعي (السليف)']) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      expect(find.textContaining('21 Mbps'), findsWidgets);
      expect(find.textContaining('-52 dBm'), findsWidgets);
      await snap(t, 'link_sheet', p390);

      await t.tap(find.text('اقلب الاتّجاه'));
      await settle(t, seconds: 1);
      expect(api.bodies['PUT /api/v2/admin/devices/towers/links/1'], [
        {'flip': true},
      ]);
      expect(find.text('برج الحي الصناعي ← البرج الرئيسي'), findsWidgets, reason: 'الورقة نفسها تتبع اللنك بعد قلبه');

      await t.tap(find.text('احذف الربط'));
      await settle(t, seconds: 1);
      expect(find.text('حذف الربط'), findsOneWidget);
      await t.tap(find.text('احذف الربط').last);
      await settle(t, seconds: 4);
      expect(api.calls, contains('DELETE /api/v2/admin/devices/towers/links/1'));
      expect(find.text('4 أبراج · لنكان'), findsOneWidget);
      expect(find.byKey(const ValueKey('topo-pill-1-2')), findsNothing);
      expect(find.byKey(const ValueKey('topo-pill-2-1')), findsNothing);
      await close(t);
    });

    testWidgets('«ربط لنك»: طرف الرئيسيّ ثمّ الفرعيّ — ما في برج الطرف الآخر وما رُبط فرعيّاً معطّلٌ بسببه — والحفظ يرسمه', (t) async {
      await boot(t, links: [_l(1, 111, 211)]);
      await openHub(t, p390);
      await t.tap(find.byTooltip('ربط برجين — لنك أو كيبل'));
      await settle(t, seconds: 1);
      expect(find.byType(TowerLinkEditorScreen), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('link-save'))).onPressed, isNull);
      await snap(t, 'editor_empty', p390);

      await t.tap(find.byKey(const ValueKey('link-end-main')));
      await settle(t, seconds: 1);
      expect(find.text('الماستر — منه يخرج الترافيك'), findsWidgets);
      await snap(t, 'editor_picker', p390);
      await t.tap(find.byKey(const ValueKey('pick-device-112')));
      await settle(t, seconds: 1);

      await t.tap(find.byKey(const ValueKey('link-end-sub')));
      await settle(t, seconds: 1);
      // في برج الطرف الآخر ⇒ معطّل؛ ومربوطٌ فرعيّاً ⇒ معطّل
      expect(find.descendant(of: find.byKey(const ValueKey('pick-device-113')), matching: find.text('في برج الطرف الآخر')), findsOneWidget);
      final list = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).last;
      await t.scrollUntilVisible(find.byKey(const ValueKey('pick-device-211')), 120, scrollable: list);
      expect(find.descendant(of: find.byKey(const ValueKey('pick-device-211')), matching: find.text('مربوطٌ بلنكٍ آخر')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('pick-device-211')), warnIfMissed: false);
      await settle(t, seconds: 1);
      expect(find.text('السليف — إليه يصل الترافيك'), findsWidgets, reason: 'المعطّل لا يُختار — المنتقي باقٍ');
      await t.scrollUntilVisible(find.byKey(const ValueKey('pick-device-311')), 120, scrollable: list);
      await t.tap(find.byKey(const ValueKey('pick-device-311')));
      await settle(t, seconds: 1);
      await snap(t, 'editor_ready', p390);

      await t.tap(find.byKey(const ValueKey('link-save')));
      await settle(t, seconds: 4);
      expect(api.bodies['POST /api/v2/admin/devices/towers/links'], [
        {'a_device_id': 112, 'b_device_id': 311},
      ]);
      expect(find.byType(TowerLinkEditorScreen), findsNothing);
      expect(find.text('4 أبراج · لنكان'), findsOneWidget);
      expect(find.byKey(const ValueKey('topo-pill-1-3')), findsOneWidget);
      await close(t);
    });

    testWidgets('لنكٌ صار طرفاه في البرج نفسه (نُقل أحدهما) لا يُرسم — يُذكر مع زرّ حذفه', (t) async {
      final devices = fourTowersDevices();
      devices.firstWhere((d) => d['id'] == 411)['region_id'] = 1; // نُقل سليف الجامعة للبرج الرئيسيّ
      await boot(t, devices: devices);
      await openHub(t, tall(p390));
      expect(find.text('4 أبراج · لنكان'), findsOneWidget);
      expect(find.text('لنكات لا تُرسم · 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('topo-pill-1-4')), findsNothing);
      await snap(t, 'broken_link', tall(p390));
      await t.tap(find.byTooltip('احذف الربط'));
      await settle(t, seconds: 1);
      await t.tap(find.text('احذف الربط').last);
      await settle(t, seconds: 4);
      expect(api.calls, contains('DELETE /api/v2/admin/devices/towers/links/3'));
      expect(find.text('لنكات لا تُرسم · 1'), findsNothing);
      await close(t);
    });

    testWidgets('الخادم لا يحفظ الترابط (أقدم) أو تعذّر الجلب: الأبراج تظهر بلا ربط ولا تعديل — وسطرٌ يقولها', (t) async {
      await boot(t);
      api.linksReady = false;
      await openHub(t, p390);
      expect(find.text('الربط بين الأبراج غير متاح الآن.'), findsOneWidget);
      expect(find.text('4 أبراج · لا لنكات'), findsOneWidget);
      expect(find.text('اربط أبراجك'), findsNothing, reason: 'لا دعوة لما لا يمكن');
      await t.tap(find.byTooltip('ربط برجين — لنك أو كيبل'));
      await settle(t, seconds: 4);
      expect(find.byType(TowerLinkEditorScreen), findsNothing);
      await close(t);

      await boot(t);
      api.towersFail = true;
      await openHub(t, p390);
      expect(find.textContaining('تعذّر جلب الترابط من الخادم'), findsOneWidget);
      await snap(t, 'load_failed', p390);
      api.towersFail = false;
      await t.tap(find.text('أعد المحاولة'));
      await settle(t, seconds: 2);
      expect(find.text('4 أبراج · 3 لنكات'), findsOneWidget);
      await close(t);
    });
  });

  // ── ١١ نوفمبر صباحاً — المالك: «اكو ابراج ترتبط مع بعضها فايبر… مرات مو لنك يعني مباشر كيبل ضوئي بين سوجات» ──
  group('الكيبل الضوئيّ بين سويجين', () {
    // سويج الرئيسيّ (102) يخرج منه كيبلان: للحيّ (201) وللجامعة (401)؛ والمعامل بلنكٍ لاسلكيّ كما هو
    List<Map<String, Object?>> mixedLinks() => [
          _f(1, 102, 201, aPort: 'sfp-sfpplus1', bPort: 'sfp1'),
          _l(2, 112, 311),
          _f(3, 102, 401, aPort: 'sfp-sfpplus2', bPort: 'sfp-sfpplus1'),
        ];
    Map<int, TowerReading> mixedReadings() => {
          102: _sw([
            _port('sfp-sfpplus1', tx: 615000000, rx: 71000000, speed: '10Gbps', light: -6.4),
            _port('sfp-sfpplus2', tx: 231000000, rx: 30000000, speed: '10Gbps', light: -8.0),
            _port('ether1', tx: 880000000, rx: 990000000, speed: '1Gbps'), // الأنشط — ليس كيبل برج
            _port('ether2', up: false),
          ]),
          201: _sw([
            _port('sfp1', rx: 612000000, tx: 70000000, speed: '10Gbps', light: -7.1),
            _port('sfp2', up: false),
            _port('ether1', rx: 4000000, tx: 300000000, speed: '1Gbps'),
          ]),
          401: _sw([
            _port('sfp-sfpplus1', rx: 228000000, tx: 29000000, speed: '10Gbps', light: -26.8),
            _port('ether1', rx: 1000000, tx: 110000000, speed: '1Gbps'),
          ]),
          112: starReadings()[112]!,
          311: starReadings()[311]!,
        };

    testWidgets('كيبلان ولنك: كلّ نوعٍ برسمه واسمه، وما ينزل لكلّ برج ما يعبر منفذ كيبله — لا أنشط منفذ', (t) async {
      for (final d in [tall(p390), tall(p390dark), tall(p360)]) {
        await boot(t, links: mixedLinks(), readings: mixedReadings());
        await openHub(t, d);
        expect(plain('4 أبراج · لنك واحد · كيبلان'), findsOneWidget);
        expect(plain('الوصلات · 3'), findsOneWidget);
        expect(plain('الوصلات'), findsOneWidget, reason: 'بلاطة الملخّص');
        // منفذ كيبل الحيّ يستقبل 612 — لا 300 (أنشط منافذه) ولا 990 (أنشط منافذ الرئيسيّ)
        expect(plainHas('612 Mbps'), findsWidgets);
        expect(plainHas('228 Mbps'), findsWidgets);
        expect(plainHas('990 Mbps'), findsNothing);
        expect(plainHas('300 Mbps'), findsNothing);
        expect(plainHas('886 Mbps'), findsOneWidget, reason: 'يوزّع الرئيسي: 612 + 228 + 46.2');
        expect(plain('105 Mbps'), findsOneWidget, reason: 'يصعد للرئيسي: 70 + 29 + 6.2');
        // حبّة الكيبل بالجهتين من منفذه: يستقبل 612 ويرسل 70
        expect(find.descendant(of: find.byKey(const ValueKey('topo-pill-1-2')), matching: plain('612 Mbps')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('topo-pill-1-2')), matching: plain('70 Mbps')), findsOneWidget);
        expect(plain('كيبل · يعمل · 10G · ضوء -7.1 dBm'), findsOneWidget);
        expect(plain('كيبل · ضوء ضعيف · 10G · ضوء -26.8 dBm'), findsOneWidget);
        expect(plainHas('متوسّط · -73 dBm'), findsOneWidget, reason: 'اللنك اللاسلكيّ بكلماته كما كان');
        // مفتاح الرسم يسمّي النوعين
        expect(plain('كيبل ضوئي'), findsOneWidget);
        expect(plain('لنك لاسلكي'), findsOneWidget);
        expect(probe.ends, {102, 201, 401, 112, 311});
        await snap(t, 'fiber_mixed', d);
        await close(t);
      }
    });

    testWidgets('🚨 منفذ الكيبل طافٍ والسويج يردّ ⇒ «واقع» بسببه؛ ومنفذٌ بلا عدّادات (قراءة VPN) «يعمل»', (t) async {
      final readings = mixedReadings();
      readings[201] = _sw([_port('sfp1', up: false), _port('ether1', rx: 4000000, tx: 300000000, speed: '1Gbps')]);
      readings[102] = _sw([_port('sfp-sfpplus1', up: false), _port('sfp-sfpplus2', speed: '10Gbps')]);
      readings[401] = _sw([_port('sfp-sfpplus1', speed: '10Gbps', light: -9.0)]);
      await boot(t, links: mixedLinks(), readings: readings);
      await openHub(t, tall(p390));
      expect(plain('كيبل · المنفذان طافيان — الكيبل أو الـSFP'), findsOneWidget);
      expect(plain('1 واقع'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('topo-pill-1-2')), matching: plain('واقع')), findsOneWidget);
      // كيبل الجامعة: شغّال بلا رقم
      expect(find.descendant(of: find.byKey(const ValueKey('topo-pill-1-4')), matching: plain('يعمل')), findsOneWidget);
      expect(plain('كيبل · يعمل · 10G · ضوء -9.0 dBm'), findsOneWidget);
      // الرقم المعروض (46) ما يعبر اللنك اللاسلكيّ وحده: كيبلٌ واقع (لا يُعدّ) وكيبلٌ يعمل بلا عدّادات ⇒ «المقروء 1 من 2»
      expect(plain('المقروء 1 من 2'), findsOneWidget);
      await snap(t, 'fiber_port_down', tall(p390));
      await t.tap(find.byKey(const ValueKey('topo-pill-1-2')));
      await settle(t, seconds: 1);
      expect(plain('كيبل ضوئي · واقع'), findsOneWidget);
      expect(plain('المنفذان طافيان — الكيبل أو الـSFP'), findsOneWidget);
      expect(plain('سرعة المنفذ'), findsOneWidget);
      expect(plain('ضوء الـSFP'), findsOneWidget);
      expect(plain('الإشارة'), findsNothing, reason: 'لا إشارة ولا CCQ لكيبل');
      expect(plainHas('sfp1 · طافي'), findsOneWidget);
      await snap(t, 'fiber_sheet_down', p390);
      await close(t);
    });

    testWidgets('كيبل بلا منفذ: «اختر المنفذ» — من تفاصيله يُختار من منافذ السويج كما تُقرأ الآن، والمأخوذ معطّل', (t) async {
      final readings = mixedReadings();
      await boot(t, links: [_f(1, 102, 201, aPort: 'sfp-sfpplus1'), _f(3, 301, 201)], readings: readings, devices: [
        ...fourTowersDevices(),
        _d(302, 'سويج المعامل', 3, type: 'switch'),
      ]);
      // كيبل الحيّ منفذه عند الرئيسيّ وحده ⇒ يُقرأ منه؛ وكيبل المعامل (راوتره ⇐ سويج الحيّ) بلا منفذ
      await openHub(t, tall(p390));
      expect(plain('كيبل · اختر المنفذ ليظهر ما يعبر الكيبل'), findsOneWidget);
      expect(plainHas('615 Mbps'), findsWidgets, reason: 'ما يرسله منفذ الرئيسيّ');
      expect(plain('المقروء 1 من 2'), findsOneWidget, reason: 'الكيبل بلا منفذ يعمل ولم يُقرأ ما يعبره');
      await snap(t, 'fiber_unset', tall(p390));
      await t.tap(find.byKey(const ValueKey('topo-link-1')));
      await settle(t, seconds: 1);
      expect(plainHas('sfp-sfpplus1 · 10G'), findsOneWidget);
      // منفذ الفرعيّ: منتقٍ بمنافذ سويج الحيّ الآن
      await t.tap(find.byKey(const ValueKey('link-sheet-port-sub')));
      await settle(t, seconds: 1);
      expect(plain('منفذ الكيبل'), findsOneWidget);
      expect(probe.readOnceCalls, contains(201));
      expect(find.byKey(const ValueKey('pick-port-sfp1')), findsOneWidget);
      expect(plainHas('↓ 612 Mbps ↑ 70 Mbps · ضوء -7.1 dBm'), findsOneWidget, reason: 'يُعرف منفذ الكيبل بما يعبره');
      // منفذ الرئيسيّ يرسل 615 وينزل له 71 ⇒ المنفذ الذي يستقبل 612 ويرسل 70 هو طرف الكيبل — يُعلَّم، وواحدٌ فقط
      expect(find.descendant(of: find.byKey(const ValueKey('pick-port-sfp1')), matching: plain('يطابق ما يعبر الطرف الآخر')), findsOneWidget);
      expect(plain('يطابق ما يعبر الطرف الآخر'), findsOneWidget);
      // الشغّالة أوّلاً ومنافذ الـSFP قبل الإيثر
      final ys = [for (final n in ['sfp1', 'ether1', 'sfp2']) t.getTopLeft(find.byKey(ValueKey('pick-port-$n'))).dy];
      expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue, reason: '$ys');
      await snap(t, 'fiber_port_picker', p390);
      await t.tap(find.byKey(const ValueKey('pick-port-sfp1')));
      await settle(t, seconds: 2);
      expect(api.bodies['PUT /api/v2/admin/devices/towers/links/1']!.last, {'kind': 'fiber', 'a_port': 'sfp-sfpplus1', 'b_port': 'sfp1'});
      expect(plainHas('sfp1 · 10G · ضوء -7.1 dBm'), findsOneWidget, reason: 'الورقة تتبع الربط بعد حفظه');
      await t.tapAt(const Offset(195, 60));
      await settle(t, seconds: 1);
      expect(plainHas('612 Mbps'), findsWidgets, reason: 'صار يُقرأ من منفذ الفرعيّ');
      // الكيبل الثاني على السويج نفسه: sfp1 مأخوذ
      await t.tap(find.byKey(const ValueKey('topo-link-3')));
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('link-sheet-port-sub')));
      await settle(t, seconds: 1);
      expect(find.descendant(of: find.byKey(const ValueKey('pick-port-sfp1')), matching: plain('عليه كيبلٌ آخر')), findsOneWidget);
      expect(plain('يطابق ما يعبر الطرف الآخر'), findsNothing, reason: 'منفذ الطرف الآخر لم يُحدَّد — لا شيء يُطابَق به');
      await t.tap(find.byKey(const ValueKey('pick-port-sfp1')), warnIfMissed: false);
      await settle(t, seconds: 1);
      expect(plain('منفذ الكيبل'), findsOneWidget, reason: 'المأخوذ لا يُختار');
      // ولا يُكتب: المكتوب كالمختار
      await t.enterText(find.byKey(const ValueKey('port-manual')), 'SFP1');
      await t.tap(find.byKey(const ValueKey('port-manual-use')));
      await settle(t, seconds: 1);
      expect(plain('منفذ الكيبل'), findsOneWidget);
      expect(find.text('على هذا المنفذ كيبلٌ آخر — اختر منفذاً غيره'), findsOneWidget);
      expect(api.bodies['PUT /api/v2/admin/devices/towers/links/3'], isNull);
      await settle(t, seconds: 5);
      await t.enterText(find.byKey(const ValueKey('port-manual')), ' SFP2 ');
      await t.tap(find.byKey(const ValueKey('port-manual-use')));
      await settle(t, seconds: 2);
      expect(api.bodies['PUT /api/v2/admin/devices/towers/links/3']!.last, {'kind': 'fiber', 'a_port': null, 'b_port': 'sfp2'},
          reason: 'المكتوب بين منافذ الجهاز ⇒ يُحفظ باسمه كما يكتبه الجهاز');
      await close(t);
    });

    testWidgets('«ربط برجين» ⇒ «كيبل ضوئي»: السويجات أوّلاً، والمنفذ بعد كلّ جهاز، والحفظ بنوعه ومنفذيه', (t) async {
      await boot(t, links: [_l(2, 112, 311)], readings: mixedReadings());
      await openHub(t, p390);
      await t.tap(find.byTooltip('ربط برجين — لنك أو كيبل'));
      await settle(t, seconds: 1);
      expect(find.byType(TowerLinkEditorScreen), findsOneWidget);
      expect(plain('لنك لاسلكي'), findsOneWidget);
      await t.tap(plain('كيبل ضوئي'));
      await settle(t, seconds: 1);
      expect(plainHas('كيبل ضوئي (فايبر) مباشر بين سويجين'), findsOneWidget);
      await snap(t, 'fiber_editor_empty', p390);
      await t.tap(find.byKey(const ValueKey('link-end-main')));
      await settle(t, seconds: 1);
      // السويج والراوتر قبل اللنكات والسكاترات في برجهما
      final yRouter = t.getTopLeft(find.byKey(const ValueKey('pick-device-101'))).dy;
      final ySwitch = t.getTopLeft(find.byKey(const ValueKey('pick-device-102'))).dy;
      final yLink = t.getTopLeft(find.byKey(const ValueKey('pick-device-111'))).dy;
      expect(yRouter < yLink && ySwitch < yLink, isTrue);
      await t.tap(find.byKey(const ValueKey('pick-device-102')));
      await settle(t, seconds: 1);
      // المنفذ مباشرةً بعد الجهاز
      expect(plain('منفذ الكيبل'), findsOneWidget);
      expect(plain('يطابق ما يعبر الطرف الآخر'), findsNothing, reason: 'الطرف الآخر لم يُختر بعد');
      await t.tap(find.byKey(const ValueKey('pick-port-sfp-sfpplus1')));
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('link-end-sub')));
      await settle(t, seconds: 1);
      final list = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).last;
      await t.scrollUntilVisible(find.byKey(const ValueKey('pick-device-201')), 120, scrollable: list);
      await t.tap(find.byKey(const ValueKey('pick-device-201')));
      await settle(t, seconds: 1);
      // منفذ الرئيسيّ اختير ⇒ منفذ سويج الحيّ الذي يعبره المقدار نفسه معكوساً معلَّم
      expect(find.descendant(of: find.byKey(const ValueKey('pick-port-sfp1')), matching: plain('يطابق ما يعبر الطرف الآخر')), findsOneWidget);
      expect(plain('يطابق ما يعبر الطرف الآخر'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('pick-port-sfp1')));
      await settle(t, seconds: 1);
      expect(find.descendant(of: find.byKey(const ValueKey('link-port-main')), matching: plainHas('sfp-sfpplus1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('link-port-sub')), matching: plainHas('sfp1')), findsOneWidget);
      await snap(t, 'fiber_editor_ready', p390);
      await t.tap(find.byKey(const ValueKey('link-save')));
      await settle(t, seconds: 4);
      expect(api.bodies['POST /api/v2/admin/devices/towers/links'], [
        {'a_device_id': 102, 'b_device_id': 201, 'kind': 'fiber', 'a_port': 'sfp-sfpplus1', 'b_port': 'sfp1'},
      ]);
      expect(find.byType(TowerLinkEditorScreen), findsNothing);
      expect(plain('4 أبراج · لنك واحد · كيبل واحد'), findsOneWidget);
      expect(plainHas('612 Mbps'), findsWidgets);
      await close(t);
    });

    testWidgets('السويج لا يُقرأ الآن: يُكتب اسم المنفذ أو يُترك لوقتٍ لاحق — والربط يُحفظ ويُرسم', (t) async {
      await boot(t, links: [], readings: {});
      await openHub(t, p390);
      await t.tap(find.byTooltip('ربط برجين — لنك أو كيبل'));
      await settle(t, seconds: 1);
      await t.tap(plain('كيبل ضوئي'));
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('link-end-main')));
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('pick-device-102')));
      await settle(t, seconds: 1);
      expect(plainHas('تعذّرت قراءة منافذ «سويج الرئيسي» الآن'), findsOneWidget);
      await snap(t, 'fiber_port_manual', p390);
      await t.enterText(find.byKey(const ValueKey('port-manual')), '  sfp-sfpplus3 ');
      await t.tap(find.byKey(const ValueKey('port-manual-use')));
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('link-end-sub')));
      await settle(t, seconds: 1);
      final list = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).last;
      await t.scrollUntilVisible(find.byKey(const ValueKey('pick-device-401')), 120, scrollable: list);
      await t.tap(find.byKey(const ValueKey('pick-device-401')));
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('port-later')));
      await settle(t, seconds: 1);
      await t.tap(find.byKey(const ValueKey('link-save')));
      await settle(t, seconds: 4);
      expect(api.bodies['POST /api/v2/admin/devices/towers/links'], [
        {'a_device_id': 102, 'b_device_id': 401, 'kind': 'fiber', 'a_port': 'sfp-sfpplus3'},
      ]);
      expect(plain('4 أبراج · كيبل واحد'), findsOneWidget);
      expect(find.byKey(const ValueKey('topo-pill-1-4')), findsOneWidget, reason: 'يُرسم ولو لم يُقرأ');
      await close(t);
    });

    testWidgets('سويجان رُبطا «لنكاً» قبل أن يوجد الكيبل: يُحوَّل من تفاصيله بلا حذف — ويرجع', (t) async {
      await boot(t, links: [_l(1, 102, 201)], readings: mixedReadings());
      await openHub(t, p390);
      await t.tap(find.byKey(const ValueKey('topo-pill-1-2')));
      await settle(t, seconds: 1);
      expect(plain('الإشارة'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('link-sheet-kind')));
      await settle(t, seconds: 2);
      expect(api.bodies['PUT /api/v2/admin/devices/towers/links/1']!.last, {'kind': 'fiber', 'a_port': null, 'b_port': null});
      expect(plain('كيبل ضوئي · بلا منفذ'), findsOneWidget);
      expect(plain('الإشارة'), findsNothing);
      expect(plain('ضوء الـSFP'), findsOneWidget);
      expect(find.byKey(const ValueKey('link-sheet-port-main')), findsOneWidget);
      await snap(t, 'fiber_converted', p390);
      await t.tap(find.byKey(const ValueKey('link-sheet-kind')));
      await settle(t, seconds: 2);
      expect(api.bodies['PUT /api/v2/admin/devices/towers/links/1']!.last, {'kind': 'radio'});
      expect(plain('الإشارة'), findsOneWidget);
      await close(t);
    });

    testWidgets('كيبلٌ اختير منفذه ⇒ تحويله إلى لنك يسأل أوّلاً (المنفذان يُمسحان) — والإلغاء لا يغيّر شيئاً', (t) async {
      await boot(t, links: [_f(1, 102, 201, aPort: 'sfp-sfpplus1', bPort: 'sfp1')], readings: mixedReadings());
      await openHub(t, p390);
      await t.tap(find.byKey(const ValueKey('topo-pill-1-2')));
      await settle(t, seconds: 1);
      expect(plain('حوّله إلى لنك لاسلكي'), findsOneWidget, reason: 'الزرّ يقول ما سيفعله');
      await t.tap(find.byKey(const ValueKey('link-sheet-kind')));
      await settle(t, seconds: 1);
      expect(plain('تحويله إلى لنك لاسلكي'), findsOneWidget);
      expect(plainHas('يُمسح منفذ الكيبل المحدَّد عند الطرفين'), findsOneWidget);
      await snap(t, 'fiber_convert_confirm', p390);
      await t.tap(find.text('إلغاء'));
      await settle(t, seconds: 1);
      expect(api.writes(), isEmpty);
      expect(plain('كيبل ضوئي · يعمل'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('link-sheet-kind')));
      await settle(t, seconds: 1);
      await t.tap(plain('حوّله'));
      await settle(t, seconds: 2);
      expect(api.bodies['PUT /api/v2/admin/devices/towers/links/1'], [
        {'kind': 'radio'},
      ]);
      expect(api.links.single['a_port'], isNull, reason: 'اللنك بلا منافذ');
      expect(plain('الإشارة'), findsOneWidget);
      expect(plain('حوّله إلى كيبل ضوئي'), findsOneWidget);
      await close(t);
    });

    testWidgets('منفذٌ محدَّد وليس بين منافذ السويج كما قُرئت: يُقال عند طرفه — ولو قُرئ الكيبل من الطرف الآخر', (t) async {
      // منفذ الفرعيّ كُتب خطأً (sfp9)، ومنفذ الرئيسيّ صحيح ⇒ الكيبل يُقرأ من الرئيسيّ، والخطأ يظهر عند طرفه
      await boot(t, links: [_f(1, 102, 201, aPort: 'sfp-sfpplus1', bPort: 'sfp9')], readings: mixedReadings());
      await openHub(t, p390);
      expect(plainHas('615 Mbps'), findsWidgets, reason: 'ما يرسله منفذ الرئيسيّ');
      await t.tap(find.byKey(const ValueKey('topo-pill-1-2')));
      await settle(t, seconds: 1);
      expect(find.descendant(of: find.byKey(const ValueKey('link-sheet-port-sub')), matching: plain('sfp9 · غير موجود بالجهاز')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('link-sheet-port-main')), matching: plainHas('غير موجود')), findsNothing);
      await t.tapAt(const Offset(195, 60));
      await settle(t, seconds: 1);
      await close(t);
      // والمنفذان خطأ ⇒ الكيبل لم يُقرأ، بسببه
      await boot(t, links: [_f(1, 102, 201, aPort: 'sfp8', bPort: 'sfp9')], readings: mixedReadings());
      await openHub(t, p390);
      expect(plain('كيبل · المنفذ «sfp9» غير موجود بالجهاز — اختره من جديد'), findsOneWidget);
      await close(t);
    });

    testWidgets('القلب يبدّل المنفذين مع الطرفين', (t) async {
      await boot(t, links: [_f(1, 102, 201, aPort: 'sfp-sfpplus1', bPort: 'sfp1')], readings: mixedReadings());
      await openHub(t, p390);
      await t.tap(find.byKey(const ValueKey('topo-pill-1-2')));
      await settle(t, seconds: 1);
      await t.tap(plain('اقلب الاتّجاه'));
      await settle(t, seconds: 2);
      expect(api.links.single, containsPair('a_port', 'sfp1'));
      expect(api.links.single, containsPair('b_port', 'sfp-sfpplus1'));
      expect(plain('برج الحي الصناعي ← البرج الرئيسي'), findsWidgets);
      // صار سويج الرئيسيّ الطرف الفرعيّ: ما يستقبله منفذه (71) ينزل له
      expect(plainHas('71 Mbps'), findsWidgets);
      await close(t);
    });

    testWidgets('خادمٌ قبل الهجرة 087: لا خيار كيبل ولا تحويل — واللنك اللاسلكيّ كما كان', (t) async {
      await boot(t);
      api.fiberReady = false;
      await openHub(t, p390);
      expect(plain('4 أبراج · 3 لنكات'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('topo-pill-1-2')));
      await settle(t, seconds: 1);
      expect(find.byKey(const ValueKey('link-sheet-kind')), findsNothing);
      await t.tapAt(const Offset(195, 60));
      await settle(t, seconds: 1);
      await t.tap(find.byTooltip('ربط برجين — لنك أو كيبل'));
      await settle(t, seconds: 1);
      expect(find.byType(TowerLinkEditorScreen), findsOneWidget);
      expect(plain('كيبل ضوئي'), findsNothing);
      expect(plainHas('اللنك يربط برجين'), findsOneWidget);
      await close(t);
    });

    testWidgets('موظّفٌ بلا «إدارة الأجهزة»: يرى الكيبل ومنفذيه، وتغيير المنفذ والتحويل بقفل', (t) async {
      await boot(t, links: mixedLinks(), readings: mixedReadings());
      PermissionsService.debugSet(isEmployee: true, permissions: const {'devices.view': true});
      await openHub(t, p390);
      await t.tap(find.byKey(const ValueKey('topo-pill-1-2')));
      await settle(t, seconds: 1);
      expect(plainHas('sfp1 · 10G · ضوء -7.1 dBm'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('link-sheet-port-sub')));
      await settle(t, seconds: 3);
      expect(plain('منفذ الكيبل'), findsNothing);
      await t.tap(find.byKey(const ValueKey('link-sheet-kind')));
      await settle(t, seconds: 3);
      expect(api.writes(), isEmpty);
      await close(t);
    });
  });

  group('إسناد الأجهزة للبرج', () {
    testWidgets('«أجهزة هذا البرج»: المعلَّم ما على البرج؛ تعليم جهازٍ ينقله ورفع العلامة يُخرجه — دفعةٌ واحدة والبرج يتحدّث', (t) async {
      await boot(t, devices: [...fourTowersDevices(), _d(901, 'سكتر جديد 1', null), _d(902, 'سكتر جديد 2', null)]);
      await openHub(t, p390, openRegionId: 3);
      expect(t.widget<TowerScreen>(find.byType(TowerScreen)).devices.length, 3);
      await t.tap(find.byTooltip('أجهزة هذا البرج'));
      await settle(t, seconds: 1);
      expect(find.byType(TowerAssignScreen), findsOneWidget);
      expect(find.text('أجهزة «برج المعامل»'), findsOneWidget);
      expect(find.text('على هذا البرج · 3'), findsOneWidget);
      expect(find.text('بلا منطقة · 2'), findsOneWidget);
      expect(find.text('لا تغيير'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('assign-save'))).onPressed, isNull);
      await snap(t, 'assign_open', p390);

      await t.tap(find.byKey(const ValueKey('assign-device-901')));
      await t.tap(find.byKey(const ValueKey('assign-device-902')));
      await t.tap(find.byKey(const ValueKey('assign-device-321'))); // يخرج
      await t.enterText(find.byType(TextField), 'سكتر الجامعة 3');
      await settle(t, seconds: 1);
      expect(find.text('على أبراجٍ أخرى · 1'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('assign-device-423'))); // يُنقل من برجٍ آخر
      await settle(t, seconds: 1);
      expect(find.text('يُنقل من «برج الجامعة»'), findsOneWidget);
      expect(find.text('يدخل 3 أجهزة · يخرج جهاز واحد'), findsOneWidget);
      await t.enterText(find.byType(TextField), '');
      await settle(t, seconds: 1);
      await snap(t, 'assign_dirty', p390);

      await t.tap(find.byKey(const ValueKey('assign-save')));
      await settle(t, seconds: 5);
      final added = api.bodies['POST /api/v2/admin/devices/regions/3/assign']!.single['device_ids'] as List;
      final removed = api.bodies['POST /api/v2/admin/devices/regions/0/assign']!.single['device_ids'] as List;
      expect(added.toSet(), {901, 902, 423});
      expect(removed, [321]);
      expect(find.byType(TowerAssignScreen), findsNothing);
      // البرج والشريط يتحدّثان من الخادم
      expect(t.widget<TowerScreen>(find.byType(TowerScreen)).regionId, 3);
      expect(find.descendant(of: find.byKey(const ValueKey('towers-chip-3')), matching: find.text('5')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('towers-chip-4')), matching: find.text('4')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('towers-chip-0')), matching: find.text('1')), findsOneWidget, reason: 'خرج إلى «بلا منطقة»');
      await close(t);
    });

    testWidgets('«+ برج»: نموذج المنطقة ثمّ إسناد أجهزته فوراً — وبرجٌ فارغ يدعو للإسناد', (t) async {
      await boot(t, devices: [...fourTowersDevices(), _d(901, 'سكتر جديد 1', null)]);
      await openHub(t, p390);
      await t.ensureVisible(find.byKey(const ValueKey('towers-new')));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const ValueKey('towers-new')));
      await settle(t, seconds: 1);
      expect(find.text('برج جديد'), findsOneWidget);
      await snap(t, 'new_tower_form', p390);
      await t.enterText(find.byType(TextField), 'برج القرية');
      await t.tap(find.text('إضافة'));
      await settle(t, seconds: 2);
      expect(api.bodies['POST /api/v2/admin/devices/regions']!.single['name'], 'برج القرية');
      expect(find.byType(TowerAssignScreen), findsOneWidget, reason: 'الإسناد يُفتح فوراً');
      expect(find.text('أجهزة «برج القرية»'), findsOneWidget);
      await t.tap(find.byTooltip('إغلاق'));
      await settle(t, seconds: 2);
      // خرج بلا إسناد: البرج الجديد مفتوحٌ فارغاً ويدعو للإسناد
      final tower = t.widget<TowerScreen>(find.byType(TowerScreen));
      expect([tower.regionName, tower.devices], ['برج القرية', isEmpty]);
      expect(find.byKey(const ValueKey('tower-assign-empty')), findsOneWidget);
      await snap(t, 'empty_tower', p390);
      await close(t);
    });
  });

  group('الموظّف بلا «إدارة الأجهزة»', () {
    testWidgets('يرى الترابط كاملاً وأزرار التعديل بقفل — ولا طلب كتابة يخرج', (t) async {
      await boot(t);
      PermissionsService.debugSet(isEmployee: true, permissions: const {'devices.view': true});
      await openHub(t, p390);
      expect(find.text('4 أبراج · 3 لنكات'), findsOneWidget);
      await t.tap(find.byTooltip('ربط برجين — لنك أو كيبل'));
      await settle(t, seconds: 3);
      expect(find.byType(TowerLinkEditorScreen), findsNothing);
      await t.tap(find.byKey(const ValueKey('topo-pill-1-2')));
      await settle(t, seconds: 1);
      await t.tap(find.text('اقلب الاتّجاه'));
      await settle(t, seconds: 3);
      await t.tap(find.text('احذف الربط'));
      await settle(t, seconds: 3);
      await snap(t, 'employee_locked', p390);
      await t.tapAt(const Offset(195, 80)); // يغلق الورقة
      await settle(t, seconds: 1);
      await t.ensureVisible(find.byKey(const ValueKey('towers-chip-2')));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const ValueKey('towers-chip-2')));
      await settle(t, seconds: 2);
      await t.tap(find.byTooltip('أجهزة هذا البرج'));
      await settle(t, seconds: 3);
      expect(find.byType(TowerAssignScreen), findsNothing);
      expect(api.writes(), isEmpty);
      await close(t);
    });
  });
}
