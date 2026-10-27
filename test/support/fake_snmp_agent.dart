import 'dart:convert';
import 'dart:typed_data';

import 'package:rad_mysvcs/api/snmp_client.dart';

/// وكيل SNMP في الذاكرة — GET/GETBULK/walk بترتيب الـOID الرقميّ كجهازٍ حقيقيّ. الغائب `noSuchInstance`.
class FakeSnmpAgent extends SnmpV2c {
  /// القيم تُكتب بلا OID (`snmpText('', …)`) والمفتاح هو الـOID — يُعاد كلّ Varbind بمفتاحه كما يردّ جهازٌ حقيقيّ.
  FakeSnmpAgent(Map<String, Varbind> data, {this.failGets = false})
      : _data = {for (final e in data.entries) e.key: Varbind(oid: e.key, rawTag: e.value.rawTag, rawBytes: e.value.rawBytes)},
        super(host: 'fixture') {
    _sorted = _data.keys.toList()..sort(compareOid);
  }

  final Map<String, Varbind> _data;
  late List<String> _sorted;
  final bool failGets;
  final List<List<String>> gets = [];
  int bulkCalls = 0;

  void put(String oid, Varbind vb) {
    _data[oid] = Varbind(oid: oid, rawTag: vb.rawTag, rawBytes: vb.rawBytes);
    _sorted = _data.keys.toList()..sort(compareOid);
  }

  void remove(String oid) {
    _data.remove(oid);
    _sorted = _data.keys.toList()..sort(compareOid);
  }

  static int compareOid(String a, String b) {
    final pa = a.split('.').map(int.parse).toList();
    final pb = b.split('.').map(int.parse).toList();
    for (var i = 0; i < pa.length && i < pb.length; i++) {
      final c = pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    return pa.length.compareTo(pb.length);
  }

  Varbind _absent(String oid) => Varbind(oid: oid, rawTag: 0x81, rawBytes: Uint8List(0));

  List<Varbind> _after(String cursor, int n) {
    final out = <Varbind>[];
    for (final k in _sorted) {
      if (compareOid(k, cursor) > 0) {
        out.add(_data[k]!);
        if (out.length >= n) break;
      }
    }
    return out;
  }

  @override
  Future<List<Varbind>> get(List<String> oids) async {
    gets.add(List.of(oids));
    if (failGets) throw SnmpTimeoutException('fixture timeout');
    return [for (final o in oids) _data[o] ?? _absent(o)];
  }

  @override
  Future<List<Varbind>> getBulk(String baseOid, {int maxRepetitions = 20, int nonRepeaters = 0}) async {
    bulkCalls++;
    final r = _after(baseOid, maxRepetitions);
    return r.isEmpty ? [Varbind(oid: baseOid, rawTag: 0x82, rawBytes: Uint8List(0))] : r;
  }

  @override
  Future<List<Varbind>> getBulkColumns(List<String> cursors, {int maxRepetitions = 25}) async {
    bulkCalls++;
    final cols = [for (final c in cursors) _after(c, maxRepetitions)];
    final out = <Varbind>[];
    for (var i = 0; i < maxRepetitions; i++) {
      for (var c = 0; c < cols.length; c++) {
        out.add(i < cols[c].length ? cols[c][i] : Varbind(oid: cursors[c], rawTag: 0x82, rawBytes: Uint8List(0)));
      }
    }
    return out;
  }

  @override
  Future<List<Varbind>> walk(String baseOid, {int chunkSize = 25, int maxIterations = 100}) async {
    return [
      for (final k in _sorted)
        if (k.startsWith('$baseOid.')) _data[k]!,
    ];
  }
}

Uint8List _intBytes(int v) {
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

Uint8List _uintBytes(int v) {
  final out = <int>[];
  var x = v;
  do {
    out.insert(0, x & 0xff);
    x >>= 8;
  } while (x > 0);
  return Uint8List.fromList(out);
}

Varbind snmpInt(String oid, int v) => Varbind(oid: oid, rawTag: 0x02, rawBytes: _intBytes(v));
Varbind snmpTicks(String oid, int v) => Varbind(oid: oid, rawTag: 0x43, rawBytes: _uintBytes(v));
Varbind snmpGauge(String oid, int v) => Varbind(oid: oid, rawTag: 0x42, rawBytes: _uintBytes(v));
Varbind snmpText(String oid, String s) => Varbind(oid: oid, rawTag: 0x04, rawBytes: Uint8List.fromList(utf8.encode(s)));
Varbind snmpBytes(String oid, List<int> b) => Varbind(oid: oid, rawTag: 0x04, rawBytes: Uint8List.fromList(b));
