import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/bdcom_epon.dart';
import 'package:rad_mysvcs/api/cdata_olt.dart';
import 'package:rad_mysvcs/api/olt_get_tables.dart';
import 'package:rad_mysvcs/api/olt_profile.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_image.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_image_cdata_catalog.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/vsol_live_panel.dart';
import 'package:rad_mysvcs/services/device_stats_cache.dart';
import 'package:rad_mysvcs/theme/typography.dart';

import 'support/app_fonts.dart';

/// أولت C-Data EPON (٢٩ أكتوبر) — على حقائق أولت المالك المقيسة حيّاً (‏4 PON · 4 GE، ١٦٩ ONU)، بأولتٍ وهميّ **لا يعرف
/// إلّا GET**: فكلّ قراءةٍ هنا تُثبت أنّ القارئ لا يمسح، ولا يسأل فرع كلمات SNMP (`…34592.1.3.1.2`). القيم الخام
/// للضوء من الجهاز نفسه وطوبقت بواجهته (289 ⇒ ‎-15.39 dBm). الماكات اصطناعيّة (‏02:…).

Varbind _int(String oid, int v) {
  final out = <int>[];
  var x = v;
  while (true) {
    out.insert(0, x & 0xff);
    final sign = x & 0x80;
    x >>= 8;
    if ((x == 0 && sign == 0) || (x == -1 && sign != 0)) break;
  }
  return Varbind(oid: oid, rawTag: 0x02, rawBytes: Uint8List.fromList(out));
}

Varbind _c64(String oid, int v) {
  final out = <int>[];
  var x = v;
  do {
    out.insert(0, x & 0xff);
    x >>= 8;
  } while (x > 0);
  return Varbind(oid: oid, rawTag: 0x46, rawBytes: Uint8List.fromList(out));
}

Varbind _str(String oid, List<int> bytes) => Varbind(oid: oid, rawTag: 0x04, rawBytes: Uint8List.fromList(bytes));
Varbind _absent(String oid) => Varbind(oid: oid, rawTag: 0x81, rawBytes: Uint8List(0));

List<int> _mac(String m) => [for (final h in m.split(':')) int.parse(h, radix: 16)];

/// «unknown» محشوّاً بأصفار إلى ٣٠ — الاسم الافتراضيّ في كلّ صفوف أولت المالك.
List<int> _unknownName() => [...ascii.encode('unknown'), ...List.filled(23, 0)];

class _FakeCdata {
  final Map<String, Varbind> table = {};
  final List<String> asked = [];
  bool Function(List<String> oids)? fail;

  Future<List<Varbind>> get(List<String> oids) async {
    if (fail?.call(oids) ?? false) throw SnmpTimeoutException('timeout');
    asked.addAll(oids);
    return [for (final o in oids) table[o] ?? _absent(o)];
  }

  void put(Varbind vb) => table[vb.oid] = vb;
}

const _ifDescr = '1.3.6.1.2.1.2.2.1.2';
const _ifOper = '1.3.6.1.2.1.2.2.1.8';
const _ifHighSpeed = '1.3.6.1.2.1.31.1.1.1.15';
const _ifHCIn = '1.3.6.1.2.1.31.1.1.1.6';
const _ifHCOut = '1.3.6.1.2.1.31.1.1.1.10';
const _onuCol = '1.3.6.1.4.1.34592.1.3.4.1.1';

int _i(int pon, int onu) => CdataOlt.onuIndex(pon, onu);

