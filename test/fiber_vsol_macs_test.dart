import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/olt_fiber_reads.dart';
import 'package:rad_mysvcs/api/olt_profile.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/api/vsol_gpon_details.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/services/fiber/fiber_monitor.dart';
import 'package:rad_mysvcs/services/fiber/fiber_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_snmp_agent.dart';

/// شبكة الألياف على VSOL EPON (٢٧ أكتوبر، المالك على V1600D: «الاولتي مجاي يقره لابورات ولامكات ويطابقه وي المتصلين»):
/// الأسماء «NULL» لكلّ جهاز، والماك لم يكن يُقرأ إلّا لـBDCOM — فلا شيء يطابق جلسات الساس. الآن ماك كلّ جهاز من
/// ifPhysAddress، و«NULL» ليست اسماً، والماك يُحفظ مع اللقطة فيعود فوراً عند الفتح التالي.
const _vsol = OltProfile(vendor: OltVendor.vsol, oltLikely: true, identified: true, model: 'V1600D');

class _Api implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final Object data = o.uri.path.endsWith('/fiber/rx') && o.method == 'GET' ? {'success': true, 'rows': []} : {'success': true};
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Backend extends FiberBackend {
  _Backend(this.agent);
  final FakeSnmpAgent agent;

  @override
  Future<String?> community(NetworkDevice d) async => 'fixture';

  @override
  SnmpV2c snmp(NetworkDevice d, String community) => agent;

  @override
  Future<VsolOltStats> structure(NetworkDevice d, String community, OltProfile p, {Map<int, String>? knownNames}) async =>
      VsolOltStats(
        sysDescr: 'V1600D',
        profile: _vsol,
        ponPorts: const [VsolPonPort(index: 1, slot: 0, port: 1, up: true, rxBytes: 0, txBytes: 0, onuTotal: 3, onuOnline: 2)],
        onus: const [
          VsolOnu(ifIndex: 27, slot: 0, ponPort: 1, onuId: 1, online: true, technology: VsolPonTechnology.epon),
          VsolOnu(ifIndex: 28, slot: 0, ponPort: 1, onuId: 2, online: true, technology: VsolPonTechnology.epon),
          VsolOnu(ifIndex: 29, slot: 0, ponPort: 1, onuId: 3, online: false, technology: VsolPonTechnology.epon),
        ],
      );

  @override
  Future<VsolOltStats> hot(NetworkDevice d, String community, VsolOltStats prev) async => prev;
}

NetworkDevice _dev() => NetworkDevice(
      id: 4415,
      adminId: '5',
      name: 'Moh',
      type: 'olt',
      brand: 'vsol',
      model: 'V1600D',
      ip: '10.0.0.4',
      port: 161,
      apiPort: 161,
      protocol: 'snmp',
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime.utc(2026),
    );

