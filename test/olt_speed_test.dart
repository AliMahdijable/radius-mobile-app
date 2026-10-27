import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/olt_fiber_reads.dart';
import 'package:rad_mysvcs/api/olt_profile.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/fiber_network.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/services/fiber/fiber_monitor.dart';
import 'package:rad_mysvcs/services/fiber/fiber_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_snmp_agent.dart';

/// سرعة الأولت الكبير البعيد — «Moh» (٢٧ أكتوبر، المالك: «كلش يتاخر بفتح الاولتي… سرعة الاستجابة وعرض المعلومات مهمّة
/// جداً… هلشي بكل olt»): VSOL V1600D بـ٣٠٢ جهاز (١٩٧ متّصل) على ٨ منافذ، رحلة ~٢٥٠ مللي، ووكيلٌ يعالج ~١٠٠ قيمة/ث.
/// كانت الدورة الأولى ~٢٣٥٠ قيمة و٩٠ ثانية قبل أوّل عرض. هنا تُثبَّت المراحل وكلفتها بالقيم (مقياس الوكيل) لا بالثواني.
class _Server implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    Object data = {'success': true};
    if (o.uri.path.endsWith('/fiber/rx') && o.method == 'GET') data = {'success': true, 'rows': []};
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _vsol = OltProfile(vendor: OltVendor.vsol, oltLikely: true, identified: true, model: 'V1600D');

/// ٨ منافذ: الأوّل ٤٣ جهازاً والبقيّة ٣٧ (= ٣٠٢)؛ ١٠٥ مفصولة (كلّ ثالثٍ وخمسةٌ أخرى) — كأرقام «Moh» الحقيقيّة.
class _Moh {
  final online = <int, bool>{};
  final names = <int, String>{};
  final agent = FakeSnmpAgent({});
  final List<({int ifIndex, int pon, int id})> onus = [];
  int structureCalls = 0, statusCalls = 0;

  _Moh() {
    for (var p = 1; p <= 8; p++) {
      names[p] = 'EPON0/$p';
    }
    for (var u = 1; u <= 4; u++) {
      names[20 + u] = 'GE0/$u';
    }
    names[50] = 'vlan1'; // واجهةٌ معروفة لا تُعرض — لا تُعدّ «جديدة»
    var idx = 1000;
    var k = 0;
    for (var p = 1; p <= 8; p++) {
      for (var id = 1; id <= (p == 1 ? 43 : 37); id++) {
        idx++;
        k++;
        onus.add((ifIndex: idx, pon: p, id: id));
        names[idx] = 'EPON0/$p:$id';
        online[idx] = !(k % 3 == 0 || const {1, 4, 7, 10, 13}.contains(k));
      }
    }
    final up = 90000000;
    agent.put(OltFiberReads.sysUpTimeOid, snmpTicks('', up));
    for (final o in onus) {
      agent.put('${OltFiberReads.ifLastChangeOid}.${o.ifIndex}', snmpTicks('', up - 60000 - o.id * 10));
      agent.put('${OltFiberReads.ifOperStatusOid}.${o.ifIndex}', snmpInt('', online[o.ifIndex]! ? 1 : 2));
      if (online[o.ifIndex]!) {
        // صيغة V1600D: الميلّيواط أوّلاً.
        agent.put('${OltFiberReads.vsolEponOptics}.7.${o.pon}.${o.id}', snmpText('', '0.0070 mW(-21.55dBm)'));
      } else {
        agent.put('${OltFiberReads.vsolEponAuth}.15.${o.pon}.${o.id}', snmpInt('', 0));
      }
    }
    agent.put('${OltFiberReads.ifAliasOid}.1001', snmpText('', 'علي كريم'));
  }

  int get offline => online.values.where((v) => !v).length;

  VsolOltStats stats() {
    final list = [
      for (final o in onus)
        VsolOnu(ifIndex: o.ifIndex, slot: 0, ponPort: o.pon, onuId: o.id, online: online[o.ifIndex]!),
    ];
    return VsolOltStats(
      profile: _vsol,
      ponPorts: [
        for (var p = 1; p <= 8; p++)
          VsolPonPort(
            index: p,
            slot: 0,
            port: p,
            up: true,
            rxBytes: 0,
            txBytes: 0,
            onuTotal: list.where((o) => o.ponPort == p).length,
            onuOnline: list.where((o) => o.ponPort == p && o.online).length,
          ),
      ],
      uplinks: [
        for (var u = 1; u <= 4; u++) VsolUplink(index: 20 + u, name: 'GE0/$u', up: u == 1, speedMbps: 1000, rxBytes: 0, txBytes: 0),
      ],
      onus: list,
      ifNames: Map.unmodifiable(names),
    );
  }
}

class _Backend extends FiberBackend {
  _Backend(this.olt);
  final _Moh olt;
  int extraIfIndex = 0;

  @override
  Future<String?> community(NetworkDevice d) async => 'fixture';
  @override
  SnmpV2c snmp(NetworkDevice d, String community) => olt.agent;
  @override
  Future<VsolOltStats> structure(NetworkDevice d, String community, OltProfile p, {Map<int, String>? knownNames}) async {
    olt.structureCalls++;
    return olt.stats();
  }

