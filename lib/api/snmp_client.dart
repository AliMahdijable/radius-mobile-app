import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// **SNMP v2c client خفيف** — pure Dart، بدون تبعيّات خارجيّة.
///
/// **لماذا داخلي بدل مكتبة**: كل مكتبات SNMP على pub.dev قديمة (Dart 2.x)
/// وغير مصانة. البروتوكول بسيط (BER over UDP) و ~300 سطر يكفي لكل احتياجاتنا.
///
/// **يدعم**: GET + GETBULK (v2c) — كافٍ للـMimosa (scalar OIDs + client table).
/// **لا يدعم**: v3 (auth/priv)، SET (لا نحتاجه لأننا قارئ فقط)، MIB parsing.
///
/// **الاستعمال**:
/// ```dart
/// final snmp = SnmpV2c(host: '192.168.1.1', community: 'public');
/// final result = await snmp.get(['1.3.6.1.2.1.1.5.0']);
/// print(result.first.value); // hostname
/// ```
class SnmpV2c {
  final String host;
  final int port;
  final String community;
  final Duration timeout;

  static int _requestIdCounter = 1;

  SnmpV2c({
    required this.host,
    this.port = 161,
    this.community = 'public',
    this.timeout = const Duration(seconds: 4),
  });

  /// GET request — يجلب قيمة واحدة أو أكثر من scalar OIDs.
  Future<List<Varbind>> get(List<String> oids) async {
    if (oids.isEmpty) return const [];
    final requestId = _nextRequestId();
    final packet = _buildRequest(
      pduType: _pduGetRequest,
      requestId: requestId,
      oids: oids,
    );
    final response = await _send(packet);
    return _parseResponse(response, expectedRequestId: requestId);
  }

  /// GETBULK — لجلب صفوف الجدول (client table). يبدأ من baseOid ويرجع
  /// آخر [maxRepetitions] OIDs بعده. يُستخدم للـtables (خصوصاً Mimosa
  /// PtMP client info).
  Future<List<Varbind>> getBulk(
    String baseOid, {
    int maxRepetitions = 20,
    int nonRepeaters = 0,
  }) async {
    final requestId = _nextRequestId();
    final packet = _buildRequest(
      pduType: _pduGetBulkRequest,
      requestId: requestId,
      oids: [baseOid],
      errorStatus: nonRepeaters, // في GETBULK: non-repeaters
      errorIndex: maxRepetitions, // في GETBULK: max-repetitions
    );
    final response = await _send(packet);
    return _parseResponse(response, expectedRequestId: requestId);
  }

  /// Walk — يجلب كل الـOIDs تحت baseOid عبر GETBULK متكرّر.
  /// يتوقّف لمّا OID المرجع يخرج من subtree الـbaseOid.
  Future<List<Varbind>> walk(
    String baseOid, {
    int chunkSize = 25,
    int maxIterations = 100,
  }) async {
    final all = <Varbind>[];
    String cursor = baseOid;
    for (int i = 0; i < maxIterations; i++) {
      final chunk = await getBulk(cursor, maxRepetitions: chunkSize);
      if (chunk.isEmpty) break;
      // نُبقي فقط الـOIDs الي تحت baseOid — البقيّة (من subtree التالي) نتجاهلها
      bool outOfSubtree = false;
      for (final vb in chunk) {
        if (!vb.oid.startsWith('$baseOid.') && vb.oid != baseOid) {
          outOfSubtree = true;
          break;
        }
        all.add(vb);
      }
      if (outOfSubtree) break;
      // لو الـchunk انتهى بـend-of-view (Null tag = 0x82 مثلاً) نوقف
      cursor = chunk.last.oid;
    }
    return all;
  }

  // ═══════════════════════════════════════════════════════════
  // Internal — UDP send/receive
  // ═══════════════════════════════════════════════════════════

