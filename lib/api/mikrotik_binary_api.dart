import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Mikrotik RouterOS Binary API client (port 8728/8729).
/// بروتوكول ثنائي رسمي من Mikrotik يعمل مع RouterOS 3.x → 7.x.
///
/// المرجع: https://help.mikrotik.com/docs/display/ROS/API
///
/// **متطلّبات**:
/// - على الراوتر: `/ip service enable api` (البورت 8728 افتراضي)
/// - مستخدم بصلاحيّة `read` كافية
class MikrotikBinaryClient {
  final String host;
  final int port;
  final String user;
  final String pass;
  final Duration timeout;

  Socket? _socket;
  final _receivedBytes = <int>[];
  StreamSubscription<Uint8List>? _sub;

  MikrotikBinaryClient({
    required this.host,
    this.port = 8728,
    required this.user,
    required this.pass,
    this.timeout = const Duration(seconds: 6),
  });

  Future<void> connect() async {
    _socket = await Socket.connect(host, port, timeout: timeout);
    _sub = _socket!.listen(
      (data) => _receivedBytes.addAll(data),
      onError: (e) {
        if (kDebugMode) debugPrint('❌ Mikrotik socket error: $e');
      },
    );
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    _socket?.destroy();
    _socket = null;
  }

  /// Login — RouterOS 6.43+ يقبل plain login (اسم + password في نفس sentence).
  /// الإصدارات القديمة (<6.43) تحتاج challenge-response (لم نُدعمها هنا،
  /// من النادر جداً أن يكون الراوتر أقدم من ذلك في 2026).
  Future<void> login() async {
    final sentence = ['/login', '=name=$user', '=password=$pass'];
    await _writeSentence(sentence);
    final reply = await _readSentence();
    // نجاح: !done. فشل: !trap =message=...
    if (reply.isEmpty || reply.first != '!done') {
      final err = reply.firstWhere((w) => w.startsWith('=message='),
          orElse: () => '=message=login failed');
      throw MikrotikBinaryException(
        err.substring('=message='.length),
        code: reply.first == '!trap' ? 'auth' : null,
      );
    }
  }

  /// إرسال command واستقبال كل الـreplies حتى !done أو !trap
  Future<List<Map<String, String>>> query(List<String> command) async {
    await _writeSentence(command);
    final results = <Map<String, String>>[];
    while (true) {
      final sentence = await _readSentence();
      if (sentence.isEmpty) continue;
      final tag = sentence.first;
      if (tag == '!re') {
        results.add(_sentenceToMap(sentence));
      } else if (tag == '!done') {
        break;
      } else if (tag == '!trap') {
        final err = sentence.firstWhere((w) => w.startsWith('=message='),
            orElse: () => '=message=unknown error');
        throw MikrotikBinaryException(err.substring('=message='.length));
      }
    }
    return results;
  }

  // ═══════════════════════════════════════════════════════
  // Binary protocol helpers
  // ═══════════════════════════════════════════════════════

  Future<void> _writeSentence(List<String> words) async {
    final buf = BytesBuilder();
    for (final w in words) {
      final bytes = utf8.encode(w);
      buf.add(_encodeLength(bytes.length));
      buf.add(bytes);
    }
    // sentence terminator = empty word (length 0)
    buf.add(_encodeLength(0));
    _socket!.add(buf.takeBytes());
    await _socket!.flush();
  }

  /// اقرأ sentence كامل — words حتى empty word
  Future<List<String>> _readSentence() async {
    final words = <String>[];
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final len = await _readLength(deadline);
      if (len == 0) break; // sentence terminator
      final bytes = await _readBytes(len, deadline);
      words.add(utf8.decode(bytes, allowMalformed: true));
    }
    return words;
  }

  /// Encode variable-length prefix حسب MikroTik protocol:
  /// - 0..0x7F           → 1 byte (0xxxxxxx)
  /// - 0x80..0x3FFF      → 2 bytes (10xxxxxx xxxxxxxx)
  /// - 0x4000..0x1FFFFF  → 3 bytes (110xxxxx ...)
  /// - 0x200000..0xFFFFFFF → 4 bytes (1110xxxx ...)
  /// - أكبر: 5 bytes (0xF0 ثم 4 bytes big-endian)
  Uint8List _encodeLength(int len) {
    if (len < 0x80) return Uint8List.fromList([len]);
    if (len < 0x4000) {
      final v = len | 0x8000;
      return Uint8List.fromList([(v >> 8) & 0xFF, v & 0xFF]);
    }
    if (len < 0x200000) {
      final v = len | 0xC00000;
      return Uint8List.fromList([(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
    }
    if (len < 0x10000000) {
      final v = len | 0xE0000000;
      return Uint8List.fromList([
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ]);
    }
    return Uint8List.fromList([
      0xF0,
      (len >> 24) & 0xFF,
      (len >> 16) & 0xFF,
      (len >> 8) & 0xFF,
      len & 0xFF,
    ]);
  }

  Future<int> _readLength(DateTime deadline) async {
    final b0 = await _readByte(deadline);
    if (b0 < 0x80) return b0;
    if ((b0 & 0xC0) == 0x80) {
      final b1 = await _readByte(deadline);
      return ((b0 & 0x3F) << 8) | b1;
    }
    if ((b0 & 0xE0) == 0xC0) {
      final b1 = await _readByte(deadline);
      final b2 = await _readByte(deadline);
      return ((b0 & 0x1F) << 16) | (b1 << 8) | b2;
    }
    if ((b0 & 0xF0) == 0xE0) {
      final b1 = await _readByte(deadline);
      final b2 = await _readByte(deadline);
      final b3 = await _readByte(deadline);
      return ((b0 & 0x0F) << 24) | (b1 << 16) | (b2 << 8) | b3;
    }
    // 0xF0 — 4 bytes big-endian
    final b1 = await _readByte(deadline);
    final b2 = await _readByte(deadline);
    final b3 = await _readByte(deadline);
    final b4 = await _readByte(deadline);
    return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4;
  }

  Future<int> _readByte(DateTime deadline) async {
    while (_receivedBytes.isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        throw MikrotikBinaryException('انتهت مهلة القراءة (timeout)');
      }
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    return _receivedBytes.removeAt(0);
  }

  Future<List<int>> _readBytes(int n, DateTime deadline) async {
    while (_receivedBytes.length < n) {
      if (DateTime.now().isAfter(deadline)) {
        throw MikrotikBinaryException('انتهت مهلة القراءة أثناء استلام كلمة');
      }
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    final out = _receivedBytes.sublist(0, n);
    _receivedBytes.removeRange(0, n);
    return out;
  }

  /// حوّل sentence مثل ['!re','=name=ether1','=running=true'] → {name:ether1, running:true}
  Map<String, String> _sentenceToMap(List<String> sentence) {
    final m = <String, String>{};
    for (final w in sentence) {
      if (w.startsWith('=')) {
        final rest = w.substring(1);
        final eq = rest.indexOf('=');
        if (eq > 0) {
          m[rest.substring(0, eq)] = rest.substring(eq + 1);
        }
      }
    }
    return m;
  }
}

class MikrotikBinaryException implements Exception {
  final String message;
  final String? code;
  MikrotikBinaryException(this.message, {this.code});
  @override
  String toString() => message;
}
