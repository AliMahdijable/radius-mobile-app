import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/olt_fiber_reads.dart';
import 'package:rad_mysvcs/api/olt_profile.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/services/fiber/fiber_onu.dart';

import 'support/fake_snmp_agent.dart';

/// قرّاء الألياف على وكيلٍ وهميّ بالقيم كما تصفها مصادرها (MIB المصنّع ومشاريع مفتوحة) — الماكات والأسماء اصطناعيّة.
const bdcom = OltProfile(vendor: OltVendor.bdcom, oltLikely: true, identified: true, model: 'P3600-04');
const vsol = OltProfile(vendor: OltVendor.vsol, oltLikely: true, identified: true, model: 'V1600D');

VsolOnu o(int pon, int id, {bool online = true, VsolPonTechnology tech = VsolPonTechnology.epon, int? ifIndex}) => VsolOnu(
      ifIndex: ifIndex ?? (pon * 100 + id),
      slot: 0,
      ponPort: pon,
      onuId: id,
      online: online,
      technology: tech,
    );

void main() {
  const e = OltFiberReads.vsolEponOptics;
  const g = OltFiberReads.vsolGponOptics;
  const a = OltFiberReads.vsolEponAuth;
  const b = OltFiberReads.bdcomDeregReason;

  group('تحليل القيم', () {
    test('نصّ VSOL بأشكاله: عشريٌّ كما هو، ووحداتٌ ملتصقة، وناقص يونيكود', () {
      expect(OltFiberReads.scaled(snmpText('1', '-21.35'), lo: -45, hi: 10), -21.35);
      expect(OltFiberReads.scaled(snmpText('1', '-21.35(dBm)'), lo: -45, hi: 10), -21.35);
      expect(OltFiberReads.scaled(snmpText('1', ' -21.35 dBm '), lo: -45, hi: 10), -21.35);
      expect(OltFiberReads.scaled(snmpText('1', '−21.35'), lo: -45, hi: 10), -21.35);
      expect(OltFiberReads.scaled(snmpText('1', '45.20 C'), lo: -30, hi: 120), 45.2);
      // VSOL V1600D (‏«Moh»، ٢٧ أكتوبر): الميلّيواط أوّلاً ثمّ الـdBm بين قوسين — كانت تُقرأ ‎0.01.
      expect(OltFiberReads.dbm(snmpText('1', '0.0070 mW(-21.55dBm)')), -21.55);
      expect(OltFiberReads.dbm(snmpText('1', '1.6982 mW(2.30dBm)'), lo: -15, hi: 12), 2.3);
      expect(OltFiberReads.dbm(snmpText('1', '0.0070 mW')), -21.55, reason: 'ميلّيواط وحده ⇒ 10·log10');
      expect(OltFiberReads.dbm(snmpText('1', '7.00 uW')), -21.55);
      expect(OltFiberReads.dbm(snmpText('1', 'Rx:-21.55dBm')), -21.55);
      expect(OltFiberReads.dbm(snmpText('1', '-21.55 dBm (0.0070mW)')), -21.55);
      expect(OltFiberReads.dbm(snmpText('1', '0.0000 mW(-inf dBm)')), isNull, reason: 'لا ضوء ⇒ لا رقم');
      expect(OltFiberReads.dbm(snmpText('1', '-21.35')), -21.35, reason: 'بلا وحدة ⇒ كالسابق');
      expect(OltFiberReads.dbm(snmpInt('1', -2135)), -21.35);
      final r = OltFiberReads.vsolReading(snmpText('1', '0.0070 mW(-21.55dBm)'), snmpText('1', '1.6982 mW(2.30dBm)'),
          snmpText('1', '45.00 C'), snmpText('1', '3.27 V'))!;
      expect([r.rxDbm, r.txDbm, r.tempC, r.voltV], [-21.55, 2.3, 45.0, 3.27]);
    });

    test('أعدادٌ صحيحة مقسومة: أوّل قسمةٍ في المدى المعقول', () {
      expect(OltFiberReads.scaled(snmpInt('1', -2135), lo: -45, hi: 10), -21.35);
      expect(OltFiberReads.scaled(snmpText('1', '-2135'), lo: -45, hi: 10), -21.35);
      expect(OltFiberReads.scaled(snmpInt('1', -213), lo: -45, hi: 10), -21.3);
      expect(OltFiberReads.scaled(snmpInt('1', 3300), lo: 2.5, hi: 5.5, divisors: const [1, 10, 100, 1000, 10000]), 3.3);
      expect(OltFiberReads.scaled(snmpInt('1', 330), lo: 2.5, hi: 5.5, divisors: const [1, 10, 100, 1000, 10000]), 3.3);
    });

    test('لا رقم كاذب: غائب · فارغ · N/A · -- · صفر · عشريٌّ خارج المدى لا يُقسم', () {
      for (final vb in [
        snmpText('1', ''),
        snmpText('1', 'N/A'),
        snmpText('1', '--'),
        snmpText('1', '0.00'),
        snmpInt('1', 0),
        snmpText('1', '-80.5'),
      ]) {
        expect(OltFiberReads.scaled(vb, lo: -45, hi: 10), isNull, reason: vb.toString());
      }
      expect(OltFiberReads.vsolReading(snmpText('1', '-40.00'), null, snmpText('1', '41.5'), null)!.rxDbm, isNull,
          reason: '−40 «لا ضوء» لجهازٍ متّصل لا يُعقل، والحرارة تبقى');
    });

    test('سبب السقوط: VSOL 1 كهرباء و2 ضوء و0 غامض؛ BDCOM 8 ضوء و9 كهرباء والبقيّة «آخر»', () {
      expect(OltFiberReads.vsolReason(snmpInt('1', 1)), FiberDropReason.power);
      expect(OltFiberReads.vsolReason(snmpInt('1', 2)), FiberDropReason.fiber);
      expect(OltFiberReads.vsolReason(snmpInt('1', 0)), FiberDropReason.unknown);
      expect(OltFiberReads.bdcomReason(snmpInt('1', 8)), FiberDropReason.fiber);
      expect(OltFiberReads.bdcomReason(snmpInt('1', 9)), FiberDropReason.power);
      expect(OltFiberReads.bdcomReason(snmpInt('1', 7)), FiberDropReason.other);
      expect(OltFiberReads.bdcomReason(snmpInt('1', 255)), FiberDropReason.unknown);
      expect(OltFiberReads.bdcomReason(snmpText('1', 'x')), isNull);
    });

    test('لحظة التغيّر من وقت التشغيل: الآن − (sysUpTime − ifLastChange)، وصفرٌ/أكبر = قبل الإقلاع', () {
      final now = DateTime.utc(2026, 10, 27, 11, 55);
      expect(OltFiberReads.changedAt(upTicks: 1000000, lastChangeTicks: 999500, now: now), now.subtract(const Duration(seconds: 5)));
      expect(OltFiberReads.changedAt(upTicks: 1000000, lastChangeTicks: 0, now: now), isNull);
      expect(OltFiberReads.changedAt(upTicks: 1000000, lastChangeTicks: 1000001, now: now), isNull);
    });
  });

  group('القراءة من الوكيل', () {
    test('ضوء VSOL EPON وGPON بفهرس المنفذ.الجهاز، والمفصول لا يُسأل', () async {
      final agent = FakeSnmpAgent({
        '$e.7.3.2': snmpText('', '-21.35'),
        '$e.6.3.2': snmpText('', '2.31'),
        '$e.3.3.2': snmpText('', '45.20'),
        '$e.4.3.2': snmpText('', '3.30'),
        '$g.7.1.4': snmpInt('', -2412),
        '$g.6.1.4': snmpInt('', 215),
        '$e.7.3.5': snmpText('', '-26.9'),
      });
      final r = await OltFiberReads.vsolOptics(agent, [
        o(3, 2),
        o(1, 4, tech: VsolPonTechnology.gpon),
        o(3, 5, online: false),
      ]);
      expect(r[302]!.rxDbm, -21.35);
      expect(r[302]!.txDbm, 2.31);
      expect(r[302]!.tempC, 45.2);
      expect(r[302]!.voltV, 3.3);
      expect(r[104]!.rxDbm, -24.12);
      expect(r[104]!.txDbm, 2.15);
      expect(r.containsKey(305), isFalse);
      expect(agent.gets.expand((x) => x).any((oid) => oid.endsWith('.3.5')), isFalse);
    });

    test('أسباب السقوط: BDCOM بـifIndex، وVSOL EPON بالعمود 15، وGPON لا يُسأل، والمتّصل لا يُسأل', () async {
      final bAgent = FakeSnmpAgent({'$b.97': snmpInt('', 8), '$b.103': snmpInt('', 9)});
      final br = await OltFiberReads.dropReasons(bAgent, bdcom, [
        o(1, 1, online: false, ifIndex: 97),
        o(1, 7, online: false, ifIndex: 103),
        o(1, 8, online: false, ifIndex: 104),
        o(1, 9, ifIndex: 105),
      ]);
      expect(br, {97: FiberDropReason.fiber, 103: FiberDropReason.power});
      expect(bAgent.gets.expand((x) => x).contains('$b.105'), isFalse);

      final vAgent = FakeSnmpAgent({'$a.15.2.7': snmpInt('', 1), '$a.15.2.8': snmpInt('', 2), '$a.15.2.9': snmpInt('', 0)});
      final vr = await OltFiberReads.dropReasons(vAgent, vsol, [
        o(2, 7, online: false),
        o(2, 8, online: false),
        o(2, 9, online: false),
        o(1, 1, online: false, tech: VsolPonTechnology.gpon),
      ]);
      expect(vr, {207: FiberDropReason.power, 208: FiberDropReason.fiber, 209: FiberDropReason.unknown});
      expect(vAgent.gets.expand((x) => x).any((oid) => oid.contains('.15.1.1')), isFalse);
    });

    test('لحظات التغيّر بدفعات ومع sysUpTime كلّ دفعة', () async {
      final now = DateTime.utc(2026, 10, 27, 11, 55);
      final agent = FakeSnmpAgent({
        OltFiberReads.sysUpTimeOid: snmpTicks('', 5000000),
        for (var i = 1; i <= 30; i++) '${OltFiberReads.ifLastChangeOid}.$i': snmpTicks('', 5000000 - i * 100),
      });
      final r = await OltFiberReads.lastChanges(agent, [for (var i = 1; i <= 30; i++) i], now: now);
      expect(r.length, 30);
      expect(r[1], now.subtract(const Duration(seconds: 1)));
      expect(r[30], now.subtract(const Duration(seconds: 30)));
      expect(agent.gets.every((q) => q.first == OltFiberReads.sysUpTimeOid && q.length <= 16), isTrue);
    });

    test('أسماء الأجهزة: ifAlias بالعربيّ، ووصف VSOL احتياطاً، والاسم الافتراضيّ (ONU0/1:1) لا يُعدّ اسماً', () async {
      final agent = FakeSnmpAgent({
        '${OltFiberReads.ifAliasOid}.302': snmpText('', 'علي كريم'),
        '${OltFiberReads.ifAliasOid}.303': snmpText('', 'EPON0/3:3'),
        '$a.9.3.3': snmpText('', 'karar77'),
        '${OltFiberReads.ifAliasOid}.304': snmpBytes('', [0x00, 0x00]),
      });
      final r = await OltFiberReads.names(agent, vsol, [o(3, 2), o(3, 3), o(3, 4)]);
      expect(r, {302: 'علي كريم', 303: 'karar77'});
      expect(agent.gets, isEmpty, reason: 'بمسح العمودين لا بسؤال كلّ جهاز');
    });

    test('«NULL» اسماً لكلّ الأجهزة (V1600D، ٢٧ أكتوبر) ليس اسماً: يُرفض ويُقرأ وصف VSOL بدله', () async {
      OltFiberReads.debugReset();
      final agent = FakeSnmpAgent({
        '${OltFiberReads.ifAliasOid}.302': snmpText('', 'NULL'),
        '${OltFiberReads.ifAliasOid}.303': snmpText('', 'NULL'),
        '${OltFiberReads.ifAliasOid}.304': snmpText('', 'null'),
        '$a.9.3.3': snmpText('', 'karar77'),
        '$a.9.3.4': snmpText('', 'EPON03ONU4'),
      });
      final r = await OltFiberReads.names(agent, vsol, [o(3, 2), o(3, 3), o(3, 4)]);
      expect(r, {303: 'karar77'}, reason: '«EPON03ONU4» اسم الواجهة الافتراضيّ لا اسم مشترك');
    });

    test('تنظيف الأسماء: الحشو يُرفض، والقيمة الواحدة المكرّرة على أغلب الأجهزة حشو، والأسماء المميّزة تبقى', () {
      expect(OltFiberReads.cleanNames({1: 'NULL', 2: 'none', 3: 'N/A', 4: '-', 5: 'علي'}), {5: 'علي'});
      final same = {for (var i = 1; i <= 10; i++) i: 'test'}..[11] = 'كرار';
      expect(OltFiberReads.cleanNames(same), {11: 'كرار'});
      final distinct = {for (var i = 1; i <= 10; i++) i: 'user$i'};
      expect(OltFiberReads.cleanNames(distinct), distinct);
      expect(OltFiberReads.cleanNames({1: 'Ali', 2: 'Ali'}), {1: 'Ali', 2: 'Ali'}, reason: 'تكرارٌ قليل ليس حشواً');
      expect(OltFiberReads.cleanNames({1: 'EPON01ONU12', 2: 'EPON0/1:3', 3: 'PON1:ONU5', 4: 'ONU0/1:1', 5: 'karar77'}), {5: 'karar77'},
          reason: 'لقطةٌ قديمة تحمل أسماء الواجهات الافتراضيّة ⇒ تُنظَّف عند التحميل');
    });

    test('ماك أجهزة VSOL EPON من ifPhysAddress بمسحةٍ واحدة: الصفريّ وغير المطلوب لا يُعدّان', () async {
      OltFiberReads.debugReset();
      final agent = FakeSnmpAgent({
        '${OltFiberReads.ifPhysOid}.1': snmpBytes('', [0x11, 0x22, 0x33, 0x44, 0x55, 0x66]),
        '${OltFiberReads.ifPhysOid}.302': snmpBytes('', [0x7c, 0x6a, 0x60, 0x0e, 0x08, 0x07]),
        '${OltFiberReads.ifPhysOid}.303': snmpBytes('', [0, 0, 0, 0, 0, 0]),
        '${OltFiberReads.ifPhysOid}.304': snmpBytes('', [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]),
      });
      final r = await OltFiberReads.vsolEponMacs(agent, {302, 303, 304});
      expect(r, {302: '7c:6a:60:0e:08:07', 304: 'aa:bb:cc:dd:ee:ff'});
      expect(agent.gets, isEmpty, reason: 'مسح عمود لا سؤال كلّ جهاز');
      expect(await OltFiberReads.vsolEponMacs(FakeSnmpAgent({}, failGets: true), {302}), anyOf(isNull, isEmpty));
    });

    test('جهازٌ لا يجيب (مهلة) ⇒ قراءاتٌ فارغة لا استثناء', () async {
      final agent = FakeSnmpAgent({}, failGets: true);
      expect(await OltFiberReads.vsolOptics(agent, [o(3, 2)]), isEmpty);
      expect(await OltFiberReads.dropReasons(agent, bdcom, [o(1, 1, online: false)]), isEmpty);
      expect(await OltFiberReads.lastChanges(agent, [1, 2]), isEmpty);
    });

    test('فحص القدرات بلا هويّات: لا ماك ولا اسم ولا SN في التقرير — أعدادٌ وأشكالٌ فقط', () async {
      final agent = FakeSnmpAgent({
        OltFiberReads.sysUpTimeOid: snmpTicks('', 9000000),
        '${OltFiberReads.ifLastChangeOid}.302': snmpTicks('', 8999000),
        '${OltFiberReads.ifLastChangeOid}.305': snmpTicks('', 8000000),
        '$e.7.3.2': snmpText('', '-21.35'),
        '$e.6.3.2': snmpText('', '2.31'),
        '$e.3.3.2': snmpText('', 'secret-ish text'),
        '$a.15.3.5': snmpInt('', 1),
        '${OltFiberReads.ifAliasOid}.302': snmpText('', 'karar77'),
      });
      final caps = await OltFiberReads.probe(agent, vsol, [o(3, 2), o(3, 5, online: false)]);
      expect(caps.hasLastChange, isTrue);
      expect(caps.hasOptics, isTrue);
      expect(caps.hasReasons, isTrue);
      expect(caps.rawReasons, {'1': 1});
      expect(caps.opticsShapes, ['str:"-21.35"', 'str:"2.31"', 'fmt:"xxxxxx-xxx xxxx"', 'absent']);
      final js = jsonEncode(caps.toJson());
      expect(js.contains('karar77'), isFalse);
      expect(js.contains('secret'), isFalse);
    });
  });
}