  Future<Uint8List> _send(Uint8List packet) async {
    RawDatagramSocket? socket;
    StreamSubscription? sub;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final addr = InternetAddress.tryParse(host) ??
          (await InternetAddress.lookup(host)).first;
      socket.send(packet, addr, port);

      final completer = Completer<Uint8List>();
      sub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket!.receive();
          if (dg != null && !completer.isCompleted) {
            completer.complete(dg.data);
          }
        }
      }, onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }, cancelOnError: true);

      return await completer.future.timeout(timeout, onTimeout: () {
        throw SnmpTimeoutException(
            'SNMP timeout بعد ${timeout.inSeconds}s — $host:$port. '
            'تحقّق: community="$community"، SNMP مفعّل على الجهاز، الـport مفتوح.');
      });
    } finally {
      // 2026-08-28 (Google 2027 audit): subscription كان يُلغى فقط في
      // success branch — timeout/onError كانا يتركانه معلّقاً (leak
      // على كل poll لأي جهاز غير متجاوب). الآن unconditional cancel.
      try {
        await sub?.cancel();
      } catch (_) {}
      socket?.close();
    }
  }

  static int _nextRequestId() {
    _requestIdCounter = (_requestIdCounter + 1) & 0x7FFFFFFF;
    if (_requestIdCounter == 0) _requestIdCounter = 1;
    return _requestIdCounter;
  }

  // ═══════════════════════════════════════════════════════════
  // BER encoding — request builder
  // ═══════════════════════════════════════════════════════════

  static const int _pduGetRequest = 0xA0;
  static const int _pduGetBulkRequest = 0xA5;
  static const int _pduGetResponse = 0xA2;

  static const int _tagInteger = 0x02;
  static const int _tagOctetString = 0x04;
  static const int _tagNull = 0x05;
  static const int _tagOid = 0x06;
  static const int _tagSequence = 0x30;

  /// يبني حزمة SNMP v2c كاملة (SEQUENCE (version, community, PDU (...)))
  Uint8List _buildRequest({
    required int pduType,
    required int requestId,
    required List<String> oids,
    int errorStatus = 0,
    int errorIndex = 0,
  }) {
    // varbinds: SEQUENCE of SEQUENCE (OID, NULL)
    final varbindsList = <int>[];
    for (final oid in oids) {
      final oidBytes = _encodeOid(oid);
      final vb = <int>[
        ..._tlv(_tagOid, oidBytes),
        ..._tlv(_tagNull, const []),
      ];
      varbindsList.addAll(_tlv(_tagSequence, vb));
    }
    final varbinds = _tlv(_tagSequence, varbindsList);

    // PDU: request-id, error-status/non-repeaters, error-index/max-reps, varbinds
    final pdu = <int>[
      ..._tlv(_tagInteger, _encodeInt(requestId)),
      ..._tlv(_tagInteger, _encodeInt(errorStatus)),
      ..._tlv(_tagInteger, _encodeInt(errorIndex)),
      ...varbinds,
    ];
    final pduBytes = _tlv(pduType, pdu);

    // Message: version=1 (v2c), community, pdu
    final msg = <int>[
      ..._tlv(_tagInteger,
          _encodeInt(1)), // v2c = version 1 (0-indexed: v1=0, v2c=1)
      ..._tlv(_tagOctetString, community.codeUnits),
      ...pduBytes,
    ];

    return Uint8List.fromList(_tlv(_tagSequence, msg));
  }

  /// TLV: tag + length + value (BER)
  List<int> _tlv(int tag, List<int> value) {
    return [tag, ..._encodeLength(value.length), ...value];
  }

  /// BER length: short form (<128) أو long form (0x80 + n بايت big-endian)
  List<int> _encodeLength(int len) {
    if (len < 128) return [len];
    final bytes = <int>[];
    int n = len;
    while (n > 0) {
      bytes.insert(0, n & 0xFF);
      n >>= 8;
    }
    return [0x80 | bytes.length, ...bytes];
  }

  /// BER integer (signed) — أضف leading 0x00 لو الـMSB set لمنع سالب.
  List<int> _encodeInt(int v) {
    if (v == 0) return [0x00];
    final bytes = <int>[];
    int n = v.abs();
    while (n > 0) {
      bytes.insert(0, n & 0xFF);
      n >>= 8;
    }
    if (v > 0 && (bytes[0] & 0x80) != 0) bytes.insert(0, 0x00);
    if (v < 0) {
      // two's complement encoding for negative
      // (Mimosa OIDs don't need negative request IDs, but keep it correct)
      // ~n + 1 in variable-length representation. Simple hack for typical
      // range — we don't use negative in this file.
      throw UnimplementedError(
          'negative int not supported in this minimal encoder');
    }
    return bytes;
  }

  /// OID → bytes (base-128 encoding). First byte = 40*a + b.
  List<int> _encodeOid(String oid) {
    final parts = oid.split('.').map(int.parse).toList();
    if (parts.length < 2) {
      throw ArgumentError('OID must have ≥2 components: $oid');
    }
    final bytes = <int>[parts[0] * 40 + parts[1]];
    for (int i = 2; i < parts.length; i++) {
      bytes.addAll(_encodeBase128(parts[i]));
    }
    return bytes;
  }

  List<int> _encodeBase128(int v) {
    if (v < 128) return [v];
    final buf = <int>[];
    while (v > 0) {
      buf.insert(0, v & 0x7F);
      v >>= 7;
    }
    // set high bit on all but last
    for (int i = 0; i < buf.length - 1; i++) {
      buf[i] |= 0x80;
    }
    return buf;
  }

  // ═══════════════════════════════════════════════════════════
  // BER decoding — response parser
  // ═══════════════════════════════════════════════════════════

  List<Varbind> _parseResponse(Uint8List data, {int? expectedRequestId}) {
    final r = _Reader(data);
    r.expect(_tagSequence);
    r.readLength();

    // version
    r.expect(_tagInteger);
    final vLen = r.readLength();
    r.pos += vLen;

    // community
    r.expect(_tagOctetString);
    final cLen = r.readLength();
    r.pos += cLen;

    // PDU
    final pduTag = r.data[r.pos++];
    if (pduTag != _pduGetResponse) {
      throw SnmpException('غير متوقّع: PDU tag = 0x${pduTag.toRadixString(16)} '
          '(المتوقّع 0xA2 GetResponse)');
    }
    r.readLength();

    // request-id
    r.expect(_tagInteger);
    final ridLen = r.readLength();
    final rid = _readIntBytes(r.data, r.pos, ridLen);
    r.pos += ridLen;
    if (expectedRequestId != null && rid != expectedRequestId) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ SNMP request-id mismatch: expected=$expectedRequestId got=$rid');
      }
    }

    // error-status
    r.expect(_tagInteger);
    final esLen = r.readLength();
    final errStatus = _readIntBytes(r.data, r.pos, esLen);
    r.pos += esLen;

    // error-index
    r.expect(_tagInteger);
    final eiLen = r.readLength();
    r.pos += eiLen;

    if (errStatus != 0) {
      throw SnmpException(
          'SNMP error-status=$errStatus (${_errorText(errStatus)})');
    }

    // varbinds SEQUENCE
    r.expect(_tagSequence);
    final vbListLen = r.readLength();
    final vbEnd = r.pos + vbListLen;

    final result = <Varbind>[];
    while (r.pos < vbEnd) {
      r.expect(_tagSequence);
      final vbLen = r.readLength();
      final vbEnd2 = r.pos + vbLen;

      // OID
      r.expect(_tagOid);
      final oidLen = r.readLength();
      final oid = _decodeOid(r.data.sublist(r.pos, r.pos + oidLen));
      r.pos += oidLen;

      // value (any tag)
      final valueTag = r.data[r.pos++];
      final valueLen = r.readLength();
      final valueBytes = r.data.sublist(r.pos, r.pos + valueLen);
      r.pos += valueLen;

      result.add(Varbind(
        oid: oid,
        rawTag: valueTag,
        rawBytes: valueBytes,
      ));

      r.pos = vbEnd2; // safety
    }

    return result;
  }

  static String _decodeOid(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final parts = <int>[bytes[0] ~/ 40, bytes[0] % 40];
    int i = 1;
    while (i < bytes.length) {
      int v = 0;
      while (i < bytes.length && (bytes[i] & 0x80) != 0) {
        v = (v << 7) | (bytes[i] & 0x7F);
        i++;
      }
      if (i < bytes.length) {
        v = (v << 7) | bytes[i];
        i++;
      }
      parts.add(v);
    }
    return parts.join('.');
  }

  static int _readIntBytes(Uint8List data, int start, int len) {
    if (len == 0) return 0;
    int v = 0;
    final signBit = (data[start] & 0x80) != 0;
    for (int i = 0; i < len; i++) {
      v = (v << 8) | data[start + i];
    }
    if (signBit && len < 8) {
      v -= 1 << (len * 8);
    }
    return v;
  }

  static String _errorText(int status) {
    switch (status) {
      case 1:
        return 'tooBig — الحزمة كبيرة جدّاً';
      case 2:
        return 'noSuchName — OID غير موجود';
      case 3:
        return 'badValue';
      case 5:
        return 'genErr — خطأ عام';
      default:
        return 'unknown';
    }
  }
}

