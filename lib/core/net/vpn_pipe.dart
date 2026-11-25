import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha1;
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

/// الخادم ردّ «مشغول» (PIPE_BUSY 429): بلغ الوكيل سقف ممرّاته المفتوحة (٢٤) — لحظيّ، يُعاد بعد قليل ([VpnPipe.connect]).
class PipeBusy implements Exception {
  const PipeBusy([this.message = '']);
  final String message;
}

/// العنوان ليس من أجهزة الوكيل ولا مشتركيه (NOT_YOURS 403) على نفق شركةٍ مشترك — فشل اتّصالٍ كغيره، ويُعرف بنوعه فلا تُجرَّب
/// بقيّة منافذ العنوان نفسه (فحص النطاق).
class PipeDenied extends SocketException {
  const PipeDenied(super.message, {super.port});
}

/// النفق نفسه لم يقم أو لا طريق (TUNNEL_FAILED، NO_VPN، CONN_VPN_OFF، PIPE_OFF) — فشل اتّصالٍ كغيره، ويُعرف بنوعه فيتباعد التطبيق
/// عن الخادم بدل الإعادة الفوريّة ([VpnPipe.backoffSteps]).
class PipeTunnelDown extends SocketException {
  const PipeTunnelDown(super.message, {super.port});
}

/// طريق الوكيل عبر الـVPN الآن: قائم ([ok] + [via]: company · own · template)، أو السبب بكلمة الخادم و[reason] (no_vpn، tunnel_failed…).
class PipeRoute {
  const PipeRoute.ok(this.via, {this.ws = false})
      : ok = true,
        message = null,
        reason = null;
  const PipeRoute.failed(this.message, {this.reason})
      : ok = false,
        via = null,
        ws = false;
  final bool ok;
  final String? via;
  final String? message;
  final String? reason;

  /// «الاتّصال الواحد» مفتوحٌ لحسابه بالخادم (pro_settings.pipe_ws) ⇒ ممرّاته على WebSocket ([WsPipeTransport]).
  final bool ws;
}

/// نداءات ممرّ الخادم (server/connVpn/pipe.js) — تُستبدل في الاختبار.
abstract class VpnPipeTransport {
  /// اتّصالٌ بالجهاز من غرفة نفق الوكيل ⇒ رقم الممرّ وزمن الاتّصال من داخل النفق (ms)، أو [SocketException] كفشل الاتّصال
  /// المباشر (رفضٌ/مهلة برمزهما).
  Future<({String id, int? ms})> open(String host, int port, Duration timeout);

  /// بايتاتٌ للجهاز ⇒ false إن أُغلق الممرّ.
  Future<bool> write(String id, Uint8List data);

  /// ما وصل من الجهاز (تنتظر ≤ [wait]) ⇒ null إن لم يعد الممرّ موجوداً؛ [PipeRetry] إن لم يُرسَل الطلب.
  Future<PipeRead?> read(String id, Duration wait);

  Future<void> close(String id);

  /// رسالة UDP بردّها (SNMP) وزمنها من داخل النفق ⇒ الردّ، أو [TimeoutException] / [SocketException].
  Future<({Uint8List data, int? ms})> udp(String host, int port, Uint8List data, Duration timeout);

  /// بنك ICMP من داخل النفق ⇒ أزمنة الردود الصحيحة (فارغة = لا ردّ)، أو [SocketException] إن تعذّر السؤال.
  Future<List<int>> ping(String host, int count, Duration timeout);

  /// طريق الوكيل الآن (يُبقي غرفة ملفّه/قالبه حيّة).
  Future<PipeRoute> route();

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

  static VpnPipeTransport _transport = WsPipeTransport(_HttpPipeTransport());
  static VpnPipeTransport get transport => _transport;

  /// ناقلٌ جديد = عالمٌ جديد (الاختبار): لا يرث تباعد سابقه.
  @visibleForTesting
  static set transport(VpnPipeTransport t) {
    _transport = t;
    resetBackoff();
  }

