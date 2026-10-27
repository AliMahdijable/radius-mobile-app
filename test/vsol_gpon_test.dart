import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/api/vsol_gpon_details.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';

Varbind textVb(String oid, String value) =>
    Varbind(oid: oid, rawTag: 4, rawBytes: Uint8List.fromList(value.codeUnits));
Varbind macVb(int row, int tail) => Varbind(
    oid: '${VsolGponDetails.macOid}.$row',
    rawTag: 4,
    rawBytes: Uint8List.fromList([0x02, 0, 0, 0, 0, tail]));
Varbind portVb(int row, String port) =>
    textVb('${VsolGponDetails.portOid}.$row', port);
List<Varbind> get end => [
      textVb('1.3.6.1.4.1.37950.1.1.5.10.3.2.1.4.1', ''),
      textVb('1.3.6.1.4.1.37950.1.1.5.10.3.3.1.1', '')
    ];

class FakeSnmp extends SnmpV2c {
  FakeSnmp(this.pages, {this.failAt}) : super(host: 'fixture');
  final List<List<Varbind>> pages;
  final int? failAt;
  int calls = 0;
  final cursors = <List<String>>[];
  @override
  Future<List<Varbind>> walk(String baseOid,
          {int chunkSize = 25, int maxIterations = 100}) async =>
      [textVb('${VsolGponDetails.serialOid}.1.1', 'TEST00000001')];
  @override
  Future<List<Varbind>> getBulkColumns(List<String> next,
      {int maxRepetitions = 25}) async {
    cursors.add(List.of(next));
    if (calls == failAt) throw SnmpException('fixture timeout');
    return pages[calls++];
  }
}