void main() {
  late FakeSnmpAgent agent;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth.token': 't', 'auth.admin_id': '5'});
    SharedPreferences.setMockInitialValues({});
    ApiClient.dio.httpClientAdapter = _Api();
    final interceptors = List<Interceptor>.of(ApiClient.dio.interceptors);
    ApiClient.dio.interceptors.clear();
    addTearDown(() => ApiClient.dio.interceptors
      ..clear()
      ..addAll(interceptors));
    OltFiberReads.debugReset();
    agent = FakeSnmpAgent({
      '${OltFiberReads.ifOperStatusOid}.27': snmpInt('', 1),
      '${OltFiberReads.ifOperStatusOid}.28': snmpInt('', 1),
      '${OltFiberReads.ifOperStatusOid}.29': snmpInt('', 2),
      // V1600D: «NULL» في خانة الاسم لكلّ جهاز
      '${OltFiberReads.ifAliasOid}.27': snmpText('', 'NULL'),
      '${OltFiberReads.ifAliasOid}.28': snmpText('', 'NULL'),
      '${OltFiberReads.ifAliasOid}.29': snmpText('', 'NULL'),
      '${OltFiberReads.vsolEponAuth}.9.1.1': snmpText('', 'NULL'),
      '${OltFiberReads.vsolEponAuth}.9.1.2': snmpText('', 'NULL'),
      '${OltFiberReads.vsolEponAuth}.9.1.3': snmpText('', 'NULL'),
      // ماك الـONU للمتّصلة، وصفرٌ للمفصولة
      '${OltFiberReads.ifPhysOid}.27': snmpBytes('', [0x7c, 0x6a, 0x60, 0x0e, 0x08, 0x07]),
      '${OltFiberReads.ifPhysOid}.28': snmpBytes('', [0x7c, 0x6a, 0x60, 0x0e, 0x09, 0x10]),
      '${OltFiberReads.ifPhysOid}.29': snmpBytes('', [0, 0, 0, 0, 0, 0]),
      OltFiberReads.sysUpTimeOid: snmpTicks('', 50000000),
      // جدول الماك الخاصّ بـVSOL: راوتر المشترك خلف EPON01ONU1، وماكٌ ثانٍ خلف EPON01ONU2
      '${VsolGponDetails.macOid}.1.10': snmpBytes('', [0x50, 0x3e, 0xaa, 0x01, 0x02, 0x03]),
      '${VsolGponDetails.portOid}.1.10': snmpText('', 'EPON01ONU1'),
      '${VsolGponDetails.macOid}.1.11': snmpBytes('', [0x50, 0x3e, 0xaa, 0x04, 0x05, 0x06]),
      '${VsolGponDetails.portOid}.1.11': snmpText('', 'EPON01ONU2'),
    });
    FiberMonitor.debugReset();
    FiberMonitor.backend = _Backend(agent);
    FiberStore.reset();
  });

  tearDown(FiberMonitor.debugReset);

  test('VSOL EPON: ماك كلّ جهاز من ifPhysAddress، و«NULL» ليست اسماً، والماك يُحفظ مع اللقطة', () async {
    final m = FiberMonitor.of(_dev());
    await m.tick();
    expect(m.error, isNull);
    final byIdx = {for (final o in m.onus) o.onu.ifIndex: o};
    expect(byIdx[27]!.onu.mac, '7c:6a:60:0e:08:07');
    expect(byIdx[27]!.ident, '7c6a600e0807', reason: 'هويّة الربط = الماك بلا فواصل');
    expect(byIdx[28]!.onu.mac, '7c:6a:60:0e:09:10');
    expect(byIdx[29]!.onu.mac, isNull, reason: 'ماكٌ صفريّ (مفصولة) لا يُعدّ');
    expect(m.onus.every((o) => (o.onu.name ?? '').toUpperCase() != 'NULL'), isTrue, reason: '«NULL» ليست اسم جهاز');

    final snap = m.snapshotJson()!;
    expect(snap['macs'], {'27': '7c:6a:60:0e:08:07', '28': '7c:6a:60:0e:09:10'});

    // الفتح التالي: لقطةٌ قديمة فيها «NULL» أسماءً ⇒ تُنظَّف، والماك يعود قبل أيّ قراءة.
    final old = Map<String, dynamic>.from(snap)..['names'] = {'27': 'NULL', '28': 'NULL', '29': 'NULL'};
    FiberMonitor.debugReset();
    final again = FiberMonitor.of(_dev())..applySnapshot(old);
    final restored = {for (final o in again.onus) o.onu.ifIndex: o};
    expect(restored[27]!.onu.mac, '7c:6a:60:0e:08:07');
    expect(restored[28]!.ident, '7c6a600e0910');
    expect(again.onus.every((o) => o.onu.name == null), isTrue);
  });

  test('VSOL EPON: الأجهزة خلف كلّ ONU من جدول الماك الخاصّ (BRIDGE-MIB لا ينسب لجهاز على V1600D)', () async {
    final m = FiberMonitor.of(_dev())..wantDevices = true;
    await m.tick();
    final byIdx = {for (final o in m.onus) o.onu.ifIndex: o};
    expect(byIdx[27]!.onu.learnedMacs, ['50:3e:aa:01:02:03']);
    expect(byIdx[28]!.onu.learnedMacs, ['50:3e:aa:04:05:06']);
    expect(byIdx[29]!.onu.learnedMacs, isEmpty, reason: 'المفصولة بلا أجهزة');
    expect(agent.walks.where((w) => w.startsWith('1.3.6.1.2.1.17.')), isEmpty, reason: 'لا BRIDGE-MIB على VSOL');
  });
}
