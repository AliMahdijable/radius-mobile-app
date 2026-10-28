import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/bdcom_epon.dart';
import 'package:rad_mysvcs/api/hsgq_olt.dart';
import 'package:rad_mysvcs/api/olt_profile.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/core/platform/desktop_layout.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_image.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/vsol_live_panel.dart';
import 'package:rad_mysvcs/services/device_stats_cache.dart';
import 'package:rad_mysvcs/theme/typography.dart';

import 'support/app_fonts.dart';

/// أولت HSGQ EPON (٢٨ أكتوبر) — على حقائق أولت المالك المقيسة حيّاً، بأولتٍ وهميّ **لا يعرف إلّا GET**: فكلّ قراءةٍ
/// هنا تُثبت أنّ القارئ لا يمسح (GETBULK/GETNEXT يُعلّقان وكيل HSGQ) ولا يسأل عدّادات ٦٤ بت (يُهمَل طلبها كلّه).
/// الماكات اصطناعيّة (‏02:…).

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

Varbind _str(String oid, List<int> bytes) => Varbind(oid: oid, rawTag: 0x04, rawBytes: Uint8List.fromList(bytes));
Varbind _absent(String oid) => Varbind(oid: oid, rawTag: 0x81, rawBytes: Uint8List(0));

List<int> _mac(String m) => [for (final h in m.split(':')) int.parse(h, radix: 16)];