/// صورة أولت المالك مصغّرة: ‏GE1..4 ثمّ PON1..4 في IF-MIB، ومتّصلةٌ بضوئها، ومفصولةٌ بماكها وأصفار ضوئها، واسمٌ
/// مكتوب، وONU برقم ٧٠ لا تظهر إلّا بمسح ما فوق الـ٦٤ (منفذٌ بلغ ٦٤).
_FakeCdata _fixture() {
  final f = _FakeCdata();
  f.put(_int(CdataOlt.ifNumberOid, 8));
  f.put(_str(CdataOlt.firmwareOid, [...ascii.encode('2.4.05_000(May 17 2018)'), ...List.filled(40, 0)]));
  const names = ['GE-1', 'GE-2', 'GE-3', 'GE-4', 'PON-1', 'PON-2', 'PON-3', 'PON-4'];
  for (var k = 1; k <= 8; k++) {
    f.put(_str('$_ifDescr.$k', ascii.encode('EPON System, ${names[k - 1]}')));
    f.put(_int('$_ifOper.$k', (k == 2 || k >= 5) ? 1 : 2));
    f.put(_int('$_ifHighSpeed.$k', 1000));
    f.put(_c64('$_ifHCIn.$k', k == 2 ? 36769927639983 : (k == 6 ? 1618781017775 : 0)));
    f.put(_c64('$_ifHCOut.$k', k == 2 ? 3759499574767 : (k == 6 ? 17920868057497 : 0)));
  }

  void onu(int pon, int id,
      {required int status, String? mac, List<int>? name, int? vendor, int? model, int? rx, int? tx, int? volt, int? temp}) {
    final i = _i(pon, id);
    f.put(_int(CdataOlt.statusOid(i), status));
    if (mac != null) f.put(_str(CdataOlt.macOid(i), _mac(mac)));
    f.put(_str(CdataOlt.nameOid(i), name ?? _unknownName()));
    f.put(_int(CdataOlt.vendorOid(i), vendor ?? 0));
    f.put(_int(CdataOlt.modelOid(i), model ?? 0));
    f.put(_int(CdataOlt.opticsOid(36, i), rx ?? 0));
    f.put(_int(CdataOlt.opticsOid(37, i), tx ?? 0));
    f.put(_int(CdataOlt.opticsOid(38, i), volt ?? 0));
    f.put(_int(CdataOlt.opticsOid(40, i), temp ?? 0));
  }

  // قيمٌ خامّ من الجهاز: 1/22 (HWTC، ‎-27.70)، 2/1 (ZTE، ‎-15.39 — طابقت واجهته 290 ⇒ ‎-15.38)، 4/3 (HWTC).
  onu(1, 1, status: 2, mac: '02:00:00:01:01:00');
  onu(1, 22, status: 3, mac: '02:00:00:01:16:00', vendor: 0x48575443, model: 0x01030008, rx: 17, tx: 15648, volt: 32950, temp: 11520);
  onu(2, 1, status: 3, mac: '02:00:00:02:01:00', name: utf8.encode('برج ٣ - علي'), vendor: 0x5A544500, model: 0x31303047,
      rx: 289, tx: 14387, volt: 32440, temp: 12285);
  onu(2, 64, status: 2, mac: '02:00:00:02:40:00');
  onu(2, 70, status: 3, mac: '02:00:00:02:46:00', rx: 0);
  onu(4, 3, status: 3, mac: '02:00:00:04:03:00', vendor: 0x48575443, rx: 26, tx: 16004, volt: 33060, temp: 11008);
  return f;
}

final _cdataProfile = OltProfile.resolve(OltProfile.fromRecord(brand: 'vsol'),
    sysObjectId: '1.3.6.1.4.1.34592', sysDescr: ' GEPON OLT');

