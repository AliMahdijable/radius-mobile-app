import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/bdcom_epon.dart';
import 'package:rad_mysvcs/api/device_reach.dart';
import 'package:rad_mysvcs/api/nscrtv_olt.dart';
import 'package:rad_mysvcs/api/olt_get_tables.dart';
import 'package:rad_mysvcs/api/olt_profile.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_check_text.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/vsol_live_panel.dart';
import 'package:rad_mysvcs/services/device_stats_cache.dart';
import 'package:rad_mysvcs/theme/typography.dart';

import 'support/app_fonts.dart';

/// أولت EPON بجداول NSCRTV (٢٠ نوفمبر) — على حقائق أولت الوكيل المقيسة حيّاً عبر VPN (GET وحده): «EasyPath Ethernet-PON»،
/// ‏sysObjectID ‏`…17409`، منافذ IF-MIB عشرة («ge0/0/1..4» · «xge0/0/1..2» · «pon0/0/1..4» بالفهارس 7..10)، ‏١٠٧ ONU (٦٨ متّصلة:
/// ٦/٧ · ٢٢/٣٤ · ١١/٢٠ · ٢٩/٤٦)، والضوء بوحدة ٠٫٠١ (‏‎-2155 أوّل صفٍّ أجاب به). الأولت الوهميّ **لا يعرف إلّا GET**، ويسكت حتى
/// المهلة لموضعٍ على بايت منفذٍ غير موجود كما سكت الجهاز (‏0x11…). الماكات اصطناعيّة (‏02:…)، والأسماء فارغة كما هي عنده.

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
Varbind _noObject(String oid) => Varbind(oid: oid, rawTag: 0x80, rawBytes: Uint8List(0));

List<int> _mac(String m) => [for (final h in m.split(':')) int.parse(h, radix: 16)];

const _ifDescr = '1.3.6.1.2.1.2.2.1.2';
const _ifOper = '1.3.6.1.2.1.2.2.1.8';
const _ifHighSpeed = '1.3.6.1.2.1.31.1.1.1.15';
const _ifHCIn = '1.3.6.1.2.1.31.1.1.1.6';
const _ifHCOut = '1.3.6.1.2.1.31.1.1.1.10';
const _onuCol = '1.3.6.1.4.1.17409.2.3.4.1.1';
const _optCol = '1.3.6.1.4.1.17409.2.3.4.2.1';

/// فهارس منافذ PON في IF-MIB على أولت الوكيل.
const _ponIf = [7, 8, 9, 10];

int _i(int ponIf, int onu) => NscrtvOlt.onuIndex(ponIf, onu);

class _FakeNscrtv {
  final Map<String, Varbind> table = {};
  final List<String> asked = [];

  /// ما سُئل خارج الأسر المعروفة (المنافذ، جدول الـONU بأعمدته الخمسة، الضوء بأعمدته الأربعة) — يجب أن يبقى فارغاً.
  final List<String> foreign = [];
  bool Function(List<String> oids)? fail;

  /// جدول الـONU غائبٌ أصلاً (noSuchObject) — أولتٌ لا يكشفه.
  bool noOnuTable = false;

  static final _onuRe = RegExp(r'^1\.3\.6\.1\.4\.1\.17409\.2\.3\.4\.1\.1\.(2|7|8|25|26)\.(\d+)$');
  static final _optRe = RegExp(r'^1\.3\.6\.1\.4\.1\.17409\.2\.3\.4\.2\.1\.(4|5|7|8)\.(\d+)\.0\.0$');
  static final _ifRe = RegExp(r'^1\.3\.6\.1\.2\.1\.(2\.1\.0|2\.2\.1\.(2|8)\.\d+|31\.1\.1\.1\.(6|10|15)\.\d+)$');

  Future<List<Varbind>> get(List<String> oids) async {
    if (fail?.call(oids) ?? false) throw SnmpTimeoutException('timeout');
    for (final o in oids) {
      final m = _onuRe.firstMatch(o) ?? _optRe.firstMatch(o);
      if (m != null) {
        // كالجهاز: موضعٌ على بايت منفذٍ ليس من منافذه ⇒ لا ردّ للطلب كلّه حتى المهلة.
        final pon = (int.parse(m.group(2)!) >> 8) & 0xff;
        if (!_ponIf.contains(pon)) throw SnmpTimeoutException('timeout');
      } else if (!_ifRe.hasMatch(o)) {
        foreign.add(o);
      }
    }
    asked.addAll(oids);
    return [
      for (final o in oids)
        table[o] ?? (noOnuTable && _onuRe.hasMatch(o) ? _noObject(o) : _absent(o)),
    ];
  }

