import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../api/api_client.dart';

/// ما يعود من قراءة الممرّ: بايتات الجهاز، و[end] = الجهاز أغلق (أو انقطع) وهذا آخرها.
class PipeRead {
  const PipeRead(this.data, this.end);
  final Uint8List data;
  final bool end;
}

/// قراءةٌ لم تُرسَل أصلاً (لا شبكة لحظتها) — تُعاد بأمان، فالخادم لم يُسلّمها شيئاً.
class PipeRetry implements Exception {
  const PipeRetry();
}

/// نداءات ممرّ الخادم (server/connVpn/pipe.js) — تُستبدل في الاختبار.
abstract class VpnPipeTransport {
  /// اتّصالٌ بالجهاز من غرفة نفق الوكيل ⇒ رقم الممرّ، أو [SocketException] كفشل الاتّصال المباشر (رفضٌ/مهلة برمزهما).
  Future<String> open(String host, int port, Duration timeout);

  /// بايتاتٌ للجهاز ⇒ false إن أُغلق الممرّ.
  Future<bool> write(String id, Uint8List data);

  /// ما وصل من الجهاز (تنتظر ≤ [wait]) ⇒ null إن لم يعد الممرّ موجوداً؛ [PipeRetry] إن لم يُرسَل الطلب.
  Future<PipeRead?> read(String id, Duration wait);

  Future<void> close(String id);

  /// رسالة UDP بردّها (SNMP) ⇒ الردّ، أو [TimeoutException] / [SocketException].
  Future<Uint8List> udp(String host, int port, Uint8List data, Duration timeout);

  /// ترك «وضع VPN»: ممرّاته وغرفته الباقية تُغلق بالخادم.
  Future<void> release();
}

/// ممرّ التطبيق عبر الـVPN (٧ نوفمبر — المالك: «انته ليش عقدتها… بمجرد نقر الوكيل ع وضع vpn كل الفحصوات تمر من vpn»).
///
/// «وضع VPN» بقسم الأجهزة: قرّاء التطبيق نفسها — مايكروتك (API، الويب، SSH)، يوبيكويتي، سسكو (SSH/Telnet)، وكلّ SNMP (ميموزا
/// وروجي والأولت) — تصل أجهزة شبكة الوكيل عبر خادمنا وغرفة نفقه. [connect] يعيد [Socket] حقيقيّاً: طرفه الآخر محلّيٌّ على الموبايل
/// يمرّر البايتات بطلبات HTTP (كتابةٌ، وقراءةٌ تنتظر حتى تصل بايتات) — فلا يتغيّر قارئٌ إلّا سطر فتح اتّصاله ([DeviceNet]).
class VpnPipe {
  VpnPipe._();

  @visibleForTesting
  static VpnPipeTransport transport = _HttpPipeTransport();

  /// أقصى كتابةٍ بطلبٍ واحد (base64 يكبر ٤/٣ — تحت حدّ جسم الخادم ١٠٠ ك.ب.).
  static const chunk = 48 * 1024;

  /// انتظار القراءة المعلّقة بالخادم.
  @visibleForTesting
  static Duration wait = const Duration(seconds: 15);

  /// فُتح ممرٌّ بهذه الجلسة ⇒ ترك «وضع VPN» يُطلق غرفته بالخادم.
  static bool used = false;

  /// [Socket] متّصلٌ بالجهاز [host]:[port] عبر الممرّ — أو [SocketException] كالمباشر.
  static Future<Socket> connect(String host, int port, {Duration? timeout}) async {
    used = true;
    final id = await transport.open(host, port, timeout ?? const Duration(seconds: 6));
    try {
      return await _bridge(id);
    } catch (e) {
      unawaited(transport.close(id).catchError((Object _) {}));
      if (e is SocketException) rethrow;
      throw SocketException('تعذّر فتح الممرّ: $e', port: port);
    }
  }

  /// رسالة UDP بردّها عبر الممرّ (SNMP).
  static Future<Uint8List> udp(String host, int port, Uint8List data, Duration timeout) {
    used = true;
    return transport.udp(host, port, data, timeout);
  }

  /// ترك «وضع VPN» — بلا انتظار.
  static void release() {
    used = false;
    unawaited(transport.release().catchError((Object _) {}));
  }