void main() {
  group('الهويّة — المؤسّسة 34592 نفسها', () {
    test('سجلٌّ «vsol» + sysObjectID = المؤسّسة بلا ذيل ⇒ C-Data حيّاً', () {
      expect(_cdataProfile.vendor, OltVendor.cdata);
      expect(_cdataProfile.identified, isTrue);
      expect(_cdataProfile.opensOltPanel, isTrue);
      expect(_cdataProfile.label, 'C-Data OLT');
      expect(OltProfile.isCdataObjectId('1.3.6.1.4.1.34592.1.3'), isTrue);
      expect(OltProfile.isCdataObjectId('1.3.6.1.4.1.345920'), isFalse, reason: 'مؤسّسةٌ أخرى تبدأ بالأرقام نفسها');
      final fromVsolModel = OltProfile.resolve(OltProfile.fromRecord(brand: 'vsol', model: 'V1600D'),
          sysObjectId: '1.3.6.1.4.1.34592', sysDescr: ' GEPON OLT');
      expect(fromVsolModel.vendor, OltVendor.cdata);
      expect(fromVsolModel.model, isNull, reason: 'طراز VSOL كُتب خطأً لا يُعرض على C-Data');
    });

    test('من السجلّ: العلامة، أو «C-Data»/رمز FD في طراز vsol/other — ولا تُسرق علامةٌ لها لوحتها', () {
      expect(OltProfile.fromRecord(brand: 'cdata').vendor, OltVendor.cdata);
      expect(OltProfile.fromRecord(brand: 'other', model: 'C-Data OLT').vendor, OltVendor.cdata);
      expect(OltProfile.fromRecord(brand: 'vsol', model: 'FD1104S').vendor, OltVendor.cdata);
      expect(OltProfile.fromRecord(brand: 'other', name: 'CDATA-برج 3').vendor, OltVendor.cdata);
      expect(OltProfile.fromRecord(brand: 'mikrotik', model: 'C-Data').vendor, OltVendor.unknown);
      expect(OltProfile.fromRecord(brand: 'vsol', model: 'V1600D').vendor, OltVendor.vsol);
    });

    test('قدرات الملفّ: GET وحده، لا ماك واجهة، لا ترفك لكلّ ONU، لا جدول جسر، وعدّادات كلّ ~٤ث', () {
      expect(_cdataProfile.readsGetTables, isTrue);
      expect(_cdataProfile.readsCdataTables, isTrue);
      expect(_cdataProfile.readsHsgqTables, isFalse);
      expect(_cdataProfile.readsInterfaceMac, isFalse);
      expect(_cdataProfile.hasOnuCounters, isFalse);
      expect(_cdataProfile.readsBridgeFdb, isFalse);
      expect(_cdataProfile.countersRefresh, const Duration(seconds: 4));
      expect(OltGetTables.of(_cdataProfile), isNotNull);
      expect(OltGetTables.of(const OltProfile(vendor: OltVendor.hsgq)), isNotNull);
      expect(OltGetTables.of(OltProfile.vsolDefault), isNull);
      expect(OltProfile.vsolDefault.readsGetTables, isFalse);
    });
  });

  group('التحويل', () {
    test('الفهرس المحسوب لا يلتقي بفهارس IF-MIB', () {
      expect(_i(1, 22), 0x01010116);
      expect(CdataOlt.slotOf(_i(1, 22)), 1);
      expect(CdataOlt.ponOf(_i(1, 22)), 1);
      expect(CdataOlt.onuOf(_i(1, 22)), 22);
      expect(CdataOlt.statusOid(_i(2, 64)), '$_onuCol.11.1.2.64');
    });

    test('الحالة 3 متّصل و2 مفصول، والغائب لا ONU', () {
      expect(CdataOlt.onlineFrom(_int('x', 3)), isTrue);
      expect(CdataOlt.onlineFrom(_int('x', 2)), isFalse);
      expect(CdataOlt.onlineFrom(_int('x', 1)), isFalse);
      expect(CdataOlt.onlineFrom(_absent('x')), isNull);
      expect(CdataOlt.onlineFrom(_str('x', ascii.encode('3'))), isNull);
    });

    test('الضوء بوحدة ٠٫١ ميكروواط كما تحسبه واجهة الجهاز، والصفر ليس ضوءاً', () {
      expect(CdataOlt.rxFrom(_int('x', 289)), -15.39);
      expect(CdataOlt.rxFrom(_int('x', 0)), isNull);
      final r = CdataOlt.readingFrom(_int('a', 17), _int('b', 15648), _int('c', 32950), _int('d', 11520))!;
      expect(r.rxDbm, -27.7);
      expect(r.txDbm, 1.94);
      expect(r.voltV, 3.295);
      expect(r.tempC, 45.0);
      expect(CdataOlt.readingFrom(_int('a', 0), _int('b', 0), _int('c', 0), _int('d', 0)), isNull, reason: 'مفصولة: أصفار');
    });

    test('الصانع والطراز حروفٌ مرصوصة — والثنائيّ والصفر لا يُعرضان', () {
      expect(CdataOlt.packedText(_int('x', 0x48575443)), 'HWTC');
      expect(CdataOlt.packedText(_int('x', 0x5A544500)), 'ZTE');
      expect(CdataOlt.packedText(_int('x', 0x56534F4C)), 'VSOL');
      expect(CdataOlt.packedText(_int('x', 0x01030008)), isNull);
      expect(CdataOlt.packedText(_int('x', 0)), isNull);
    });

    test('الاسم: «unknown» والافتراضيّ يُهملان، والمكتوب يبقى', () {
      expect(CdataOlt.nameFrom(_str('x', _unknownName())), isNull);
      expect(CdataOlt.nameFrom(_str('x', ascii.encode('[ONU-22]'))), isNull);
      expect(CdataOlt.nameFrom(_str('x', List.filled(16, 0))), isNull);
      expect(CdataOlt.nameFrom(_str('x', utf8.encode('برج ٣ - علي'))), 'برج ٣ - علي');
      expect(CdataOlt.textFrom(_str('x', [...ascii.encode('2.4.05_000(May 17 2018)'), 0, 0])), '2.4.05_000(May 17 2018)');
    });
  });

  group('القراءة — GET وحده بفهارس محسوبة', () {
    test('لقطةٌ كاملة: المنافذ من IF-MIB، كلّ الـONU (وما فوق ٦٤)، الماك للمفصولة، والاسم المكتوب وحده', () async {
      final f = _fixture();
      final partials = <VsolOltStats>[];
      final s = await CdataOlt.fetchStats(f.get,
          profile: _cdataProfile, sysDescr: 'GEPON OLT', sysName: 'epon', withCounters: true, onPartialReady: partials.add);

      expect(partials.first.ponPorts, hasLength(4));
      expect(partials.first.onus, isEmpty, reason: 'المنافذ تُعرض قبل الـONU');
      expect(partials.last.onus, hasLength(6));

      expect(s.sysDescr, 'GEPON OLT · 2.4.05_000(May 17 2018)');
      expect(s.profile.vendor, OltVendor.cdata);
      expect([for (final o in s.onus) o.label], ['EPON0/1:1', 'EPON0/1:22', 'EPON0/2:1', 'EPON0/2:64', 'EPON0/2:70', 'EPON0/4:3']);
      expect(s.onusOnline, 4);
      expect(s.onus.every((o) => o.mac != null), isTrue, reason: 'الماك هويّة الـONU المسجّلة — للمفصولة أيضاً');
      expect({for (final o in s.onus) if (o.name != null) o.label: o.name}, {'EPON0/2:1': 'برج ٣ - علي'});
      expect([for (final p in s.ponPorts) '${p.label} ${p.onuOnline}/${p.onuTotal}'],
          ['EPON0/1 1/2', 'EPON0/2 2/3', 'EPON0/3 0/0', 'EPON0/4 1/1']);
      expect([for (final u in s.uplinks) '${u.name}${u.up ? '↑' : '↓'}'], ['GE1↓', 'GE2↑', 'GE3↓', 'GE4↓']);
      expect(s.narrowCounters, isFalse, reason: 'عدّادات ٦٤ بت تعمل على C-Data');
      expect(s.uplinks[1].rxBytes, 36769927639983);
      expect(s.ponPorts[1].txBytes, 17920868057497);

      // لا فرع كلمات SNMP، ولا عمود 4 (يُسقط الردّ للمفصولة)، ولا مسح ما فوق الـ٦٤ لمنفذٍ لم يبلغه.
      expect(f.asked.where((o) => o.startsWith('1.3.6.1.4.1.34592.1.3.1.2')), isEmpty);
      expect(f.asked.where((o) => o.startsWith('$_onuCol.4.')), isEmpty);
      expect(f.asked, contains(CdataOlt.statusOid(_i(2, 65))));
      expect(f.asked, isNot(contains(CdataOlt.statusOid(_i(1, 65)))));
    });

    test('جدولٌ غائب أو حالةٌ لم تُجب كاملة ⇒ استثناءٌ (تبقى آخر قراءةٍ صحيحة)، لا لقطةٌ ناقصة', () async {
      final noIf = _fixture()..table.remove(CdataOlt.ifNumberOid);
      await expectLater(CdataOlt.fetchStats(noIf.get, profile: _cdataProfile), throwsA(isA<VsolException>()));
      final lossy = _fixture()..fail = (oids) => oids.contains(CdataOlt.statusOid(_i(3, 20)));
      await expectLater(CdataOlt.fetchStats(lossy.get, profile: _cdataProfile), throwsA(isA<VsolException>()));
    });

    test('الحالة وحدها: يتبدّل المتّصل، وONU جديدة تُعدّ ‹unknown›، والناقص null', () async {
      final f = _fixture();
      final s = await CdataOlt.fetchStats(f.get, profile: _cdataProfile, withCounters: true);
      f.put(_int(CdataOlt.statusOid(_i(1, 1)), 3));
      f.put(_int(CdataOlt.statusOid(_i(3, 5)), 2));
      f.put(_int('$_ifOper.6', 2));
      final r = await OltGetTables.of(_cdataProfile)!.refreshStatus(f.get, s);
      expect(r, isNotNull);
      expect(r!.unknown, 1);
      expect(r.stats.onus.firstWhere((o) => o.label == 'EPON0/1:1').online, isTrue);
      expect(r.stats.ponPorts.firstWhere((p) => p.port == 2).up, isFalse);

      f.fail = (oids) => oids.any((o) => o.startsWith('$_onuCol.11.'));
      expect(await CdataOlt.refreshStatus(f.get, s), isNull);
    });

    test('عبر القارئ الموحّد: الضوء للمتّصلة، الصانع/الطراز، الاستقبال وحده، الحالة لأجهزةٍ بعينها، ولا معالج', () async {
      final f = _fixture();
      final t = OltGetTables.of(_cdataProfile)!;
      final online = [_i(1, 22), _i(2, 1), _i(2, 70), _i(4, 3)];
      final r = await t.readings(f.get, online);
      expect(r.keys, unorderedEquals([_i(1, 22), _i(2, 1), _i(4, 3)]), reason: 'rx صفرٌ وحده ⇒ لا قراءة');
      expect(r[_i(2, 1)]!.rxDbm, -15.39);
      expect(r[_i(2, 1)]!.tempC, 48.0);

      final ids = await t.identities(f.get, [_i(1, 1), _i(1, 22), _i(2, 1)]);
      expect(ids[_i(1, 22)]!.vendor, 'HWTC');
      expect(ids[_i(1, 22)]!.module, isNull, reason: 'رمزٌ ثنائيّ');
      expect(ids[_i(2, 1)]!.vendor, 'ZTE');
      expect(ids[_i(2, 1)]!.module, '100G');
      expect(ids.containsKey(_i(1, 1)), isFalse, reason: 'المفصولة مصفّرة');

      expect(await t.rxOnly(f.get, online), {_i(1, 22): -27.7, _i(2, 1): -15.39, _i(4, 3): -25.85});
      expect(await t.statusOf(f.get, [_i(1, 1), _i(1, 22), _i(3, 9)]), {_i(1, 1): false, _i(1, 22): true});
      expect((await t.chassis(f.get)).isEmpty, isTrue, reason: 'لا معالج مسمّى — «—» لا تخمين');
      expect(await t.names(f.get, [_i(1, 1), _i(2, 1)]), {_i(2, 1): 'برج ٣ - علي'});
    });
  });

  group('الترفك', () {
    VsolOltStats snap(int ponRx) => VsolOltStats(
          profile: _cdataProfile,
          ponPorts: [VsolPonPort(index: 5, slot: 0, port: 1, up: true, rxBytes: ponRx, txBytes: 10)],
          uplinks: const [VsolUplink(index: 2, name: 'GE2', up: true, speedMbps: 1000, rxBytes: 7, txBytes: 7)],
          onus: [VsolOnu(ifIndex: _i(1, 22), slot: 0, ponPort: 1, onuId: 22, online: true)],
        );

    test('عدّادٌ لم يتحدّث بعد = مؤجَّل لا صفر (كلّ ~٤ث)، وبعد تحديثين فائتين يُقبل الصفر', () {
      final a = snap(1000);
      expect(VsolTraffic.frozenBetween(_cdataProfile, a, a, const Duration(seconds: 3)), isTrue);
      expect(VsolTraffic.frozenBetween(_cdataProfile, a, snap(5000), const Duration(seconds: 3)), isFalse);
      expect(VsolTraffic.frozenBetween(_cdataProfile, a, a, const Duration(seconds: 9)), isFalse);
      final t0 = DateTime(2026, 10, 29, 1);
      final h = VsolTraffic.between(snap(1000), snap(5000), const Duration(seconds: 4));
      expect(h.containsKey('EPON0/1'), isTrue);
      expect(h.containsKey('EPON0/1:22'), isFalse, reason: 'لا عدّادات لكلّ ONU — لا «0 bps» كاذب');
      expect(t0.isBefore(DateTime(2026, 10, 30)), isTrue);
    });
  });

  group('الصورة — صورة الطراز الرسميّة، وإلّا صورة العائلة المقاربة (قرار المالك ٢٩ أكتوبر)', () {
    const file = 'cdata/C-Data-FD1104SN-R1.webp';

    test('سجلّ C-Data بلا طراز أو «C-Data OLT» ⇒ صورة العائلة؛ وطرازٌ رسميّ ⇒ صورته؛ وغير C-Data لا يأخذها', () {
      expect(kCdataFamilyPhoto, file);
      expect(DeviceImage.assetFor(null, brand: 'cdata'), file);
      expect(DeviceImage.assetFor('', brand: 'cdata'), file);
      expect(DeviceImage.assetFor('C-Data OLT', brand: 'vsol'), file, reason: 'ما يكتبه الكاشف على سجلّ vsol');
      expect(DeviceImage.assetFor('C-Data OLT', brand: 'other'), file);
      expect(DeviceImage.assetFor('FD1304S-B2', brand: 'cdata'), 'olt/FD1304S-B2.png', reason: 'الرسميّة تسبق المقاربة');
      expect(DeviceImage.assetFor('C-Data FD1608S-B1', brand: 'other'), 'olt/FD1608S-B1.jpg');
      expect(DeviceImage.assetFor('FD1608S-B1', brand: 'other'), 'olt/FD1608S-B1.jpg', reason: 'كما كان');
      expect(DeviceImage.assetFor(null, brand: 'vsol'), isNull);
      expect(DeviceImage.assetFor(null, brand: 'hsgq'), isNull);
      expect(DeviceImage.assetFor('V1600D', brand: 'vsol'), isNot(file));
      expect(DeviceImage.assetFor('C-Data', brand: 'mikrotik'), isNot(file), reason: 'علامةٌ لها لوحتها');
      expect(DeviceImage.assetFor('HSGQ-XE04R', brand: 'hsgq'), 'hsgq/HSGQ-XE04R.webp', reason: 'HSGQ كما كان');
    });

    test('المنتقي ذهاباً وإياباً، والملفّ WebP حقيقيّ بأبعاده الموثّقة', () {
      expect(DeviceImage.allAssets, contains(file));
      expect(DeviceImage.boardNameOf(file), 'C-Data-FD1104SN-R1');
      expect(DeviceImage.assetFor(DeviceImage.boardNameOf(file), brand: 'vsol'), file);
      expect(DeviceImage.assetFor(DeviceImage.boardNameOf(file), brand: 'cdata'), file);
      final b = File('assets/devices-images/$file').readAsBytesSync();
      expect(ascii.decode(b.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(b.sublist(8, 12)), 'WEBP');
      expect(ascii.decode(b.sublist(12, 16)), 'VP8 ');
      final w = (b[26] | (b[27] << 8)) & 0x3fff;
      final h = (b[28] | (b[29] << 8)) & 0x3fff;
      expect('${w}x$h', '481x66');
    });
  });

  group('اللوحة', () {
    late List<Interceptor> oldInterceptors;
    setUpAll(loadAppFonts);
    setUp(() {
      oldInterceptors = List<Interceptor>.of(ApiClient.dio.interceptors);
      ApiClient.dio.interceptors
        ..clear(keepImplyContentTypeInterceptor: false)
        ..add(InterceptorsWrapper(onRequest: (o, h) => h.reject(DioException(requestOptions: o, error: 'offline fixture'))));
    });
    tearDown(() {
      ApiClient.dio.interceptors
        ..clear(keepImplyContentTypeInterceptor: false)
        ..addAll(oldInterceptors);
    });

    VsolOltStats seed() {
      final at = DateTime.now();
      return CdataOlt.buildStats(
        profile: _cdataProfile,
        sysDescr: 'GEPON OLT · 2.4.05_000(May 17 2018)',
        sysName: 'epon',
        ports: const [
          VsolIfRow(index: 2, name: 'EPON System, GE-2', up: true, mac: null, speedMbps: 1000, rxBytes: 0, txBytes: 0),
          VsolIfRow(index: 5, name: 'EPON System, PON-1', up: true, mac: null, speedMbps: 1000, rxBytes: 0, txBytes: 0),
          VsolIfRow(index: 6, name: 'EPON System, PON-2', up: true, mac: null, speedMbps: 1000, rxBytes: 0, txBytes: 0),
        ],
        status: {_i(1, 22): true, _i(1, 1): false},
        macs: {_i(1, 22): '02:00:00:01:16:00', _i(1, 1): '02:00:00:01:01:00'},
      ).withEponDetails(OltEponDetails(
        readings: {_i(1, 22): const BdcomOnuReading(rxDbm: -15.39, txDbm: 1.58, tempC: 48, voltV: 3.244)},
        readingsAt: at,
        identities: {_i(1, 22): const BdcomOnuReading(vendor: 'ZTE', module: '100G')},
        macsAt: at,
        chassis: const BdcomChassis(),
        chassisAt: at,
      ));
    }

    NetworkDevice device(int id) => NetworkDevice(
          id: id,
          adminId: 'fixture',
          name: 'OLT',
          type: 'other',
          brand: 'cdata',
          ip: '127.0.0.1',
          port: 161,
          apiPort: 161,
          protocol: 'snmp',
          lastStatus: 'online',
          createdAt: DateTime.utc(2026),
        );

    testWidgets('هاتف ٣٢٠: الماك للمتّصلة والمفصولة، والضوء، ولا معالج ولا سطر ترفكٍ للـONU', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      const id = 99005031;
      DeviceStatsCache.instance.putRaw(id, seed());
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: AppType.family),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SingleChildScrollView(child: VsolLivePanel(device: device(id)))),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'لا فيضان على ٣٢٠');
      expect(find.text('02:00:00:01:16:00'), findsOneWidget);
      expect(find.text('02:00:00:01:01:00'), findsOneWidget, reason: 'ماك المفصولة هويّتها المسجّلة');
      expect(find.textContaining('RX -15.4 dBm'), findsOneWidget);
      expect(find.textContaining('CPU'), findsNothing, reason: 'لا معالج مسمّى على C-Data');
      expect(find.byKey(const ValueKey('EPON0/1:22')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('EPON0/1:22')), matching: find.text('▼ تنزيل')), findsNothing);
      expect(find.textContaining('أجهزة خلف الـONU'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