void main() {
  VsolIfRow row(int id, String name, {bool up = true}) => VsolIfRow(
      index: id,
      name: name,
      up: up,
      mac: null,
      speedMbps: 1000,
      rxBytes: 100,
      txBytes: 200);

  test('V1600G0B shape: 4 GPON ports, 12 named ONUs, VLANs excluded', () {
    final parsed = VsolParse.build([
      for (var n = 1; n <= 4; n++) row(n, 'GE0/$n'),
      for (var n = 1; n <= 4; n++) row(4 + n, 'GPON0/$n', up: n <= 2),
      for (var n = 1; n <= 4; n++) row(9 + n, 'VLAN${100 * n}'),
      for (var p = 1; p <= 2; p++)
        for (var n = 1; n <= 6; n++)
          row(8 + p * 6 + n, 'GPON0${p}ONU$n Customer $p-$n'),
    ]);
    expect(parsed.uplinks.length, 4);
    expect(parsed.ponPorts.length, 4);
    expect(parsed.onus.length, 12);
    expect(parsed.onusOnline, 12);
    expect(parsed.ponPorts.map((p) => p.onuTotal), [6, 6, 0, 0]);
    expect(parsed.onus.first.label, 'GPON0/1:1');
    expect(parsed.onus.first.name, 'Customer 1-1');
  });

  test('keeps technology and slots separate and sorts numeric IDs', () {
    final b = VsolParse.build([
      row(1, 'GPON1/2'),
      row(2, 'GPON0/2'),
      row(3, 'EPON0/2'),
      row(4, 'GPON1/2:10 Name With Spaces'),
      row(5, 'GPON1/2:2'),
      row(6, 'gpon02onu3 Alias'),
      row(7, 'EPON0/2:1'),
      row(8, 'GPON0/2:4garbage'),
      row(9, 'GPON0/2ONU5'),
    ]);
    expect(b.onus.length, 4);
    expect(b.onus.map((o) => o.label),
        ['EPON0/2:1', 'GPON0/2:3', 'GPON1/2:2', 'GPON1/2:10']);
    expect(b.ponPorts.firstWhere((p) => p.label == 'GPON1/2').onuTotal, 2);
    expect(b.ponPorts.firstWhere((p) => p.label == 'GPON0/2').onuTotal, 1);
  });

  test('GPON metadata survives counter refresh; serial is not a MAC', () {
    final onu = VsolParse.build([row(1, 'GPON01ONU1 Test ONU')])
        .onus
        .single
        .withGponDetails(
            const VsolGponSnapshot({
              '1/1': 'TEST00000001'
            }, {
              '1/1': ['02:00:00:00:00:01']
            }, true),
            DateTime.utc(2026));
    final refreshed = onu.withBytes(200, 300);
    expect(refreshed.name, 'Test ONU');
    expect(refreshed.label, 'GPON0/1:1');
    expect(refreshed.serial, 'TEST00000001');
    expect(refreshed.mac, isNull);
    expect(refreshed.learnedMacs, ['02:00:00:00:00:01']);
    expect(refreshed.learnedMacsComplete, isTrue);
    expect(refreshed.learnedMacsReadAt, DateTime.utc(2026));
    final pon = VsolParse.build([row(2, 'GPON0/1')]).ponPorts.single;
    expect(pon.withBytes(10, 20).withCounts(onuTotal: 1, onuOnline: 1).label,
        'GPON0/1');
  });

  test('GPON uses asymmetric upstream/downstream traffic limits', () {
    VsolOltStats sample(int rx, int tx) => VsolOltStats(ponPorts: [
          VsolPonPort(
              index: 1,
              slot: 0,
              port: 1,
              up: true,
              rxBytes: rx,
              txBytes: tx,
              technology: VsolPonTechnology.gpon),
        ]);
    final rate = VsolTraffic.between(sample(100, 100),
        sample(250000100, 250000100), const Duration(seconds: 1))['GPON0/1']!;
    expect(rate.rxBps, isNull);
    expect(rate.txBps, 2000000000);
  });

  test('rejects zero, broadcast, multicast and malformed MAC addresses', () {
    for (final bytes in [
      List.filled(6, 0),
      List.filled(6, 255),
      [1, 0, 0, 0, 0, 1],
      [2, 0, 0]
    ]) {
      expect(VsolGponDetails.macAddress(bytes), isNull);
    }
    expect(VsolGponDetails.macAddress([2, 1, 2, 3, 4, 5]), '02:01:02:03:04:05');
  });

  test('reads MAC + ONU as paired columns, excludes uplink MACs', () async {
    final fake = FakeSnmp([
      [
        macVb(1, 1),
        portVb(1, 'PON1:ONU1'),
        macVb(2, 2),
        portVb(2, 'GE1'),
        macVb(3, 3),
        portVb(3, 'PON2:ONU6')
      ],
      end,
    ]);
    final data = await VsolGponDetails.fetch(fake);
    expect(data.macsComplete, isTrue);
    expect(data.learnedMacs, {
      '1/1': ['02:00:00:00:00:01'],
      '2/6': ['02:00:00:00:00:03']
    });
    expect(data.serials['1/1'], 'TEST00000001');
    expect(fake.cursors[1],
        ['${VsolGponDetails.macOid}.3', '${VsolGponDetails.portOid}.3']);
  });

  test('never attaches a MAC when the response row indices disagree', () async {
    final data = await VsolGponDetails.fetch(FakeSnmp([
      [macVb(1, 1), portVb(2, 'PON1:ONU1')],
    ]));
    expect(data.macsComplete, isFalse);
    expect(data.learnedMacs, isEmpty);
  });

  test('failed/odd-length reads do not expose a partial MAC table', () async {
    for (final fake in [
      FakeSnmp([
        [macVb(1, 1), portVb(1, 'PON1:ONU1')]
      ], failAt: 1),
      FakeSnmp([
        [macVb(1, 1)]
      ]),
    ]) {
      final data = await VsolGponDetails.fetch(fake);
      expect(data.macsComplete, isFalse);
      expect(data.learnedMacs, isEmpty);
      expect(data.serials, isNotEmpty);
    }
  });

  test('unsupported vendor columns are unavailable, not an empty MAC table',
      () async {
    for (final tag in [0x80, 0x81]) {
      final data = await VsolGponDetails.fetch(FakeSnmp([
        [
          for (final oid in [VsolGponDetails.macOid, VsolGponDetails.portOid])
            Varbind(oid: oid, rawTag: tag, rawBytes: Uint8List(0))
        ],
      ]));
      expect(data.macsComplete, isFalse);
      expect(data.learnedMacs, isEmpty);
    }
  });

  test('cancelled background reads stop without publishing a partial table',
      () async {
    final fake = FakeSnmp([
      [macVb(1, 1), portVb(1, 'PON1:ONU1')],
      end,
    ]);
    final data =
        await VsolGponDetails.fetch(fake, isCancelled: () => fake.calls == 1);
    expect(fake.calls, 1);
    expect(data.macsComplete, isFalse);
    expect(data.learnedMacs, isEmpty);
  });

  test('slow details merge without replacing the latest counter sample', () {
    final now = DateTime.utc(2026);
    final parsed = VsolParse.build([
      row(1, 'GPON0/1'),
      row(2, 'GPON01ONU1 Customer'),
      row(3, 'GPON01ONU2 Offline', up: false),
      row(4, 'GE0/1'),
    ]);
    final stats = VsolOltStats(
        sysName: 'fixture',
        sysDescr: 'V1600G0B',
        uptime: const Duration(hours: 2),
        narrowCounters: true,
        rxAt: now,
        txAt: now.add(const Duration(milliseconds: 200)),
        ponPorts: parsed.ponPorts,
        onus: parsed.onus,
        uplinks: parsed.uplinks);
    final enriched = stats.withGponDetails(
        const VsolGponSnapshot({
          '1/1': 'TEST00000001'
        }, {
          '1/1': ['02:00:00:00:00:01'],
          '1/2': ['02:00:00:00:00:02']
        }, true),
        now);
    expect(enriched.rxAt, stats.rxAt);
    expect(enriched.txAt, stats.txAt);
    expect(enriched.narrowCounters, isTrue);
    expect(enriched.sysName, stats.sysName);
    expect(enriched.sysDescr, stats.sysDescr);
    expect(enriched.uptime, stats.uptime);
    expect(enriched.ponPorts, same(stats.ponPorts));
    expect(enriched.uplinks, same(stats.uplinks));
    expect(enriched.onus.first.rxBytes, 100);
    expect(enriched.onus.first.txBytes, 200);
    expect(enriched.onus.first.learnedMacs, ['02:00:00:00:00:01']);
    expect(enriched.onus.last.learnedMacs, isEmpty);
    final failed =
        enriched.withGponDetails(const VsolGponSnapshot({}, {}, false), now);
    expect(failed.onus.first.learnedMacs, isEmpty);
    expect(failed.onus.first.learnedMacsComplete, isFalse);
  });

  test('a moving MAC is not assigned to either ONU; repeats deduplicate',
      () async {
    final data = await VsolGponDetails.fetch(FakeSnmp([
      [
        macVb(1, 1),
        portVb(1, 'PON1:ONU1'),
        macVb(2, 2),
        portVb(2, 'PON1:ONU2')
      ],
      [
        macVb(3, 1),
        portVb(3, 'PON2:ONU1'),
        macVb(4, 2),
        portVb(4, 'PON1:ONU2')
      ],
      end,
    ]));
    expect(data.macsComplete, isTrue);
    expect(data.learnedMacs, {
      '1/2': ['02:00:00:00:00:02']
    });
  });

  test('منفذ جدول الماك ⇒ «منفذ/جهاز»: GPON «PON1:ONU5» وEPON V1600D «EPON01ONU1» و«EPON0/1:12»', () {
    expect(VsolGponDetails.portKey('PON1:ONU5'), '1/5');
    expect(VsolGponDetails.portKey('EPON01ONU1'), '1/1');
    expect(VsolGponDetails.portKey('EPON08ONU42'), '8/42');
    expect(VsolGponDetails.portKey('EPON0/1:12'), '1/12');
    expect(VsolGponDetails.portKey('GE0/1'), isNull);
    expect(VsolGponDetails.portKey('EPON00ONU3'), isNull, reason: 'لا منفذ صفر');
  });
}