  /// زوجٌ محلّيّ: القارئ يأخذ طرفاً، والآخر يمرّ بالخادم. المقبول يُطابَق بمنفذ طرفنا (لا يُقبل غيره).
  static Future<Socket> _bridge(String id) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final got = Completer<Socket>();
    int? want;
    final early = <Socket>[];
    final sub = server.listen((s) {
      if (want == null) {
        early.add(s);
      } else if (s.remotePort == want && !got.isCompleted) {
        got.complete(s);
      } else {
        s.destroy();
      }
    });
    try {
      final client = await Socket.connect(InternetAddress.loopbackIPv4, server.port, timeout: const Duration(seconds: 5));
      want = client.port;
      for (final s in early) {
        if (s.remotePort == want && !got.isCompleted) {
          got.complete(s);
        } else {
          s.destroy();
        }
      }
      final Socket inner;
      try {
        inner = await got.future.timeout(const Duration(seconds: 5));
      } catch (_) {
        client.destroy();
        rethrow;
      }
      try {
        client.setOption(SocketOption.tcpNoDelay, true);
        inner.setOption(SocketOption.tcpNoDelay, true);
      } catch (_) {/* اختياريّ */}
      _Link(id, inner, transport).start();
      return client;
    } finally {
      await sub.cancel();
      await server.close();
    }
  }

  /// ردّ الخادم المرفوض ⇒ [SocketException] كفشل الاتّصال المباشر: رفض الجهاز ومهلته برمزيهما (القارئ يجرّب طريقه التالي كما
  /// على شبكته)، وغيرهما (لا VPN، ليس من أجهزتك، النفق لم يقم) بكلمة الخادم.
  @visibleForTesting
  static SocketException failure(Object? body, {int? port}) {
    final m = body is Map ? body : const {};
    final code = '${m['code'] ?? ''}';
    final err = '${m['error'] ?? ''}'.toUpperCase();
    if (code == 'CONNECT_FAILED' && _errno.containsKey(err)) {
      final msg = _errText[err]!;
      return SocketException(msg, osError: OSError(msg, _errnoOf(err)), port: port);
    }
    final msg = '${m['message'] ?? ''}'.trim();
    return SocketException(msg.isEmpty ? 'الجهاز ما ردّ عبر الـVPN' : msg, port: port);
  }

  static const _errno = {
    // ماك/آيفون · ويندوز · أندرويد/لينكس
    'ECONNREFUSED': (61, 10061, 111),
    'ETIMEDOUT': (60, 10060, 110),
    'EHOSTUNREACH': (65, 10065, 113),
    'ENETUNREACH': (51, 10051, 101),
    'ECONNRESET': (54, 10054, 104),
  };
  static const _errText = {
    'ECONNREFUSED': 'Connection refused',
    'ETIMEDOUT': 'Connection timed out',
    'EHOSTUNREACH': 'No route to host',
    'ENETUNREACH': 'Network is unreachable',
    'ECONNRESET': 'Connection reset by peer',
  };
  static int _errnoOf(String e) {
    final c = _errno[e]!;
    if (Platform.isIOS || Platform.isMacOS) return c.$1;
    if (Platform.isWindows) return c.$2;
    return c.$3;
  }
}

/// طرفٌ محلّيّ ⇄ ممرّ الخادم: ما يكتبه القارئ يُرسل بالترتيب (طلبٌ بعد طلب)، وقراءةٌ معلّقة دائماً تأتي بما يرسله الجهاز.
class _Link {
  _Link(this.id, this.inner, this.t);
  final String id;
  final Socket inner;
  final VpnPipeTransport t;
  final _out = BytesBuilder(copy: false);
  bool _writing = false;
  bool _closed = false;
  bool _localDone = false;

  void start() {
    inner.listen(
      (d) {
        _out.add(d);
        unawaited(_pump());
      },
      onDone: () {
        _localDone = true;
        unawaited(_pump());
      },
      onError: (Object _) => _shutdown(),
      cancelOnError: true,
    );
    unawaited(_readLoop());
  }

  Future<void> _pump() async {
    if (_writing || _closed) return;
    _writing = true;
    try {
      while (!_closed && _out.isNotEmpty) {
        final all = _out.takeBytes();
        for (var i = 0; i < all.length && !_closed; i += VpnPipe.chunk) {
          final ok = await t.write(id, Uint8List.sublistView(all, i, math.min(all.length, i + VpnPipe.chunk)));
          if (!ok) {
            _shutdown();
            return;
          }
        }
      }
      // القارئ أغلق طرفه (انتهى) ⇒ الممرّ يُغلق بالخادم
      if (_localDone && !_closed) _shutdown();
    } catch (_) {
      _shutdown();
    } finally {
      _writing = false;
    }
  }