  /// الساعة — تُستبدل في الاختبار (التباعد و«الاتّصال الواحد»).
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  // ——— «الاتّصال الواحد» (٢٥ نوفمبر — server/connVpn/pipeWs.js؛ المالك: «اي ابدي بالاتصال الواحد») ———
  // قراءة جهازٍ كانت ٦–١٤ طلب HTTP (١٩٢ ألفاً يوم ٢٣ نوفمبر)؛ الآن WebSocket واحد لكلّ ممرّ حين يقول «الطريق» ws:true.

  /// الخادم قال ws:true بآخر «طريق» ([route]).
  static bool wsAllowed = false;
  static DateTime? _wsOffUntil;

  /// الممرّات الجديدة على WebSocket؟ — مفتوحٌ بالخادم ولم تتعذّر مصافحته قريباً.
  static bool get wsUsable {
    final u = _wsOffUntil;
    return wsAllowed && (u == null || now().isAfter(u));
  }

  static void _wsUnavailable(Duration d) => _wsOffUntil = now().add(d);

  // ——— التباعد بعد الفشل (٢٥ نوفمبر — النقطة ٣؛ المالك: «رح يتاثر الفحص؟ تقل جودته ويتاخر؟») ———
  // كان التطبيق يعيد فوراً بإيقاع قرّائه: ٢١ نوفمبر صفحةٌ ملفّها خربان ⇒ ٣٠٨٤ طلباً فاشلاً وأعلى دقيقة ٢٢٣. الآن:
  //  · النفق لم يقم ([PipeTunnelDown]) ⇒ لا سؤال للخادم حتى ٥⇒١٠⇒٢٠⇒٣٠ث (±٢٠٪)، والقرّاء تأخذ الخطأ نفسه فوراً.
  //  · منفذ جهازٍ لا يجيب (مهلة/لا طريق، أو UDP بلا ردّ) [hostFailsBeforeBackoff] مرّاتٍ متتالية ⇒ هو وحده بالفواصل نفسها — لكلّ
  //    منفذ لا للجهاز كلّه: فحصٌ واحد يجرّب منافذ عدّة (الكرت: ٨٠ ثمّ ٤٤٣ ثمّ ٨٧٢٨…) فلا يُحسب الجهاز طافياً من فحصٍ واحد. الرفض
  //    (ECONNREFUSED) جوابٌ من جهازٍ حيّ فيصفّر منافذه كلّها، والبقيّة طبيعيّة.
  //  · أيّ نجاحٍ يصفّر؛ «طريقٌ» سليم يصفّر النفق؛ [resetBackoff] لدخول الوضع وتركه؛ [urgentKey] (الفحص الشامل) يتجاوز التباعد.
  //  · والوضع سليمٌ ⇒ لا شيء يتغيّر (لا انتظار قبل أيّ محاولة).
  static const backoffSteps = [Duration(seconds: 5), Duration(seconds: 10), Duration(seconds: 20), Duration(seconds: 30)];
  static const hostFailsBeforeBackoff = 3;

  /// منطقةٌ صريحة من الوكيل (الفحص الشامل — [DeviceNet.vpn]) ⇒ تحاول فوراً مهما كان التباعد.
  static const urgentKey = #vpnPipeUrgent;
  static _Back? _tunnel;
  static final Map<String, _Back> _hosts = {};
  static final _rnd = math.Random();

  /// يصفّر التباعد كلّه (دخول «وضع VPN» وتركه، و«حاول هسه») — ومعه «تعذّرت المصافحة»: الضغطة الصريحة تجرّب الاتّصال المفتوح من جديد.
  static void resetBackoff() {
    _tunnel = null;
    _hosts.clear();
    _wsOffUntil = null;
  }

  @visibleForTesting
  static bool get tunnelBackedOff {
    final u = _tunnel?.until;
    return u != null && now().isBefore(u);
  }

  @visibleForTesting
  static bool hostBackedOff(String host, int port) {
    final u = _hosts['$host:$port']?.until;
    return u != null && now().isBefore(u);
  }

  static Duration _step(int n) {
    final b = backoffSteps[math.min(n, backoffSteps.length - 1)];
    return Duration(milliseconds: (b.inMilliseconds * (0.8 + _rnd.nextDouble() * 0.4)).round());
  }

