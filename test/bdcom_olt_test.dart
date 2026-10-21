import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/bdcom_epon.dart';
import 'package:rad_mysvcs/api/bridge_fdb.dart';
import 'package:rad_mysvcs/api/olt_profile.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_image.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_image_bdcom_catalog.dart';

/// BDCOM EPON OLT (٢٢ أكتوبر) — اختبارات القبول من دليل التدقيق
/// (docs/CLAUDE_BDCOM_GUIDE.txt §١٠). كلّ الماكات اصطناعيّة (02:…) — لا
/// عنوان زبونٍ حقيقيّ هنا.

Uint8List _int(int v) {
  final out = <int>[];
  var x = v;
  while (true) {
    out.insert(0, x & 0xff);
    final next = x >> 8;
    final neg = (out.first & 0x80) != 0;
    if ((next == 0 && !neg) || (next == -1 && neg)) break;
    x = next;
  }
  return Uint8List.fromList(out);
}

Varbind vInt(String oid, int v) => Varbind(oid: oid, rawTag: 0x02, rawBytes: _int(v));
Varbind vGauge(String oid, int v) =>
    Varbind(oid: oid, rawTag: 0x42, rawBytes: Uint8List.fromList(_int(v).where((_) => true).toList()));
Varbind vOct(String oid, List<int> b) => Varbind(oid: oid, rawTag: 0x04, rawBytes: Uint8List.fromList(b));
Varbind vAbsent(String oid) => Varbind(oid: oid, rawTag: 0x81, rawBytes: Uint8List(0));

VsolIfRow r(int i, String name, {bool up = true, String? mac}) =>
    VsolIfRow(index: i, name: name, up: up, mac: mac, speedMbps: 0, rxBytes: 0, txBytes: 0);

const _bdcomSysDescr = 'BDCOM(tm) P3600-04 Software, Version 124293; hardwareversion:D';
const _bdcomOid = '1.3.6.1.4.1.3320.1.495.0';

/// جدول IF-MIB كما رآه التدقيق: ٨ صعود (33..40)، ٤ PON (41..44)، ONU
/// على فهارس غير متتالية، وواجهاتٌ أخرى لا تُصنَّف.
List<VsolIfRow> _bdcomRows({String sharedIfPhys = '02:00:00:00:ff:01'}) => [
      for (var i = 1; i <= 4; i++) r(32 + i, 'GigaEthernet0/$i', up: i == 1),
      for (var i = 1; i <= 4; i++) r(36 + i, 'TGigaEthernet0/$i', up: i == 2),
      for (var p = 1; p <= 4; p++) r(40 + p, 'EPON0/$p', up: p != 4),
      r(97, 'EPON0/1:1', mac: sharedIfPhys),
      r(103, 'EPON0/1:7', up: false, mac: sharedIfPhys),
      r(166, 'EPON0/2:6', mac: sharedIfPhys),
      r(1, 'VLAN1'),
      r(2, 'Null0'),
      r(3, 'loopback0'),
    ];

NetworkDevice _dev({required String brand, String? model, String protocol = 'snmp', bool creds = true}) => NetworkDevice(
      id: 1,
      adminId: 'fixture',
      name: 'OLT',
      type: 'other',
      brand: brand,
      model: model,
      ip: '127.0.0.1',
      port: 161,
      apiPort: 161,
      protocol: protocol,
      hasCredentials: creds,
      lastStatus: 'online',
      createdAt: DateTime.utc(2026),
    );