  void put(Varbind vb) => table[vb.oid] = vb;
}

const _models = ['120C', '342R', '321R', '020C', '145C', '540M', '340M', '456C', '45C5', '46AR'];

/// أولت الوكيل كما قِيس: المنافذ العشرة، و١٠٧ ONU بأعدادها، والمتّصلة بضوئها في مداه المقيس، والمفصولة بماكها وحده.
_FakeNscrtv _fixture() {
  final f = _FakeNscrtv();
  f.put(_int(NscrtvOlt.ifNumberOid, 10));
  const names = ['ge0/0/1', 'ge0/0/2', 'ge0/0/3', 'ge0/0/4', 'xge0/0/1', 'xge0/0/2', 'pon0/0/1', 'pon0/0/2', 'pon0/0/3', 'pon0/0/4'];
  for (var k = 1; k <= 10; k++) {
    f.put(_str('$_ifDescr.$k', ascii.encode(names[k - 1])));
    f.put(_int('$_ifOper.$k', (k == 5 || k == 6) ? 2 : 1));
    f.put(_int('$_ifHighSpeed.$k', (k == 5 || k == 6) ? 10000 : 1000));
    f.put(_c64('$_ifHCIn.$k', k == 1 ? 36769927639983 : (k == 7 ? 1618781017775 : 1000 * k)));
    f.put(_c64('$_ifHCOut.$k', k == 1 ? 3759499574767 : (k == 7 ? 17920868057497 : 2000 * k)));
  }
  // (منفذ IF-MIB، مسجّلة، متّصلة) — والأولى على PON1 مفصولة كما أجاب الجهاز (‏16779009 = 2).
  const pons = [(7, 7, 6), (8, 34, 22), (9, 20, 11), (10, 46, 29)];
  for (final (ponIf, total, up) in pons) {
    for (var n = 1; n <= total; n++) {
      final i = _i(ponIf, n);
      final online = ponIf == 7 ? n != 1 : n <= up;
      f.put(_int(NscrtvOlt.statusOid(i), online ? 1 : 2));
      f.put(_str(NscrtvOlt.macOid(i), _mac('02:00:00:${ponIf.toRadixString(16).padLeft(2, '0')}:${n.toRadixString(16).padLeft(2, '0')}:00')));
      f.put(_str(NscrtvOlt.nameOid(i), const []));
      f.put(_str(NscrtvOlt.vendorOid(i), online ? ascii.encode('HWTC') : const []));
      f.put(_str(NscrtvOlt.modelOid(i), online ? ascii.encode(_models[n % _models.length]) : const []));
      if (online) {
        final rx = ponIf == 7 && n == 2 ? -2155 : -1524 - ((n * 37 + ponIf * 11) % 1300);
        f.put(_int(NscrtvOlt.opticsOid(4, i), rx));
        f.put(_int(NscrtvOlt.opticsOid(5, i), 181 + (n % 57)));
        f.put(_int(NscrtvOlt.opticsOid(7, i), 321000 + (n * 100) % 16000));
        f.put(_int(NscrtvOlt.opticsOid(8, i), 3000 + (n * 30) % 2400));
      }
    }
  }
  return f;
}

final _profile = OltProfile.resolve(OltProfile.fromRecord(brand: 'cdata'),
    sysObjectId: '1.3.6.1.4.1.17409', sysDescr: 'EasyPath Ethernet-PON');