  /// ما زال بالتباعد ⇒ الخطأ الأخير نفسه فوراً (بلا سؤال الخادم).
  static void _gate(String host, int? port) {
    if (Zone.current[urgentKey] == true) return;
    final t = now();
    final tu = _tunnel;
    if (tu != null && tu.until != null && t.isBefore(tu.until!) && tu.err != null) throw tu.err!;
    if (port == null) return;
    final h = _hosts['$host:$port'];
    if (h != null && h.until != null && t.isBefore(h.until!) && h.err != null) throw h.err!;
  }

  static const _noAnswer = {'Connection timed out', 'No route to host', 'Network is unreachable'};

  static void _noteFail(String host, int? port, Object e) {
    final t = now();
    if (e is PipeTunnelDown) {
      final b = _tunnel ??= _Back();
      b.until = t.add(_step(b.n));
      b.n += 1;
      b.err = e;
      return;
    }
    if (port == null) return;
    final noAnswer = e is TimeoutException || (e is SocketException && e is! PipeDenied && _noAnswer.contains(e.osError?.message));
    if (!noAnswer) {
      // رفضٌ أو ردٌّ آخر من الجهاز نفسه ⇒ حيّ
      if (e is SocketException && e.osError != null) _hosts.removeWhere((k, _) => k.startsWith('$host:'));
      return;
    }
    final b = _hosts.putIfAbsent('$host:$port', _Back.new);
    b.fails += 1;
    b.err = e;
    if (b.fails >= hostFailsBeforeBackoff) {
      b.until = t.add(_step(b.n));
      b.n += 1;
    }
    if (_hosts.length > 2000) _hosts.remove(_hosts.keys.first);
  }

  static void _noteOk(String host, int? port) {
    _tunnel = null;
    if (port != null) _hosts.remove('$host:$port');
  }

  /// أقصى كتابةٍ بطلبٍ واحد (base64 يكبر ٤/٣ — تحت حدّ جسم الخادم ١٠٠ ك.ب.).
  static const chunk = 48 * 1024;

  /// انتظار القراءة المعلّقة بالخادم.
  @visibleForTesting
  static Duration wait = const Duration(seconds: 15);

  /// فُتح ممرٌّ بهذه الجلسة ⇒ ترك «وضع VPN» يُطلق غرفته بالخادم.
  static bool used = false;

  /// زمن الاتّصال بالجهاز من داخل النفق لكلّ مقبسٍ فُتح عبر الممرّ — يُعرض بدل زمن الطريق إلى خادمنا (كأنّه على شبكته).
  static final Expando<int> _connectMs = Expando<int>('vpnConnectMs');

  /// آخر زمن ردٍّ UDP من داخل النفق لكلّ عنوان (فحص SNMP يقيس به).
  static final Map<String, int> _udpMs = {};

  static int? connectMsOf(Socket s) => _connectMs[s];
  static int? udpMsOf(String host) => _udpMs[host];

  // ——— طابور الممرّات (١٤ نوفمبر — المالك: «فحص الأجهزة من ينقر ع الدرع يفحص يوصل للنصّ مرّات ويفصل») ———
  //
  // الخادم يسمح للوكيل بـ٢٤ ممرّاً مفتوحاً معاً (PIPE_BUSY فوقها). «الفحص الشامل» (٦ أجهزة معاً، ٢–٤ اتّصالات لكلٍّ) مع جولة القسم
  // وبطاقاته كانت تتجاوزها بمنتصف الفحص، فيُرفض فتح الباقي ويظهر «ما قُرئ» — ٥٢ رفضاً بسجلّ الخادم يومها، كلّها على الفتح.
  // الآن: ما زاد على [maxOpen] **ينتظر دوره** (والانتظار لا يُحسب من مهلة الجهاز)، و«مشغول» من الخادم (تطبيقٌ ثانٍ للوكيل نفسه،
  // أو ممرّاتٌ لم يُغلقها الخادم بعد) يُعاد بعد لحظة بدل أن يُعدّ فشلاً.

  /// أقصى ممرّاتٍ مفتوحة من هذا التطبيق معاً — دون سقف الخادم (٢٤) بهامشٍ لتطبيقٍ ثانٍ. يُضبط بالاختبار.
  static int maxOpen = 20;

  /// أقصى انتظارٍ للدور قبل أن يُعدّ الممرّ مشغولاً فعلاً.
  static Duration queueWait = const Duration(seconds: 25);