void main() {
  group('ملفّ المصنّع (OltProfile)', () {
    test('سجلّ المالك القديم: vsol وطرازه BDCOM ⇒ BDCOM ولوحة الأولت', () {
      final p = OltProfile.fromRecord(brand: 'vsol', model: 'BDCOM P3600-04');
      expect(p.vendor, OltVendor.bdcom);
      expect(p.model, 'P3600-04');
      expect(p.opensOltPanel, isTrue);
    });

    test('سويتش BDCOM العاديّ لا يفتح لوحة ONU — المؤسّسة 3320 وحدها لا تكفي', () {
      final p = OltProfile.fromRecord(brand: 'bdcom', model: 'S2528-B');
      expect(p.vendor, OltVendor.bdcom);
      expect(p.opensOltPanel, isFalse);
    });

    test('الهويّة الحيّة تغلب العلامة المخزَّنة', () {
      final live = OltProfile.resolve(OltProfile.vsolDefault, sysObjectId: _bdcomOid, sysDescr: _bdcomSysDescr);
      expect(live.vendor, OltVendor.bdcom);
      expect(live.identified, isTrue);
      expect(live.model, 'P3600-04');
      expect(live.readsInterfaceMac, isFalse, reason: 'ifPhysAddress عنوان واجهةٍ مشترك على BDCOM');
      expect(live.readsVsolTables, isFalse, reason: 'لا يُسأل BDCOM عن جدول VSOL 37950');
      expect(live.readsBdcomEponTables, isTrue);
    });

    test('هويّةٌ غامضة تُبقي التلميح كما هو، وVSOL يبقى VSOL', () {
      expect(OltProfile.resolve(OltProfile.vsolDefault, sysDescr: 'Linux'), OltProfile.vsolDefault);
      expect(OltProfile.fromRecord(brand: 'vsol', model: 'V1600D8').vendor, OltVendor.vsol);
    });

    test('مواصفات الكتالوج للطراز الأساسيّ وحده', () {
      expect(OltProfile.fromRecord(brand: 'bdcom', model: 'P3600-04').catalogSpecs, isNotNull);
      expect(OltProfile.fromRecord(brand: 'bdcom', model: 'P3600-04-2AC').catalogSpecs, isNull);
    });
  });

  group('المحلّل: صعود BDCOM وONU', () {
    test('GigaEthernet وTGigaEthernet ⇒ ٨ صعود، EPON0/x ⇒ ٤ PON، ولا VLAN/Null/loopback', () {
      final b = VsolParse.build(_bdcomRows(), profile: OltProfile.fromRecord(brand: 'bdcom', model: 'P3600-04'));
      expect(b.uplinks.length, 8, reason: 'كانت تسقط الثمانية كلّها');
      expect(b.uplinks.where((u) => u.up).length, 2, reason: 'الصعود يظهر ولو كان مفصولاً');
      expect(b.ponPorts.length, 4);
      expect(b.onus.map((o) => o.label), ['EPON0/1:1', 'EPON0/1:7', 'EPON0/2:6']);
      expect(b.onusOnline, 2);
    });

    test('BDCOM: عنوان الواجهة المتكرّر لا يصير ماكاً لأيّ مشترك', () {
      final b = VsolParse.build(_bdcomRows(), profile: OltProfile.fromRecord(brand: 'bdcom', model: 'P3600-04'));
      expect(b.onus.every((o) => o.mac == null), isTrue);
    });

    test('VSOL EPON كما كان: ماك المتّصل من IF-MIB، والمفصول بلا ماك', () {
      final b = VsolParse.build([
        r(1, 'EPON0/1'),
        r(9, 'EPON0/1:1', mac: '02:00:00:00:00:09'),
        r(10, 'EPON0/1:2', up: false, mac: '02:00:00:00:00:0a'),
      ]);
      expect(b.onus.first.mac, '02:00:00:00:00:09');
      expect(b.onus.last.mac, isNull);
    });

    test('GPON: لا ماك من IF-MIB (هويّتها SN)', () {
      final b = VsolParse.build([r(1, 'GPON0/1'), r(9, 'GPON0/1:1', mac: '02:00:00:00:00:09')]);
      expect(b.onus.single.mac, isNull);
    });
  });

  group('ماك الـONU من جدول المصنّع', () {
    test('ستّة بايتات خام — لا صفريّ ولا بثّ ولا جماعيّ ولا طولٌ آخر', () {
      expect(BdcomEpon.macFrom(vOct('x', [0x02, 0, 0, 0, 1, 1])), '02:00:00:00:01:01');
      expect(BdcomEpon.macFrom(vOct('x', [0, 0, 0, 0, 0, 0])), isNull);
      expect(BdcomEpon.macFrom(vOct('x', [255, 255, 255, 255, 255, 255])), isNull);
      expect(BdcomEpon.macFrom(vOct('x', [0x01, 0, 0x5e, 0, 0, 1])), isNull);
      expect(BdcomEpon.macFrom(vOct('x', [2, 0, 0, 0, 1])), isNull);
      expect(BdcomEpon.macFrom(vAbsent('x')), isNull);
      expect(BdcomEpon.macFrom(vInt('x', 5)), isNull);
    });

    test('عدّة ONU بعنوان واجهةٍ واحد ⇒ ماكاتٌ مختلفة من المصنّع، لا ifPhys', () {
      final profile = OltProfile.fromRecord(brand: 'bdcom', model: 'P3600-04');
      final b = VsolParse.build(_bdcomRows(), profile: profile);
      final stats = VsolOltStats(uplinks: b.uplinks, ponPorts: b.ponPorts, onus: b.onus, profile: profile).withEponDetails(
        OltEponDetails(
          onuMacs: const {97: '02:00:00:00:01:01', 103: '02:00:00:00:01:07', 166: '02:00:00:00:02:06'},
          macsAt: DateTime.utc(2026, 10, 22),
        ),
      );
      final macs = stats.onus.map((o) => o.mac).toList();
      expect(macs.toSet().length, 3);
      expect(macs.contains('02:00:00:00:ff:01'), isFalse);
    });
  });

  group('أجهزة خلف الـONU — جدول الجسر', () {
    // MAC_REGRESSION_FIXTURE.json من حزمة التدقيق — اصطناعيّة كلّها.
    final ports = {7: 97, 9: 166, 3: 34};
    final rows = [
      const FdbRow(fdbId: 12, mac: '02:10:00:00:00:01', bridgePort: 7, status: 3),
      const FdbRow(fdbId: 12, mac: '02:10:00:00:00:02', bridgePort: 7, status: 3),
      const FdbRow(fdbId: 12, mac: '02:10:00:00:00:03', bridgePort: 9, status: 3),
      const FdbRow(fdbId: 12, mac: '02:10:00:00:00:fe', bridgePort: 3, status: 3),
      const FdbRow(fdbId: 12, mac: '02:00:00:00:ff:01', bridgePort: 7, status: 4),
      const FdbRow(fdbId: 12, mac: '00:00:00:00:00:00', bridgePort: 9, status: 3),
    ];

    test('الربط عبر الجدول (منفذ الجسر ≠ ifIndex)، بلا صعودٍ ولا self ولا صفريّ', () {
      final f = BridgeFdb.build(bridgePortToIfIndex: ports, rows: rows, targets: {97, 166}, complete: true);
      expect(f.macsByIfIndex, {
        97: ['02:10:00:00:00:01', '02:10:00:00:00:02'],
        166: ['02:10:00:00:00:03'],
      });
    });

    test('عنوانٌ على ONU‏َين ملتبسٌ فيُسقط، والمكرّر داخل ONU واحدة مرّة، وبلا ربطٍ لا إسناد', () {
      final f = BridgeFdb.build(
        bridgePortToIfIndex: ports,
        rows: [
          const FdbRow(fdbId: 1, mac: '02:20:00:00:00:01', bridgePort: 7, status: 3),
          const FdbRow(fdbId: 2, mac: '02:20:00:00:00:01', bridgePort: 9, status: 3),
          const FdbRow(fdbId: 1, mac: '02:20:00:00:00:02', bridgePort: 7, status: 3),
          const FdbRow(fdbId: 5, mac: '02:20:00:00:00:02', bridgePort: 7, status: 3),
          const FdbRow(fdbId: 1, mac: '02:20:00:00:00:03', bridgePort: 99, status: 3),
        ],
        targets: {97, 166},
        complete: true,
      );
      expect(f.macsByIfIndex, {
        97: ['02:20:00:00:00:02'],
      });
    });

    test('مفتاح الصفّ من الـOID: ‏Q-BRIDGE ‏(fdbId + ٦) وBRIDGE-MIB ‏(٦)، والمشوَّه يُرفض', () {
      final q = BridgeFdb.rowFromIndex('12.2.16.0.0.0.1', withFdbId: true, bridgePort: 7, status: 3)!;
      expect(q.fdbId, 12);
      expect(q.mac, '02:10:00:00:00:01');
      final d = BridgeFdb.rowFromIndex('2.16.0.0.0.1', withFdbId: false, bridgePort: 7, status: 3)!;
      expect(d.fdbId, 0);
      expect(d.mac, '02:10:00:00:00:01');
      expect(BridgeFdb.rowFromIndex('12.2.16.0.0.1', withFdbId: true, bridgePort: 7, status: 3), isNull);
      expect(BridgeFdb.rowFromIndex('12.2.16.0.0.0.300', withFdbId: true, bridgePort: 7, status: 3), isNull);
    });

    test('المفصول بلا أجهزة، والناقص يُعلَّم ناقصاً — لا يُقدَّم كاملاً', () {
      final profile = OltProfile.fromRecord(brand: 'bdcom', model: 'P3600-04');
      final b = VsolParse.build(_bdcomRows(), profile: profile);
      final fdb = FdbSnapshot(macsByIfIndex: const {
        97: ['02:10:00:00:00:01'],
        103: ['02:10:00:00:00:07'],
      }, complete: false, supported: true);
      final s = VsolOltStats(onus: b.onus, ponPorts: b.ponPorts, profile: profile)
          .withEponDetails(OltEponDetails(fdb: fdb, fdbAt: DateTime.utc(2026, 10, 22)));
      final on = s.onus.firstWhere((o) => o.ifIndex == 97);
      final off = s.onus.firstWhere((o) => o.ifIndex == 103);
      expect(on.learnedMacs, ['02:10:00:00:00:01']);
      expect(on.learnedMacsComplete, isFalse);
      expect(off.learnedMacs, isEmpty, reason: 'الجدول يشيخ — عنوان ما قبل الفصل ليس حيّاً');
      expect(on.mac, isNull, reason: 'القائمة الفارغة/الأجهزة لا تُملأ بماك الـONU ولا العكس');
    });
  });

  group('الوحدات كما ثبتت حيّاً', () {
    test('الضوء ٠٫١ dBm، الحرارة ÷٢٥٦، الجهد ×٠٫٠٠٠١ — والغائب null لا صفر', () {
      expect(BdcomEpon.dbmFrom(vInt('x', -135)), -13.5);
      expect(BdcomEpon.dbmFrom(vInt('x', 21)), 2.1);
      expect(BdcomEpon.onuTempFrom(vInt('x', 11776)), 46.0);
      expect(BdcomEpon.voltFrom(vInt('x', 33170)), closeTo(3.317, 1e-9));
      expect(BdcomEpon.dbmFrom(vAbsent('x')), isNull);
      expect(BdcomEpon.onuTempFrom(vAbsent('x')), isNull);
      expect(BdcomEpon.voltFrom(vAbsent('x')), isNull);
      expect(BdcomEpon.dbmFrom(vInt('x', -900)), isNull, reason: 'خارج مدى الضوء = وحدةٌ أخرى لا قراءة');
    });

    test('المعالج Gauge32 مقبول ضمن ٠..١٠٠، والذاكرة إجماليٌّ بالبايت وحده', () {
      expect(BdcomEpon.cpuFrom([vGauge('${BdcomEpon.cpuTableOid}.1', 9)]), 9);
      expect(BdcomEpon.cpuFrom([vAbsent('${BdcomEpon.cpuTableOid}.1')]), isNull);
      expect(BdcomEpon.cpuFrom([vGauge('${BdcomEpon.cpuTableOid}.1', 250)]), isNull);
      expect(BdcomEpon.ramFrom(vInt('x', 268435456)), 268435456);
      expect(BdcomEpon.ramFrom(vInt('x', 268435456 * 1024 * 1024)), isNull, reason: 'لا ٢٥٦ جيجا من خلط الوحدات');
      expect(BdcomEpon.boxTempFrom(vInt('x', 31)), 31);
      expect(BdcomEpon.textFrom(vOct('x', 'HWTC'.codeUnits)), 'HWTC');
      expect(BdcomEpon.textFrom(vOct('x', 'N/A'.codeUnits)), isNull);
    });

    test('قراءة الضوء للمتّصل وحده', () {
      final profile = OltProfile.fromRecord(brand: 'bdcom', model: 'P3600-04');
      final b = VsolParse.build(_bdcomRows(), profile: profile);
      final s = VsolOltStats(onus: b.onus, profile: profile).withEponDetails(OltEponDetails(
        readings: const {
          97: BdcomOnuReading(rxDbm: -13.5, txDbm: 2.1, tempC: 46, voltV: 3.317),
          103: BdcomOnuReading(rxDbm: -20),
        },
        readingsAt: DateTime.utc(2026, 10, 22),
      ));
      expect(s.onus.firstWhere((o) => o.ifIndex == 97).reading?.rxDbm, -13.5);
      expect(s.onus.firstWhere((o) => o.ifIndex == 103).reading, isNull);
    });
  });

  group('صور BDCOM', () {
    test('مطابقةٌ تامّة للرمز مع BDCOM/الحالة/الفواصل', () {
      expect(DeviceImage.assetFor('BDCOM P3600-04', brand: 'bdcom'), 'bdcom/P3600-04.webp');
      expect(DeviceImage.assetFor('P3600-04', brand: 'bdcom'), 'bdcom/P3600-04.webp');
      expect(DeviceImage.assetFor('bdcom p3600 04', brand: 'bdcom'), 'bdcom/P3600-04.webp');
      expect(DeviceImage.assetFor('BDCOM P3600-04-2AC', brand: 'bdcom'), 'bdcom/P3600-04-2AC.webp');
      expect(DeviceImage.assetFor('P3600-08-2AC', brand: 'bdcom'), 'bdcom/P3600-08-2AC.webp');
    });

    test('لا تصادم: GP3600-04D ليس P3600-04، ولا P3600-08E أو P3608 مرادفين', () {
      expect(DeviceImage.assetFor('BDCOM GP3600-04D', brand: 'bdcom'), isNull);
      expect(DeviceImage.assetFor('BDCOM P3600-08E', brand: 'bdcom'), isNull);
      expect(DeviceImage.assetFor('BDCOM P3608', brand: 'bdcom'), isNull);
    });

    test('السجلّ القديم (vsol وطرازه BDCOM) يرى صورته، ولا صورة BDCOM لـVSOL أو غيره بالنصّ وحده', () {
      expect(DeviceImage.assetFor('BDCOM P3600-04', brand: 'vsol'), 'bdcom/P3600-04.webp');
      expect(DeviceImage.assetFor('P3600-04', brand: 'vsol'), isNull);
      expect(DeviceImage.assetFor('P3600-04', brand: 'mikrotik'), isNull);
    });

    test('كلّ صورةٍ موجودةٌ وصالحة (WEBP)، والمنتقي يكتب الطراز بلا مجلّد ويعود إلى الصورة نفسها', () {
      for (final f in kBdcomCatalog.values) {
        final bytes = File('assets/devices-images/$f').readAsBytesSync();
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF', reason: f);
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WEBP', reason: f);
      }
      expect(DeviceImage.boardNameOf('bdcom/P3600-04.webp'), 'P3600-04');
      expect(DeviceImage.boardNameOf('vsol/V1600D8.jpg'), 'V1600D8');
      final all = DeviceImage.allAssets;
      expect(all.toSet().length, all.length, reason: 'لا تكرار بعدد المرادفات');
      final picked = [
        for (final f in all)
          if (DeviceImage.assetFor(DeviceImage.boardNameOf(f), brand: 'bdcom') == f) f,
      ];
      expect(picked, containsAll(kBdcomCatalog.values));
    });
  });

  group('النظرة العامّة: ملخّص الأولت وسسكو وروجي', () {
    test('تُقاس كميكروتك، وبروتوكول لوحتها شرط', () {
      expect(DeviceVitals.skipReason(_dev(brand: 'bdcom', model: 'P3600-04')), isNull);
      expect(DeviceVitals.skipReason(_dev(brand: 'vsol', model: 'BDCOM P3600-04')), isNull);
      expect(DeviceVitals.skipReason(_dev(brand: 'other', model: 'V1600D8')), isNull, reason: 'أولت قديمٌ مسجّل «أخرى»');
      expect(DeviceVitals.skipReason(_dev(brand: 'ruijie')), isNull);
      expect(DeviceVitals.skipReason(_dev(brand: 'cisco', protocol: 'ssh')), isNull);
      expect(DeviceVitals.skipReason(_dev(brand: 'cisco', protocol: 'snmp')), isNotNull);
      expect(DeviceVitals.skipReason(_dev(brand: 'bdcom', model: 'P3600-04', protocol: 'telnet')), isNotNull);
      expect(DeviceVitals.skipReason(_dev(brand: 'bdcom', model: 'S2528-B')), 'لا مقاييس لهذه العلامة',
          reason: 'سويتش BDCOM لا ملخّص أولت له');
    });
  });
}