  @override
  Future<({VsolOltStats stats, int unknown})?> status(NetworkDevice d, String community, VsolOltStats prev) async {
    olt.statusCalls++;
    return VsolOltApi.applyStatus(prev, {
      for (final e in olt.names.keys) e: olt.online[e] ?? true,
      if (extraIfIndex > 0) extraIfIndex: true,
    });
  }

  @override
  Future<VsolOltStats> hot(NetworkDevice d, String community, VsolOltStats prev) async => prev;
}

NetworkDevice _dev() => NetworkDevice(
      id: 5267,
      adminId: '2251',
      name: 'Moh',
      type: 'other',
      brand: 'vsol',
      model: 'V1600D',
      ip: '10.200.222.51',
      port: 161,
      apiPort: 161,
      protocol: 'snmp',
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime.utc(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Moh olt;
  late _Backend backend;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth.token': 't', 'auth.admin_id': '2251'});
    SharedPreferences.setMockInitialValues({});
    ApiClient.dio.httpClientAdapter = _Server();
    OltFiberReads.debugReset();
    olt = _Moh();
    backend = _Backend(olt);
    FiberMonitor.debugReset();
    FiberMonitor.backend = backend;
    FiberStore.reset();
    FiberStore.debugSet(FiberLayout.empty, admin: '2251');
  });

  tearDown(FiberMonitor.debugReset);

  test('الدورة الأولى: الحالة تُعرض قبل الضوء، والضوء شريحةٌ بأربع قيمٍ بالطلب، ولحظة السقوط للمفصولة وحدها', () async {
    expect(olt.onus.length, 302);
    expect(olt.offline, 105);
    final m = FiberMonitor.of(_dev());
    final seen = <({int onus, int rx})>[];
    m.addListener(() => seen.add((onus: m.onus.length, rx: m.onus.where((o) => o.rx != null).length)));
    await m.tick();

    final firstShown = seen.firstWhere((e) => e.onus == 302);
    expect(firstShown.rx, 0, reason: 'المتّصل/المفصول يُرسم قبل انتظار الضوء');
    // ٢٧ أكتوبر، مقيس على V1600D: جدول الضوء يُحسب جهازاً جهازاً — مسحه ~ثانية للصفّ ويخنق الوكيل ⇒ شريحة ٢٤ كلّ دورة.
    expect(m.onus.where((o) => o.rx != null).length, 24);
    expect(m.onus.firstWhere((o) => o.online).rx, -21.55, reason: 'صيغة V1600D تُقرأ صحيحة');

    final asked = olt.agent.gets.expand((g) => g).toList();
    expect(olt.agent.walks.where((w) => w.startsWith(OltFiberReads.vsolEponOptics)), isEmpty, reason: 'لا مسح لجدول الضوء');
    final optGets = olt.agent.gets.where((g) => g.any((o) => o.startsWith(OltFiberReads.vsolEponOptics))).toList();
    expect(optGets.every((g) => g.length <= 4), isTrue, reason: 'أربع قيمٍ بالطلب — أكثر يتجاوز المهلة على V1600D');
    expect(asked.where((o) => o.startsWith('${OltFiberReads.vsolEponOptics}.7.')).length, lessThanOrEqualTo(24 + 4),
        reason: 'شريحةٌ واحدة (+ عيّنة فحص القدرات)');
    // المفصولة وحدها (+ عيّنة فحص القدرات مرّةً بالجلسة: ٤ متّصلة و٦ مفصولة).
    expect(asked.where((o) => o.startsWith('${OltFiberReads.ifLastChangeOid}.')).length, lessThanOrEqualTo(105 + 10));
    expect(asked.where((o) => o.startsWith('${OltFiberReads.vsolEponAuth}.15.')).length, lessThanOrEqualTo(105 + 12));
    // الكلفة على الوكيل (قيمٌ لا ثوانٍ): كانت ~١٨٢٠ قيمة لهذه المراحل (لحظات الكلّ + ٤ قيم ضوء للمتّصل + الأسماء بالسؤال).
    // + عمود الماك (~٣٣٠، مرّةً كلّ نصف ساعة ويُحفظ مع اللقطة) — به يطابق «ربط المشتركين» على VSOL.
    expect(olt.agent.values, lessThan(1000), reason: 'قيم الدورة الأولى عبر SNMP: ${olt.agent.values}');
    expect(m.stale, isFalse);
  });

  test('الدورة الثانية: عمود الحالة وحده — لا بنية ولا أسماء ولا ضوء قبل موعده', () async {
    final m = FiberMonitor.of(_dev());
    await m.tick();
    expect([olt.structureCalls, olt.statusCalls], [1, 0]);
    await Future<void>.delayed(const Duration(milliseconds: 50)); // فحص القدرات (مرّةً بالجلسة) ينتهي
    final before = olt.agent.values;
    final walksBefore = olt.agent.walks.length;
    olt.online[1002] = false; // جهازٌ متّصل يسقط
    olt.agent.put('${OltFiberReads.vsolEponAuth}.15.1.2', snmpInt('', 2));
    await m.tick();
    expect([olt.structureCalls, olt.statusCalls], [1, 1]);
    expect(olt.agent.walks.length, walksBefore, reason: 'لا مسح: لا أسماء (قبل نصف الساعة) ولا ماك (قبل نصف الساعة)');
    expect(olt.agent.values - before, lessThan(10 + 24), reason: 'لحظة الساقط وسببه + شريحة ضوء (٢٤)');
    final dropped = m.onus.firstWhere((o) => o.onu.ifIndex == 1002);
    expect(dropped.online, isFalse);
    expect(dropped.changedAt, isNotNull);
  });

  test('واجهةٌ لا تعرفها البنية (ONU سُجّلت للتوّ) ⇒ البنية في الدورة التالية', () async {
    final m = FiberMonitor.of(_dev());
    await m.tick();
    backend.extraIfIndex = 2000;
    await m.tick();
    expect([olt.structureCalls, olt.statusCalls], [1, 1]);
    await m.tick();
    expect(olt.structureCalls, 2);
  });

  test('applyStatus: المتّصل والمفصول وعدّ المنافذ، والمسح الناقص لا يُعرض كأنّ نصف الأجهزة فصلت', () {
    final s = olt.stats();
    final oper = {for (final i in olt.names.keys) i: olt.online[i] ?? true};
    expect(olt.online[1002], isTrue);
    oper[1002] = false;
    final r = VsolOltApi.applyStatus(s, oper)!;
    expect(r.unknown, 0, reason: 'vlan1 معروفةٌ في الأسماء');
    expect(r.stats.onus.firstWhere((o) => o.ifIndex == 1002).online, isFalse);
    final p1 = r.stats.ponPorts.firstWhere((p) => p.port == 1);
    expect([p1.onuTotal, p1.onuOnline], [43, s.ponPorts.first.onuOnline - 1]);
    final partial = Map.of(oper)..removeWhere((k, _) => k > 1100);
    expect(VsolOltApi.applyStatus(s, partial), isNull);
    expect(VsolOltApi.applyStatus(s, const {}), isNull);
  });

  test('اللقطة المحفوظة تُرسم فوراً «محفوظة»، ثمّ الحالة وحدها تجعلها حيّة', () async {
    final m = FiberMonitor.of(_dev());
    await m.tick();
    final snap = m.snapshotJson()!;
    expect(jsonEncode(snap).length, lessThan(40000));

    FiberMonitor.resetAll();
    final m2 = FiberMonitor.of(_dev());
    m2.applySnapshot(jsonDecode(jsonEncode(snap)) as Map<String, dynamic>);
    expect(m2.stale, isTrue);
    expect(m2.onus.length, 302);
    expect(m2.onus.where((o) => o.rx != null).length, 24, reason: 'الضوء من اللقطة (شريحة الدورة الأولى)');
    final structures = olt.structureCalls;
    final values = olt.agent.values;
    await m2.tick();
    expect(m2.stale, isFalse);
    expect(olt.structureCalls, structures, reason: 'اللقطة تحمل الأسماء ⇒ الحالة وحدها');
    // لقطةٌ حديثة: لا أسماء من جديد، ولا لحظات/أسباب لما بقي مفصولاً — الضوء وحده (عموده) + عيّنة فحص القدرات.
    expect(olt.agent.walks.where((w) => w == OltFiberReads.ifAliasOid).length, 1, reason: 'الأسماء من الدورة الأولى وحدها');
    expect(olt.agent.values - values, lessThan(260), reason: 'الفتحة الثانية: ${olt.agent.values - values} قيمة');
    expect(m2.onus.where((o) => !o.online && o.changedAt != null).length, greaterThanOrEqualTo(100), reason: 'لحظاتها من اللقطة');
  });

  test('الحزمة الضائعة تُعاد على المنفذ نفسه قبل انقضاء المهلة', () async {
    final server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    var received = 0;
    server.listen((e) {
      if (e != RawSocketEvent.read) return;
      final dg = server.receive();
      if (dg == null) return;
      received++;
      if (received == 1) return; // الأولى «تضيع»
      // ردٌّ صالح: الطلب نفسه بنوع GetResponse (0xA2) بدل GetRequest (0xA0).
      final b = Uint8List.fromList(dg.data);
      final i = b.indexOf(0xA0);
      b[i] = 0xA2;
      server.send(b, dg.address, dg.port);
    });
    final snmp = SnmpV2c(host: '127.0.0.1', port: server.port, timeout: const Duration(seconds: 2));
    final t0 = DateTime.now();
    final r = await snmp.get([OltFiberReads.sysUpTimeOid]);
    final took = DateTime.now().difference(t0);
    server.close();
    expect(r, hasLength(1));
    expect(received, 2);
    expect(took, lessThan(const Duration(milliseconds: 1500)), reason: 'أُعيدت بعد ~٠٫٩ث لا بعد المهلة كلّها');
  });
}