  /// مهلات إعادة «مشغول» من الخادم (ms) — ~٦ث مجموعاً.
  static List<int> busyBackoffMs = const [300, 500, 800, 1200, 1500, 1800];

  static int _open = 0;
  static final _queue = <Completer<void>>[];

  /// ممرّاتٌ مفتوحة (أو تُفتح) الآن من هذا التطبيق.
  @visibleForTesting
  static int get openNow => _open;

  @visibleForTesting
  static void debugResetGate() {
    _open = 0;
    for (final c in _queue) {
      if (!c.isCompleted) c.completeError(const SocketException('reset'));
    }
    _queue.clear();
  }

  static Future<void> _acquire(int port) async {
    if (_open < maxOpen) {
      _open++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    try {
      // الدور يُسلَّم محجوزاً ([_release] لا يُنقص العدّاد حين يسلّمه)
      await c.future.timeout(queueWait);
    } on TimeoutException {
      _queue.remove(c);
      // سُلّم الدور لحظة انتهاء المهلة ⇒ يُعاد لغيره
      if (c.isCompleted) _release();
      throw SocketException('الممرّ مشغول — أعد المحاولة بعد لحظة', port: port);
    }
  }

  static void _release() {
    while (_queue.isNotEmpty) {
      final c = _queue.removeAt(0);
      if (!c.isCompleted) {
        c.complete(); // الدور ينتقل لمن ينتظر (العدّاد كما هو)
        return;
      }
    }
    if (_open > 0) _open--;
  }

  /// [Socket] متّصلٌ بالجهاز [host]:[port] عبر الممرّ — أو [SocketException] كالمباشر.
  static Future<Socket> connect(String host, int port, {Duration? timeout}) async {
    used = true;
    _gate(host, port);
    await _acquire(port);
    var held = true; // الدور بيدنا حتى يحمله الرابط (يُعاد عند إغلاقه)
    void free() {
      if (held) {
        held = false;
        _release();
      }
    }

    try {
      ({String id, int? ms}) o;
      for (var i = 0;; i++) {
        try {
          o = await transport.open(host, port, timeout ?? const Duration(seconds: 6));
          break;
        } on PipeBusy catch (e) {
          if (i >= busyBackoffMs.length) {
            throw SocketException(e.message.isEmpty ? 'الممرّ مشغول — أعد المحاولة بعد لحظة' : e.message, port: port);
          }
          await Future<void>.delayed(Duration(milliseconds: busyBackoffMs[i]));
        }
      }
      _noteOk(host, port);
      final id = o.id;
      try {
        final s = await _bridge(id, onClosed: free);
        if (o.ms != null) _connectMs[s] = o.ms!;
        return s;
      } catch (e) {
        unawaited(transport.close(id).catchError((Object _) {}));
        if (e is SocketException) rethrow;
        throw SocketException('تعذّر فتح الممرّ: $e', port: port);
      }
    } catch (e) {
      free();
      _noteFail(host, port, e);
      rethrow;
    }
  }

  /// رسالة UDP بردّها عبر الممرّ (SNMP).
  static Future<Uint8List> udp(String host, int port, Uint8List data, Duration timeout) async {
    used = true;
    _gate(host, port);
    final ({Uint8List data, int? ms}) r;
    try {
      r = await transport.udp(host, port, data, timeout);
    } catch (e) {
      _noteFail(host, port, e);
      rethrow;
    }
    _noteOk(host, port);
    if (r.ms != null) {
      if (_udpMs.length > 500) _udpMs.remove(_udpMs.keys.first);
      _udpMs[host] = r.ms!;
    }
    return r.data;
  }

  /// بنك ICMP عبر الممرّ (ينفّذه الخادم من داخل النفق — وعلى الآيفون أيضاً).
  static Future<List<int>> ping(String host, {int count = 1, Duration timeout = const Duration(seconds: 2)}) async {
    used = true;
    // البنك سؤالٌ رخيص يكشف عودة الجهاز ⇒ تباعد النفق وحده
    _gate(host, null);
    try {
      return await transport.ping(host, count, timeout);
    } catch (e) {
      _noteFail(host, null, e);
      rethrow;
    }
  }

  /// طريق الوكيل الآن («وضع VPN» شُغّل، وكلّ دقيقةٍ ما دام).
  static Future<PipeRoute> route() async {
    used = true;
    try {
      final r = await transport.route();
      if (r.ok) {
        _tunnel = null;
        wsAllowed = r.ws;
      }
      return r;
    } catch (_) {
      return const PipeRoute.failed('تعذّر الوصول للخادم — تأكّد من الإنترنت');
    }
  }

  /// ترك «وضع VPN» — بلا انتظار.
  static void release() {
    used = false;
    resetBackoff();
    unawaited(transport.release().catchError((Object _) {}));
  }

  /// زوجٌ محلّيّ: القارئ يأخذ طرفاً، والآخر يمرّ بالخادم. المقبول يُطابَق بمنفذ طرفنا (لا يُقبل غيره).
  static Future<Socket> _bridge(String id, {void Function()? onClosed}) async {
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
      // قبولٌ قُطع قبل أن يكتمل (القارئ أغلق فوراً) ⇒ لا خطأ سائب في المنطقة
    }, onError: (Object _) {});
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
      _Link(id, inner, transport, onClosed: onClosed).start();
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
    if (code == 'NOT_YOURS') return PipeDenied(msg.isEmpty ? 'هذا العنوان ليس من أجهزتك ولا مشتركيك' : msg, port: port);
    if (_tunnelCodes.contains(code)) return PipeTunnelDown(msg.isEmpty ? 'الـVPN ما اتّصل الآن — حاول بعد قليل' : msg, port: port);
    return SocketException(msg.isEmpty ? 'الجهاز ما ردّ عبر الـVPN' : msg, port: port);
  }

  static const _tunnelCodes = {'TUNNEL_FAILED', 'NO_VPN', 'CONN_VPN_OFF', 'PIPE_OFF'};

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
  _Link(this.id, this.inner, this.t, {this.onClosed});
  final String id;
  final Socket inner;
  final VpnPipeTransport t;

  /// يُنادى مرّةً حين ينتهي الرابط بأيّ طريق (القارئ أغلق، الجهاز أغلق، الخادم أسقطه) — يُعيد دوره في طابور الممرّات.
  final void Function()? onClosed;
  bool _freed = false;
  void _free() {
    if (_freed) return;
    _freed = true;
    onClosed?.call();
  }
  final _out = BytesBuilder(copy: false);
  bool _writing = false;
  bool _closed = false;
  bool _localDone = false;

  void start() {
    // كتابةٌ على مقبسٍ أغلقه القارئ فجأةً (RST) تُبلَّغ بـdone — تُبتلع هنا (الإغلاق يجري بمساره) فلا خطأ سائب في المنطقة
    unawaited(inner.done.catchError((Object _) {}));
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
        _free();
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
    _free();
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
  Future<({String id, int? ms})> open(String host, int port, Duration timeout) async {
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
      final data = body['data'] as Map;
      final id = '${data['id'] ?? ''}';
      final ms = data['ms'];
      if (_id.hasMatch(id)) return (id: id, ms: ms is num && ms > 0 ? ms.round() : null);
    }
    if (r.statusCode == 429 || (body is Map && body['code'] == 'PIPE_BUSY')) {
      throw PipeBusy(body is Map ? '${body['message'] ?? ''}'.trim() : '');
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
  Future<({Uint8List data, int? ms})> udp(String host, int port, Uint8List data, Duration timeout) async {
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
      final d = body['data'] as Map;
      final t = d['ms'];
      return (data: base64Decode('${d['d'] ?? ''}'), ms: t is num && t > 0 ? t.round() : null);
    }
    if (r.statusCode == 504) throw TimeoutException('SNMP عبر الـVPN: الجهاز ما ردّ', Duration(milliseconds: ms));
    throw VpnPipe.failure(body, port: port);
  }

  @override
  Future<List<int>> ping(String host, int count, Duration timeout) async {
    final ms = timeout.inMilliseconds.clamp(500, 5000);
    final Response<dynamic> r;
    try {
      r = await _post('/api/v2/conn-vpn/pipe/ping', {'ip': host, 'count': count, 'timeout_ms': ms},
          receive: Duration(milliseconds: count * (ms + 1000) + 45000));
    } on DioException catch (e) {
      throw SocketException('تعذّر الوصول للخادم (${e.type.name})');
    }
    final body = r.data;
    if (r.statusCode == 200 && body is Map && body['data'] is Map) {
      final t = (body['data'] as Map)['times'];
      return [
        if (t is List)
          for (final x in t)
            if (x is num && x > 0) x.round(),
      ];
    }
    throw VpnPipe.failure(body);
  }

  @override
  Future<PipeRoute> route() async {
    final Response<dynamic> r;
    try {
      // أوّل تشغيلٍ لملفّ الوكيل أو قالب شركته يتّصل النفق (حتى دقيقة ونصف مع المخرج)
      r = await _post('/api/v2/conn-vpn/pipe/route', const <String, dynamic>{}, receive: const Duration(seconds: 100));
    } on DioException catch (_) {
      return const PipeRoute.failed('تعذّر الوصول للخادم — تأكّد من الإنترنت');
    }
    final body = r.data;
    if (r.statusCode == 200 && body is Map && body['success'] == true && body['data'] is Map) {
      final dm = body['data'] as Map;
      return PipeRoute.ok('${dm['via'] ?? ''}', ws: dm['ws'] == true);
    }
    final m = body is Map ? body : const {};
    final code = '${m['code'] ?? ''}';
    final reason = switch (code) {
      'NO_VPN' => 'no_vpn',
      'TUNNEL_FAILED' => 'tunnel_failed',
      'CONN_VPN_OFF' || 'PIPE_OFF' => 'off',
      'PERMISSION_DENIED' => 'permission',
      _ => null,
    };
    final why = '${m['why'] ?? ''}';
    final msg = '${m['message'] ?? ''}'.trim();
    final text = why == 'cert'
        ? 'خادم الـVPN رفض شهادة ملفّك — ارفع الملفّ الجديد من صفحة VPN'
        : why == 'auth'
            ? 'خادم الـVPN رفض اليوزر أو كلمة المرور — صحّحهما من صفحة VPN'
            : (msg.isEmpty ? 'الـVPN ما اتّصل الآن — حاول بعد قليل' : msg);
    return PipeRoute.failed(text, reason: reason);
  }

  @override
  Future<void> release() async {
    await _d.post<dynamic>('/api/v2/conn-vpn/pipe/release', data: const <String, dynamic>{});
  }
}