void main() {
  group('الهويّة — المؤسّسة 17409 نفسها', () {
    test('سجلّ «cdata» + sysObjectID = ‏17409 بلا ذيل ⇒ NSCRTV حيّاً، يفتح لوحة الأولت', () {
      expect(_profile.vendor, OltVendor.nscrtv);
      expect(_profile.identified, isTrue);
      expect(_profile.opensOltPanel, isTrue);
      expect(_profile.label, 'EPON OLT');
      expect(OltProfile.isNscrtvObjectId('1.3.6.1.4.1.17409'), isTrue);
      expect(OltProfile.isNscrtvObjectId('1.3.6.1.4.1.17409.2.3'), isTrue);
      expect(OltProfile.isNscrtvObjectId('1.3.6.1.4.1.174090'), isFalse, reason: 'مؤسّسةٌ أخرى تبدأ بالأرقام نفسها');
      expect(OltProfile.isNscrtvObjectId(null), isFalse);
    });

    test('الطراز: طراز سجلّ C-Data يبقى، وطراز VSOL كُتب خطأً لا يُعرض؛ وC-Data القديم (34592) كما كان', () {
      final fd = OltProfile.resolve(OltProfile.fromRecord(brand: 'cdata', model: 'FD1204SN'),
          sysObjectId: '1.3.6.1.4.1.17409', sysDescr: 'EasyPath Ethernet-PON');
      expect(fd.vendor, OltVendor.nscrtv);
      expect(fd.model, 'FD1204SN');
      final wrong = OltProfile.resolve(OltProfile.fromRecord(brand: 'vsol', model: 'V1600D'), sysObjectId: '1.3.6.1.4.1.17409');
      expect(wrong.vendor, OltVendor.nscrtv);
      expect(wrong.model, isNull);
      final old = OltProfile.resolve(OltProfile.fromRecord(brand: 'cdata'), sysObjectId: '1.3.6.1.4.1.34592', sysDescr: ' GEPON OLT');
      expect(old.vendor, OltVendor.cdata, reason: 'أولت المالك القديم لا يتغيّر');
    });

    test('قدرات الملفّ: GET وحده، لا ماك واجهة، لا ترفك لكلّ ONU، لا جدول جسر، والعدّادات لحظيّة', () {
      expect(_profile.readsGetTables, isTrue);
      expect(_profile.readsNscrtvTables, isTrue);
      expect(_profile.readsCdataTables, isFalse);
      expect(_profile.readsHsgqTables, isFalse);
      expect(_profile.readsInterfaceMac, isFalse);
      expect(_profile.hasOnuCounters, isFalse);
      expect(_profile.readsBridgeFdb, isFalse);
      expect(_profile.countersRefresh, isNull, reason: '٢٤ قراءةً بفاصل ~٠٫٦ث تغيّرت كلّها');
      expect(OltGetTables.of(_profile), isNotNull);
    });
  });

  group('التحويل', () {
    test('الفهرس: بايت المنفذ = فهرس منفذ الـPON في IF-MIB — أوّل صفّين أجاب بهما الجهاز', () {
      expect(_i(7, 1), 16779009, reason: 'أوّل صفٍّ في عمود الحالة');
      expect(_i(7, 2), 16779010, reason: 'أوّل صفٍّ في جدول الضوء');
      expect(NscrtvOlt.ponIfIndexOf(_i(10, 46)), 10);
      expect(NscrtvOlt.onuOf(_i(10, 46)), 46);
      expect(NscrtvOlt.statusOid(_i(7, 1)), '$_onuCol.8.16779009');
      expect(NscrtvOlt.opticsOid(4, _i(7, 2)), '$_optCol.4.16779010.0.0');
    });

    test('الحالة 1 متّصل و2 مفصول، والغائب لا ONU', () {
      expect(NscrtvOlt.onlineFrom(_int('x', 1)), isTrue);
      expect(NscrtvOlt.onlineFrom(_int('x', 2)), isFalse);
      expect(NscrtvOlt.onlineFrom(_int('x', 3)), isFalse);
      expect(NscrtvOlt.onlineFrom(_absent('x')), isNull);
      expect(NscrtvOlt.onlineFrom(_str('x', ascii.encode('1'))), isNull);
    });

    test('الضوء والحرارة بوحدة ٠٫٠١، والجهد ٠٫٠١ ملّي فولت — القيم في مداها المقيس', () {
      expect(NscrtvOlt.rxFrom(_int('x', -2155)), -21.55);
      expect(NscrtvOlt.rxFrom(_int('x', 0)), isNull, reason: 'الصفر ليس ضوءاً');
      expect(NscrtvOlt.rxFrom(_int('x', -9000)), isNull, reason: '‎-90 dBm لا يُعقل');
      final r = NscrtvOlt.readingFrom(_int('a', -2824), _int('b', 181), _int('c', 321000), _int('d', 3000))!;
      expect(r.rxDbm, -28.24);
      expect(r.txDbm, 1.81);
      expect(r.voltV, 3.21);
      expect(r.tempC, 30.0);
      final hi = NscrtvOlt.readingFrom(_int('a', -1524), _int('b', 237), _int('c', 337000), _int('d', 5400))!;
      expect([hi.rxDbm, hi.txDbm, hi.voltV, hi.tempC], [-15.24, 2.37, 3.37, 54.0]);
      expect(NscrtvOlt.readingFrom(_absent('a'), _absent('b'), _absent('c'), _absent('d')), isNull);
    });

    test('الاسم: الفارغ والافتراضيّ يُهملان، والمكتوب يبقى', () {
      expect(NscrtvOlt.nameFrom(_str('x', const [])), isNull, reason: 'كلّ أسماء أولت الوكيل فارغة');
      expect(NscrtvOlt.nameFrom(_str('x', ascii.encode('ONU01/07'))), isNull);
      expect(NscrtvOlt.nameFrom(_str('x', ascii.encode('pon0/0/1:7'))), isNull);
      expect(NscrtvOlt.nameFrom(_str('x', ascii.encode('unknown'))), isNull);
      expect(NscrtvOlt.nameFrom(_str('x', utf8.encode('برج ٣ - علي'))), 'برج ٣ - علي');
    });
  });

  group('القراءة — GET وحده، على منافذ الجدول وحدها', () {
    test('لقطةٌ كاملة كما قِيست: أربعة PON بأعدادها، الصعود، ١٠٧ ONU بماكها، وعدّادات ٦٤ بت', () async {
      final f = _fixture();
      final partials = <VsolOltStats>[];
      final s = await NscrtvOlt.fetchStats(f.get,
          profile: _profile, sysDescr: 'EasyPath Ethernet-PON', sysName: 'olt', withCounters: true, onPartialReady: partials.add);

      expect(partials.first.ponPorts, hasLength(4));
      expect(partials.first.onus, isEmpty, reason: 'المنافذ تُعرض قبل الـONU');
      expect(partials.last.onus, hasLength(107));

      expect(s.sysDescr, 'EasyPath Ethernet-PON');
      expect(s.profile.vendor, OltVendor.nscrtv);
      expect([for (final p in s.ponPorts) '${p.label} ${p.onuOnline}/${p.onuTotal}'],
          ['EPON0/1 6/7', 'EPON0/2 22/34', 'EPON0/3 11/20', 'EPON0/4 29/46']);
      expect(s.onus, hasLength(107));
      expect(s.onusOnline, 68);
      expect(s.onus.first.label, 'EPON0/1:1');
      expect(s.onus.first.online, isFalse, reason: 'كما أجاب الجهاز: ‏16779009 = 2');
      expect(s.onus.every((o) => o.mac != null), isTrue, reason: 'الماك هويّة الـONU المسجّلة — للمفصولة أيضاً');
      expect(s.onus.every((o) => o.name == null), isTrue, reason: 'الأسماء فارغة على الجهاز');
      expect([for (final u in s.uplinks) '${u.name}${u.up ? '↑' : '↓'}'], ['GE1↑', 'GE2↑', 'GE3↑', 'GE4↑', 'XGE1↓', 'XGE2↓']);
      expect(s.narrowCounters, isFalse, reason: 'عدّادات ٦٤ بت تعمل هنا');
      expect(s.uplinks.first.rxBytes, 36769927639983);
      expect(s.ponPorts.first.txBytes, 17920868057497);

      expect(f.foreign, isEmpty, reason: 'لا شيء خارج المنافذ وجدول الـONU والضوء — ولا عمود الكلمات');
      final ponBytes = {
        for (final o in f.asked)
          if (o.startsWith('$_onuCol.') || o.startsWith('$_optCol.')) (int.parse(o.split('.')[13]) >> 8) & 0xff,
      };
      expect(ponBytes, {7, 8, 9, 10}, reason: 'مواضع منافذ الجدول وحدها');
      expect(f.asked, isNot(contains(NscrtvOlt.statusOid(_i(8, 65)))), reason: 'لا ما فوق الـ٦٤ لمنفذٍ لم يبلغه');
    });

    test('منفذٌ بلغ آخر الـ٦٤ ⇒ يُسأل حتى ١٢٨ وحده', () async {
      final f = _fixture();
      f.put(_int(NscrtvOlt.statusOid(_i(10, 60)), 1));
      f.put(_int(NscrtvOlt.statusOid(_i(10, 70)), 2));
      final s = await NscrtvOlt.fetchStats(f.get, profile: _profile);
      expect(s.onus.map((o) => o.label), containsAll(['EPON0/4:60', 'EPON0/4:70']));
      expect(f.asked, contains(NscrtvOlt.statusOid(_i(10, 128))));
      expect(f.asked, isNot(contains(NscrtvOlt.statusOid(_i(7, 65)))));
    });

    test('جدولٌ غائب، أو حالةٌ لم تُجب كاملة، أو لا منافذ PON ⇒ استثناءٌ (تبقى آخر قراءةٍ صحيحة)، لا «٠ مشترك»', () async {
      final noIf = _fixture()..table.remove(NscrtvOlt.ifNumberOid);
      await expectLater(NscrtvOlt.fetchStats(noIf.get, profile: _profile), throwsA(isA<VsolException>()));

      final lossy = _fixture()..fail = (oids) => oids.contains(NscrtvOlt.statusOid(_i(9, 20)));
      await expectLater(NscrtvOlt.fetchStats(lossy.get, profile: _profile), throwsA(isA<VsolException>()));

      final noPon = _fixture();
      for (var k = 7; k <= 10; k++) {
        noPon.put(_str('$_ifDescr.$k', ascii.encode('vlan$k')));
      }
      await expectLater(
          NscrtvOlt.fetchStats(noPon.get, profile: _profile),
          throwsA(isA<VsolException>().having((e) => e.message, 'message', startsWith('قراءةٌ ناقصة'))));

      final noTable = _fixture()
        ..table.removeWhere((k, _) => k.startsWith('$_onuCol.'))
        ..noOnuTable = true;
      await expectLater(
          NscrtvOlt.fetchStats(noTable.get, profile: _profile),
          throwsA(isA<VsolException>().having((e) => e.message, 'message', contains('لا يكشف قائمة الـONU'))));

      final empty = _fixture()..table.removeWhere((k, _) => k.startsWith('$_onuCol.') || k.startsWith('$_optCol.'));
      final s = await NscrtvOlt.fetchStats(empty.get, profile: _profile);
      expect(s.onus, isEmpty, reason: 'أولتٌ فارغ حقّاً (noSuchInstance) ⇒ صفرٌ صادق');
    });

    test('الحالة وحدها: يتبدّل المتّصل، وONU جديدة تُعدّ مجهولة، ومنفذٌ يطفأ، والناقص null', () async {
      final f = _fixture();
      final s = await NscrtvOlt.fetchStats(f.get, profile: _profile, withCounters: true);
      f.put(_int(NscrtvOlt.statusOid(_i(7, 1)), 1));
      f.put(_int(NscrtvOlt.statusOid(_i(9, 21)), 2));
      f.put(_int('$_ifOper.8', 2));
      final r = await OltGetTables.of(_profile)!.refreshStatus(f.get, s);
      expect(r, isNotNull);
      expect(r!.unknown, 1);
      expect(r.stats.onus.firstWhere((o) => o.label == 'EPON0/1:1').online, isTrue);
      expect(r.stats.ponPorts.firstWhere((p) => p.port == 2).up, isFalse);

      f.fail = (oids) => oids.any((o) => o.startsWith('$_onuCol.8.'));
      expect(await NscrtvOlt.refreshStatus(f.get, s), isNull);
    });

    test('عبر القارئ الموحّد: الضوء للمتّصلة، الصانع/الطراز، الاستقبال وحده، الحالة لأجهزةٍ بعينها، ولا معالج', () async {
      final f = _fixture();
      final t = OltGetTables.of(_profile)!;
      final online = [_i(7, 2), _i(8, 1), _i(10, 29)];
      final r = await t.readings(f.get, online);
      expect(r.keys, unorderedEquals(online));
      expect(r[_i(7, 2)]!.rxDbm, -21.55);
      expect(r[_i(7, 2)]!.voltV, closeTo(3.212, 0.0001));
      expect(r[_i(7, 2)]!.tempC, 30.6);

      final ids = await t.identities(f.get, [_i(7, 1), _i(7, 2)]);
      expect(ids[_i(7, 2)]!.vendor, 'HWTC');
      expect(ids[_i(7, 2)]!.module, _models[2]);
      expect(ids.containsKey(_i(7, 1)), isFalse, reason: 'المفصولة فارغة الصانع والطراز');

      expect((await t.rxOnly(f.get, [_i(7, 2)]))![_i(7, 2)], -21.55);
      expect(await t.statusOf(f.get, [_i(7, 1), _i(7, 2), _i(9, 30)]), {_i(7, 1): false, _i(7, 2): true});
      expect((await t.chassis(f.get)).isEmpty, isTrue, reason: 'لا معالج في جداول NSCRTV — «—» لا تخمين');
      expect(await t.names(f.get, [_i(7, 1), _i(7, 2)]), isEmpty);
      expect(f.foreign, isEmpty);
    });
  });

  group('رسالة الفحص — «قراءةٌ ناقصة» ليست إعداداً خاطئاً', () {
    final d = NetworkDevice(
      id: 10969,
      adminId: 'fixture',
      name: 'c-data-olt',
      type: 'switch',
      brand: 'cdata',
      ip: '192.168.1.100',
      port: 80,
      apiPort: 161,
      protocol: 'snmp',
      lastStatus: 'online',
      createdAt: DateTime.utc(2026, 11, 20),
    );
    const c = DeviceCheck(reachable: true, latencyMs: 5, packetLoss: 0, via: ReachVia.ping, icmpTried: true);

    test('أجاب SNMP وبياناته لم تُقرأ ⇒ «الإعدادات سليمة»، لا «تأكّد من الـcommunity» (لقطة المالك ٢٠ نوفمبر)', () {
      final n = DeviceCheckText.note(d, c, readError: 'قراءةٌ ناقصة: لم تظهر منافذ PON في جدول الواجهات')!;
      expect(n.line, 'الجهاز يردّ على الاتصال (ping) — إعدادات الاتصال سليمة — بياناته لم تُقرأ كاملة');
      expect(n.line, isNot(contains('community')));
      final hsgq = DeviceCheckText.note(d, c,
          readError: 'هذا الأولت (HSGQ ببرمجيّةٍ قديمة) لا يكشف قائمة الـONU عبر SNMP — أضف «دخول صفحة الأولت»')!;
      expect(hsgq.detail, DeviceCheckText.dataErrorHint);
    });

    test('فشل الاتّصال نفسه ⇒ «تأكّد من الـcommunity والمنفذ» كما كان', () {
      final n = DeviceCheckText.note(d, c, readError: 'تعذّر الاتّصال بالـOLT عبر SNMP: timeout')!;
      expect(n.detail, 'تأكّد من إعدادات الجهاز: الـcommunity والمنفذ');
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
      return NscrtvOlt.buildStats(
        profile: _profile,
        sysDescr: 'EasyPath Ethernet-PON',
        sysName: 'EasyPath Series PON Switch Access',
        ports: const [
          VsolIfRow(index: 1, name: 'ge0/0/1', up: true, mac: null, speedMbps: 1000, rxBytes: 0, txBytes: 0),
          VsolIfRow(index: 5, name: 'xge0/0/1', up: false, mac: null, speedMbps: 10000, rxBytes: 0, txBytes: 0),
          VsolIfRow(index: 7, name: 'pon0/0/1', up: true, mac: null, speedMbps: 1000, rxBytes: 0, txBytes: 0),
          VsolIfRow(index: 8, name: 'pon0/0/2', up: true, mac: null, speedMbps: 1000, rxBytes: 0, txBytes: 0),
        ],
        status: {_i(7, 1): false, _i(7, 2): true},
        macs: {_i(7, 1): '02:00:00:07:01:00', _i(7, 2): '02:00:00:07:02:00'},
      ).withEponDetails(OltEponDetails(
        readings: {_i(7, 2): const BdcomOnuReading(rxDbm: -21.57, txDbm: 1.83, tempC: 30.6, voltV: 3.212)},
        readingsAt: at,
        identities: {_i(7, 2): const BdcomOnuReading(vendor: 'HWTC', module: '321R')},
        macsAt: at,
        chassis: const BdcomChassis(),
        chassisAt: at,
      ));
    }

    NetworkDevice device(int id) => NetworkDevice(
          id: id,
          adminId: 'fixture',
          name: 'c-data-olt',
          type: 'switch',
          brand: 'cdata',
          ip: '127.0.0.1',
          port: 161,
          apiPort: 161,
          protocol: 'snmp',
          lastStatus: 'online',
          createdAt: DateTime.utc(2026),
        );

    testWidgets('هاتف ٣٢٠: الماك للمتّصلة والمفصولة، والضوء، ولا معالج، والمنفذان بعدّهما', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      const id = 99010969;
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
      expect(find.text('02:00:00:07:02:00'), findsOneWidget);
      expect(find.text('02:00:00:07:01:00'), findsOneWidget, reason: 'ماك المفصولة هويّتها المسجّلة');
      expect(find.textContaining('RX -21.6 dBm'), findsOneWidget);
      expect(find.textContaining('CPU'), findsNothing);
      expect(find.byKey(const ValueKey('EPON0/1:2')), findsOneWidget);
      expect(find.textContaining('قراءةٌ ناقصة'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
