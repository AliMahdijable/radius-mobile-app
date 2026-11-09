import 'dart:async';
import 'dart:typed_data';

import 'package:rad_mysvcs/api/snmp_client.dart';
import 'package:rad_mysvcs/core/net/vpn_pipe.dart';

import 'fake_snmp_agent.dart';

/// طلب SNMP v2c كما يرسله [SnmpV2c] على السلك — مفكوكاً من BER: النوع، الرقم، max-repetitions، والـOIDs.
class SnmpWireRequest {
  SnmpWireRequest._(this.community, this.pdu, this.requestId, this.maxRepetitions, this.oids);

  final List<int> community;

  /// 0xA0 GET · 0xA5 GETBULK.
  final int pdu;
  final int requestId;
  final int maxRepetitions;
  final List<String> oids;

  bool get bulk => pdu == 0xA5;

  static SnmpWireRequest parse(Uint8List b) {
    var p = 0;
    int len() {
      final f = b[p++];
      if (f < 0x80) return f;
      var n = 0;
      for (var i = 0; i < (f & 0x7f); i++) {
        n = (n << 8) | b[p++];
      }
      return n;
    }

    int integer() {
      p++; // INTEGER
      final l = len();
      var v = 0;
      for (var i = 0; i < l; i++) {
        v = (v << 8) | b[p + i];
      }
      p += l;
      return v;
    }

    p++; // SEQUENCE
    len();
    integer(); // version
    p++; // OCTET STRING
    final cl = len();
    final community = b.sublist(p, p + cl);
    p += cl;
    final pdu = b[p++];
    len();
    final rid = integer();
    integer(); // error-status · non-repeaters
    final maxRep = integer(); // error-index · max-repetitions
    p++; // SEQUENCE varbinds
    final end = len() + p;
    final oids = <String>[];
    while (p < end) {
      p++; // SEQUENCE varbind
      final vbEnd = len() + p;
      p++; // OID
      final ol = len();
      oids.add(_decodeOid(b.sublist(p, p + ol)));
      p = vbEnd;
    }
    return SnmpWireRequest._(community, pdu, rid, maxRep, oids);
  }

  /// GetResponse بهذه القيم — أو بخطأٍ من الوكيل ([errorStatus]: 5 genErr) بلا قيم.
  Uint8List reply(List<Varbind> vbs, {int errorStatus = 0}) {
    final list = <int>[
      for (final v in vbs) ..._tlv(0x30, [..._tlv(0x06, _encodeOid(v.oid)), ..._tlv(v.rawTag, v.rawBytes)]),
    ];
    final body = [
      ..._tlv(0x02, _uint(requestId)),
      ..._tlv(0x02, _uint(errorStatus)),
      ..._tlv(0x02, _uint(0)),
      ..._tlv(0x30, list),
    ];
    return Uint8List.fromList(_tlv(0x30, [..._tlv(0x02, const [1]), ..._tlv(0x04, community), ..._tlv(0xA2, body)]));
  }

  static List<int> _len(int n) {
    if (n < 0x80) return [n];
    final out = <int>[];
    for (var x = n; x > 0; x >>= 8) {
      out.insert(0, x & 0xff);
    }
    return [0x80 | out.length, ...out];
  }

  static List<int> _tlv(int tag, List<int> v) => [tag, ..._len(v.length), ...v];

  static List<int> _uint(int v) {
    final out = <int>[];
    var x = v;
    do {
      out.insert(0, x & 0xff);
      x >>= 8;
    } while (x > 0);
    if (out.first & 0x80 != 0) out.insert(0, 0);
    return out;
  }

  static List<int> _encodeOid(String oid) {
    final parts = oid.split('.').map(int.parse).toList();
    final out = <int>[parts[0] * 40 + parts[1]];
    for (final v in parts.skip(2)) {
      final buf = <int>[v & 0x7f];
      for (var x = v >> 7; x > 0; x >>= 7) {
        buf.insert(0, (x & 0x7f) | 0x80);
      }
      out.addAll(buf);
    }
    return out;
  }

  static String _decodeOid(List<int> b) {
    final parts = <int>[b[0] ~/ 40, b[0] % 40];
    var v = 0;
    for (final x in b.skip(1)) {
      v = (v << 7) | (x & 0x7f);
      if (x & 0x80 == 0) {
        parts.add(v);
        v = 0;
      }
    }
    return parts.join('.');
  }
}

/// ممرّ الـVPN ([VpnPipe.transport]) يصل وكيلاً في الذاكرة: القارئ يمرّ بعميل [SnmpV2c] الحقيقيّ (walk وتحويل المهلة)
/// لا ببديلٍ يتجاوزه. [lose]: شجراتٌ لا يجيب طلبها (الممرّ ٥٠٤ ⇒ مهلة)، و[refuse]: شجراتٌ يردّ عليها الوكيل بخطأ
/// (genErr — لا يدعمها).
class SnmpWirePipe implements VpnPipeTransport {
  SnmpWirePipe(this.agent, {this.lose = const {}, this.refuse = const {}});

  final FakeSnmpAgent agent;
  final Set<String> lose;
  final Set<String> refuse;

  /// كلّ OID سُئل (مؤشّرات المسوح) — بالترتيب.
  final List<String> asked = [];

  @override
  Future<({Uint8List data, int? ms})> udp(String host, int port, Uint8List data, Duration timeout) async {
    final q = SnmpWireRequest.parse(data);
    asked.addAll(q.oids);
    bool under(Set<String> roots) => q.oids.any((o) => roots.any((r) => o == r || o.startsWith('$r.')));
    if (under(lose)) throw TimeoutException('SNMP عبر الـVPN: الجهاز ما ردّ', timeout);
    if (under(refuse)) return (data: q.reply(const [], errorStatus: 5), ms: 2);
    final vbs = q.bulk ? await agent.getBulkColumns(q.oids, maxRepetitions: q.maxRepetitions) : agent.getSync(q.oids);
    return (data: q.reply(vbs), ms: 2);
  }

  @override
  Future<({String id, int? ms})> open(String host, int port, Duration timeout) => throw UnimplementedError('TCP');

  @override
  Future<bool> write(String id, Uint8List data) => throw UnimplementedError('TCP');

  @override
  Future<PipeRead?> read(String id, Duration wait) => throw UnimplementedError('TCP');

  @override
  Future<void> close(String id) async {}

  @override
  Future<List<int>> ping(String host, int count, Duration timeout) async => const [3];

  @override
  Future<PipeRoute> route() async => const PipeRoute.ok('company');

  @override
  Future<void> release() async {}
}