/// حال تباعدٍ واحد (النفق أو جهاز).
class _Back {
  int fails = 0;
  int n = 0;
  DateTime? until;
  Object? err;
}

/// «الاتّصال الواحد» (٢٥ نوفمبر — server/connVpn/pipeWs.js): الممرّ على WebSocket واحد بدل طلبٍ لكلّ رزمة (كانت ٦–١٤ طلباً لكلّ قراءة
/// جهاز). العقد نفسه ([VpnPipeTransport]) فـ[_Link] وكلّ قارئ كما هم؛ UDP والبنك والطريق والترك بالطلبات العاديّة ([http]).
/// يُستعمل حين يقول «الطريق» ws:true ([VpnPipe.wsUsable])؛ تعذّرت المصافحة ⇒ الطلب العاديّ لهذا الممرّ، وإيقافٌ مؤقّت بحسب السبب:
/// 401/403 لا شيء (الطلب العاديّ يجدّد الجلسة أو يقول السبب) · 409 PIPE_WS_OFF ⇒ حتى «طريقٍ» يقول ws · 426 (وسيطٌ حذف الترقية) ٣٠ د ·
/// غيرها والشبكة ٥ د. الترويسات من معترضات [ApiClient.pipe] نفسها ([ApiClient.headersFor]).
class WsPipeTransport implements VpnPipeTransport {
  WsPipeTransport(this.http, {Uri Function()? base, Future<Map<String, String>?> Function(String path)? headers})
      : _base = base ?? (() => Uri.parse(ApiClient.baseUrl)),
        _headers = headers ?? ApiClient.headersFor;

