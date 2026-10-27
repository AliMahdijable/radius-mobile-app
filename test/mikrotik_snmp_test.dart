import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/mikrotik_snmp.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';

/// ميكروتك عبر SNMP — الأرقام من MIKROTIK-MIB الرسميّ (REVISION 2026-07-07). القيم هنا بالوسوم التي يُرسلها
/// الجهاز فعلاً (INTEGER موقَّع · Gauge32 · Counter64 · TimeTicks · OCTET STRING).
Uint8List _signed(int v) {
  final out = <int>[];
  var x = v;
  while (true) {
    out.insert(0, x & 0xff);
    final rest = x >> 8;
    final signBit = (x & 0x80) != 0;
    if ((rest == 0 && !signBit) || (rest == -1 && signBit)) break;
    x = rest;
  }
  return Uint8List.fromList(out);
}

Uint8List _unsigned(int v) {
  final out = <int>[];
  var x = v;
  do {
    out.insert(0, x & 0xff);
    x >>= 8;
  } while (x > 0);
  return Uint8List.fromList(out);
}

MapEntry<String, Varbind> i(String oid, int v) => MapEntry(oid, Varbind(oid: oid, rawTag: 0x02, rawBytes: _signed(v)));
MapEntry<String, Varbind> g(String oid, int v) => MapEntry(oid, Varbind(oid: oid, rawTag: 0x42, rawBytes: _unsigned(v)));
MapEntry<String, Varbind> c64(String oid, int v) => MapEntry(oid, Varbind(oid: oid, rawTag: 0x46, rawBytes: _unsigned(v)));
MapEntry<String, Varbind> t(String oid, int v) => MapEntry(oid, Varbind(oid: oid, rawTag: 0x43, rawBytes: _unsigned(v)));
MapEntry<String, Varbind> s(String oid, String v) =>
    MapEntry(oid, Varbind(oid: oid, rawTag: 0x04, rawBytes: Uint8List.fromList(utf8.encode(v))));
MapEntry<String, Varbind> mac(String oid, List<int> b) =>
    MapEntry(oid, Varbind(oid: oid, rawTag: 0x04, rawBytes: Uint8List.fromList(b)));

/// LHG 60G (محطّة) بـRouterOS 7 + ثلاث جلسات PPPoE ديناميكيّة.
Map<String, Varbind> _lhg() => Map.fromEntries([
      s(MikrotikSnmp.sysDescr, 'RouterOS LHG 60G'),
      t(MikrotikSnmp.sysUpTime, (3 * 86400 + 4 * 3600 + 5 * 60) * 100),
      s(MikrotikSnmp.boardName, 'LHG 60G'),
      s(MikrotikSnmp.licVersion, '7.15.3'),
      i(MikrotikSnmp.hlTemperature, 470), // 47.0 °C — يتقدّمه جدول المقاييس
      i(MikrotikSnmp.hlVoltage, 241), // 24.1 V
      i(MikrotikSnmp.hlCpuFrequency, 716),
      i('${MikrotikSnmp.hrProcessorLoad}.1', 10),
      i('${MikrotikSnmp.hrProcessorLoad}.2', 20),
      s('${MikrotikSnmp.hrStorageEntry}.3.65536', 'main memory'),
      i('${MikrotikSnmp.hrStorageEntry}.4.65536', 1024),
      i('${MikrotikSnmp.hrStorageEntry}.5.65536', 262144), // 256 MiB
      i('${MikrotikSnmp.hrStorageEntry}.6.65536', 65536), // 64 MiB مستعملة
      s('${MikrotikSnmp.gaugeEntry}.2.1', 'cpu-temperature'),
      i('${MikrotikSnmp.gaugeEntry}.3.1', 52),
      i('${MikrotikSnmp.gaugeEntry}.4.1', 1),
      s('${MikrotikSnmp.gaugeEntry}.2.2', 'fan1-speed'),
      i('${MikrotikSnmp.gaugeEntry}.3.2', 4100),
      i('${MikrotikSnmp.gaugeEntry}.4.2', 2),
      // المنافذ
      s('${MikrotikSnmp.ifName}.1', 'ether1'),
      i('${MikrotikSnmp.ifType}.1', 6),
      i('${MikrotikSnmp.ifAdmin}.1', 1),
      i('${MikrotikSnmp.ifOper}.1', 1),
      c64('${MikrotikSnmp.ifHcIn}.1', 123456789012),
      c64('${MikrotikSnmp.ifHcOut}.1', 98765),
      g('${MikrotikSnmp.ifHighSpeed}.1', 1000),
      s('${MikrotikSnmp.ifName}.2', 'sfp1'),
      i('${MikrotikSnmp.ifType}.2', 6),
      i('${MikrotikSnmp.ifAdmin}.2', 1),
      i('${MikrotikSnmp.ifOper}.2', 2),
      g('${MikrotikSnmp.ifHighSpeed}.2', 10000),
      s('${MikrotikSnmp.ifName}.3', 'wlan60-1'),
      i('${MikrotikSnmp.ifType}.3', 6),
      i('${MikrotikSnmp.ifAdmin}.3', 1),
      i('${MikrotikSnmp.ifOper}.3', 1),
      s('${MikrotikSnmp.ifName}.4', 'bridge'),
      i('${MikrotikSnmp.ifType}.4', 209),
      i('${MikrotikSnmp.ifAdmin}.4', 1),
      i('${MikrotikSnmp.ifOper}.4', 1),
      for (final n in [10, 11, 12]) ...[
        s('${MikrotikSnmp.ifName}.$n', '<pppoe-user$n>'),
        i('${MikrotikSnmp.ifType}.$n', 23),
        i('${MikrotikSnmp.ifOper}.$n', 1),
      ],
      // 60 GHz — station-bridge متّصلة
      i('${MikrotikSnmp.w60gEntry}.2.3', 1),
      s('${MikrotikSnmp.w60gEntry}.3.3', 'tower-60'),
      i('${MikrotikSnmp.w60gEntry}.4.3', 1),
      mac('${MikrotikSnmp.w60gEntry}.5.3', [0x00, 0x11, 0x22, 0x33, 0x44, 0x55]),
      i('${MikrotikSnmp.w60gEntry}.6.3', 60480),
      i('${MikrotikSnmp.w60gEntry}.7.3', 8),
      i('${MikrotikSnmp.w60gEntry}.8.3', 80),
      i('${MikrotikSnmp.w60gEntry}.9.3', 28),
      s('${MikrotikSnmp.w60gEntry}.11.3', 'center'),
      i('${MikrotikSnmp.w60gEntry}.12.3', -55),
      g('${MikrotikSnmp.w60gEntry}.13.3', 2310),
    ]);