/// أولتٌ وهميّ بتخطيط HSGQ: GET وحده، والمجهول «غير موجود» (كالجهاز). [fail] يُسقط الطلب كمهلةٍ ضائعة.
class _FakeHsgq {
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
const _ifIn = '1.3.6.1.2.1.2.2.1.10';
const _ifOut = '1.3.6.1.2.1.2.2.1.16';

int _i(int pon, int onu) => HsgqOlt.onuIndex(pon, onu);

/// صورة أولت المالك مصغّرة: ‏4 PON · 4 GE · 4 XGE، وفجوةٌ في الأرقام، ومفصولةٌ بماكها، وأخرى لم تُسجَّل قطّ، واسمٌ
/// افتراضيٌّ لموضعٍ آخر، واسمٌ عربيّ مكتوب، وONU برقم ٧٠ لا تظهر إلّا بمسح ما فوق الـ٦٤.
_FakeHsgq _fixture() {
  final f = _FakeHsgq();
  f.put(_int(HsgqOlt.ponCountOid, 4));
  f.put(_int(HsgqOlt.portCountOid, 12));
  f.put(_str(HsgqOlt.firmwareOid, [...ascii.encode('I_V3.1.20C_Rel'), ...List.filled(18, 0)]));
  f.put(_int(HsgqOlt.cpuOid, 11));
  const names = ['PON01', 'PON02', 'PON03', 'PON04', 'GE01', 'GE02', 'GE03', 'GE04', 'XGE01', 'XGE02', 'XGE03', 'XGE04'];
  for (var k = 1; k <= 12; k++) {
    f.put(_str('$_ifDescr.$k', ascii.encode(names[k - 1])));
    f.put(_int('$_ifOper.$k', k <= 5 ? 1 : 2));
    f.put(_int('$_ifHighSpeed.$k', k <= 8 ? (k <= 5 ? 1000 : 0) : 10000));
    f.put(_int('$_ifIn.$k', k == 1 ? 2498855 : (k == 5 ? 409254 : 0)));
    f.put(_int('$_ifOut.$k', k == 1 ? 3392962 : (k == 5 ? 2646126 : 0)));
  }
  // صفّ ONU في IF-MIB (‏١٣) — طُعم: القارئ لا يقرأ بعد عدد المنافذ.
  f.put(_str('$_ifDescr.13', ascii.encode('ONU01/01')));

  void onu(int pon, int id, {required int status, String? mac, List<int>? name, String? vendor, String? model, int? rx, int? tx, int? volt, int? temp}) {
    final i = _i(pon, id);
    f.put(_int(HsgqOlt.statusOid(i), status));
    if (mac != null) f.put(_str(HsgqOlt.macOid(i), _mac(mac)));
    if (name != null) f.put(_str(HsgqOlt.nameOid(i), name));
    if (vendor != null) f.put(_str(HsgqOlt.vendorOid(i), ascii.encode(vendor)));
    if (model != null) f.put(_str(HsgqOlt.modelOid(i), ascii.encode(model)));
    if (rx != null) f.put(_int(HsgqOlt.opticsOid(4, i), rx));
    if (tx != null) f.put(_int(HsgqOlt.opticsOid(5, i), tx));
    if (volt != null) f.put(_int(HsgqOlt.opticsOid(7, i), volt));
    if (temp != null) f.put(_int(HsgqOlt.opticsOid(8, i), temp));
  }

  onu(1, 1, status: 1, mac: '02:00:00:01:01:00', name: ascii.encode('ONU02/06'), vendor: 'HWTC', model: '145C631', rx: -1823, tx: 220, volt: 329, temp: 4500);
  onu(1, 2, status: 2, mac: '02:00:00:01:02:00', name: ascii.encode('ONU01/02'), vendor: 'HWTC', model: '545M631');
  onu(1, 4, status: 1, mac: '02:00:00:01:04:00', name: utf8.encode('برج ٢ - أحمد'), vendor: 'MONU', rx: -2795, tx: 181);
  onu(2, 1, status: 2, mac: '02:00:00:02:01:00', name: ascii.encode('ONU02/01'));
  onu(4, 60, status: 1, mac: '02:00:00:04:3c:00', name: ascii.encode('NULL'), vendor: 'HWTC', model: '245C631', rx: -764, tx: 762, volt: 339, temp: 5996);
  onu(4, 70, status: 1, mac: '02:00:00:04:46:00', rx: 0);
  return f;
}

final _hsgqProfile = OltProfile.resolve(OltProfile.fromRecord(brand: 'vsol'),
    sysObjectId: '1.3.6.1.4.1.50224.3.1.1', sysDescr: 'EPON OLT');

void main() {
  group('الهويّة — المؤسّسة لا الاسم', () {
    test('سجلٌّ «vsol» بلا طراز + المؤسّسة 50224 ⇒ HSGQ حيّاً، ولا يُستعار طراز VSOL', () {
      expect(_hsgqProfile.vendor, OltVendor.hsgq);
      expect(_hsgqProfile.identified, isTrue);
      expect(_hsgqProfile.opensOltPanel, isTrue);
      final fromVsolModel = OltProfile.resolve(OltProfile.fromRecord(brand: 'vsol', model: 'V1600D'),
          sysObjectId: '1.3.6.1.4.1.50224.3.1.1', sysDescr: 'EPON OLT');
      expect(fromVsolModel.vendor, OltVendor.hsgq);
      expect(fromVsolModel.model, isNull, reason: 'طراز VSOL كُتب خطأً لا يُعرض على HSGQ');
      final own = OltProfile.resolve(OltProfile.fromRecord(brand: 'hsgq', model: 'E04I'),
          sysObjectId: '1.3.6.1.4.1.50224.3.1.1', sysDescr: 'EPON OLT');
      expect(own.model, 'E04I');
    });

    test('من السجلّ: العلامة، أو «HSGQ» كلمةً في طراز vsol/other', () {
      expect(OltProfile.fromRecord(brand: 'hsgq').vendor, OltVendor.hsgq);
      expect(OltProfile.fromRecord(brand: 'other', model: 'HSGQ OLT').vendor, OltVendor.hsgq);
      expect(OltProfile.fromRecord(brand: 'vsol', name: 'HSGQ-برج 3').vendor, OltVendor.hsgq);
      expect(OltProfile.fromRecord(brand: 'other', model: 'HSGQX1').vendor, OltVendor.unknown, reason: 'جزءٌ من كلمة');
      expect(OltProfile.fromRecord(brand: 'mikrotik', name: 'hsgq uplink').vendor, OltVendor.unknown);
      expect(OltProfile.fromRecord(brand: 'other', model: 'HSGQ OLT').opensOltPanel, isTrue);
    });

    test('وصف «EPON OLT» وحده لا يكفي، وBDCOM/VSOL كما كانا', () {
      final generic = OltProfile.resolve(OltProfile.unknown, sysObjectId: '1.3.6.1.4.1.99999.1', sysDescr: 'EPON OLT');
      expect(generic.vendor, OltVendor.unknown);
      expect(OltProfile.resolve(OltProfile.unknown, sysObjectId: '1.3.6.1.4.1.3320.1.495.0', sysDescr: 'x').vendor, OltVendor.bdcom);
      expect(OltProfile.resolve(OltProfile.unknown, sysObjectId: '1.3.6.1.4.1.37950.1.1', sysDescr: 'x').vendor, OltVendor.vsol);
    });

    test('قدرات HSGQ: GET وحده، بلا ماك واجهة ولا ترفك ONU ولا جدول جسر، وعدّاداتٌ كلّ ~٣١ث', () {
      expect(_hsgqProfile.readsHsgqTables, isTrue);
      expect(_hsgqProfile.readsInterfaceMac, isFalse);
      expect(_hsgqProfile.hasOnuCounters, isFalse);
      expect(_hsgqProfile.readsBridgeFdb, isFalse);
      expect(_hsgqProfile.countersRefresh, const Duration(seconds: 31));
      expect(_hsgqProfile.label, 'HSGQ OLT');
      const vsol = OltProfile.vsolDefault;
      expect(vsol.hasOnuCounters, isTrue);
      expect(vsol.readsBridgeFdb, isTrue);
      expect(vsol.countersRefresh, isNull);
      expect(vsol.readsInterfaceMac, isTrue);
      expect(const OltProfile(vendor: OltVendor.bdcom).readsBridgeFdb, isTrue);
      expect(OltProfile.unknown.readsBridgeFdb, isFalse);
    });
  });

  group('التحويل', () {
    test('الفهرس: الخانة ١ · المنفذ · الـONU', () {
      expect(HsgqOlt.onuIndex(1, 7), 16777479);
      expect(HsgqOlt.ponOf(16777479), 1);
      expect(HsgqOlt.onuOf(16777479), 7);
      expect(HsgqOlt.onuIndex(4, 70), 0x01000446);
    });

    test('الحالة 1 متّصل، 2/3 مفصول، الغائب لا ONU، والنصّ ليس حالة', () {
      expect(HsgqOlt.onlineFrom(_int('x', 1)), isTrue);
      expect(HsgqOlt.onlineFrom(_int('x', 2)), isFalse);
      expect(HsgqOlt.onlineFrom(_int('x', 3)), isFalse);
      expect(HsgqOlt.onlineFrom(_absent('x')), isNull);
      expect(HsgqOlt.onlineFrom(_str('x', ascii.encode('1'))), isNull);
    });

    test('البرمجيّة حتّى أوّل صفر، والضوء بوحدة ٠٫٠١ مع حارس المعقول', () {
      expect(HsgqOlt.firmwareFrom(_str('x', [...ascii.encode('I_V3.1.20C_Rel'), 0, 0, 0])), 'I_V3.1.20C_Rel');
      expect(HsgqOlt.rxFrom(_int('x', -1823)), -18.23);
      expect(HsgqOlt.rxFrom(_int('x', 0)), isNull, reason: 'صفرٌ ليس ضوءاً');
      expect(HsgqOlt.rxFrom(_int('x', -9999)), isNull);
      final r = HsgqOlt.readingFrom(_int('a', -2366), _int('b', 753), _int('c', 329), _int('d', 3094))!;
      expect(r.rxDbm, -23.66);
      expect(r.txDbm, 7.53);
      expect(r.voltV, 3.29);
      expect(r.tempC, 30.94);
      expect(HsgqOlt.readingFrom(_int('a', 0), null, null, null), isNull);
    });

    test('الاسم: الافتراضيّ والحشو يُهملان، والمكتوب (عربيّاً) يبقى', () {
      expect(HsgqOlt.nameFrom(_str('x', ascii.encode('ONU02/06'))), isNull);
      expect(HsgqOlt.nameFrom(_str('x', ascii.encode('NULL'))), isNull);
      expect(HsgqOlt.nameFrom(_str('x', utf8.encode('برج ٢ - أحمد'))), 'برج ٢ - أحمد');
      expect(HsgqOlt.nameFrom(_str('x', [0, 0])), isNull);
    });
  });

  group('القراءة — GET وحده بفهارس محسوبة', () {
    test('لقطةٌ كاملة: المنافذ، كلّ الـONU (وما فوق ٦٤)، الماك للمفصولة، والاسم المكتوب وحده', () async {
      final f = _fixture();
      final partials = <VsolOltStats>[];
      final s = await HsgqOlt.fetchStats(f.get,
          profile: _hsgqProfile, sysDescr: 'EPON OLT', sysName: 'OLT', withCounters: true, onPartialReady: partials.add);

      expect(partials.first.ponPorts, hasLength(4));
      expect(partials.first.onus, isEmpty, reason: 'المنافذ تُعرض قبل الـONU');
      expect(partials.last.onus, hasLength(6));
      expect(partials.last.onus.every((o) => o.mac == null), isTrue, reason: 'الماك في المرحلة الأخيرة');

      expect(s.sysDescr, 'EPON OLT · I_V3.1.20C_Rel');
      expect(s.profile.vendor, OltVendor.hsgq);
      expect([for (final o in s.onus) '${o.ponPort}/${o.onuId}'], ['1/1', '1/2', '1/4', '2/1', '4/60', '4/70']);
      expect(s.onusOnline, 4);
      expect(s.onus.every((o) => o.mac != null), isTrue, reason: 'الماك هويّة الـONU المسجّلة — للمفصولة أيضاً');
      expect(s.onus.map((o) => o.mac).toSet(), hasLength(6));
      expect({for (final o in s.onus) if (o.name != null) o.label: o.name}, {'EPON0/1:4': 'برج ٢ - أحمد'});
      expect([for (final p in s.ponPorts) '${p.label} ${p.onuOnline}/${p.onuTotal}'],
          ['EPON0/1 2/3', 'EPON0/2 0/1', 'EPON0/3 0/0', 'EPON0/4 2/2']);
      expect([for (final u in s.uplinks) '${u.name}${u.up ? '↑' : '↓'}'],
          ['GE1↑', 'GE2↓', 'GE3↓', 'GE4↓', 'XGE1↓', 'XGE2↓', 'XGE3↓', 'XGE4↓']);
      expect(s.narrowCounters, isTrue);
      expect(s.hasCounters, isTrue);
      expect(s.ponPorts.first.rxBytes, 2498855);
      expect(s.ifNames, hasLength(18), reason: '١٢ منفذاً + ٦ ONU ⇒ refreshStatus يكشف الجديدة');
      expect(s.onus.every((o) => o.rxBytes == 0 && o.txBytes == 0), isTrue);

      // لا عدّادات ٦٤ بت، ولا صفّ ONU من IF-MIB، ولا مسح ما فوق الـ٦٤ لمنفذٍ لم يبلغه.
      expect(f.asked.where((o) => o.startsWith('1.3.6.1.2.1.31.1.1.1.6.') || o.startsWith('1.3.6.1.2.1.31.1.1.1.10.')), isEmpty);
      expect(f.asked, isNot(contains('$_ifDescr.13')));
      expect(f.asked, contains(HsgqOlt.statusOid(_i(4, 65))));
      expect(f.asked, isNot(contains(HsgqOlt.statusOid(_i(1, 65)))));
    });

    test('جداولٌ غائبة أو حالةٌ لم تُجب كاملة ⇒ استثناءٌ (تبقى آخر قراءةٍ صحيحة)، لا لقطةٌ ناقصة', () async {
      final noTables = _fixture()..table.remove(HsgqOlt.ponCountOid);
      await expectLater(HsgqOlt.fetchStats(noTables.get, profile: _hsgqProfile), throwsA(isA<VsolException>()));
      final lossy = _fixture()..fail = (oids) => oids.contains(HsgqOlt.statusOid(_i(2, 20)));
      await expectLater(HsgqOlt.fetchStats(lossy.get, profile: _hsgqProfile), throwsA(isA<VsolException>()));
    });

    test('الحالة وحدها: يتبدّل المتّصل، وONU جديدة تُعدّ ‹unknown› فتُعاد البنية، والناقص null', () async {
      final f = _fixture();
      final s = await HsgqOlt.fetchStats(f.get, profile: _hsgqProfile, withCounters: true);
      f.put(_int(HsgqOlt.statusOid(_i(1, 2)), 1));
      f.put(_int(HsgqOlt.statusOid(_i(3, 5)), 2));
      f.put(_int('$_ifOper.2', 2));
      final r = await HsgqOlt.refreshStatus(f.get, s);
      expect(r, isNotNull);
      expect(r!.unknown, 1);
      expect(r.stats.onus.firstWhere((o) => o.label == 'EPON0/1:2').online, isTrue);
      expect(r.stats.ponPorts.firstWhere((p) => p.port == 2).up, isFalse);
      expect(r.stats.ponPorts.firstWhere((p) => p.port == 1).onuOnline, 3);

      f.fail = (oids) => oids.any((o) => o.startsWith('1.3.6.1.4.1.50224.3.3.2.1.8.'));
      expect(await HsgqOlt.refreshStatus(f.get, s), isNull);
    });

    test('الضوء للمتّصلة وحدها، والصانع/الطراز، والاستقبال وحده، والحالة لأجهزةٍ بعينها، والمعالج', () async {
      final f = _fixture();
      final online = [_i(1, 1), _i(1, 4), _i(4, 60), _i(4, 70)];
      final r = await HsgqOlt.readings(f.get, online);
      expect(r.keys, unorderedEquals([_i(1, 1), _i(1, 4), _i(4, 60)]), reason: 'rx صفرٌ وحده ⇒ لا قراءة');
      expect(r[_i(1, 1)]!.rxDbm, -18.23);
      expect(r[_i(1, 1)]!.tempC, 45.0);
      expect(r[_i(4, 60)]!.txDbm, 7.62);
      expect(await HsgqOlt.readings(f.get, [_i(1, 2), _i(2, 1)]), isEmpty, reason: 'المفصولة بلا صفّ ضوء');

      final ids = await HsgqOlt.identities(f.get, [_i(1, 1), _i(1, 2), _i(1, 4), _i(2, 1)]);
      expect(ids[_i(1, 1)]!.vendor, 'HWTC');
      expect(ids[_i(1, 1)]!.module, '145C631');
      expect(ids[_i(1, 2)]!.module, '545M631', reason: 'آخر طرازٍ معروفٍ للمفصولة');
      expect(ids.containsKey(_i(2, 1)), isFalse, reason: 'لم تُسجَّل قطّ');

      final rx = await HsgqOlt.rxOnly(f.get, online);
      expect(rx, {_i(1, 1): -18.23, _i(1, 4): -27.95, _i(4, 60): -7.64});

      expect(await HsgqOlt.statusOf(f.get, [_i(1, 1), _i(1, 2), _i(3, 9)]), {_i(1, 1): true, _i(1, 2): false});
      expect((await HsgqOlt.chassis(f.get)).cpuPct, 11);
      expect(f.asked.where((o) => o.startsWith('1.3.6.1.2.1.31.1.1.1.6.') || o.startsWith('1.3.6.1.2.1.31.1.1.1.10.')), isEmpty);
    });
  });

  group('الترفك', () {
    VsolOltStats snap(OltProfile p, int ponRx, {int onuRx = 0, DateTime? at}) => VsolOltStats(
          profile: p,
          narrowCounters: true,
          rxAt: at,
          txAt: at,
          ponPorts: [VsolPonPort(index: 1, slot: 0, port: 1, up: true, rxBytes: ponRx, txBytes: 10)],
          uplinks: const [VsolUplink(index: 5, name: 'GE1', up: true, speedMbps: 1000, rxBytes: 7, txBytes: 7)],
          onus: [VsolOnu(ifIndex: _i(1, 1), slot: 0, ponPort: 1, onuId: 1, online: true, rxBytes: onuRx, txBytes: onuRx)],
        );

    test('لا معدّل لـONU بلا عدّادات (HSGQ) — لا «0 bps» كاذب؛ وVSOL كما كان', () {
      final t0 = DateTime(2026, 10, 28, 10);
      final t1 = t0.add(const Duration(seconds: 31));
      final h = VsolTraffic.between(snap(_hsgqProfile, 1000, at: t0), snap(_hsgqProfile, 2000000, at: t1), const Duration(seconds: 31));
      expect(h.keys, containsAll(['EPON0/1', 'GE1']));
      expect(h.containsKey('EPON0/1:1'), isFalse);
      const vsol = OltProfile.vsolDefault;
      final v = VsolTraffic.between(snap(vsol, 1000, onuRx: 5, at: t0), snap(vsol, 2000, onuRx: 9, at: t1), const Duration(seconds: 31));
      expect(v.containsKey('EPON0/1:1'), isTrue);
    });

    test('عدّاداتٌ لم يُحدّثها الجهاز = مؤجَّل لا صفر؛ وبعد تحديثين فائتين يُقبل الصفر؛ وVSOL لا يُؤجَّل أبداً', () {
      final a = snap(_hsgqProfile, 1000);
      final moved = snap(_hsgqProfile, 5000);
      expect(VsolTraffic.portsMoved(a, a), isFalse);
      expect(VsolTraffic.portsMoved(a, moved), isTrue);
      expect(VsolTraffic.frozenBetween(_hsgqProfile, a, a, const Duration(seconds: 9)), isTrue);
      expect(VsolTraffic.frozenBetween(_hsgqProfile, a, moved, const Duration(seconds: 9)), isFalse);
      expect(VsolTraffic.frozenBetween(_hsgqProfile, a, a, const Duration(seconds: 70)), isFalse, reason: 'منافذ ساكنةٌ حقّاً');
      expect(VsolTraffic.frozenBetween(OltProfile.vsolDefault, a, a, const Duration(seconds: 3)), isFalse);
    });
  });

  group('الصورة — رمزٌ تامّ وسجلٌّ مصنّعه HSGQ', () {
    const file = 'hsgq/HSGQ-XE04R.webp';
    test('XE04R بعلامة HSGQ أو باسم HSGQ في الطراز — وغيره لا', () {
      expect(DeviceImage.assetFor('HSGQ-XE04R', brand: 'other'), file);
      expect(DeviceImage.assetFor('HSGQ XE04R', brand: 'vsol'), file);
      expect(DeviceImage.assetFor('XE04R', brand: 'hsgq'), file);
      expect(DeviceImage.assetFor('XE04R', brand: 'vsol'), isNull, reason: 'بلا هويّة HSGQ في السجلّ');
      expect(DeviceImage.assetFor('HSGQ XE04RD', brand: 'hsgq'), isNull, reason: 'مطابقةٌ تامّة');
      expect(DeviceImage.assetFor('HSGQ OLT', brand: 'other'), isNull, reason: 'الطراز غير معروف — شارة العلامة');
      expect(DeviceImage.assetFor('HSGQ-XE04R', brand: 'mikrotik'), isNull);
      expect(DeviceImage.hsgqTokens('HSGQXE04R olt'), ['XE04R']);
    });

    test('المنتقي ذهاباً وإياباً، والملفّ WebP حقيقيّ بأبعاده الموثّقة', () {
      expect(DeviceImage.allAssets, contains(file));
      expect(DeviceImage.boardNameOf(file), 'HSGQ-XE04R');
      expect(DeviceImage.assetFor(DeviceImage.boardNameOf(file), brand: 'vsol'), file);
      final b = File('assets/devices-images/$file').readAsBytesSync();
      expect(ascii.decode(b.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(b.sublist(8, 12)), 'WEBP');
      expect(ascii.decode(b.sublist(12, 16)), 'VP8 ');
      // ترويسة VP8: العرض والارتفاع (‏14 بت) بعد رمز البداية — 687×111 كما في الكتالوج.
      final w = (b[26] | (b[27] << 8)) & 0x3fff;
      final h = (b[28] | (b[29] << 8)) & 0x3fff;
      expect('${w}x$h', '687x111');
    });
  });

  group('اللوحة', () {
    late List<Interceptor> oldInterceptors;
    setUpAll(loadAppFonts);
    setUp(() {
      oldInterceptors = List<Interceptor>.of(ApiClient.dio.interceptors);
      ApiClient.dio.interceptors
        ..clear()
        ..add(InterceptorsWrapper(onRequest: (o, h) => h.reject(DioException(requestOptions: o, error: 'offline fixture'))));
    });
    tearDown(() {
      ApiClient.dio.interceptors
        ..clear()
        ..addAll(oldInterceptors);
    });

    VsolOltStats seed() {
      final at = DateTime.now();
      return HsgqOlt.buildStats(
        profile: _hsgqProfile,
        sysDescr: 'EPON OLT · I_V3.1.20C_Rel',
        sysName: 'OLT',
        ports: [
          for (var k = 1; k <= 4; k++) VsolIfRow(index: k, name: 'PON0$k', up: true, mac: null, speedMbps: 1000, rxBytes: 0, txBytes: 0),
          const VsolIfRow(index: 5, name: 'GE01', up: true, mac: null, speedMbps: 1000, rxBytes: 0, txBytes: 0),
          const VsolIfRow(index: 9, name: 'XGE01', up: false, mac: null, speedMbps: 10000, rxBytes: 0, txBytes: 0),
        ],
        status: {_i(1, 1): true, _i(1, 2): false},
        macs: {_i(1, 1): '02:00:00:01:01:00', _i(1, 2): '02:00:00:01:02:00'},
      ).withEponDetails(OltEponDetails(
        readings: {_i(1, 1): const BdcomOnuReading(rxDbm: -18.23, txDbm: 2.2, tempC: 45, voltV: 3.29)},
        readingsAt: at,
        identities: {_i(1, 1): const BdcomOnuReading(vendor: 'HWTC', module: '145C631')},
        macsAt: at,
        chassis: const BdcomChassis(cpuPct: 11),
        chassisAt: at,
      ));
    }

    NetworkDevice device(int id) => NetworkDevice(
          id: id,
          adminId: 'fixture',
          name: 'OLT',
          type: 'other',
          brand: 'vsol',
          ip: '127.0.0.1',
          port: 161,
          apiPort: 161,
          protocol: 'snmp',
          lastStatus: 'online',
          createdAt: DateTime.utc(2026),
        );

    testWidgets('هاتف ٣٢٠: الماك للمتّصلة والمفصولة، والضوء والمعالج، ولا سطر ترفكٍ للـONU', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      const id = 99005022;
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
      expect(find.text('02:00:00:01:01:00'), findsOneWidget);
      expect(find.text('02:00:00:01:02:00'), findsOneWidget, reason: 'ماك المفصولة هويّتها المسجّلة');
      expect(find.textContaining('RX -18.2 dBm'), findsOneWidget);
      expect(find.text('CPU 11%'), findsOneWidget);
      expect(find.byKey(const ValueKey('EPON0/1:1')), findsOneWidget, reason: 'صفّ الـONU معروض — فغياب السطر حقيقيّ');
      expect(find.descendant(of: find.byKey(const ValueKey('EPON0/1:1')), matching: find.text('▼ تنزيل')), findsNothing);
      expect(find.text('▼ تنزيل'), findsWidgets, reason: 'منافذ PON تبقى بترفكها');
      expect(find.textContaining('أجهزة خلف الـONU'), findsNothing, reason: 'لا جدول جسر على HSGQ — لا قسمٌ يومض');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('الحاسبة: عمودا الترفك في جدول المنافذ وحده لا في جدول المشتركين', (tester) async {
      tester.view.physicalSize = const Size(1260, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const id = 99005023;
      DeviceStatsCache.instance.putRaw(id, seed());
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: AppType.family),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: DesktopScope(child: Scaffold(body: SingleChildScrollView(child: VsolLivePanel(device: device(id))))),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('ماك الـONU / الرقم'), findsOneWidget, reason: 'جدول المشتركين معروض');
      expect(find.text('تنزيل ↓'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