  final VpnPipeTransport http;
  final Uri Function() _base;
  final Future<Map<String, String>?> Function(String path) _headers;
  final Map<String, _WsConn> _conns = {};

  static const path = '/api/v2/conn-vpn/pipe/ws';

  /// ممرّاتٌ مفتوحة على WebSocket الآن.
  @visibleForTesting
  int get wsOpen => _conns.length;

  @override
  Future<({String id, int? ms})> open(String host, int port, Duration timeout) async {
    if (!VpnPipe.wsUsable) return http.open(host, port, timeout);
    final ms = timeout.inMilliseconds.clamp(1000, 15000);
    final h = await _headers(path);
    if (h == null) return http.open(host, port, timeout);
    final b = _base();
    final uri = b.replace(
      scheme: b.scheme == 'https' ? 'wss' : 'ws',
      path: path,
      queryParameters: {'ip': host, 'port': '$port', 'timeout_ms': '$ms'},
    );
    final _Handshake hs;
    try {
      hs = await _wsHandshake(uri, h, const Duration(seconds: 20));
    } catch (_) {
      VpnPipe._wsUnavailable(const Duration(minutes: 5));
      return http.open(host, port, timeout);
    }
    final ws = hs.ws;
    if (ws == null) {
      if (hs.status == 409 && hs.code == 'PIPE_WS_OFF') {
        VpnPipe.wsAllowed = false;
      } else if (hs.status == 426) {
        VpnPipe._wsUnavailable(const Duration(minutes: 30));
      } else if (hs.status != 401 && hs.status != 403) {
        VpnPipe._wsUnavailable(const Duration(minutes: 5));
      }
      return http.open(host, port, timeout);
    }
    // الطريق قد يحتاج أن يتّصل النفق أوّلاً (ملفّ الوكيل أو قالب شركته) ⇒ مهلةٌ أطول من مهلة الجهاز (كالطلب العاديّ)
    final c = _WsConn(ws);
    final first = await c.first.timeout(Duration(milliseconds: ms + 45000), onTimeout: () => null);
    if (first == null || first['success'] != true || first['data'] is! Map) {
      c.dispose();
      if (first == null) throw SocketException('تعذّر فتح الممرّ — الخادم ما ردّ', port: port);
      if (first['status'] == 429 || first['code'] == 'PIPE_BUSY') throw PipeBusy('${first['message'] ?? ''}'.trim());
      throw VpnPipe.failure(first, port: port);
    }
    final data = first['data'] as Map;
    final id = '${data['id'] ?? ''}';
    if (id.isEmpty) {
      c.dispose();
      throw SocketException('تعذّر فتح الممرّ', port: port);
    }
    _conns[id] = c;
    c.onGone = () => _conns.remove(id);
    final cms = data['ms'];
    return (id: id, ms: cms is num && cms > 0 ? cms.round() : null);
  }