// ═══════════════════════════════════════════════════════════
// Varbind — نتيجة SNMP (OID + قيمة مُترجَمة)
// ═══════════════════════════════════════════════════════════

class Varbind {
  final String oid;
  final int rawTag;
  final Uint8List rawBytes;

  Varbind({required this.oid, required this.rawTag, required this.rawBytes});

  /// هل ردّ الجهاز بأنّ هذا الـOID **غير موجود** عنده؟
  ///
  /// 🐛 عطلٌ صامت (٢٠٢٦-٠٩-٠٢): `asInt` يعيد صفراً لأيّ وسمٍ مجهول،
  /// بما فيه هذه الوسوم الثلاثة. فكان «الـOID غير موجود» يظهر في
  /// السجلّ وفي الواجهة رقماً صفراً لا يُميَّز عن قيمةٍ حقيقيّة —
  /// وضاعت أشهرٌ من قراءة أصفارٍ تُظنّ بيانات.
  ///
  /// 0x80 noSuchObject · 0x81 noSuchInstance · 0x82 endOfMibView
  bool get isAbsent => rawTag == 0x80 || rawTag == 0x81 || rawTag == 0x82;

  /// `null` حين يكون الـOID غائباً — لتُميّز الشاشة «لا يدعمه الجهاز»
  /// عن «القيمة صفر».
  int? get asIntOrNull => isAbsent ? null : asInt;