  Future<void> _readLoop() async {
    var retries = 0;
    while (!_closed) {
      PipeRead? r;
      try {
        r = await t.read(id, VpnPipe.wait);
        retries = 0;
      } on PipeRetry {
        if (++retries > 3) {
          _shutdown();
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      } catch (_) {
        _shutdown();
        return;
      }
      if (_closed) return;
      if (r == null) {
        // الممرّ لم يعد بالخادم (أُغلق أو أُعيد تشغيله)
        _shutdown(notify: false);
        return;
      }
      if (r.data.isNotEmpty) {
        try {
          inner.add(r.data);
        } catch (_) {
          _shutdown();
          return;
        }
      }
      if (r.end) {
        // الجهاز أغلق ⇒ نهاية القراءة عند القارئ بعد آخر بايت
        _closed = true;
        try {
          await inner.flush();
          await inner.close();
        } catch (_) {}
        Timer(const Duration(seconds: 10), inner.destroy);
        return;
      }
    }
  }

  void _shutdown({bool notify = true}) {
    if (_closed) return;
    _closed = true;
    try {
      inner.destroy();
    } catch (_) {}
    if (notify) unawaited(t.close(id).catchError((Object _) {}));
  }
}

class _HttpPipeTransport implements VpnPipeTransport {
  Dio get _d => ApiClient.pipe;
  static final _id = RegExp(r'^[0-9a-f]{24}$');

  Future<Response<dynamic>> _post(String path, Object data, {Duration? receive, ResponseType? type}) async {
    try {
      return await _d.post<dynamic>(path, data: data, options: Options(receiveTimeout: receive, responseType: type));
    } on DioException catch (e) {
      final resp = e.response;
      if (resp != null) return resp;
      rethrow;
    }
  }

  static bool _notSent(DioException e) =>
      e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout;

  @override
  Future<String> open(String host, int port, Duration timeout) async {
    final ms = timeout.inMilliseconds.clamp(1000, 15000);
    final Response<dynamic> r;
    try {
      // الطريق قد يحتاج أن يتّصل النفق أوّلاً (ملفّ الوكيل أو قالب شركته) ⇒ مهلةٌ أطول من مهلة الجهاز
      r = await _post('/api/v2/conn-vpn/pipe/open', {'ip': host, 'port': port, 'timeout_ms': ms},
          receive: Duration(milliseconds: ms + 45000));
    } on DioException catch (e) {
      throw SocketException('تعذّر الوصول للخادم (${e.type.name})', port: port);
    }
    final body = r.data;
    if (r.statusCode == 200 && body is Map && body['success'] == true && body['data'] is Map) {
      final id = '${(body['data'] as Map)['id'] ?? ''}';
      if (_id.hasMatch(id)) return id;
    }
    throw VpnPipe.failure(body, port: port);
  }

  @override
  Future<bool> write(String id, Uint8List data) async {
    try {
      final r = await _post('/api/v2/conn-vpn/pipe/$id/w', {'d': base64Encode(data)});
      return r.statusCode == 200;
    } catch (_) {
      // لا إعادة: كتابةٌ وصلت وضاع ردّها تُكرّر البايتات فتفسد الجلسة
      return false;
    }
  }

  @override
  Future<PipeRead?> read(String id, Duration wait) async {
    final Response<dynamic> r;
    try {
      r = await _post('/api/v2/conn-vpn/pipe/$id/r', {'wait_ms': wait.inMilliseconds},
          receive: wait + const Duration(seconds: 20), type: ResponseType.bytes);
    } on DioException catch (e) {
      // لم يُرسَل (لا شبكة لحظتها) ⇒ تُعاد بأمان؛ ضاع ردٌّ أُرسل ⇒ قد ضاعت بايتات ⇒ يُغلق
      if (_notSent(e)) throw const PipeRetry();
      rethrow;
    }
    if (r.statusCode != 200) return null;
    final raw = r.data;
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw is List<int> ? raw : const <int>[]);
    final end = (r.headers.value('x-pipe-end') ?? '0') != '0';
    return PipeRead(bytes, end);
  }

  @override
  Future<void> close(String id) async {
    try {
      await _d.post<dynamic>('/api/v2/conn-vpn/pipe/$id/close', data: const <String, dynamic>{});
    } catch (_) {/* الخادم يُغلقه بالخمول */}
  }

  @override
  Future<Uint8List> udp(String host, int port, Uint8List data, Duration timeout) async {
    final ms = timeout.inMilliseconds.clamp(300, 15000);
    final Response<dynamic> r;
    try {
      r = await _post('/api/v2/conn-vpn/pipe/udp', {'ip': host, 'port': port, 'd': base64Encode(data), 'timeout_ms': ms},
          receive: Duration(milliseconds: ms + 45000));
    } on DioException catch (e) {
      throw SocketException('تعذّر الوصول للخادم (${e.type.name})', port: port);
    }
    final body = r.data;
    if (r.statusCode == 200 && body is Map && body['data'] is Map) {
      return base64Decode('${(body['data'] as Map)['d'] ?? ''}');
    }
    if (r.statusCode == 504) throw TimeoutException('SNMP عبر الـVPN: الجهاز ما ردّ', Duration(milliseconds: ms));
    throw VpnPipe.failure(body, port: port);
  }

  @override
  Future<void> release() async {
    await _d.post<dynamic>('/api/v2/conn-vpn/pipe/release', data: const <String, dynamic>{});
  }
}