  @override
  Future<bool> write(String id, Uint8List data) async {
    final c = _conns[id];
    if (c == null) return http.write(id, data);
    return c.write(data);
  }

  @override
  Future<PipeRead?> read(String id, Duration wait) async {
    final c = _conns[id];
    if (c == null) return http.read(id, wait);
    return c.read(wait);
  }

  @override
  Future<void> close(String id) async {
    final c = _conns.remove(id);
    if (c == null) return http.close(id);
    c.dispose();
  }

  @override
  Future<({Uint8List data, int? ms})> udp(String host, int port, Uint8List data, Duration timeout) =>
      http.udp(host, port, data, timeout);

  @override
  Future<List<int>> ping(String host, int count, Duration timeout) => http.ping(host, count, timeout);

  @override
  Future<PipeRoute> route() => http.route();

  @override
  Future<void> release() async {
    for (final c in _conns.values.toList()) {
      c.dispose();
    }
    _conns.clear();
    await http.release();
  }
}

/// ممرٌّ واحد على WebSocket: أوّل رسالةٍ نصّيّة ردّ open، ثمّ بايتات الجهاز تُخزَّن حتى يقرأها [_Link].
class _WsConn {
  _WsConn(this.ws) {
    _sub = ws.listen(_onData, onDone: _onDone, onError: (Object _) => _onDone(), cancelOnError: true);
  }

  final WebSocket ws;
  late final StreamSubscription<dynamic> _sub;
  final _first = Completer<Map<String, dynamic>?>();
  final _buf = BytesBuilder(copy: false);
  Completer<void>? _wake;
  bool _done = false;
  bool _taken = false;
  void Function()? onGone;