  /// القيمة كنص — يعمل مع OctetString + OID + IpAddress.
  String get asString {
    if (isAbsent) return '<غير موجود>';
    switch (rawTag) {
      case 0x04: // OCTET STRING
        return String.fromCharCodes(rawBytes);
      case 0x06: // OID
        return SnmpV2c._decodeOid(rawBytes);
      case 0x40: // IpAddress (4 bytes)
        if (rawBytes.length == 4) {
          return '${rawBytes[0]}.${rawBytes[1]}.${rawBytes[2]}.${rawBytes[3]}';
        }
        return rawBytes.join('.');
      default:
        return asInt.toString();
    }
  }

  /// القيمة كعدد صحيح — يعمل مع INTEGER / Counter32 / Gauge32 / TimeTicks / Counter64.
  int get asInt {
    switch (rawTag) {
      case 0x02: // INTEGER (signed)
        return SnmpV2c._readIntBytes(rawBytes, 0, rawBytes.length);
      case 0x41: // Counter32
      case 0x42: // Gauge32 / Unsigned32
      case 0x43: // TimeTicks
      case 0x46: // Counter64
        int v = 0;
        for (final b in rawBytes) {
          v = (v << 8) | b;
        }
        return v;
      default:
        return 0;
    }
  }

  /// MAC address (OCTET STRING 6 bytes)
  String? get asMac {
    if (rawTag != 0x04 || rawBytes.length != 6) return null;
    return rawBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
  }

  /// hex dump للـdebug
  String get asHex {
    return rawBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  /// end-of-mib-view (SNMPv2 exception) — tag = 0x82
  bool get isEndOfMibView => rawTag == 0x82;
  bool get isNoSuchObject => rawTag == 0x80;
  bool get isNoSuchInstance => rawTag == 0x81;

  @override
  String toString() =>
      'Varbind($oid, tag=0x${rawTag.toRadixString(16)}, value=$asString)';
}

class _Reader {
  final Uint8List data;
  int pos = 0;
  _Reader(this.data);

  void expect(int tag) {
    if (pos >= data.length) {
      throw SnmpException('SNMP response truncated');
    }
    final got = data[pos++];
    if (got != tag) {
      throw SnmpException(
          'BER expected tag 0x${tag.toRadixString(16)} got 0x${got.toRadixString(16)} at pos ${pos - 1}');
    }
  }

  int readLength() {
    if (pos >= data.length) throw SnmpException('BER length truncated');
    final first = data[pos++];
    if (first < 128) return first;
    final n = first & 0x7F;
    if (n == 0 || n > 4) {
      throw SnmpException('BER unsupported length form: $n bytes');
    }
    int len = 0;
    for (int i = 0; i < n; i++) {
      len = (len << 8) | data[pos++];
    }
    return len;
  }
}

// ═══════════════════════════════════════════════════════════
// Exceptions
// ═══════════════════════════════════════════════════════════

class SnmpException implements Exception {
  final String message;
  SnmpException(this.message);
  @override
  String toString() => message;
}

class SnmpTimeoutException extends SnmpException {
  SnmpTimeoutException(super.msg);
}