void main() {
  group('LHG 60G عبر SNMP', () {
    final st = MikrotikSnmp.build(_lhg());

    test('الهويّة والمعالج والذاكرة والمدّة', () {
      expect(st.via, 'SNMP');
      expect(st.boardName, 'LHG 60G');
      expect(st.version, '7.15.3');
      expect(st.cpuLoad, 15, reason: 'متوسّط النواتين');
      expect(st.cpuCount, 2);
      expect(st.memTotalBytes, 268435456);
      expect(st.memUsedPercent, 25);
      expect(st.uptime, '3d4h5m');
      expect(st.cpuFrequencyMhz, 716);
    });

    test('الصحّة: جدول المقاييس أوّلاً (°C صحيحة)، والفولت بأعشاره، والمراوح', () {
      expect(st.temperature, 52, reason: 'لا 47 من القيمة المفردة');
      expect(st.voltage, 24.1);
      expect(st.fans.single.intValue, 4100);
    });

    test('المنافذ: سرعة الموصول وحده، وجلسات PPP تُعدّ ولا تُسرد', () {
      final eth = st.interfaces.firstWhere((x) => x.name == 'ether1');
      expect(eth.type, 'ether');
      expect(eth.rxBytes, 123456789012, reason: 'Counter64 — لا التفاف ٣٢-بت');
      expect(eth.linkSpeed, '1Gbps');
      final sfp = st.interfaces.firstWhere((x) => x.name == 'sfp1');
      expect(sfp.type, 'sfp');
      expect(sfp.running, isFalse);
      expect(sfp.linkSpeed, isNull, reason: 'مفصولٌ ⇒ لا سرعة');
      expect(st.interfaces.firstWhere((x) => x.name == 'bridge').type, 'bridge');
      expect(st.interfaces.firstWhere((x) => x.name == 'wlan60-1').type, 'w60g');
      expect(st.interfaces.where((x) => x.name.startsWith('<pppoe')), isEmpty);
      expect(st.pppActiveCount, 3);
    });

    test('🚨 وصلة الـ60: RSSI بالـdBm والجودة بالمئة والسرعة والقطاع والطرف الآخر', () {
      final w = st.wirelessInterfaces.single;
      expect(w.name, 'wlan60-1');
      expect(w.mode, 'station-bridge');
      expect(w.is60g, isTrue);
      expect(w.frequency, 60480);
      final l = st.w60gLinks.single;
      expect(l.connected, isTrue);
      expect(l.rssi, -55);
      expect(l.signalPercent, 80);
      expect(l.phyRateMbps, 2310);
      expect(l.mcs, 8);
      expect(l.sectorText, '28 · center');
      expect(l.remoteMac, '00:11:22:33:44:55');
      expect(l.distanceMeters, isNull, reason: 'المسافة في جدول المحطّات وحده');
      expect(st.isAccessPoint, isFalse);
    });

    test('الخفيف لا يقرأ اللاسلكيّ', () {
      final light = MikrotikSnmp.build(_lhg(), vitalsOnly: true);
      expect(light.wirelessInterfaces, isEmpty);
      expect(light.cpuLoad, 15);
    });
  });

  group('نقطة وصول 5 GHz عبر SNMP', () {
    test('جدول التسجيل: الماك من الفهرس، والإشارتان والسرعة بالميغا والمدّة بالثواني', () {
      const rt = MikrotikSnmp.wlRtabEntry;
      const idx = '220.44.110.1.2.3.5'; // DC:2C:6E:01:02:03 على ifIndex 5
      final all = Map.fromEntries([
        s(MikrotikSnmp.sysDescr, 'RouterOS RB921GS-5HPacD r2'),
        s('${MikrotikSnmp.ifName}.5', 'wlan1'),
        i('${MikrotikSnmp.ifType}.5', 71),
        i('${MikrotikSnmp.ifOper}.5', 1),
        s('${MikrotikSnmp.wlApEntry}.4.5', 'sector-1'),
        i('${MikrotikSnmp.wlApEntry}.7.5', 5180),
        s('${MikrotikSnmp.wlApEntry}.8.5', '5ghz-a/n/ac'),
        i('$rt.3.$idx', -63),
        i('$rt.19.$idx', -60),
        i('$rt.12.$idx', 34),
        g('$rt.8.$idx', 270000000),
        g('$rt.9.$idx', 216000000),
        t('$rt.11.$idx', 360000),
        s('$rt.20.$idx', 'home-ap'),
      ]);
      final st = MikrotikSnmp.build(all);
      expect(st.boardName, 'RB921GS-5HPacD r2', reason: 'بلا mtxrBoardName ⇒ من sysDescr');
      final w = st.wirelessInterfaces.single;
      expect(w.mode, 'ap-bridge');
      expect(w.frequency, 5180);
      expect(st.isAccessPoint, isTrue);
      final c = st.wirelessClients.single;
      expect(c.mac, 'DC:2C:6E:01:02:03');
      expect(c.iface, 'wlan1');
      expect(c.signalStrength, -63);
      expect(c.txSignalStrength, -60);
      expect(c.signalToNoise, 34);
      expect(c.txRate, 270);
      expect(c.rxRate, 216);
      expect(c.uptime, 3600);
      expect(c.hostname, 'home-ap');
    });
  });

  test('🚨 SwOS (CSS610 حيّاً ٢٧ أكتوبر): بلا معالجٍ ولا ذاكرة ⇒ «—» لا 0٪، والطراز بلا «SwOS v2.21»، والحرارة 52.0', () {
    final st = MikrotikSnmp.build(Map.fromEntries([
      s(MikrotikSnmp.sysDescr, 'CSS610-1Gi-7R-2S+ SwOS v2.21'),
      t(MikrotikSnmp.sysUpTime, 124543614),
      s(MikrotikSnmp.firmwareVersion, '2.21'),
      i('${MikrotikSnmp.gaugeEntry}.3.52.0', 41),
      s('${MikrotikSnmp.ifName}.1', 'Port1'),
      i('${MikrotikSnmp.ifType}.1', 6),
      i('${MikrotikSnmp.ifOper}.1', 1),
      g('${MikrotikSnmp.ifHighSpeed}.1', 1000),
    ]));
    expect(st.boardName, 'CSS610-1Gi-7R-2S+');
    expect(st.version, 'SwOS 2.21');
    expect(st.cpuKnown, isFalse);
    expect(st.memKnown, isFalse);
    expect(st.temperature, 41);
    expect(st.interfaces.single.linkSpeed, '1Gbps');
    expect(st.uptime, '2w9h57m16s', reason: '124543614 tick = 1245436 ثانية');
  });

  test('RouterOS عبر SNMP: المعالج والذاكرة مقروءان', () {
    final st = MikrotikSnmp.build(_lhg());
    expect(st.cpuKnown, isTrue);
    expect(st.memKnown, isTrue);
  });

  test('الصيغ: السرعة كـethernet monitor، والمدّة كـRouterOS', () {
    expect(MikrotikSnmp.speedText(100), '100Mbps');
    expect(MikrotikSnmp.speedText(1000), '1Gbps');
    expect(MikrotikSnmp.speedText(2500), '2.5Gbps');
    expect(MikrotikSnmp.uptimeText(0), '0s');
    expect(MikrotikSnmp.uptimeText(8 * 86400 + 61), '1w1d1m1s');
  });

  test('ردٌّ فارغ لا يرمي ولا يخترع', () {
    final st = MikrotikSnmp.build(const {});
    expect(st.cpuLoad, 0);
    expect(st.temperature, isNull);
    expect(st.memTotalBytes, 0);
    expect(st.interfaces, isEmpty);
    expect(st.w60gLinks, isEmpty);
  });
}