  Future<Map<String, dynamic>?> get first => _first.future;

  void _onData(dynamic d) {
    if (d is String) {
      if (!_first.isCompleted) {
        Object? m;
        try {
          m = jsonDecode(d);
        } catch (_) {
          m = null;
        }
        _first.complete(m is Map<String, dynamic> ? m : null);
      }
      return;
    }
    if (d is List<int>) {
      _buf.add(d);
      _signal();
    }
  }

  void _onDone() {
    _done = true;
    if (!_first.isCompleted) _first.complete(null);
    _signal();
  }

  void _signal() {
    final w = _wake;
    _wake = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<bool> write(Uint8List data) async {
    if (_done) return false;
    try {
      ws.add(data);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ما وصل (تنتظر ≤ [wait]) ⇒ بايتاته؛ أغلق الخادم بعد آخر بايت (1000: الجهاز أغلق) ⇒ end؛ انقطاعٌ شاذّ ⇒ ما بقي ثمّ null (القارئ
  /// يُقطع كما حين يسقط الممرّ العاديّ).
  Future<PipeRead?> read(Duration wait) async {
    if (_taken) return null;
    if (_buf.isEmpty && !_done) {
      final w = _wake = Completer<void>();
      await w.future.timeout(wait, onTimeout: () {});
    }
    final data = _buf.takeBytes();
    if (_done && _buf.isEmpty) {
      final clean = ws.closeCode == 1000;
      if (clean) {
        _taken = true;
        onGone?.call();
        return PipeRead(data, true);
      }
      if (data.isEmpty) {
        _taken = true;
        onGone?.call();
        return null;
      }
    }
    return PipeRead(data, false);
  }

  void dispose() {
    _done = true;
    _signal();
    onGone?.call();
    try {
      unawaited(ws.close(1000).catchError((Object _) {}));
    } catch (_) {}
    unawaited(_sub.cancel().catchError((Object _) {}));
  }
}

/// نتيجة المصافحة: 101 ⇒ [ws]، وإلّا الحالة ورمز الجسم (409 PIPE_WS_OFF، 401…).
class _Handshake {
  const _Handshake(this.status, this.ws, this.code);
  final int status;
  final WebSocket? ws;
  final String? code;
}

const _wsGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/// مصافحة WebSocket يدويّة (WebSocket.connect لا يقول حالة الرفض ولا جسمه): طلب GET بترقية، 101 ⇒ مقبسٌ مفصول ⇒ WebSocket،
/// وغيرها ⇒ الحالة والرمز. Sec-WebSocket-Accept يُتحقَّق منه.
Future<_Handshake> _wsHandshake(Uri uri, Map<String, String> headers, Duration timeout) async {
  final key = base64.encode(List<int>.generate(16, (_) => VpnPipe._rnd.nextInt(256)));
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.openUrl('GET', uri.replace(scheme: uri.scheme == 'wss' ? 'https' : 'http')).timeout(timeout);
    req.followRedirects = false;
    const skip = {'content-type', 'content-length', 'accept-encoding', 'host', 'connection', 'upgrade'};
    headers.forEach((k, v) {
      if (!skip.contains(k.toLowerCase())) req.headers.set(k, v);
    });
    req.headers
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Key', key)
      ..set('Sec-WebSocket-Version', '13');
    final res = await req.close().timeout(timeout);
    if (res.statusCode != HttpStatus.switchingProtocols) {
      String body = '';
      try {
        body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 5));
      } catch (_) {}
      String? code;
      try {
        final m = jsonDecode(body);
        if (m is Map) code = m['code']?.toString();
      } catch (_) {}
      client.close(force: true);
      return _Handshake(res.statusCode, null, code);
    }
    final want = base64.encode(sha1.convert(utf8.encode('$key$_wsGuid')).bytes);
    if (res.headers.value('sec-websocket-accept') != want) {
      client.close(force: true);
      throw const SocketException('مصافحة الاتّصال المفتوح لا تطابق');
    }
    final socket = await res.detachSocket();
    client.close();
    return _Handshake(101, WebSocket.fromUpgradedSocket(socket, serverSide: false), null);
  } catch (_) {
    client.close(force: true);
    rethrow;
  }
}
